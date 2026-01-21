import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:shazapiano/core/practice/pitch/practice_pitch_router.dart';
import 'package:shazapiano/core/practice/pitch/onset_detector.dart';
import 'package:shazapiano/core/practice/pitch/note_tracker.dart';
import 'package:shazapiano/core/practice/pitch/mic_tuning.dart';

/// Feature flag: Enable hybrid YIN/Goertzel detection.
/// - OFF: Use existing MPM path.
/// - ON (default): Use YIN for mono notes, Goertzel for chords.
const bool kUseHybridDetector = true;

/// SESSION-019 FIX: Refresh UI during sustained notes.
/// When true, _uiMidi is updated even when NoteTracker blocks emission (held state).
/// This prevents the keyboard from going black while holding a note.
/// Set to false to rollback if this causes issues.
const bool kRefreshUiDuringSustain = true;

/// SESSION-019 FIX P2: Extend UI hold when no pitch detected but likely still sustaining.
/// When routerEvents is empty (RMS too low for pitch detection), extend _uiMidiSetAt
/// if we're within sustainExtendMs of the last valid pitch detection.
/// This prevents keyboard from going black during quiet sustain phases.
/// Set to false to rollback if this causes ghost highlights.
const bool kExtendUiDuringSilentSustain = true;
const int kSustainExtendWindowMs = 400; // Max time to extend UI without new pitch (was 600, reduced)
const double kSustainExtendMinRms = 0.025; // Min RMS to allow extension (presence gate)

/// Feature flag: Force fixed sample rate instead of dynamic detection.
/// SESSION-012 FIX: Dynamic SR detection is unreliable on some Android devices
/// (e.g., Xiaomi) where chunk timing jitter causes wrong SR estimation.
/// When true, always use 44100 Hz regardless of detected rate.
const bool kForceFixedSampleRate = true;
const int kFixedSampleRate = 44100;

/// MicEngine: Robust scoring engine for Practice mode
/// Handles: pitch detection → event buffer → note matching → decisions
/// ZERO dependency on "nextDetected" stability gates
class MicEngine {
  MicEngine({
    required this.noteEvents,
    required this.hitNotes,
    required this.detectPitch,
    this.headWindowSec = 0.15, // SESSION-009: Increased for low-end tolerance
    this.tailWindowSec =
        0.60, // SESSION-009: Increased from 0.45 for high latency devices
    this.absMinRms = 0.0008,
    // FIX BUG SESSION-005: Réduire seuil confidence pour détecter fausses notes plus faibles
    // 0.35 → 0.25 permet de capter notes jouées doucement
    this.minConfForWrong = 0.25,
    // SESSION-008: Minimum confidence to accept any pitch detection
    // Ignores weak/noisy detections that are likely subharmonics or noise
    this.minConfForPitch = 0.40,
    this.eventDebounceSec = 0.05,
    this.wrongFlashCooldownSec = 0.15,
    // SESSION-014: Per-midi dedup for WRONG_FLASH (prevents spam of same wrong note)
    this.wrongFlashDedupMs = 400.0,
    // SESSION-014: Max semitone distance for WRONG_FLASH (filters outliers like subharmonics)
    // If detected midi is > 12 semitones from ALL expected midis, ignore it
    this.maxSemitoneDeltaForWrong = 12,
    // SESSION-014: PROBE safety - max semitone distance to allow WRONG_FLASH from PROBE events
    // PROBE events with delta > 3 are likely artifacts, not real wrong notes
    this.probeSafetyMaxDelta = 3,
    // SESSION-015: Minimum confidence required to emit WRONG_FLASH (filters weak artifacts)
    // Higher than minConfForWrong to avoid ghost flashes from low-confidence detections
    // 0.75 = user must really be pressing the wrong key with conviction
    this.wrongFlashMinConf = 0.75,
    // SESSION-015: Block WRONG_FLASH from PROBE events entirely (artifacts, not real mistakes)
    // When true, PROBE events never trigger WRONG_FLASH regardless of delta
    this.probeBlockWrongFlash = true,
    // SESSION-015: Confirmation temporelle - require N detections of same wrong midi
    // within a time window to trigger WRONG_FLASH (anti-single-spike filter)
    // This prevents sustain/reverb artifacts from triggering ghost red flashes
    this.wrongFlashConfirmCount = 2,
    this.wrongFlashConfirmWindowMs = 250.0,
    // SESSION-009: Sustain filter - ignore previous note's pitch for wrong detection
    double? sustainFilterMs,
    this.uiHoldMs = 200,
    this.pitchWindowSize = 2048,
    this.minPitchIntervalMs = 40,
    this.verboseDebug = false,
    // SESSION-015: Latency compensation - applied to event timestamps for HIT matching
    // Positive = detection arrives late (shift events earlier), Negative = detection early
    this.latencyCompEnabled = true,
    this.latencyCompMaxMs = 400.0,
    this.latencyCompEmaAlpha =
        0.25, // SESSION-015: Faster convergence (was 0.2)
    this.latencyCompSampleCount =
        5, // SESSION-015: Smaller window for faster convergence (was 10)
    // SESSION-015: Default latency for low-end devices (based on session-015 evidence: ~325ms median)
    // Applied immediately at session start, then refined by auto-estimation
    this.latencyCompDefaultMs = 250.0,
    // SESSION-016: MicTuning support (null = use medium profile)
    MicTuning? tuning,
  })  : tuning = tuning ?? MicTuning.forProfile(ReverbProfile.medium),
        sustainFilterMs = sustainFilterMs ?? (tuning?.sustainFilterMs ?? 600.0),
        _onsetDetector = OnsetDetector.fromTuning(
          tuning ?? MicTuning.forProfile(ReverbProfile.medium),
        ),
        _noteTracker = NoteTracker.fromTuning(
          tuning ?? MicTuning.forProfile(ReverbProfile.medium),
        );

  final List<NoteEvent> noteEvents;
  final List<bool> hitNotes;
  final double Function(List<double>, double) detectPitch;

  final double headWindowSec;
  final double tailWindowSec;
  final double absMinRms;
  final double minConfForWrong;
  final double
  minConfForPitch; // SESSION-008: Minimum confidence for pitch detection
  final double eventDebounceSec;
  final double wrongFlashCooldownSec;
  final double wrongFlashDedupMs; // SESSION-014: Per-midi dedup for WRONG_FLASH
  final int
  maxSemitoneDeltaForWrong; // SESSION-014: Max delta for outlier filter
  final int probeSafetyMaxDelta; // SESSION-014: PROBE safety max delta
  final double wrongFlashMinConf; // SESSION-015: Min confidence for WRONG_FLASH
  final bool probeBlockWrongFlash; // SESSION-015: Block WRONG_FLASH from PROBE
  final int
  wrongFlashConfirmCount; // SESSION-015: Require N detections to confirm
  final double
  wrongFlashConfirmWindowMs; // SESSION-015: Time window for confirmation
  final double
  sustainFilterMs; // SESSION-009: Time to ignore previous note's pitch
  final int uiHoldMs;
  final int pitchWindowSize;
  final int minPitchIntervalMs;
  final bool verboseDebug;
  // SESSION-015: Latency compensation parameters
  final bool latencyCompEnabled;
  final double latencyCompMaxMs;
  final double latencyCompEmaAlpha;
  final int latencyCompSampleCount;
  final double latencyCompDefaultMs; // Default latency for low-end devices

  /// SESSION-016: MicTuning configuration for reverb profile.
  final MicTuning tuning;

  /// Hybrid pitch router (YIN for mono, Goertzel for chords).
  /// Only used when kUseHybridDetector is true.
  final PracticePitchRouter _router = PracticePitchRouter();

  /// Onset detector gate - decides WHEN to allow pitch detection.
  /// Prevents sustain/reverb pollution by only evaluating during attack bursts.
  /// SESSION-016: Now configured via MicTuning.
  final OnsetDetector _onsetDetector;

  /// SESSION-015 P4: Note tracker - prevents tail/sustain from generating new attacks.
  /// Envelope gate with hysteresis: allows ATTACK only on rising edge, blocks HELD/TAIL.
  /// SESSION-016: Now configured via MicTuning.
  final NoteTracker _noteTracker;

  String? _sessionId;
  final List<PitchEvent> _events = [];
  int _detectedChannels = 1;
  int _detectedSampleRate = 44100;
  bool _configLogged = false;
  bool _eventTimeLogged = false;

  DateTime? _lastChunkTime;
  double? _sampleRateEmaHz;
  DateTime? _lastPitchAt;

  // FIX BUG CRITIQUE: Expose detected sample rate for calibration/tests
  int get detectedSampleRate => _detectedSampleRate;

  final List<double> _sampleBuffer = <double>[];
  Float32List? _pitchWindow;

  double? _lastFreqHz;
  double? _lastRms;
  double? _lastConfidence;
  int? _lastMidi;

  double? get lastFreqHz => _lastFreqHz;
  double? get lastRms => _lastRms;
  double? get lastConfidence => _lastConfidence;
  int? get lastMidi => _lastMidi;

  // UI state (hold last valid midi 200ms)
  int? _uiMidi;
  DateTime? _uiMidiSetAt;

  // Wrong flash throttle
  DateTime? _lastWrongFlashAt;
  // SESSION-014: Per-midi dedup tracking for WRONG_FLASH
  final Map<int, DateTime> _lastWrongFlashByMidi = {};

