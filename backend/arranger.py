"""
ShazaPiano - MIDI Arranger
Transforms basic melody into 4 difficulty levels
"""
from typing import List, Tuple, Optional, Dict, Any, Iterable
from copy import deepcopy
import math
import json
from pathlib import Path

import pretty_midi
import numpy as np
from loguru import logger

from config import get_level_config, MAJOR_SCALE, MINOR_SCALE

EXPECTED_NOTES_MIN_DURATION_MS = 50
EXPECTED_NOTES_MERGE_GAP_MS = 80
EXPECTED_NOTES_MAX_DURATION_MS = 6000
EXPECTED_NOTES_VIDEO_TOLERANCE_SEC = 0.25


def quantize_notes(notes: List[pretty_midi.Note], grid: float) -> List[pretty_midi.Note]:
    """
    Quantize note timings to grid
    
    Args:
        notes: List of MIDI notes
        grid: Grid size in seconds (e.g., 0.25 for quarter notes at 120 BPM)
        
    Returns:
        Quantized notes
    """
    quantized = []
    
    for note in notes:
        # Snap start to previous grid boundary
        new_start = math.floor(note.start / grid) * grid
        
        # Snap end to next grid boundary to avoid shortening notes too much
        new_end = math.ceil(note.end / grid) * grid
        new_duration = max(grid, new_end - new_start)

        quantized.append(
            pretty_midi.Note(
                velocity=note.velocity,
                pitch=note.pitch,
                start=new_start,
                end=new_end
            )
        )
    
    return quantized


def transpose_to_c(notes: List[pretty_midi.Note], current_key: str) -> Tuple[List[pretty_midi.Note], int]:
    """
    Transpose notes to C major/minor
    
    Args:
        notes: List of MIDI notes
        current_key: Current key (e.g., "G", "Am")
        
    Returns:
        Tuple of (transposed notes, semitone shift)
    """
    # Key to semitone mapping
    key_to_semitone = {
        "C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3,
        "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
        "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11,
        # Minor keys
        "Cm": 0, "C#m": 1, "Dm": 2, "D#m": 3, "Em": 4,
        "Fm": 5, "F#m": 6, "Gm": 7, "G#m": 8, "Am": 9,
        "A#m": 10, "Bm": 11,
    }
    
    # Calculate semitone shift to C
    base_semitone = key_to_semitone.get(current_key, 0)
    shift = -base_semitone  # Shift to C
    
    if shift == 0:
        return notes, 0
    
    transposed = []
    for note in notes:
        new_pitch = note.pitch + shift
        # Keep in valid MIDI range
        new_pitch = max(21, min(108, new_pitch))
        
        transposed.append(
            pretty_midi.Note(
                velocity=note.velocity,
                pitch=new_pitch,
                start=note.start,
                end=note.end
            )
        )
    
    logger.info(f"Transposed from {current_key} to C ({shift:+d} semitones)")
    return transposed, shift


def filter_notes_by_range(notes: List[pretty_midi.Note], min_pitch: int, max_pitch: int) -> List[pretty_midi.Note]:
    """
    Keep only notes within pitch range, transpose octaves if needed
    
    Args:
        notes: List of notes
        min_pitch: Minimum MIDI pitch
        max_pitch: Maximum MIDI pitch
        
    Returns:
        Filtered notes
    """
    filtered = []
    
    for note in notes:
        pitch = note.pitch
        
        # Transpose to range if out of bounds
        while pitch < min_pitch:
            pitch += 12
        while pitch > max_pitch:
            pitch -= 12
        
        filtered.append(
            pretty_midi.Note(
                velocity=note.velocity,
                pitch=pitch,
                start=note.start,
                end=note.end
            )
        )
    
    return filtered


def reduce_polyphony(notes: List[pretty_midi.Note]) -> List[pretty_midi.Note]:
    """
    Keep only highest note at each time (monophonic melody)
    
    Args:
        notes: List of notes
        
    Returns:
        Monophonic melody
    """
    if not notes:
        return []
    
    # Sort by start time
    notes = sorted(notes, key=lambda n: n.start)
    
    # Group overlapping notes
    monophonic = []
    current_group = [notes[0]]
    
    for note in notes[1:]:
        # If note overlaps with current group
        if note.start < current_group[-1].end:
            current_group.append(note)
        else:
            # Select highest pitch from group
            highest = max(current_group, key=lambda n: n.pitch)
            monophonic.append(highest)
            current_group = [note]
    
    # Add last group
    if current_group:
        highest = max(current_group, key=lambda n: n.pitch)
        monophonic.append(highest)
    
    logger.info(f"Reduced polyphony: {len(notes)} → {len(monophonic)} notes")
    return monophonic


