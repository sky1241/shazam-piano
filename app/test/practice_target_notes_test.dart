import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/presentation/pages/practice/practice_test_api.dart';

void main() {
  test('effectiveElapsedForTest uses video time when available', () {
    final elapsed = effectiveElapsedForTest(
      isPracticeRunning: true,
      videoPosSec: 12.5,
      practiceClockSec: 1.0,
      videoSyncOffsetSec: 0.0,
    );

    expect(elapsed, 12.5);
  });

  test('resolveTargetNotesForTest returns active chord', () {
    final pitches = [60, 64, 67, 72];
    final starts = [0.0, 0.0, 1.0, 1.01];
    final ends = [0.6, 0.6, 1.6, 1.6];
    final hitNotes = [false, false, false, false];

    final result = resolveTargetNotesForTest(
      pitches: pitches,
      starts: starts,
      ends: ends,
      hitNotes: hitNotes,
      elapsedSec: 0.2,
      windowTailSec: 0.2,
      chordToleranceSec: 0.03,
    );

    expect(result, {60, 64});
  });

  test('resolveTargetNotesForTest returns next chord when none active', () {
    final pitches = [60, 64, 67];
    final starts = [1.0, 1.01, 2.0];
    final ends = [1.4, 1.4, 2.4];
    final hitNotes = [false, false, false];

    final result = resolveTargetNotesForTest(
      pitches: pitches,
      starts: starts,
      ends: ends,
      hitNotes: hitNotes,
      elapsedSec: 0.3,
      windowTailSec: 0.2,
      chordToleranceSec: 0.03,
    );

    expect(result, {60, 64});
  });

  test('normalizeNoteEventsForTest dedupes and filters out of range', () {
    final pitches = [60, 60, 61, 90];
    final starts = [0.0, 0.0, 0.1, 0.2];
    final ends = [0.5, 0.5, 0.6, 0.7];

    final result = normalizeNoteEventsForTest(
      pitches: pitches,
      starts: starts,
      ends: ends,
      firstKey: 60,
      lastKey: 72,
      epsilonSec: 0.001,
    );

    expect(result.totalCount, 4);
    expect(result.dedupedCount, 3);
    expect(result.filteredCount, 2);
    expect(result.events.map((e) => e[0]).toList(), [60, 61]);
  });
}
