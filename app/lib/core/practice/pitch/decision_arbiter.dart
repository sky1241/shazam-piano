import 'package:flutter/foundation.dart';

import 'onset_detector.dart';

// ═══════════════════════════════════════════════════════════════════════════
// DECISION ARBITER - Unified HIT/WRONG/MISS/SKIP/AMBIGUOUS decision point
// Refactored from dispersed logic in mic_engine.dart _matchNotes()
// ═══════════════════════════════════════════════════════════════════════════

/// Decision result types
/// SESSION-073 (Deep Research): Added wrongFreeplay for "no expected notes" case
enum DecisionResult { hit, wrong, wrongFreeplay, miss, skip, ambiguous }

/// Source of pitch event for tail-aware suppression
enum PitchSourceType { trigger, burst, probe, legacy }

/// Minimal pitch event info needed by arbiter
class ArbiterPitchEvent {
  const ArbiterPitchEvent({
    required this.midi,
    required this.conf,
    required this.tSec,
    required this.source,
    this.rms = 0.0,
    this.dRms = 0.0,
  });

  final int midi;
  final double conf;
  final double tSec;
  final PitchSourceType source;
  final double rms;
  final double dRms;
}

/// Minimal hit candidate info
class ArbiterHitCandidate {
  const ArbiterHitCandidate({
    required this.midi,
    required this.tMs,
    required this.conf,
    required this.dtFromOnsetMs,
  });

  final int midi;
  final double tMs;
  final double conf;
  final double dtFromOnsetMs;
}

/// Minimal wrong sample info
class ArbiterWrongSample {
  const ArbiterWrongSample({
    required this.midi,
    required this.conf,
    required this.tMs,
    required this.isTriggerOrFailsafe,
  });

  final int midi;
  final double conf;
  final double tMs;
  final bool isTriggerOrFailsafe;
}

// ═══════════════════════════════════════════════════════════════════════════
// DECISION INPUTS - All signals needed for decision (SIGNAL category)
// ═══════════════════════════════════════════════════════════════════════════

class DecisionInputs {
  const DecisionInputs({
    // A. Timing / Window
    required this.elapsedMs,
    required this.noteWindowStartMs,
    required this.noteWindowEndMs,
    required this.noteIdx,
    // B. Note context
    required this.expectedMidi,
    required this.alreadyHit,
    // C. Detection / Candidates
    required this.bestEvent,
    required this.bestDistance,
    required this.matchedCandidate,
    required this.fallbackSample,
    // D. Onset / Attack
    required this.onsetState,
    required this.lastOnsetTriggerMs,
    required this.attackId,
    // E. Signal gates
    required this.isWithinGracePeriod,
    required this.isLookaheadMatch,
    required this.wrongFlashEmittedThisTick,
    // F. History for brakes
    required this.lastWrongFlashAtMs,
    required this.lastWrongFlashForMidiMs,
    required this.lastTripleFlashMs,
    required this.wfDedupLastEmitMs,
    required this.hitAttackIdMs,
    required this.recentHitForDetectedPCMs,
    // G. Clear pitch age
    required this.clearPitchAgeMs,
    // H. Thresholds from existing code
    required this.hitDistanceThreshold,
    required this.dtMaxMs,
    required this.wrongFlashMinConf,
    required this.gracePeriodMs,
    required this.sustainThresholdMs,
    // I. Confirmation tracking
    required this.confirmationCount,
    // J. Computed dt for HIT
    required this.candidateDtMs,
    // K. Snap allowed
    required this.snapAllowed,
    // L. Now timestamp for brake checks
    required this.nowMs,
  });

  // ═══ A. TIMING / WINDOW ═══
  // source: mic_engine.dart:1949 _matchNotes() elapsed param * 1000
  final double elapsedMs;
  // source: mic_engine.dart:1988 note.start - headWindowSec
  final double noteWindowStartMs;
  // source: mic_engine.dart:1989 note.end + tailWindowSec
  final double noteWindowEndMs;
  // source: mic_engine.dart:1984 loop index
  final int noteIdx;

  // ═══ B. NOTE CONTEXT ═══
  // source: mic_engine.dart:1987 note.pitch
  final int expectedMidi;
  // derived: expectedMidi % 12
  int get expectedPC => expectedMidi % 12;
  // source: mic_engine.dart:1985 hitNotes[idx]
  final bool alreadyHit;

