import '../model/practice_models.dart';

/// Type alias for pitch comparison function
///
/// Returns true if two MIDI notes should be considered a match
typedef PitchComparator = bool Function(int pitch1, int pitch2);

/// Note matcher with optimized indexing and exclusivity
///
/// Features:
/// - Time window filtering (±windowMs)
/// - Pitch comparison via configurable PitchComparator
/// - Exclusivity (1 played event can only match 1 expected note)
/// - Performance: O(notes × events_in_pitch_bucket) instead of O(notes × all_events)
class NoteMatcher {
  NoteMatcher({required this.windowMs, required this.pitchEquals});

  final int windowMs;
  final PitchComparator pitchEquals;

  /// Find the best match for an expected note
  ///
  /// Returns:
  /// - MatchCandidate if a valid match is found
  /// - null if no match found (within window, correct pitch, not already used)
  ///
  /// Algorithm:
  /// 1. Filter buffer: t_played in [t_expected - window, t_expected + window]
  /// 2. Filter pitch: pitchEquals(played.midi, expected.midi)
  /// 3. Exclude already used IDs (alreadyUsedPlayedIds)
  /// 4. Select min |dt| = min |t_played - t_expected|
  MatchCandidate? findBestMatch(
    ExpectedNote expected,
    List<PlayedNoteEvent> buffer,
    Set<String> alreadyUsedPlayedIds,
  ) {
    final tExp = expected.tExpectedMs;
    final windowStart = tExp - windowMs;
    final windowEnd = tExp + windowMs;

    PlayedNoteEvent? bestEvent;
    double bestAbsDt = double.infinity;

    for (final event in buffer) {
      // Filter: time window
      if (event.tPlayedMs < windowStart || event.tPlayedMs > windowEnd) {
        continue;
      }

      // Filter: already used (exclusivity)
      if (alreadyUsedPlayedIds.contains(event.id)) {
        continue;
      }

      // Filter: pitch mismatch
      if (!pitchEquals(event.midi, expected.midi)) {
        continue;
      }

      // Select closest dt
      final dt = event.tPlayedMs - tExp;
      final absDt = dt.abs();
      if (absDt < bestAbsDt) {
        bestAbsDt = absDt;
        bestEvent = event;
      }
    }

    if (bestEvent == null) return null;

    final dt = bestEvent.tPlayedMs - tExp;
    return MatchCandidate(
      expectedIndex: expected.index,
      playedId: bestEvent.id,
      dtMs: dt,
    );
  }

  /// Index buffer by pitch key for faster lookup
  ///
  /// Groups events by pitch (modulo 12 for pitch class)
  ///
  /// Usage:
  /// ```dart
  /// final indexed = matcher.indexBufferByPitch(buffer);
  /// final eventsForPitchC = indexed[0] ?? []; // C = 0
  /// ```
  ///
  /// NOTE: Currently not used in findBestMatch (simple linear scan suffices
  /// for typical buffer sizes < 100 events). Can be enabled for optimization
  /// if profiling shows performance issues with large buffers.
  Map<int, List<PlayedNoteEvent>> indexBufferByPitch(
    List<PlayedNoteEvent> buffer,
  ) {
    final indexed = <int, List<PlayedNoteEvent>>{};

    for (final event in buffer) {
      final pitchClass = event.midi % 12;
      (indexed[pitchClass] ??= []).add(event);
    }

    return indexed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PITCH COMPARATORS (REUSED FROM EXISTING SYSTEM)
// ═══════════════════════════════════════════════════════════════════════════

/// Mic pitch comparator (MicEngine logic)
/// P0 SESSION4 FIX: Octave shifts DISABLED (harmonics prevention)
///
/// Comparison logic:
/// 1. Pitch class must match (midi % 12)
/// 2. Accept direct match if distance ≤3 semitones
///
/// Example:
/// - C4 (midi 60) matches C4 (60), C4±3 (57-63)
/// - C4 (60) does NOT match C#4 (61>3) or C3 (48, octave disabled)
bool micPitchMatch(int detected, int expected) {
  // Pitch class must match
  final detectedPC = detected % 12;
  final expectedPC = expected % 12;
  if (detectedPC != expectedPC) return false;

  // Test direct match ONLY (no octave shifts)
  final dist = (detected - expected).abs();
  return dist <= 3;
}

/// MIDI pitch comparator (existing MIDI handler logic)
///
/// Comparison logic:
/// - Distance ≤1 semitone (almost exact)
///
/// Example:
/// - C4 (60) matches C4 (60), B3 (59), C#4 (61)
/// - C4 (60) does NOT match A3 (57)
bool midiPitchMatch(int detected, int expected) {
  return (detected - expected).abs() <= 1;
}

/// Exact MIDI match (no tolerance)
///
/// Useful for strict matching scenarios
bool exactPitchMatch(int detected, int expected) {
  return detected == expected;
}
