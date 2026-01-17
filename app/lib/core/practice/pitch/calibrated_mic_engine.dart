import 'dart:typed_data';

import '../device_calibration.dart';
import 'pitch_services.dart';

/// Factory for creating calibrated MicEngine configurations.
///
/// STEP 5: Applies calibration results to MicEngine parameters.
///
/// Usage:
/// ```dart
/// // Option 1: Use device tier profile
/// final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);
///
/// // Option 2: Use dynamic calibration result
/// final calibration = await calibrationService.calibrate(...);
/// final config = CalibratedMicEngineConfig.fromCalibration(calibration);
///
/// // Create MicEngine with calibrated config
/// final engine = MicEngine(
///   noteEvents: [...],
///   hitNotes: [...],
///   detectPitch: config.createPitchDetector(),
///   headWindowSec: config.headWindowSec,
///   tailWindowSec: config.tailWindowSec,
///   absMinRms: config.absMinRms,
///   ...
/// );
/// ```
class CalibratedMicEngineConfig {
  const CalibratedMicEngineConfig({
    required this.headWindowSec,
    required this.tailWindowSec,
    required this.absMinRms,
    required this.minConfForWrong,
    required this.minConfForPitch,
    required this.eventDebounceSec,
    required this.wrongFlashCooldownSec,
    required this.sustainFilterMs,
    required this.pitchWindowSize,
    required this.minPitchIntervalMs,
    required this.algorithm,
    required this.clarityThreshold,
    required this.latencyCompensationMs,
  });

  // Timing windows
  final double headWindowSec;
  final double tailWindowSec;

  // Detection thresholds
  final double absMinRms;
  final double minConfForWrong;
  final double minConfForPitch;

  // Anti-ghost/sustain
  final double eventDebounceSec;
  final double wrongFlashCooldownSec;
  final double sustainFilterMs;

  // Performance
  final int pitchWindowSize;
  final int minPitchIntervalMs;

  // Pitch detection
  final PitchAlgorithm algorithm;
  final double clarityThreshold;

  // Latency compensation (applied to timing)
  final double latencyCompensationMs;

  /// Create config from a device tier (static profile).
  factory CalibratedMicEngineConfig.fromDeviceTier(DeviceTier tier) {
    final calibration = PracticeCalibration.forTier(tier);

    return CalibratedMicEngineConfig(
      headWindowSec: calibration.headWindowSec,
      tailWindowSec: calibration.tailWindowSec,
      absMinRms: calibration.absMinRms,
      minConfForWrong: calibration.minConfForWrong,
      minConfForPitch: calibration.minConfForPitch,
      eventDebounceSec: calibration.eventDebounceSec,
      wrongFlashCooldownSec: calibration.wrongFlashCooldownSec,
      sustainFilterMs: calibration.sustainFilterMs,
      pitchWindowSize: calibration.pitchWindowSize,
      minPitchIntervalMs: calibration.minPitchIntervalMs,
      algorithm: PitchAlgorithm.mpm, // Default to MPM
      clarityThreshold: calibration.clarityThreshold,
      latencyCompensationMs: calibration.micLatencyMs,
    );
  }

  /// Create config from dynamic calibration result.
  factory CalibratedMicEngineConfig.fromCalibration(CalibrationResult result) {
    // Base on low-end profile, then adjust based on calibration
    final base = PracticeCalibration.lowEnd();

    // Adjust tail window based on measured latency
    // Rule: tailWindow = max(base, latency * 2 + 100ms buffer)
    final latencyBasedTail = (result.avgLatencyMs * 2 + 100) / 1000;
    final tailWindowSec = latencyBasedTail > base.tailWindowSec
        ? latencyBasedTail
        : base.tailWindowSec;

    // Adjust RMS threshold based on calibration
    final absMinRms = result.minRmsThreshold > 0
        ? result.minRmsThreshold
        : base.absMinRms;

    // Adjust clarity threshold based on success rate
    // Lower success rate → lower threshold (more permissive)
    final clarityThreshold = result.successRate >= 0.8
        ? base.clarityThreshold
        : base.clarityThreshold - 0.05; // Slightly more permissive

    return CalibratedMicEngineConfig(
      headWindowSec: base.headWindowSec,
      tailWindowSec: tailWindowSec,
      absMinRms: absMinRms,
      minConfForWrong: base.minConfForWrong,
      minConfForPitch: base.minConfForPitch,
      eventDebounceSec: base.eventDebounceSec,
      wrongFlashCooldownSec: base.wrongFlashCooldownSec,
      sustainFilterMs: base.sustainFilterMs,
      pitchWindowSize: base.pitchWindowSize,
      minPitchIntervalMs: base.minPitchIntervalMs,
      algorithm: result.recommendedAlgorithm,
      clarityThreshold: clarityThreshold,
      latencyCompensationMs: result.avgLatencyMs,
    );
  }

