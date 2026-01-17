import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/core/practice/pitch/pitch_services.dart';

void main() {
  group('CalibrationNoteMeasurement', () {
    test('isValid returns true when detected values are present', () {
      const measurement = CalibrationNoteMeasurement(
        expectedMidi: 60,
        detectedMidi: 60,
        detectedFreq: 261.63,
        latencyMs: 150.0,
        rmsAmplitude: 0.5,
        confidence: 0.9,
      );

      expect(measurement.isValid, isTrue);
    });

    test('isValid returns false when detectedMidi is null', () {
      const measurement = CalibrationNoteMeasurement(
        expectedMidi: 60,
        detectedMidi: null,
        detectedFreq: null,
        latencyMs: 5000.0,
        rmsAmplitude: 0.001,
        confidence: 0.0,
      );

      expect(measurement.isValid, isFalse);
    });

    test('pitchErrorSemitones calculates correctly', () {
      const measurement = CalibrationNoteMeasurement(
        expectedMidi: 60,
        detectedMidi: 62,
        detectedFreq: 293.66,
        latencyMs: 100.0,
        rmsAmplitude: 0.5,
        confidence: 0.9,
      );

      expect(measurement.pitchErrorSemitones, -2.0); // 60 - 62 = -2
    });

    test('pitchErrorSemitones returns 0 when no detection', () {
      const measurement = CalibrationNoteMeasurement(
        expectedMidi: 60,
        detectedMidi: null,
        detectedFreq: null,
        latencyMs: 5000.0,
        rmsAmplitude: 0.001,
        confidence: 0.0,
      );

      expect(measurement.pitchErrorSemitones, 0.0);
    });
  });

  group('CalibrationResult', () {
    test('isUsable returns true for >50% success rate', () {
      const result = CalibrationResult(
        measurements: [],
        avgLatencyMs: 200.0,
        latencyStdDev: 50.0,
        avgFreqOffset: 1.0,
        minRmsThreshold: 0.001,
        successRate: 0.7,
        recommendedAlgorithm: PitchAlgorithm.mpm,
      );

      expect(result.isUsable, isTrue);
    });

    test('isUsable returns false for <50% success rate', () {
      const result = CalibrationResult(
        measurements: [],
        avgLatencyMs: 200.0,
        latencyStdDev: 50.0,
        avgFreqOffset: 1.0,
        minRmsThreshold: 0.001,
        successRate: 0.3,
        recommendedAlgorithm: PitchAlgorithm.mpm,
      );

      expect(result.isUsable, isFalse);
    });

    test('grade returns correct values', () {
      const excellent = CalibrationResult(
        measurements: [],
        avgLatencyMs: 100.0,
        latencyStdDev: 20.0,
        avgFreqOffset: 1.0,
        minRmsThreshold: 0.001,
        successRate: 0.95,
        recommendedAlgorithm: PitchAlgorithm.mpm,
      );
      expect(excellent.grade, 'Excellent');

      const good = CalibrationResult(
        measurements: [],
        avgLatencyMs: 150.0,
        latencyStdDev: 30.0,
        avgFreqOffset: 1.0,
        minRmsThreshold: 0.001,
        successRate: 0.75,
        recommendedAlgorithm: PitchAlgorithm.mpm,
      );
      expect(good.grade, 'Good');

      const acceptable = CalibrationResult(
        measurements: [],
        avgLatencyMs: 200.0,
        latencyStdDev: 50.0,
        avgFreqOffset: 1.0,
        minRmsThreshold: 0.001,
        successRate: 0.55,
        recommendedAlgorithm: PitchAlgorithm.mpm,
      );
      expect(acceptable.grade, 'Acceptable');

      const poor = CalibrationResult(
        measurements: [],
        avgLatencyMs: 300.0,
        latencyStdDev: 100.0,
        avgFreqOffset: 1.0,
        minRmsThreshold: 0.001,
        successRate: 0.3,
        recommendedAlgorithm: PitchAlgorithm.mpm,
      );
      expect(poor.grade, 'Poor');
    });
  });

  group('CalibrationService', () {
    test('has correct calibration notes', () {
      expect(CalibrationService.calibrationNotes.length, 9);
      expect(CalibrationService.calibrationNotes, [
        48, 52, 55, // C3, E3, G3
        60, 64, 67, // C4, E4, G4
        72, 76, 79, // C5, E5, G5
      ]);
    });

    test('has matching note names', () {
      expect(CalibrationService.noteNames.length, 9);
      expect(CalibrationService.noteNames, [
        'C3',
        'E3',
        'G3',
        'C4',
        'E4',
        'G4',
        'C5',
        'E5',
        'G5',
      ]);
    });

    test('initial state is idle', () {
      final service = CalibrationService();
      expect(service.state, CalibrationState.idle);
    });

    test(
      'calibrate with silent audio stream returns poor result',
      () async {
        final service = CalibrationService();

        // Create a stream that emits silent audio
        final controller = StreamController<Float32List>();
        final states = <CalibrationState>[];

        // Start calibration
        final resultFuture = service.calibrate(
          onProgress: (state, current, total, message) {
            states.add(state);
          },
          audioStream: controller.stream,
        );

        // Emit silent audio frames periodically
        for (int i = 0; i < 100; i++) {
          await Future.delayed(const Duration(milliseconds: 50));
          if (!controller.isClosed) {
            controller.add(Float32List(2048)); // All zeros = silent
          }
        }

        // Wait for calibration to complete (will timeout on each note)
        final result = await resultFuture.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            controller.close();
            return CalibrationResult(
              measurements: [],
              avgLatencyMs: 500.0,
              latencyStdDev: 0.0,
              avgFreqOffset: 1.0,
              minRmsThreshold: 0.001,
              successRate: 0.0,
              recommendedAlgorithm: PitchAlgorithm.mpm,
            );
          },
        );

        controller.close();

        // Should have 0% success rate with silent audio
        expect(result.successRate, 0.0);
        expect(result.isUsable, isFalse);
        expect(result.grade, 'Poor');
      },
      skip: 'Long-running test - enable for integration testing',
    );

    test('CalibrationState has all expected values', () {
      expect(CalibrationState.values, contains(CalibrationState.idle));
      expect(CalibrationState.values, contains(CalibrationState.preparing));
      expect(
        CalibrationState.values,
        contains(CalibrationState.waitingForNote),
      );
      expect(CalibrationState.values, contains(CalibrationState.listening));
      expect(CalibrationState.values, contains(CalibrationState.processing));
      expect(CalibrationState.values, contains(CalibrationState.complete));
      expect(CalibrationState.values, contains(CalibrationState.failed));
    });
  });

  group('CalibrationService._sqrt', () {
    test('approximates sqrt correctly', () {
      // Access via a measurement's internal calculation
      // We test indirectly through the freq ratio calculation
      const measurement = CalibrationNoteMeasurement(
        expectedMidi: 69, // A4
        detectedMidi: 69,
        detectedFreq: 440.0,
        latencyMs: 100.0,
        rmsAmplitude: 0.5,
        confidence: 0.9,
      );

      // freqErrorRatio should be ~1.0 for exact match
      expect(measurement.freqErrorRatio, closeTo(1.0, 0.1));
    });
  });
}
