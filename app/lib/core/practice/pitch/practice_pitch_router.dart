import 'dart:math' show max;

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

/// Routes pitch detection between Goertzel (fast) and YIN (validation).
///
/// ARCHITECTURE (Goertzel-first):
/// - 0 expected notes → no detection
/// - 1+ expected notes → Goertzel ALWAYS runs first (fast, ~5ms)
/// - YIN runs as backup ONLY when:
///   - Single note expected AND
///   - (Goertzel confidence < threshold OR periodic validation)
///
/// This provides:
/// - Fast response time (Goertzel is O(N) per frequency)
/// - YIN validation catches wrong notes Goertzel can't see
/// - Lower CPU usage (YIN runs occasionally, not every frame)
///
/// The router does NOT modify scoring logic - it only produces PitchEvents.
class PracticePitchRouter {
  PracticePitchRouter({
    YinPitchService? yinService,
    GoertzelDetector? goertzelDetector,
    this.snapSemitoneTolerance = 0,
    this.goertzelConfidenceThreshold = 0.5,
    this.yinValidationIntervalSec = 1.0,
    this.yinWarmupPeriodSec = 1.5,
    this.yinMinRmsForOverride = 0.05,
    this.yinRmsNoiseMultiplier = 3.0,
  }) : _yin = yinService ?? YinPitchService(),
       _goertzel = goertzelDetector ?? GoertzelDetector();

  /// Goertzel confidence threshold below which YIN is triggered for validation.
  /// Default 0.5 (after normalization × 12, good signals reach 0.6-0.9).
  final double goertzelConfidenceThreshold;

  /// Maximum interval between YIN validation calls (seconds).
  /// Even if Goertzel is confident, YIN runs at least this often for drift detection.
  final double yinValidationIntervalSec;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-052: YIN WARMUP GUARD - Prevent YIN hallucinations on weak signals
  // ══════════════════════════════════════════════════════════════════════════

  /// Warmup period in seconds during which YIN override is blocked.
  /// During this period, if Goertzel returns low conf but YIN detects a different
  /// note, we trust Goertzel (or return empty) instead of YIN's potentially
  /// hallucinated detection from noise/reverb.
  /// Default 1.5s = typical mic/baseline warmup time.
  final double yinWarmupPeriodSec;

  /// Minimum RMS required for YIN to override Goertzel with a different note.
  /// If RMS < this threshold, YIN's "different note" detection is ignored
  /// to prevent false WRONG flashes from weak signals.
  /// Default 0.05 = clearly audible note (not noise/reverb artifact).
  final double yinMinRmsForOverride;

  /// Multiplier for noise floor to compute dynamic RMS threshold.
  /// YIN override is only trusted when RMS > noiseFloor * multiplier.
  /// Default 3.0 = signal must be 3x above noise floor.
  final double yinRmsNoiseMultiplier;

  /// Noise floor RMS (set during countdown calibration).
  /// Used to compute dynamic threshold for YIN override trust.
  double _noiseFloorRms = 0.0;

  /// Set the noise floor RMS for dynamic YIN trust threshold.
  set noiseFloorRms(double value) => _noiseFloorRms = value;

  /// Timestamp of last YIN validation call.
  double _lastYinTimeSec = -1000.0;

  /// Semitone tolerance for snapping detected pitch to expected (mono mode).
  /// Default 0 = strict mode (no tolerance, C4 != C#4).
  /// Set to 1 for lenient mode (snaps if within 1 semitone).
  final int snapSemitoneTolerance;

  final YinPitchService _yin;
  final GoertzelDetector _goertzel;

  /// Last detection mode used (for debugging/logging).
  DetectionMode _lastMode = DetectionMode.none;
  DetectionMode get lastMode => _lastMode;

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION-037: Raw detection (BEFORE confidence filtering) for "REAL-TIME FEEL"
  // These fields capture what YIN detected even if confidence is too low
  // for scoring. This allows UI to show BLUE feedback for any detected pitch.
  // ═══════════════════════════════════════════════════════════════════════════
  int? _lastRawMidi;
  double? _lastRawFreq;
  double? _lastRawConf;
  double _lastRawTSec = -1000.0;
  String _lastRawSource = 'none';

