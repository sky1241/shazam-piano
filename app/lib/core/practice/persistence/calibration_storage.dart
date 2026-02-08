import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../device_calibration.dart';
import '../pitch/mic_tuning.dart';
import '../pitch/pitch_services.dart';

/// Keys for SharedPreferences storage.
abstract class _StorageKeys {
  static const String calibrationResult = 'calibration_result_v1';
  static const String deviceTier = 'device_tier_v1';
  static const String reverbProfile = 'reverb_profile_v1';
  static const String adaptiveParams = 'adaptive_params_v1';
  static const String lastCalibrationTimestamp =
      'last_calibration_timestamp_v1';
}

/// DTO for serializing [CalibrationNoteMeasurement].
class CalibrationNoteMeasurementDto {
  const CalibrationNoteMeasurementDto({
    required this.expectedMidi,
    required this.detectedMidi,
    required this.detectedFreq,
    required this.latencyMs,
    required this.rmsAmplitude,
    required this.confidence,
  });

  final int expectedMidi;
  final int? detectedMidi;
  final double? detectedFreq;
  final double latencyMs;
  final double rmsAmplitude;
  final double confidence;

  factory CalibrationNoteMeasurementDto.fromMeasurement(
    CalibrationNoteMeasurement m,
  ) {
    return CalibrationNoteMeasurementDto(
      expectedMidi: m.expectedMidi,
      detectedMidi: m.detectedMidi,
      detectedFreq: m.detectedFreq,
      latencyMs: m.latencyMs,
      rmsAmplitude: m.rmsAmplitude,
      confidence: m.confidence,
    );
  }

  CalibrationNoteMeasurement toMeasurement() {
    return CalibrationNoteMeasurement(
      expectedMidi: expectedMidi,
      detectedMidi: detectedMidi,
      detectedFreq: detectedFreq,
      latencyMs: latencyMs,
      rmsAmplitude: rmsAmplitude,
      confidence: confidence,
    );
  }

