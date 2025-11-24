"""
Tests for inference.py - MIDI extraction
"""
import pytest
from pathlib import Path
import pretty_midi
from inference import (
    estimate_tempo,
    estimate_key,
    clean_midi,
    frequencyToMidiNote,
    midiNoteToFrequency,
)


def test_estimate_tempo():
    """Test tempo estimation"""
    midi = pretty_midi.PrettyMIDI()
    instrument = pretty_midi.Instrument(program=0)
    
    # Add notes at 120 BPM (0.5s per beat)
    for i in range(8):
        note = pretty_midi.Note(
            velocity=100,
            pitch=60,
            start=i * 0.5,
            end=i * 0.5 + 0.4
        )
        instrument.notes.append(note)
    
    midi.instruments.append(instrument)
    
    tempo = estimate_tempo(midi)
    assert 100 <= tempo <= 140  # Should be around 120


def test_estimate_key_c_major():
    """Test key estimation for C major"""
    midi = pretty_midi.PrettyMIDI()
    instrument = pretty_midi.Instrument(program=0)
    
    # C major scale notes
    c_major_notes = [60, 62, 64, 65, 67, 69, 71, 72]  # C D E F G A B C
    
    for i, pitch in enumerate(c_major_notes):
        note = pretty_midi.Note(
            velocity=100,
            pitch=pitch,
            start=i * 0.5,
            end=i * 0.5 + 0.4
        )
        instrument.notes.append(note)
    
    midi.instruments.append(instrument)
    
    key = estimate_key(midi)
    assert key in ["C", "Am"]  # Could be C major or A minor


def test_clean_midi():
    """Test MIDI cleaning"""
    midi = pretty_midi.PrettyMIDI()
    instrument = pretty_midi.Instrument(program=0)
    
    # Add notes including very short ones
    notes = [
        pretty_midi.Note(100, 60, 0.0, 0.5),    # Keep (500ms)
        pretty_midi.Note(100, 62, 0.5, 0.51),   # Remove (10ms)
        pretty_midi.Note(100, 64, 1.0, 1.3),    # Keep (300ms)
        pretty_midi.Note(100, 65, 1.5, 1.52),   # Remove (20ms)
    ]
    instrument.notes.extend(notes)
    midi.instruments.append(instrument)
    
    cleaned = clean_midi(midi, min_duration_ms=50)
    
    assert len(cleaned.instruments[0].notes) == 2  # Only 2 long notes


def test_frequency_conversion():
    """Test frequency <-> MIDI conversion"""
    # A4 = 440 Hz = MIDI 69
    assert frequencyToMidiNote(440) == 69
    
    # C4 = 261.63 Hz = MIDI 60
    midi_note = frequencyToMidiNote(261.63)
    assert 59 <= midi_note <= 61  # Allow small rounding error
    
    # Reverse conversion
    freq = midiNoteToFrequency(69)
    assert abs(freq - 440) < 0.01


if __name__ == '__main__':
    pytest.main([__file__, '-v'])