  // SESSION-015: Confirmation temporelle tracking for WRONG_FLASH
  // Maps midi → list of detection timestamps (for requiring N confirmations)
  final Map<int, List<double>> _wrongCandidateHistory = {};

  // SESSION-017: Per-(noteIdx, midi) dedup for mismatch WRONG_FLASH
  // Key: "noteIdx_midi" string to allow same wrong note to flash for different expected notes
  final Map<String, DateTime> _mismatchDedupHistory = {};

  // SESSION-017: Per-noteIdx confirmation history for mismatch WRONG_FLASH
  // Key: noteIdx to track confirmations per target note
  final Map<int, List<double>> _mismatchConfirmHistory = {};

  // SESSION-009: Track recently hit pitch classes to filter sustain/reverb
  // Maps pitchClass (0-11) to timestamp when it was last hit
  final Map<int, DateTime> _recentlyHitPitchClasses = {};

  // Stability tracking: pitchClass → consecutive count
  final Map<int, int> _pitchClassStability = {};
  int? _lastDetectedPitchClass;

  // SESSION-015: Latency compensation state
  final List<double> _latencySamples = []; // Recent dt samples (ms)
  double _latencyCompMs = 0.0; // Current applied compensation (ms)
  double? _latencyMedianMs; // Last computed median (for logging)

  /// SESSION-015: Current latency compensation in milliseconds.
  /// Positive = detection arrives late (events shifted earlier).
  double get latencyCompMs => _latencyCompMs;

  /// SESSION-015: Last computed median latency (for debugging).
  double? get latencyMedianMs => _latencyMedianMs;

  // SESSION-016: Auto-baseline noise floor detection
  double _noiseFloorRms = 0.0; // Estimated noise floor during baseline
  double _dynamicOnsetMinRms = 0.0; // Dynamic onset threshold (after baseline)
  double _baselineStartMs = 0.0; // When baseline measurement started
  bool _baselineComplete = false; // Whether baseline measurement is done
  int _baselineSampleCount = 0; // Number of samples in baseline
  double _lastOnsetTriggerMs = -10000.0; // Last onset trigger time (for baseline guard)
  double _lastBaselineLogMs = -10000.0; // Rate limit baseline logs

  /// SESSION-016: Dynamic onset minimum RMS (after auto-baseline).
  double get dynamicOnsetMinRms => _dynamicOnsetMinRms;

  /// Epsilon for grouping chord notes with nearly-simultaneous starts.
  /// Notes within this time window are considered part of the same chord.
  /// 30ms is safe for piano MIDI where chord notes may have slightly different starts.
  static const double _epsilonStartSec = 0.03;

  /// Compute active expected MIDIs for routing decision (epsilon grouping).
  ///
  /// This groups notes by their start time (within epsilon) to correctly
  /// detect chords even when note starts are not perfectly aligned.
  ///
  /// Algorithm:
  /// 1. Find all non-hit notes whose start is within the routing window
  /// 2. Group them by start time (notes within epsilon are same group)
  /// 3. Select the group closest to current elapsedSec
  /// 4. Return deduplicated, sorted, capped midis from that group
  ///
  /// This ensures:
  /// - Hyper Facile (mono): always returns 1 note → YIN
  /// - Facile (chords): returns 2+ notes at chord moments → Goertzel
  List<int> _computeActiveExpectedMidisForRouting(double elapsedSec) {
    // Step 1: Collect candidate notes within routing window
    final candidates = <({double start, int pitch})>[];
    for (var idx = 0; idx < noteEvents.length; idx++) {
      if (hitNotes[idx]) continue;
      final note = noteEvents[idx];
      // Routing window: start-only (not end)
      final windowStart = note.start - headWindowSec;
      final windowEnd = note.start + tailWindowSec;
      if (elapsedSec >= windowStart && elapsedSec <= windowEnd) {
        candidates.add((start: note.start, pitch: note.pitch));
      }
    }

    if (candidates.isEmpty) return [];

    // Step 2: Group candidates by start time (epsilon clustering)
    // Sort by start time first
    candidates.sort((a, b) => a.start.compareTo(b.start));

    final groups = <List<({double start, int pitch})>>[];
    var currentGroup = <({double start, int pitch})>[candidates.first];
    var groupAnchor = candidates.first.start;

    for (var i = 1; i < candidates.length; i++) {
      final c = candidates[i];
      if ((c.start - groupAnchor).abs() <= _epsilonStartSec) {
        // Same group (within epsilon of anchor)
        currentGroup.add(c);
      } else {
        // New group
        groups.add(currentGroup);
        currentGroup = [c];
        groupAnchor = c.start;
      }
    }
    groups.add(currentGroup);

    // Step 3: Select group closest to elapsedSec
    List<({double start, int pitch})> chosenGroup = groups.first;
    double minDistance = double.infinity;
    for (final group in groups) {
      final groupStart = group.first.start;
      final distance = (groupStart - elapsedSec).abs();
      if (distance < minDistance) {
        minDistance = distance;
        chosenGroup = group;
      }
    }

    // Step 4: Extract midis, dedup, sort, cap
    final midis = chosenGroup.map((c) => c.pitch).toSet().toList()..sort();
    final result = midis.take(6).toList();

    // Debug log: show all groups and chosen group
    if (kDebugMode && verboseDebug) {
      final groupsStr = groups
          .map(
            (g) =>
                '(start=${g.first.start.toStringAsFixed(3)},midis=${g.map((c) => c.pitch).toList()})',
          )
          .join(',');
      debugPrint(
        'EXPECTED_ROUTING t=${elapsedSec.toStringAsFixed(3)} '
        'groups=[$groupsStr] chosen=$result',
      );
    }

    return result;
  }

  /// Current UI detected MIDI (held 200ms)
  int? get uiDetectedMidi {
    if (_uiMidi != null && _uiMidiSetAt != null) {
      final elapsed = DateTime.now().difference(_uiMidiSetAt!).inMilliseconds;
      if (elapsed < uiHoldMs) return _uiMidi;
    }
    return null;
  }

  void reset(String sessionId) {
    _sessionId = sessionId;
    _events.clear();
    _detectedChannels = 1;
    _detectedSampleRate = 44100;
    _configLogged = false;
    _eventTimeLogged = false;
    _lastChunkTime = null;
    _sampleRateEmaHz = null;
    _lastPitchAt = null;
    _sampleBuffer.clear();
    _recentlyHitPitchClasses.clear(); // SESSION-009
    _pitchWindow = null;
    _lastFreqHz = null;
    _lastRms = null;
    _lastConfidence = null;
    _lastMidi = null;
    _uiMidi = null;
    _uiMidiSetAt = null;
    _lastWrongFlashAt = null;
    _lastWrongFlashByMidi.clear(); // SESSION-014: Reset per-midi dedup
    _wrongCandidateHistory.clear(); // SESSION-015: Reset confirmation tracking
    _mismatchDedupHistory.clear(); // SESSION-017: Reset mismatch dedup
    _mismatchConfirmHistory.clear(); // SESSION-017: Reset mismatch confirmation
    _pitchClassStability.clear();
    _lastDetectedPitchClass = null;
    _onsetDetector.reset(); // Reset onset gate for new session
    _noteTracker.reset(); // SESSION-015 P4: Reset note tracker for new session
    // SESSION-015: Reset latency compensation with default value for low-end devices
    _latencySamples.clear();
    _latencyCompMs =
        latencyCompDefaultMs; // Start with default, refine with samples
    _latencyMedianMs = null;

    // SESSION-016: Reset auto-baseline state
    _noiseFloorRms = 0.0;
    _dynamicOnsetMinRms = tuning.onsetMinRms; // Start with preset, refine with baseline
    _baselineStartMs = 0.0;
    _baselineComplete = false;
    _baselineSampleCount = 0;
    _lastOnsetTriggerMs = -10000.0;
    _lastBaselineLogMs = -10000.0;

    if (kDebugMode) {
      // PITCH_PIPELINE: Non-filterable startup log proving pipeline configuration
      // This log MUST always appear to verify hybrid mode and sample rate settings
      final detectorStr = kUseHybridDetector ? 'HYBRID' : 'MPM';
      debugPrint(
        'PITCH_PIPELINE sessionId=$sessionId hybrid=$kUseHybridDetector detector=$detectorStr '
        'snapTol=${_router.snapSemitoneTolerance} minRms=${absMinRms.toStringAsFixed(4)} '
        'minConf=${minConfForPitch.toStringAsFixed(2)} debounce=${eventDebounceSec.toStringAsFixed(3)}s '
        'wrongCooldown=${wrongFlashCooldownSec.toStringAsFixed(3)}s uiHold=${uiHoldMs}ms '
        'sampleRateForced=$kForceFixedSampleRate fixedSR=$kFixedSampleRate',
      );
      debugPrint(
        'SESSION_PARAMS sessionId=$sessionId head=${headWindowSec.toStringAsFixed(3)}s '
        'tail=${tailWindowSec.toStringAsFixed(3)}s absMinRms=${absMinRms.toStringAsFixed(4)} '
        'minConfWrong=${minConfForWrong.toStringAsFixed(2)} debounce=${eventDebounceSec.toStringAsFixed(3)}s '
        'wrongCooldown=${wrongFlashCooldownSec.toStringAsFixed(3)}s uiHold=${uiHoldMs}ms',
      );
      // SESSION-016: Log tuning profile
      debugPrint(
        'TUNING_PROFILE profile=${tuning.profile.name} '
        'onsetMinRms=${tuning.onsetMinRms.toStringAsFixed(4)} '
        'dynamicOnsetMinRms=${_dynamicOnsetMinRms.toStringAsFixed(4)} '
        'cooldown=${tuning.pitchClassCooldownMs.toStringAsFixed(0)} '
        'releaseRatio=${tuning.releaseRatio.toStringAsFixed(2)} '
        'presenceEnd=${tuning.presenceEndThreshold.toStringAsFixed(2)} '
        'endFrames=${tuning.endConsecutiveFrames} '
        'sustainFilterMs=${sustainFilterMs.toStringAsFixed(0)}',
      );
    }
  }

