"""
ShazaPiano Backend - FastAPI Application
Main entry point with routes
"""
import asyncio
import shutil
import time
import uuid
from pathlib import Path
from typing import List, Optional, Dict
from datetime import datetime, timedelta

from fastapi import FastAPI, UploadFile, File, HTTPException, Form, Header, Depends
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
    firebase_app,
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


class JobProgressResponse(BaseModel):
    """Response for job progress endpoints"""
    job_id: str
    timestamp: str
    status: str
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
# Job Store (in-memory)
# ============================================

jobs_store: Dict[str, dict] = {}
jobs_lock = asyncio.Lock()


# ============================================
# Auth Helpers
# ============================================

def get_current_user(authorization: str = Header(None)):
    """Validate Firebase ID token from Authorization header and return claims."""
    # In dev without Firebase configured, allow a debug user to pass through.
    if firebase_app is None and settings.DEBUG:
        logger.warning("Firebase not initialized; bypassing auth for dev.")
        return {"uid": "debug-user"}
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
# Job Helpers
# ============================================

def _now_iso() -> str:
    return datetime.utcnow().isoformat()


def _new_job_id() -> str:
    return f"{int(time.time())}_{uuid.uuid4().hex}"


def _parse_levels(levels: Optional[str]) -> List[int]:
    raw = levels or "1,2,3,4"
    try:
        parsed = [int(l.strip()) for l in raw.split(",") if l.strip()]
        if not parsed or not all(1 <= l <= 4 for l in parsed):
            raise ValueError
        return parsed
    except Exception:
        raise HTTPException(status_code=400, detail=ERROR_MESSAGES["invalid_level"])


def _build_level_payload(level: int, status: str = "queued") -> dict:
    level_config = get_level_config(level)
    return {
        "level": level,
        "name": level_config["name"],
        "preview_url": "",
        "video_url": "",
        "midi_url": "",
        "key_guess": None,
        "tempo_guess": None,
        "duration_sec": None,
        "status": status,
        "error": None,
    }


def _build_job_response(job: dict) -> JobProgressResponse:
    identified = job.get("identified") or {}
    levels = [LevelResult(**level) for level in job.get("levels", [])]
    return JobProgressResponse(
        job_id=job["job_id"],
        timestamp=_now_iso(),
        status=job["status"],
        levels=levels,
        identified_title=identified.get("title"),
        identified_artist=identified.get("artist"),
        identified_album=identified.get("album"),
    )


def _parse_iso(ts: Optional[str]) -> Optional[datetime]:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts)
    except ValueError:
        return None


async def _cleanup_jobs(max_age_minutes: int = 30) -> None:
    cutoff = datetime.utcnow() - timedelta(minutes=max_age_minutes)
    async with jobs_lock:
        to_remove = []
        for job_id, job in jobs_store.items():
            status = job.get("status")
            if status not in {"complete", "error"}:
                continue
            updated = _parse_iso(job.get("updated_at")) or _parse_iso(
                job.get("created_at")
            )
            if updated and updated < cutoff:
                to_remove.append(job_id)
        for job_id in to_remove:
            jobs_store.pop(job_id, None)


async def _update_job_level(job_id: str, level: int, updates: dict) -> None:
    async with jobs_lock:
        job = jobs_store.get(job_id)
        if not job:
            return
        for entry in job.get("levels", []):
            if entry.get("level") == level:
                entry.update(updates)
                job["updated_at"] = _now_iso()
                return


async def _mark_job_error(job_id: str, levels: List[int], message: str) -> None:
    async with jobs_lock:
        job = jobs_store.get(job_id)
        if not job:
            return
        job["status"] = "error"
        job["updated_at"] = _now_iso()
        for entry in job.get("levels", []):
            if entry.get("level") in levels:
                entry.update(
                    {
                        "status": "error",
                        "error": message,
                        "preview_url": "",
                        "video_url": "",
                        "midi_url": "",
                    }
                )


