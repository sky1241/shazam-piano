import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../pitch/decision_arbiter.dart';

/// Statistiques analysées d'une session de pratique.
class SessionStats {
  const SessionStats({
    required this.totalHits,
    required this.totalMisses,
    required this.totalWrongs,
    required this.totalSkips,
    required this.sessionDurationMs,
    required this.wrongByReason,
    required this.skipByReason,
    required this.gateBreakdown,
    this.avgDtMs,
    this.dtStdDev,
    this.avgConfidence,
  });

  /// Nombre de HIT (notes correctement détectées).
  final int totalHits;

  /// Nombre de MISS (notes manquées).
  final int totalMisses;

  /// Nombre de WRONG (mauvaises notes détectées).
  final int totalWrongs;

  /// Nombre de SKIP (décisions ignorées).
  final int totalSkips;

  /// Durée de la session en ms.
  final int sessionDurationMs;

  /// Breakdown des WRONG par raison.
  final Map<String, int> wrongByReason;

  /// Breakdown des SKIP par raison.
  final Map<String, int> skipByReason;

  /// Breakdown des gates (TTL, cooldown, sustain, etc.).
  final GateBreakdown gateBreakdown;

  /// Timing moyen des HIT (dt en ms, null si pas de données).
  final double? avgDtMs;

  /// Écart-type du timing (null si pas de données).
  final double? dtStdDev;

  /// Confiance moyenne des détections.
  final double? avgConfidence;

  /// Total des événements (hors SKIP).
  int get totalEvents => totalHits + totalMisses + totalWrongs;

  /// Taux de détection (hits / (hits + misses)).
  double get detectionRate {
    final total = totalHits + totalMisses;
    if (total == 0) return 0.0;
    return totalHits / total;
  }

  /// Taux d'erreur (wrongs / total events).
  double get errorRate {
    if (totalEvents == 0) return 0.0;
    return totalWrongs / totalEvents;
  }

  /// Score global de la session (0.0-1.0).
  /// Basé sur: 70% detection rate + 30% (1 - error rate).
  double get sessionScore {
    return (detectionRate * 0.7) + ((1.0 - errorRate) * 0.3);
  }

  /// La session est-elle valide pour l'apprentissage ?
  /// Requiert un minimum d'événements.
  bool get isValidForLearning => totalEvents >= 10;

  @override
  String toString() {
    return 'SessionStats(hits=$totalHits, misses=$totalMisses, wrongs=$totalWrongs, '
        'detectionRate=${(detectionRate * 100).toStringAsFixed(1)}%, '
        'errorRate=${(errorRate * 100).toStringAsFixed(1)}%, '
        'score=${(sessionScore * 100).toStringAsFixed(1)}%)';
  }
}

/// Breakdown des gates qui ont bloqué des décisions.
class GateBreakdown {
  const GateBreakdown({
    required this.ttl,
    required this.cooldown,
    required this.sustain,
    required this.lookahead,
    required this.perTick,
    required this.hitBlocks,
    required this.triple,
    required this.perMidi,
    required this.grace,
    required this.confirm,
  });

  final int ttl;
  final int cooldown;
  final int sustain;
  final int lookahead;
  final int perTick;
  final int hitBlocks;
  final int triple;
  final int perMidi;
  final int grace;
  final int confirm;

  int get total =>
      ttl +
      cooldown +
      sustain +
      lookahead +
      perTick +
      hitBlocks +
      triple +
      perMidi +
      grace +
      confirm;

  factory GateBreakdown.fromArbiterStats(ArbiterStats stats) {
    return GateBreakdown(
      ttl: stats.gatedByTTL,
      cooldown: stats.gatedByCooldown,
      sustain: stats.gatedBySustain,
      lookahead: stats.gatedByLookahead,
      perTick: stats.gatedByPerTick,
      hitBlocks: stats.gatedByHitBlocks,
      triple: stats.gatedByTriple,
      perMidi: stats.gatedByPerMidi,
      grace: stats.gatedByGrace,
      confirm: stats.gatedByConfirm,
    );
  }
}

/// Ajustements recommandés pour les paramètres.
class ParameterAdjustments {
  const ParameterAdjustments({
    required this.rmsMultiplierDelta,
    required this.latencyDeltaMs,
    required this.clarityDelta,
    required this.reasons,
  });

