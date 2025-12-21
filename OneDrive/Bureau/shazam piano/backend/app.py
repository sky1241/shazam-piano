"""
ShazaPiano Backend - FastAPI Application
Main entry point with routes
"""
import asyncio
import shutil
from pathlib import Path
from typing import List, Optional
from datetime import datetime

from fastapi import FastAPI, UploadFile, File, HTTPException, Query, Form, Header, Depends
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from loguru import logger

from config import settings, init_directories, get_level_config, ERROR_MESSAGES
from inference import process_audio_to_midi
from arranger import arrange_level
from render import render_level_video
from identify import identify_audio
from separation import separate_melody
from firebase_client import (
    init_firebase,
    verify_firebase_token,
    save_job_for_user,
    save_practice_session,
)
import pretty_midi

# ============================================
# App Setup
# ============================================

app = FastAPI(
    title="ShazaPiano API",
    description="Generate 4-level piano videos from audio recordings",
    version="1.0.0",
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # TODO: Restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Static files
init_directories()
app.mount("/media", StaticFiles(directory=str(settings.MEDIA_DIR)), name="media")


# ============================================
# Models
# ============================================

class LevelResult(BaseModel):
    """Result for one difficulty level"""
    level: int
    name: str
    preview_url: str
    video_url: str
    midi_url: str
    key_guess: Optional[str] = None
    tempo_guess: Optional[int] = None
    duration_sec: Optional[float] = None
    status: str = "success"
    error: Optional[str] = None


class ProcessResponse(BaseModel):
    """Response for /process endpoint"""
    job_id: str
    timestamp: str
    levels: List[LevelResult]
    identified_title: Optional[str] = None
    identified_artist: Optional[str] = None
    identified_album: Optional[str] = None


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    timestamp: str
    version: str


class PracticeSession(BaseModel):
    """Payload to store a practice session result"""
    job_id: str
    level: int
    score: float
    accuracy: float | None = None
    timing_ms: float | None = None
    combo: int | None = None
    notes_total: int | None = None
    notes_correct: int | None = None
    notes_missed: int | None = None
    notes_wrong: int | None = None
    started_at: str | None = None
    ended_at: str | None = None
    device: str | None = None
    app_version: str | None = None


# ============================================
# Auth Helpers
# ============================================

def get_current_user(authorization: str = Header(None)):
    """Validate Firebase ID token from Authorization header and return claims."""
    if settings.DEBUG_AUTH_BYPASS:
        return {"uid": "debug-user"}
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing Authorization Bearer token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        decoded = verify_firebase_token(token)
        return decoded
    except HTTPException:
        raise
    except Exception as e:
        logger.warning(f"Token verification failed: {e}")
        raise HTTPException(status_code=401, detail="Invalid token")


# ============================================
# Routes
# ============================================

@app.get("/", response_model=HealthResponse)
async def root():
    """Root endpoint"""
    return HealthResponse(
        status="ok",
        timestamp=datetime.utcnow().isoformat(),
        version="1.0.0"
    )


@app.get("/health", response_model=HealthResponse)
async def health():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.utcnow().isoformat(),
        version="1.0.0"
    )