  // ═══ C. DETECTION / CANDIDATES ═══
  // source: mic_engine.dart:2075-2168 bestEvent from _events buffer scan
  final ArbiterPitchEvent? bestEvent;
  // source: mic_engine.dart:2153-2156 distance calculation
  final double? bestDistance;
  // source: mic_engine.dart:2175-2264 _hitCandidates fallback
  final ArbiterHitCandidate? matchedCandidate;
  // source: mic_engine.dart:2446-2476 _recentWrongSamples
  final ArbiterWrongSample? fallbackSample;

  // ═══ D. ONSET / ATTACK ═══
  // source: mic_engine.dart:830 _lastOnsetState
  final OnsetState onsetState;
  // source: mic_engine.dart:831 _lastOnsetTriggerElapsedMs
  final double lastOnsetTriggerMs;
  // source: mic_engine.dart:2389 _lastOnsetTriggerElapsedMs.round()
  final int attackId;

  // ═══ E. SIGNAL GATES ═══
  // source: mic_engine.dart:2492 (elapsed - windowStart) * 1000 < kFallbackGracePeriodMs
  final bool isWithinGracePeriod;
  // source: mic_engine.dart:698-740 _isLookaheadMatch()
  final bool isLookaheadMatch;
  // source: mic_engine.dart:1952-1955 _wrongFlashEmittedThisTick
  final bool wrongFlashEmittedThisTick;

  // ═══ F. HISTORY FOR BRAKES ═══
  // source: mic_engine.dart:2480 _lastWrongFlashAt (converted to ms)
  final double? lastWrongFlashAtMs;
  // source: mic_engine.dart:2484 _lastWrongFlashByMidi[midi] (converted to ms)
  final double? lastWrongFlashForMidiMs;
  // source: mic_engine.dart:2505 _wrongFlashTripleDedupHistory[key] (converted to ms)
  final double? lastTripleFlashMs;
  // source: mic_engine.dart:616 _wfDedupHistory[key]
  final int? wfDedupLastEmitMs;
  // source: mic_engine.dart:652-667 _hitAttackIdHistory[attackId]
  final int? hitAttackIdMs;
  // source: mic_engine.dart:2610 _recentlyHitPitchClasses[detectedPC] (converted to ms)
  final double? recentHitForDetectedPCMs;

  // ═══ G. CLEAR PITCH AGE ═══
  // source: mic_engine.dart:1276-1291 _lastDetectedElapsedMs
  // Represents ms since last clear/high-conf pitch detection
  final double clearPitchAgeMs;

  // ═══ H. THRESHOLDS (from existing constants) ═══
  // source: mic_engine.dart:2268 bestDistance <= 3.0 (but we use existing threshold)
  final double hitDistanceThreshold;
  // source: mic_engine.dart:381 kHitDtMaxMs = 250
  final double dtMaxMs;
  // source: mic_engine.dart wrongFlashMinConf = 0.75
  final double wrongFlashMinConf;
  // source: mic_engine.dart:369 kFallbackGracePeriodMs = 400
  final double gracePeriodMs;
  // source: mic_engine.dart:302-303 kSustainWrongSuppressTriggerMs/ProbeMs
  final double sustainThresholdMs;

  // ═══ I. CONFIRMATION COUNT ═══
  // source: mic_engine.dart:2799-2811 candidateList.length
  final int confirmationCount;

  // ═══ J. COMPUTED DT ═══
  // source: mic_engine.dart:2289-2299 dtSec calculation
  final double? candidateDtMs;

  // ═══ K. SNAP ALLOWED ═══
  // source: mic_engine.dart:2108-2115 _shouldSnapToExpected()
  final bool snapAllowed;

  // ═══ L. NOW TIMESTAMP ═══
  // source: mic_engine.dart:1949 now param
  final double nowMs;

  /// Helper: detected pitch class (if event exists)
  int? get detectedPC => bestEvent?.midi != null ? bestEvent!.midi % 12 : null;

  /// Helper: is octave error (same PC, different octave)
  bool get isOctaveError {
    if (bestEvent == null || bestDistance == null) return false;
    final detPC = bestEvent!.midi % 12;
    return detPC == expectedPC && bestDistance! > hitDistanceThreshold;
  }

