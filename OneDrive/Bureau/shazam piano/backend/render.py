"""
ShazaPiano - Video Renderer
Generates animated piano keyboard videos from MIDI
"""
from pathlib import Path
from typing import Tuple, Optional
import subprocess

import pretty_midi
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from moviepy.editor import ImageSequenceClip, AudioFileClip, concatenate_videoclips
from loguru import logger

from config import settings


# ============================================
# Piano Keyboard Constants
# ============================================

# Piano keys layout (C2 to C7 = 61 keys)
FIRST_KEY = 36  # C2
LAST_KEY = 96   # C7
NUM_KEYS = LAST_KEY - FIRST_KEY + 1

# Visual constants
WHITE_KEY_WIDTH = 20
WHITE_KEY_HEIGHT = 120
BLACK_KEY_WIDTH = 12
BLACK_KEY_HEIGHT = 75

# Colors
COLOR_WHITE_KEY = (255, 255, 255)
COLOR_BLACK_KEY = (30, 30, 30)
COLOR_WHITE_KEY_ACTIVE = (42, 230, 190)  # Primary color #2AE6BE
COLOR_BLACK_KEY_ACTIVE = (33, 199, 163)  # PrimaryVariant #21C7A3
COLOR_BACKGROUND = (11, 15, 16)  # Background #0B0F10
COLOR_TEXT = (233, 245, 241)  # TextPrimary #E9F5F1

# Black key positions in octave (0=C, 1=C#, ..., 11=B)
BLACK_KEY_POSITIONS = [1, 3, 6, 8, 10]  # C#, D#, F#, G#, A#


def is_black_key(midi_note: int) -> bool:
    """Check if MIDI note is a black key"""
    return (midi_note % 12) in BLACK_KEY_POSITIONS


def get_key_position(midi_note: int) -> Tuple[int, int, bool]:
    """
    Get visual position of a key
    
    Returns:
        (x_position, y_position, is_black)
    """
    if midi_note < FIRST_KEY or midi_note > LAST_KEY:
        # Out of range, place at edges
        if midi_note < FIRST_KEY:
            return (0, 0, False)
        else:
            return (NUM_KEYS * WHITE_KEY_WIDTH, 0, False)
    
    # Calculate position
    octave = (midi_note - FIRST_KEY) // 12
    note_in_octave = (midi_note - FIRST_KEY) % 12
    
    # White key numbering in octave
    white_keys_in_octave = [0, 2, 4, 5, 7, 9, 11]  # C D E F G A B
    
    is_black = is_black_key(midi_note)
    
    if is_black:
        # Find preceding white key
        white_key_index = white_keys_in_octave.index(note_in_octave - 1 if note_in_octave - 1 in white_keys_in_octave else note_in_octave - 2)
        white_key_count = octave * 7 + white_key_index
        x = white_key_count * WHITE_KEY_WIDTH + WHITE_KEY_WIDTH - BLACK_KEY_WIDTH // 2
        y = 0
    else:
        white_key_index = white_keys_in_octave.index(note_in_octave)
        white_key_count = octave * 7 + white_key_index
        x = white_key_count * WHITE_KEY_WIDTH
        y = 0
    
    return (x, y, is_black)