@app.post("/process", response_model=ProcessResponse)
async def process_audio(
    audio: UploadFile = File(...),
    with_audio: bool = Query(False, description="Include synthesized audio in video"),
    levels: Optional[str] = Form("1,2,3,4"),
    user=Depends(get_current_user),
):
    """
    Process audio and generate piano videos for specified levels.
    
    - **audio**: Audio file (m4a, wav, mp3) - max 10MB, ~8s recommended
    - **with_audio**: Include synthesized piano audio in output videos
    - **levels**: Which levels to generate (default: all 4)
    
    Returns URLs for preview (16s) and full videos for each level.
    """
    
    user_id = user.get("uid") if isinstance(user, dict) else None
    if not user_id:
        raise HTTPException(status_code=401, detail="Unauthenticated user")

    # Validate file size
    file_size = 0
    chunk_size = 1024 * 1024  # 1MB
    max_size = settings.MAX_UPLOAD_SIZE_MB * chunk_size
    
    # Parse requested levels
    try:
        requested_levels = [int(l.strip()) for l in levels.split(",")]
        if not all(1 <= l <= 4 for l in requested_levels):
            raise ValueError
    except:
        raise HTTPException(status_code=400, detail=ERROR_MESSAGES["invalid_level"])
    
    # Generate unique job ID
    job_id = f"{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}_{id(audio)}"
    
    # Save uploaded file
    input_path = settings.INPUT_DIR / f"{job_id}_input{Path(audio.filename).suffix}"
    
    try:
        with input_path.open("wb") as f:
            while chunk := await audio.read(chunk_size):
                file_size += len(chunk)
                if file_size > max_size:
                    input_path.unlink(missing_ok=True)
                    raise HTTPException(
                        status_code=413,
                        detail=ERROR_MESSAGES["too_large"]
                    )
                f.write(chunk)
        
        logger.info(f"Received file: {input_path.name} ({file_size / 1024 / 1024:.2f} MB)")
        
        # Process audio and generate videos
        results = []
        identified = None
        
        try:
            # Optional: identify track via ACRCloud
            logger.info("Attempting to identify audio track...")
            try:
                identified = identify_audio(input_path)
                if identified:
                    logger.success(f"✓ Identified track: title='{identified.get('title')}', artist='{identified.get('artist')}'")
                else:
                    logger.warning("Could not identify track")
            except Exception as id_error:
                logger.warning(f"Identification failed (non-fatal): {id_error}")
                identified = None

            # Optional: separate melody to help detection
            logger.info("Attempting melody separation...")
            try:
                separated_path = separate_melody(input_path)
                if separated_path:
                    logger.success(f"✓ Separated melody: {separated_path.name}")
                    midi_source = separated_path
                else:
                    logger.info("No separation applied, using original audio")
                    midi_source = input_path
            except Exception as sep_error:
                logger.warning(f"Separation failed (non-fatal): {sep_error}")
                midi_source = input_path

            # Step 1: Extract MIDI from audio
            logger.info("=" * 60)
            logger.info("STARTING MIDI EXTRACTION")
            logger.info("=" * 60)
            logger.info(f"Input audio: {midi_source.name}")
            
            try:
                midi_path = settings.OUTPUT_DIR / f"{job_id}_raw.mid"
                logger.info(f"Calling process_audio_to_midi()...")
                logger.info(f"  audio_path: {midi_source}")
                logger.info(f"  output_path: {midi_path}")
                
                base_midi, metadata = process_audio_to_midi(
                    audio_path=midi_source,
                    output_path=midi_path,
                    clean=False
                )
                
                key_guess = metadata.get("key", "C")
                tempo_guess = metadata.get("tempo", 120)
                num_notes = metadata.get("num_notes", 0)
                
                logger.success(f"=" * 60)
                logger.success(f"✅ MIDI EXTRACTION COMPLETE")
                logger.success(f"=" * 60)
                logger.success(f"Extracted: {num_notes} notes")
                logger.success(f"Key: {key_guess}, Tempo: {tempo_guess} BPM")
                logger.success(f"Duration: {metadata.get('duration', 0):.2f}s")
                logger.success(f"Saved to: {midi_path.name}")
                
            except Exception as midi_error:
                logger.error("=" * 60)
                logger.error(f"❌ MIDI EXTRACTION FAILED")
                logger.error("=" * 60)
                logger.error(f"Error: {type(midi_error).__name__}: {midi_error}")
                import traceback
                logger.error(f"Traceback:\n{traceback.format_exc()}")
                raise
            
            # Step 2: Generate videos for each requested level (parallel processing possible)
            for level in requested_levels:
                try:
                    level_config = get_level_config(level)
                    logger.info(f"Step 2.{level}: Processing Level {level} - {level_config['name']}")
                    
                    # Arrange MIDI for this level
                    arranged_midi = arrange_level(
                        midi=base_midi,
                        level=level,
                        key=key_guess,
                        tempo=tempo_guess
                    )
                    
                    # Render video
                    full_video, preview_video, audio_file = render_level_video(
                        midi=arranged_midi,
                        level=level,
                        level_name=level_config["name"],
                        output_dir=settings.OUTPUT_DIR,
                        job_id=job_id,
                        with_audio=with_audio
                    )
                    
                    # Build result
                    base = settings.BASE_URL.rstrip("/")
                    results.append(
                        LevelResult(
                            level=level,
                            name=level_config["name"],
                            preview_url=f"{base}/media/out/{preview_video.name}",
                            video_url=f"{base}/media/out/{full_video.name}",
                            midi_url=f"{base}/media/out/{job_id}_L{level}.mid",
                            key_guess=key_guess,
                            tempo_guess=tempo_guess,
                            duration_sec=arranged_midi.get_end_time(),
                            status="success"
                        )
                    )
                    
                    logger.success(f"✅ Level {level} completed!")
                    
                except Exception as level_error:
                    logger.error(f"Level {level} failed: {level_error}")
                    results.append(
                        LevelResult(
                            level=level,
                            name=level_config["name"],
                            preview_url="",
                            video_url="",
                            midi_url="",
                            status="error",
                            error=str(level_error)
                        )
                    )
            
            logger.success(f"🎉 Job {job_id} completed! {len([r for r in results if r.status == 'success'])}/{len(requested_levels)} levels successful")
            
        except Exception as e:
            logger.error(f"Processing failed: {e}")
            # Return error results for all levels
            for level in requested_levels:
                level_config = get_level_config(level)
                results.append(
                    LevelResult(
                        level=level,
                        name=level_config["name"],
                        preview_url="",
                        video_url="",
                        midi_url="",
                        status="error",
                        error=str(e)
                    )
                )
        
        response = ProcessResponse(
            job_id=job_id,
            timestamp=datetime.utcnow().isoformat(),
            levels=results,
            identified_title=identified.get("title") if identified else None,
            identified_artist=identified.get("artist") if identified else None,
            identified_album=identified.get("album") if identified else None,
        )

        # Persist job metadata to Firestore
        try:
            levels_payload = [r.model_dump() for r in results]
            payload = {
                "jobId": job_id,
                "createdAt": datetime.utcnow().isoformat(),
                "identifiedTitle": identified.get("title") if identified else None,
                "identifiedArtist": identified.get("artist") if identified else None,
                "identifiedAlbum": identified.get("album") if identified else None,
                "withAudio": with_audio,
                "levels": levels_payload,
                "inputFilename": input_path.name,
            }
            save_job_for_user(user_id, job_id, payload)
        except Exception as save_error:
            logger.warning(f"Failed to persist job to Firestore: {save_error}")

        return response
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Processing error: {e}")
        if input_path.exists():
            input_path.unlink()
        raise HTTPException(
            status_code=500,
            detail=ERROR_MESSAGES["processing_failed"]
        )


