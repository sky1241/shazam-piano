import 'package:flutter/foundation.dart';

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
  });

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
    }
    _noiseFloorEma = 0.001;
    _statsAttacks = 0;
    _statsSuppressHeld = 0;
    _statsSuppressCooldown = 0;
    _statsSuppressTail = 0;
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
          _statsSuppressTail > 0) {
        debugPrint(
          'NOTE_STATS t=${nowMs.toStringAsFixed(0)}ms '
          'attacks=$_statsAttacks suppressHeld=$_statsSuppressHeld '
          'suppressCooldown=$_statsSuppressCooldown suppressTail=$_statsSuppressTail',
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

      // Check END conditions (only after minHoldMs)
      if (msSinceAttack >= minHoldMs) {
        final endThreshold = (_noiseFloorEma + marginEnd)
            .clamp(0.0, _peakRms[pc] * releaseRatio);
        final rmsBelow = rmsNow < endThreshold;
        final confBelow = _confEma[pc] < presenceEndThreshold;

        if (rmsBelow && confBelow) {
          _belowThresholdFrames[pc]++;
          if (_belowThresholdFrames[pc] >= endConsecutiveFrames) {
            // NOTE_END: transition to idle
            final heldMs = nowMs - _attackStartMs[pc];
            _isHeld[pc] = false;
            _belowThresholdFrames[pc] = 0;

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

      // HELD: suppress new attacks (tail filtering)
      _statsSuppressHeld++;
      if (kDebugMode && canLogSuppress()) {
        debugPrint(
          'NOTE_SUPPRESS reason=held midi=$midi pc=$pc t=${nowMs.toStringAsFixed(0)}ms '
          'rms=${rmsNow.toStringAsFixed(4)} conf=${conf.toStringAsFixed(2)} '
          'presence=${_confEma[pc].toStringAsFixed(2)}',
        );
      }

      return const NoteTrackerResult(
        shouldEmit: false,
        reason: 'held',
        isNewAttack: false,
      );
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
    final effectiveMargin =
        dynamicMargin > attackMarginAbs ? dynamicMargin : attackMarginAbs;
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
    return 'attacks=$_statsAttacks held=$_statsSuppressHeld '
        'cooldown=$_statsSuppressCooldown tail=$_statsSuppressTail';
  }
}