async def _run_job_generation(
    job_id: str,
    requested_levels: List[int],
    with_audio: bool,
) -> None:
    async with jobs_lock:
        job = jobs_store.get(job_id)
        if not job:
            return
        job["status"] = "running"
        job["updated_at"] = _now_iso()
        input_path = Path(job["input_path"])

    if not input_path.exists():
        await _mark_job_error(job_id, requested_levels, "Input audio missing")
        return

    try:
        logger.info("Attempting melody separation...")
        try:
            separated_path = await asyncio.to_thread(separate_melody, input_path)
            if separated_path:
                logger.success(f"V Separated melody: {separated_path.name}")
                midi_source = separated_path
            else:
                logger.info("No separation applied, using original audio")
                midi_source = input_path
        except Exception as sep_error:
            logger.warning(f"Separation failed (non-fatal): {sep_error}")
            midi_source = input_path

        logger.info("=" * 60)
        logger.info("STARTING MIDI EXTRACTION (JOB)")
        logger.info("=" * 60)
        midi_path = settings.OUTPUT_DIR / f"{job_id}_raw.mid"
        try:
            base_midi, metadata = await asyncio.to_thread(
                process_audio_to_midi,
                audio_path=midi_source,
                output_path=midi_path,
                clean=False,
            )
        except Exception as midi_error:
            logger.error(f"MIDI extraction failed for job {job_id}: {midi_error}")
            await _mark_job_error(job_id, requested_levels, str(midi_error))
            return

        key_guess = metadata.get("key", "C")
        tempo_guess = metadata.get("tempo", 120)

        for level in requested_levels:
            await _update_job_level(job_id, level, {"status": "processing"})
            try:
                level_config = get_level_config(level)
                arranged_midi = await asyncio.to_thread(
                    arrange_level,
                    midi=base_midi,
                    level=level,
                    key=key_guess,
                    tempo=tempo_guess,
                )
                full_video, preview_video, _ = await asyncio.to_thread(
                    render_level_video,
                    midi=arranged_midi,
                    level=level,
                    level_name=level_config["name"],
                    output_dir=settings.OUTPUT_DIR,
                    job_id=job_id,
                    with_audio=with_audio,
                )
                base = settings.BASE_URL.rstrip("/")
                await _update_job_level(
                    job_id,
                    level,
                    {
                        "status": "success",
                        "preview_url": f"{base}/media/out/{preview_video.name}",
                        "video_url": f"{base}/media/out/{full_video.name}",
                        "midi_url": f"{base}/media/out/{job_id}_L{level}.mid",
                        "key_guess": key_guess,
                        "tempo_guess": tempo_guess,
                        "duration_sec": arranged_midi.get_end_time(),
                        "error": None,
                    },
                )
                logger.success(f"V Job {job_id} level {level} completed")
            except Exception as level_error:
                logger.error(
                    f"Job {job_id} level {level} failed: {level_error}"
                )
                await _update_job_level(
                    job_id,
                    level,
                    {
                        "status": "error",
                        "preview_url": "",
                        "video_url": "",
                        "midi_url": "",
                        "error": f"{type(level_error).__name__}: {level_error}",
                    },
                )

        async with jobs_lock:
            job = jobs_store.get(job_id)
            if job:
                job["status"] = "complete"
                job["updated_at"] = _now_iso()
        logger.success(f"Job {job_id} completed")
    except Exception as fatal_error:
        logger.error(f"Job {job_id} fatal error: {fatal_error}")
        await _mark_job_error(job_id, requested_levels, str(fatal_error))
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
    with_audio: bool = Form(False, description="Include synthesized audio in video"),
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
    job_id = _new_job_id()
    
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
                    import traceback
                    logger.error(f"Level {level} failed: {level_error}")
                    logger.error(f"Traceback:\n{traceback.format_exc()}")
                    error_message = f"{type(level_error).__name__}: {level_error}"
                    results.append(
                        LevelResult(
                            level=level,
                            name=level_config["name"],
                            preview_url="",
                            video_url="",
                            midi_url="",
                            status="error",
                            error=error_message
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


@app.post("/jobs", response_model=JobProgressResponse)
async def create_job(
    audio: UploadFile = File(...),
    with_audio: bool = Form(False, description="Include synthesized audio in video"),
    levels: Optional[str] = Form("1,2,3,4"),
    user=Depends(get_current_user),
):
    """
    Create a job, upload audio, and run only identification.
    """
    user_id = user.get("uid") if isinstance(user, dict) else None
    if not user_id:
        raise HTTPException(status_code=401, detail="Unauthenticated user")

    requested_levels = _parse_levels(levels)
    await _cleanup_jobs()

    file_size = 0
    chunk_size = 1024 * 1024
    max_size = settings.MAX_UPLOAD_SIZE_MB * chunk_size

    job_id = _new_job_id()
    input_path = settings.INPUT_DIR / f"{job_id}_input{Path(audio.filename).suffix}"

    try:
        with input_path.open("wb") as f:
            while chunk := await audio.read(chunk_size):
                file_size += len(chunk)
                if file_size > max_size:
                    input_path.unlink(missing_ok=True)
                    raise HTTPException(
                        status_code=413,
                        detail=ERROR_MESSAGES["too_large"],
                    )
                f.write(chunk)

        logger.info(
            f"Job {job_id} received file {input_path.name} "
            f"({file_size / 1024 / 1024:.2f} MB)"
        )

        identified = None
        try:
            logger.info(f"Attempting to identify audio track for job {job_id}...")
            identified = await asyncio.to_thread(identify_audio, input_path)
        except Exception as id_error:
            logger.warning(
                f"Identification failed for job {job_id}: {id_error}"
            )
            identified = None

        job = {
            "job_id": job_id,
            "user_id": user_id,
            "owner_user_id": user_id,
            "status": "awaiting_ad",
            "created_at": _now_iso(),
            "updated_at": _now_iso(),
            "input_path": str(input_path),
            "with_audio": with_audio,
            "identified": identified,
            "levels": [_build_level_payload(level) for level in requested_levels],
        }

        async with jobs_lock:
            jobs_store[job_id] = job

        return _build_job_response(job)
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Job creation failed: {e}")
        if input_path.exists():
            input_path.unlink()
        raise HTTPException(status_code=500, detail=ERROR_MESSAGES["processing_failed"])


@app.post("/jobs/{job_id}/start", response_model=JobProgressResponse)
async def start_job(
    job_id: str,
    with_audio: bool = Form(False, description="Include synthesized audio in video"),
    levels: Optional[str] = Form("1,2,3,4"),
    user=Depends(get_current_user),
):
    """Start generation for an existing job."""
    user_id = user.get("uid") if isinstance(user, dict) else None
    if not user_id:
        raise HTTPException(status_code=401, detail="Unauthenticated user")

    requested_levels = _parse_levels(levels)

    async with jobs_lock:
        job = jobs_store.get(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        owner_id = job.get("owner_user_id") or job.get("user_id")
        if owner_id != user_id:
            raise HTTPException(status_code=403, detail="Forbidden")
        if job.get("status") in {"running", "complete", "error"}:
            return _build_job_response(job)

        job["status"] = "running"
        job["updated_at"] = _now_iso()
        job["with_audio"] = with_audio
        job["requested_levels"] = requested_levels

    asyncio.create_task(_run_job_generation(job_id, requested_levels, with_audio))

    async with jobs_lock:
        job = jobs_store.get(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        return _build_job_response(job)


@app.get("/jobs/{job_id}/progress", response_model=JobProgressResponse)
async def job_progress(job_id: str, user=Depends(get_current_user)):
    """Get progress for a job."""
    user_id = user.get("uid") if isinstance(user, dict) else None
    if not user_id:
        raise HTTPException(status_code=401, detail="Unauthenticated user")

    async with jobs_lock:
        job = jobs_store.get(job_id)
        if not job:
            raise HTTPException(status_code=404, detail="Job not found")
        owner_id = job.get("owner_user_id") or job.get("user_id")
        if owner_id != user_id:
            raise HTTPException(status_code=403, detail="Forbidden")
        return _build_job_response(job)


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
    logger.info(
        "Preview config: duration=%ss size=%sx%s",
        settings.PREVIEW_DURATION_SEC,
        settings.VIDEO_WIDTH,
        settings.VIDEO_HEIGHT,
    )
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
