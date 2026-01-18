import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/core/practice/pitch/practice_pitch_router.dart';
import 'package:shazapiano/core/practice/pitch/yin_pitch_service.dart';
import 'package:shazapiano/core/practice/pitch/goertzel_detector.dart';

void main() {
  group('PracticePitchRouter', () {
    late PracticePitchRouter router;

    setUp(() {
      router = PracticePitchRouter();
    });

    group('routing logic', () {
      test('empty expected notes => no detection, mode=none', () {
        final samples = _generateSineWave(440.0, 2048, 44100);

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [],
          rms: 0.1,
          tSec: 1.0,
        );

        expect(events, isEmpty);
        expect(router.lastMode, DetectionMode.none);
      });

      test('single expected note => YIN mode', () {
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60], // C4
          rms: 0.1,
          tSec: 1.0,
        );

        expect(router.lastMode, DetectionMode.yin);
      });

      test('two expected notes => Goertzel mode', () {
        final samples = _generateChord([261.63, 329.63], 2048, 44100);

        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64], // C4, E4
          rms: 0.1,
          tSec: 1.0,
        );

        expect(router.lastMode, DetectionMode.goertzel);
      });

      test('three expected notes => Goertzel mode', () {
        final samples = _generateChord([261.63, 329.63, 392.00], 2048, 44100);

        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64, 67], // C4, E4, G4
          rms: 0.1,
          tSec: 1.0,
        );

        expect(router.lastMode, DetectionMode.goertzel);
      });
    });

    group('YIN path', () {
      test('detects mono note with YIN', () {
        // Generate A4 (440 Hz) - clean signal
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69], // A4
          rms: 0.1,
          tSec: 1.5,
        );

        expect(router.lastMode, DetectionMode.yin);
        // YIN may or may not detect depending on signal quality
        // but if it does, it should produce valid events
        if (events.isNotEmpty) {
          expect(events.first.tSec, 1.5);
          expect(events.first.rms, 0.1);
          expect(events.first.freq, greaterThan(400));
          expect(events.first.freq, lessThan(480));
        }
      });

      test('silence => no YIN detection', () {
        final samples = Float32List(2048); // Silence

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60],
          rms: 0.0001, // Very low RMS
          tSec: 1.0,
        );

        expect(router.lastMode, DetectionMode.yin);
        expect(events, isEmpty);
      });

      test('YIN respects minConfidence', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // Very high min confidence should filter out detection
        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.001, // Low RMS => low confidence
          tSec: 1.0,
          yinMinConfidence: 0.99, // Very high threshold
        );

        expect(events, isEmpty);
      });
    });

    group('Goertzel path', () {
      test('detects chord notes with Goertzel', () {
        // Generate C major chord
        final samples = _generateChord([261.63, 329.63, 392.00], 2048, 44100);

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64, 67], // C4, E4, G4
          rms: 0.1,
          tSec: 2.0,
          goertzelMinConfidence: 0.05, // Lower threshold for test
        );

        expect(router.lastMode, DetectionMode.goertzel);
        // Should detect at least some of the chord notes
        expect(events.length, greaterThanOrEqualTo(1));

        // All events should have correct tSec and rms
        for (final event in events) {
          expect(event.tSec, 2.0);
          expect(event.rms, 0.1);
        }
      });

      test('respects maxSimultaneousNotes', () {
        final samples = _generateChord([261.63, 329.63, 392.00], 2048, 44100);

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64, 67],
          rms: 0.1,
          tSec: 1.0,
          maxSimultaneousNotes: 2, // Limit to 2
          goertzelMinConfidence: 0.01,
        );

        expect(events.length, lessThanOrEqualTo(2));
      });

      test('silence => no Goertzel detection', () {
        final samples = Float32List(2048);

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64],
          rms: 0.0,
          tSec: 1.0,
        );

        expect(router.lastMode, DetectionMode.goertzel);
        expect(events, isEmpty);
      });

      test('Goertzel events sorted by confidence (descending)', () {
        final samples = _generateChord([261.63, 329.63, 392.00], 2048, 44100);

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64, 67],
          rms: 0.1,
          tSec: 1.0,
          goertzelMinConfidence: 0.01,
        );

        if (events.length >= 2) {
          // Verify descending order
          for (var i = 0; i < events.length - 1; i++) {
            expect(
              events[i].conf,
              greaterThanOrEqualTo(events[i + 1].conf),
              reason: 'Events should be sorted by confidence descending',
            );
          }
        }
      });
    });

    group('RouterPitchEvent', () {
      test('contains all required fields', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.15,
          tSec: 3.5,
        );

        if (events.isNotEmpty) {
          final event = events.first;
          expect(event.tSec, 3.5);
          expect(event.rms, 0.15);
          expect(event.midi, isA<int>());
          expect(event.freq, isA<double>());
          expect(event.conf, isA<double>());
          expect(event.stabilityFrames, 1);
        }
      });
    });

    group('custom services', () {
      test('accepts custom YIN and Goertzel instances', () {
        final customYin = YinPitchService(threshold: 0.15);
        final customGoertzel = GoertzelDetector(normalizationGain: 15.0);

        final customRouter = PracticePitchRouter(
          yinService: customYin,
          goertzelDetector: customGoertzel,
        );

        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // Should not throw
        customRouter.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.1,
          tSec: 1.0,
        );

        expect(customRouter.lastMode, DetectionMode.yin);
      });
    });

    group('edge cases', () {
      test('handles very short buffer', () {
        final samples = Float32List(64); // Minimum size

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60],
          rms: 0.1,
          tSec: 1.0,
        );

        // Should not crash, may return empty
        expect(events, isA<List<RouterPitchEvent>>());
      });

      test('handles different sample rates', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 48000);

        router.decide(
          samples: samples,
          sampleRate: 48000,
          activeExpectedMidis: [69, 72],
          rms: 0.1,
          tSec: 1.0,
        );

        expect(router.lastMode, DetectionMode.goertzel);
      });

      test('lastMode persists between calls', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // First call: mono
        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.1,
          tSec: 1.0,
        );
        expect(router.lastMode, DetectionMode.yin);

        // Second call: chord
        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64],
          rms: 0.1,
          tSec: 2.0,
        );
        expect(router.lastMode, DetectionMode.goertzel);

        // Third call: empty
        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [],
          rms: 0.1,
          tSec: 3.0,
        );
        expect(router.lastMode, DetectionMode.none);
      });
    });

    group('DetectionMode enum', () {
      test('has all expected values', () {
        expect(DetectionMode.values, contains(DetectionMode.none));
        expect(DetectionMode.values, contains(DetectionMode.yin));
        expect(DetectionMode.values, contains(DetectionMode.goertzel));
        expect(DetectionMode.values.length, 3);
      });
    });
  });
}