  /// Process audio chunk: detect pitch, store event, match notes
  List<NoteDecision> onAudioChunk(
    List<double> rawSamples,
    DateTime now,
    double elapsedMs,
  ) {
    // Normalize input timebase to seconds for matching/window logic.
    final elapsedSec = elapsedMs / 1000.0;
    // Update audio config (sampleRate/channels) using real callback cadence.
    _detectAudioConfig(rawSamples, now);

    // Downmix if stereo interleaved.
    final samples = _detectedChannels == 2
        ? _downmixStereo(rawSamples)
        : rawSamples;

    // Keep a fixed-size rolling window for pitch detection (MPM requires bufferSize).
    if (samples.isNotEmpty) {
      _sampleBuffer.addAll(samples);
      if (_sampleBuffer.length > pitchWindowSize) {
        _sampleBuffer.removeRange(0, _sampleBuffer.length - pitchWindowSize);
      }
    }

    final decisions = <NoteDecision>[];

    final rms = samples.isEmpty ? 0.0 : _computeRms(samples);
    _lastRms = rms;

    // SESSION-016: Auto-baseline noise floor detection
    // During the first baselineMs, collect RMS samples to estimate noise floor
    // GUARD: Only update if "silent" (no recent onset, RMS below threshold)
    if (tuning.autoNoiseBaseline && !_baselineComplete) {
      if (_baselineStartMs == 0.0) {
        _baselineStartMs = elapsedMs;
      }
      final baselineElapsed = elapsedMs - _baselineStartMs;

      if (baselineElapsed < tuning.baselineMs) {
        // Guard conditions: only update noise floor if truly silent
        const double baselineSilenceMaxMult = 0.6; // Max RMS as multiple of onsetMinRms
        const double onsetRecentMs = 300.0; // "Recent" onset window

        final bool onsetTriggeredRecently =
            (elapsedMs - _lastOnsetTriggerMs) < onsetRecentMs;
        final bool isSilent =
            rms < baselineSilenceMaxMult * tuning.onsetMinRms;

        if (!onsetTriggeredRecently && isSilent) {
          // Safe to update noise floor
          _baselineSampleCount++;
          if (_baselineSampleCount == 1) {
            _noiseFloorRms = rms;
          } else {
            // Slow EMA (alpha=0.1) for stable noise floor estimation
            _noiseFloorRms = _noiseFloorRms * 0.9 + rms * 0.1;
          }

          // Rate-limited log (max 1 per 300ms)
          if (kDebugMode && (elapsedMs - _lastBaselineLogMs) >= 300.0) {
            _lastBaselineLogMs = elapsedMs;
            debugPrint(
              'NOISE_BASELINE_UPDATE floor=${_noiseFloorRms.toStringAsFixed(5)} '
              'rms=${rms.toStringAsFixed(5)} samples=$_baselineSampleCount',
            );
          }
        } else {
          // Skip this sample (not silent)
          if (kDebugMode && (elapsedMs - _lastBaselineLogMs) >= 300.0) {
            _lastBaselineLogMs = elapsedMs;
            debugPrint(
              'NOISE_BASELINE_SKIP reason=not_silent '
              'rms=${rms.toStringAsFixed(5)} onsetRecently=$onsetTriggeredRecently '
              'silenceThresh=${(baselineSilenceMaxMult * tuning.onsetMinRms).toStringAsFixed(5)}',
            );
          }
        }
      } else {
        // Baseline period ended - compute dynamic threshold
        _baselineComplete = true;
        _dynamicOnsetMinRms = (
          _noiseFloorRms * tuning.noiseFloorMultiplier + tuning.noiseFloorMargin
        ).clamp(tuning.onsetMinRms, tuning.onsetMinRms * 5);

        if (kDebugMode) {
          debugPrint(
            'NOISE_BASELINE floor=${_noiseFloorRms.toStringAsFixed(5)} '
            'dynamicOnsetMinRms=${_dynamicOnsetMinRms.toStringAsFixed(5)} '
            'samples=$_baselineSampleCount baselineMs=${tuning.baselineMs}',
          );
        }
      }
    }

    final canComputePitch =
        pitchWindowSize > 0 &&
        _sampleBuffer.length >= pitchWindowSize &&
        rms >= absMinRms &&
        (_lastPitchAt == null ||
            now.difference(_lastPitchAt!).inMilliseconds >= minPitchIntervalMs);

    if (canComputePitch) {
      _lastPitchAt = now;
      final window = _pitchWindow ??= Float32List(pitchWindowSize);
      final start = _sampleBuffer.length - pitchWindowSize;
      for (var i = 0; i < pitchWindowSize; i++) {
        window[i] = _sampleBuffer[start + i];
      }

      // ─────────────────────────────────────────────────────────────────────
      // HYBRID PATH: Use YIN for mono-note, Goertzel for chords
      // ─────────────────────────────────────────────────────────────────────
      if (kUseHybridDetector) {
        // Compute active expected MIDIs using START-ONLY window for routing
        // This prevents long notes from artificially extending chord detection
        final activeExpectedMidis = _computeActiveExpectedMidisForRouting(
          elapsedSec,
        );

        // ─────────────────────────────────────────────────────────────────────
        // ONSET GATING: Only allow pitch detection during attack bursts
        // This prevents sustain/reverb from previous notes from polluting detection
        // ─────────────────────────────────────────────────────────────────────
        final onsetState = _onsetDetector.update(
          rmsNow: rms,
          nowMs: elapsedMs,
          hasExpectedNotes: activeExpectedMidis.isNotEmpty,
        );

        // If onset gate says skip, don't call pitch detector at all
        if (onsetState == OnsetState.skip) {
          // Still prune old events and run matching (for MISS detection)
          _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);
          decisions.addAll(_matchNotes(elapsedSec, now));
          _lastChunkTime = now;
          return decisions;
        }

        // Call router to decide YIN vs Goertzel
        final routerEvents = _router.decide(
          samples: window,
          sampleRate: _detectedSampleRate,
          activeExpectedMidis: activeExpectedMidis,
          rms: rms,
          tSec: elapsedSec,
        );

        // Debug log (grep-friendly PITCH_ROUTER format)
        // Always log to verify hybrid is working (essential for debugging)
        if (kDebugMode) {
          final modeStr = _router.lastMode == DetectionMode.yin
              ? 'YIN'
              : _router.lastMode == DetectionMode.goertzel
              ? 'GOERTZEL'
              : 'NONE';
          debugPrint(
            'PITCH_ROUTER expected=$activeExpectedMidis mode=$modeStr events=${routerEvents.length} t=${elapsedSec.toStringAsFixed(3)}',
          );
        }

        // SESSION-014: Convert OnsetState to PitchEventSource for tracking
        final PitchEventSource eventSource;
        switch (onsetState) {
          case OnsetState.trigger:
            eventSource = PitchEventSource.trigger;
            // SESSION-016: Track onset trigger time for baseline guard
            _lastOnsetTriggerMs = elapsedMs;
            break;
          case OnsetState.burst:
            eventSource = PitchEventSource.burst;
            break;
          case OnsetState.probe:
            eventSource = PitchEventSource.probe;
            break;
          case OnsetState.skip:
            eventSource = PitchEventSource.legacy; // Should not happen
            break;
        }

        // SESSION-019 FIX P2: Extend UI during silent sustain
        // If no pitch detected but we have a recent _uiMidi, extend its lifetime
        // This prevents keyboard from going black during quiet decay phases
        // HARDENED: Added presence gate (rms >= kSustainExtendMinRms) to prevent ghost highlights
        if (kExtendUiDuringSilentSustain &&
            routerEvents.isEmpty &&
            _uiMidi != null &&
            _uiMidiSetAt != null) {
          final ageMs = now.difference(_uiMidiSetAt!).inMilliseconds;
          final presenceOk = rms >= kSustainExtendMinRms;
          final windowOk = ageMs < kSustainExtendWindowMs;

          if (windowOk && presenceOk) {
            // Refresh the timestamp to keep the highlight alive
            _uiMidiSetAt = now;
            if (kDebugMode) {
              debugPrint(
                'UI_EXTEND_SUSTAIN events=0 uiMidi=$_uiMidi ageMs=$ageMs '
                'rmsNow=${rms.toStringAsFixed(4)} minRms=${kSustainExtendMinRms.toStringAsFixed(4)} '
                'windowMs=$kSustainExtendWindowMs t=${elapsedMs.toStringAsFixed(0)}ms',
              );
            }
          } else if (kDebugMode && windowOk && !presenceOk) {
            // Log when we SKIP extension due to low presence (helps debug ghost issues)
            debugPrint(
              'UI_EXTEND_SKIP reason=low_presence uiMidi=$_uiMidi ageMs=$ageMs '
              'rmsNow=${rms.toStringAsFixed(4)} minRms=${kSustainExtendMinRms.toStringAsFixed(4)} '
              't=${elapsedMs.toStringAsFixed(0)}ms',
            );
          }
        }

        // Add router events to buffer (with sustain filter + debounce)
        for (final re in routerEvents) {
          final pitchClass = re.midi % 12;

          // Sustain filter: skip recently hit pitch classes
          final recentHitTime = _recentlyHitPitchClasses[pitchClass];
          if (recentHitTime != null) {
            final msSinceHit = now.difference(recentHitTime).inMilliseconds;
            if (msSinceHit < sustainFilterMs) {
              continue; // Skip sustain/reverb
            }
          }

          // Anti-spam: skip if same midi within debounce window
          if (_events.isNotEmpty) {
            final last = _events.last;
            if ((elapsedSec - last.tSec).abs() < eventDebounceSec &&
                last.midi == re.midi) {
              continue;
            }
          }

          // Track stability
          if (_lastDetectedPitchClass == pitchClass) {
            _pitchClassStability[pitchClass] =
                (_pitchClassStability[pitchClass] ?? 0) + 1;
          } else {
            _pitchClassStability.clear();
            _pitchClassStability[pitchClass] = 1;
            _lastDetectedPitchClass = pitchClass;
          }

          final stabilityFrames = _pitchClassStability[pitchClass] ?? 1;

          // SESSION-015 P4: NoteTracker gate - prevent tail/sustain from generating attacks
          final trackerResult = _noteTracker.feed(
            midi: re.midi,
            rmsNow: re.rms,
            conf: re.conf,
            nowMs: elapsedMs,
            source: eventSource.name,
          );

          if (!trackerResult.shouldEmit) {
            // SESSION-019 FIX: Refresh UI during sustained notes
            // Even though we don't add to buffer (to avoid scoring spam),
            // we still want the keyboard to stay lit while holding a note.
            // Only refresh if: (1) feature flag enabled, (2) reason is "held" (not cooldown/tail),
            // (3) confidence is high enough to trust the pitch.
            if (kRefreshUiDuringSustain &&
                trackerResult.reason == 'held' &&
                re.conf >= minConfForPitch) {
              _uiMidi = re.midi;
              _uiMidiSetAt = now;
              // Also update last values for consistency
              _lastFreqHz = re.freq;
              _lastConfidence = re.conf;
              _lastMidi = re.midi;
            }
            // Tail/held/cooldown - skip adding to buffer
            continue;
          }

          _logFirstEventTime(
            rawTSec: re.tSec,
            rawName: 're.tSec',
            elapsedSec: elapsedSec,
          );
          _events.add(
            PitchEvent(
              tSec: re.tSec,
              midi: re.midi,
              freq: re.freq,
              conf: re.conf,
              rms: re.rms,
              stabilityFrames: stabilityFrames,
              source: eventSource, // SESSION-014: Track source for PROBE safety
            ),
          );

          // Update UI state (same as MPM path: always update)
          _uiMidi = re.midi;
          _uiMidiSetAt = now;

          // Update last values
          _lastFreqHz = re.freq;
          _lastConfidence = re.conf;
          _lastMidi = re.midi;
        }
      } else {
        // ───────────────────────────────────────────────────────────────────
        // ORIGINAL MPM PATH (unchanged when kUseHybridDetector = false)
        // ───────────────────────────────────────────────────────────────────
        final freqRaw = detectPitch(window, _detectedSampleRate.toDouble());
        // detectPitch already uses the detected sample rate; avoid double correction.
        final freq = freqRaw > 0 ? freqRaw : 0.0;

        if (freq > 0 && freq >= 50.0 && freq <= 2000.0) {
          final midi = _freqToMidi(freq);
          final conf = (rms / 0.05).clamp(0.0, 1.0);

          _lastFreqHz = freq;
          _lastConfidence = conf;
          _lastMidi = midi;

          // SESSION-008: Skip weak detections (likely subharmonics or noise)
          if (conf < minConfForPitch) {
            _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);
            decisions.addAll(_matchNotes(elapsedSec, now));
            _lastChunkTime = now;
            return decisions;
          }

          // Track pitch class stability (consecutive detections)
          final pitchClass = midi % 12;
          if (_lastDetectedPitchClass == pitchClass) {
            _pitchClassStability[pitchClass] =
                (_pitchClassStability[pitchClass] ?? 0) + 1;
          } else {
            _pitchClassStability.clear();
            _pitchClassStability[pitchClass] = 1;
            _lastDetectedPitchClass = pitchClass;
          }

          // Anti-spam: skip if same midi within debounce window
          if (_events.isNotEmpty) {
            final last = _events.last;
            if ((elapsedSec - last.tSec).abs() < eventDebounceSec &&
                last.midi == midi) {
              _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);
              decisions.addAll(_matchNotes(elapsedSec, now));
              _lastChunkTime = now;
              return decisions;
            }
          }

          // SESSION-010 FIX: Skip pitch events that are sustain/reverb of recently HIT notes
          // This prevents the previous note's sustain from filling the buffer and blocking
          // detection of the next note (especially for adjacent semitones like C#4 -> C4)
          final recentHitTime = _recentlyHitPitchClasses[pitchClass];
          if (recentHitTime != null) {
            final msSinceHit = now.difference(recentHitTime).inMilliseconds;
            if (msSinceHit < sustainFilterMs) {
              // This pitch class was recently hit - likely sustain/reverb, skip adding to buffer
              if (kDebugMode && verboseDebug) {
                debugPrint(
                  'SUSTAIN_SKIP sessionId=$_sessionId pitchClass=$pitchClass midi=$midi '
                  'msSinceHit=$msSinceHit sustainFilterMs=$sustainFilterMs',
                );
              }
              _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);
              decisions.addAll(_matchNotes(elapsedSec, now));
              _lastChunkTime = now;
              return decisions;
            }
          }