  int? get lastRawMidi => _lastRawMidi;
  double? get lastRawFreq => _lastRawFreq;
  double? get lastRawConf => _lastRawConf;
  double get lastRawTSec => _lastRawTSec;
  String get lastRawSource => _lastRawSource;

  /// Clear raw detection state (on reset)
  void clearRawDetection() {
    _lastRawMidi = null;
    _lastRawFreq = null;
    _lastRawConf = null;
    _lastRawTSec = -1000.0;
    _lastRawSource = 'none';
    _lastYinTimeSec = -1000.0;
    _noiseFloorRms = 0.0; // SESSION-052: Reset noise floor on session reset
  }

  /// Decide which algorithm to use and produce pitch events.
  ///
  /// GOERTZEL-FIRST ARCHITECTURE:
  /// 1. Goertzel runs ALWAYS (fast, targeted detection)
  /// 2. YIN runs ONLY when mono + (low confidence OR periodic validation)
  /// 3. Results are merged: YIN wins if it detects a different note (WRONG)
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

    // ══════════════════════════════════════════════════════════════════════════
    // STEP 1: GOERTZEL ALWAYS RUNS FIRST (even for single note)
    // ══════════════════════════════════════════════════════════════════════════
    final goertzelResults = _detectWithGoertzel(
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

    // Find best Goertzel confidence
    final bestGoertzelConf = goertzelResults.isEmpty
        ? 0.0
        : goertzelResults.map((e) => e.conf).reduce(max);

    // ══════════════════════════════════════════════════════════════════════════
    // STEP 2: YIN CONDITIONAL (mono only, when needed)
    // ══════════════════════════════════════════════════════════════════════════
    final isMono = activeExpectedMidis.length == 1;
    final goertzelNeedsHelp = bestGoertzelConf < goertzelConfidenceThreshold;
    final yinValidationDue =
        (tSec - _lastYinTimeSec) > yinValidationIntervalSec;

    final shouldRunYin = isMono && (goertzelNeedsHelp || yinValidationDue);

    if (shouldRunYin) {
      _lastYinTimeSec = tSec;

      final yinResults = _detectWithYin(
        samples: samples,
        sampleRate: sampleRate,
        expectedMidi: activeExpectedMidis.first,
        rms: rms,
        tSec: tSec,
        minConfidence: yinMinConfidence,
      );

      // ════════════════════════════════════════════════════════════════════════
      // STEP 3: MERGE RESULTS (with SESSION-052 warmup/RMS guards)
      // ════════════════════════════════════════════════════════════════════════
      final merged = _mergeResults(
        goertzelResults: goertzelResults,
        yinResults: yinResults,
        expectedMidi: activeExpectedMidis.first,
        tSec: tSec,
        rms: rms,
      );

      // Debug log
      if (kDebugMode) {
        debugPrint(
          'ROUTER_YIN_TRIGGERED t=${tSec.toStringAsFixed(2)} '
          'goertzelConf=${bestGoertzelConf.toStringAsFixed(2)} '
          'reason=${goertzelNeedsHelp ? "lowConf" : "periodic"} '
          'yinMidi=${yinResults.isNotEmpty ? yinResults.first.midi : "none"} '
          'merged=${merged.isNotEmpty ? merged.first.midi : "none"}',
        );
      }

      _lastMode = DetectionMode.yin;
      return merged;
    }

    // No YIN needed, return Goertzel results directly
    _lastMode = DetectionMode.goertzel;
    return goertzelResults;
  }

