/// Barrel file for pitch detection services.
///
/// Usage:
/// ```dart
/// import 'package:shazapiano/core/practice/pitch/pitch_services.dart';
///
/// final service = PitchServiceFactory.create(PitchAlgorithm.mpm);
/// final freq = service.detectPitch(samples);
/// ```
library;

import 'pitch_detection_service.dart';
import 'mpm_pitch_service.dart';
import 'yin_pitch_service.dart';

export 'pitch_detection_service.dart';
export 'mpm_pitch_service.dart';
export 'yin_pitch_service.dart';
export 'calibration_service.dart';
export 'calibrated_mic_engine.dart';

/// Available pitch detection algorithms.
enum PitchAlgorithm {
  /// McLeod Pitch Method (current default).
  mpm,

  /// YIN algorithm - better for low frequencies.
  yin,
}

/// Factory for creating pitch detection services.
///
/// Centralizes algorithm selection and configuration.
class PitchServiceFactory {
  PitchServiceFactory._();

  /// Current default algorithm.
  /// Can be changed at runtime for A/B testing.
  static PitchAlgorithm defaultAlgorithm = PitchAlgorithm.mpm;

  /// Feature flag: enable debug comparison logging between algorithms.
  static bool enableComparisonLogging = false;

  /// Create a pitch detection service for the given algorithm.
  ///
  /// [algorithm] - Algorithm to use (defaults to [defaultAlgorithm]).
  /// [clarityThreshold] - Confidence threshold (MPM only, 0.0-1.0).
  /// [sampleRate] - Sample rate for YIN (defaults to 44100).
  /// [bufferSize] - Buffer size for YIN (defaults to 2048).
  static PitchDetectionService create({
    PitchAlgorithm? algorithm,
    double? clarityThreshold,
    int? sampleRate,
    int? bufferSize,
  }) {
    final algo = algorithm ?? defaultAlgorithm;

    switch (algo) {
      case PitchAlgorithm.mpm:
        return MpmPitchService(clarityThreshold: clarityThreshold ?? 0.80);
      case PitchAlgorithm.yin:
        return YinPitchService(sampleRate: sampleRate, bufferSize: bufferSize);
    }
  }

  /// Create default service (uses defaultAlgorithm).
  static PitchDetectionService createDefault() {
    return create(algorithm: defaultAlgorithm);
  }

  /// Create both MPM and YIN services for comparison.
  ///
  /// Useful for debugging and validating algorithm accuracy.
  static ({PitchDetectionService mpm, PitchDetectionService yin})
  createBothForComparison({
    double? clarityThreshold,
    int? sampleRate,
    int? bufferSize,
  }) {
    return (
      mpm: MpmPitchService(clarityThreshold: clarityThreshold ?? 0.80),
      yin: YinPitchService(sampleRate: sampleRate, bufferSize: bufferSize),
    );
  }
}
