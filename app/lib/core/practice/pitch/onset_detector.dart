import 'package:flutter/foundation.dart';

import 'mic_tuning.dart';

/// Onset detection state returned by OnsetDetector.update().
enum OnsetState {
  /// Skip pitch evaluation - no onset detected, outside burst window.
  skip,

  /// Onset just triggered - start attack burst window.
  trigger,

  /// Inside attack burst window - allow pitch evaluation.
  burst,

  /// Probe failsafe - allow limited pitch evaluation when no onset detected
  /// but expected notes are active (for very soft attacks).
  probe,
}

/// Onset detector using RMS + EMA + delta threshold + cooldown + attack burst.
///
/// This gate decides WHEN to allow pitch detection, reducing spurious
/// detections during sustain/reverb tails of previous notes.
///
/// Design principles (for low-end hardware):
/// - O(1) per chunk (no FFT, no allocations)
/// - Robust to variable chunk sizes (100-200ms on cheap Android)
/// - Handles short taps, medium notes (1-2s), and long notes (3s+)
///
/// Algorithm:
/// 1. Compute EMA of RMS for background/ambient level tracking
/// 2. Detect onset when: rmsNow > minRms AND delta > threshold AND cooldown elapsed
/// 3. Open "attack burst" window allowing N evaluations over M ms
/// 4. Block evaluations outside burst (sustain/reverb filtering)
/// 5. Optional probe failsafe for missed soft onsets
class OnsetDetector {
  // SESSION-065: Optimized defaults based on research + weak signal diagnosis
  // - onsetMinRms: 0.008→0.005 (detect weaker signals, session-065 had RMS=0.0052)
  // - onsetDeltaRatioMin: 1.8→1.5 (more sensitive to onset variations)
  // - onsetCooldownMs: 180→120 (faster passages, research suggests 50-60ms for trills)
  // - probeIntervalMs: 300→200 (5 probes/s instead of 3, catches soft attacks)
  // SESSION-068: probeIntervalMs: 200→100 (10 probes/s, catches fast sequences like C5-D5-E5)
  // SESSION-068: probeRmsRatio: 0.5→0.3 (more sensitive probe threshold)
  OnsetDetector({
    this.emaAlpha = 0.15,
    this.onsetMinRms = 0.005, // SESSION-065: was 0.008, lowered for weak signals
    this.onsetDeltaAbsMin = 0.004,
    this.onsetDeltaRatioMin = 1.5, // SESSION-065: was 1.8, more sensitive
    this.onsetCooldownMs = 120, // SESSION-065: was 180, allows faster passages
    this.attackBurstMs = 200,
    this.maxEvalsPerBurst = 3,
    this.probeIntervalMs = 100, // SESSION-068: was 200, 10 probes/s for fast sequences
    this.probeEnabled = true,
    this.probeRmsRatio = 0.3, // SESSION-068: was 0.5 (implicit), lower threshold
  });