          final stabilityFrames = _pitchClassStability[pitchClass] ?? 1;
          _logFirstEventTime(
            rawTSec: elapsedSec,
            rawName: 'elapsedSec',
            elapsedSec: elapsedSec,
          );
          _events.add(
            PitchEvent(
              tSec: elapsedSec,
              midi: midi,
              freq: freq,
              conf: conf,
              rms: rms,
              stabilityFrames: stabilityFrames,
            ),
          );

          // UI state (hold last valid midi 200ms)
          _uiMidi = midi;
          _uiMidiSetAt = now;
        }
      }
    }

    // Prune old events (keep 2.0s), then match notes even if no new pitch event
    // so MISS decisions still fire when the user stays silent.
    _events.removeWhere((e) => elapsedSec - e.tSec > 2.0);
    decisions.addAll(_matchNotes(elapsedSec, now));

    _lastChunkTime = now;
    return decisions;
  }

  void _detectAudioConfig(List<double> samples, DateTime now) {
    // Keep updating the estimate; _configLogged only gates one-time logging.

    // Heuristic: if samples.length > typical mono frame size → stereo
    // Typical: 44100Hz × 0.1s = 4410 samples mono, 8820 stereo
    if (_lastChunkTime == null) {
      return;
    }

    final dtUs = now.difference(_lastChunkTime!).inMicroseconds;
    if (dtUs <= 0) {
      return;
    }

    final dtSec = dtUs / 1000000.0;
    if (dtSec < 0.008 || dtSec > 0.2) {
      return;
    }
    final inputRate = samples.length / dtSec;

    // Infer stereo when total input rate is roughly 2x a plausible mono SR.
    // Threshold chosen to avoid false positives from scheduling jitter.
    final channels = inputRate >= 60000 ? 2 : 1;
    if (channels != _detectedChannels) {
      _sampleBuffer.clear();
      _pitchWindow = null;
    }
    _detectedChannels = channels;

    final srInstant = inputRate / channels;
    _sampleRateEmaHz = _sampleRateEmaHz == null
        ? srInstant
        : (_sampleRateEmaHz! * 0.9 + srInstant * 0.1);

    // SESSION-012 FIX: Use fixed sample rate if flag is set
    // Dynamic detection is unreliable on some Android devices
    if (kForceFixedSampleRate) {
      _detectedSampleRate = kFixedSampleRate;
    } else {
      _detectedSampleRate = _sampleRateEmaHz!.round().clamp(32000, 52000);
    }

    if (!_configLogged && kDebugMode) {
      // PROOF log: calculate semitone shift if mismatch
      const expectedSampleRate = 44100;
      final detectedForLog = _sampleRateEmaHz!.round().clamp(32000, 52000);
      final ratio = detectedForLog / expectedSampleRate;
      final semitoneShift = 12 * (log(ratio) / ln2);
      debugPrint(
        'MIC_INPUT sessionId=$_sessionId channels=$_detectedChannels '
        'sampleRate=$_detectedSampleRate (detected=$detectedForLog, forced=${kForceFixedSampleRate ? "YES" : "NO"}) '
        'inputRate=${inputRate.toStringAsFixed(0)} '
        'samplesLen=${samples.length} dtSec=${dtSec.toStringAsFixed(3)} '
        'expectedSR=44100 ratio=${ratio.toStringAsFixed(3)} semitoneShift=${semitoneShift.toStringAsFixed(2)}',
      );
      _configLogged = true;
    }
  }

  List<double> _downmixStereo(List<double> samples) {
    final mono = <double>[];
    for (var i = 0; i < samples.length - 1; i += 2) {
      final l = samples[i];
      final r = samples[i + 1];
      mono.add((l + r) / 2.0);
    }
    return mono;
  }

  double _computeRms(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    double sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    return sqrt(sum / samples.length);
  }

  (double, double)? _firstActiveWindow(double elapsedSec) {
    if (hitNotes.length != noteEvents.length) return null;
    for (var idx = 0; idx < noteEvents.length; idx++) {
      if (hitNotes[idx]) continue;
      final note = noteEvents[idx];
      final windowStart = note.start - headWindowSec;
      final windowEnd = note.end + tailWindowSec;
      if (elapsedSec >= windowStart && elapsedSec <= windowEnd) {
        return (windowStart, windowEnd);
      }
    }
    return null;
  }

  void _logFirstEventTime({
    required double rawTSec,
    required String rawName,
    required double elapsedSec,
  }) {
    if (!kDebugMode || _eventTimeLogged) return;
    final window = _firstActiveWindow(elapsedSec);
    final windowStart = window?.$1;
    final windowEnd = window?.$2;
    debugPrint(
      'MIC_EVENT_TIME sessionId=$_sessionId raw=${rawTSec.toStringAsFixed(3)} (name=$rawName) '
      'elapsedSec=${elapsedSec.toStringAsFixed(3)} '
      'windowStart=${windowStart?.toStringAsFixed(3) ?? "n/a"} '
      'windowEnd=${windowEnd?.toStringAsFixed(3) ?? "n/a"}',
    );
    _eventTimeLogged = true;
  }

  int _freqToMidi(double freq) {
    return (12 * (log(freq / 440.0) / ln2) + 69).round();
  }

  /// SESSION-015: Update latency compensation estimate from collected samples.
  ///
  /// Uses median of recent samples (robust to outliers) with EMA smoothing.
  /// Clamps result to [-latencyCompMaxMs, +latencyCompMaxMs].
  void _updateLatencyEstimate() {
    if (_latencySamples.isEmpty) return;

    // Compute median (robust to outliers)
    final sorted = List<double>.from(_latencySamples)..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2.0;

    _latencyMedianMs = median;

    // Apply EMA smoothing to avoid sudden jumps
    final newComp =
        _latencyCompMs * (1 - latencyCompEmaAlpha) +
        median * latencyCompEmaAlpha;

    // Clamp to reasonable range
    _latencyCompMs = newComp.clamp(-latencyCompMaxMs, latencyCompMaxMs);

    if (kDebugMode) {
      debugPrint(
        'LATENCY_EST medianMs=${median.toStringAsFixed(1)} '
        'appliedMs=${_latencyCompMs.toStringAsFixed(1)} '
        'samples=${_latencySamples.length}',
      );
    }
  }

  List<NoteDecision> _matchNotes(double elapsed, DateTime now) {
    final decisions = <NoteDecision>[];

    // CRITICAL FIX: Guard against hitNotes/noteEvents desync
    // Can occur if notes reloaded or list reassigned during active session
    if (hitNotes.length != noteEvents.length) {
      if (verboseDebug && kDebugMode) {
        debugPrint(
          'SCORING_DESYNC sessionId=$_sessionId hitNotes=${hitNotes.length} noteEvents=${noteEvents.length} ABORT',
        );
      }
      return decisions; // Abort scoring to prevent crash
    }

    // FIX BUG SESSION-005: Track WRONG events separately (notes played but not matching any expected)
    // This allows detecting wrong notes even when a correct note is also played
    PitchEvent? bestWrongEvent;
    int? bestWrongMidi;

    // FIX BUG SESSION-003 #4: Track consumed events to prevent one event
    // from validating multiple notes with the same pitch class.
    // An event can only validate ONE note per scoring pass.
    final consumedEventTimes = <double>{};

    for (var idx = 0; idx < noteEvents.length; idx++) {
      if (hitNotes[idx]) continue; // Already resolved

      final note = noteEvents[idx];
      final windowStart = note.start - headWindowSec;
      final windowEnd = note.end + tailWindowSec;

      // Check timeout MISS
      if (elapsed > windowEnd) {
        hitNotes[idx] = true;
        decisions.add(
          NoteDecision(
            type: DecisionType.miss,
            noteIndex: idx,
            expectedMidi: note.pitch,
            window: (windowStart, windowEnd),
            reason: 'timeout_no_match',
          ),
        );
        if (kDebugMode) {
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] '
            'result=MISS reason=timeout_no_match',
          );
        }
        continue;
      }

      // Check if note is active
      if (elapsed < windowStart) continue;

      // Declare expectedPitchClass early for logging
      final expectedPitchClass = note.pitch % 12;

      // Log event buffer state for this note (debug)
      if (kDebugMode) {
        final eventsInWindow = _events
            .where((e) => e.tSec >= windowStart && e.tSec <= windowEnd)
            .toList();
        double? minEventSec;
        double? maxEventSec;
        for (final event in _events) {
          final tSec = event.tSec;
          if (minEventSec == null || tSec < minEventSec) {
            minEventSec = tSec;
          }
          if (maxEventSec == null || tSec > maxEventSec) {
            maxEventSec = tSec;
          }
        }
        final eventsOverlapWindow =
            minEventSec != null &&
            maxEventSec != null &&
            maxEventSec >= windowStart &&
            minEventSec <= windowEnd;
        final pitchClasses = eventsInWindow
            .map((e) => e.midi % 12)
            .toSet()
            .join(',');
        debugPrint(
          'BUFFER_STATE sessionId=$_sessionId noteIdx=$idx expectedMidi=${note.pitch} expectedPC=$expectedPitchClass '
          'window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] '
          'eventsInWindow=${eventsInWindow.length} totalEvents=${_events.length} '
          'eventsMin=${minEventSec?.toStringAsFixed(3) ?? "n/a"} '
          'eventsMax=${maxEventSec?.toStringAsFixed(3) ?? "n/a"} '
          'windowStart=${windowStart.toStringAsFixed(3)} '
          'windowEnd=${windowEnd.toStringAsFixed(3)} '
          'eventsOverlapWindow=$eventsOverlapWindow '
          'pitchClassesInWindow=[$pitchClasses]',
        );
      }

      // Find best match in event buffer with DETAILED REJECT LOGGING
      PitchEvent? bestEvent;
      double bestDistance = double.infinity;
      String? rejectReason; // Track why events were rejected

      for (final event in _events) {
        // Reject: out of time window
        if (event.tSec < windowStart || event.tSec > windowEnd) {
          if (verboseDebug && kDebugMode && rejectReason == null) {
            rejectReason = 'out_of_window';
          }
          continue;
        }

        // FIX BUG SESSION-003 #4: Reject events already consumed by another note
        // This prevents one pitch event from validating multiple notes
        if (consumedEventTimes.contains(event.tSec)) {
          if (verboseDebug && kDebugMode && rejectReason == null) {
            rejectReason = 'event_already_consumed';
          }
          continue;
        }

        // Reject: low stability (< 1 frame = impossible, so accept all)
        // Note: Piano with real mic is often unstable, requiring only 1 frame
        if (event.stabilityFrames < 1) {
          if (verboseDebug && kDebugMode && rejectReason == null) {
            rejectReason = 'low_stability_frames=${event.stabilityFrames}';
          }
          continue;
        }

        final detectedPitchClass = event.midi % 12;

        // Reject: pitch class mismatch
        if (detectedPitchClass != expectedPitchClass) {
          // Always track pitch_class_mismatch (not just verboseDebug) for accurate logging
          if (kDebugMode && rejectReason == null) {
            rejectReason =
                'pitch_class_mismatch_expected=${expectedPitchClass}_detected=$detectedPitchClass';
          }
          continue;
        }

        // Now we have pitch class match, test direct midi ONLY
        // (octave shifts ±12/±24 disabled to prevent harmonics false hits)
        final distDirect = (event.midi - note.pitch).abs().toDouble();
        if (distDirect < bestDistance) {
          bestDistance = distDirect;
          bestEvent = event;
        }
      }

      // Check HIT with very tolerant distance (≤3 semitones for real piano+mic)
      if (bestEvent != null && bestDistance <= 3.0) {
        hitNotes[idx] = true;

        // FIX BUG SESSION-003 #4: Mark this event as consumed so it can't
        // validate another note with the same pitch class
        consumedEventTimes.add(bestEvent.tSec);

        // SESSION-015: Apply latency compensation to event timestamp
        // If detection arrives late (positive latencyCompMs), shift event earlier
        final adjustedEventTSec = latencyCompEnabled
            ? bestEvent.tSec - (_latencyCompMs / 1000.0)
            : bestEvent.tSec;

        // FIX BUG #7 (SESSION4): Calculate dt correctly for long notes
        // For long notes (>500ms), playing DURING the note should be perfect (dt=0)
        // Only penalize if played before note.start or after note.end
        final double dtSec;
        if (adjustedEventTSec < note.start) {
          // Played before note started (early)
          dtSec = adjustedEventTSec - note.start; // negative
        } else if (adjustedEventTSec <= note.end) {
          // Played DURING the note (perfect timing for long notes)
          dtSec = 0.0;
        } else {
          // Played after note ended (late)
          dtSec = adjustedEventTSec - note.end; // positive
        }

        // SESSION-015: Collect latency sample for auto-estimation
        // Only from high-confidence, non-PROBE sources
        if (latencyCompEnabled &&
            bestEvent.conf >= minConfForPitch &&
            bestEvent.source != PitchEventSource.probe) {
          // Raw dt: how late the detection arrived relative to the "expected time"
          // For latency estimation, we use note.start as the reference point
          // (when the user SHOULD press the key to be "on time")
          // Positive = detection late, Negative = detection early
          //
          // Note: We use note.start (not center) because that's when the user
          // should ideally begin playing. The detection latency is the delay
          // between user action and system detection.
          final expectedTime = note.start;
          final rawDtMs = (bestEvent.tSec - expectedTime) * 1000.0;

          // Log the sample
          if (kDebugMode) {
            debugPrint(
              'LATENCY_SAMPLE dtMs=${rawDtMs.toStringAsFixed(1)} '
              'source=${bestEvent.source.name} conf=${bestEvent.conf.toStringAsFixed(2)} '
              'midi=${bestEvent.midi} noteIdx=$idx '
              'eventT=${bestEvent.tSec.toStringAsFixed(3)} expectedT=${expectedTime.toStringAsFixed(3)}',
            );
          }

          // Add to sliding window
          _latencySamples.add(rawDtMs);
          if (_latencySamples.length > latencyCompSampleCount) {
            _latencySamples.removeAt(0);
          }

          // Update latency estimate when we have enough samples
          // SESSION-015: Start estimating after just 2 samples for faster convergence
          if (_latencySamples.length >= 2) {
            _updateLatencyEstimate();
          }
        }

        // SUSTAIN SCORING: Calculate held duration from pitch events in buffer
        // Find all events matching this pitch class within the note window
        final matchingEvents = _events.where((e) {
          if (e.tSec < windowStart || e.tSec > windowEnd) return false;
          return (e.midi % 12) == expectedPitchClass;
        }).toList();

        double? heldDurationSec;
        if (matchingEvents.length >= 2) {
          // Sort by time and calculate duration from first to last detection
          matchingEvents.sort((a, b) => a.tSec.compareTo(b.tSec));
          heldDurationSec =
              matchingEvents.last.tSec - matchingEvents.first.tSec;
        } else if (matchingEvents.length == 1) {
          // Single event = minimal held duration (use debounce as minimum)
          heldDurationSec = eventDebounceSec;
        }

        final expectedDurationSec = note.end - note.start;

        decisions.add(
          NoteDecision(
            type: DecisionType.hit,
            noteIndex: idx,
            expectedMidi: note.pitch,
            detectedMidi: bestEvent.midi,
            confidence: bestEvent.conf,
            dtSec: dtSec,
            window: (windowStart, windowEnd),
            heldDurationSec: heldDurationSec,
            expectedDurationSec: expectedDurationSec,
          ),
        );

        // SESSION-009: Track this pitch class as recently hit for sustain filtering
        _recentlyHitPitchClasses[expectedPitchClass] = now;

        // SESSION-015 P4: Release NoteTracker hold for this pitchClass
        // HOTFIX P4: Pass nowMs to keep cooldown active (prevents tail re-attack)
        _noteTracker.forceRelease(expectedPitchClass, nowMs: elapsed * 1000.0);

        if (kDebugMode) {
          // SESSION-015: Include latency compensation info in HIT log
          final latencyInfo = latencyCompEnabled
              ? 'latencyCompMs=${_latencyCompMs.toStringAsFixed(1)} '
                    'rawT=${bestEvent.tSec.toStringAsFixed(3)} adjT=${adjustedEventTSec.toStringAsFixed(3)}'
              : 'latencyComp=OFF';
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} expectedPC=$expectedPitchClass detectedMidi=${bestEvent.midi} '
            'freq=${bestEvent.freq.toStringAsFixed(1)} conf=${bestEvent.conf.toStringAsFixed(2)} '
            'stability=${bestEvent.stabilityFrames} distance=${bestDistance.toStringAsFixed(1)} '
            'dt=${dtSec.toStringAsFixed(3)}s $latencyInfo '
            'window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] result=HIT',
          );
        }
      } else {
        // LOG REJECT with detailed reason
        if (kDebugMode) {
          final finalReason = bestEvent == null
              ? (rejectReason ?? 'no_events_in_buffer')
              : 'distance_too_large=${bestDistance.toStringAsFixed(1)}_threshold=3.0';
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} expectedPC=$expectedPitchClass '
            'window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] '
            'result=REJECT reason=$finalReason '
            'bestEvent=${bestEvent != null ? "midi=${bestEvent.midi} freq=${bestEvent.freq.toStringAsFixed(1)} conf=${bestEvent.conf.toStringAsFixed(2)} stability=${bestEvent.stabilityFrames}" : "null"}',
          );
        }

        // ─────────────────────────────────────────────────────────────────────
        // SESSION-017 FIX: Emit WRONG_FLASH on pitch_class_mismatch REJECT
        // When user plays wrong pitch during an active note window, show red flash
        // This catches cases where detectedPC is in activeExpectedPitchClasses
        // (e.g., D# sustain from previous note) but mismatches current note's expectedPC
        // ─────────────────────────────────────────────────────────────────────
        if (rejectReason != null && rejectReason.startsWith('pitch_class_mismatch_expected=')) {
          // Parse detected info from rejectReason: "pitch_class_mismatch_expected=X_detected=Y"
          // Robust regex: captures both expectedPC and detectedPC
          final mismatchRegex = RegExp(r'pitch_class_mismatch_expected=(\d+)_detected=(\d+)');
          final mismatchMatch = mismatchRegex.firstMatch(rejectReason);

          if (mismatchMatch == null) {
            // FAIL-SAFE: Parse failed - log and skip
            if (kDebugMode) {
              debugPrint(
                'WRONG_FLASH_SKIP reason=parse_failed noteIdx=$idx '
                'rejectReason=$rejectReason',
              );
            }
          } else {
            final parsedExpectedPC = int.parse(mismatchMatch.group(1)!);
            final detectedPC = int.parse(mismatchMatch.group(2)!);

            // Find the event that caused this mismatch (highest conf with this PC in window)
            PitchEvent? mismatchEvent;
            for (final event in _events) {
              if (event.tSec >= windowStart && event.tSec <= windowEnd) {
                if ((event.midi % 12) == detectedPC) {
                  if (mismatchEvent == null || event.conf > mismatchEvent.conf) {
                    mismatchEvent = event;
                  }
                }
              }
            }

            if (mismatchEvent == null) {
              // FAIL-SAFE: No candidate event found - log and skip
              if (kDebugMode) {
                debugPrint(
                  'WRONG_FLASH_SKIP reason=no_candidate noteIdx=$idx '
                  'expectedPC=$parsedExpectedPC detectedPC=$detectedPC '
                  'eventsInBuffer=${_events.length}',
                );
              }
            } else if (mismatchEvent.conf < wrongFlashMinConf) {
              // FAIL-SAFE: Candidate confidence too low - log and skip
              if (kDebugMode) {
                debugPrint(
                  'WRONG_FLASH_SKIP reason=low_conf noteIdx=$idx '
                  'expectedPC=$parsedExpectedPC detectedPC=$detectedPC '
                  'detectedMidi=${mismatchEvent.midi} '
                  'conf=${mismatchEvent.conf.toStringAsFixed(2)} '
                  'threshold=$wrongFlashMinConf',
                );
              }
            } else {
              // Candidate is valid - apply gates

              // GATE 1: Global cooldown
              final globalCooldownOk =
                  _lastWrongFlashAt == null ||
                  now.difference(_lastWrongFlashAt!).inMilliseconds >
                      (wrongFlashCooldownSec * 1000);

              // GATE 2: Per-(noteIdx, detectedMidi) dedup to avoid blocking flash on other notes
              // Key format: "noteIdx_midi" to allow same wrong note to flash for different expected notes
              final dedupKey = '${idx}_${mismatchEvent.midi}';
              final lastFlashForKey = _mismatchDedupHistory[dedupKey];
              final perNoteDedupOk =
                  lastFlashForKey == null ||
                  now.difference(lastFlashForKey).inMilliseconds > wrongFlashDedupMs;

              // GATE 3: Confirmation count (anti-single-spike)
              // Key: noteIdx to track confirmations per target note
              final confirmKey = idx;
              final candidateList = _mismatchConfirmHistory.putIfAbsent(
                confirmKey,
                () => <double>[],
              );
              candidateList.add(mismatchEvent.tSec);
              final confirmWindowStartSec =
                  mismatchEvent.tSec - (wrongFlashConfirmWindowMs / 1000.0);
              candidateList.removeWhere((t) => t < confirmWindowStartSec);
              final confirmationOk = candidateList.length >= wrongFlashConfirmCount;

              if (globalCooldownOk && perNoteDedupOk && confirmationOk) {
                // All gates passed - emit WRONG_FLASH
                decisions.add(
                  NoteDecision(
                    type: DecisionType.wrongFlash,
                    noteIndex: idx,
                    expectedMidi: note.pitch,
                    detectedMidi: mismatchEvent.midi,
                    confidence: mismatchEvent.conf,
                  ),
                );
                _lastWrongFlashAt = now;
                _mismatchDedupHistory[dedupKey] = now;
                _mismatchConfirmHistory.remove(confirmKey);

                if (kDebugMode) {
                  debugPrint(
                    'WRONG_FLASH sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
                    'expectedMidi=${note.pitch} expectedPC=$expectedPitchClass '
                    'detectedMidi=${mismatchEvent.midi} detectedPC=$detectedPC '
                    'conf=${mismatchEvent.conf.toStringAsFixed(2)} '
                    'source=${mismatchEvent.source.name} '
                    'cooldownOk=$globalCooldownOk dedupOk=$perNoteDedupOk confirmOk=$confirmationOk '
                    'trigger=HIT_DECISION_REJECT_MISMATCH',
                  );
                }
              } else {
                // Gates blocked - log skip with details
                if (kDebugMode) {
                  debugPrint(
                    'WRONG_FLASH_SKIP reason=gated noteIdx=$idx '
                    'expectedPC=$parsedExpectedPC detectedPC=$detectedPC '
                    'detectedMidi=${mismatchEvent.midi} '
                    'conf=${mismatchEvent.conf.toStringAsFixed(2)} '
                    'cooldownOk=$globalCooldownOk dedupOk=$perNoteDedupOk '
                    'confirmations=${candidateList.length}/$wrongFlashConfirmCount',
                  );
                }
              }
            }
          }
        }
      }
    }

    // FIX BUG SESSION-005: Detect WRONG notes played (not matching any expected note)
    // Scan all recent events and find ones that don't match ANY active expected note
    final hasActiveNoteInWindow = noteEvents.asMap().entries.any((entry) {
      final idx = entry.key;
      final note = entry.value;
      if (hitNotes[idx]) return false; // Already hit
      final windowStart = note.start - headWindowSec;
      final windowEnd = note.end + tailWindowSec;
      return elapsed >= windowStart && elapsed <= windowEnd;
    });

    // Collect all expected pitch classes AND midis for active notes
    final activeExpectedPitchClasses = <int>{};
    final activeExpectedMidis = <int>[]; // SESSION-014: For outlier filter
    for (var idx = 0; idx < noteEvents.length; idx++) {
      if (hitNotes[idx]) continue;
      final note = noteEvents[idx];
      final windowStart = note.start - headWindowSec;
      final windowEnd = note.end + tailWindowSec;
      if (elapsed >= windowStart && elapsed <= windowEnd) {
        activeExpectedPitchClasses.add(note.pitch % 12);
        activeExpectedMidis.add(note.pitch);
      }
    }

    // SESSION-015: Compute plausible keyboard range based on expected notes
    // This filters ghost notes far outside the visible/playable range
    int minExpectedMidi = 999;
    int maxExpectedMidi = 0;
    for (final midi in activeExpectedMidis) {
      if (midi < minExpectedMidi) minExpectedMidi = midi;
      if (midi > maxExpectedMidi) maxExpectedMidi = midi;
    }
    // Plausible range: 24 semitones (2 octaves) around expected notes
    final plausibleMinMidi = minExpectedMidi - 24;
    final plausibleMaxMidi = maxExpectedMidi + 24;

    // ─────────────────────────────────────────────────────────────────────────
    // SESSION-016: WrongFlashGate helpers (local, minimal, readable)
    // ─────────────────────────────────────────────────────────────────────────

    // Effective onset RMS threshold (dynamic if auto-baseline complete, else preset)
    final double effectiveOnsetMinRms =
        _baselineComplete ? _dynamicOnsetMinRms : tuning.onsetMinRms;

    // Multiplier for PROBE override RMS check
    const double probeOverrideRmsMult = 2.0;
    const double probeOverrideConfMin = 0.92;
    const double highConfAttackConfMin = 0.90;

    /// Check if event is a high-confidence attack (bypasses outlier/range filters).
    bool isHighConfidenceAttack(PitchEvent e) {
      return e.conf >= highConfAttackConfMin;
    }

    /// Check if PROBE event can override the probe block.
    /// Requires: very high conf + RMS well above effective onset threshold.
    bool canOverrideProbe(PitchEvent e) {
      if (e.source != PitchEventSource.probe) return false;
      if (e.conf < probeOverrideConfMin) return false;
      if (e.rms < probeOverrideRmsMult * effectiveOnsetMinRms) return false;
      return true;
    }

    // Find events that DON'T match any expected pitch class = WRONG notes
    for (final event in _events) {
      // Only consider recent events (within last 500ms)
      if (event.tSec < elapsed - 0.5) continue;

      // SESSION-015: Initial confidence filter (basic threshold)
      if (event.conf < minConfForWrong) continue;

      final eventPitchClass = event.midi % 12;
      final isWrongNote = !activeExpectedPitchClasses.contains(eventPitchClass);

      // SESSION-014: Calculate minimum distance to any expected note (for outlier filter)
      int minDeltaToExpected = 999;
      for (final expectedMidi in activeExpectedMidis) {
        final delta = (event.midi - expectedMidi).abs();
        if (delta < minDeltaToExpected) {
          minDeltaToExpected = delta;
        }
      }

      // ─────────────────────────────────────────────────────────────────────
      // SESSION-016: WrongFlashGate - Multi-layer filtering for ghost flashes
      // ─────────────────────────────────────────────────────────────────────

      final bool highConfAttack = isHighConfidenceAttack(event);
      final bool probeOverride = canOverrideProbe(event);

      // FILTER 1: PROBE block - PROBE events don't trigger WRONG_FLASH
      // EXCEPTION: probeOverride allows very confident PROBE events through
      if (probeBlockWrongFlash &&
          event.source == PitchEventSource.probe &&
          !probeOverride) {
        if (kDebugMode) {
          debugPrint(
            'WRONG_FLASH_DROP reason=probe midi=${event.midi} '
            'conf=${event.conf.toStringAsFixed(2)} rms=${event.rms.toStringAsFixed(4)} '
            'effOnsetMinRms=${effectiveOnsetMinRms.toStringAsFixed(4)} '
            'minDelta=$minDeltaToExpected probeOverride=$probeOverride',
          );
        }
        continue;
      }

      // FILTER 2: PROBE safety fallback (if probeBlockWrongFlash=false)
      // Don't flag wrong notes from PROBE if delta > probeSafetyMaxDelta
      // EXCEPTION: probeOverride bypasses this filter too
      if (!probeOverride &&
          event.source == PitchEventSource.probe &&
          minDeltaToExpected > probeSafetyMaxDelta) {
        if (kDebugMode) {
          debugPrint(
            'WRONG_FLASH_DROP reason=probe_safety midi=${event.midi} '
            'conf=${event.conf.toStringAsFixed(2)} minDelta=$minDeltaToExpected '
            'threshold=$probeSafetyMaxDelta',
          );
        }
        continue;
      }

      // FILTER 3: Outlier filter - skip events too far from any expected note
      // This filters subharmonics like MIDI 34 when expecting MIDI 60-70
      // SESSION-016: BYPASS if highConfAttack (real intentional wrong note)
      if (!highConfAttack && minDeltaToExpected > maxSemitoneDeltaForWrong) {
        if (kDebugMode) {
          debugPrint(
            'WRONG_FLASH_DROP reason=outlier midi=${event.midi} '
            'conf=${event.conf.toStringAsFixed(2)} minDelta=$minDeltaToExpected '
            'threshold=$maxSemitoneDeltaForWrong',
          );
        }
        continue;
      }

      // FILTER 4: Out of plausible keyboard range
      // SESSION-016: BYPASS if highConfAttack (real intentional wrong note)
      if (!highConfAttack &&
          activeExpectedMidis.isNotEmpty &&
          (event.midi < plausibleMinMidi || event.midi > plausibleMaxMidi)) {
        if (kDebugMode) {
          debugPrint(
            'WRONG_FLASH_DROP reason=out_of_range midi=${event.midi} '
            'conf=${event.conf.toStringAsFixed(2)} '
            'range=[$plausibleMinMidi..$plausibleMaxMidi]',
          );
        }
        continue;
      }

      // FILTER 5: Low confidence for WRONG_FLASH (higher threshold than detection)
      if (event.conf < wrongFlashMinConf) {
        if (kDebugMode) {
          debugPrint(
            'WRONG_FLASH_DROP reason=low_conf midi=${event.midi} '
            'conf=${event.conf.toStringAsFixed(2)} threshold=$wrongFlashMinConf',
          );
        }
        continue;
      }

      // SESSION-009: Sustain filter - ignore pitch classes that were recently hit
      // This prevents sustain/reverb of previous note from triggering false "wrong"
      bool isSustainOfPreviousNote = false;
      final recentHitTime = _recentlyHitPitchClasses[eventPitchClass];
      if (recentHitTime != null) {
        final msSinceHit = now.difference(recentHitTime).inMilliseconds;
        if (msSinceHit < sustainFilterMs) {
          isSustainOfPreviousNote = true;
          if (kDebugMode && verboseDebug) {
            debugPrint(
              'WRONG_FLASH_DROP reason=sustain midi=${event.midi} '
              'pitchClass=$eventPitchClass msSinceHit=$msSinceHit',
            );
          }
        }
      }

      if (isWrongNote && hasActiveNoteInWindow && !isSustainOfPreviousNote) {
        // SESSION-015: FILTER 6 - Confirmation temporelle (anti-single-spike)
        // Require N detections of same wrong midi within time window
        final candidateList = _wrongCandidateHistory.putIfAbsent(
          event.midi,
          () => <double>[],
        );

        // Add current detection timestamp
        candidateList.add(event.tSec);

        // Prune old entries outside confirmation window
        final windowStartSec =
            event.tSec - (wrongFlashConfirmWindowMs / 1000.0);
        candidateList.removeWhere((t) => t < windowStartSec);

        // Check if we have enough confirmations
        if (candidateList.length < wrongFlashConfirmCount) {
          if (kDebugMode) {
            debugPrint(
              'WRONG_FLASH_DROP reason=unconfirmed midi=${event.midi} '
              'conf=${event.conf.toStringAsFixed(2)} '
              'detections=${candidateList.length}/$wrongFlashConfirmCount '
              'windowMs=$wrongFlashConfirmWindowMs',
            );
          }
          continue;
        }

        // This event doesn't match any expected note = WRONG (confirmed!)
        // SESSION-016: Log WRONG_FLASH_ALLOW for debugging (proves the gate was passed)
        if (kDebugMode) {
          final reason = highConfAttack
              ? 'highConfAttack'
              : probeOverride
                  ? 'probeOverride'
                  : 'normal';
          // Include RMS info for probeOverride (proves it met the threshold)
          final rmsInfo = probeOverride
              ? 'rms=${event.rms.toStringAsFixed(4)} effOnsetMinRms=${effectiveOnsetMinRms.toStringAsFixed(4)} mult=$probeOverrideRmsMult '
              : '';
          debugPrint(
            'WRONG_FLASH_ALLOW reason=$reason '
            'midi=${event.midi} conf=${event.conf.toStringAsFixed(2)} '
            '${rmsInfo}source=${event.source.name} minDelta=$minDeltaToExpected '
            'expected=$activeExpectedMidis',
          );
        }
        if (bestWrongEvent == null || event.conf > bestWrongEvent.conf) {
          bestWrongEvent = event;
          bestWrongMidi = event.midi;
        }
      }
    }

    // Trigger wrongFlash for wrong notes (independent of HITs)
    // FIX BUG SESSION-005: Allow wrongFlash even when a HIT was also registered
    // SESSION-018 FIX: Also allow wrongFlash in SILENCE mode (no active note)
    // Mode detection: mismatch (hasActiveNoteInWindow=true) vs silence (false)
    final bool isSilenceMode = !hasActiveNoteInWindow;

    // SESSION-018: Stricter gate for silence mode to avoid noise spam
    // In silence: require trigger/burst source AND very high confidence
    const double silenceModeMinConf = 0.92;
    final bool silenceGateOk = !isSilenceMode || (
      bestWrongEvent != null &&
      bestWrongEvent.source != PitchEventSource.probe &&
      bestWrongEvent.conf >= silenceModeMinConf
    );

    if (bestWrongEvent != null && silenceGateOk) {
      // Global cooldown check
      final globalCooldownOk =
          _lastWrongFlashAt == null ||
          now.difference(_lastWrongFlashAt!).inMilliseconds >
              (wrongFlashCooldownSec * 1000);

      // SESSION-014: Per-midi dedup check - prevent spam of same wrong note
      final lastFlashForMidi = _lastWrongFlashByMidi[bestWrongMidi!];
      final perMidiDedupOk =
          lastFlashForMidi == null ||
          now.difference(lastFlashForMidi).inMilliseconds > wrongFlashDedupMs;

      if (globalCooldownOk && perMidiDedupOk) {
        // SESSION-018 FIX: Find dominant active note (closest to elapsed time)
        // In silence mode, these will be null (no active note)
        int? dominantNoteIdx;
        int? dominantExpectedMidi;
        double minDistanceToNow = double.infinity;
        for (var idx = 0; idx < noteEvents.length; idx++) {
          if (hitNotes[idx]) continue;
          final note = noteEvents[idx];
          final windowStart = note.start - headWindowSec;
          final windowEnd = note.end + tailWindowSec;
          if (elapsed >= windowStart && elapsed <= windowEnd) {
            // Distance = how close note.start is to current elapsed time
            final distanceToNow = (note.start - elapsed).abs();
            if (distanceToNow < minDistanceToNow) {
              minDistanceToNow = distanceToNow;
              dominantNoteIdx = idx;
              dominantExpectedMidi = note.pitch;
            }
          }
        }

        decisions.add(
          NoteDecision(
            type: DecisionType.wrongFlash,
            // SESSION-018: noteIndex/expectedMidi are null in silence mode
            noteIndex: dominantNoteIdx,
            expectedMidi: dominantExpectedMidi,
            detectedMidi: bestWrongMidi,
            confidence: bestWrongEvent.conf,
          ),
        );
        _lastWrongFlashAt = now;
        _lastWrongFlashByMidi[bestWrongMidi] =
            now; // SESSION-014: Track per-midi
        _wrongCandidateHistory.remove(
          bestWrongMidi,
        ); // SESSION-015: Clear confirmation history

        if (kDebugMode) {
          // SESSION-018: Unified log with mode indicator
          final mode = isSilenceMode ? 'silence' : 'mismatch';
          int logMinDelta = isSilenceMode ? -1 : 999;
          if (!isSilenceMode) {
            for (final expectedMidi in activeExpectedMidis) {
              final delta = (bestWrongMidi - expectedMidi).abs();
              if (delta < logMinDelta) logMinDelta = delta;
            }
          }
          debugPrint(
            'WRONG_FLASH_EMIT mode=$mode sessionId=$_sessionId noteIdx=$dominantNoteIdx '
            'elapsed=${elapsed.toStringAsFixed(3)} expectedMidi=$dominantExpectedMidi '
            'detectedMidi=$bestWrongMidi detectedPC=${bestWrongMidi % 12} '
            'conf=${bestWrongEvent.conf.toStringAsFixed(2)} source=${bestWrongEvent.source.name} '
            'minDelta=$logMinDelta expectedMidis=$activeExpectedMidis',
          );
        }
      } else {
        // Log skip with reason
        if (kDebugMode) {
          final mode = isSilenceMode ? 'silence' : 'mismatch';
          debugPrint(
            'WRONG_FLASH_SKIP reason=gated mode=$mode midi=$bestWrongMidi '
            'conf=${bestWrongEvent.conf.toStringAsFixed(2)} '
            'globalCooldownOk=$globalCooldownOk perMidiDedupOk=$perMidiDedupOk',
          );
        }
      }
    } else if (bestWrongEvent != null && !silenceGateOk && kDebugMode) {
      // Log silence gate rejection
      debugPrint(
        'WRONG_FLASH_SKIP reason=silence_gate midi=$bestWrongMidi '
        'conf=${bestWrongEvent.conf.toStringAsFixed(2)} source=${bestWrongEvent.source.name} '
        'requiredConf=$silenceModeMinConf',
      );
    }

    return decisions;
  }
}

