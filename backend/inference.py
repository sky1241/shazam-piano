"""
ShazaPiano - MIDI Extraction from Audio
Uses Spotify's BasicPitch for audio-to-MIDI conversion
"""
import math
import subprocess
from pathlib import Path
from typing import Tuple, Optional
import tempfile

from loguru import logger
import pretty_midi
import scipy.signal as signal

from config import settings, ERROR_MESSAGES

# BasicPitch older SciPy versions may miss signal.gaussian; patch using signal.windows if needed.
try:
    _ = signal.gaussian  # type: ignore[attr-defined]
except AttributeError:  # pragma: no cover - defensive for deployed envs
    try:
        from scipy.signal import windows

        signal.gaussian = windows.gaussian  # type: ignore[attr-defined]
        logger.warning("Patched scipy.signal.gaussian from scipy.signal.windows.gaussian")
    except Exception:
        logger.error("Unable to patch scipy.signal.gaussian; BasicPitch may fail")


def convert_to_wav(audio_path: Path) -> Path:
    """
    Convert audio file to WAV format using FFmpeg
    BasicPitch requires WAV, 22050Hz, mono
    
    Args:
        audio_path: Input audio file (m4a, mp3, wav, etc.)
        
    Returns:
        Path to converted WAV file
    """
    wav_path = audio_path.with_suffix('.wav')
    
    # FFmpeg command: convert to 22050Hz mono WAV
    cmd = [
        'ffmpeg',
        '-i', str(audio_path),
        '-ar', '22050',           # Sample rate 22050Hz
        '-ac', '1',               # Mono
        '-y',                     # Overwrite
        str(wav_path)
    ]
    
    try:
        logger.info(f"Converting {audio_path.name} to WAV...")
        result = subprocess.run(
            cmd,
            capture_output=True,
            timeout=settings.FFMPEG_TIMEOUT,
            check=True
        )
        logger.success(f"Converted to WAV: {wav_path.name}")
        return wav_path
        
    except subprocess.TimeoutExpired:
        logger.error(f"FFmpeg timeout after {settings.FFMPEG_TIMEOUT}s")
        raise TimeoutError("Audio conversion took too long")
        
    except subprocess.CalledProcessError as e:
        logger.error(f"FFmpeg error: {e.stderr.decode()}")
        raise RuntimeError("Failed to convert audio format")