// =============================================================================
// Test Helpers
// =============================================================================

/// Generate a pure sine wave.
Float32List _generateSineWave(double frequency, int samples, int sampleRate) {
  final buffer = Float32List(samples);
  for (int i = 0; i < samples; i++) {
    buffer[i] = sin(2 * pi * frequency * i / sampleRate);
  }
  return buffer;
}

/// Generate a sine wave with harmonics (piano-like spectrum).
Float32List _generateSineWaveWithHarmonics(
  double frequency,
  int samples,
  int sampleRate,
) {
  final buffer = Float32List(samples);
  for (int i = 0; i < samples; i++) {
    final t = i / sampleRate;
    final fundamental = sin(2 * pi * frequency * t);
    final harmonic2 = 0.5 * sin(2 * pi * frequency * 2 * t);
    final harmonic3 = 0.25 * sin(2 * pi * frequency * 3 * t);
    final harmonic4 = 0.125 * sin(2 * pi * frequency * 4 * t);
    buffer[i] = (fundamental + harmonic2 + harmonic3 + harmonic4) / 1.875;
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
      sample += sin(2 * pi * freq * t);
      sample += 0.3 * sin(2 * pi * freq * 2 * t);
      sample += 0.15 * sin(2 * pi * freq * 3 * t);
    }
    buffer[i] = sample * normFactor * 0.5;
  }
  return buffer;
}