def add_bass_notes(melody_notes: List[pretty_midi.Note], style: str = "root") -> List[pretty_midi.Note]:
    """
    Add left hand bass accompaniment
    
    Args:
        melody_notes: Melody notes
        style: "root" (just root note) or "root_fifth" (root + fifth)
        
    Returns:
        Bass notes
    """
    bass_notes = []
    
    # Simple approach: add root note of implied chord every measure
    # Group notes by measure (assuming 4/4, ~2 seconds per measure at 120 BPM)
    if not melody_notes:
        return []
    
    duration = melody_notes[-1].end
    measure_duration = 2.0  # seconds
    num_measures = int(duration / measure_duration) + 1
    
    for i in range(num_measures):
        measure_start = i * measure_duration
        measure_end = (i + 1) * measure_duration
        
        # Find notes in this measure
        measure_notes = [n for n in melody_notes if measure_start <= n.start < measure_end]
        
        if not measure_notes:
            continue
        
        # Estimate root: most common pitch class
        pitch_classes = [n.pitch % 12 for n in measure_notes]
        root_pc = max(set(pitch_classes), key=pitch_classes.count)
        
        # Bass note (2 octaves below middle C)
        bass_pitch = 36 + root_pc  # C2 + root
        
        # Add root note
        bass_notes.append(
            pretty_midi.Note(
                velocity=80,
                pitch=bass_pitch,
                start=measure_start,
                end=measure_end
            )
        )
        
        # Add fifth if requested
        if style == "root_fifth":
            fifth_pitch = bass_pitch + 7  # Perfect fifth
            bass_notes.append(
                pretty_midi.Note(
                    velocity=70,
                    pitch=fifth_pitch,
                    start=measure_start,
                    end=measure_end
                )
            )
    
    logger.info(f"Added {len(bass_notes)} bass notes ({style})")
    return bass_notes


def add_chord_accompaniment(
    melody_notes: List[pretty_midi.Note],
    style: str = "block"
) -> List[pretty_midi.Note]:
    """
    Add right hand chord accompaniment
    
    Args:
        melody_notes: Melody notes
        style: "block" (triads) or "broken" (arpeggios)
        
    Returns:
        Chord notes
    """
    chord_notes = []
    
    if not melody_notes:
        return []
    
    duration = melody_notes[-1].end
    measure_duration = 2.0
    num_measures = int(duration / measure_duration) + 1
    
    for i in range(num_measures):
        measure_start = i * measure_duration
        measure_end = (i + 1) * measure_duration
        
        measure_notes = [n for n in melody_notes if measure_start <= n.start < measure_end]
        
        if not measure_notes:
            continue
        
        # Estimate chord: most common pitch classes
        pitch_classes = [n.pitch % 12 for n in measure_notes]
        root_pc = max(set(pitch_classes), key=pitch_classes.count)
        
        # Build triad (root, third, fifth) in C4 range
        root = 60 + root_pc  # C4 + root
        third = root + 4  # Major third (simplification)
        fifth = root + 7  # Perfect fifth
        
        if style == "block":
            # Block chord at start of measure
            for pitch in [root, third, fifth]:
                chord_notes.append(
                    pretty_midi.Note(
                        velocity=60,
                        pitch=pitch,
                        start=measure_start,
                        end=measure_start + 0.5  # Half beat
                    )
                )
        
        elif style == "broken":
            # Arpeggio pattern
            arp_notes = [root, third, fifth, root + 12]
            beat_duration = 0.5
            
            for j, pitch in enumerate(arp_notes):
                chord_notes.append(
                    pretty_midi.Note(
                        velocity=60,
                        pitch=pitch,
                        start=measure_start + j * beat_duration,
                        end=measure_start + (j + 1) * beat_duration
                    )
                )
    
    logger.info(f"Added {len(chord_notes)} chord notes ({style})")
    return chord_notes


