import 'dart:math';
import 'dart:typed_data';

import 'pitch_detection_service.dart';

/// MPM (McLeod Pitch Method) implementation of PitchDetectionService.
///
/// Wraps the existing PitchDetector logic behind the abstract interface.
/// This allows easy swapping with YIN or other algorithms.
///
/// STEP 1 (YIN Integration): MPM implementation behind stable interface.
/// STEP 3: Uses extends to inherit detectPitchAsync default implementation.
class MpmPitchService extends PitchDetectionService {
  MpmPitchService({
    this.clarityThreshold = 0.80,
    this.subharmonicClarityRatio = 0.85,
  });

  /// Clarity threshold for accepting a pitch (0.0 to 1.0).
  /// Higher = stricter, fewer false positives.
  final double clarityThreshold;

  /// Ratio for anti-subharmonic filtering.
  /// If octave-up peak has clarity >= this * bestClarity, prefer higher octave.
  final double subharmonicClarityRatio;

  @override
  String get algorithmName => 'MPM';

  @override
  int get defaultSampleRate => 44100;

  @override
  int get requiredBufferSize => 2048;

  // Max tau for piano range (A0 = 27.5Hz => tau ~1603, +10% margin)
  static const int _maxTauPiano = 1763;
  static const double _minUsefulHz = 50.0;

  @override
  double? detectPitch(Float32List samples, {int? sampleRate}) {
    if (samples.length < requiredBufferSize) {
      return null;
    }

    final effectiveSampleRate = sampleRate ?? defaultSampleRate;
    return _mpmPitch(samples, effectiveSampleRate);
  }

  /// McLeod Pitch Method with anti-subharmonic filtering.
  double? _mpmPitch(Float32List samples, int effectiveSampleRate) {
    // Step 1: Normalized Square Difference Function (NSDF)
    final nsdf = _normalizedSquareDifference(samples, effectiveSampleRate);

    // Step 2: Peak picking
    final peaks = _pickPeaks(nsdf);

    if (peaks.isEmpty) {
      return null;
    }

    // Step 3: Find highest peak with good clarity
    int? bestPeak;
    double maxClarity = 0;

    for (final peak in peaks) {
      if (nsdf[peak] > maxClarity && nsdf[peak] > clarityThreshold) {
        maxClarity = nsdf[peak];
        bestPeak = peak;
      }
    }

    if (bestPeak == null || bestPeak == 0) {
      return null;
    }

    // Step 4: Parabolic interpolation for sub-sample accuracy
    final interpolated = _parabolicInterpolation(nsdf, bestPeak);

    // Convert lag to frequency using runtime sample rate
    double frequency = effectiveSampleRate / interpolated;

    // Filter unrealistic frequencies (piano range: 27.5 Hz - 4186 Hz)
    if (frequency < 20 || frequency > 5000) {
      return null;
    }

    // Anti-subharmonic correction
    // Check if there's a peak at half the lag (2x frequency = octave up)
    final halfLag = bestPeak ~/ 2;
    if (halfLag > 10 && halfLag < nsdf.length) {
      // Look for a peak near halfLag (±5% tolerance)
      final searchStart = (halfLag * 0.95).floor().clamp(1, nsdf.length - 1);
      final searchEnd = (halfLag * 1.05).ceil().clamp(1, nsdf.length - 1);

      double octaveUpClarity = 0;
      int? octaveUpPeak;
      for (var i = searchStart; i <= searchEnd; i++) {
        if (nsdf[i] > octaveUpClarity) {
          octaveUpClarity = nsdf[i];
          octaveUpPeak = i;
        }
      }

      // If octave-up peak has clarity >= subharmonicClarityRatio * bestClarity,
      // prefer the higher frequency (it's likely the true fundamental)
      if (octaveUpPeak != null &&
          octaveUpClarity >= subharmonicClarityRatio * maxClarity) {
        final octaveUpInterpolated = _parabolicInterpolation(
          nsdf,
          octaveUpPeak,
        );
        final octaveUpFreq = effectiveSampleRate / octaveUpInterpolated;

        // Verify it's roughly 2x the original (within 10% tolerance)
        final ratio = octaveUpFreq / frequency;
        if (ratio > 1.8 && ratio < 2.2) {
          frequency = octaveUpFreq;
        }
      }
    }

    return frequency;
  }

  /// Normalized Square Difference Function.
  List<double> _normalizedSquareDifference(
    Float32List samples,
    int effectiveSampleRate,
  ) {
    final n = samples.length;
    // Bound NSDF loop to maxTauPiano instead of full n
    final maxTauByFreq = ((effectiveSampleRate / _minUsefulHz) * 1.1).floor();
    final maxTau = min(n, min(_maxTauPiano, maxTauByFreq));
    final nsdf = List<double>.filled(maxTau, 0);

    // Autocorrelation
    for (int tau = 0; tau < maxTau; tau++) {
      double acf = 0;
      double divisorM = 0;

      for (int i = 0; i < n - tau; i++) {
        acf += samples[i] * samples[i + tau];
        divisorM +=
            samples[i] * samples[i] + samples[i + tau] * samples[i + tau];
      }

      nsdf[tau] = divisorM > 0 ? 2 * acf / divisorM : 0;
    }

    return nsdf;
  }

  /// Find peaks in NSDF.
  List<int> _pickPeaks(List<double> nsdf) {
    final peaks = <int>[];
    int pos = 0;
    int curMaxPos = 0;

    // Find first negative zero crossing
    while (pos < nsdf.length - 1 && nsdf[pos] > 0) {
      pos++;
    }

    // Loop through remaining values
    while (pos < nsdf.length - 1) {
      pos++;

      // Positive crossing
      if (nsdf[pos] > 0) {
        curMaxPos = pos;

        // Find local maximum
        while (pos < nsdf.length - 1 && nsdf[pos] <= nsdf[pos + 1]) {
          pos++;
          curMaxPos = pos;
        }

        // Is this a significant peak?
        if (curMaxPos > 0 && nsdf[curMaxPos] > 0.65) {
          peaks.add(curMaxPos);
        }
      }
    }

    return peaks;
  }

  /// Parabolic interpolation for sub-sample accuracy.
  double _parabolicInterpolation(List<double> nsdf, int peak) {
    if (peak < 1 || peak >= nsdf.length - 1) {
      return peak.toDouble();
    }

    final s0 = nsdf[peak - 1];
    final s1 = nsdf[peak];
    final s2 = nsdf[peak + 1];

    final adjustment = (s2 - s0) / (2 * (2 * s1 - s2 - s0));

    return peak + adjustment;
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
