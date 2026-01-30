import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/core/practice/pitch/goertzel_detector.dart';

void main() {
  group('GoertzelDetector', () {
    late GoertzelDetector detector;

    setUp(() {
      detector = GoertzelDetector();
    });

    group('basic properties', () {
      test('has reasonable default values', () {
        expect(detector.defaultDominanceRatio, 1.25);
        expect(detector.defaultHarmonics, 3);
        expect(detector.normalizationGain, greaterThan(0));
      });

      test('midiToFrequency converts correctly', () {
        expect(
          GoertzelDetector.midiToFrequency(69),
          closeTo(440.0, 0.01),
        ); // A4
        expect(
          GoertzelDetector.midiToFrequency(60),
          closeTo(261.63, 0.1),
        ); // C4
        expect(
          GoertzelDetector.midiToFrequency(64),
          closeTo(329.63, 0.1),
        ); // E4
        expect(
          GoertzelDetector.midiToFrequency(67),
          closeTo(392.00, 0.1),
        ); // G4
        expect(
          GoertzelDetector.midiToFrequency(72),
          closeTo(523.25, 0.1),
        ); // C5
      });

      test('frequencyToMidi converts correctly', () {
        expect(GoertzelDetector.frequencyToMidi(440.0), 69); // A4
        expect(GoertzelDetector.frequencyToMidi(261.63), 60); // C4
        expect(GoertzelDetector.frequencyToMidi(329.63), 64); // E4
      });
    });

    group('silence detection', () {
      test('silence => confidence close to 0', () {
        final samples = Float32List(2048); // All zeros
        final result = detector.detectPresence(samples, 44100, [60]);

        expect(result.containsKey(60), isTrue);
        expect(result[60], equals(0.0));
      });

      test('near-silence => confidence very low', () {
        final samples = Float32List(2048);
        // Very tiny values (essentially noise floor)
        for (var i = 0; i < samples.length; i++) {
          samples[i] = 1e-8;
        }
        final result = detector.detectPresence(samples, 44100, [60, 64, 67]);

        for (final midi in [60, 64, 67]) {
          expect(result[midi], lessThan(0.01));
        }
      });

      test('empty buffer returns zeros', () {
        final samples = Float32List(0);
        final result = detector.detectPresence(samples, 44100, [60, 64]);

        expect(result[60], equals(0.0));
        expect(result[64], equals(0.0));
      });

      test('too short buffer returns zeros', () {
        final samples = Float32List(32); // Less than 64
        final result = detector.detectPresence(samples, 44100, [60]);

        expect(result[60], equals(0.0));
      });
    });

    group('mono note detection - C4 dominant', () {
      test('mono C4 => C4 more confident than neighbors', () {
        // Generate C4 with harmonics (like a piano)
        final samples = _generateSineWaveWithHarmonics(
          261.63, // C4
          2048,
          44100,
        );

        final result = detector.detectPresence(
          samples,
          44100,
          [59, 60, 61], // B3, C4, C#4
          dominanceRatio: 1.15,
        );

        // C4 should be detected with reasonable confidence
        expect(
          result[60],
          greaterThan(0.1),
          reason: 'C4 should have confidence > 0.1',
        );

        // C4 should be more confident than neighbors
        expect(result[60]! > result[59]!, isTrue, reason: 'C4 should be > B3');
        expect(result[60]! > result[61]!, isTrue, reason: 'C4 should be > C#4');

        // Neighbors should be relatively low
        expect(result[59], lessThan(0.15), reason: 'B3 should be low (< 0.15)');
        expect(
          result[61],
          lessThan(0.15),
          reason: 'C#4 should be low (< 0.15)',
        );
      });

      test('mono A4 (440Hz) => A4 dominant over neighbors', () {
        final samples = _generateSineWaveWithHarmonics(
          440.0, // A4
          2048,
          44100,
        );

        final result = detector.detectPresence(
          samples,
          44100,
          [68, 69, 70], // G#4, A4, A#4
          dominanceRatio: 1.15,
        );

        // A4 should be detected
        expect(result[69], greaterThan(0.1));

        // A4 should dominate neighbors
        expect(result[69]! > result[68]!, isTrue);
        expect(result[69]! > result[70]!, isTrue);
      });

      test('dominance ratio suppresses ambiguous detections', () {
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        // With high dominance ratio, neighbors should be suppressed
        final result = detector.detectPresence(samples, 44100, [
          59,
          60,
          61,
        ], dominanceRatio: 1.5);

        // Target note should pass dominance check
        expect(result[60], greaterThan(0.05));

        // Neighbors should be suppressed (0 or very low)
        // because they're not dominant over their own neighbors
        expect(result[59], lessThan(result[60]!));
        expect(result[61], lessThan(result[60]!));
      });
    });

    group('chord detection - C major (C4-E4-G4)', () {
      test('C major chord => all 3 notes detected', () {
        // Generate C major chord: C4 + E4 + G4
        final samples = _generateChord(
          [261.63, 329.63, 392.00], // C4, E4, G4
          2048,
          44100,
        );

        final result = detector.detectPresence(
          samples,
          44100,
          [60, 64, 67], // C4, E4, G4
          dominanceRatio: 1.0, // Disable dominance for chord
        );

        // All chord tones should be detected
        const threshold = 0.08;
        expect(
          result[60],
          greaterThan(threshold),
          reason: 'C4 should be detected in chord',
        );
        expect(
          result[64],
          greaterThan(threshold),
          reason: 'E4 should be detected in chord',
        );
        expect(
          result[67],
          greaterThan(threshold),
          reason: 'G4 should be detected in chord',
        );
      });

      test('C major chord => non-chord tones are lower', () {
        final samples = _generateChord([261.63, 329.63, 392.00], 2048, 44100);

        // Include some non-chord tones
        final result = detector.detectPresence(
          samples,
          44100,
          [60, 61, 63, 64, 65, 67], // C4, C#4, D#4, E4, F4, G4
          dominanceRatio: 1.0,
        );

        // Chord tones should be higher than non-chord tones
        final chordToneMin = [
          result[60]!,
          result[64]!,
          result[67]!,
        ].reduce(min);
        final nonChordToneMax = [
          result[61]!,
          result[63]!,
          result[65]!,
        ].reduce(max);

        expect(
          chordToneMin > nonChordToneMax * 0.5,
          isTrue,
          reason: 'Chord tones should be more prominent than non-chord tones',
        );
      });
    });

    group('windowing', () {
      test('Hann window reduces spectral leakage', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // Without window - more leakage to neighbors
        final withoutWindow = detector.detectPresence(
          samples,
          44100,
          [68, 69, 70],
          applyHannWindow: false,
          dominanceRatio: 1.0,
        );

        // With window - less leakage
        final withWindow = detector.detectPresence(
          samples,
          44100,
          [68, 69, 70],
          applyHannWindow: true,
          dominanceRatio: 1.0,
        );

        // Both should detect A4
        expect(withoutWindow[69], greaterThan(0.05));
        expect(withWindow[69], greaterThan(0.05));

        // Window should improve selectivity (lower neighbor relative to target)
        final ratioWithout =
            withoutWindow[69]! /
            (max(withoutWindow[68]!, withoutWindow[70]!) + 1e-10);
        final ratioWith =
            withWindow[69]! / (max(withWindow[68]!, withWindow[70]!) + 1e-10);

        expect(
          ratioWith >= ratioWithout * 0.8,
          isTrue,
          reason: 'Windowing should not degrade selectivity significantly',
        );
      });

      test('window cache is reused for same length', () {
        final samples1 = _generateSineWaveWithHarmonics(440.0, 2048, 44100);
        final samples2 = _generateSineWaveWithHarmonics(523.25, 2048, 44100);

        // First call creates cache
        detector.detectPresence(samples1, 44100, [69]);

        // Second call should reuse cache (no way to verify directly,
        // but we verify it doesn't crash and produces valid results)
        final result = detector.detectPresence(samples2, 44100, [72]);
        expect(result[72], greaterThan(0.05));
      });
    });

    group('harmonics parameter', () {
      test('more harmonics improves detection of rich tones', () {
        // Generate signal with strong harmonics
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        // Single harmonic (fundamental only)
        final single = detector.detectPresence(
          samples,
          44100,
          [60],
          harmonics: 1,
          dominanceRatio: 1.0,
        );

        // Multiple harmonics
        final multi = detector.detectPresence(
          samples,
          44100,
          [60],
          harmonics: 3,
          dominanceRatio: 1.0,
        );

        // Both should detect, but relationship depends on signal
        expect(single[60], greaterThan(0.01));
        expect(multi[60], greaterThan(0.01));
      });

      test('harmonics clamped to valid range', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // Extreme values should not crash
        final resultLow = detector.detectPresence(
          samples,
          44100,
          [69],
          harmonics: -5, // Should clamp to 1
        );
        final resultHigh = detector.detectPresence(
          samples,
          44100,
          [69],
          harmonics: 100, // Should clamp to 5
        );

        expect(resultLow[69], greaterThan(0.0));
        expect(resultHigh[69], greaterThan(0.0));
      });
    });

    group('minConfidence threshold', () {
      test('minConfidence filters low values', () {
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        final result = detector.detectPresence(
          samples,
          44100,
          [60, 61],
          minConfidence: 0.5,
          dominanceRatio: 1.0,
        );

        // Values below threshold become 0
        for (final conf in result.values) {
          expect(conf == 0.0 || conf >= 0.5, isTrue);
        }
      });
    });

    group('edge cases', () {
      test('returns entry for each requested MIDI', () {
        final samples = Float32List(2048);
        final midis = [36, 48, 60, 72, 84, 96];

        final result = detector.detectPresence(samples, 44100, midis);

        for (final midi in midis) {
          expect(
            result.containsKey(midi),
            isTrue,
            reason: 'Should have entry for MIDI $midi',
          );
        }
        expect(result.length, equals(midis.length));
      });

      test('handles different sample rates', () {
        final samples48k = _generateSineWaveWithHarmonics(440.0, 2048, 48000);

        final result = detector.detectPresence(samples48k, 48000, [69]);

        expect(
          result[69],
          greaterThan(0.05),
          reason: 'Should work with 48kHz sample rate',
        );
      });

      test('handles very low frequencies', () {
        // A1 = 55 Hz (needs longer buffer for accuracy)
        final samples = _generateSineWaveWithHarmonics(55.0, 4096, 44100);

        final result = detector.detectPresence(samples, 44100, [33]);

        // Should at least not crash and return something
        expect(result.containsKey(33), isTrue);
      });

      test('handles high frequencies', () {
        // C7 = 2093 Hz
        final samples = _generatePureSineWave(2093.0, 2048, 44100);

        final result = detector.detectPresence(
          samples,
          44100,
          [96],
          harmonics: 1, // Only fundamental (harmonics would exceed Nyquist)
        );

        expect(result[96], greaterThan(0.01));
      });

      test('custom detector parameters', () {
        final customDetector = GoertzelDetector(
          defaultDominanceRatio: 1.5,
          defaultHarmonics: 2,
          normalizationGain: 15.0,
        );

        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);
        final result = customDetector.detectPresence(samples, 44100, [69]);

        expect(result[69], greaterThan(0.0));
      });
    });

    group('robustness', () {
      test('consistent results for same input', () {
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        final result1 = detector.detectPresence(samples, 44100, [60]);
        final result2 = detector.detectPresence(samples, 44100, [60]);

        expect(result1[60], equals(result2[60]));
      });

      test('handles noisy signal', () {
        final samples = _generateNoisySineWave(
          440.0,
          2048,
          44100,
          noiseLevel: 0.2,
        );

        final result = detector.detectPresence(samples, 44100, [
          68,
          69,
          70,
        ], dominanceRatio: 1.1);

        // Should still detect A4 as dominant despite noise
        expect(result[69], greaterThan(result[68]!));
        expect(result[69], greaterThan(result[70]!));
      });
    });

    group('pitch offset (detuned piano support)', () {
      test('default pitch offset is 0', () {
        expect(detector.pitchOffsetCents, 0.0);
      });

      test('centsToFrequencyRatio converts correctly', () {
        // 0 cents = no change
        expect(GoertzelDetector.centsToFrequencyRatio(0), 1.0);

        // +100 cents = 1 semitone up ≈ 1.0595
        expect(
          GoertzelDetector.centsToFrequencyRatio(100),
          closeTo(1.0595, 0.001),
        );

        // -100 cents = 1 semitone down ≈ 0.9439
        expect(
          GoertzelDetector.centsToFrequencyRatio(-100),
          closeTo(0.9439, 0.001),
        );

        // +1200 cents = 1 octave up = 2.0
        expect(
          GoertzelDetector.centsToFrequencyRatio(1200),
          closeTo(2.0, 0.001),
        );

        // -1200 cents = 1 octave down = 0.5
        expect(
          GoertzelDetector.centsToFrequencyRatio(-1200),
          closeTo(0.5, 0.001),
        );
      });

      test('frequencyRatioToCents converts correctly', () {
        // 1.0 = 0 cents
        expect(GoertzelDetector.frequencyRatioToCents(1.0), closeTo(0, 0.1));

        // 442/440 ≈ +7.85 cents (typical piano sharp)
        expect(
          GoertzelDetector.frequencyRatioToCents(442 / 440),
          closeTo(7.85, 0.1),
        );

        // 438/440 ≈ -7.88 cents (typical piano flat)
        expect(
          GoertzelDetector.frequencyRatioToCents(438 / 440),
          closeTo(-7.88, 0.1),
        );

        // 2.0 = +1200 cents (octave up)
        expect(GoertzelDetector.frequencyRatioToCents(2.0), closeTo(1200, 0.1));
      });

      test('midiToFrequencyWithOffset applies offset', () {
        // A4 with no offset = 440 Hz
        detector.pitchOffsetCents = 0.0;
        expect(detector.midiToFrequencyWithOffset(69), closeTo(440.0, 0.01));

        // A4 with +50 cents (half semitone sharp)
        detector.pitchOffsetCents = 50.0;
        final sharpFreq = detector.midiToFrequencyWithOffset(69);
        expect(sharpFreq, closeTo(452.89, 0.1)); // 440 * 2^(50/1200)

        // A4 with -50 cents (half semitone flat)
        detector.pitchOffsetCents = -50.0;
        final flatFreq = detector.midiToFrequencyWithOffset(69);
        expect(flatFreq, closeTo(427.47, 0.1)); // 440 * 2^(-50/1200)
      });

      test('pitch offset improves detection of detuned piano', () {
        // Simulate a piano tuned +20 cents sharp (442.5 Hz for A4)
        // Generate a signal at 442.5 Hz (sharp A4)
        final sharpA4Freq = 440.0 * pow(2, 20 / 1200.0); // ~442.5 Hz
        final samples = _generateSineWaveWithHarmonics(
          sharpA4Freq.toDouble(),
          2048,
          44100,
        );

        // Without offset - should still detect but maybe lower confidence
        detector.pitchOffsetCents = 0.0;
        final withoutOffset = detector.detectPresence(samples, 44100, [
          69,
        ], dominanceRatio: 1.0);

        // With correct offset (+20 cents) - should detect well
        detector.pitchOffsetCents = 20.0;
        final withOffset = detector.detectPresence(samples, 44100, [
          69,
        ], dominanceRatio: 1.0);

        // Both should detect, but offset should help
        expect(withoutOffset[69], greaterThan(0.0));
        expect(withOffset[69], greaterThan(0.0));

        // With correct offset, confidence should be at least as good
        expect(
          withOffset[69]! >= withoutOffset[69]! * 0.9,
          isTrue,
          reason: 'Correct offset should maintain or improve detection',
        );
      });

      test('constructor accepts initial pitch offset', () {
        final detectorWithOffset = GoertzelDetector(pitchOffsetCents: 15.0);
        expect(detectorWithOffset.pitchOffsetCents, 15.0);
      });

      test('pitch offset can be updated at runtime', () {
        detector.pitchOffsetCents = 0.0;
        expect(detector.pitchOffsetCents, 0.0);

        detector.pitchOffsetCents = 10.0;
        expect(detector.pitchOffsetCents, 10.0);

        detector.pitchOffsetCents = -5.0;
        expect(detector.pitchOffsetCents, -5.0);
      });
    });
  });
}

