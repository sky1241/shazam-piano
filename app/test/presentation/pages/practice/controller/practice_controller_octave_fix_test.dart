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
        scoringEngine: PracticeScoringEngine(
          config: const ScoringConfig(),
        ),
        matcher: NoteMatcher(
          windowMs: 300,
          pitchEquals: micPitchMatch,
        ),
        logger: logger,
      );
    });

    test('BUG #1: corrects microphone subharmonic (48 -> 60) to allow match', () {
      const sessionId = 's1';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000),
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Micro detects C3 (48) while expected is C4 (60)
      // Octave fix should correct 48→60 since pitch-class matches
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 48,
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
        reason: 'Octave fix should enable match',
      );
      expect(controller.state.scoringState.wrongCount, 0);
      expect(controller.state.scoringState.totalScore, greaterThan(0));

      final resolutions = logger.getResolutionLogsForSession(sessionId);
      expect(resolutions.length, 1);
      expect(
        resolutions.first.grade,
        isIn([HitGrade.perfect, HitGrade.good, HitGrade.ok]),
      );
    });

    test('BUG #1: does NOT correct octave if pitch-class does not match', () {
      const sessionId = 's2';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Play D3 (50): pitch-class different → no correction
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 50,
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Advance time beyond window to trigger MISS/WRONG
      controller.onTimeUpdate(1000 + 300 + 300 + 10);

      // Should NOT match (pitch-class mismatch)
      expect(controller.state.scoringState.missCount, 1);
      expect(controller.state.scoringState.totalScore, 0);
    });

    test('BUG #1: does NOT correct MIDI source events (only microphone)', () {
      const sessionId = 's3';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000),
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // MIDI source with 48 → should NOT be corrected
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 48,
          tPlayedMs: 1000,
          source: NoteSource.midi,
        ),
      );

      // Advance time
      controller.onTimeUpdate(1000 + 300 + 300 + 10);

      // Should MISS (MIDI not corrected)
      expect(controller.state.scoringState.missCount, 1);
    });

    test('BUG #2: near-miss pitch-class is logged as near-miss (not WRONG)', () {
      const sessionId = 's4';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // User plays octave above: C5 (72) - same pitch-class but distance=12
      // This should NOT correct (already within MIDI range), but reject matching
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 72,
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Advance time beyond window
      controller.onTimeUpdate(1000 + 300 + 300 + 10);

      // Expected note should be MISS (not matched)
      expect(controller.state.scoringState.missCount, 1);

      // Played note 72 should be logged as NEAR_MISS (not WRONG)
      expect(controller.state.scoringState.wrongCount, 0);

      final nearMisses = logger.getNearMissLogsForSession(sessionId);
      expect(nearMisses.length, 1);
      expect(nearMisses.first.pitchKey, 72);

      final wrongs = logger.getWrongNoteLogsForSession(sessionId);
      expect(wrongs, isEmpty);
    });

    test('BUG #2: truly wrong note (no pitch-class match) is still WRONG', () {
      const sessionId = 's5';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Play F# (66) - completely different pitch-class
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 66,
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Advance time
      controller.onTimeUpdate(1000 + 300 + 300 + 10);

      // Should be counted as WRONG (no pitch-class match)
      expect(controller.state.scoringState.wrongCount, 1);
      expect(controller.state.scoringState.missCount, 1);

      final wrongs = logger.getWrongNoteLogsForSession(sessionId);
      expect(wrongs.length, 1);
      expect(wrongs.first.pitchKey, 66);

      final nearMisses = logger.getNearMissLogsForSession(sessionId);
      expect(nearMisses, isEmpty);
    });

    test('BUG #1: corrects double octave down (36 -> 60) if needed', () {
      const sessionId = 's6';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000), // C4
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Extreme subharmonic: C2 (36) detected instead of C4 (60)
      // Fix should try +12 (48) then +24 (60) → match!
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 36,
          tPlayedMs: 1000,
          source: NoteSource.microphone,
        ),
      );

      // Should match with 60
      expect(
        controller.state.scoringState.perfectCount +
            controller.state.scoringState.goodCount +
            controller.state.scoringState.okCount,
        1,
      );
      expect(controller.state.scoringState.wrongCount, 0);
    });

    test('Summary includes nearMissCount', () {
      const sessionId = 's7';
      final expected = [
        ExpectedNote(index: 0, midi: 60, tExpectedMs: 1000),
        ExpectedNote(index: 1, midi: 62, tExpectedMs: 2000),
      ];

      controller.startPractice(sessionId: sessionId, expectedNotes: expected);

      // Note 1: near-miss (octave high)
      controller.onPlayedNote(
        PracticeController.createPlayedEvent(
          midi: 72,
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

      controller.onTimeUpdate(2000 + 300 + 300 + 10);

      final summary = logger.getSessionSummary(sessionId);
      expect(summary['nearMissCount'], 1);
      expect(summary['wrongCount'], 0);
      expect(summary['missCount'], 1);
    });
  });
}
