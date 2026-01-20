import 'package:flutter/foundation.dart';

import 'yin_pitch_service.dart';
import 'goertzel_detector.dart';

/// Pitch event data produced by the router.
///
/// This mirrors the PitchEvent structure in mic_engine.dart
/// to allow seamless integration.
class RouterPitchEvent {
  const RouterPitchEvent({
    required this.tSec,
    required this.midi,
    required this.freq,
    required this.conf,
    required this.rms,
    this.stabilityFrames = 1,
  });

  final double tSec;
  final int midi;
  final double freq;
  final double conf;
  final double rms;
  final int stabilityFrames;
}

/// Detection mode used for the current frame.
enum DetectionMode {
  /// No detection (empty expected notes).
  none,

  /// Single note detection using YIN algorithm.
  yin,

  /// Chord/multi-note detection using Goertzel algorithm.
  goertzel,
}

/// Routes pitch detection between YIN (mono-note) and Goertzel (chords).
///
/// This router decides which algorithm to use based on the number of
/// expected notes:
/// - 0 expected notes → no detection
/// - 1 expected note → YIN (precise pitch detection)
/// - 2+ expected notes → Goertzel (multi-bin presence detection)
///
/// The router does NOT modify scoring logic - it only produces PitchEvents.
class PracticePitchRouter {
  PracticePitchRouter({
    YinPitchService? yinService,
    GoertzelDetector? goertzelDetector,
    this.snapSemitoneTolerance = 0, // STRICT: C4 ≠ C#4, no tolerance
  }) : _yin = yinService ?? YinPitchService(),
       _goertzel = goertzelDetector ?? GoertzelDetector();

  /// Semitone tolerance for snapping detected pitch to expected (mono mode).
  /// Default 0 = strict precision (C4 ≠ C#4).
  /// Set to 1 for lenient mode (snaps if within 1 semitone).
  final int snapSemitoneTolerance;

  final YinPitchService _yin;
  final GoertzelDetector _goertzel;

  /// Last detection mode used (for debugging/logging).
  DetectionMode _lastMode = DetectionMode.none;
  DetectionMode get lastMode => _lastMode;

  /// Decide which algorithm to use and produce pitch events.
  ///
  /// Parameters:
  /// - [samples]: Audio buffer (mono, Float32List)
  /// - [sampleRate]: Sample rate in Hz
  /// - [activeExpectedMidis]: MIDI notes currently expected (active window)
  /// - [rms]: RMS level of the current audio chunk
  /// - [tSec]: Current elapsed time in seconds
  /// - [maxSimultaneousNotes]: Max notes to return for chords (default 3)
  /// - [goertzelDominanceRatio]: Dominance ratio for Goertzel (default 1.25)
  /// - [goertzelHarmonics]: Number of harmonics for Goertzel (default 3)
  /// - [goertzelMinConfidence]: Minimum confidence for Goertzel (default 0.08)
  /// - [yinMinConfidence]: Minimum confidence for YIN (default 0.40)
  List<RouterPitchEvent> decide({
    required Float32List samples,
    required int sampleRate,
    required List<int> activeExpectedMidis,
    required double rms,
    required double tSec,
    int maxSimultaneousNotes = 3,
    double goertzelDominanceRatio = 1.25,
    int goertzelHarmonics = 3,
    double goertzelMinConfidence = 0.08,
    double yinMinConfidence = 0.40,
  }) {
    // No expected notes → no detection
    if (activeExpectedMidis.isEmpty) {
      _lastMode = DetectionMode.none;
      return [];
    }

    // Single note → use YIN for precise pitch detection
    if (activeExpectedMidis.length == 1) {
      _lastMode = DetectionMode.yin;
      return _detectWithYin(
        samples: samples,
        sampleRate: sampleRate,
        expectedMidi: activeExpectedMidis.first,
        rms: rms,
        tSec: tSec,
        minConfidence: yinMinConfidence,
      );
    }

    // Multiple notes → use Goertzel for chord detection
    _lastMode = DetectionMode.goertzel;
    return _detectWithGoertzel(
      samples: samples,
      sampleRate: sampleRate,
      activeExpectedMidis: activeExpectedMidis,
      rms: rms,
      tSec: tSec,
      maxSimultaneousNotes: maxSimultaneousNotes,
      dominanceRatio: goertzelDominanceRatio,
      harmonics: goertzelHarmonics,
      minConfidence: goertzelMinConfidence,
    );
  }