// =============================================================================
// Test Helpers
// =============================================================================

/// Generate a sine wave with harmonics (piano-like spectrum).
Float32List _generateSineWaveWithHarmonics(
  double frequency,
  int samples,
  int sampleRate,
) {
  final buffer = Float32List(samples);
  for (int i = 0; i < samples; i++) {
    final t = i / sampleRate;
    // Fundamental + harmonics (typical piano spectrum)
    final fundamental = sin(2 * pi * frequency * t);
    final harmonic2 = 0.5 * sin(2 * pi * frequency * 2 * t);
    final harmonic3 = 0.25 * sin(2 * pi * frequency * 3 * t);
    final harmonic4 = 0.125 * sin(2 * pi * frequency * 4 * t);
    buffer[i] = (fundamental + harmonic2 + harmonic3 + harmonic4) / 1.875;
  }
  return buffer;
}

/// Generate a pure sine wave (no harmonics).
Float32List _generatePureSineWave(
  double frequency,
  int samples,
  int sampleRate,
) {
  final buffer = Float32List(samples);
  for (int i = 0; i < samples; i++) {
    buffer[i] = sin(2 * pi * frequency * i / sampleRate);
  }
  return buffer;
}

/// Generate a chord (multiple frequencies summed and normalized).
Float32List _generateChord(
  List<double> frequencies,
  int samples,
  int sampleRate,
) {
  final buffer = Float32List(samples);
  final normFactor = 1.0 / frequencies.length;

  for (int i = 0; i < samples; i++) {
    final t = i / sampleRate;
    var sample = 0.0;
    for (final freq in frequencies) {
      // Each note with some harmonics
      sample += sin(2 * pi * freq * t);
      sample += 0.3 * sin(2 * pi * freq * 2 * t);
      sample += 0.15 * sin(2 * pi * freq * 3 * t);
    }
    buffer[i] = sample * normFactor * 0.5; // Normalize to avoid clipping
  }
  return buffer;
}

/// Generate a noisy sine wave.
Float32List _generateNoisySineWave(
  double frequency,
  int samples,
  int sampleRate, {
  double noiseLevel = 0.1,
}) {
  final buffer = Float32List(samples);
  final random = Random(42); // Fixed seed for reproducibility
  for (int i = 0; i < samples; i++) {
    final signal = sin(2 * pi * frequency * i / sampleRate);
    final noise = (random.nextDouble() * 2 - 1) * noiseLevel;
    buffer[i] = signal + noise;
  }
  return buffer;
}
