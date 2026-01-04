import pretty_midi

from arranger import build_expected_notes_payload


def _make_midi(notes):
    midi = pretty_midi.PrettyMIDI()
    instrument = pretty_midi.Instrument(program=0)
    instrument.notes.extend(notes)
    midi.instruments.append(instrument)
    return midi


def test_expected_notes_payload_splits_and_sorts():
    notes = [
        pretty_midi.Note(velocity=90, pitch=60, start=0.0, end=0.03),
        pretty_midi.Note(velocity=90, pitch=60, start=0.1, end=0.2),
        pretty_midi.Note(velocity=90, pitch=60, start=0.25, end=0.4),
        pretty_midi.Note(velocity=80, pitch=62, start=0.5, end=7.0),
    ]
    midi = _make_midi(notes)
    payload = build_expected_notes_payload(
        midi=midi,
        job_id="job",
        level=1,
        duration_sec=8.0,
        min_duration_ms=50,
        merge_gap_ms=80,
        max_duration_ms=6000,
    )
    out_notes = payload["notes"]
    assert payload["stats"]["notes_in"] == 4
    assert payload["stats"]["dropped_too_short"] == 1
    assert payload["stats"]["dropped_too_long"] == 1
    assert payload["stats"]["notes_out"] == 3
    starts = [note["start"] for note in out_notes]
    assert starts == sorted(starts)
    assert all(note["end"] > note["start"] for note in out_notes)
    assert all((note["end"] - note["start"]) <= 6.0 for note in out_notes)


def test_expected_notes_payload_clamps_to_duration():
    notes = [
        pretty_midi.Note(velocity=80, pitch=64, start=0.0, end=4.1),
        pretty_midi.Note(velocity=80, pitch=65, start=5.1, end=5.2),
    ]
    midi = _make_midi(notes)
    payload = build_expected_notes_payload(
        midi=midi,
        job_id="job",
        level=2,
        duration_sec=4.0,
        min_duration_ms=50,
        merge_gap_ms=80,
        max_duration_ms=6000,
    )
    out_notes = payload["notes"]
    assert len(out_notes) == 1
    assert abs(out_notes[0]["end"] - 4.0) < 1e-6
    assert payload["stats"]["clamped_to_duration"] == 1
