import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/core/practice/model/practice_models.dart';
import 'package:shazapiano/core/practice/matching/note_matcher.dart';

void main() {
  group('NoteMatcher', () {
    late NoteMatcher matcher;

    setUp(() {
      matcher = NoteMatcher(
        windowMs: 200,
        pitchEquals: exactPitchMatch, // Start with simple exact match
      );
    });

    group('findBestMatch', () {
      test('Returns null if buffer is empty', () {
        final expected = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        final match = matcher.findBestMatch(expected, [], {});
        expect(match, isNull);
      });

      test('Returns null if all events are outside window', () {
        final expected = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        final buffer = [
          PlayedNoteEvent(
            midi: 60,
            tPlayedMs: 700.0, // 300ms early (outside ±200ms window)
            source: NoteSource.microphone,
          ),
          PlayedNoteEvent(
            midi: 60,
            tPlayedMs: 1300.0, // 300ms late (outside window)
            source: NoteSource.microphone,
          ),
        ];

        final match = matcher.findBestMatch(expected, buffer, {});
        expect(match, isNull);
      });

      test('Returns null if pitch mismatch', () {
        final expected = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        final buffer = [
          PlayedNoteEvent(
            midi: 61, // C# instead of C
            tPlayedMs: 1000.0,
            source: NoteSource.microphone,
          ),
        ];

        final match = matcher.findBestMatch(expected, buffer, {});
        expect(match, isNull);
      });

      test('Returns null if event already used (exclusivity)', () {
        final expected = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        final event = PlayedNoteEvent(
          midi: 60,
          tPlayedMs: 1000.0,
          source: NoteSource.microphone,
        );

        final buffer = [event];
        final alreadyUsed = {event.id};

        final match = matcher.findBestMatch(expected, buffer, alreadyUsed);
        expect(match, isNull);
      });

      test('Returns closest dt candidate', () {
        final expected = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        final eventA = PlayedNoteEvent(
          id: 'event-a',
          midi: 60,
          tPlayedMs: 950.0, // dt = -50ms
          source: NoteSource.microphone,
        );

        final eventB = PlayedNoteEvent(
          id: 'event-b',
          midi: 60,
          tPlayedMs: 980.0, // dt = -20ms ← BEST (closest)
          source: NoteSource.microphone,
        );

        final eventC = PlayedNoteEvent(
          id: 'event-c',
          midi: 60,
          tPlayedMs: 1100.0, // dt = +100ms
          source: NoteSource.microphone,
        );

        final buffer = [eventA, eventB, eventC];

        final match = matcher.findBestMatch(expected, buffer, {});
        expect(match, isNotNull);
        expect(match!.playedId, eventB.id);
        expect(match.dtMs, -20.0);
        expect(match.absDtMs, 20.0);
      });

      test('Exclusivity: same event cannot match twice', () {
        final expected1 = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        final expected2 = const ExpectedNote(
          index: 1,
          midi: 60,
          tExpectedMs: 1010.0, // Very close to expected1
        );

        final event = PlayedNoteEvent(
          midi: 60,
          tPlayedMs: 1000.0,
          source: NoteSource.microphone,
        );

        final buffer = [event];

        // First match succeeds
        final match1 = matcher.findBestMatch(expected1, buffer, {});
        expect(match1, isNotNull);
        expect(match1!.playedId, event.id);

        // Second match with same event: fails (already consumed)
        final match2 = matcher.findBestMatch(
          expected2,
          buffer,
          {event.id},
        );
        expect(match2, isNull);
      });

      test('Window boundary: exactly at edge (inclusive)', () {
        final expected = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        // Event exactly at window start (1000 - 200 = 800ms)
        final eventStart = PlayedNoteEvent(
          id: 'event-start',
          midi: 60,
          tPlayedMs: 800.0,
          source: NoteSource.microphone,
        );

        // Event exactly at window end (1000 + 200 = 1200ms)
        final eventEnd = PlayedNoteEvent(
          id: 'event-end',
          midi: 60,
          tPlayedMs: 1200.0,
          source: NoteSource.microphone,
        );

        final buffer = [eventStart, eventEnd];

        // Both should be matched (window is inclusive)
        final matchStart = matcher.findBestMatch(expected, buffer, {});
        expect(matchStart, isNotNull);

        final matchEnd = matcher.findBestMatch(expected, buffer, {eventStart.id});
        expect(matchEnd, isNotNull);
        expect(matchEnd!.playedId, eventEnd.id);
      });

      test('Multiple expected notes competing for same event', () {
        // This test validates that the matcher itself is stateless
        // and that exclusivity tracking is external

        final expected1 = const ExpectedNote(
          index: 0,
          midi: 60,
          tExpectedMs: 1000.0,
        );

        final expected2 = const ExpectedNote(
          index: 1,
          midi: 60,
          tExpectedMs: 1050.0,
        );

        final event = PlayedNoteEvent(
          midi: 60,
          tPlayedMs: 1025.0, // Midway between both expected notes
          source: NoteSource.microphone,
        );

        final buffer = [event];

        // expected1: dt = 1025 - 1000 = +25ms
        final match1 = matcher.findBestMatch(expected1, buffer, {});
        expect(match1, isNotNull);
        expect(match1!.absDtMs, 25.0);

        // expected2: dt = 1025 - 1050 = -25ms (also good)
        final match2 = matcher.findBestMatch(expected2, buffer, {});
        expect(match2, isNotNull);
        expect(match2!.absDtMs, 25.0);

        // First-come-first-served: whoever matches first consumes the event
        // External code must track which was processed first
      });
    });

    group('indexBufferByPitch', () {
      test('Groups events by pitch class', () {
        final buffer = [
          PlayedNoteEvent(midi: 60, tPlayedMs: 1000.0, source: NoteSource.microphone), // C
          PlayedNoteEvent(midi: 72, tPlayedMs: 1100.0, source: NoteSource.microphone), // C (octave higher)
          PlayedNoteEvent(midi: 61, tPlayedMs: 1200.0, source: NoteSource.microphone), // C#
          PlayedNoteEvent(midi: 62, tPlayedMs: 1300.0, source: NoteSource.microphone), // D
        ];

        final indexed = matcher.indexBufferByPitch(buffer);

        expect(indexed[0]?.length, 2); // C (60, 72)
        expect(indexed[1]?.length, 1); // C# (61)
        expect(indexed[2]?.length, 1); // D (62)
        expect(indexed[3], isNull); // No D#
      });

      test('Handles empty buffer', () {
        final indexed = matcher.indexBufferByPitch([]);
        expect(indexed, isEmpty);
      });
    });

    group('Pitch comparators', () {
      test('micPitchMatch: pitch class must match', () {
        // Same pitch class, same octave
        expect(micPitchMatch(60, 60), isTrue); // C4 == C4

        // Same pitch class, different octave (within tolerance)
        expect(micPitchMatch(60, 72), isTrue); // C4 vs C5 (+12)
        expect(micPitchMatch(72, 60), isTrue); // C5 vs C4 (-12)
        expect(micPitchMatch(60, 48), isTrue); // C4 vs C3 (-12)
        expect(micPitchMatch(60, 84), isTrue); // C4 vs C6 (+24)

        // Different pitch class
        expect(micPitchMatch(60, 61), isFalse); // C4 vs C#4
        expect(micPitchMatch(60, 62), isFalse); // C4 vs D4
      });

      test('micPitchMatch: distance ≤3 tolerance (same pitch class only)', () {
        // Tolerance is applied AFTER pitch class match
        // C4 (60, PC=0) can match other C notes (PC=0) with distance ≤3
        
        // Direct: C4 (60) with tolerance ±3
        expect(micPitchMatch(60, 57), isFalse); // A3 (PC=9) → different PC
        expect(micPitchMatch(60, 63), isFalse); // D#4 (PC=3) → different PC
        
        // C4 (60) vs C3 (48): distance = 12, but with octave shift → 0
        expect(micPitchMatch(60, 48), isTrue); // C3, exact octave match
        
        // C4 (60) vs B2 (47): PC=11 ≠ 0 → false
        expect(micPitchMatch(60, 47), isFalse);
        
        // C4 (60) vs C#3 (49): PC=1 ≠ 0 → false
        expect(micPitchMatch(60, 49), isFalse);
        
        // C4 (60) vs C2 (36): distance = 24, with -24 shift → 0, exact
        expect(micPitchMatch(60, 36), isTrue);
        
        // Edge case: C4 (60) vs G2 (43)
        // PC: 43%12=7 ≠ 0 → false
        expect(micPitchMatch(60, 43), isFalse);
        
        // The ±3 tolerance allows slight detuning in real piano
        // but this is tested at the MIDI level, not frequency
        // In practice, detected MIDI is already rounded, so tolerance
        // comes from the mic_engine's distance check
      });

      test('midiPitchMatch: distance ≤1 semitone', () {
        expect(midiPitchMatch(60, 60), isTrue); // C4 == C4
        expect(midiPitchMatch(60, 59), isTrue); // C4 vs B3 (-1)
        expect(midiPitchMatch(60, 61), isTrue); // C4 vs C#4 (+1)
        expect(midiPitchMatch(60, 58), isFalse); // C4 vs Bb3 (-2)
        expect(midiPitchMatch(60, 62), isFalse); // C4 vs D4 (+2)
      });

      test('exactPitchMatch: only exact match', () {
        expect(exactPitchMatch(60, 60), isTrue);
        expect(exactPitchMatch(60, 59), isFalse);
        expect(exactPitchMatch(60, 61), isFalse);
        expect(exactPitchMatch(60, 72), isFalse); // Different octave
      });
    });

    group('Integration: matcher with micPitchMatch', () {
      test('Matches across octaves with pitch class comparator', () {
        final matcherMic = NoteMatcher(
          windowMs: 200,
          pitchEquals: micPitchMatch,
        );

        final expected = const ExpectedNote(
          index: 0,
          midi: 60, // C4
          tExpectedMs: 1000.0,
        );

        final buffer = [
          PlayedNoteEvent(
            midi: 72, // C5 (octave higher)
            tPlayedMs: 1000.0,
            source: NoteSource.microphone,
          ),
        ];

        final match = matcherMic.findBestMatch(expected, buffer, {});
        expect(match, isNotNull);
        expect(match!.absDtMs, 0.0); // Perfect timing
      });

      test('Rejects different pitch class', () {
        final matcherMic = NoteMatcher(
          windowMs: 200,
          pitchEquals: micPitchMatch,
        );

        final expected = const ExpectedNote(
          index: 0,
          midi: 60, // C4
          tExpectedMs: 1000.0,
        );

        final buffer = [
          PlayedNoteEvent(
            midi: 61, // C#4 (different pitch class)
            tPlayedMs: 1000.0,
            source: NoteSource.microphone,
          ),
        ];

        final match = matcherMic.findBestMatch(expected, buffer, {});
        expect(match, isNull);
      });
    });
  });
}
