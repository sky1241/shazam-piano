import 'dart:math';
import 'dart:typed_data';

/// Goertzel-based multi-bin presence detector with harmonic weighting.
///
/// This is a pure DSP brick that detects the presence of specific MIDI notes
/// in an audio buffer using the Goertzel algorithm (O(N) per frequency).
/// It does NOT perform pitch detection - it answers "is note X present?".
///
/// Features:
/// - Multi-bin analysis for multiple target notes
/// - Harmonic weighting (f0 + 0.5*2f0 + 0.25*3f0)
/// - Dominance ratio to reject ambiguous detections (anti half-tone)
/// - Optional Hann windowing to reduce spectral leakage
class GoertzelDetector {
  GoertzelDetector({
    this.defaultDominanceRatio = 1.25,
    this.defaultHarmonics = 3,
    this.normalizationGain = 12.0,
  });

  /// Default dominance ratio for neighbor rejection.
  final double defaultDominanceRatio;

  /// Default number of harmonics to analyze (1 = fundamental only).
  final int defaultHarmonics;

  /// Gain factor for confidence normalization.
  final double normalizationGain;

  /// Cached Hann window coefficients (reused if same length).
  Float32List? _cachedHannWindow;
  int _cachedHannLength = 0;

  /// Detect presence confidence for multiple MIDI notes.
  ///
  /// Returns a Map with an entry for EACH requested MIDI note.
  /// Values are confidence scores in range [0.0, 1.0].
  ///
  /// Parameters:
  /// - [samples]: Audio buffer (mono, normalized -1..1)
  /// - [sampleRate]: Sample rate in Hz (typically 44100)
  /// - [targetMidis]: List of MIDI note numbers to detect
  /// - [dominanceRatio]: If > 1, reject notes where neighbors are too strong
  /// - [applyHannWindow]: Apply Hann window to reduce spectral leakage
  /// - [harmonics]: Number of harmonics to use (1-5, default 3)
  /// - [minConfidence]: Minimum confidence threshold (values below become 0)
  Map<int, double> detectPresence(
    Float32List samples,
    int sampleRate,
    List<int> targetMidis, {
    double? dominanceRatio,
    bool applyHannWindow = true,
    int harmonics = 3,
    double minConfidence = 0.0,
  }) {
    final effectiveDominance = dominanceRatio ?? defaultDominanceRatio;
    final effectiveHarmonics = harmonics.clamp(1, 5);

    // Handle empty or too short buffer
    if (samples.isEmpty || samples.length < 64) {
      return {for (final midi in targetMidis) midi: 0.0};
    }

    // Compute total energy for normalization
    final energy = _computeEnergy(samples);

    // Early exit if signal is essentially silent
    if (energy < 1e-10) {
      return {for (final midi in targetMidis) midi: 0.0};
    }

    // Apply Hann window if requested
    final processedSamples = applyHannWindow
        ? _applyHannWindow(samples)
        : samples;

    // Compute raw scores for all target MIDIs + neighbors
    final allMidis = <int>{};
    for (final midi in targetMidis) {
      allMidis.add(midi);
      if (effectiveDominance > 1.0) {
        allMidis.add(midi - 1);
        allMidis.add(midi + 1);
      }
    }

    final rawScores = <int, double>{};
    for (final midi in allMidis) {
      rawScores[midi] = _computeHarmonicScore(
        processedSamples,
        sampleRate,
        midi,
        effectiveHarmonics,
      );
    }

    // Build result map with normalization and dominance check
    final result = <int, double>{};
    const eps = 1e-12;

    for (final midi in targetMidis) {
      final score = rawScores[midi]!;

      // Normalize by energy
      var normalized = score / (energy + eps);

      // Apply gain and clamp to [0, 1]
      var confidence = (normalized * normalizationGain).clamp(0.0, 1.0);

      // Dominance check: reject if neighbors are too strong
      if (effectiveDominance > 1.0 && confidence > 0) {
        final neighborMinus = rawScores[midi - 1] ?? 0.0;
        final neighborPlus = rawScores[midi + 1] ?? 0.0;
        final maxNeighbor = max(neighborMinus, neighborPlus);

        // If score is not dominant enough over neighbors, suppress
        if (score < effectiveDominance * maxNeighbor) {
          confidence = 0.0;
        }
      }

      // Apply minimum confidence threshold
      if (confidence < minConfidence) {
        confidence = 0.0;
      }

      result[midi] = confidence;
    }

    return result;
  }

  /// Compute total energy (sum of squared samples).
  double _computeEnergy(Float32List samples) {
    var energy = 0.0;
    for (var i = 0; i < samples.length; i++) {
      energy += samples[i] * samples[i];
    }
    return energy;
  }

  /// Apply Hann window to samples (with caching).
  Float32List _applyHannWindow(Float32List samples) {
    final n = samples.length;

    // Update cache if needed
    if (_cachedHannWindow == null || _cachedHannLength != n) {
      _cachedHannWindow = Float32List(n);
      for (var i = 0; i < n; i++) {
        _cachedHannWindow![i] = 0.5 * (1 - cos(2 * pi * i / (n - 1)));
      }
      _cachedHannLength = n;
    }

    // Apply window
    final windowed = Float32List(n);
    for (var i = 0; i < n; i++) {
      windowed[i] = samples[i] * _cachedHannWindow![i];
    }
    return windowed;
  }

  /// Compute weighted harmonic score for a MIDI note.
  ///
  /// score = power(f0) + 0.5*power(2*f0) + 0.25*power(3*f0) + ...
  double _computeHarmonicScore(
    Float32List samples,
    int sampleRate,
    int midi,
    int harmonicCount,
  ) {
    final f0 = midiToFrequency(midi);
    var score = 0.0;

    // Harmonic weights: 1.0, 0.5, 0.25, 0.125, 0.0625
    var weight = 1.0;

    for (var h = 1; h <= harmonicCount; h++) {
      final freq = f0 * h;

      // Skip harmonics above Nyquist
      if (freq >= sampleRate / 2) break;

      final power = _goertzelPower(samples, sampleRate, freq);
      score += weight * power;
      weight *= 0.5;
    }

    return score;
  }

  /// Goertzel algorithm: compute power at a specific frequency.
  ///
  /// This is O(N) and much more efficient than FFT for a few frequencies.
  double _goertzelPower(Float32List samples, int sampleRate, double frequency) {
    final n = samples.length;

    // Normalized frequency
    final k = (frequency * n / sampleRate);
    final omega = 2 * pi * k / n;
    final coeff = 2 * cos(omega);

    var s0 = 0.0;
    var s1 = 0.0;
    var s2 = 0.0;

    // Main Goertzel iteration
    for (var i = 0; i < n; i++) {
      s0 = samples[i] + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }

    // Compute power (magnitude squared)
    // power = s1^2 + s2^2 - coeff * s1 * s2
    final power = s1 * s1 + s2 * s2 - coeff * s1 * s2;

    return power;
  }

  /// Convert MIDI note number to frequency in Hz.
  ///
  /// Uses standard A4 = 440 Hz tuning.
  static double midiToFrequency(int midi) {
    return 440.0 * pow(2, (midi - 69) / 12.0);
  }

  /// Convert frequency in Hz to MIDI note number.
  static int frequencyToMidi(double frequency) {
    return (69 + 12 * log(frequency / 440.0) / ln2).round();
  }
}