  /// Helper: is pitch class mismatch
  bool get isPitchClassMismatch {
    if (bestEvent == null) return false;
    final detPC = bestEvent!.midi % 12;
    return detPC != expectedPC && !snapAllowed;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DECISION OUTPUT
// ═══════════════════════════════════════════════════════════════════════════

class DecisionOutput {
  const DecisionOutput({
    required this.result,
    required this.reason,
    required this.path,
    this.detectedMidi,
    this.confidence,
    this.dtMs,
    this.gatedBy,
  });

  final DecisionResult result;
  final String reason;
  final String path;
  final int? detectedMidi;
  final double? confidence;
  final double? dtMs;
  final String? gatedBy;

  /// Convert to log string
  String toLogString(int noteIdx) {
    return 'DECIDE_OUT noteIdx=$noteIdx result=${result.name} '
        'reason=$reason path=$path '
        'detectedMidi=$detectedMidi '
        'dtMs=${dtMs?.toStringAsFixed(0) ?? "null"} '
        'gatedBy=${gatedBy ?? "none"}';
  }

  /// Create a copy with modified fields
  DecisionOutput copyWith({
    DecisionResult? result,
    String? reason,
    String? path,
    int? detectedMidi,
    double? confidence,
    double? dtMs,
    String? gatedBy,
  }) {
    return DecisionOutput(
      result: result ?? this.result,
      reason: reason ?? this.reason,
      path: path ?? this.path,
      detectedMidi: detectedMidi ?? this.detectedMidi,
      confidence: confidence ?? this.confidence,
      dtMs: dtMs ?? this.dtMs,
      gatedBy: gatedBy ?? this.gatedBy,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ARBITER STATS (for SUMMARY_END)
// ═══════════════════════════════════════════════════════════════════════════

class ArbiterStats {
  int totalDecisions = 0;
  int hitCount = 0;
  int missCount = 0;
  int wrongCount = 0;
  int skipCount = 0;
  int ambiguousCount = 0;

  // Skip breakdown by reason
  final Map<String, int> skipByReason = {};
  // Wrong breakdown by reason
  final Map<String, int> wrongByReason = {};
  // Ambiguous breakdown by reason
  final Map<String, int> ambiguousByReason = {};

  // Gates breakdown
  int gatedByTTL = 0;
  int gatedByCooldown = 0;
  int gatedBySustain = 0;
  int gatedByLookahead = 0;
  int gatedByPerTick = 0;
  int gatedByHitBlocks = 0;
  int gatedByTriple = 0;
  int gatedByPerMidi = 0;
  int gatedByGrace = 0;
  int gatedByConfirm = 0;

  void recordDecision(DecisionOutput output) {
    totalDecisions++;
    switch (output.result) {
      case DecisionResult.hit:
        hitCount++;
        break;
      case DecisionResult.miss:
        missCount++;
        break;
      case DecisionResult.wrong:
      case DecisionResult.wrongFreeplay:
        // SESSION-073: wrongFreeplay counts as wrong for stats
        wrongCount++;
        wrongByReason[output.reason] = (wrongByReason[output.reason] ?? 0) + 1;
        break;
      case DecisionResult.skip:
        skipCount++;
        skipByReason[output.reason] = (skipByReason[output.reason] ?? 0) + 1;
        if (output.gatedBy != null) {
          _recordGate(output.gatedBy!);
        }
        break;
      case DecisionResult.ambiguous:
        ambiguousCount++;
        ambiguousByReason[output.reason] =
            (ambiguousByReason[output.reason] ?? 0) + 1;
        break;
    }
  }

  void _recordGate(String gate) {
    switch (gate) {
      case 'ttl_dedup':
        gatedByTTL++;
        break;
      case 'cooldown':
        gatedByCooldown++;
        break;
      case 'sustain':
        gatedBySustain++;
        break;
      case 'lookahead':
        gatedByLookahead++;
        break;
      case 'per_tick':
        gatedByPerTick++;
        break;
      case 'hit_blocks':
        gatedByHitBlocks++;
        break;
      case 'triple_dedup':
        gatedByTriple++;
        break;
      case 'per_midi':
        gatedByPerMidi++;
        break;
      case 'grace_period':
        gatedByGrace++;
        break;
      case 'confirm_count':
        gatedByConfirm++;
        break;
    }
  }

  void reset() {
    totalDecisions = 0;
    hitCount = 0;
    missCount = 0;
    wrongCount = 0;
    skipCount = 0;
    ambiguousCount = 0;
    skipByReason.clear();
    wrongByReason.clear();
    ambiguousByReason.clear();
    gatedByTTL = 0;
    gatedByCooldown = 0;
    gatedBySustain = 0;
    gatedByLookahead = 0;
    gatedByPerTick = 0;
    gatedByHitBlocks = 0;
    gatedByTriple = 0;
    gatedByPerMidi = 0;
    gatedByGrace = 0;
    gatedByConfirm = 0;
  }

  String toSummaryString() {
    final wrongReasons = wrongByReason.entries
        .map((e) => '${e.key}=${e.value}')
        .join(',');
    final skipReasons = skipByReason.entries
        .map((e) => '${e.key}=${e.value}')
        .join(',');
    final ambigReasons = ambiguousByReason.entries
        .map((e) => '${e.key}=${e.value}')
        .join(',');

    return 'SUMMARY_END total=$totalDecisions '
        'HIT=$hitCount MISS=$missCount WRONG=$wrongCount '
        'SKIP=$skipCount AMBIGUOUS=$ambiguousCount '
        'WRONG_BY_REASON={$wrongReasons} '
        'SKIP_BY_REASON={$skipReasons} '
        'AMBIGUOUS_BY_REASON={$ambigReasons} '
        'gatedTTL=$gatedByTTL gatedCooldown=$gatedByCooldown '
        'gatedSustain=$gatedBySustain gatedLookahead=$gatedByLookahead '
        'gatedPerTick=$gatedByPerTick gatedHitBlocks=$gatedByHitBlocks '
        'gatedTriple=$gatedByTriple gatedPerMidi=$gatedByPerMidi '
        'gatedGrace=$gatedByGrace gatedConfirm=$gatedByConfirm';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DECISION ARBITER - Main class
// ═══════════════════════════════════════════════════════════════════════════

class DecisionArbiter {
  DecisionArbiter({
    // Brake thresholds (from existing code)
    this.globalCooldownMs = 100.0,
    this.perMidiDedupMs = 150.0,
    this.tripleDedupMs = 200.0,
    this.ttlDedupMs = 1500.0,
    this.hitBlocksTtlMs = 500.0,
    this.sustainTriggerMs = 350.0,
    this.sustainProbeMs = 600.0,
    this.octaveConfirmRequired = 2,
    this.clearPitchRecentMs = 200.0,
  });

  // ═══ BRAKE THRESHOLDS ═══
  // source: mic_engine.dart wrongFlashCooldownSec * 1000
  final double globalCooldownMs;
  // source: mic_engine.dart:588 wrongFlashDedupMs = 150
  final double perMidiDedupMs;
  // source: mic_engine.dart:613 _wrongFlashTripleDedupMs = 200
  final double tripleDedupMs;
  // source: mic_engine.dart:623 _wfDedupTtlMs = 1500
  final double ttlDedupMs;
  // source: mic_engine.dart:633 _hitAttackIdTtlMs = 500
  final double hitBlocksTtlMs;
  // source: mic_engine.dart:302 kSustainWrongSuppressTriggerMs = 350
  final double sustainTriggerMs;
  // source: mic_engine.dart:303 kSustainWrongSuppressProbeMs = 600
  final double sustainProbeMs;
  // OCTAVE promotion requires N confirmations
  final int octaveConfirmRequired;
  // How recent a pitch must be to block fallback wrong
  final double clearPitchRecentMs;

  final ArbiterStats stats = ArbiterStats();

  void reset() {
    stats.reset();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DECIDE - Pure priority-based decision (no brakes yet)
  // ═══════════════════════════════════════════════════════════════════════

  DecisionOutput decide(DecisionInputs inputs) {
    // Log DECIDE_IN
    if (kDebugMode) {
      debugPrint(
        'DECIDE_IN noteIdx=${inputs.noteIdx} '
        'elapsed=${inputs.elapsedMs.toStringAsFixed(0)} '
        'expectedMidi=${inputs.expectedMidi} '
        'attackId=${inputs.attackId} '
        'hasBestEvent=${inputs.bestEvent != null} '
        'hasCandidate=${inputs.matchedCandidate != null} '
        'hasFallback=${inputs.fallbackSample != null} '
        'onsetState=${inputs.onsetState.name} '
        'clearPitchAgeMs=${inputs.clearPitchAgeMs.toStringAsFixed(0)}',
      );
    }

    // ═══ P0: Already hit ═══
    if (inputs.alreadyHit) {
      return const DecisionOutput(
        result: DecisionResult.skip,
        reason: 'already_hit',
        path: 'P0_ALREADY_HIT',
      );
    }

    // ═══ P1: Not in window yet ═══
    if (inputs.elapsedMs < inputs.noteWindowStartMs) {
      return const DecisionOutput(
        result: DecisionResult.skip,
        reason: 'not_in_window',
        path: 'P1_NOT_IN_WINDOW',
      );
    }

    // ═══ P2: Window timeout -> MISS ═══
    if (inputs.elapsedMs > inputs.noteWindowEndMs) {
      return DecisionOutput(
        result: DecisionResult.miss,
        reason: 'timeout',
        path: 'P2_TIMEOUT',
        detectedMidi: inputs.expectedMidi,
      );
    }

    // ═══ P3: HIT match valide ═══
    // source: mic_engine.dart:2268 bestEvent != null && bestDistance <= 3.0
    if (inputs.bestEvent != null &&
        inputs.bestDistance != null &&
        inputs.bestDistance! <= inputs.hitDistanceThreshold) {
      // Check dt guard
      if (inputs.candidateDtMs != null &&
          inputs.candidateDtMs!.abs() <= inputs.dtMaxMs) {
        return DecisionOutput(
          result: DecisionResult.hit,
          reason: 'hit_match',
          path: 'P3_HIT_MATCH',
          detectedMidi: inputs.bestEvent!.midi,
          confidence: inputs.bestEvent!.conf,
          dtMs: inputs.candidateDtMs,
        );
      }
    }

    // ═══ P4: HIT candidate fallback ═══
    // source: mic_engine.dart:2175-2264 _hitCandidates
    if (inputs.matchedCandidate != null) {
      // Candidate already passed dtGuard in collection
      return DecisionOutput(
        result: DecisionResult.hit,
        reason: 'candidate_fallback',
        path: 'P4_CANDIDATE_FALLBACK',
        detectedMidi: inputs.matchedCandidate!.midi,
        confidence: inputs.matchedCandidate!.conf,
        dtMs: inputs.matchedCandidate!.dtFromOnsetMs,
      );
    }

    // ═══ P5: Candidate exists but dt exceeded ═══
    if (inputs.bestEvent != null &&
        inputs.bestDistance != null &&
        inputs.bestDistance! <= inputs.hitDistanceThreshold &&
        inputs.candidateDtMs != null &&
        inputs.candidateDtMs!.abs() > inputs.dtMaxMs) {
      return DecisionOutput(
        result: DecisionResult.ambiguous,
        reason: 'dt_exceeded',
        path: 'P5_DT_EXCEEDED',
        detectedMidi: inputs.bestEvent!.midi,
        confidence: inputs.bestEvent!.conf,
        dtMs: inputs.candidateDtMs,
      );
    }

    // ═══ P6: Octave error candidate ═══
    // source: mic_engine.dart:2577-2723 bestEvent != null && bestDistance > 3.0 && isPitchClassMatch
    if (inputs.isOctaveError) {
      // AMBIGUOUS - needs confirmation via postBrakes to become WRONG
      return DecisionOutput(
        result: DecisionResult.ambiguous,
        reason: 'octave_error_candidate',
        path: 'P6_OCTAVE_ERROR',
        detectedMidi: inputs.bestEvent!.midi,
        confidence: inputs.bestEvent!.conf,
      );
    }

    // ═══ P7: Pitch class mismatch candidate ═══
    // source: mic_engine.dart:2726-2933 rejectReason contains "pitch_class_mismatch"
    if (inputs.isPitchClassMismatch &&
        inputs.bestEvent != null &&
        inputs.bestEvent!.conf >= inputs.wrongFlashMinConf) {
      return DecisionOutput(
        result: DecisionResult.ambiguous,
        reason: 'pc_mismatch_candidate',
        path: 'P7_PC_MISMATCH',
        detectedMidi: inputs.bestEvent!.midi,
        confidence: inputs.bestEvent!.conf,
      );
    }

    // ═══ P8: No-events fallback candidate ═══
    // source: mic_engine.dart:2431-2567 bestEvent == null && fallbackSample != null
    if (inputs.bestEvent == null && inputs.fallbackSample != null) {
      return DecisionOutput(
        result: DecisionResult.ambiguous,
        reason: 'no_events_fallback_candidate',
        path: 'P8_NO_EVENTS_FALLBACK',
        detectedMidi: inputs.fallbackSample!.midi,
        confidence: inputs.fallbackSample!.conf,
      );
    }

    // ═══ P9: No candidate ═══
    return const DecisionOutput(
      result: DecisionResult.skip,
      reason: 'no_candidate',
      path: 'P9_NO_CANDIDATE',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // POST BRAKES - Apply brakes and possibly promote AMBIGUOUS to WRONG
  // ═══════════════════════════════════════════════════════════════════════

  DecisionOutput postBrakes(DecisionOutput output, DecisionInputs inputs) {
    // HIT and MISS pass through without brakes
    if (output.result == DecisionResult.hit ||
        output.result == DecisionResult.miss) {
      return output;
    }

    // SKIP passes through
    if (output.result == DecisionResult.skip) {
      return output;
    }

    // ═══ FIX #2: dt_exceeded is diagnostic, do NOT apply brakes ═══
    // This keeps dt_exceeded measurable without being "crushed" by gates.
    if (output.reason == 'dt_exceeded') {
      return output;
    }

    // AMBIGUOUS and initial WRONG need brake checks
    final detectedMidi = output.detectedMidi;
    if (detectedMidi == null) {
      return output.copyWith(
        result: DecisionResult.skip,
        reason: 'no_detected_midi',
        gatedBy: 'no_midi',
      );
    }

    final detectedPC = detectedMidi % 12;

    // ═══ BRAKE 1: Per-tick flag ═══
    // source: mic_engine.dart:2622-2623 tickOk = !_wrongFlashEmittedThisTick
    if (inputs.wrongFlashEmittedThisTick) {
      return output.copyWith(
        result: DecisionResult.skip,
        reason: 'gated_per_tick',
        gatedBy: 'per_tick',
      );
    }

    // ═══ BRAKE 2: Hit blocks wrong (same attackId) ═══
    // source: mic_engine.dart:652-667 _hitAttackIdHistory[attackId]
    if (inputs.hitAttackIdMs != null) {
      final msSinceHit = inputs.nowMs - inputs.hitAttackIdMs!;
      if (msSinceHit < hitBlocksTtlMs) {
        if (kDebugMode) {
          debugPrint(
            'S43_HIT_BLOCK attackId=${inputs.attackId} '
            'msSinceHit=${msSinceHit.toStringAsFixed(0)} '
            'noteIdx=${inputs.noteIdx}',
          );
        }
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'gated_hit_blocks',
          gatedBy: 'hit_blocks',
        );
      }
    }

    // ═══ BRAKE 3: TTL dedup (noteIdx + attackId) ═══
    // source: mic_engine.dart:639-687 _wfDedupAllow()
    if (inputs.wfDedupLastEmitMs != null) {
      final msSinceEmit = inputs.nowMs - inputs.wfDedupLastEmitMs!;
      if (msSinceEmit < ttlDedupMs) {
        if (kDebugMode) {
          debugPrint(
            'S42_DEDUP_SKIP key=${inputs.noteIdx}_${inputs.attackId} '
            'msSinceEmit=${msSinceEmit.toStringAsFixed(0)} '
            'ttl=$ttlDedupMs',
          );
        }
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'gated_ttl_dedup',
          gatedBy: 'ttl_dedup',
        );
      }
    }

    // ═══ BRAKE 4: Lookahead (only for WRONG candidates, not HIT) ═══
    // source: mic_engine.dart:698-740 _isLookaheadMatch()
    if (inputs.isLookaheadMatch) {
      if (kDebugMode) {
        debugPrint(
          'S44_LOOKAHEAD_BLOCK noteIdx=${inputs.noteIdx} '
          'midi=$detectedMidi',
        );
      }
      return output.copyWith(
        result: DecisionResult.skip,
        reason: 'gated_lookahead',
        gatedBy: 'lookahead',
      );
    }

    // ═══ BRAKE 5: Global cooldown ═══
    // source: mic_engine.dart:2480-2483 _lastWrongFlashAt
    if (inputs.lastWrongFlashAtMs != null) {
      final msSinceLast = inputs.nowMs - inputs.lastWrongFlashAtMs!;
      if (msSinceLast < globalCooldownMs) {
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'gated_cooldown',
          gatedBy: 'cooldown',
        );
      }
    }

    // ═══ BRAKE 6: Per-midi dedup ═══
    // source: mic_engine.dart:2484-2488 _lastWrongFlashByMidi[midi]
    if (inputs.lastWrongFlashForMidiMs != null) {
      final msSinceLast = inputs.nowMs - inputs.lastWrongFlashForMidiMs!;
      if (msSinceLast < perMidiDedupMs) {
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'gated_per_midi',
          gatedBy: 'per_midi',
        );
      }
    }

    // ═══ BRAKE 7: Triple dedup ═══
    // source: mic_engine.dart:2503-2507 _wrongFlashTripleDedupHistory[tripleKey]
    if (inputs.lastTripleFlashMs != null) {
      final msSinceLast = inputs.nowMs - inputs.lastTripleFlashMs!;
      if (msSinceLast < tripleDedupMs) {
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'gated_triple_dedup',
          gatedBy: 'triple_dedup',
        );
      }
    }

    // ═══ BRAKE 8: Sustain suppression (tail-aware) ═══
    // source: mic_engine.dart:2606-2620 _recentlyHitPitchClasses[detectedPC]
    if (inputs.recentHitForDetectedPCMs != null) {
      final msSinceHit = inputs.nowMs - inputs.recentHitForDetectedPCMs!;
      final threshold = inputs.bestEvent?.source == PitchSourceType.probe
          ? sustainProbeMs
          : sustainTriggerMs;
      if (msSinceHit < threshold) {
        if (kDebugMode) {
          debugPrint(
            'SUSTAIN_SUPPRESS_WRONG midi=$detectedMidi pc=$detectedPC '
            'msSinceHit=${msSinceHit.toStringAsFixed(0)} '
            'threshold=$threshold noteIdx=${inputs.noteIdx}',
          );
        }
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'gated_sustain',
          gatedBy: 'sustain',
        );
      }
    }

    // ═══ PATH-SPECIFIC BRAKES ═══

    // --- OCTAVE ERROR: requires confirmation >= 2 to promote ---
    if (output.reason == 'octave_error_candidate') {
      if (inputs.confirmationCount < octaveConfirmRequired) {
        // Not enough confirmations, stay AMBIGUOUS (don't emit)
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'octave_awaiting_confirm',
          gatedBy: 'confirm_count',
        );
      }
      // Confirmed octave error -> promote to WRONG
      return output.copyWith(
        result: DecisionResult.wrong,
        reason: 'octave_error',
        path: 'P6_OCTAVE_ERROR_CONFIRMED',
      );
    }

    // --- PC MISMATCH: promote to WRONG if brakes passed ---
    if (output.reason == 'pc_mismatch_candidate') {
      return output.copyWith(
        result: DecisionResult.wrong,
        reason: 'pc_mismatch',
        path: 'P7_PC_MISMATCH_CONFIRMED',
      );
    }

    // --- NO EVENTS FALLBACK: check grace (+ clearPitchAge for logging only) ---
    if (output.reason == 'no_events_fallback_candidate') {
      // BRAKE: Grace period
      // source: mic_engine.dart:2490-2501 timeSinceWindowStartMs < kFallbackGracePeriodMs
      if (inputs.isWithinGracePeriod) {
        return output.copyWith(
          result: DecisionResult.skip,
          reason: 'gated_grace_period',
          gatedBy: 'grace_period',
        );
      }

      // NOTE: clearPitchRecentMs gate not implemented here.
      // clearPitchAgeMs is kept in DECIDE_IN/OUT logs for diagnostic only.

      // Promote to WRONG (same as legacy behavior)
      return output.copyWith(
        result: DecisionResult.wrong,
        reason: 'no_events_fallback',
        path: 'P8_NO_EVENTS_FALLBACK_CONFIRMED',
      );
    }

    // Default: return as-is (AMBIGUOUS stays AMBIGUOUS)
    return output;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FULL PIPELINE - decide + postBrakes + stats
  // ═══════════════════════════════════════════════════════════════════════

  DecisionOutput process(DecisionInputs inputs) {
    final rawOutput = decide(inputs);
    final finalOutput = postBrakes(rawOutput, inputs);

    // Record stats
    stats.recordDecision(finalOutput);

    // Log DECIDE_OUT
    if (kDebugMode) {
      debugPrint(finalOutput.toLogString(inputs.noteIdx));
    }

    return finalOutput;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SESSION-073 (Deep Research): FREEPLAY MODE - No expected notes active
  // "When expected list is empty, arbiter should still classify as
  // WRONG_FREEPLAY and flash the detected key."
  // ═══════════════════════════════════════════════════════════════════════

  /// Process a detection when NO expected notes are active (freeplay/silence mode).
  /// This implements the Deep Research recommendation to not gate event generation
  /// on expected-notes routing windows.
  DecisionOutput processFreeplay({
    required ArbiterPitchEvent event,
    required double nowMs,
    required double wrongFlashMinConf,
    required double? lastWrongFlashAtMs,
    required double? lastWrongFlashForMidiMs,
    required bool wrongFlashEmittedThisTick,
    int plausibleMinMidi = 21, // Piano low A
    int plausibleMaxMidi = 108, // Piano high C
  }) {
    if (kDebugMode) {
      debugPrint(
        'DECIDE_FREEPLAY_IN midi=${event.midi} conf=${event.conf.toStringAsFixed(2)} '
        'source=${event.source.name} nowMs=${nowMs.toStringAsFixed(0)}',
      );
    }

    // ═══ F1: Range filter - must be in plausible keyboard range ═══
    if (event.midi < plausibleMinMidi || event.midi > plausibleMaxMidi) {
      final output = DecisionOutput(
        result: DecisionResult.skip,
        reason: 'freeplay_out_of_range',
        path: 'F1_RANGE_FILTER',
        detectedMidi: event.midi,
        gatedBy: 'range',
      );
      stats.recordDecision(output);
      return output;
    }

    // ═══ F2: Confidence filter ═══
    if (event.conf < wrongFlashMinConf) {
      final output = DecisionOutput(
        result: DecisionResult.skip,
        reason: 'freeplay_low_conf',
        path: 'F2_CONF_FILTER',
        detectedMidi: event.midi,
        confidence: event.conf,
        gatedBy: 'confidence',
      );
      stats.recordDecision(output);
      return output;
    }

    // ═══ F3: Per-tick flag (only one wrong per tick) ═══
    if (wrongFlashEmittedThisTick) {
      final output = DecisionOutput(
        result: DecisionResult.skip,
        reason: 'freeplay_already_emitted_tick',
        path: 'F3_PER_TICK',
        detectedMidi: event.midi,
        gatedBy: 'per_tick',
      );
      stats.recordDecision(output);
      return output;
    }

    // ═══ F4: Global cooldown ═══
    if (lastWrongFlashAtMs != null) {
      final msSinceLast = nowMs - lastWrongFlashAtMs;
      if (msSinceLast < globalCooldownMs) {
        final output = DecisionOutput(
          result: DecisionResult.skip,
          reason: 'freeplay_global_cooldown',
          path: 'F4_GLOBAL_COOLDOWN',
          detectedMidi: event.midi,
          gatedBy: 'cooldown',
        );
        stats.recordDecision(output);
        return output;
      }
    }

    // ═══ F5: Per-midi dedup ═══
    if (lastWrongFlashForMidiMs != null) {
      final msSinceLast = nowMs - lastWrongFlashForMidiMs;
      if (msSinceLast < perMidiDedupMs) {
        final output = DecisionOutput(
          result: DecisionResult.skip,
          reason: 'freeplay_per_midi_dedup',
          path: 'F5_PER_MIDI_DEDUP',
          detectedMidi: event.midi,
          gatedBy: 'per_midi',
        );
        stats.recordDecision(output);
        return output;
      }
    }

    // ═══ All gates passed → WRONG_FREEPLAY ═══
    final output = DecisionOutput(
      result: DecisionResult.wrongFreeplay,
      reason: 'freeplay_detected',
      path: 'FREEPLAY_CONFIRMED',
      detectedMidi: event.midi,
      confidence: event.conf,
    );

    if (kDebugMode) {
      debugPrint(
        'DECIDE_FREEPLAY_OUT result=${output.result.name} '
        'midi=${event.midi} conf=${event.conf.toStringAsFixed(2)}',
      );
    }

    stats.recordDecision(output);
    return output;
  }

  /// Get summary string for session end
  String getSummary() {
    return stats.toSummaryString();
  }
}