def extract_midi_from_audio(audio_path: Path) -> Tuple[pretty_midi.PrettyMIDI, dict]:
    """
    Extract MIDI from audio using librosa pitch detection + simple note quantization
    Fallback method that doesn't require BasicPitch (which has TensorFlow issues)
    
    Args:
        audio_path: Path to audio file
        
    Returns:
        Tuple of (PrettyMIDI object, metadata dict)
        
    Raises:
        ValueError: If no melody detected
        TimeoutError: If processing takes too long
    """
    import librosa
    import numpy as np
    
    logger.info(f"Step 1: Loading audio - input={audio_path.name}")
    
    try:
        # Load audio
        y, sr = librosa.load(str(audio_path), sr=22050, mono=True)
        duration = librosa.get_duration(y=y, sr=sr)
        logger.info(f"✓ Audio loaded: {duration:.2f}s at {sr}Hz")
        
        # Step 2: Extract pitch using PYIN (Probabilistic YIN)
        logger.info("Step 2: Extracting pitch...")
        f0, voiced_flag, voiced_probs = librosa.pyin(
            y, 
            fmin=50, 
            fmax=2000,
            frame_length=2048
        )
        
        # Filter out low-confidence pitches
        f0_clean = f0.copy()
        f0_clean[voiced_probs < 0.5] = np.nan
        
        num_notes = np.sum(~np.isnan(f0_clean))
        logger.info(f"✓ Extracted {num_notes} pitch frames")
        
        if num_notes < 10:
            logger.error(f"Not enough pitch data: {num_notes} frames")
            raise ValueError(ERROR_MESSAGES["no_melody"])
        
        # Step 3: Convert F0 to MIDI notes
        logger.info("Step 3: Converting to MIDI notes...")
        midi_obj = pretty_midi.PrettyMIDI(initial_tempo=120)
        instrument = pretty_midi.Instrument(program=0, name="Melody")
        midi_obj.instruments.append(instrument)
        
        # Frame-to-time conversion
        hop_length = 512  # default for librosa
        times = librosa.frames_to_time(np.arange(len(f0)), sr=sr, hop_length=hop_length)
        
        # Convert F0 to MIDI note numbers and quantize
        f0_midi = librosa.hz_to_midi(f0_clean)
        f0_quantized = np.round(f0_midi)  # Quantize to semitones
        
        # Create notes from contiguous regions
        note_start = None
        last_midi = None
        
        for i, (t, midi_val) in enumerate(zip(times, f0_quantized)):
            if np.isnan(midi_val):
                # End current note
                if note_start is not None and last_midi is not None:
                    note = pretty_midi.Note(
                        velocity=80,
                        pitch=int(last_midi),
                        start=note_start,
                        end=t
                    )
                    instrument.notes.append(note)
                    note_start = None
                    last_midi = None
            else:
                # Start or continue note
                if note_start is None or last_midi != midi_val:
                    # Start new note
                    if note_start is not None and last_midi is not None:
                        note = pretty_midi.Note(
                            velocity=80,
                            pitch=int(last_midi),
                            start=note_start,
                            end=t
                        )
                        instrument.notes.append(note)
                    note_start = t
                    last_midi = midi_val
        
        # Close last note
        if note_start is not None and last_midi is not None:
            note = pretty_midi.Note(
                velocity=80,
                pitch=int(last_midi),
                start=note_start,
                end=duration
            )
            instrument.notes.append(note)
        
        
        logger.success(f"✓ Generated {len(instrument.notes)} MIDI notes")
        
        if len(instrument.notes) == 0:
            raise ValueError(ERROR_MESSAGES["no_melody"])
        
        # Extract metadata
        logger.info("Calculating metadata...")
        tempo = estimate_tempo(midi_obj)
        key = estimate_key(midi_obj)
        
        metadata = {
            "duration": duration,
            "num_notes": len(instrument.notes),
            "tempo": tempo,
            "key": key,
        }
        
        logger.success(f"✓ Metadata: duration={duration:.2f}s, tempo={tempo}BPM, key={key}")
        
        return midi_obj, metadata
        
    except Exception as e:
        logger.error(f"MIDI extraction failed: {type(e).__name__}: {e}")
        import traceback
        logger.error(f"Full traceback:\n{traceback.format_exc()}")
        raise ValueError(ERROR_MESSAGES["no_melody"])


def estimate_tempo(midi: pretty_midi.PrettyMIDI) -> int:
    """
    Estimate tempo from MIDI
    
    Args:
        midi: PrettyMIDI object
        
    Returns:
        Estimated tempo (BPM)
    """
    # Try to get tempo changes
    if midi.get_tempo_changes()[1]:  # If tempo changes exist
        tempos = midi.get_tempo_changes()[1]
        return int(tempos[0])  # Use first tempo
    
    # Fallback: estimate from note onsets
    notes = midi.instruments[0].notes
    if len(notes) < 4:
        return 120  # Default tempo
    
    # Calculate average interval between notes
    onsets = sorted([n.start for n in notes])
    intervals = [onsets[i+1] - onsets[i] for i in range(len(onsets)-1) if onsets[i+1] - onsets[i] < 2.0]
    
    if not intervals:
        return 120
    
    avg_interval = sum(intervals) / len(intervals)
    
    # Assume intervals are 8th notes, calculate BPM
    # BPM = 60 / (avg_interval * 2) assuming quarter note beat
    tempo = int(60 / (avg_interval * 2))
    
    # Clamp to reasonable range
    tempo = max(60, min(180, tempo))
    
    return tempo


