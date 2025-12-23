"""
Tests for arranger.py - MIDI arrangements
"""
import pytest
import pretty_midi
from arranger import (
    quantize_notes,
    transpose_to_c,
    filter_notes_by_range,
    reduce_polyphony,
    add_bass_notes,
    add_chord_accompaniment,
)


def test_quantize_notes():
    """Test note quantization"""
    notes = [
        pretty_midi.Note(100, 60, 0.13, 0.48),  # Should snap to 0.0, 0.5
        pretty_midi.Note(100, 62, 0.63, 0.88),  # Should snap to 0.5, 1.0
    ]
    
    quantized = quantize_notes(notes, grid=0.25)  # Quarter note grid
    
    assert quantized[0].start == 0.0
    assert quantized[0].end == 0.5
    assert quantized[1].start == 0.5
    assert abs(quantized[1].end - 1.0) < 0.01


def test_transpose_to_c():
    """Test transposition to C"""
    # G major notes (G A B C D E F# G) = (67 69 71 72 74 76 78 79)
    notes = [
        pretty_midi.Note(100, 67, 0, 1),  # G
        pretty_midi.Note(100, 71, 1, 2),  # B
        pretty_midi.Note(100, 74, 2, 3),  # D
    ]
    
    transposed, shift = transpose_to_c(notes, "G")
    
    assert shift == -7  # G to C is -7 semitones
    assert transposed[0].pitch == 60  # G -> C
    assert transposed[1].pitch == 64  # B -> E
    assert transposed[2].pitch == 67  # D -> G


def test_filter_notes_by_range():
    """Test note range filtering"""
    notes = [
        pretty_midi.Note(100, 40, 0, 1),  # Too low
        pretty_midi.Note(100, 60, 1, 2),  # In range
        pretty_midi.Note(100, 80, 2, 3),  # Too high
    ]
    
    filtered = filter_notes_by_range(notes, min_pitch=48, max_pitch=72)
    
    # Should transpose out-of-range notes to be in range
    assert all(48 <= note.pitch <= 72 for note in filtered)
    assert len(filtered) == 3


def test_reduce_polyphony():
    """Test polyphony reduction"""
    # Overlapping notes (chord)
    notes = [
        pretty_midi.Note(100, 60, 0.0, 1.0),  # C
        pretty_midi.Note(100, 64, 0.0, 1.0),  # E (highest)
        pretty_midi.Note(100, 67, 0.0, 1.0),  # G
        pretty_midi.Note(100, 69, 1.0, 2.0),  # A (next)
    ]
    
    monophonic = reduce_polyphony(notes)
    
    assert len(monophonic) == 2  # Should keep only 2 notes
    assert monophonic[0].pitch == 67  # Highest from first chord (G)
    assert monophonic[1].pitch == 69  # Second note (A)


def test_add_bass_notes():
    """Test bass note generation"""
    melody_notes = [
        pretty_midi.Note(100, 60, 0.0, 1.0),
        pretty_midi.Note(100, 64, 1.0, 2.0),
    ]
    
    bass = add_bass_notes(melody_notes, style="root")
    
    assert len(bass) > 0
    assert all(note.pitch < 48 for note in bass)  # Bass range


def test_add_chord_accompaniment():
    """Test chord generation"""
    melody_notes = [
        pretty_midi.Note(100, 60, 0.0, 2.0),
    ]
    
    chords = add_chord_accompaniment(melody_notes, style="block")
    
    assert len(chords) > 0  # Should generate some chord notes


if __name__ == '__main__':
    pytest.main([__file__, '-v'])