  /// Delta pour le multiplicateur RMS (ex: -0.05 = -5%).
  final double rmsMultiplierDelta;

  /// Delta pour la compensation de latence (ms).
  final double latencyDeltaMs;

  /// Delta pour le seuil de clarté.
  final double clarityDelta;

  /// Raisons des ajustements.
  final List<AdjustmentReason> reasons;

  /// Aucun ajustement nécessaire.
  bool get isEmpty =>
      rmsMultiplierDelta == 0 && latencyDeltaMs == 0 && clarityDelta == 0;

  /// Tous les ajustements sont nuls.
  factory ParameterAdjustments.none() {
    return const ParameterAdjustments(
      rmsMultiplierDelta: 0,
      latencyDeltaMs: 0,
      clarityDelta: 0,
      reasons: [AdjustmentReason.stablePerformance],
    );
  }

  @override
  String toString() {
    return 'ParameterAdjustments(rms=${rmsMultiplierDelta.toStringAsFixed(3)}, '
        'latency=${latencyDeltaMs.toStringAsFixed(1)}ms, '
        'clarity=${clarityDelta.toStringAsFixed(3)}, '
        'reasons=$reasons)';
  }
}

/// Raison d'un ajustement de paramètre.
enum AdjustmentReason {
  /// Trop de MISS → baisser rmsThreshold.
  highMissRate,

  /// Trop de WRONG → augmenter clarityThreshold.
  highWrongRate,

  /// Beaucoup de gates sustain → augmenter sustainFilter.
  highSustainGates,

  /// Beaucoup de gates TTL → ajuster latency.
  highTTLGates,

  /// Session trop courte pour évaluer.
  insufficientData,

  /// Scores stables → pas d'ajustement.
  stablePerformance,
}

/// Analyseur de session de pratique.
///
/// Prend les statistiques brutes d'ArbiterStats et calcule
/// des métriques et ajustements recommandés.
class SessionAnalyzer {
  const SessionAnalyzer();

  /// Analyse une session à partir des stats de l'arbiter.
  SessionStats analyzeSession({
    required ArbiterStats arbiterStats,
    required Duration sessionDuration,
    List<double>? hitTimingDtMs,
    List<double>? confidences,
  }) {
    // Calculer les moyennes si disponibles
    double? avgDt;
    double? dtStdDev;
    double? avgConf;

    if (hitTimingDtMs != null && hitTimingDtMs.isNotEmpty) {
      avgDt = hitTimingDtMs.reduce((a, b) => a + b) / hitTimingDtMs.length;
      if (hitTimingDtMs.length > 1) {
        var variance = 0.0;
        for (final dt in hitTimingDtMs) {
          variance += (dt - avgDt) * (dt - avgDt);
        }
        dtStdDev = math.sqrt(variance / hitTimingDtMs.length);
      }
    }

    if (confidences != null && confidences.isNotEmpty) {
      avgConf = confidences.reduce((a, b) => a + b) / confidences.length;
    }

    return SessionStats(
      totalHits: arbiterStats.hitCount,
      totalMisses: arbiterStats.missCount,
      totalWrongs: arbiterStats.wrongCount,
      totalSkips: arbiterStats.skipCount,
      sessionDurationMs: sessionDuration.inMilliseconds,
      wrongByReason: Map.from(arbiterStats.wrongByReason),
      skipByReason: Map.from(arbiterStats.skipByReason),
      gateBreakdown: GateBreakdown.fromArbiterStats(arbiterStats),
      avgDtMs: avgDt,
      dtStdDev: dtStdDev,
      avgConfidence: avgConf,
    );
  }