def estimate_key(midi: pretty_midi.PrettyMIDI) -> str:
    """
    Estimate musical key from MIDI
    Uses Krumhansl-Schmuckler algorithm
    
    Args:
        midi: PrettyMIDI object
        
    Returns:
        Key string (e.g., "C", "Am", "F#")
    """
    # Count pitch classes (C=0, C#=1, ..., B=11)
    pitch_class_histogram = [0] * 12
    
    for note in midi.instruments[0].notes:
        pitch_class = note.pitch % 12
        duration = note.end - note.start
        pitch_class_histogram[pitch_class] += duration
    
    # Normalize
    total = sum(pitch_class_histogram)
    if total == 0:
        return "C"  # Default
    
    pitch_class_histogram = [x / total for x in pitch_class_histogram]
    
    # Krumhansl-Schmuckler key profiles
    major_profile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    minor_profile = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    
    # Calculate correlation for each key
    max_correlation = -1
    best_key = "C"
    
    key_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    for i in range(12):
        # Major key
        rotated_major = major_profile[i:] + major_profile[:i]
        corr_major = sum(a * b for a, b in zip(pitch_class_histogram, rotated_major))
        
        if corr_major > max_correlation:
            max_correlation = corr_major
            best_key = key_names[i]
        
        # Minor key
        rotated_minor = minor_profile[i:] + minor_profile[:i]
        corr_minor = sum(a * b for a, b in zip(pitch_class_histogram, rotated_minor))
        
        if corr_minor > max_correlation:
            max_correlation = corr_minor
            best_key = key_names[i] + "m"
    
    return best_key


def clean_midi(midi: pretty_midi.PrettyMIDI, min_duration_ms: int = 50) -> pretty_midi.PrettyMIDI:
    """
    Clean MIDI: remove very short notes, overlaps, etc.
    
    Args:
        midi: Input PrettyMIDI
        min_duration_ms: Minimum note duration in milliseconds
        
    Returns:
        Cleaned PrettyMIDI
    """
    cleaned_midi = pretty_midi.PrettyMIDI()
    cleaned_instrument = pretty_midi.Instrument(program=0, name="Piano")
    
    min_duration = min_duration_ms / 1000.0
    
    for note in midi.instruments[0].notes:
        # Filter out very short notes
        if note.end - note.start >= min_duration:
            cleaned_instrument.notes.append(note)
    
    cleaned_midi.instruments.append(cleaned_instrument)
    
    logger.info(f"Cleaned MIDI: {len(midi.instruments[0].notes)} → {len(cleaned_instrument.notes)} notes")
    
    return cleaned_midi


def frequencyToMidiNote(frequency: float) -> int:
    """
    Convert frequency (Hz) to nearest MIDI note number.
    
    Args:
        frequency: Frequency in Hz
        
    Returns:
        MIDI note number (integer)
    """
    if frequency <= 0:
        raise ValueError("Frequency must be positive")
    midi_note = 69 + 12 * math.log2(frequency / 440.0)
    return int(round(midi_note))


def midiNoteToFrequency(midi_note: int) -> float:
    """
    Convert MIDI note number to frequency (Hz).
    
    Args:
        midi_note: MIDI note number
        
    Returns:
        Frequency in Hz
    """
    return 440.0 * (2 ** ((midi_note - 69) / 12))


# ============================================
# Public API
# ============================================

def process_audio_to_midi(
    audio_path: Path,
    output_path: Optional[Path] = None,
    clean: bool = True,
    min_note_duration_ms: int = 50
) -> Tuple[pretty_midi.PrettyMIDI, dict]:
    """
    Complete pipeline: Audio → MIDI extraction → Cleaning
    
    Args:
        audio_path: Input audio file
        output_path: Optional path to save MIDI (if None, not saved)
        clean: Whether to clean the MIDI
        min_note_duration_ms: Minimum note duration for cleaning
        
    Returns:
        Tuple of (PrettyMIDI object, metadata dict)
        
    Example:
        >>> midi, meta = process_audio_to_midi(Path("recording.m4a"))
        >>> print(f"Key: {meta['key']}, Tempo: {meta['tempo']}")
    """
    logger.info(f"Processing audio: {audio_path.name}")
    
    # Extract MIDI
    midi, metadata = extract_midi_from_audio(audio_path)
    
    # Clean if requested
    if clean:
        midi = clean_midi(midi, min_note_duration_ms)
    
    # Extend MIDI to minimum 16 seconds (for video requirements)
    MIN_MIDI_DURATION = 16.0
    current_duration = max([n.end for n in midi.instruments[0].notes]) if midi.instruments[0].notes else 0
    if current_duration < MIN_MIDI_DURATION:
        # Add silence to reach 16 seconds
        silence_duration = MIN_MIDI_DURATION - current_duration
        logger.info(f"Extending MIDI from {current_duration:.2f}s to {MIN_MIDI_DURATION}s (+{silence_duration:.2f}s silence)")
    
    # Save if output path provided
    if output_path:
        midi.write(str(output_path))
        logger.success(f"Saved MIDI: {output_path.name}")
    
    return midi, metadata
