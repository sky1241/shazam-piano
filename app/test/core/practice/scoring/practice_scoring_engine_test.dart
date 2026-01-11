import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/core/practice/model/practice_models.dart';
import 'package:shazapiano/core/practice/scoring/practice_scoring_engine.dart';

void main() {
  group('PracticeScoringEngine', () {
    late PracticeScoringEngine engine;

    setUp(() {
      engine = PracticeScoringEngine(
        config: const ScoringConfig(
          perfectThresholdMs: 40,
          goodThresholdMs: 100,
          okThresholdMs: 200,
          enableWrongPenalty: false,
          wrongPenaltyPoints: -10,
          sustainMinFactor: 0.7,
        ),
      );
    });

    group('gradeFromDt - edge cases', () {
      test('Perfect boundary (≤40ms)', () {
        expect(engine.gradeFromDt(0), HitGrade.perfect);
        expect(engine.gradeFromDt(1), HitGrade.perfect);
        expect(engine.gradeFromDt(39), HitGrade.perfect);
        expect(engine.gradeFromDt(40), HitGrade.perfect); // Edge: exactly 40ms
      });

      test('Good boundary (41-100ms)', () {
        expect(
          engine.gradeFromDt(41),
          HitGrade.good,
        ); // Edge: just over perfect
        expect(engine.gradeFromDt(50), HitGrade.good);
        expect(engine.gradeFromDt(99), HitGrade.good);
        expect(engine.gradeFromDt(100), HitGrade.good); // Edge: exactly 100ms
      });

      test('OK boundary (101-200ms)', () {
        expect(engine.gradeFromDt(101), HitGrade.ok); // Edge: just over good
        expect(engine.gradeFromDt(150), HitGrade.ok);
        expect(engine.gradeFromDt(199), HitGrade.ok);
        expect(engine.gradeFromDt(200), HitGrade.ok); // Edge: exactly 200ms
      });

      test('Miss (>200ms)', () {
        expect(engine.gradeFromDt(201), HitGrade.miss); // Edge: just over ok
        expect(engine.gradeFromDt(300), HitGrade.miss);
        expect(engine.gradeFromDt(1000), HitGrade.miss);
      });
    });

    group('basePoints', () {
      test('Returns correct base points per grade', () {
        expect(engine.basePoints(HitGrade.perfect), 100);
        expect(engine.basePoints(HitGrade.good), 70);
        expect(engine.basePoints(HitGrade.ok), 40);
        expect(engine.basePoints(HitGrade.miss), 0);
        expect(engine.basePoints(HitGrade.wrong), 0);
      });
    });

    group('computeSustainFactor', () {
      test('Returns 1.0 if durExpected is null', () {
        expect(engine.computeSustainFactor(1000.0, null), 1.0);
      });

      test('Returns 1.0 if durExpected is ≤0', () {
        expect(engine.computeSustainFactor(1000.0, 0.0), 1.0);
        expect(engine.computeSustainFactor(1000.0, -100.0), 1.0);
      });

      test('Returns 1.0 if durPlayed is null', () {
        expect(engine.computeSustainFactor(null, 1000.0), 1.0);
      });

      test('Returns 1.0 for perfect duration match', () {
        expect(engine.computeSustainFactor(1000.0, 1000.0), 1.0);
      });

      test('Clamps to sustainMinFactor (0.7) for large errors', () {
        // Very short held duration
        final factor1 = engine.computeSustainFactor(100.0, 1000.0);
        expect(factor1, greaterThanOrEqualTo(0.7));
        expect(factor1, lessThan(1.0));

        // Very long held duration
        final factor2 = engine.computeSustainFactor(2000.0, 1000.0);
        expect(factor2, greaterThanOrEqualTo(0.7));
        expect(factor2, lessThan(1.0));
      });

      test('Returns value in [0.7, 1.0] for moderate errors', () {
        final factor = engine.computeSustainFactor(800.0, 1000.0);
        expect(factor, greaterThanOrEqualTo(0.7));
        expect(factor, lessThanOrEqualTo(1.0));
      });
    });

    group('computeMultiplier - combo cap', () {
      test('Combo 0-9 → 1.0x', () {
        expect(engine.computeMultiplier(0), 1.0);
        expect(engine.computeMultiplier(5), 1.0);
        expect(engine.computeMultiplier(9), 1.0);
      });

      test('Combo 10-19 → 1.1x', () {
        expect(engine.computeMultiplier(10), 1.1);
        expect(engine.computeMultiplier(15), 1.1);
        expect(engine.computeMultiplier(19), 1.1);
      });

      test('Combo 20-29 → 1.2x', () {
        expect(engine.computeMultiplier(20), 1.2);
        expect(engine.computeMultiplier(25), 1.2);
        expect(engine.computeMultiplier(29), 1.2);
      });

      test('Combo 30-39 → 1.3x', () {
        expect(engine.computeMultiplier(30), 1.3);
        expect(engine.computeMultiplier(39), 1.3);
      });

      test('Combo 100+ → 2.0x (cap)', () {
        expect(engine.computeMultiplier(100), 2.0);
        expect(engine.computeMultiplier(150), 2.0);
        expect(engine.computeMultiplier(200), 2.0); // Cap even at 200
        expect(engine.computeMultiplier(1000), 2.0);
      });
    });

    group('computeFinalPoints', () {
      test('Perfect + no combo + perfect sustain', () {
        final points = engine.computeFinalPoints(HitGrade.perfect, 0, 1.0);
        expect(points, 100); // 100 * 1.0 * 1.0 = 100
      });

      test('Perfect + combo 10 + perfect sustain', () {
        final points = engine.computeFinalPoints(HitGrade.perfect, 10, 1.0);
        expect(points, 110); // 100 * 1.0 * 1.1 = 110
      });

      test('Perfect + combo 100 + perfect sustain (cap)', () {
        final points = engine.computeFinalPoints(HitGrade.perfect, 100, 1.0);
        expect(points, 200); // 100 * 1.0 * 2.0 = 200 (cap)
      });

      test('Good + combo 20 + sustain 0.9', () {
        final points = engine.computeFinalPoints(HitGrade.good, 20, 0.9);
        expect(points, 76); // 70 * 0.9 * 1.2 = 75.6 → 76 (rounded)
      });

      test('OK + no combo + sustain 0.8', () {
        final points = engine.computeFinalPoints(HitGrade.ok, 0, 0.8);
        expect(points, 32); // 40 * 0.8 * 1.0 = 32
      });

      test('Miss always 0 points', () {
        expect(engine.computeFinalPoints(HitGrade.miss, 0, 1.0), 0);
        expect(engine.computeFinalPoints(HitGrade.miss, 100, 1.0), 0);
      });

      test('Wrong always 0 points', () {
        expect(engine.computeFinalPoints(HitGrade.wrong, 0, 1.0), 0);
        expect(engine.computeFinalPoints(HitGrade.wrong, 100, 1.0), 0);
      });
    });

    group('applyResolution', () {
      test('Perfect hit increments combo and counts', () {
        final state = PracticeScoringState();
        final resolution = NoteResolution(
          expectedIndex: 0,
          grade: HitGrade.perfect,
          dtMs: 20.0,
          pointsAdded: 100,
          matchedPlayedId: 'test-id',
          sustainFactor: 1.0,
        );

        engine.applyResolution(state, resolution);

        expect(state.totalScore, 100);
        expect(state.combo, 1);
        expect(state.maxCombo, 1);
        expect(state.perfectCount, 1);
        expect(state.timingAbsDtSum, 20.0);
        expect(state.sustainFactorSum, 1.0);
      });

      test('Multiple hits increment combo correctly', () {
        final state = PracticeScoringState();

        for (var i = 0; i < 5; i++) {
          final resolution = NoteResolution(
            expectedIndex: i,
            grade: HitGrade.good,
            dtMs: 50.0,
            pointsAdded: 70,
            matchedPlayedId: 'test-id-$i',
            sustainFactor: 1.0,
          );
          engine.applyResolution(state, resolution);
        }

        expect(state.combo, 5);
        expect(state.maxCombo, 5);
        expect(state.goodCount, 5);
        expect(state.totalScore, 350); // 5 * 70
      });

      test('Miss resets combo', () {
        final state = PracticeScoringState(combo: 10, maxCombo: 10);

        final resolution = NoteResolution(
          expectedIndex: 0,
          grade: HitGrade.miss,
          dtMs: null,
          pointsAdded: 0,
          matchedPlayedId: null,
          sustainFactor: 1.0,
        );

        engine.applyResolution(state, resolution);

        expect(state.combo, 0); // Reset
        expect(state.maxCombo, 10); // Preserved
        expect(state.missCount, 1);
        expect(state.totalScore, 0);
      });

      test('Wrong resets combo', () {
        final state = PracticeScoringState(combo: 15, maxCombo: 15);

        final resolution = NoteResolution(
          expectedIndex: 0,
          grade: HitGrade.wrong,
          dtMs: null,
          pointsAdded: 0,
          matchedPlayedId: null,
          sustainFactor: 1.0,
        );

        engine.applyResolution(state, resolution);

        expect(state.combo, 0); // Reset
        expect(state.maxCombo, 15); // Preserved
        expect(state.wrongCount, 1);
      });

      test('Tracks max combo correctly', () {
        final state = PracticeScoringState();

        // Build combo to 10
        for (var i = 0; i < 10; i++) {
          final resolution = NoteResolution(
            expectedIndex: i,
            grade: HitGrade.perfect,
            dtMs: 10.0,
            pointsAdded: 100,
            matchedPlayedId: 'test-$i',
            sustainFactor: 1.0,
          );
          engine.applyResolution(state, resolution);
        }

        expect(state.combo, 10);
        expect(state.maxCombo, 10);

        // Miss (reset combo)
        engine.applyResolution(
          state,
          const NoteResolution(
            expectedIndex: 10,
            grade: HitGrade.miss,
            pointsAdded: 0,
          ),
        );

        expect(state.combo, 0);
        expect(state.maxCombo, 10); // Still 10

        // Build combo to 5 (not exceeding 10)
        for (var i = 0; i < 5; i++) {
          final resolution = NoteResolution(
            expectedIndex: 11 + i,
            grade: HitGrade.good,
            dtMs: 50.0,
            pointsAdded: 70,
            matchedPlayedId: 'test2-$i',
            sustainFactor: 1.0,
          );
          engine.applyResolution(state, resolution);
        }

        expect(state.combo, 5);
        expect(state.maxCombo, 10); // Still 10, not 5
      });
    });

    group('applyWrongNotePenalty', () {
      test('With penalty enabled: subtracts points and resets combo', () {
        final engineWithPenalty = PracticeScoringEngine(
          config: const ScoringConfig(
            enableWrongPenalty: true,
            wrongPenaltyPoints: -10,
          ),
        );

        final state = PracticeScoringState(
          totalScore: 100,
          combo: 5,
          maxCombo: 5,
        );

        engineWithPenalty.applyWrongNotePenalty(state);

        expect(state.totalScore, 90); // 100 - 10
        expect(state.combo, 0); // Reset
        expect(state.wrongCount, 1);
      });

      test('With penalty disabled: only resets combo', () {
        final state = PracticeScoringState(
          totalScore: 100,
          combo: 5,
          maxCombo: 5,
        );

        engine.applyWrongNotePenalty(state);

        expect(state.totalScore, 100); // No change
        expect(state.combo, 0); // Reset
        expect(state.wrongCount, 1);
      });

      test('Prevents negative total score', () {
        final engineWithPenalty = PracticeScoringEngine(
          config: const ScoringConfig(
            enableWrongPenalty: true,
            wrongPenaltyPoints: -20,
          ),
        );

        final state = PracticeScoringState(totalScore: 10);

        engineWithPenalty.applyWrongNotePenalty(state);

        expect(state.totalScore, 0); // Clamped to 0, not -10
      });
    });

    group('Derived metrics', () {
      test('accuracyPitch calculation', () {
        final state = PracticeScoringState(
          perfectCount: 5,
          goodCount: 3,
          okCount: 2,
          missCount: 2,
        );

        expect(state.accuracyPitch, closeTo(0.833, 0.01)); // 10/12
      });

      test('timingAvgAbsMs calculation', () {
        final state = PracticeScoringState(
          perfectCount: 2,
          goodCount: 1,
          timingAbsDtSum: 150.0, // 50 + 50 + 50
        );

        expect(state.timingAvgAbsMs, closeTo(50.0, 0.01)); // 150 / 3
      });

      test('sustainAvgFactor calculation', () {
        final state = PracticeScoringState(
          perfectCount: 2,
          okCount: 1,
          sustainFactorSum: 2.7, // 0.9 + 0.9 + 0.9
        );

        expect(state.sustainAvgFactor, closeTo(0.9, 0.01)); // 2.7 / 3
      });
    });
  });
}