  factory CalibrationNoteMeasurementDto.fromJson(Map<String, dynamic> json) {
    return CalibrationNoteMeasurementDto(
      expectedMidi: json['expectedMidi'] as int,
      detectedMidi: json['detectedMidi'] as int?,
      detectedFreq: (json['detectedFreq'] as num?)?.toDouble(),
      latencyMs: (json['latencyMs'] as num).toDouble(),
      rmsAmplitude: (json['rmsAmplitude'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'expectedMidi': expectedMidi,
      'detectedMidi': detectedMidi,
      'detectedFreq': detectedFreq,
      'latencyMs': latencyMs,
      'rmsAmplitude': rmsAmplitude,
      'confidence': confidence,
    };
  }
}

/// DTO for serializing [CalibrationResult].
class CalibrationResultDto {
  const CalibrationResultDto({
    required this.measurements,
    required this.avgLatencyMs,
    required this.latencyStdDev,
    required this.avgFreqOffset,
    required this.minRmsThreshold,
    required this.successRate,
    required this.recommendedAlgorithm,
    this.reverbProfile,
    this.roomDetectionConfidence,
  });

  final List<CalibrationNoteMeasurementDto> measurements;
  final double avgLatencyMs;
  final double latencyStdDev;
  final double avgFreqOffset;
  final double minRmsThreshold;
  final double successRate;
  final String recommendedAlgorithm;
  final String? reverbProfile;
  final double? roomDetectionConfidence;

  factory CalibrationResultDto.fromResult(CalibrationResult result) {
    return CalibrationResultDto(
      measurements: result.measurements
          .map(CalibrationNoteMeasurementDto.fromMeasurement)
          .toList(),
      avgLatencyMs: result.avgLatencyMs,
      latencyStdDev: result.latencyStdDev,
      avgFreqOffset: result.avgFreqOffset,
      minRmsThreshold: result.minRmsThreshold,
      successRate: result.successRate,
      recommendedAlgorithm: result.recommendedAlgorithm.name,
      reverbProfile: result.reverbProfile?.name,
      roomDetectionConfidence: result.roomDetectionConfidence,
    );
  }

  CalibrationResult toResult() {
    return CalibrationResult(
      measurements: measurements.map((m) => m.toMeasurement()).toList(),
      avgLatencyMs: avgLatencyMs,
      latencyStdDev: latencyStdDev,
      avgFreqOffset: avgFreqOffset,
      minRmsThreshold: minRmsThreshold,
      successRate: successRate,
      recommendedAlgorithm: _parseAlgorithm(recommendedAlgorithm),
      reverbProfile: _parseReverbProfile(reverbProfile),
      roomDetectionConfidence: roomDetectionConfidence,
    );
  }

  static PitchAlgorithm _parseAlgorithm(String name) {
    switch (name) {
      case 'yin':
        return PitchAlgorithm.yin;
      case 'mpm':
      default:
        return PitchAlgorithm.mpm;
    }
  }

  static ReverbProfile? _parseReverbProfile(String? name) {
    if (name == null) return null;
    switch (name) {
      case 'low':
        return ReverbProfile.low;
      case 'high':
        return ReverbProfile.high;
      case 'medium':
      default:
        return ReverbProfile.medium;
    }
  }

  factory CalibrationResultDto.fromJson(Map<String, dynamic> json) {
    return CalibrationResultDto(
      measurements: (json['measurements'] as List<dynamic>)
          .map(
            (m) => CalibrationNoteMeasurementDto.fromJson(
              m as Map<String, dynamic>,
            ),
          )
          .toList(),
      avgLatencyMs: (json['avgLatencyMs'] as num).toDouble(),
      latencyStdDev: (json['latencyStdDev'] as num).toDouble(),
      avgFreqOffset: (json['avgFreqOffset'] as num).toDouble(),
      minRmsThreshold: (json['minRmsThreshold'] as num).toDouble(),
      successRate: (json['successRate'] as num).toDouble(),
      recommendedAlgorithm: json['recommendedAlgorithm'] as String,
      reverbProfile: json['reverbProfile'] as String?,
      roomDetectionConfidence: (json['roomDetectionConfidence'] as num?)
          ?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'measurements': measurements.map((m) => m.toJson()).toList(),
      'avgLatencyMs': avgLatencyMs,
      'latencyStdDev': latencyStdDev,
      'avgFreqOffset': avgFreqOffset,
      'minRmsThreshold': minRmsThreshold,
      'successRate': successRate,
      'recommendedAlgorithm': recommendedAlgorithm,
      'reverbProfile': reverbProfile,
      'roomDetectionConfidence': roomDetectionConfidence,
    };
  }
}

/// DTO for serializing adaptive parameters (for learning brique).
class AdaptiveParametersDto {
  const AdaptiveParametersDto({
    required this.rmsMultiplier,
    required this.latencyDeltaMs,
    required this.clarityDelta,
    required this.sessionCount,
    required this.lastUpdatedIso,
  });

  /// Multiplicateur pour rmsThreshold (ex: 0.95 = -5%)
  final double rmsMultiplier;

  /// Delta pour compensation de latence (ms)
  final double latencyDeltaMs;

  /// Delta pour clarityThreshold
  final double clarityDelta;

  /// Nombre de sessions analysées
  final int sessionCount;

  /// ISO 8601 timestamp
  final String lastUpdatedIso;

  factory AdaptiveParametersDto.initial() {
    return AdaptiveParametersDto(
      rmsMultiplier: 1.0,
      latencyDeltaMs: 0.0,
      clarityDelta: 0.0,
      sessionCount: 0,
      lastUpdatedIso: DateTime.now().toIso8601String(),
    );
  }

  factory AdaptiveParametersDto.fromJson(Map<String, dynamic> json) {
    return AdaptiveParametersDto(
      rmsMultiplier: (json['rmsMultiplier'] as num?)?.toDouble() ?? 1.0,
      latencyDeltaMs: (json['latencyDeltaMs'] as num?)?.toDouble() ?? 0.0,
      clarityDelta: (json['clarityDelta'] as num?)?.toDouble() ?? 0.0,
      sessionCount: (json['sessionCount'] as int?) ?? 0,
      lastUpdatedIso:
          json['lastUpdatedIso'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rmsMultiplier': rmsMultiplier,
      'latencyDeltaMs': latencyDeltaMs,
      'clarityDelta': clarityDelta,
      'sessionCount': sessionCount,
      'lastUpdatedIso': lastUpdatedIso,
    };
  }

  AdaptiveParametersDto copyWith({
    double? rmsMultiplier,
    double? latencyDeltaMs,
    double? clarityDelta,
    int? sessionCount,
    String? lastUpdatedIso,
  }) {
    return AdaptiveParametersDto(
      rmsMultiplier: rmsMultiplier ?? this.rmsMultiplier,
      latencyDeltaMs: latencyDeltaMs ?? this.latencyDeltaMs,
      clarityDelta: clarityDelta ?? this.clarityDelta,
      sessionCount: sessionCount ?? this.sessionCount,
      lastUpdatedIso: lastUpdatedIso ?? this.lastUpdatedIso,
    );
  }
}

/// Service de persistance pour la calibration.
///
/// Sauvegarde et charge:
/// - [CalibrationResult] de la routine 9 notes
/// - [DeviceTier] détecté automatiquement
/// - [ReverbProfile] détecté ou choisi manuellement
/// - [AdaptiveParametersDto] ajustements cumulés de l'apprentissage
class CalibrationStorage {
  CalibrationStorage({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  /// Initialise le service. Doit être appelé avant toute autre méthode.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Vérifie si le service est initialisé.
  bool get isInitialized => _prefs != null;

  // ═══════════════════════════════════════════════════════════════════════════
  // CALIBRATION RESULT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sauvegarde le résultat de calibration.
  Future<bool> saveCalibrationResult(CalibrationResult result) async {
    _ensureInitialized();
    try {
      final dto = CalibrationResultDto.fromResult(result);
      final json = jsonEncode(dto.toJson());
      await _prefs!.setString(_StorageKeys.calibrationResult, json);
      await _prefs!.setString(
        _StorageKeys.lastCalibrationTimestamp,
        DateTime.now().toIso8601String(),
      );
      if (kDebugMode) {
        debugPrint(
          'CalibrationStorage: Saved calibration result (successRate=${result.successRate.toStringAsFixed(2)})',
        );
      }
      return true;
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to save calibration result: $e');
      return false;
    }
  }

  /// Charge le résultat de calibration.
  /// Retourne null si absent ou corrompu.
  CalibrationResult? loadCalibrationResult() {
    _ensureInitialized();
    try {
      final json = _prefs!.getString(_StorageKeys.calibrationResult);
      if (json == null) return null;
      final dto = CalibrationResultDto.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
      if (kDebugMode) {
        debugPrint(
          'CalibrationStorage: Loaded calibration result (successRate=${dto.successRate.toStringAsFixed(2)})',
        );
      }
      return dto.toResult();
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to load calibration result: $e');
      return null;
    }
  }

  /// Vérifie si la calibration est périmée.
  bool isCalibrationStale({Duration maxAge = const Duration(days: 30)}) {
    _ensureInitialized();
    try {
      final timestampStr = _prefs!.getString(
        _StorageKeys.lastCalibrationTimestamp,
      );
      if (timestampStr == null) return true;
      final timestamp = DateTime.parse(timestampStr);
      return DateTime.now().difference(timestamp) > maxAge;
    } catch (e) {
      return true;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DEVICE TIER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sauvegarde le device tier détecté.
  Future<bool> saveDeviceTier(DeviceTier tier) async {
    _ensureInitialized();
    try {
      await _prefs!.setString(_StorageKeys.deviceTier, tier.name);
      if (kDebugMode) {
        debugPrint('CalibrationStorage: Saved device tier: ${tier.name}');
      }
      return true;
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to save device tier: $e');
      return false;
    }
  }

  /// Charge le device tier. Retourne lowEnd par défaut si absent.
  DeviceTier loadDeviceTier() {
    _ensureInitialized();
    try {
      final name = _prefs!.getString(_StorageKeys.deviceTier);
      if (name == null) return DeviceTier.lowEnd;
      return DeviceTier.values.firstWhere(
        (t) => t.name == name,
        orElse: () => DeviceTier.lowEnd,
      );
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to load device tier: $e');
      return DeviceTier.lowEnd;
    }
  }

  /// Vérifie si un device tier a été sauvegardé.
  bool hasDeviceTier() {
    _ensureInitialized();
    return _prefs!.containsKey(_StorageKeys.deviceTier);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REVERB PROFILE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sauvegarde le reverb profile détecté.
  Future<bool> saveReverbProfile(ReverbProfile profile) async {
    _ensureInitialized();
    try {
      await _prefs!.setString(_StorageKeys.reverbProfile, profile.name);
      if (kDebugMode) {
        debugPrint('CalibrationStorage: Saved reverb profile: ${profile.name}');
      }
      return true;
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to save reverb profile: $e');
      return false;
    }
  }

  /// Charge le reverb profile. Retourne medium par défaut si absent.
  ReverbProfile loadReverbProfile() {
    _ensureInitialized();
    try {
      final name = _prefs!.getString(_StorageKeys.reverbProfile);
      if (name == null) return ReverbProfile.medium;
      return ReverbProfile.values.firstWhere(
        (p) => p.name == name,
        orElse: () => ReverbProfile.medium,
      );
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to load reverb profile: $e');
      return ReverbProfile.medium;
    }
  }

  /// Vérifie si un reverb profile a été sauvegardé.
  bool hasReverbProfile() {
    _ensureInitialized();
    return _prefs!.containsKey(_StorageKeys.reverbProfile);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ADAPTIVE PARAMETERS (pour brique 2 - learning)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Sauvegarde les paramètres adaptatifs.
  Future<bool> saveAdaptiveParameters(AdaptiveParametersDto params) async {
    _ensureInitialized();
    try {
      final json = jsonEncode(params.toJson());
      await _prefs!.setString(_StorageKeys.adaptiveParams, json);
      if (kDebugMode) {
        debugPrint(
          'CalibrationStorage: Saved adaptive params (sessions=${params.sessionCount})',
        );
      }
      return true;
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to save adaptive params: $e');
      return false;
    }
  }

  /// Charge les paramètres adaptatifs.
  /// Retourne null si absent (pas d'apprentissage encore).
  AdaptiveParametersDto? loadAdaptiveParameters() {
    _ensureInitialized();
    try {
      final json = _prefs!.getString(_StorageKeys.adaptiveParams);
      if (json == null) return null;
      return AdaptiveParametersDto.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('CalibrationStorage: Failed to load adaptive params: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Efface toutes les données de calibration.
  Future<void> clearAll() async {
    _ensureInitialized();
    await _prefs!.remove(_StorageKeys.calibrationResult);
    await _prefs!.remove(_StorageKeys.deviceTier);
    await _prefs!.remove(_StorageKeys.reverbProfile);
    await _prefs!.remove(_StorageKeys.adaptiveParams);
    await _prefs!.remove(_StorageKeys.lastCalibrationTimestamp);
    if (kDebugMode) {
      debugPrint('CalibrationStorage: Cleared all calibration data');
    }
  }

  void _ensureInitialized() {
    if (_prefs == null) {
      throw StateError(
        'CalibrationStorage not initialized. Call init() first.',
      );
    }
  }
}