  /// Merge Goertzel and YIN results with smart conflict resolution.
  ///
  /// Rules:
  /// - If Goertzel found the expected note and YIN confirms → Goertzel wins (faster)
  /// - If Goertzel found nothing but YIN did → YIN wins
  /// - If YIN detects a DIFFERENT note than expected → YIN wins (to detect WRONG)
  ///   UNLESS we're in warmup period OR RMS is too low (SESSION-052 guard)
  /// - If both empty → empty
  List<RouterPitchEvent> _mergeResults({
    required List<RouterPitchEvent> goertzelResults,
    required List<RouterPitchEvent> yinResults,
    required int expectedMidi,
    required double tSec,
    required double rms,
  }) {
    // Case 1: Both empty
    if (goertzelResults.isEmpty && yinResults.isEmpty) {
      return [];
    }

    // Case 2: YIN empty → trust Goertzel
    if (yinResults.isEmpty) {
      return goertzelResults;
    }

    // Case 3: Goertzel empty → trust YIN
    if (goertzelResults.isEmpty) {
      return yinResults;
    }

    // Case 4: Both have results - check for contradiction
    final yinMidi = yinResults.first.midi;
    final goertzelMidi = goertzelResults.first.midi;

    // YIN confirms Goertzel (same note or within 1 semitone) → Goertzel wins
    if ((yinMidi - goertzelMidi).abs() <= 1) {
      return goertzelResults;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SESSION-052: YIN OVERRIDE GUARD
    // YIN detected a different note than Goertzel. This could be:
    // (a) User played wrong note → we want to return YIN for WRONG flash
    // (b) YIN hallucinated from noise/reverb → we should trust Goertzel
    //
    // Apply guards to distinguish (a) from (b):
    // 1. Warmup guard: During first yinWarmupPeriodSec, YIN may hallucinate
    // 2. RMS guard: Low RMS = weak signal, YIN unreliable
    // ══════════════════════════════════════════════════════════════════════════

    // Guard 1: Warmup period - don't trust YIN override during initial warmup
    final inWarmup = tSec < yinWarmupPeriodSec;

    // Guard 2: RMS threshold - require strong signal for YIN override
    final dynamicRmsThreshold = max(
      yinMinRmsForOverride,
      _noiseFloorRms * yinRmsNoiseMultiplier,
    );
    final rmsOk = rms >= dynamicRmsThreshold;

    // If guards fail, don't trust YIN override - return Goertzel instead
    if (inWarmup || !rmsOk) {
      if (kDebugMode) {
        final reason = inWarmup ? 'warmup' : 'lowRms';
        debugPrint(
          'ROUTER_YIN_BLOCKED reason=$reason tSec=${tSec.toStringAsFixed(2)} '
          'rms=${rms.toStringAsFixed(4)} threshold=${dynamicRmsThreshold.toStringAsFixed(4)} '
          'noiseFloor=${_noiseFloorRms.toStringAsFixed(4)} '
          'goertzelMidi=$goertzelMidi yinMidi=$yinMidi expected=$expectedMidi',
        );
      }
      // Return Goertzel results (may be empty if Goertzel conf was below threshold)
      return goertzelResults;
    }

    // Guards passed: YIN contradicts with strong signal → YIN wins to detect WRONG
    if (kDebugMode) {
      debugPrint(
        'ROUTER_YIN_OVERRIDE goertzelMidi=$goertzelMidi yinMidi=$yinMidi '
        'expected=$expectedMidi rms=${rms.toStringAsFixed(4)} → returning YIN for WRONG detection',
      );
    }
    return yinResults;
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

    // SESSION-037: Capture raw detection BEFORE confidence filtering
    // This allows UI to show BLUE feedback even for low-conf detections
    _lastRawMidi = detectedMidi;
    _lastRawFreq = freq;
    _lastRawConf = conf;
    _lastRawTSec = tSec;
    _lastRawSource = 'yin';

    // Filter weak detections (for scoring, not for raw UI feedback)
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

    // SESSION-037: Capture raw detection from highest-confidence Goertzel bin
    // This captures even sub-threshold detections for BLUE UI feedback
    if (presenceMap.isNotEmpty) {
      final sortedAll = presenceMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final best = sortedAll.first;
      _lastRawMidi = best.key;
      _lastRawFreq = GoertzelDetector.midiToFrequency(best.key);
      _lastRawConf = best.value;
      _lastRawTSec = tSec;
      _lastRawSource = 'goertzel';
    }

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