  /// Detect pitch using YIN algorithm with tolerant snap.
  ///
  /// Returns 0 or 1 PitchEvent depending on whether a valid pitch is found.
  /// If detected MIDI is within [snapSemitoneTolerance] of expected, snaps to expected.
  /// This avoids rejecting notes with minor pitch drift while allowing wrongFlash.
  List<RouterPitchEvent> _detectWithYin({
    required Float32List samples,
    required int sampleRate,
    required int expectedMidi,
    required double rms,
    required double tSec,
    required double minConfidence,
  }) {
    // YIN needs sufficient samples
    if (samples.length < _yin.requiredBufferSize) {
      return [];
    }

    // Detect pitch
    final freq = _yin.detectPitch(samples, sampleRate: sampleRate);

    // No valid pitch detected
    if (freq == null || freq <= 0 || freq < 50.0 || freq > 2000.0) {
      return [];
    }

    // Convert to MIDI
    final detectedMidi = _yin.frequencyToMidiNote(freq);

    // Compute confidence from RMS (same heuristic as MicEngine)
    final conf = (rms / 0.05).clamp(0.0, 1.0);

    // Filter weak detections
    if (conf < minConfidence) {
      return [];
    }

    // Tolerant snap: if within tolerance, snap to expected
    // This avoids rejecting notes with minor pitch drift
    final distance = (detectedMidi - expectedMidi).abs();
    final snappedMidi = distance <= snapSemitoneTolerance
        ? expectedMidi
        : detectedMidi;

    // Debug log (grep-friendly YIN_CALLED format)
    if (kDebugMode) {
      debugPrint(
        'YIN_CALLED expected=[$expectedMidi] detectedMidi=$detectedMidi '
        'snappedMidi=$snappedMidi freq=${freq.toStringAsFixed(1)} conf=${conf.toStringAsFixed(2)}',
      );
    }

    return [
      RouterPitchEvent(
        tSec: tSec,
        midi: snappedMidi,
        freq: freq,
        conf: conf,
        rms: rms,
        stabilityFrames: 1,
      ),
    ];
  }

  /// Detect notes using Goertzel algorithm.
  ///
  /// Returns up to [maxSimultaneousNotes] PitchEvents for detected notes.
  List<RouterPitchEvent> _detectWithGoertzel({
    required Float32List samples,
    required int sampleRate,
    required List<int> activeExpectedMidis,
    required double rms,
    required double tSec,
    required int maxSimultaneousNotes,
    required double dominanceRatio,
    required int harmonics,
    required double minConfidence,
  }) {
    // Detect presence of all expected notes
    final presenceMap = _goertzel.detectPresence(
      samples,
      sampleRate,
      activeExpectedMidis,
      dominanceRatio: dominanceRatio,
      harmonics: harmonics,
      minConfidence: minConfidence,
    );

    // Filter notes above threshold and sort by confidence (descending)
    final detected =
        presenceMap.entries.where((e) => e.value >= minConfidence).toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    // Take top N notes
    final topNotes = detected.take(maxSimultaneousNotes).toList();

    // Debug log (grep-friendly GOERTZEL_CALLED format)
    if (kDebugMode) {
      final presentList = topNotes
          .map((e) => '(${e.key},${e.value.toStringAsFixed(2)})')
          .join(',');
      debugPrint(
        'GOERTZEL_CALLED targets=$activeExpectedMidis present=[$presentList]',
      );
    }

    // Convert to PitchEvents
    return topNotes.map((entry) {
      final midi = entry.key;
      final conf = entry.value;
      final freq = GoertzelDetector.midiToFrequency(midi);

      return RouterPitchEvent(
        tSec: tSec,
        midi: midi,
        freq: freq,
        conf: conf,
        rms: rms,
        stabilityFrames: 1,
      );
    }).toList();
  }

  /// Debug log helper for hybrid detection.
  static void debugLog({
    required double tSec,
    required int expectedCount,
    required int eventsCount,
    required DetectionMode mode,
  }) {
    if (kDebugMode) {
      final modeStr = mode == DetectionMode.yin
          ? 'YIN'
          : mode == DetectionMode.goertzel
          ? 'GOERTZEL'
          : 'NONE';
      debugPrint(
        'HYBRID_DETECT t=${tSec.toStringAsFixed(3)} '
        'expected=$expectedCount events=$eventsCount mode=$modeStr',
      );
    }
  }
}
