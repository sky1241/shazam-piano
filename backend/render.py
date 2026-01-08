"""
ShazaPiano - Video Renderer
Generates animated piano keyboard videos from MIDI
"""
from pathlib import Path
from typing import Tuple, Optional, Iterator
import subprocess
import gc

import pretty_midi
import numpy as np
from PIL import Image, ImageDraw, ImageFont
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
COLOR_KEY_LABEL = (60, 60, 60)

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# Black key positions in octave (0=C, 1=C#, ..., 11=B)
BLACK_KEY_POSITIONS = [1, 3, 6, 8, 10]  # C#, D#, F#, G#, A#


def is_black_key(midi_note: int) -> bool:
    """Check if MIDI note is a black key"""
    return (midi_note % 12) in BLACK_KEY_POSITIONS


def note_label(midi_note: int) -> str:
    """Get label for white keys: C with octave, others without octave."""
    base = NOTE_NAMES[midi_note % 12]
    if base == "C":
        octave = (midi_note // 12) - 1
        return f"{base}{octave}"
    return base


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
    level_name: str = "",
    current_time: float = 0.0,
    upcoming_notes: Optional[list] = None,
    show_level_label: bool = False,
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
    font = ImageFont.load_default()
    
    # Calculate keyboard position (bottom of screen, scaled to fit width)
    total_white_keys = 35  # 5 octaves = 35 white keys
    
    # Scale keys to fill ~75% of screen width with dynamic sizing (gives more breathing room / less zoom)
    available_width = int(width * 0.75)
    dynamic_white_key_width = max(8, available_width // total_white_keys)  # Scale keys but min 8px
    keyboard_width = total_white_keys * dynamic_white_key_width
    keyboard_x = (width - keyboard_width) // 2
    
    # Piano sits flush at bottom (no gap) so falling bars disappear behind it
    piano_bottom_padding = 0
    keyboard_y = height - WHITE_KEY_HEIGHT - piano_bottom_padding

    # Precompute scaling helpers so falling bars and keys align perfectly
    scaled_black_key_width = max(6, (dynamic_white_key_width * BLACK_KEY_WIDTH) // WHITE_KEY_WIDTH)
    def scale_x(x_base: int) -> int:
        """Scale base x (using WHITE_KEY_WIDTH grid) to the dynamic key width grid."""
        return keyboard_x + (x_base * dynamic_white_key_width) // WHITE_KEY_WIDTH

    # Draw falling notes
    if upcoming_notes:
        lookahead = settings.VIDEO_LOOKAHEAD_SEC
        fall_area = min(settings.VIDEO_FALLING_AREA_HEIGHT, max(200, int(height * 0.7)))
        speed_px = settings.VIDEO_FALLING_SPEED_PX_PER_SEC
        fall_color = (255, 204, 0)
        bar_start_y = keyboard_y - fall_area - settings.VIDEO_BAR_START_Y_OFFSET
        
        for pitch, start, end in upcoming_notes:
            if current_time > end:
                continue

            # Only keep future notes within lookahead OR active notes still sustaining
            time_to_start = start - current_time
            if time_to_start > lookahead:
                continue

            # Distance bar will fall = dt * speed (pixels per second)
            # Before start: bar falls toward the keyboard. After start: keep falling past the keyboard until note end.
            if time_to_start >= 0:
                fall_distance = time_to_start * speed_px
                bar_bottom = keyboard_y - fall_distance
            else:
                elapsed = -time_to_start  # time since note started
                bar_bottom = keyboard_y + elapsed * speed_px

            # Horizontal position scaled to current key sizes
            x_base, _, is_black = get_key_position(pitch)
            x = scale_x(x_base)
            key_width = scaled_black_key_width if is_black else dynamic_white_key_width
            bar_width = max(4, key_width - 4)

            note_duration = max(0.1, end - start)
            # Make bar height proportional to how long the key will stay pressed
            bar_height = int(note_duration * speed_px)
            bar_height = max(20, bar_height)
            bar_top = bar_bottom - bar_height

            # Clamp so pre-start bars don't start above the visible fall area
            min_top = keyboard_y - fall_area - settings.VIDEO_BAR_START_Y_OFFSET
            min_bottom = min_top + 1  # ensure bottom stays >= top
            if time_to_start >= 0:
                if bar_bottom < min_bottom:
                    bar_bottom = min_bottom
                    bar_top = bar_bottom - bar_height
                bar_top = max(bar_top, min_top)

            # Ensure bottom is not above top (Pillow constraint)
            if bar_bottom <= bar_top:
                bar_bottom = bar_top + 1

            # Center bar on the key width for cleaner alignment
            x_offset = (key_width - bar_width) // 2
            y0 = bar_top
            y1 = bar_bottom
            draw.rectangle(
                [x + x_offset, y0, x + x_offset + bar_width, y1],
                fill=fall_color,
                outline=None,
            )
    
    # Draw white keys first
    for midi_note in range(FIRST_KEY, LAST_KEY + 1):
        if not is_black_key(midi_note):
            x, y, _ = get_key_position(midi_note)
            # Scale position and size by ratio
            key_width = dynamic_white_key_width
            x = scale_x(x)
            y += keyboard_y
            
            # Active or inactive
            color = COLOR_WHITE_KEY_ACTIVE if midi_note in active_notes else COLOR_WHITE_KEY
            
            # Draw key with scaled width
            draw.rectangle(
                [x, y, x + key_width - 2, y + WHITE_KEY_HEIGHT],
                fill=color,
                outline=COLOR_BACKGROUND,
                width=2
            )

            label = note_label(midi_note)
            if label:
                bbox = draw.textbbox((0, 0), label, font=font)
                text_w = bbox[2] - bbox[0]
                text_h = bbox[3] - bbox[1]
                text_x = x + (key_width - text_w) / 2
                text_y = y + WHITE_KEY_HEIGHT - text_h - 4
                draw.text((text_x, text_y), label, fill=COLOR_KEY_LABEL, font=font)
    
    # Draw black keys on top
    for midi_note in range(FIRST_KEY, LAST_KEY + 1):
        if is_black_key(midi_note):
            x, y, _ = get_key_position(midi_note)
            # Scale position and size by ratio
            black_key_width = max(6, (dynamic_white_key_width * BLACK_KEY_WIDTH) // WHITE_KEY_WIDTH)
            x = scale_x(x)
            y += keyboard_y
            
            color = COLOR_BLACK_KEY_ACTIVE if midi_note in active_notes else COLOR_BLACK_KEY
            
            draw.rectangle(
                [x, y, x + black_key_width, y + BLACK_KEY_HEIGHT],
                fill=color,
                outline=COLOR_BACKGROUND,
                width=1
            )
    
    # Level label intentionally disabled to avoid duplicate overlays

    # Mask area below keys to hide falling bars once they pass the keyboard
    draw.rectangle(
        [0, keyboard_y + WHITE_KEY_HEIGHT, width, height],
        fill=COLOR_BACKGROUND,
        outline=None,
    )
    
    return img


def _sanitize_notes(notes: list[tuple[int, float, float]], frame_dt: float) -> list[tuple[int, float, float]]:
    """
    Ensure successive notes of the same pitch don't overlap.
    Only shortens ends if they overlap the next note (tiny gap).
    """
    by_pitch = {}
    for pitch, start, end in notes:
        by_pitch.setdefault(pitch, []).append([start, end])

    sanitized = []
    for pitch, spans in by_pitch.items():
        spans.sort(key=lambda x: x[0])
        for idx, (start, end) in enumerate(spans):
            if idx + 1 < len(spans):
                next_start = spans[idx + 1][0]
                max_end = next_start - 0.05  # small gap if overlapping next note
                if end > max_end:
                    end = max(start, max_end)
            # Ensure minimal positive duration
            min_dur = max(0.01, 0.5 * frame_dt)
            if end - start < min_dur:
                end = start + min_dur
            sanitized.append((pitch, start, end))
    return sanitized


def generate_video_frames(
    midi: pretty_midi.PrettyMIDI,
    level: int,
    level_name: str,
    max_duration: float | None = None,
) -> tuple[Iterator[np.ndarray], int, float]:
    """
    Generate video frames from MIDI as a stream
    
    Args:
        midi: PrettyMIDI object
        level: Level number
        level_name: Level name for display
        
    Returns:
        (frame_iterator, num_frames, duration_sec)
    """
    logger.info(f"Generating frames for Level {level}...")
    
    fps = settings.VIDEO_FPS
    width = settings.VIDEO_WIDTH
    height = settings.VIDEO_HEIGHT
    frame_dt = 1.0 / fps
    time_offset = settings.VIDEO_TIME_OFFSET_MS / 1000.0
    
    # Calculate duration
    midi_duration = midi.get_end_time()
    preroll = settings.VIDEO_PREROLL_SEC
    # Force target duration: limit to max_duration if specified (e.g., 16s)
    if max_duration:
        duration = min(max_duration, midi_duration)
    else:
        duration = midi_duration
    effective_duration = duration + preroll
    num_frames = int(effective_duration * fps)
    
    # Collect all notes with timing
    all_notes = []
    for instrument in midi.instruments:
        all_notes.extend(instrument.notes)
    # Convert to tuples for speed (keep all pitches, we'll clamp positions visually)
    all_notes = [(n.pitch, n.start, n.end) for n in all_notes]
    all_notes = _sanitize_notes(all_notes, frame_dt)
    release_epsilon = 0.02  # tiny release margin to avoid sticky keys

    def frame_iterator() -> Iterator[np.ndarray]:
        # Generate each frame
        for frame_idx in range(num_frames):
            time = frame_idx * frame_dt - preroll + time_offset  # start with preroll so bars fall from the sky

            # Find active notes at this time (with global offset)
            active_notes = set()
            for pitch, start, end in all_notes:
                s = start + time_offset
                e = end + time_offset
                tolerance_start = 0.05 * frame_dt
                tolerance_end = 0.1 * frame_dt
                if (s - tolerance_start) <= time <= (e + tolerance_end - release_epsilon):
                    active_notes.add(pitch)

            # Upcoming notes for falling bars
            upcoming = []
            for pitch, start, end in all_notes:
                s = start + time_offset
                e = end + time_offset
                if (time <= s <= time + settings.VIDEO_LOOKAHEAD_SEC) or (s <= time <= e):
                    upcoming.append((pitch, s, e))

            # Render frame
            frame = render_keyboard_frame(
                active_notes=active_notes,
                width=width,
                height=height,
                level_name="",  # Hide text in video to avoid duplicated titles (front can overlay)
                current_time=time,
                upcoming_notes=upcoming,
                show_level_label=False,
            )

            # Log progress
            if frame_idx % (fps * 2) == 0:  # Every 2 seconds
                logger.debug(f"Frame {frame_idx}/{num_frames} ({time:.1f}s)")

            yield np.array(frame)

    return frame_iterator(), num_frames, duration


def create_video_from_frames(
    frames: Iterator[np.ndarray],
    output_path: Path,
    fps: int = 30,
    audio_path: Optional[Path] = None,
    max_duration: Optional[float] = None,
    width: Optional[int] = None,
    height: Optional[int] = None,
    expected_frames: Optional[int] = None,
    duration_sec: Optional[float] = None,
) -> Path:
    """
    Create MP4 video from frames
    
    Args:
        frames: Iterator of numpy arrays (frames)
        output_path: Output video path
        fps: Frames per second
        audio_path: Optional audio file to add
        max_duration: Optional max duration in seconds (will trim if exceeded)
        width: Frame width
        height: Frame height
        expected_frames: Optional expected frame count
        duration_sec: Optional duration in seconds
        
    Returns:
        Path to created video
    """
    logger.info(f"Creating video: {output_path.name}")
    
    if width is None or height is None:
        raise RuntimeError("Missing frame dimensions for streaming encoder")

    max_frames = None
    if max_duration:
        max_frames = int(max_duration * fps)
        if expected_frames and expected_frames > max_frames:
            logger.info(
                f"Clamped frames to {max_frames} for {max_duration}s max duration"
            )

    cmd = [
        "ffmpeg",
        "-y",
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        f"{width}x{height}",
        "-r",
        str(fps),
        "-i",
        "-",
    ]
    if audio_path and audio_path.exists():
        cmd += [
            "-i",
            str(audio_path),
            "-shortest",
            "-c:a",
            "aac",
            "-b:a",
            "128k",
        ]
    else:
        cmd += ["-an"]

    cmd += [
        "-c:v",
        "libx264",
        "-preset",
        "veryfast",
        "-pix_fmt",
        "yuv420p",
        str(output_path),
    ]

    process = subprocess.Popen(
        cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE
    )
    broken_pipe = False
    stream_error = None
    frame_count = 0

    try:
        for frame in frames:
            if max_frames is not None and frame_count >= max_frames:
                break
            frame_data = np.ascontiguousarray(frame, dtype=np.uint8)
            try:
                process.stdin.write(frame_data.tobytes())
            except BrokenPipeError:
                broken_pipe = True
                break
            frame_count += 1
    except Exception as exc:
        stream_error = exc
    finally:
        if process.stdin:
            process.stdin.close()

    stderr_output = b""
    return_code = None
    if process.stderr:
        try:
            _, stderr_output = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            _, stderr_output = process.communicate()
        return_code = process.returncode
    else:
        return_code = process.wait()

    stderr_text = stderr_output.decode("utf-8", errors="replace")
    tail = "\n".join(stderr_text.splitlines()[-40:])

    if stream_error is not None:
        if tail:
            raise RuntimeError(
                f"{type(stream_error).__name__}: {stream_error}\n{tail}"
            )
        raise stream_error

    if broken_pipe or return_code != 0:
        raise RuntimeError(
            f"FFmpeg failed while encoding {output_path.name}:\n{tail}"
        )

    measured_duration = frame_count / fps
    if duration_sec is None:
        duration_sec = measured_duration
    else:
        duration_sec = max(duration_sec, measured_duration)

    logger.success(f"Video saved: {output_path.name}")
    logger.success(f"Encoded {frame_count} frames ({duration_sec:.1f}s)")
    gc.collect()
    return output_path


def create_preview_video(full_video_path: Path, duration_sec: int = None) -> Path:
    """
    Create preview (truncated) version of video
    
    Args:
        full_video_path: Path to full video
        duration_sec: Preview duration in seconds (default from settings)
        
    Returns:
        Path to preview video
    """
    if duration_sec is None:
        duration_sec = settings.PREVIEW_DURATION_SEC  # SYNC: use config value
    
    preview_path = full_video_path.with_name(
        full_video_path.stem + "_preview" + full_video_path.suffix
    )
    
    logger.info(f"Creating {duration_sec}s preview with FFmpeg trim...")
    
    # Use FFmpeg to trim video to exact duration with fast encoding
    cmd = [
        'ffmpeg',
        '-i', str(full_video_path),
        '-t', str(float(duration_sec)),  # Duration in seconds
        '-c:v', 'libx264',
        '-preset', 'ultrafast',  # Fastest encode
        '-c:a', 'aac',
        '-y',
        str(preview_path)
    ]
    
    try:
        subprocess.run(cmd, capture_output=True, check=True, timeout=60)
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
    
    # Generate frames (streamed)
    frame_iter, num_frames, duration_sec = generate_video_frames(
        midi,
        level,
        "",  # hide level/title text in video (front can display it)
        max_duration=settings.FULL_VIDEO_MAX_DURATION_SEC,
    )
    
    # Create full video
    full_video_path = create_video_from_frames(
        frame_iter,
        full_video_path,
        fps=settings.VIDEO_FPS,
        audio_path=audio_file,
        max_duration=settings.FULL_VIDEO_MAX_DURATION_SEC,
        width=settings.VIDEO_WIDTH,
        height=settings.VIDEO_HEIGHT,
        expected_frames=num_frames,
        duration_sec=duration_sec,
    )
    
    # Create preview (16s by config)
    preview_video_path = create_preview_video(
        full_video_path,
        duration_sec=settings.PREVIEW_DURATION_SEC,
    )
    
    logger.success(f"✅ Level {level} complete!")
    return full_video_path, preview_video_path, audio_path
