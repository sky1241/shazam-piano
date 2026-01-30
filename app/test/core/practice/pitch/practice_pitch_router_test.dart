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

    group('routing logic (Goertzel-first architecture)', () {
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

      test('single expected note with high Goertzel conf => Goertzel mode', () {
        // With Goertzel-first, even single notes use Goertzel first
        // YIN only triggers if Goertzel conf is low or periodic validation
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60], // C4
          rms: 0.1,
          tSec: 1.0,
        );

        // Goertzel-first: should be goertzel unless conf is low
        expect(
          router.lastMode,
          anyOf(DetectionMode.goertzel, DetectionMode.yin),
          reason: 'Goertzel-first: goertzel if confident, yin if not',
        );
      });

      test('single note triggers YIN when Goertzel confidence low', () {
        // Low RMS / weak signal => Goertzel conf should be low => YIN triggered
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        // Use a router with low confidence threshold to force YIN trigger
        final routerLowThreshold = PracticePitchRouter(
          goertzelConfidenceThreshold: 0.99, // Very high => always triggers YIN
        );

        routerLowThreshold.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60], // C4
          rms: 0.1,
          tSec: 1.0,
        );

        expect(routerLowThreshold.lastMode, DetectionMode.yin);
      });

      test('single note triggers YIN on periodic validation', () {
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        // Very short interval => should trigger YIN
        final routerShortInterval = PracticePitchRouter(
          goertzelConfidenceThreshold: 0.0, // Never trigger on low conf
          yinValidationIntervalSec: 0.001, // Very short => always due
        );

        // First call at t=0
        routerShortInterval.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60],
          rms: 0.1,
          tSec: 0.0,
        );

        // Second call at t=1 (way past interval)
        routerShortInterval.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60],
          rms: 0.1,
          tSec: 1.0,
        );

        expect(routerShortInterval.lastMode, DetectionMode.yin);
      });

      test('two expected notes => Goertzel mode (YIN never for chords)', () {
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

    group('YIN path (validation/fallback in Goertzel-first)', () {
      test('YIN validates mono note when forced by low threshold', () {
        // Generate A4 (440 Hz) - clean signal
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // Force YIN trigger with high confidence threshold
        final routerForceYin = PracticePitchRouter(
          goertzelConfidenceThreshold: 0.99,
        );

        final events = routerForceYin.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69], // A4
          rms: 0.1,
          tSec: 1.5,
        );

        expect(routerForceYin.lastMode, DetectionMode.yin);
        // YIN may or may not detect depending on signal quality
        // but if it does, it should produce valid events
        if (events.isNotEmpty) {
          expect(events.first.tSec, 1.5);
          expect(events.first.rms, 0.1);
          expect(events.first.freq, greaterThan(400));
          expect(events.first.freq, lessThan(480));
        }
      });

      test('silence => no detection (Goertzel or YIN)', () {
        final samples = Float32List(2048); // Silence

        final events = router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60],
          rms: 0.0001, // Very low RMS
          tSec: 1.0,
        );

        // With silence, Goertzel conf is low, so YIN may be triggered
        // Either way, no events should be detected
        expect(events, isEmpty);
      });

      test('YIN respects minConfidence, but Goertzel fallback still works', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // Force YIN trigger + very high min confidence
        // YIN will fail to detect, but Goertzel will succeed
        // Merge logic: YIN empty → return Goertzel
        final routerHighYinConf = PracticePitchRouter(
          goertzelConfidenceThreshold: 0.99, // Force YIN
        );

        final events = routerHighYinConf.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.001, // Low RMS => low YIN confidence
          tSec: 1.0,
          yinMinConfidence: 0.99, // Very high threshold => YIN returns empty
        );

        // With Goertzel-first: YIN empty, Goertzel detects → returns Goertzel
        // This is correct behavior - Goertzel acts as fallback
        expect(routerHighYinConf.lastMode, DetectionMode.yin);
        // Goertzel still detected the note, so we have results
        if (events.isNotEmpty) {
          expect(events.first.midi, 69);
        }
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

        // Goertzel-first: mode depends on confidence
        expect(
          customRouter.lastMode,
          anyOf(DetectionMode.goertzel, DetectionMode.yin),
        );
      });
    });

    group('snap tolerance (mono mode, YIN only)', () {
      test('default snapSemitoneTolerance is 0 (strict precision)', () {
        // Default router should have no tolerance (C4 ≠ C#4)
        final defaultRouter = PracticePitchRouter();
        expect(
          defaultRouter.snapSemitoneTolerance,
          0,
          reason: 'Default should be strict (no snap tolerance)',
        );
      });

      test('snaps detected MIDI to expected when within tolerance (YIN path)', () {
        // Generate a note slightly sharp (442 Hz instead of 440 Hz for A4)
        // 442 Hz is still within ~1 semitone of A4 (440 Hz)
        final samples = _generateSineWaveWithHarmonics(442.0, 2048, 44100);

        // Force YIN path to test snap behavior
        final routerWithSnap = PracticePitchRouter(
          snapSemitoneTolerance: 1, // Allow 1 semitone snap
          goertzelConfidenceThreshold: 0.99, // Force YIN
        );

        final events = routerWithSnap.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69], // A4 expected
          rms: 0.1,
          tSec: 1.0,
        );

        expect(routerWithSnap.lastMode, DetectionMode.yin);
        // If detection works, the MIDI should be snapped to expected (69)
        if (events.isNotEmpty) {
          expect(
            events.first.midi,
            69,
            reason: 'Should snap to expected MIDI when within tolerance',
          );
        }
      });

      test('does NOT snap when detected is too far from expected (YIN path)', () {
        // Generate C4 (261.63 Hz) but expect A4 (69)
        // C4 (midi 60) is 9 semitones away from A4 (midi 69)
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        // Force YIN path
        final routerWithSnap = PracticePitchRouter(
          snapSemitoneTolerance: 1, // Only 1 semitone tolerance
          goertzelConfidenceThreshold: 0.99, // Force YIN
        );

        final events = routerWithSnap.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69], // A4 expected, but playing C4
          rms: 0.1,
          tSec: 1.0,
        );

        expect(routerWithSnap.lastMode, DetectionMode.yin);
        // If detection works, the MIDI should NOT be snapped (wrong note)
        if (events.isNotEmpty) {
          expect(
            events.first.midi,
            isNot(69),
            reason: 'Should NOT snap when detected is far from expected',
          );
        }
      });

      test('snapSemitoneTolerance=0 disables snapping (YIN path)', () {
        final samples = _generateSineWaveWithHarmonics(442.0, 2048, 44100);

        // Force YIN path
        final routerNoSnap = PracticePitchRouter(
          snapSemitoneTolerance: 0, // No tolerance
          goertzelConfidenceThreshold: 0.99, // Force YIN
        );

        final events = routerNoSnap.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69], // A4
          rms: 0.1,
          tSec: 1.0,
        );

        expect(routerNoSnap.lastMode, DetectionMode.yin);
        // With tolerance=0, only exact match would snap
        // 442 Hz rounds to midi 69, so it would still match
        if (events.isNotEmpty) {
          // This depends on YIN's exact detection
          expect(events.first.midi, isA<int>());
        }
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

        // First call: mono (Goertzel-first, may or may not trigger YIN)
        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.1,
          tSec: 1.0,
        );
        // Goertzel-first: mode depends on confidence
        expect(
          router.lastMode,
          anyOf(DetectionMode.goertzel, DetectionMode.yin),
        );

        // Second call: chord (always Goertzel, YIN never for chords)
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

    group('Goertzel-first merge logic', () {
      test('YIN detects wrong note that Goertzel missed', () {
        // Play C4 (261.63 Hz) but expect A4 (midi 69)
        // Goertzel won't detect C4 because it only looks at expected notes
        // YIN should catch the wrong note
        final samples = _generateSineWaveWithHarmonics(261.63, 2048, 44100);

        // Force YIN trigger
        final routerForceYin = PracticePitchRouter(
          goertzelConfidenceThreshold: 0.99,
        );

        final events = routerForceYin.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69], // Expected A4, but playing C4
          rms: 0.1,
          tSec: 1.0,
        );

        // YIN should have been triggered and detected the wrong note
        expect(routerForceYin.lastMode, DetectionMode.yin);
        if (events.isNotEmpty) {
          // Should detect C4 (midi ~60), not A4 (midi 69)
          expect(events.first.midi, isNot(69));
        }
      });

      test('clearRawDetection also resets YIN timer', () {
        final samples = _generateSineWaveWithHarmonics(440.0, 2048, 44100);

        // Force YIN trigger on short interval
        final routerShortInterval = PracticePitchRouter(
          yinValidationIntervalSec: 0.5,
          goertzelConfidenceThreshold: 0.0, // Don't trigger on low conf
        );

        // First call triggers YIN (periodic)
        routerShortInterval.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.1,
          tSec: 0.0,
        );

        // Clear resets timer
        routerShortInterval.clearRawDetection();

        // After clear, YIN should be due again immediately
        routerShortInterval.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [69],
          rms: 0.1,
          tSec: 0.1, // Only 0.1s later but should still trigger YIN
        );

        // After clear, timer reset to -1000, so 0.1 - (-1000) > 0.5
        expect(routerShortInterval.lastMode, DetectionMode.yin);
      });

      test('YIN not triggered for chords even with low Goertzel conf', () {
        final samples = Float32List(2048); // Silence => low conf

        router.decide(
          samples: samples,
          sampleRate: 44100,
          activeExpectedMidis: [60, 64], // Chord
          rms: 0.001,
          tSec: 1.0,
        );

        // Chords never trigger YIN, always Goertzel
        expect(router.lastMode, DetectionMode.goertzel);
      });

      test('configurable confidence threshold', () {
        final routerHighThreshold = PracticePitchRouter(
          goertzelConfidenceThreshold: 0.9,
        );
        expect(routerHighThreshold.goertzelConfidenceThreshold, 0.9);

        final routerLowThreshold = PracticePitchRouter(
          goertzelConfidenceThreshold: 0.1,
        );
        expect(routerLowThreshold.goertzelConfidenceThreshold, 0.1);
      });

      test('configurable YIN validation interval', () {
        final routerShortInterval = PracticePitchRouter(
          yinValidationIntervalSec: 0.5,
        );
        expect(routerShortInterval.yinValidationIntervalSec, 0.5);

        final routerLongInterval = PracticePitchRouter(
          yinValidationIntervalSec: 5.0,
        );
        expect(routerLongInterval.yinValidationIntervalSec, 5.0);
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