class NoteEvent {
  const NoteEvent({
    required this.start,
    required this.end,
    required this.pitch,
  });
  final double start;
  final double end;
  final int pitch;
}

/// Source of a pitch event (for PROBE safety filtering).
enum PitchEventSource {
  /// Event from onset trigger (first eval in burst).
  trigger,

  /// Event from burst window (subsequent evals after trigger).
  burst,

  /// Event from probe failsafe (soft attack recovery).
  probe,

  /// Event from legacy MPM path (non-hybrid).
  legacy,
}

class PitchEvent {
  const PitchEvent({
    required this.tSec,
    required this.midi,
    required this.freq,
    required this.conf,
    required this.rms,
    required this.stabilityFrames,
    this.source = PitchEventSource.legacy,
  });
  final double tSec;
  final int midi;
  final double freq;
  final double conf;
  final double rms;
  final int stabilityFrames;

  /// Source of this event (for PROBE safety filtering).
  final PitchEventSource source;
}

enum DecisionType { hit, miss, wrongFlash }

class NoteDecision {
  const NoteDecision({
    required this.type,
    this.noteIndex,
    this.expectedMidi,
    this.detectedMidi,
    this.confidence,
    this.dtSec,
    this.window,
    this.reason,
    this.heldDurationSec,
    this.expectedDurationSec,
  });

