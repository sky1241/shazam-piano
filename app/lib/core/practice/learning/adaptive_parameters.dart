import 'package:flutter/foundation.dart';

import '../persistence/calibration_storage.dart';
import '../pitch/calibrated_mic_engine.dart';
import 'session_analyzer.dart';

/// Paramètres adaptatifs qui évoluent avec l'apprentissage.
///
/// Ces paramètres sont des multiplicateurs/deltas appliqués sur
/// la configuration de base issue de la calibration.
class AdaptiveParameters {
  const AdaptiveParameters({
    required this.rmsMultiplier,
    required this.latencyDeltaMs,
    required this.clarityDelta,
    required this.sessionCount,
    required this.lastUpdated,
  });

  /// Multiplicateur pour absMinRms (ex: 0.95 = -5%).
  /// Plage: [0.5, 1.5] (±50% de la valeur de base).
  final double rmsMultiplier;

  /// Delta pour latencyCompensationMs.
  /// Plage: [-100, +100] ms.
  final double latencyDeltaMs;

  /// Delta pour clarityThreshold.
  /// Plage: [-0.15, +0.15].
  final double clarityDelta;

  /// Nombre de sessions analysées.
  final int sessionCount;

  /// Dernière mise à jour.
  final DateTime lastUpdated;

  /// Crée des paramètres neutres (aucun ajustement).
  factory AdaptiveParameters.neutral() {
    return AdaptiveParameters(
      rmsMultiplier: 1.0,
      latencyDeltaMs: 0.0,
      clarityDelta: 0.0,
      sessionCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  /// Crée depuis un DTO de persistance.
  factory AdaptiveParameters.fromDto(AdaptiveParametersDto dto) {
    return AdaptiveParameters(
      rmsMultiplier: dto.rmsMultiplier,
      latencyDeltaMs: dto.latencyDeltaMs,
      clarityDelta: dto.clarityDelta,
      sessionCount: dto.sessionCount,
      lastUpdated: DateTime.tryParse(dto.lastUpdatedIso) ?? DateTime.now(),
    );
  }

  /// Convertit en DTO pour persistance.
  AdaptiveParametersDto toDto() {
    return AdaptiveParametersDto(
      rmsMultiplier: rmsMultiplier,
      latencyDeltaMs: latencyDeltaMs,
      clarityDelta: clarityDelta,
      sessionCount: sessionCount,
      lastUpdatedIso: lastUpdated.toIso8601String(),
    );
  }

  /// Applique les ajustements sur une configuration de base.
  ///
  /// Retourne une nouvelle configuration avec les paramètres ajustés.
  CalibratedMicEngineConfig apply(CalibratedMicEngineConfig base) {
    // Appliquer le multiplicateur RMS
    final adjustedRms = base.absMinRms * rmsMultiplier;

    // Appliquer le delta de latence
    final adjustedLatency = base.latencyCompensationMs + latencyDeltaMs;

    // Appliquer le delta de clarté
    final adjustedClarity = (base.clarityThreshold + clarityDelta).clamp(0.5, 0.95);

    if (kDebugMode && (rmsMultiplier != 1.0 || latencyDeltaMs != 0 || clarityDelta != 0)) {
      debugPrint(
        'AdaptiveParameters.apply: rms ${base.absMinRms.toStringAsFixed(5)} '
        '-> ${adjustedRms.toStringAsFixed(5)} (×${rmsMultiplier.toStringAsFixed(2)}), '
        'latency ${base.latencyCompensationMs.toStringAsFixed(0)} '
        '-> ${adjustedLatency.toStringAsFixed(0)}ms, '
        'clarity ${base.clarityThreshold.toStringAsFixed(2)} '
        '-> ${adjustedClarity.toStringAsFixed(2)}',
      );
    }

    return CalibratedMicEngineConfig(
      headWindowSec: base.headWindowSec,
      tailWindowSec: base.tailWindowSec,
      absMinRms: adjustedRms,
      minConfForWrong: base.minConfForWrong,
      minConfForPitch: base.minConfForPitch,
      eventDebounceSec: base.eventDebounceSec,
      wrongFlashCooldownSec: base.wrongFlashCooldownSec,
      sustainFilterMs: base.sustainFilterMs,
      pitchWindowSize: base.pitchWindowSize,
      minPitchIntervalMs: base.minPitchIntervalMs,
      algorithm: base.algorithm,
      clarityThreshold: adjustedClarity,
      latencyCompensationMs: adjustedLatency,
    );
  }

  /// Fusionne avec les ajustements d'une nouvelle session.
  ///
  /// Les ajustements sont cumulatifs mais bornés par les limites.
  AdaptiveParameters merge(
    ParameterAdjustments adjustments, {
    AdaptiveParameterLimits limits = const AdaptiveParameterLimits(),
  }) {
    // Cumuler les ajustements
    var newRmsMultiplier = rmsMultiplier + adjustments.rmsMultiplierDelta;
    var newLatencyDelta = latencyDeltaMs + adjustments.latencyDeltaMs;
    var newClarityDelta = clarityDelta + adjustments.clarityDelta;

    // Borner les valeurs cumulées
    newRmsMultiplier = newRmsMultiplier.clamp(
      1.0 - limits.maxCumulativeDeltaPercent,
      1.0 + limits.maxCumulativeDeltaPercent,
    );
    newLatencyDelta = newLatencyDelta.clamp(-100.0, 100.0);
    newClarityDelta = newClarityDelta.clamp(-0.15, 0.15);

    if (kDebugMode) {
      debugPrint(
        'AdaptiveParameters.merge: rms ${rmsMultiplier.toStringAsFixed(3)} '
        '+ ${adjustments.rmsMultiplierDelta.toStringAsFixed(3)} '
        '-> ${newRmsMultiplier.toStringAsFixed(3)}, '
        'sessions ${sessionCount + 1}',
      );
    }

    return AdaptiveParameters(
      rmsMultiplier: newRmsMultiplier,
      latencyDeltaMs: newLatencyDelta,
      clarityDelta: newClarityDelta,
      sessionCount: sessionCount + 1,
      lastUpdated: DateTime.now(),
    );
  }

  /// Vérifie si les paramètres ont divergé trop loin de la baseline.
  ///
  /// Si true, il est recommandé de reset aux valeurs calibrées.
  bool get hasDivergedTooMuch {
    return (rmsMultiplier - 1.0).abs() > 0.45 ||
        latencyDeltaMs.abs() > 90 ||
        clarityDelta.abs() > 0.12;
  }

  @override
  String toString() {
    return 'AdaptiveParameters(rms×${rmsMultiplier.toStringAsFixed(2)}, '
        'latency${latencyDeltaMs >= 0 ? '+' : ''}${latencyDeltaMs.toStringAsFixed(0)}ms, '
        'clarity${clarityDelta >= 0 ? '+' : ''}${clarityDelta.toStringAsFixed(3)}, '
        'sessions=$sessionCount)';
  }
}

/// Service de gestion des paramètres adaptatifs.
///
/// Gère le chargement, la sauvegarde et l'application des paramètres
/// adaptatifs sur la configuration de base.
class AdaptiveParameterService {
  AdaptiveParameterService({
    required CalibrationStorage storage,
    this.limits = const AdaptiveParameterLimits(),
  }) : _storage = storage;

  final CalibrationStorage _storage;
  final AdaptiveParameterLimits limits;

  AdaptiveParameters? _cachedParams;

  /// Charge les paramètres adaptatifs depuis le stockage.
  Future<AdaptiveParameters> loadParameters() async {
    if (_cachedParams != null) {
      return _cachedParams!;
    }

    final dto = _storage.loadAdaptiveParameters();
    if (dto == null) {
      _cachedParams = AdaptiveParameters.neutral();
    } else {
      _cachedParams = AdaptiveParameters.fromDto(dto);
    }

    if (kDebugMode) {
      debugPrint('AdaptiveParameterService: Loaded $_cachedParams');
    }

    return _cachedParams!;
  }

  /// Obtient la configuration effective (base + ajustements).
  Future<CalibratedMicEngineConfig> getEffectiveConfig(
    CalibratedMicEngineConfig baseConfig,
  ) async {
    final params = await loadParameters();
    return params.apply(baseConfig);
  }

  /// Applique l'apprentissage d'une session.
  ///
  /// Analyse les stats, calcule les ajustements, et sauvegarde.
  Future<void> applySessionLearning({
    required SessionStats stats,
    SessionAnalyzer analyzer = const SessionAnalyzer(),
  }) async {
    // Vérifier si la session est valide pour l'apprentissage
    if (!stats.isValidForLearning) {
      if (kDebugMode) {
        debugPrint(
          'AdaptiveParameterService: Session not valid for learning '
          '(${stats.totalEvents} events)',
        );
      }
      return;
    }

    // Vérifier le score minimum
    if (stats.sessionScore < limits.minSessionScore) {
      if (kDebugMode) {
        debugPrint(
          'AdaptiveParameterService: Session score too low '
          '(${(stats.sessionScore * 100).toStringAsFixed(1)}%)',
        );
      }
      return;
    }

    // Charger les paramètres actuels
    final currentParams = await loadParameters();

    // Vérifier si on a assez de sessions
    if (currentParams.sessionCount < limits.minSessionsForAdjustment - 1) {
      // Juste incrémenter le compteur sans ajuster
      final updatedParams = AdaptiveParameters(
        rmsMultiplier: currentParams.rmsMultiplier,
        latencyDeltaMs: currentParams.latencyDeltaMs,
        clarityDelta: currentParams.clarityDelta,
        sessionCount: currentParams.sessionCount + 1,
        lastUpdated: DateTime.now(),
      );
      await _saveParameters(updatedParams);
      if (kDebugMode) {
        debugPrint(
          'AdaptiveParameterService: Session ${updatedParams.sessionCount} recorded, '
          'waiting for ${limits.minSessionsForAdjustment} sessions before adjusting',
        );
      }
      return;
    }

    // Calculer les ajustements
    final adjustments = analyzer.recommendAdjustments(
      stats: stats,
      limits: limits,
    );

    if (adjustments.isEmpty) {
      // Pas d'ajustement nécessaire, juste mettre à jour le compteur
      final updatedParams = AdaptiveParameters(
        rmsMultiplier: currentParams.rmsMultiplier,
        latencyDeltaMs: currentParams.latencyDeltaMs,
        clarityDelta: currentParams.clarityDelta,
        sessionCount: currentParams.sessionCount + 1,
        lastUpdated: DateTime.now(),
      );
      await _saveParameters(updatedParams);
      return;
    }

    // Appliquer les ajustements
    final newParams = currentParams.merge(adjustments, limits: limits);

    // Vérifier si les paramètres ont trop divergé
    if (newParams.hasDivergedTooMuch) {
      if (kDebugMode) {
        debugPrint(
          'AdaptiveParameterService: Parameters diverged too much, resetting',
        );
      }
      await resetToCalibration();
      return;
    }

    // Sauvegarder
    await _saveParameters(newParams);

    if (kDebugMode) {
      debugPrint('AdaptiveParameterService: Applied $adjustments -> $newParams');
    }
  }

  /// Reset les paramètres aux valeurs de calibration (neutres).
  Future<void> resetToCalibration() async {
    _cachedParams = AdaptiveParameters.neutral();
    await _saveParameters(_cachedParams!);
    if (kDebugMode) {
      debugPrint('AdaptiveParameterService: Reset to neutral parameters');
    }
  }

  /// Obtient les deltas cumulés actuels.
  Future<Map<String, double>> getCumulativeDeltas() async {
    final params = await loadParameters();
    return {
      'rmsMultiplier': params.rmsMultiplier,
      'latencyDeltaMs': params.latencyDeltaMs,
      'clarityDelta': params.clarityDelta,
    };
  }

  Future<void> _saveParameters(AdaptiveParameters params) async {
    _cachedParams = params;
    await _storage.saveAdaptiveParameters(params.toDto());
  }
}
