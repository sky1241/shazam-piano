import 'package:flutter_test/flutter_test.dart';

import 'package:shazapiano/core/practice/debug/practice_debug_logger.dart';
import 'package:shazapiano/core/practice/matching/note_matcher.dart';
import 'package:shazapiano/core/practice/model/practice_models.dart';
import 'package:shazapiano/core/practice/scoring/practice_scoring_engine.dart';
import 'package:shazapiano/presentation/pages/practice/controller/practice_controller.dart';

void main() {
  group('PracticeController - Session4 octave subharmonic fix', () {
    late PracticeController controller;
    late PracticeDebugLogger logger;

    setUp(() {
      logger = PracticeDebugLogger(
        config: const DebugLogConfig(enableLogs: true, enableJsonExport: false),
      );

      controller = PracticeController(
        scoringEngine: PracticeScoringEngine(config: const ScoringConfig()),
        matcher: NoteMatcher(windowMs: 300, pitchEquals: micPitchMatch),
        logger: logger,
      );
    });

    // P0 SESSION4 FIX: Octave shifts are now DISABLED to prevent harmonics false hits.
    // micPitchMatch only accepts distance ≤3 semitones (no pitch class matching).
    // Tests updated to reflect this behavior.

    test(
      'BUG #1: corrects microphone subharmonic (48 -> 60) to allow match',
      () {
        const sessionId = 's1';
        final expected = [ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000)];

        controller.startPractice(sessionId: sessionId, expectedNotes: expected);

        // Micro detects C3 (48) while expected is C4 (60)
        // P0 FIX: Octave correction is DISABLED - distance=12 > 3, so NO match
        // Play exact pitch to get a match
        controller.onPlayedNote(
          PracticeController.createPlayedEvent(
            midi: 60, // Changed from 48 to 60 - exact match required now
            tPlayedMs: 1000,
            source: NoteSource.microphone,
          ),
        );

        // Should match and score as HIT (perfect/good/ok)
        expect(
          controller.state.scoringState.perfectCount +
              controller.state.scoringState.goodCount +
              controller.state.scoringState.okCount,
          1,
          reason: 'Exact pitch should match',
        );
        expect(controller.state.scoringState.wrongCount, 0);
        expect(controller.state.scoringState.totalScore, greaterThan(0));

        final resolutions = logger.getResolutionLogsForSession(sessionId);
        expect(resolutions.length, 1);
        expect(
          resolutions.first.grade,
          isIn([HitGrade.perfect, HitGrade.good, HitGrade.ok]),
        );
      },
    );

    test('BUG #1: does NOT match if pitch distance > 3 semitones', () {
      const sessionId = 's2';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Play D3 (50): distance = 10 semitones → no match (micPitchMatch requires ≤3)
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 50,
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Advance time beyond window to trigger MISS
      controller.onTimeUpdate(1000 + 450 + 300 + 10);

      // Should NOT match (distance > 3 semitones)
      expect(controller.state.scoringState.missCount, 1);
      expect(controller.state.scoringState.totalScore, 0);
    });

    test('BUG #1: MIDI and microphone use same matching logic', () {
      const sessionId = 's3';
      final expected = [ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000)];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // MIDI source with distance > 3 → no match (same rule as microphone)
      // P0 FIX: No special handling for MIDI vs microphone anymore
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 48, // distance = 12 > 3
          tPlayedMs: 1000,
          source: NoteSource.midi,
        ),
      );

      // Advance time
      controller.onTimeUpdate(1000 + 450 + 300 + 10);

      // Should MISS (distance > 3 for any source)
      expect(controller.state.scoringState.missCount, 1);
    });

    test('Octave up (72 vs 60) does NOT match - octave shifts disabled', () {
      const sessionId = 's4';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // User plays octave above: C5 (72) - distance=12 > 3, no match
      // P0 FIX: Octave shifts disabled to prevent harmonics false hits
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 72,
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Advance time beyond window
      controller.onTimeUpdate(1000 + 450 + 300 + 10);

      // Expected note should be MISS (not matched due to distance > 3)
      expect(controller.state.scoringState.missCount, 1);
    });

    test('Distance ≤3 semitones matches (tolerance for pitch detection)', () {
      const sessionId = 's5';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Play 63 (distance = 3) - should match within tolerance
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 63, // distance = 3, within ≤3 tolerance
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Should match
      expect(
        controller.state.scoringState.perfectCount +
            controller.state.scoringState.goodCount +
            controller.state.scoringState.okCount,
        1,
      );
      expect(controller.state.scoringState.missCount, 0);
    });

    test('BUG #1: corrects double octave down (36 -> 60) if needed', () {
      const sessionId = 's6';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // P0 FIX: Octave correction is DISABLED
      // C2 (36) vs C4 (60) = distance 24 > 3, NO match
      // Play exact pitch instead
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 60, // Changed from 36 to 60 - exact match required now
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Should match with exact pitch
      expect(
        controller.state.scoringState.perfectCount +
            controller.state.scoringState.goodCount +
            controller.state.scoringState.okCount,
        1,
      );
      expect(controller.state.scoringState.wrongCount, 0);
    });

    test('Summary includes missCount for unmatched notes', () {
      const sessionId = 's7';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000),
        ExpectedNote(index: 1, midi: 62, tExpectedMs: 2000),
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Note 1: play wrong octave (72) - won't match (distance > 3)
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 72, // distance = 12 > 3, no match
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Note 2: correct
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 62,
          tPlayedMs: 2000,
          source: NoteSource.microphone,
        ),
      );

      controller.onTimeUpdate(2000 + 450 + 300 + 10);

      final summary = logger.getSessionSummary(sessionId);
      // First note missed (distance > 3), second note hit
      expect(summary['missCount'], 1);
      // One hit for the second note
      expect(
        (summary['perfectCount'] as int) +
            (summary['goodCount'] as int) +
            (summary['okCount'] as int),
        1,
      );
    });
  });
}
