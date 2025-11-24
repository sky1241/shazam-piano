"""
ShazaPiano Backend - FastAPI Application
Main entry point with routes
"""
import asyncio
import shutil
from pathlib import Path
from typing import List, Optional
from datetime import datetime

from fastapi import FastAPI, UploadFile, File, HTTPException, Query
from fastapi.responses import FileResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from loguru import logger

from config import settings, init_directories, get_level_config, ERROR_MESSAGES
# from inference import extract_melody_from_audio
# from arranger import arrange_midi
# from render import render_video

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


class HealthResponse(BaseModel):
    """Health check response"""
    status: str
    timestamp: str
    version: str


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
    levels: Optional[str] = Query("1,2,3,4", description="Comma-separated levels (e.g., '1,2,3,4')")
):
    """
    Process audio and generate piano videos for specified levels.
    
    - **audio**: Audio file (m4a, wav, mp3) - max 10MB, ~8s recommended
    - **with_audio**: Include synthesized piano audio in output videos
    - **levels**: Which levels to generate (default: all 4)
    
    Returns URLs for preview (16s) and full videos for each level.
    """
    
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
        
        # TODO: Process audio and generate videos
        # For now, return mock response
        results = []
        
        for level in requested_levels:
            level_config = get_level_config(level)
            results.append(
                LevelResult(
                    level=level,
                    name=level_config["name"],
                    preview_url=f"/media/out/{job_id}_L{level}_preview.mp4",
                    video_url=f"/media/out/{job_id}_L{level}_full.mp4",
                    midi_url=f"/media/out/{job_id}_L{level}.mid",
                    key_guess="C",
                    tempo_guess=120,
                    duration_sec=8.0,
                    status="pending"  # Will be "success" after processing
                )
            )
        
        return ProcessResponse(
            job_id=job_id,
            timestamp=datetime.utcnow().isoformat(),
            levels=results
        )
        
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
    logger.info(f"📁 Media directory: {settings.MEDIA_DIR}")
    logger.info(f"🎵 Ready to process on http://{settings.HOST}:{settings.PORT}")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info("👋 ShazaPiano Backend shutting down...")


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

