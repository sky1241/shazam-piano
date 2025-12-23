import 'dart:math';
import 'dart:typed_data';

/// Simple Pitch Detector using MPM (McLeod Pitch Method)
/// Détecte la fréquence fondamentale d'un signal audio monophonique
class PitchDetector {
  static const int sampleRate = 44100;
  static const int bufferSize = 2048;
  static const double clarityThreshold = 0.9;

  /// Detect pitch from audio samples
  /// Returns frequency in Hz, or null if no clear pitch
  double? detectPitch(Float32List samples) {
    if (samples.length < bufferSize) {
      return null;
    }

    // Use MPM algorithm
    final frequency = _mpmPitch(samples);

    return frequency;
  }

  /// McLeod Pitch Method
  double? _mpmPitch(Float32List samples) {
    // Step 1: Normalized Square Difference Function (NSDF)
    final nsdf = _normalizedSquareDifference(samples);

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

    // Convert lag to frequency
    final frequency = sampleRate / interpolated;

    // Filter unrealistic frequencies (piano range: 27.5 Hz - 4186 Hz)
    if (frequency < 20 || frequency > 5000) {
      return null;
    }

    return frequency;
  }

  /// Normalized Square Difference Function
  List<double> _normalizedSquareDifference(Float32List samples) {
    final n = samples.length;
    final nsdf = List<double>.filled(n, 0);

    // Autocorrelation
    for (int tau = 0; tau < n; tau++) {
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

  /// Find peaks in NSDF
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
        if (curMaxPos > 0 && nsdf[curMaxPos] > 0.8) {
          peaks.add(curMaxPos);
        }
      }
    }

    return peaks;
  }

  /// Parabolic interpolation for sub-sample accuracy
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

  /// Convert frequency to MIDI note number
  int frequencyToMidiNote(double frequency) {
    return (69 + 12 * log(frequency / 440) / log(2)).round();
  }

  /// Convert MIDI note to frequency
  double midiNoteToFrequency(int note) {
    return (440 * pow(2, (note - 69) / 12)).toDouble();
  }

  /// Calculate cents difference between two frequencies
  double centsDifference(double freq1, double freq2) {
    return 1200 * log(freq2 / freq1) / log(2);
  }

  /// Classify note accuracy
  NoteAccuracy classifyAccuracy(double centsError) {
    final absError = centsError.abs();

    if (absError <= 25) {
      return NoteAccuracy.correct;
    } else if (absError <= 50) {
      return NoteAccuracy.close;
    } else {
      return NoteAccuracy.wrong;
    }
  }
}

enum NoteAccuracy {
  correct, // ±25 cents
  close, // ±25-50 cents
  wrong, // >50 cents
  miss, // No note detected
}