def render_keyboard_frame(
    active_notes: set,
    width: int,
    height: int,
    level_name: str = ""
) -> Image.Image:
    """
    Render single frame of piano keyboard
    
    Args:
        active_notes: Set of MIDI note numbers currently active
        width: Frame width
        height: Frame height
        level_name: Optional level name to display
        
    Returns:
        PIL Image
    """
    # Create image
    img = Image.new('RGB', (width, height), COLOR_BACKGROUND)
    draw = ImageDraw.Draw(img)
    
    # Calculate keyboard position (centered)
    total_white_keys = 35  # 5 octaves = 35 white keys
    keyboard_width = total_white_keys * WHITE_KEY_WIDTH
    keyboard_x = (width - keyboard_width) // 2
    keyboard_y = (height - WHITE_KEY_HEIGHT) // 2
    
    # Draw white keys first
    for midi_note in range(FIRST_KEY, LAST_KEY + 1):
        if not is_black_key(midi_note):
            x, y, _ = get_key_position(midi_note)
            x += keyboard_x
            y += keyboard_y
            
            # Active or inactive
            color = COLOR_WHITE_KEY_ACTIVE if midi_note in active_notes else COLOR_WHITE_KEY
            
            # Draw key
            draw.rectangle(
                [x, y, x + WHITE_KEY_WIDTH - 2, y + WHITE_KEY_HEIGHT],
                fill=color,
                outline=COLOR_BACKGROUND,
                width=2
            )
    
    # Draw black keys on top
    for midi_note in range(FIRST_KEY, LAST_KEY + 1):
        if is_black_key(midi_note):
            x, y, _ = get_key_position(midi_note)
            x += keyboard_x
            y += keyboard_y
            
            color = COLOR_BLACK_KEY_ACTIVE if midi_note in active_notes else COLOR_BLACK_KEY
            
            draw.rectangle(
                [x, y, x + BLACK_KEY_WIDTH, y + BLACK_KEY_HEIGHT],
                fill=color,
                outline=COLOR_BACKGROUND,
                width=1
            )
    
    # Draw level name at top
    if level_name:
        try:
            font = ImageFont.truetype("arial.ttf", 32)
        except:
            font = ImageFont.load_default()
        
        text_bbox = draw.textbbox((0, 0), level_name, font=font)
        text_width = text_bbox[2] - text_bbox[0]
        text_x = (width - text_width) // 2
        text_y = 30
        
        draw.text((text_x, text_y), level_name, fill=COLOR_TEXT, font=font)
    
    return img


def generate_video_frames(
    midi: pretty_midi.PrettyMIDI,
    level: int,
    level_name: str
) -> list:
    """
    Generate all video frames from MIDI
    
    Args:
        midi: PrettyMIDI object
        level: Level number
        level_name: Level name for display
        
    Returns:
        List of PIL Images
    """
    logger.info(f"Generating frames for Level {level}...")
    
    fps = settings.VIDEO_FPS
    width = settings.VIDEO_WIDTH
    height = settings.VIDEO_HEIGHT
    
    # Calculate duration
    duration = midi.get_end_time()
    num_frames = int(duration * fps) + fps  # Add 1 second padding
    
    frames = []
    
    # Collect all notes with timing
    all_notes = []
    for instrument in midi.instruments:
        all_notes.extend(instrument.notes)
    
    # Generate each frame
    for frame_idx in range(num_frames):
        time = frame_idx / fps
        
        # Find active notes at this time
        active_notes = set()
        for note in all_notes:
            if note.start <= time <= note.end:
                active_notes.add(note.pitch)
        
        # Render frame
        frame = render_keyboard_frame(
            active_notes=active_notes,
            width=width,
            height=height,
            level_name=f"Niveau {level}: {level_name}"
        )
        
        frames.append(np.array(frame))
        
        # Log progress
        if frame_idx % (fps * 2) == 0:  # Every 2 seconds
            logger.debug(f"Frame {frame_idx}/{num_frames} ({time:.1f}s)")
    
    logger.success(f"Generated {len(frames)} frames ({duration:.1f}s)")
    return frames


def create_video_from_frames(
    frames: list,
    output_path: Path,
    fps: int = 30,
    audio_path: Optional[Path] = None
) -> Path:
    """
    Create MP4 video from frames
    
    Args:
        frames: List of numpy arrays (frames)
        output_path: Output video path
        fps: Frames per second
        audio_path: Optional audio file to add
        
    Returns:
        Path to created video
    """
    logger.info(f"Creating video: {output_path.name}")
    
    # Create video clip
    clip = ImageSequenceClip(frames, fps=fps)
    
    # Add audio if provided
    if audio_path and audio_path.exists():
        audio = AudioFileClip(str(audio_path))
        clip = clip.set_audio(audio)
    
    # Write video
    clip.write_videofile(
        str(output_path),
        codec='libx264',
        audio_codec='aac' if audio_path else None,
        fps=fps,
        logger=None  # Suppress MoviePy logs
    )
    
    clip.close()
    if audio_path:
        audio.close()
    
    logger.success(f"Video saved: {output_path.name}")
    return output_path