  /// Create default config (low-end profile).
  factory CalibratedMicEngineConfig.defaultConfig() {
    return CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);
  }

  /// Create a pitch detection service based on this config.
  PitchDetectionService createPitchService() {
    return PitchServiceFactory.create(
      algorithm: algorithm,
      clarityThreshold: clarityThreshold,
    );
  }

  /// Create a pitch detector function for MicEngine compatibility.
  ///
  /// Returns a function with signature: `(List<double>, double) -> double`
  /// This bridges the new PitchDetectionService to the old MicEngine API.
  double Function(List<double>, double) createPitchDetector() {
    final service = createPitchService();

    return (List<double> samples, double sampleRate) {
      // Convert List<double> to Float32List
      final buffer = Float32List.fromList(samples);
      final freq = service.detectPitch(buffer, sampleRate: sampleRate.toInt());
      return freq ?? 0.0;
    };
  }

  /// Get adjusted timing window start (compensated for latency).
  ///
  /// The latency compensation shifts the expected timing to account for
  /// audio input/processing delay.
  double adjustedWindowStart(double noteStart) {
    return noteStart - headWindowSec - (latencyCompensationMs / 1000);
  }

  /// Get adjusted timing window end (compensated for latency).
  double adjustedWindowEnd(double noteEnd) {
    return noteEnd + tailWindowSec;
  }

  /// Convert frequency offset ratio to semitone correction.
  static double freqOffsetToSemitones(double freqOffset) {
    if (freqOffset <= 0 || freqOffset.isNaN || freqOffset.isInfinite) {
      return 0.0;
    }
    // semitones = 12 * log2(ratio)
    return 12 * _log2(freqOffset);
  }

  static double _log2(double x) {
    if (x <= 0) return 0;
    // log2(x) = ln(x) / ln(2)
    return _ln(x) / 0.693147;
  }

  static double _ln(double x) {
    if (x <= 0) return 0;
    // Taylor series approximation for ln(x) around x=1
    // For better accuracy, normalize x to [0.5, 2]
    double result = 0.0;
    int exp = 0;
    while (x > 2) {
      x /= 2;
      exp++;
    }
    while (x < 0.5) {
      x *= 2;
      exp--;
    }
    // ln(x) for x in [0.5, 2] using series
    final y = (x - 1) / (x + 1);
    double term = y;
    for (int i = 1; i <= 20; i += 2) {
      result += term / i;
      term *= y * y;
    }
    result *= 2;
    return result + exp * 0.693147;
  }

  @override
  String toString() {
    return 'CalibratedMicEngineConfig('
        'algo=$algorithm, '
        'headWin=${headWindowSec.toStringAsFixed(2)}s, '
        'tailWin=${tailWindowSec.toStringAsFixed(2)}s, '
        'latencyComp=${latencyCompensationMs.toStringAsFixed(0)}ms, '
        'rmsThreshold=${absMinRms.toStringAsFixed(4)}, '
        'clarity=${clarityThreshold.toStringAsFixed(2)}'
        ')';
  }
}

/// Extension for Float32List.fromList
extension Float32ListExtension on Float32List {
  static Float32List fromList(List<double> list) {
    final result = Float32List(list.length);
    for (int i = 0; i < list.length; i++) {
      result[i] = list[i];
    }
    return result;
  }
}
