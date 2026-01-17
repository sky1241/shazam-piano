import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/core/practice/device_calibration.dart';
import 'package:shazapiano/core/practice/pitch/pitch_services.dart';

void main() {
  group('CalibratedMicEngineConfig', () {
    group('fromDeviceTier', () {
      test('creates config for lowEnd tier', () {
        final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);

        expect(config.headWindowSec, 0.15);
        expect(config.tailWindowSec, 0.60);
        expect(config.algorithm, PitchAlgorithm.mpm);
        expect(config.latencyCompensationMs, 200.0);
      });

      test('creates config for midRange tier', () {
        final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.midRange);

        expect(config.headWindowSec, 0.12);
        expect(config.tailWindowSec, 0.45);
        expect(config.latencyCompensationMs, 150.0);
      });

      test('creates config for highEnd tier', () {
        final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.highEnd);

        expect(config.headWindowSec, 0.10);
        expect(config.tailWindowSec, 0.35);
        expect(config.latencyCompensationMs, 100.0);
      });
    });

    group('fromCalibration', () {
      test('creates config with recommended algorithm', () {
        const calibration = CalibrationResult(
          measurements: [],
          avgLatencyMs: 150.0,
          latencyStdDev: 30.0,
          avgFreqOffset: 1.0,
          minRmsThreshold: 0.002,
          successRate: 0.8,
          recommendedAlgorithm: PitchAlgorithm.yin,
        );

        final config = CalibratedMicEngineConfig.fromCalibration(calibration);

        expect(config.algorithm, PitchAlgorithm.yin);
      });

      test('adjusts tail window based on latency', () {
        const highLatency = CalibrationResult(
          measurements: [],
          avgLatencyMs: 400.0, // High latency
          latencyStdDev: 50.0,
          avgFreqOffset: 1.0,
          minRmsThreshold: 0.001,
          successRate: 0.7,
          recommendedAlgorithm: PitchAlgorithm.mpm,
        );

        final config = CalibratedMicEngineConfig.fromCalibration(highLatency);

        // tailWindow = max(base, latency * 2 + 100ms) / 1000
        // = max(0.60, (400 * 2 + 100) / 1000) = max(0.60, 0.9) = 0.9
        expect(config.tailWindowSec, greaterThan(0.60));
      });

      test('uses calibrated RMS threshold', () {
        const calibration = CalibrationResult(
          measurements: [],
          avgLatencyMs: 150.0,
          latencyStdDev: 30.0,
          avgFreqOffset: 1.0,
          minRmsThreshold: 0.005,
          successRate: 0.9,
          recommendedAlgorithm: PitchAlgorithm.mpm,
        );

        final config = CalibratedMicEngineConfig.fromCalibration(calibration);

        expect(config.absMinRms, 0.005);
      });

      test('lowers clarity threshold for low success rate', () {
        const lowSuccess = CalibrationResult(
          measurements: [],
          avgLatencyMs: 150.0,
          latencyStdDev: 30.0,
          avgFreqOffset: 1.0,
          minRmsThreshold: 0.001,
          successRate: 0.5, // Low success rate
          recommendedAlgorithm: PitchAlgorithm.mpm,
        );

        const highSuccess = CalibrationResult(
          measurements: [],
          avgLatencyMs: 150.0,
          latencyStdDev: 30.0,
          avgFreqOffset: 1.0,
          minRmsThreshold: 0.001,
          successRate: 0.9, // High success rate
          recommendedAlgorithm: PitchAlgorithm.mpm,
        );

        final lowConfig = CalibratedMicEngineConfig.fromCalibration(lowSuccess);
        final highConfig = CalibratedMicEngineConfig.fromCalibration(highSuccess);

        expect(lowConfig.clarityThreshold, lessThan(highConfig.clarityThreshold));
      });
    });

    group('defaultConfig', () {
      test('returns lowEnd config', () {
        final defaultConfig = CalibratedMicEngineConfig.defaultConfig();
        final lowEndConfig = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);

        expect(defaultConfig.headWindowSec, lowEndConfig.headWindowSec);
        expect(defaultConfig.tailWindowSec, lowEndConfig.tailWindowSec);
        expect(defaultConfig.latencyCompensationMs, lowEndConfig.latencyCompensationMs);
      });
    });

    group('createPitchService', () {
      test('creates MPM service for MPM algorithm', () {
        final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);
        final service = config.createPitchService();

        expect(service, isA<MpmPitchService>());
        expect(service.algorithmName, 'MPM');
      });

      test('creates YIN service for YIN algorithm', () {
        const calibration = CalibrationResult(
          measurements: [],
          avgLatencyMs: 150.0,
          latencyStdDev: 30.0,
          avgFreqOffset: 1.0,
          minRmsThreshold: 0.001,
          successRate: 0.7,
          recommendedAlgorithm: PitchAlgorithm.yin,
        );

        final config = CalibratedMicEngineConfig.fromCalibration(calibration);
        final service = config.createPitchService();

        expect(service, isA<YinPitchService>());
        expect(service.algorithmName, 'YIN');
      });
    });

    group('createPitchDetector', () {
      test('returns function with correct signature', () {
        final config = CalibratedMicEngineConfig.defaultConfig();
        final detector = config.createPitchDetector();

        // Should be callable with List<double> and double
        expect(detector, isA<double Function(List<double>, double)>());
      });

      test('returns 0.0 for silent audio', () {
        final config = CalibratedMicEngineConfig.defaultConfig();
        final detector = config.createPitchDetector();

        final silentSamples = List<double>.filled(2048, 0.0);
        final result = detector(silentSamples, 44100.0);

        expect(result, 0.0);
      });
    });

    group('adjustedWindowStart', () {
      test('subtracts head window and latency compensation', () {
        final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);

        // noteStart = 1.0s
        // headWindowSec = 0.15s
        // latencyCompensationMs = 200ms = 0.2s
        // adjustedStart = 1.0 - 0.15 - 0.2 = 0.65s
        final adjusted = config.adjustedWindowStart(1.0);

        expect(adjusted, closeTo(0.65, 0.01));
      });
    });

    group('adjustedWindowEnd', () {
      test('adds tail window', () {
        final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);

        // noteEnd = 1.0s
        // tailWindowSec = 0.60s
        // adjustedEnd = 1.0 + 0.60 = 1.60s
        final adjusted = config.adjustedWindowEnd(1.0);

        expect(adjusted, closeTo(1.60, 0.01));
      });
    });

    group('freqOffsetToSemitones', () {
      test('returns 0 for ratio of 1.0', () {
        final semitones = CalibratedMicEngineConfig.freqOffsetToSemitones(1.0);
        expect(semitones, closeTo(0.0, 0.01));
      });

      test('returns ~12 for ratio of 2.0 (octave)', () {
        final semitones = CalibratedMicEngineConfig.freqOffsetToSemitones(2.0);
        expect(semitones, closeTo(12.0, 0.5));
      });

      test('returns ~-12 for ratio of 0.5 (octave down)', () {
        final semitones = CalibratedMicEngineConfig.freqOffsetToSemitones(0.5);
        expect(semitones, closeTo(-12.0, 0.5));
      });

      test('handles invalid values', () {
        expect(CalibratedMicEngineConfig.freqOffsetToSemitones(0), 0.0);
        expect(CalibratedMicEngineConfig.freqOffsetToSemitones(-1), 0.0);
        expect(CalibratedMicEngineConfig.freqOffsetToSemitones(double.nan), 0.0);
        expect(CalibratedMicEngineConfig.freqOffsetToSemitones(double.infinity), 0.0);
      });
    });

    group('toString', () {
      test('formats config correctly', () {
        final config = CalibratedMicEngineConfig.fromDeviceTier(DeviceTier.lowEnd);
        final str = config.toString();

        expect(str, contains('algo='));
        expect(str, contains('headWin='));
        expect(str, contains('tailWin='));
        expect(str, contains('latencyComp='));
        expect(str, contains('rmsThreshold='));
        expect(str, contains('clarity='));
      });
    });
  });
}