def arrange_level(
    midi: pretty_midi.PrettyMIDI,
    level: int,
    key: str = "C",
    tempo: int = 120
) -> pretty_midi.PrettyMIDI:
    """
    Arrange MIDI for specific difficulty level
    
    Args:
        midi: Input MIDI (raw melody)
        level: Difficulty level (1-4)
        key: Musical key
        tempo: Tempo in BPM
        
    Returns:
        Arranged MIDI for the level
    """
    config = get_level_config(level)
    logger.info(f"Arranging Level {level}: {config['name']}")
    
    # Get melody notes
    melody_notes = list(midi.instruments[0].notes)
    
    # Step 1: Transpose to C if needed
    if config["transpose_to_c"]:
        melody_notes, _ = transpose_to_c(melody_notes, key)
    
    # Step 2: Quantize
    if config["quantize"] == "1/4":
        grid = 60 / tempo  # Quarter note
    elif config["quantize"] == "1/8":
        grid = 30 / tempo  # Eighth note
    elif config["quantize"] == "1/16":
        grid = 15 / tempo  # Sixteenth note
    else:
        grid = 30 / tempo  # Default 1/8
    
    melody_notes = quantize_notes(melody_notes, grid)
    
    # Step 3: Reduce polyphony if needed
    if not config["polyphony"]:
        melody_notes = reduce_polyphony(melody_notes)
    
    # Step 4: Filter by range
    min_pitch, max_pitch = config["note_range"]
    melody_notes = filter_notes_by_range(melody_notes, min_pitch, max_pitch)
    
    # Step 5: Filter short notes
    min_duration = config["filter_short_notes_ms"] / 1000.0
    melody_notes = [n for n in melody_notes if n.end - n.start >= min_duration]
    
    # Step 6: Adjust tempo
    if config.get("tempo_factor", 1.0) != 1.0:
        factor = config["tempo_factor"]
        melody_notes = [
            pretty_midi.Note(
                velocity=n.velocity,
                pitch=n.pitch,
                start=n.start / factor,
                end=n.end / factor
            )
            for n in melody_notes
        ]
    
    # Step 7: Build final MIDI
    arranged_midi = pretty_midi.PrettyMIDI(initial_tempo=tempo)
    
    # Right hand (melody + chords)
    right_hand = pretty_midi.Instrument(program=0, name="Right Hand")
    right_hand.notes.extend(melody_notes)
    
    # Add chords if configured
    if config.get("right_hand_chords"):
        chord_style = config["right_hand_chords"]
        chord_notes = add_chord_accompaniment(melody_notes, style=chord_style)
        right_hand.notes.extend(chord_notes)
    
    arranged_midi.instruments.append(right_hand)
    
    # Left hand (bass)
    if config.get("left_hand"):
        left_hand = pretty_midi.Instrument(program=0, name="Left Hand")
        bass_style = config["left_hand"]
        bass_notes = add_bass_notes(melody_notes, style=bass_style)
        left_hand.notes.extend(bass_notes)
        arranged_midi.instruments.append(left_hand)
    
    logger.success(f"Level {level} arranged: {len(arranged_midi.instruments)} tracks, {sum(len(inst.notes) for inst in arranged_midi.instruments)} notes")
    
    return arranged_midi


def _collect_notes(midi: pretty_midi.PrettyMIDI) -> List[pretty_midi.Note]:
    notes: List[pretty_midi.Note] = []
    for instrument in midi.instruments:
        notes.extend(instrument.notes)
    return notes


