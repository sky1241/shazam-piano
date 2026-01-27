import 'package:flutter/foundation.dart';

import 'mic_tuning.dart';

/// Result from NoteTracker.feed() - whether to emit a pitch event.
class NoteTrackerResult {
  const NoteTrackerResult({
    required this.shouldEmit,
    required this.reason,
    this.isNewAttack = false,
  });

  /// Whether to emit this pitch event to the buffer.
  final bool shouldEmit;

  /// Reason for the decision (for logging).
  final String reason;

  /// True if this is a NEW attack (not a continuation).
  /// Used for logging NOTE_START.
  final bool isNewAttack;
}

/// Envelope Gate for filtering tail/sustain from being detected as new attacks.
///
/// **Design Principles (P4 anti-lag):**
/// - O(1) per call (no loops over events, no FFT)
/// - Zero allocations per frame (fixed arrays, no maps that grow)
/// - 12 pitchClass states (not 128 midis)
///
/// **HOTFIX P4 changes:**
/// - NO bypass for onset trigger - all sources go through full gate
/// - forceRelease() keeps cooldown active (post-HIT protection)
/// - Hardened thresholds: confAttackMin=0.70, strict dRms > 0
/// - Rate-limited logs (1 per 120ms per pitchClass)
///
/// **SESSION-022 changes:**
/// - Re-attack on same note: if dRms > reattackDeltaThreshold while held,
///   force release and allow new attack (fixes "stuck note" bug)
/// - Max hold TTL: auto-release after maxHoldMs without activity
///   (fixes notes that never release due to reverb/confEma drift)
///
/// **Algorithm:**
/// 1. Track RMS envelope per pitchClass with EMA smoothing
/// 2. NEW ATTACK allowed only if ALL conditions met:
///    - `dRms > minAttackDelta` (strictly rising edge)
///    - `rmsNow > rmsEma + attackMargin` (above background)
///    - `conf >= confAttackMin` (high confidence)
///    - `cooldown elapsed` since last attack for this pitchClass
/// 3. TAIL blocked because:
///    - `dRms <= 0` during decay (falling edge)
///    - Even if dRms slightly positive, cooldown blocks re-trigger
/// 4. RE-ATTACK: if held but dRms > reattackDelta, force release + new attack
/// 5. TTL: if held > maxHoldMs, auto-release
class NoteTracker {
  NoteTracker({
    // Attack gate thresholds - HARDENED for anti-tail
    this.attackMarginAbs = 0.006,
    this.attackMarginRatio = 0.25, // 25% above EMA
    this.minAttackDelta = 0.003,
    this.confAttackMin = 0.70, // HOTFIX: was 0.50, now stricter
    // EMA smoothing
    this.rmsEmaAlpha = 0.25,
    this.confEmaAlpha = 0.30,
    // Cooldown/hold - HOTFIX: post-HIT keeps cooldown
    this.minHoldMs = 100.0,
    this.cooldownMs = 160.0,
    this.postHitCooldownMs = 200.0, // Extra cooldown after HIT
    // End detection (optional, for NOTE_END logging)
    this.releaseRatio = 0.40,
    this.marginEnd = 0.005,
    this.presenceEndThreshold = 0.30,
    this.endConsecutiveFrames = 4,
    // Log rate limiting
    this.logRateLimitMs = 120.0,
    // SESSION-022 V1: Re-attack parameters (LOWERED thresholds for repeated strikes)
    this.reattackDeltaThreshold =
        0.025, // Was 0.05, now lower to catch more reattacks
    this.minInterOnsetMs =
        80.0, // Minimum time between re-attacks (anti-reverb)
    // SESSION-022 V1: Silence-based hard release (fixes stuck notes)
    this.silenceRmsThreshold = 0.015, // RMS below this = silence
    this.silenceFramesForRelease =
        6, // Consecutive silent frames to trigger release
    // SESSION-022 V1: Conditional TTL (only if near-silence, not brute force)
    this.maxHoldMs =
        1200.0, // Increased from 800 - only kicks in if truly stuck
  });