  /// Recommande des ajustements basés sur les statistiques de session.
  ParameterAdjustments recommendAdjustments({
    required SessionStats stats,
    required AdaptiveParameterLimits limits,
  }) {
    // Vérifier si on a assez de données
    if (!stats.isValidForLearning) {
      if (kDebugMode) {
        debugPrint(
          'SessionAnalyzer: Insufficient data (${stats.totalEvents} events)',
        );
      }
      return const ParameterAdjustments(
        rmsMultiplierDelta: 0,
        latencyDeltaMs: 0,
        clarityDelta: 0,
        reasons: [AdjustmentReason.insufficientData],
      );
    }

    final reasons = <AdjustmentReason>[];
    var rmsAdjust = 0.0;
    var latencyAdjust = 0.0;
    var clarityAdjust = 0.0;

    // Règle 1: Si missRate > 30% → baisser rmsThreshold de 5%
    final missRate = stats.totalMisses / (stats.totalHits + stats.totalMisses);
    if (missRate > 0.30) {
      rmsAdjust = -0.05; // -5%
      reasons.add(AdjustmentReason.highMissRate);
      if (kDebugMode) {
        debugPrint(
          'SessionAnalyzer: High miss rate (${(missRate * 100).toStringAsFixed(1)}%) -> rms -5%',
        );
      }
    }

    // Règle 2: Si errorRate > 20% → augmenter clarityThreshold de 0.02
    if (stats.errorRate > 0.20) {
      clarityAdjust = 0.02;
      reasons.add(AdjustmentReason.highWrongRate);
      if (kDebugMode) {
        debugPrint(
          'SessionAnalyzer: High wrong rate (${(stats.errorRate * 100).toStringAsFixed(1)}%) -> clarity +0.02',
        );
      }
    }

    // Règle 3: Si beaucoup de gates sustain → indicateur mais pas d'ajustement auto
    final sustainGateRatio =
        stats.gateBreakdown.sustain / math.max(1, stats.gateBreakdown.total);
    if (sustainGateRatio > 0.3) {
      reasons.add(AdjustmentReason.highSustainGates);
      if (kDebugMode) {
        debugPrint(
          'SessionAnalyzer: High sustain gates (${(sustainGateRatio * 100).toStringAsFixed(1)}%)',
        );
      }
    }

    // Règle 4: Si timing std dev > 100ms → ajuster latency compensation
    if (stats.dtStdDev != null && stats.dtStdDev! > 100) {
      // Ajuster de 10% de la moyenne
      if (stats.avgDtMs != null && stats.avgDtMs!.abs() > 50) {
        latencyAdjust = stats.avgDtMs! * 0.1;
        latencyAdjust = latencyAdjust.clamp(
          -limits.maxLatencyAdjustMs,
          limits.maxLatencyAdjustMs,
        );
        reasons.add(AdjustmentReason.highTTLGates);
        if (kDebugMode) {
          debugPrint(
            'SessionAnalyzer: High timing variance (${stats.dtStdDev!.toStringAsFixed(1)}ms) '
            '-> latency ${latencyAdjust > 0 ? '+' : ''}${latencyAdjust.toStringAsFixed(1)}ms',
          );
        }
      }
    }

    // Si aucun ajustement → stable
    if (rmsAdjust == 0 && latencyAdjust == 0 && clarityAdjust == 0) {
      reasons.add(AdjustmentReason.stablePerformance);
      if (kDebugMode) {
        debugPrint('SessionAnalyzer: Stable performance, no adjustments');
      }
    }

    // Borner les ajustements
    rmsAdjust = rmsAdjust.clamp(
      -limits.maxSessionDeltaPercent,
      limits.maxSessionDeltaPercent,
    );
    clarityAdjust = clarityAdjust.clamp(
      -limits.maxSessionDeltaPercent,
      limits.maxSessionDeltaPercent,
    );

    return ParameterAdjustments(
      rmsMultiplierDelta: rmsAdjust,
      latencyDeltaMs: latencyAdjust,
      clarityDelta: clarityAdjust,
      reasons: reasons,
    );
  }
}

/// Limites pour les ajustements adaptatifs.
class AdaptiveParameterLimits {
  const AdaptiveParameterLimits({
    this.maxSessionDeltaPercent = 0.10,
    this.maxCumulativeDeltaPercent = 0.50,
    this.minSessionsForAdjustment = 3,
    this.minSessionScore = 0.3,
    this.maxLatencyAdjustMs = 20.0,
  });

  /// Max ajustement par session (default: ±10%).
  final double maxSessionDeltaPercent;

  /// Max ajustement cumulé (default: ±50%).
  final double maxCumulativeDeltaPercent;

  /// Nombre minimum de sessions avant ajustement.
  final int minSessionsForAdjustment;

  /// Score minimum pour considérer la session valide.
  final double minSessionScore;

  /// Max ajustement de latence par session (ms).
  final double maxLatencyAdjustMs;
}
