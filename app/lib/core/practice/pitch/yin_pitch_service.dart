import 'dart:math';
import 'dart:typed_data';

import 'pitch_detection_service.dart';

/// YIN algorithm implementation of PitchDetectionService.
///
/// Implements the YIN algorithm for pitch detection.
/// YIN is known for better accuracy on low frequencies compared to MPM.
/// Reference: http://audition.ens.fr/adc/pdf/2002_JASA_YIN.pdf
///
/// STEP 2 (YIN Integration): YIN implementation behind stable interface.
class YinPitchService extends PitchDetectionService {
  YinPitchService({int? sampleRate, int? bufferSize, this.threshold = 0.1})
    : _sampleRate = sampleRate ?? 44100,
      _bufferSize = bufferSize ?? 2048;

  final int _sampleRate;
  final int _bufferSize;

  /// YIN threshold for pitch detection (default 0.1).
  /// Lower = stricter, higher = more permissive.
  final double threshold;

  @override
  String get algorithmName => 'YIN';

  @override
  int get defaultSampleRate => _sampleRate;

  @override
  int get requiredBufferSize => _bufferSize;

  @override
  double? detectPitch(Float32List samples, {int? sampleRate}) {
    if (samples.length < requiredBufferSize) {
      return null;
    }

    // YIN algorithm via pitch_detector_dart
    // The package expects List<double>, so we convert
    final audioSamples = List<double>.from(samples);

    try {
      // getPitchFromFloatBuffer returns Future<PitchDetectorResult>
      // Since we need sync, we use the internal algorithm directly
      // Note: This is a workaround - ideally we'd make detectPitch async
      final result = _detectPitchSync(audioSamples);
      return result;
    } catch (e) {
      // Catch any exceptions from the detector
      return null;
    }
  }

  /// Synchronous pitch detection using YIN algorithm directly.
  ///
  /// This method implements YIN inline for synchronous operation.
  double? _detectPitchSync(List<double> audioSamples) {
    // Simplified YIN implementation for sync operation
    // Based on the YIN algorithm: http://audition.ens.fr/adc/pdf/2002_JASA_YIN.pdf

    final bufferSize = audioSamples.length;
    final yinBuffer = List<double>.filled(bufferSize ~/ 2, 0.0);

    // Check for silent audio (all zeros or very low amplitude)
    double maxAmp = 0.0;
    for (final sample in audioSamples) {
      final abs = sample.abs();
      if (abs > maxAmp) maxAmp = abs;
    }
    if (maxAmp < 0.001) {
      return null; // Silent audio
    }

    // Step 2: Difference function
    for (int tau = 0; tau < yinBuffer.length; tau++) {
      double sum = 0.0;
      for (int i = 0; i < yinBuffer.length; i++) {
        final delta = audioSamples[i] - audioSamples[i + tau];
        sum += delta * delta;
      }
      yinBuffer[tau] = sum;
    }

    // Step 3: Cumulative mean normalized difference
    yinBuffer[0] = 1.0;
    double runningSum = 0.0;
    for (int tau = 1; tau < yinBuffer.length; tau++) {
      runningSum += yinBuffer[tau];
      if (runningSum == 0) {
        yinBuffer[tau] = 1.0; // Avoid division by zero
      } else {
        yinBuffer[tau] = yinBuffer[tau] * tau / runningSum;
      }
    }

    // Step 4: Absolute threshold
    int? tauEstimate;
    for (int tau = 2; tau < yinBuffer.length; tau++) {
      if (yinBuffer[tau] < threshold) {
        while (tau + 1 < yinBuffer.length &&
            yinBuffer[tau + 1] < yinBuffer[tau]) {
          tau++;
        }
        tauEstimate = tau;
        break;
      }
    }

    // If no pitch found below threshold, find minimum
    int finalTau;
    if (tauEstimate == null) {
      double minVal = yinBuffer[1];
      int minTau = 1;
      for (int tau = 2; tau < yinBuffer.length; tau++) {
        if (yinBuffer[tau] < minVal) {
          minVal = yinBuffer[tau];
          minTau = tau;
        }
      }
      // Only accept if minimum is reasonably low
      if (minVal > 0.5) {
        return null;
      }
      finalTau = minTau;
    } else {
      finalTau = tauEstimate;
    }

    // Step 5: Parabolic interpolation
    double betterTau;
    if (finalTau > 0 && finalTau < yinBuffer.length - 1) {
      final s0 = yinBuffer[finalTau - 1];
      final s1 = yinBuffer[finalTau];
      final s2 = yinBuffer[finalTau + 1];
      final adjustment = (s2 - s0) / (2 * (2 * s1 - s2 - s0));
      betterTau = finalTau + adjustment;
    } else {
      betterTau = finalTau.toDouble();
    }

    // Convert to frequency
    if (betterTau <= 0) {
      return null;
    }
    final freq = _sampleRate / betterTau;

    // Filter NaN, Infinity, and unrealistic frequencies
    if (freq.isNaN || freq.isInfinite || freq < 20 || freq > 5000) {
      return null;
    }

    return freq;
  }

  @override
  int frequencyToMidiNote(double frequency) {
    return (69 + 12 * log(frequency / 440) / log(2)).round();
  }

  @override
  double midiNoteToFrequency(int note) {
    return (440 * pow(2, (note - 69) / 12)).toDouble();
  }
}