@app.delete("/cleanup/{job_id}")
async def cleanup_job(job_id: str):
    """Delete all files associated with a job ID"""
    try:
        deleted = []
        
        # Delete input files
        for file in settings.INPUT_DIR.glob(f"{job_id}*"):
            file.unlink()
            deleted.append(str(file.name))
        
        # Delete output files
        for file in settings.OUTPUT_DIR.glob(f"{job_id}*"):
            file.unlink()
            deleted.append(str(file.name))
        
        return {"status": "ok", "deleted": deleted}
    
    except Exception as e:
        logger.error(f"Cleanup error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# ============================================
# Startup & Shutdown
# ============================================

@app.on_event("startup")
async def startup_event():
    """Initialize on startup"""
    logger.info("🚀 ShazaPiano Backend starting...")
    init_directories()
    init_firebase(settings.FIREBASE_CREDENTIALS)
    logger.info(f"📁 Media directory: {settings.MEDIA_DIR}")
    logger.info(f"🎵 Ready to process on http://{settings.HOST}:{settings.PORT}")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("👋 ShazaPiano Backend shutting down...")


# ============================================
# Practice endpoints
# ============================================


@app.post("/practice/session")
async def save_practice(
    payload: PracticeSession,
    user=Depends(get_current_user),
):
    """Store a practice session result for the authenticated user."""
    user_id = user.get("uid") if isinstance(user, dict) else None
    if not user_id:
        raise HTTPException(status_code=401, detail="Unauthenticated user")

    session_id = payload.started_at or datetime.utcnow().isoformat()
    data = payload.model_dump()
    data["userId"] = user_id
    try:
        save_practice_session(user_id, session_id, data)
    except Exception as e:
        logger.warning(f"Failed to persist practice session: {e}")
        raise HTTPException(status_code=500, detail="Failed to save practice session")

    return {"status": "ok", "session_id": session_id}


@app.get("/practice/notes/{job_id}/{level}")
async def get_practice_notes(
    job_id: str,
    level: int,
    user=Depends(get_current_user),
):
    """Return note list (pitch,start,end) for a rendered MIDI level."""
    user_id = user.get("uid") if isinstance(user, dict) else None
    if not user_id:
        raise HTTPException(status_code=401, detail="Unauthenticated user")

    midi_path = settings.OUTPUT_DIR / f"{job_id}_L{level}.mid"
    if not midi_path.exists():
        raise HTTPException(status_code=404, detail="MIDI not found for this level")

    try:
        pm = pretty_midi.PrettyMIDI(str(midi_path))
        notes = []
        for inst in pm.instruments:
            for n in inst.notes:
                notes.append(
                    {
                        "pitch": int(n.pitch),
                        "start": float(n.start),
                        "end": float(n.end),
                    }
                )
        # Sort by start time
        notes.sort(key=lambda x: x["start"])
        return {"job_id": job_id, "level": level, "notes": notes}
    except Exception as e:
        logger.error(f"Failed to read MIDI for notes: {e}")
        raise HTTPException(status_code=500, detail="Failed to load notes")


# ============================================
# Main
# ============================================

if __name__ == "__main__":
    import uvicorn
    
    uvicorn.run(
        "app:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )
