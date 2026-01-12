import 'dart:math';
import '../model/practice_models.dart';

/// Configuration for scoring thresholds and penalties
class ScoringConfig {
  const ScoringConfig({
    this.perfectThresholdMs = 40,
    this.goodThresholdMs = 100,
    this.okThresholdMs = 300, // P0 #1 FIX: 200→300ms pour matcher windowMs=300
    this.enableWrongPenalty = false,
    this.wrongPenaltyPoints = -10,
    this.sustainMinFactor = 0.7,
  });

  final int perfectThresholdMs;
  final int goodThresholdMs;
  final int okThresholdMs;
  final bool enableWrongPenalty;
  final int wrongPenaltyPoints;
  final double sustainMinFactor;

  @override
  String toString() =>
      'ScoringConfig(perfect≤${perfectThresholdMs}ms, good≤${goodThresholdMs}ms, '
      'ok≤${okThresholdMs}ms, wrongPenalty=${enableWrongPenalty ? wrongPenaltyPoints : "disabled"}, '
      'sustainMin=$sustainMinFactor)';
}

/// Pure Dart scoring engine (no Flutter dependencies, 100% testable)
///
/// Handles:
/// - Hit grade calculation from timing delta
/// - Base points per grade
/// - Sustain factor calculation
/// - Combo multiplier with cap
/// - Final points calculation
/// - State updates (score, combo, counts)
class PracticeScoringEngine {
  PracticeScoringEngine({required this.config});

  final ScoringConfig config;

  /// Grade a note based on absolute timing delta (ms)
  ///
  /// CRITICAL: Test edge cases:
  /// - 39ms, 40ms, 41ms
  /// - 99ms, 100ms, 101ms
  /// - 199ms, 200ms, 201ms
  HitGrade gradeFromDt(int absDtMs) {
    if (absDtMs <= config.perfectThresholdMs) {
      return HitGrade.perfect;
    } else if (absDtMs <= config.goodThresholdMs) {
      return HitGrade.good;
    } else if (absDtMs <= config.okThresholdMs) {
      return HitGrade.ok;
    } else {
      return HitGrade.miss;
    }
  }

  /// Base points for a grade (before sustain & combo multiplier)
  int basePoints(HitGrade grade) {
    return switch (grade) {
      HitGrade.perfect => 100,
      HitGrade.good => 70,
      HitGrade.ok => 40,
      HitGrade.miss => 0,
      HitGrade.wrong => 0,
    };
  }

  /// Compute sustain factor from duration played vs expected
  ///
  /// Returns 1.0 if:
  /// - durExpected is null or ≤0 (duration not available)
  /// - durPlayed is null (not available)
  ///
  /// Otherwise:
  /// - Calculate duration error
  /// - Threshold = max(150ms, durExpected)
  /// - Factor = 1.0 - (error / threshold)
  /// - Clamp to [sustainMinFactor, 1.0]
  double computeSustainFactor(double? durPlayed, double? durExpected) {
    // Safety: no duration data available
    if (durExpected == null || durExpected <= 0 || durPlayed == null) {
      return 1.0;
    }

    final durErr = (durPlayed - durExpected).abs();
    final threshold = max(150.0, durExpected); // 150ms minimum threshold
    final factor = 1.0 - (durErr / threshold);

    return factor.clamp(config.sustainMinFactor, 1.0);
  }

  /// Compute combo multiplier with cap at 2.0x
  ///
  /// Formula: 1.0 + floor(combo/10) * 0.1
  ///
  /// Examples:
  /// - combo 0-9 → 1.0x
  /// - combo 10-19 → 1.1x
  /// - combo 20-29 → 1.2x
  /// - combo 100-109 → 2.0x (cap)
  /// - combo 200+ → 2.0x (cap)
  double computeMultiplier(int combo) {
    final mult = 1.0 + (combo ~/ 10) * 0.1;
    return min(mult, 2.0);
  }

  /// Compute final points for a note resolution
  ///
  /// Formula: basePoints * sustainFactor * comboMultiplier (rounded)
  int computeFinalPoints(HitGrade grade, int combo, double sustainFactor) {
    final base = basePoints(grade);
    final withSustain = base * sustainFactor;
    final mult = computeMultiplier(combo);
    final final_ = withSustain * mult;

    return final_.round();
  }

  /// Apply a resolution to the scoring state (mutates state)
  ///
  /// Updates:
  /// - totalScore
  /// - combo (increment or reset)
  /// - maxCombo (track maximum)
  /// - grade counts (perfectCount, goodCount, etc.)
  /// - timing sum (for average)
  /// - sustain sum (for average)
  void applyResolution(PracticeScoringState state, NoteResolution resolution) {
    // Add points
    state.totalScore += resolution.pointsAdded;

    // Update combo
    final isHit =
        resolution.grade == HitGrade.perfect ||
        resolution.grade == HitGrade.good ||
        resolution.grade == HitGrade.ok;

    if (isHit) {
      state.combo++;
      if (state.combo > state.maxCombo) {
        state.maxCombo = state.combo;
      }

      // Accumulate timing & sustain for averages
      if (resolution.dtMs != null) {
        state.timingAbsDtSum += resolution.dtMs!.abs();
      }
      state.sustainFactorSum += resolution.sustainFactor;
    } else {
      // Miss or Wrong: reset combo
      state.combo = 0;
    }

    // Update grade counts
    switch (resolution.grade) {
      case HitGrade.perfect:
        state.perfectCount++;
        break;
      case HitGrade.good:
        state.goodCount++;
        break;
      case HitGrade.ok:
        state.okCount++;
        break;
      case HitGrade.miss:
        state.missCount++;
        break;
      case HitGrade.wrong:
        state.wrongCount++;
        break;
    }
  }

  /// Apply a wrong note penalty (if enabled)
  ///
  /// Updates:
  /// - totalScore (add penalty points, usually negative)
  /// - combo (reset to 0)
  /// - wrongCount++
  void applyWrongNotePenalty(PracticeScoringState state) {
    if (config.enableWrongPenalty) {
      state.totalScore += config.wrongPenaltyPoints; // Usually negative
      // Prevent negative total score
      if (state.totalScore < 0) {
        state.totalScore = 0;
      }
    }

    state.combo = 0;
    state.wrongCount++;
  }
}
