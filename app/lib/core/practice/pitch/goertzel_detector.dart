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
    this.pitchOffsetCents = 0.0,
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

  // ══════════════════════════════════════════════════════════════════════════
  // PITCH OFFSET: Support for detuned pianos
  // ══════════════════════════════════════════════════════════════════════════

  /// Global pitch offset in cents (100 cents = 1 semitone).
  ///
  /// Positive values = piano is sharp (frequencies higher than standard).
  /// Negative values = piano is flat (frequencies lower than standard).
  ///
  /// Example: If calibration measures A4 at 442 Hz instead of 440 Hz,
  /// the offset is +7.85 cents: `1200 * log2(442/440) ≈ 7.85`
  ///
  /// This should be set based on calibration measurement of the piano's
  /// actual tuning vs standard A4=440 Hz.
  double pitchOffsetCents;

  /// Convert cents offset to frequency multiplier.
  ///
  /// Formula: ratio = 2^(cents/1200)
  /// - +100 cents → 2^(100/1200) ≈ 1.0595 (1 semitone up)
  /// - -100 cents → 2^(-100/1200) ≈ 0.9439 (1 semitone down)
  static double centsToFrequencyRatio(double cents) {
    if (cents == 0.0) return 1.0;
    return pow(2, cents / 1200.0).toDouble();
  }

  /// Convert frequency ratio to cents offset.
  ///
  /// Formula: cents = 1200 * log2(ratio)
  /// Useful for computing offset from measured vs expected frequency.
  static double frequencyRatioToCents(double ratio) {
    if (ratio <= 0) return 0.0;
    return 1200.0 * log(ratio) / ln2;
  }

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
  ///
  /// Uses [_pitchOffsetCents] to adjust target frequency for detuned pianos.
  double _computeHarmonicScore(
    Float32List samples,
    int sampleRate,
    int midi,
    int harmonicCount,
  ) {
    // Apply pitch offset to target the actual piano frequency
    final f0 = midiToFrequencyWithOffset(midi);
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

  /// Convert MIDI note to frequency with pitch offset applied.
  ///
  /// This is the instance method that applies [_pitchOffsetCents].
  /// Use this for detection (targets actual piano frequencies).
  double midiToFrequencyWithOffset(int midi) {
    final baseFreq = midiToFrequency(midi);
    if (pitchOffsetCents == 0.0) return baseFreq;
    return baseFreq * centsToFrequencyRatio(pitchOffsetCents);
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

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-063: OCTAVE DISAMBIGUATION - Fix YIN octave errors
  // ══════════════════════════════════════════════════════════════════════════
  //
  // Problem: YIN pitch detection sometimes detects the wrong octave due to
  // "period doubling" - it finds a period 2x longer (octave below) when
  // harmonics are stronger than the fundamental.
  //
  // Solution: After YIN detects a pitch, use Goertzel to compare energy at:
  //   - detected MIDI (from YIN)
  //   - detected MIDI + 12 (octave above)
  //   - detected MIDI - 12 (octave below)
  // Return the MIDI with highest fundamental energy.
  // ══════════════════════════════════════════════════════════════════════════

  /// Disambiguate octave using Goertzel energy comparison.
  ///
  /// YIN often detects one octave below due to period doubling.
  /// This method compares energy at the detected MIDI and adjacent octaves
  /// to find the true fundamental.
  ///
  /// Parameters:
  /// - [samples]: Audio buffer (mono, normalized -1..1)
  /// - [sampleRate]: Sample rate in Hz (typically 44100)
  /// - [detectedMidi]: MIDI note detected by YIN
  /// - [applyHannWindow]: Apply Hann window (default true)
  ///
  /// Returns:
  /// - [OctaveDisambiguationResult] with corrected MIDI and confidence
  OctaveDisambiguationResult disambiguateOctave(
    Float32List samples,
    int sampleRate,
    int detectedMidi, {
    bool applyHannWindow = true,
  }) {
    // Handle empty or too short buffer
    if (samples.isEmpty || samples.length < 64) {
      return OctaveDisambiguationResult(
        originalMidi: detectedMidi,
        correctedMidi: detectedMidi,
        wasCorrected: false,
        confidence: 0.0,
        reason: 'buffer_too_short',
      );
    }

    // Compute total energy for normalization
    final energy = _computeEnergy(samples);

    if (energy < 1e-10) {
      return OctaveDisambiguationResult(
        originalMidi: detectedMidi,
        correctedMidi: detectedMidi,
        wasCorrected: false,
        confidence: 0.0,
        reason: 'silent',
      );
    }

    // Apply Hann window if requested
    final processedSamples =
        applyHannWindow ? _applyHannWindow(samples) : samples;

    // Candidate octaves to test
    // MIDI range for piano: 21 (A0) to 108 (C8)
    final candidates = <int>[];

    // Add detected MIDI
    candidates.add(detectedMidi);

    // Add octave above (if within piano range)
    final octaveAbove = detectedMidi + 12;
    if (octaveAbove <= 108) {
      candidates.add(octaveAbove);
    }

    // Add octave below (if within piano range)
    final octaveBelow = detectedMidi - 12;
    if (octaveBelow >= 21) {
      candidates.add(octaveBelow);
    }

    // Compute fundamental power for each candidate
    // Use ONLY the fundamental (1 harmonic) to avoid harmonic confusion
    final scores = <int, double>{};
    for (final midi in candidates) {
      final f0 = midiToFrequencyWithOffset(midi);

      // Skip if frequency is above Nyquist or below reasonable range
      if (f0 >= sampleRate / 2 || f0 < 50.0) {
        scores[midi] = 0.0;
        continue;
      }

      final power = _goertzelPower(processedSamples, sampleRate, f0);
      scores[midi] = power;
    }

    // Find the candidate with highest fundamental power
    int bestMidi = detectedMidi;
    double bestScore = scores[detectedMidi] ?? 0.0;

    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestMidi = entry.key;
      }
    }

    // Compute confidence (normalized score)
    final confidence = (bestScore / (energy + 1e-12) * normalizationGain)
        .clamp(0.0, 1.0);

    // Determine if correction occurred
    final wasCorrected = bestMidi != detectedMidi;
    final correction = bestMidi - detectedMidi;
    final reason = wasCorrected
        ? (correction > 0 ? 'octave_up_$correction' : 'octave_down_$correction')
        : 'no_correction';

    return OctaveDisambiguationResult(
      originalMidi: detectedMidi,
      correctedMidi: bestMidi,
      wasCorrected: wasCorrected,
      confidence: confidence,
      reason: reason,
      scores: scores,
    );
  }
}

/// Result of octave disambiguation.
class OctaveDisambiguationResult {
  const OctaveDisambiguationResult({
    required this.originalMidi,
    required this.correctedMidi,
    required this.wasCorrected,
    required this.confidence,
    required this.reason,
    this.scores,
  });

  /// Original MIDI detected by YIN.
  final int originalMidi;

  /// Corrected MIDI after octave disambiguation.
  final int correctedMidi;

  /// Whether the octave was corrected.
  final bool wasCorrected;

  /// Confidence in the corrected MIDI (0.0-1.0).
  final double confidence;

  /// Reason for the correction (e.g., 'octave_up_12', 'no_correction').
  final String reason;

  /// Optional: scores for each candidate MIDI (for debugging).
  final Map<int, double>? scores;

  @override
  String toString() {
    return 'OctaveDisambiguationResult(original=$originalMidi, corrected=$correctedMidi, '
        'wasCorrected=$wasCorrected, conf=${confidence.toStringAsFixed(2)}, reason=$reason)';
  }
}