  /// SESSION-016: Create NoteTracker from MicTuning preset.
  factory NoteTracker.fromTuning(MicTuning tuning) {
    return NoteTracker(
      attackMarginAbs: tuning.attackMarginAbs,
      attackMarginRatio: tuning.attackMarginRatio,
      minAttackDelta: tuning.minAttackDelta,
      confAttackMin: tuning.confAttackMin,
      cooldownMs: tuning.pitchClassCooldownMs,
      postHitCooldownMs: tuning.postHitCooldownMs,
      releaseRatio: tuning.releaseRatio,
      presenceEndThreshold: tuning.presenceEndThreshold,
      endConsecutiveFrames: tuning.endConsecutiveFrames,
      // SESSION-022 V1: Re-attack, silence release, and TTL parameters
      reattackDeltaThreshold: tuning.reattackDeltaThreshold,
      minInterOnsetMs: tuning.minInterOnsetMs,
      silenceRmsThreshold: tuning.silenceRmsThreshold,
      silenceFramesForRelease: tuning.silenceFramesForRelease,
      maxHoldMs: tuning.maxHoldMs,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PARAMETERS
  // ───────────────────────────────────────────────────────────────────────────

  /// Absolute margin above EMA (minimum).
  final double attackMarginAbs;

  /// Relative margin (ratio of EMA) - combined with abs for hybrid check.
  final double attackMarginRatio;

  /// Minimum positive delta (rmsNow - rmsPrev) to allow attack.
  /// STRICT: must be > 0, not >= 0.
  final double minAttackDelta;

  /// Minimum confidence to allow attack. HOTFIX: 0.70 (was 0.50).
  final double confAttackMin;

  /// EMA alpha for RMS smoothing (0 = no smoothing, 1 = instant).
  final double rmsEmaAlpha;

  /// EMA alpha for confidence smoothing.
  final double confEmaAlpha;

  /// Minimum hold time after ATTACK before allowing END (ms).
  final double minHoldMs;

  /// Cooldown after attack before allowing another attack for same pitchClass (ms).
  final double cooldownMs;

  /// Extra cooldown after HIT registration (prevents tail re-attack).
  final double postHitCooldownMs;

  /// Release ratio for END detection: rms < peakRms * releaseRatio.
  final double releaseRatio;

  /// Margin above noise floor for END detection.
  final double marginEnd;

  /// Presence threshold for END detection.
  final double presenceEndThreshold;

  /// Consecutive frames below threshold to trigger END.
  final int endConsecutiveFrames;

  /// Rate limit for suppress logs (ms) - prevents log spam.
  final double logRateLimitMs;

  /// SESSION-022 V1: Minimum dRms jump to force re-attack on a held note.
  /// If a note is held and we detect dRms > this threshold, it's a new strike.
  /// 0.025 = lowered from 0.05 to catch more repeated strikes.
  final double reattackDeltaThreshold;

  /// SESSION-022 V1: Minimum time between re-attacks (ms).
  /// Prevents reverb/tail from triggering false re-attacks.
  /// 80ms = allows fast repeated notes but filters reverb artifacts.
  final double minInterOnsetMs;

  /// SESSION-022 V1: RMS threshold for silence detection.
  /// If rmsNow < this for N consecutive frames, force release.
  /// 0.015 = just above typical noise floor.
  final double silenceRmsThreshold;

  /// SESSION-022 V1: Consecutive silent frames to trigger hard release.
  /// 6 frames = ~300-600ms depending on chunk rate.
  final int silenceFramesForRelease;

  /// SESSION-022 V1: Maximum hold duration before auto-release (ms).
  /// Only kicks in if silence-based release didn't trigger.
  /// 1200ms = generous timeout for long sustained notes.
  final double maxHoldMs;

  // ───────────────────────────────────────────────────────────────────────────
  // STATE (fixed arrays, O(1) access, zero allocations)
  // ───────────────────────────────────────────────────────────────────────────

  // Per pitchClass (0-11) tracking - fixed size arrays
  final List<double> _rmsEma = List.filled(12, 0.0);
  final List<double> _rmsPrev = List.filled(12, 0.0);
  final List<double> _confEma = List.filled(12, 0.0);
  final List<double> _peakRms = List.filled(12, 0.0);
  final List<double> _lastAttackMs = List.filled(12, -10000.0);
  final List<double> _attackStartMs = List.filled(12, -10000.0);
  final List<int> _belowThresholdFrames = List.filled(12, 0);
  final List<bool> _isHeld = List.filled(12, false);
  // SESSION-022 V1: Silence tracking for hard release
  final List<int> _silentFrames = List.filled(12, 0);
  final List<double> _lastReattackMs = List.filled(12, -10000.0);

  // Log rate limiting per pitchClass
  final List<double> _lastSuppressLogMs = List.filled(12, -10000.0);

  // Global noise floor estimation
  double _noiseFloorEma = 0.001;
  static const double _noiseFloorAlpha = 0.05; // Very slow adaptation

  // ───────────────────────────────────────────────────────────────────────────
  // STATS (fixed counters, O(1), zero allocs)
  // ───────────────────────────────────────────────────────────────────────────
  int _statsAttacks = 0;
  int _statsSuppressHeld = 0;
  int _statsSuppressCooldown = 0;
  int _statsSuppressTail = 0;
  int _statsReattacks = 0; // SESSION-022: Re-attacks on same note
  int _statsTtlReleases = 0; // SESSION-022: TTL auto-releases
  int _statsSilenceReleases = 0; // SESSION-022 V1: Silence-based releases
  double _lastStatsLogMs = -10000.0;
  static const double _statsLogIntervalMs = 5000.0; // Log stats every 5s

  /// Reset all state (call on session start).
  void reset() {
    for (var i = 0; i < 12; i++) {
      _rmsEma[i] = 0.0;
      _rmsPrev[i] = 0.0;
      _confEma[i] = 0.0;
      _peakRms[i] = 0.0;
      _lastAttackMs[i] = -10000.0;
      _attackStartMs[i] = -10000.0;
      _belowThresholdFrames[i] = 0;
      _isHeld[i] = false;
      _lastSuppressLogMs[i] = -10000.0;
      _silentFrames[i] = 0;
      _lastReattackMs[i] = -10000.0;
    }
    _noiseFloorEma = 0.001;
    _statsAttacks = 0;
    _statsSuppressHeld = 0;
    _statsSuppressCooldown = 0;
    _statsSuppressTail = 0;
    _statsReattacks = 0;
    _statsTtlReleases = 0;
    _statsSilenceReleases = 0;
    _lastStatsLogMs = -10000.0;
  }

  /// Feed a detected pitch and decide whether to emit it.
  ///
  /// Call this BEFORE adding a PitchEvent to the buffer.
  ///
  /// **HOTFIX P4:** No bypass for any source. All events go through:
  /// - risingEdge (dRms > minAttackDelta, strictly positive)
  /// - aboveBackground (rmsNow > rmsEma + margin)
  /// - confOk (conf >= confAttackMin)
  ///
  /// Parameters:
  /// - [midi]: Detected MIDI note
  /// - [rmsNow]: Current RMS level
  /// - [conf]: Detection confidence (0-1)
  /// - [nowMs]: Current elapsed time in milliseconds
  /// - [source]: Event source (trigger/burst/probe/legacy) - for logging only
  ///
  /// Returns [NoteTrackerResult] with decision and reason.
  NoteTrackerResult feed({
    required int midi,
    required double rmsNow,
    required double conf,
    required double nowMs,
    required String source,
  }) {
    final pc = midi % 12;

    // Periodic stats logging (every 5s)
    if (kDebugMode && nowMs - _lastStatsLogMs >= _statsLogIntervalMs) {
      _lastStatsLogMs = nowMs;
      if (_statsAttacks > 0 ||
          _statsSuppressHeld > 0 ||
          _statsSuppressCooldown > 0 ||
          _statsSuppressTail > 0 ||
          _statsReattacks > 0 ||
          _statsTtlReleases > 0 ||
          _statsSilenceReleases > 0) {
        debugPrint(
          'NOTE_STATS t=${nowMs.toStringAsFixed(0)}ms '
          'attacks=$_statsAttacks reattacks=$_statsReattacks '
          'silenceRel=$_statsSilenceReleases ttlRel=$_statsTtlReleases '
          'suppHeld=$_statsSuppressHeld suppCool=$_statsSuppressCooldown suppTail=$_statsSuppressTail',
        );
      }
    }

    // Update EMAs
    _rmsEma[pc] = _rmsEma[pc] * (1 - rmsEmaAlpha) + rmsNow * rmsEmaAlpha;
    _confEma[pc] = _confEma[pc] * (1 - confEmaAlpha) + conf * confEmaAlpha;

    // Calculate delta RMS (STRICT: must be > 0, not >= 0)
    final dRms = rmsNow - _rmsPrev[pc];
    _rmsPrev[pc] = rmsNow;

    // Update noise floor when not held (slow adaptation)
    if (!_isHeld[pc] && rmsNow < _noiseFloorEma * 2) {
      _noiseFloorEma =
          _noiseFloorEma * (1 - _noiseFloorAlpha) + rmsNow * _noiseFloorAlpha;
    }

    final msSinceAttack = nowMs - _lastAttackMs[pc];
    final cooldownOk = msSinceAttack >= cooldownMs;

    // Rate-limit helper for suppress logs
    bool canLogSuppress() {
      if (nowMs - _lastSuppressLogMs[pc] >= logRateLimitMs) {
        _lastSuppressLogMs[pc] = nowMs;
        return true;
      }
      return false;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // STATE: HELD (note is being sustained)
    // ─────────────────────────────────────────────────────────────────────────
    if (_isHeld[pc]) {
      // Track peak RMS during hold
      if (rmsNow > _peakRms[pc]) {
        _peakRms[pc] = rmsNow;
      }

      // ───────────────────────────────────────────────────────────────────────
      // SESSION-022 V1 FIX #1: SILENCE-BASED HARD RELEASE (highest priority)
      // If RMS drops to near-silence for N consecutive frames, force release.
      // This fixes notes that stay "held" forever in silence (see Evidence Table).
      // ───────────────────────────────────────────────────────────────────────
      final isSilent = rmsNow < silenceRmsThreshold;
      if (isSilent) {
        _silentFrames[pc]++;
        if (_silentFrames[pc] >= silenceFramesForRelease) {
          final heldMs = nowMs - _attackStartMs[pc];
          _isHeld[pc] = false;
          _belowThresholdFrames[pc] = 0;
          _silentFrames[pc] = 0;
          // Short cooldown to allow new attack soon after silence
          _lastAttackMs[pc] =
              nowMs - cooldownMs + 50; // 50ms cooldown remaining
          _statsSilenceReleases++;

          if (kDebugMode) {
            debugPrint(
              'NOTE_SILENCE_RELEASE midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
              'rms=${rmsNow.toStringAsFixed(4)} silentFrames=$silenceFramesForRelease '
              'heldMs=${heldMs.toStringAsFixed(0)} reason=silence_detected',
            );
          }

          return const NoteTrackerResult(
            shouldEmit: false,
            reason: 'silence_release',
            isNewAttack: false,
          );
        }
      } else {
        _silentFrames[pc] = 0; // Reset silence counter when sound detected
      }

      // ───────────────────────────────────────────────────────────────────────
      // SESSION-022 V1 FIX #2: RE-ATTACK on strong RMS jump (same note struck)
      // Conditions: dRms > threshold AND conf >= min AND minInterOnsetMs elapsed
      // The minInterOnsetMs prevents reverb artifacts from triggering false attacks.
      // ───────────────────────────────────────────────────────────────────────
      final msSinceLastReattack = nowMs - _lastReattackMs[pc];
      final interOnsetOk = msSinceLastReattack >= minInterOnsetMs;
      final isReattack =
          dRms > reattackDeltaThreshold &&
          conf >= confAttackMin &&
          interOnsetOk &&
          rmsNow > silenceRmsThreshold * 2; // Not in silence

      if (isReattack) {
        // SESSION-040 FIX: Return directly with new attack instead of falling through
        // CAUSE: cooldownOk was computed BEFORE re-attack reset, causing stale gate check
        final heldMs = nowMs - _attackStartMs[pc];
        _isHeld[pc] = false;
        _belowThresholdFrames[pc] = 0;
        _silentFrames[pc] = 0;
        _lastReattackMs[pc] = nowMs;
        _statsReattacks++;

        // Start new attack immediately (no fall-through needed)
        _lastAttackMs[pc] = nowMs;
        _attackStartMs[pc] = nowMs;
        _peakRms[pc] = rmsNow;
        _isHeld[pc] = true;
        _statsAttacks++;

        if (kDebugMode) {
          debugPrint(
            'NOTE_REATTACK midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
            'dRms=${dRms.toStringAsFixed(4)} threshold=${reattackDeltaThreshold.toStringAsFixed(4)} '
            'conf=${conf.toStringAsFixed(2)} heldMs=${heldMs.toStringAsFixed(0)} '
            'interOnsetMs=${msSinceLastReattack.toStringAsFixed(0)} reason=strong_rms_jump',
          );
          debugPrint(
            'REATTACK_ALLOWED midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
            'reason=direct_emit_no_fallthrough',
          );
        }

        // SESSION-040: Return directly with new attack (fixes stale cooldownOk bug)
        return const NoteTrackerResult(
          shouldEmit: true,
          reason: 'reattack',
          isNewAttack: true,
        );
      }
      // ───────────────────────────────────────────────────────────────────────
      // SESSION-022 V1 FIX #3: TTL auto-release (safety net for stuck notes)
      // Only kicks in after maxHoldMs if silence-based release didn't trigger.
      // ───────────────────────────────────────────────────────────────────────
      else if (msSinceAttack >= maxHoldMs) {
        final heldMs = nowMs - _attackStartMs[pc];
        _isHeld[pc] = false;
        _belowThresholdFrames[pc] = 0;
        _silentFrames[pc] = 0;
        // Keep cooldown active to prevent immediate re-trigger from reverb tail
        _lastAttackMs[pc] = nowMs;
        _statsTtlReleases++;

        if (kDebugMode) {
          debugPrint(
            'NOTE_TTL_RELEASE midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
            'heldMs=${heldMs.toStringAsFixed(0)} maxHoldMs=${maxHoldMs.toStringAsFixed(0)} '
            'rms=${rmsNow.toStringAsFixed(4)} conf=${conf.toStringAsFixed(2)} '
            'reason=ttl_expired',
          );
        }

        return const NoteTrackerResult(
          shouldEmit: false,
          reason: 'ttl_release',
          isNewAttack: false,
        );
      }
      // ───────────────────────────────────────────────────────────────────────
      // Original END detection (rms + conf below thresholds) - kept as fallback
      // ───────────────────────────────────────────────────────────────────────
      else if (msSinceAttack >= minHoldMs) {
        final endThreshold = (_noiseFloorEma + marginEnd).clamp(
          0.0,
          _peakRms[pc] * releaseRatio,
        );
        final rmsBelow = rmsNow < endThreshold;
        final confBelow = _confEma[pc] < presenceEndThreshold;

        if (rmsBelow && confBelow) {
          _belowThresholdFrames[pc]++;
          if (_belowThresholdFrames[pc] >= endConsecutiveFrames) {
            // NOTE_END: transition to idle
            final heldMs = nowMs - _attackStartMs[pc];
            _isHeld[pc] = false;
            _belowThresholdFrames[pc] = 0;
            _silentFrames[pc] = 0;

            if (kDebugMode) {
              debugPrint(
                'NOTE_END midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
                'rms=${rmsNow.toStringAsFixed(4)} conf=${conf.toStringAsFixed(2)} '
                'presence=${_confEma[pc].toStringAsFixed(2)} heldMs=${heldMs.toStringAsFixed(0)}',
              );
            }

            return const NoteTrackerResult(
              shouldEmit: false,
              reason: 'note_end',
              isNewAttack: false,
            );
          }
        } else {
          _belowThresholdFrames[pc] = 0;
        }
      }

      // Still held (no reattack, no silence release, no TTL, no end) - suppress
      if (_isHeld[pc]) {
        _statsSuppressHeld++;
        if (kDebugMode && canLogSuppress()) {
          debugPrint(
            'NOTE_SUPPRESS reason=held midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
            'rms=${rmsNow.toStringAsFixed(4)} conf=${conf.toStringAsFixed(2)} '
            'presence=${_confEma[pc].toStringAsFixed(2)} dRms=${dRms.toStringAsFixed(4)} '
            'silentFrames=${_silentFrames[pc]}',
          );
        }

        return const NoteTrackerResult(
          shouldEmit: false,
          reason: 'held',
          isNewAttack: false,
        );
      }
      // If we reach here, reattack forced release - fall through to attack logic
    }

    // ─────────────────────────────────────────────────────────────────────────
    // STATE: IDLE (checking for new attack)
    // ─────────────────────────────────────────────────────────────────────────

    // Cooldown check
    if (!cooldownOk) {
      _statsSuppressCooldown++;
      if (kDebugMode && canLogSuppress()) {
        debugPrint(
          'NOTE_SUPPRESS reason=cooldown midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
          'rms=${rmsNow.toStringAsFixed(4)} conf=${conf.toStringAsFixed(2)} '
          'msSinceAttack=${msSinceAttack.toStringAsFixed(0)} cooldownMs=$cooldownMs',
        );
      }

      return const NoteTrackerResult(
        shouldEmit: false,
        reason: 'cooldown',
        isNewAttack: false,
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ATTACK GATE CONDITIONS (NO BYPASS - all sources must pass)
    // HOTFIX P4: Removed isOnsetTrigger bypass
    // ─────────────────────────────────────────────────────────────────────────

    // 1. RMS above background (hybrid: max of absolute and relative margin)
    final dynamicMargin = _rmsEma[pc] * attackMarginRatio;
    final effectiveMargin = dynamicMargin > attackMarginAbs
        ? dynamicMargin
        : attackMarginAbs;
    final aboveBackground = rmsNow > _rmsEma[pc] + effectiveMargin;

    // 2. STRICT rising edge: dRms must be > minAttackDelta (not >=)
    final risingEdge = dRms > minAttackDelta;

    // 3. Confidence above minimum (HARDENED: 0.70)
    final confOk = conf >= confAttackMin;

    // ALL conditions must be met - NO BYPASS
    final allowAttack = risingEdge && aboveBackground && confOk;

    if (!allowAttack) {
      // TAIL: block because conditions not met
      _statsSuppressTail++;

      if (kDebugMode && canLogSuppress()) {
        // Build reason without string concat in hot path (use ternary)
        final reason = !risingEdge
            ? 'tail_falling'
            : !aboveBackground
            ? 'tail_below_bg'
            : 'tail_low_conf';
        debugPrint(
          'NOTE_SUPPRESS reason=$reason midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
          'rms=${rmsNow.toStringAsFixed(4)} dRms=${dRms.toStringAsFixed(4)} '
          'conf=${conf.toStringAsFixed(2)} rmsEma=${_rmsEma[pc].toStringAsFixed(4)} '
          'margin=${effectiveMargin.toStringAsFixed(4)} source=$source',
        );
      }

      return const NoteTrackerResult(
        shouldEmit: false,
        reason: 'tail',
        isNewAttack: false,
      );
    }

    // ─────────────────────────────────────────────────────────────────────────
    // NEW ATTACK: allow and transition to HELD
    // ─────────────────────────────────────────────────────────────────────────
    _lastAttackMs[pc] = nowMs;
    _attackStartMs[pc] = nowMs;
    _peakRms[pc] = rmsNow;
    _isHeld[pc] = true;
    _belowThresholdFrames[pc] = 0;
    _statsAttacks++;

    if (kDebugMode) {
      debugPrint(
        'NOTE_START midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
        'rms=${rmsNow.toStringAsFixed(4)} conf=${conf.toStringAsFixed(2)} '
        'confEma=${_confEma[pc].toStringAsFixed(2)} source=$source '
        'dRms=${dRms.toStringAsFixed(4)} margin=${effectiveMargin.toStringAsFixed(4)}',
      );
    }

    return const NoteTrackerResult(
      shouldEmit: true,
      reason: 'attack',
      isNewAttack: true,
    );
  }

  /// Release hold after HIT registration.
  ///
  /// **HOTFIX P4:** Does NOT reset cooldown - keeps post-HIT protection.
  /// The pitchClass exits HELD state but remains in cooldown for [postHitCooldownMs].
  /// This prevents tail of the hit note from being detected as a new attack.
  ///
  /// Semantics post-HIT:
  /// 1. _isHeld[pc] = false (no longer in HELD state)
  /// 2. _lastAttackMs[pc] = nowMs (restart cooldown from NOW)
  /// 3. Next attack requires: cooldown elapsed + risingEdge + aboveBackground + confOk
  void forceRelease(int pitchClass, {double? nowMs}) {
    final pc = pitchClass % 12;
    if (_isHeld[pc]) {
      _isHeld[pc] = false;
      _belowThresholdFrames[pc] = 0;

      // HOTFIX P4: Keep cooldown active after HIT
      // Set lastAttackMs to NOW so cooldown restarts (prevents tail re-attack)
      if (nowMs != null) {
        _lastAttackMs[pc] = nowMs;
      }
      // If nowMs not provided, keep existing lastAttackMs (still in cooldown)

      if (kDebugMode) {
        debugPrint(
          'NOTE_RELEASE pc=$pc reason=hit_registered postHitCooldown=${postHitCooldownMs}ms',
        );
      }
    }
  }

  /// Get current stats for external logging.
  String getStatsString() {
    return 'attacks=$_statsAttacks reattacks=$_statsReattacks '
        'silenceRel=$_statsSilenceReleases ttlRel=$_statsTtlReleases '
        'suppHeld=$_statsSuppressHeld suppCool=$_statsSuppressCooldown suppTail=$_statsSuppressTail';
  }
}