def _sanitize_expected_notes(
    notes: Iterable[pretty_midi.Note],
    duration_sec: Optional[float],
    min_duration_ms: int,
    merge_gap_ms: int,
    max_duration_ms: int,
) -> Tuple[List[Dict[str, Any]], Dict[str, int]]:
    notes_list = list(notes)
    min_duration_sec = min_duration_ms / 1000.0
    merge_gap_sec = merge_gap_ms / 1000.0
    max_duration_sec = max_duration_ms / 1000.0

    dropped_too_short = 0
    dropped_too_long = 0
    clamped_to_duration = 0
    by_pitch: Dict[int, List[Tuple[float, float, int]]] = {}

    max_start = None
    if duration_sec is not None:
        max_start = duration_sec + EXPECTED_NOTES_VIDEO_TOLERANCE_SEC

    for note in notes_list:
        start = float(note.start)
        end = float(note.end)
        if start < 0 or end < 0:
            dropped_too_short += 1
            continue
        if max_start is not None:
            if start > max_start or end > max_start:
                dropped_too_short += 1
                continue
            if duration_sec is not None and end > duration_sec:
                end = duration_sec
                clamped_to_duration += 1
        if end <= start:
            dropped_too_short += 1
            continue
        if end - start < min_duration_sec:
            dropped_too_short += 1
            continue
        by_pitch.setdefault(note.pitch, []).append(
            (start, end, int(note.velocity))
        )

    merged: List[Tuple[int, float, float, int]] = []
    for pitch, spans in by_pitch.items():
        spans.sort(key=lambda s: s[0])
        current_start, current_end, current_velocity = spans[0]
        for start, end, velocity in spans[1:]:
            if start - current_end <= merge_gap_sec:
                current_end = max(current_end, end)
                current_velocity = max(current_velocity, velocity)
            else:
                merged.append((pitch, current_start, current_end, current_velocity))
                current_start, current_end, current_velocity = start, end, velocity
        merged.append((pitch, current_start, current_end, current_velocity))

    sanitized: List[Tuple[int, float, float, int]] = []
    for pitch, start, end, velocity in merged:
        duration = end - start
        if duration > max_duration_sec:
            dropped_too_long += 1
            segment_start = start
            while segment_start < end:
                segment_end = min(segment_start + max_duration_sec, end)
                if segment_end - segment_start < min_duration_sec:
                    dropped_too_short += 1
                else:
                    sanitized.append(
                        (pitch, segment_start, segment_end, velocity)
                    )
                segment_start = segment_end
        else:
            sanitized.append((pitch, start, end, velocity))

    sanitized.sort(key=lambda n: (n[1], n[0]))
    payload_notes = [
        {
            "pitch": pitch,
            "start": float(start),
            "end": float(end),
            "velocity": int(velocity),
        }
        for pitch, start, end, velocity in sanitized
    ]

    stats = {
        "notes_in": len(notes_list),
        "notes_out": len(payload_notes),
        "dropped_too_short": dropped_too_short,
        "dropped_too_long": dropped_too_long,
        "clamped_to_duration": clamped_to_duration,
    }
    return payload_notes, stats


def build_expected_notes_payload(
    midi: pretty_midi.PrettyMIDI,
    job_id: str,
    level: int,
    duration_sec: Optional[float] = None,
    melody_quality: Optional[float] = None,
    min_duration_ms: int = EXPECTED_NOTES_MIN_DURATION_MS,
    merge_gap_ms: int = EXPECTED_NOTES_MERGE_GAP_MS,
    max_duration_ms: int = EXPECTED_NOTES_MAX_DURATION_MS,
) -> Dict[str, Any]:
    raw_notes = _collect_notes(midi)
    payload_duration = duration_sec if duration_sec is not None else midi.get_end_time()
    payload_duration = float(payload_duration or 0.0)
    payload_notes, stats = _sanitize_expected_notes(
        raw_notes,
        payload_duration,
        min_duration_ms,
        merge_gap_ms,
        max_duration_ms,
    )

    return {
        "job_id": job_id,
        "level": level,
        "duration_sec": payload_duration,
        "melody_quality": float(melody_quality) if melody_quality is not None else None,
        "notes": payload_notes,
        "stats": stats,
    }


def export_expected_notes_json(
    midi: pretty_midi.PrettyMIDI,
    output_dir: Path,
    job_id: str,
    level: int,
    duration_sec: Optional[float] = None,
    melody_quality: Optional[float] = None,
    min_duration_ms: int = EXPECTED_NOTES_MIN_DURATION_MS,
    merge_gap_ms: int = EXPECTED_NOTES_MERGE_GAP_MS,
    max_duration_ms: int = EXPECTED_NOTES_MAX_DURATION_MS,
) -> Path:
    payload = build_expected_notes_payload(
        midi=midi,
        job_id=job_id,
        level=level,
        duration_sec=duration_sec,
        melody_quality=melody_quality,
        min_duration_ms=min_duration_ms,
        merge_gap_ms=merge_gap_ms,
        max_duration_ms=max_duration_ms,
    )
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{job_id}_expected_notes_L{level}.json"
    output_path.write_text(
        json.dumps(payload, ensure_ascii=True),
        encoding="utf-8",
    )
    return output_path