def create_preview_video(full_video_path: Path, duration_sec: int = 16) -> Path:
    """
    Create preview (truncated) version of video
    
    Args:
        full_video_path: Path to full video
        duration_sec: Preview duration in seconds
        
    Returns:
        Path to preview video
    """
    preview_path = full_video_path.with_name(
        full_video_path.stem + "_preview" + full_video_path.suffix
    )
    
    logger.info(f"Creating {duration_sec}s preview...")
    
    # Use FFmpeg to trim video
    cmd = [
        'ffmpeg',
        '-i', str(full_video_path),
        '-t', str(duration_sec),  # Duration
        '-c', 'copy',  # Copy codec (fast)
        '-y',  # Overwrite
        str(preview_path)
    ]
    
    try:
        subprocess.run(cmd, capture_output=True, check=True, timeout=30)
        logger.success(f"Preview created: {preview_path.name}")
        return preview_path
    except Exception as e:
        logger.error(f"Preview creation failed: {e}")
        # Fallback: copy full video
        import shutil
        shutil.copy(full_video_path, preview_path)
        return preview_path


def synthesize_audio(midi: pretty_midi.PrettyMIDI, output_path: Path) -> Path:
    """
    Synthesize audio from MIDI using FluidSynth (optional)
    
    Args:
        midi: PrettyMIDI object
        output_path: Output audio path (.wav)
        
    Returns:
        Path to audio file
    """
    logger.info("Synthesizing audio from MIDI...")
    
    try:
        # Try FluidSynth synthesis
        audio = midi.fluidsynth(fs=44100)
        
        # Save as WAV
        import scipy.io.wavfile as wav
        wav.write(str(output_path), 44100, audio)
        
        logger.success(f"Audio synthesized: {output_path.name}")
        return output_path
        
    except Exception as e:
        logger.warning(f"Audio synthesis failed: {e}. Continuing without audio.")
        return None


# ============================================
# Main Rendering Pipeline
# ============================================

def render_level_video(
    midi: pretty_midi.PrettyMIDI,
    level: int,
    level_name: str,
    output_dir: Path,
    job_id: str,
    with_audio: bool = False
) -> Tuple[Path, Path, Optional[Path]]:
    """
    Complete pipeline: MIDI → Frames → Video (full + preview)
    
    Args:
        midi: Arranged MIDI for this level
        level: Level number (1-4)
        level_name: Level name (e.g., "Hyper Facile")
        output_dir: Output directory
        job_id: Job ID for naming files
        with_audio: Whether to synthesize and add audio
        
    Returns:
        Tuple of (full_video_path, preview_video_path, audio_path)
        
    Example:
        >>> full, preview, audio = render_level_video(midi, 1, "Hyper Facile", Path("out"), "job123")
    """
    logger.info(f"=== Rendering Level {level}: {level_name} ===")
    
    # Paths
    full_video_path = output_dir / f"{job_id}_L{level}_full.mp4"
    midi_path = output_dir / f"{job_id}_L{level}.mid"
    audio_path = output_dir / f"{job_id}_L{level}_audio.wav" if with_audio else None
    
    # Save MIDI
    midi.write(str(midi_path))
    logger.info(f"MIDI saved: {midi_path.name}")
    
    # Synthesize audio if requested
    audio_file = None
    if with_audio:
        audio_file = synthesize_audio(midi, audio_path)
    
    # Generate frames
    frames = generate_video_frames(midi, level, level_name)
    
    # Create full video
    full_video_path = create_video_from_frames(
        frames,
        full_video_path,
        fps=settings.VIDEO_FPS,
        audio_path=audio_file
    )
    
    # Create preview (16s)
    preview_video_path = create_preview_video(full_video_path, duration_sec=16)
    
    logger.success(f"✅ Level {level} complete!")
    return full_video_path, preview_video_path, audio_path