  /// SESSION-016: Create OnsetDetector from MicTuning preset.
  factory OnsetDetector.fromTuning(MicTuning tuning) {
    return OnsetDetector(
      emaAlpha: tuning.emaAlpha,
      onsetMinRms: tuning.onsetMinRms,
      onsetDeltaAbsMin: tuning.onsetDeltaAbsMin,
      onsetDeltaRatioMin: tuning.onsetDeltaRatioMin,
      onsetCooldownMs: tuning.onsetCooldownMs,
      attackBurstMs: tuning.attackBurstMs,
      maxEvalsPerBurst: tuning.maxEvalsPerBurst,
      probeIntervalMs: tuning.probeIntervalMs,
      probeEnabled: tuning.probeEnabled,
      probeRmsRatio: tuning.probeRmsRatio, // SESSION-068
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PARAMETERS (session-013 + session-065 optimizations + research document)
  // ─────────────────────────────────────────────────────────────────────────

  /// EMA smoothing factor (0 = no smoothing, 1 = instant).
  /// 0.15 = ~7 chunks to reach 63% of new level.
  /// Session-013: chunks ~100-150ms, so ~1s to adapt to new level.
  final double emaAlpha;

  /// Minimum RMS to even consider an onset.
  /// Session-013 evidence: silence RMS ≈ 0.001, attack RMS ≈ 0.035-0.244.
  /// SESSION-065: lowered from 0.008 to 0.005 to catch weak signals (RMS=0.0052 was missed).
  final double onsetMinRms;

  /// Minimum absolute delta (rmsNow - rmsEma) for onset.
  /// Session-013: delta between silence (0.001) and soft attack (0.035) ≈ 0.034.
  /// 0.004 catches transitions while ignoring EMA drift.
  final double onsetDeltaAbsMin;

  /// Minimum ratio (rmsNow / rmsEma) for onset.
  /// Session-013: ratio 0.035/0.001 = 35x for clean attack.
  /// SESSION-065: lowered from 1.8 to 1.5 for more sensitivity to onset variations.
  final double onsetDeltaRatioMin;

  /// Cooldown after onset before allowing another onset (ms).
  /// Session-013: note transitions ~788ms minimum (F→D# problem).
  /// SESSION-065: reduced from 180ms to 120ms (research: 50-60ms for fast trills).
  /// 120ms balances sustain filtering with fast passage support.
  final double onsetCooldownMs;

  /// Duration of attack burst window after onset (ms).
  /// During burst, pitch evaluations are allowed.
  /// 200ms covers variable latency (100-200ms chunks) with 2-3 evals.
  final double attackBurstMs;

  /// Maximum pitch evaluations allowed per burst.
  /// Limits buffer pollution if burst window spans multiple chunks.
  final int maxEvalsPerBurst;

  /// Interval for probe failsafe when no onset detected (ms).
  /// Allows catching very soft attacks that don't trigger onset.
  /// SESSION-065: reduced from 300ms to 200ms = 5 probes/s (was 3 probes/s).
  final double probeIntervalMs;

  /// Enable probe failsafe.
  /// Set false to completely block evaluations outside onsets.
  final bool probeEnabled;

  /// SESSION-068: Ratio of onsetMinRms for probe threshold.
  /// Probe triggers when rmsNow >= onsetMinRms * probeRmsRatio.
  /// Lower = more sensitive probes (catches softer notes during sustain).
  /// Default 0.3 (was implicit 0.5 before SESSION-068).
  final double probeRmsRatio;

  // ─────────────────────────────────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────────────────────────────────

  double _rmsEma = 0.0;
  double _lastOnsetMs = -10000.0;
  double _burstStartMs = -10000.0;
  int _evalsInCurrentBurst = 0;
  double _lastProbeMs = -10000.0;
  bool _initialized = false;

  // SESSION-068: Track last detected pitch for pitch-change re-trigger
  int? _lastDetectedMidi;
  double _lastPitchChangeMs = -10000.0;
  static const double _pitchChangeCooldownMs = 80.0; // Min time between pitch-change triggers
  static const int _pitchChangeMinSemitones = 2; // Min semitone diff to trigger

  // SESSION-068: Force probes during warmup period even if no expected notes
  double _sessionStartMs = 0.0;
  static const double _warmupPeriodMs = 3000.0; // 3s warmup for early detection

  /// Last RMS EMA value (for debugging).
  double get rmsEma => _rmsEma;

  /// Reset detector state (call on session start).
  void reset() {
    _rmsEma = 0.0;
    _lastOnsetMs = -10000.0;
    _burstStartMs = -10000.0;
    _evalsInCurrentBurst = 0;
    _lastProbeMs = -10000.0;
    _initialized = false;
    // SESSION-068: Reset pitch-change state
    _lastDetectedMidi = null;
    _lastPitchChangeMs = -10000.0;
    // SESSION-068: Reset warmup tracking
    _sessionStartMs = 0.0;
  }

  /// SESSION-068: Signal that a new pitch was detected.
  /// If pitch changed significantly, force a new burst to capture the note.
  /// Returns true if a burst was forced (caller should continue processing).
  bool signalPitchDetected({
    required int midi,
    required double nowMs,
    required double rmsNow,
  }) {
    final prevMidi = _lastDetectedMidi;
    _lastDetectedMidi = midi;

    // No previous pitch - nothing to compare
    if (prevMidi == null) return false;

    // Check if pitch changed significantly
    final semitoneDiff = (midi - prevMidi).abs();
    if (semitoneDiff < _pitchChangeMinSemitones) return false;

    // Check cooldown since last pitch-change trigger
    final msSincePitchChange = nowMs - _lastPitchChangeMs;
    if (msSincePitchChange < _pitchChangeCooldownMs) return false;

    // Check RMS threshold (must have some energy)
    if (rmsNow < onsetMinRms * probeRmsRatio) return false;

    // PITCH-CHANGE TRIGGER: Force a new burst
    _lastPitchChangeMs = nowMs;
    _burstStartMs = nowMs;
    _evalsInCurrentBurst = 0; // Reset eval count for new burst

    if (kDebugMode) {
      debugPrint(
        'ONSET_PITCH_CHANGE t=${nowMs.toStringAsFixed(0)}ms '
        'prevMidi=$prevMidi newMidi=$midi diff=$semitoneDiff '
        'rmsNow=${rmsNow.toStringAsFixed(4)} reason=pitch_shift_detected',
      );
    }

    return true;
  }

  /// Update detector with current RMS and time.
  ///
  /// Returns [OnsetState] indicating whether pitch evaluation is allowed.
  ///
  /// Parameters:
  /// - [rmsNow]: Current chunk RMS (already computed in MicEngine)
  /// - [nowMs]: Current elapsed time in milliseconds
  /// - [hasExpectedNotes]: Whether there are active expected notes
  ///
  /// Call this BEFORE pitch detection. If returns [OnsetState.skip],
  /// do NOT call the pitch detector (saves CPU, prevents queue pollution).
  OnsetState update({
    required double rmsNow,
    required double nowMs,
    required bool hasExpectedNotes,
  }) {
    // Initialize EMA on first call
    if (!_initialized) {
      _rmsEma = rmsNow;
      _initialized = true;
      _sessionStartMs = nowMs; // SESSION-068: Track session start
    }

    // Update EMA (exponential moving average)
    _rmsEma = _rmsEma * (1 - emaAlpha) + rmsNow * emaAlpha;

    // SESSION-068: Check if in warmup period (allow probes even without expected notes)
    final inWarmup = (nowMs - _sessionStartMs) < _warmupPeriodMs;

    // If no expected notes, skip UNLESS in warmup period with sufficient RMS
    if (!hasExpectedNotes) {
      // SESSION-068: During warmup, allow probes to detect early wrong notes
      if (inWarmup && rmsNow >= onsetMinRms) {
        final msSinceProbe = nowMs - _lastProbeMs;
        if (msSinceProbe >= probeIntervalMs) {
          _lastProbeMs = nowMs;
          if (kDebugMode) {
            debugPrint(
              'ONSET_WARMUP_PROBE t=${nowMs.toStringAsFixed(0)}ms '
              'rms=${rmsNow.toStringAsFixed(4)} reason=warmup_no_expected',
            );
          }
          return OnsetState.probe;
        }
      }
      // SESSION-068: Debug log for no expected notes
      if (kDebugMode && rmsNow >= onsetMinRms) {
        debugPrint(
          'ONSET_NO_EXPECTED t=${nowMs.toStringAsFixed(0)}ms '
          'rms=${rmsNow.toStringAsFixed(4)} inWarmup=$inWarmup reason=hasExpectedNotes_false',
        );
      }
      return OnsetState.skip;
    }

    // Check if we're in an active burst
    final msSinceBurst = nowMs - _burstStartMs;
    if (msSinceBurst >= 0 && msSinceBurst < attackBurstMs) {
      // Inside burst window
      if (_evalsInCurrentBurst < maxEvalsPerBurst) {
        _evalsInCurrentBurst++;
        if (kDebugMode) {
          debugPrint(
            'ONSET_BURST t=${nowMs.toStringAsFixed(0)}ms '
            'evalNum=$_evalsInCurrentBurst/$maxEvalsPerBurst '
            'burstRemaining=${(attackBurstMs - msSinceBurst).toStringAsFixed(0)}ms',
          );
        }
        return OnsetState.burst;
      } else {
        // Burst exhausted - still in window but no more evals
        return OnsetState.skip;
      }
    }

    // Check onset conditions
    final delta = rmsNow - _rmsEma;
    final ratio = _rmsEma > 0.0001 ? rmsNow / _rmsEma : 999.0;
    final msSinceOnset = nowMs - _lastOnsetMs;
    final cooldownOk = msSinceOnset >= onsetCooldownMs;

    // Onset trigger conditions:
    // 1. RMS above minimum threshold
    // 2. Delta above absolute OR ratio threshold (adaptive)
    // 3. Cooldown elapsed
    final aboveMinRms = rmsNow >= onsetMinRms;
    final deltaOk = delta >= onsetDeltaAbsMin || ratio >= onsetDeltaRatioMin;

    if (aboveMinRms && deltaOk && cooldownOk) {
      // ONSET TRIGGERED - start burst
      _lastOnsetMs = nowMs;
      _burstStartMs = nowMs;
      _evalsInCurrentBurst = 1; // This call counts as first eval

      if (kDebugMode) {
        debugPrint(
          'ONSET_TRIGGER t=${nowMs.toStringAsFixed(0)}ms '
          'rmsNow=${rmsNow.toStringAsFixed(4)} rmsEma=${_rmsEma.toStringAsFixed(4)} '
          'delta=${delta.toStringAsFixed(4)} ratio=${ratio.toStringAsFixed(2)} '
          'cooldownOk=$cooldownOk burstMs=$attackBurstMs',
        );
      }

      return OnsetState.trigger;
    }

    // No onset detected - check probe failsafe
    if (probeEnabled && hasExpectedNotes) {
      final msSinceProbe = nowMs - _lastProbeMs;
      // SESSION-068: Use configurable probeRmsRatio instead of hardcoded 0.5
      if (msSinceProbe >= probeIntervalMs && rmsNow >= onsetMinRms * probeRmsRatio) {
        // Probe allowed - but very limited
        _lastProbeMs = nowMs;

        if (kDebugMode) {
          debugPrint(
            'ONSET_PROBE t=${nowMs.toStringAsFixed(0)}ms '
            'rmsNow=${rmsNow.toStringAsFixed(4)} rmsEma=${_rmsEma.toStringAsFixed(4)} '
            'reason=failsafe_soft_attack',
          );
        }

        return OnsetState.probe;
      }
    }

    // Default: skip (outside burst, no onset, no probe)
    return OnsetState.skip;
  }

  /// Check if pitch evaluation is currently allowed.
  ///
  /// Convenience method that wraps [update] for simple bool check.
  bool allowPitchEval({
    required double rmsNow,
    required double nowMs,
    required bool hasExpectedNotes,
  }) {
    final state = update(
      rmsNow: rmsNow,
      nowMs: nowMs,
      hasExpectedNotes: hasExpectedNotes,
    );
    return state != OnsetState.skip;
  }
}