  final DecisionType type;
  final int? noteIndex;
  final int? expectedMidi;
  final int? detectedMidi;
  final double? confidence;
  final double? dtSec;
  final (double, double)? window;
  final String? reason;

  // Sustain scoring: actual held duration vs expected duration
  final double? heldDurationSec;
  final double? expectedDurationSec;

  /// Sustain ratio (0.0 to 1.0) - how long user held vs expected
  ///
  /// FIX BUG SESSION-003 #2: Microphone detection often captures only 1-2 events
  /// even when the note is held correctly. This caused precision to show ~19%
  /// when it should be ~85%+.
  ///
  /// Solution: A HIT note gets minimum 0.7 sustainRatio (played correctly but
  /// held duration unmeasurable), scaling up to 1.0 based on actual held time.
  double get sustainRatio {
    if (heldDurationSec == null ||
        expectedDurationSec == null ||
        expectedDurationSec! <= 0) {
      return 1.0; // Default to 100% if no duration data
    }

    // Calculate raw ratio
    final rawRatio = heldDurationSec! / expectedDurationSec!;

    // FIX: Minimum 0.7 for any HIT note (mic detection is unreliable for sustain)
    // This ensures a correctly played note doesn't get penalized unfairly
    // Scale: 0.7 (minimum) to 1.0 (full sustain detected)
    const minSustainForHit = 0.7;
    final scaledRatio =
        minSustainForHit + (rawRatio * (1.0 - minSustainForHit));

    return scaledRatio.clamp(0.0, 1.0);
  }
}
