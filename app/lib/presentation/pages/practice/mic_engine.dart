import 'dart:math';
import 'package:flutter/foundation.dart';

import 'package:shazapiano/core/practice/pitch/practice_pitch_router.dart';
import 'package:shazapiano/core/practice/pitch/decision_arbiter.dart';

// ============================================================================
// PATCH LEDGER - SESSION-035 (2026-01-26) - FALSE RED AFTER HIT FIX
// ============================================================================
// BUG: False red flash appears immediately after correct HIT
//   PREUVE: session-035 elapsed=7.317:
//           - HIT_DECISION noteIdx=5 midi=61 result=HIT
//           - WRONG_FLASH_EMIT noteIdx=6 expected=60 detected=61 ← FALSE RED!
//           - Frame 245-247: Red flash visible on keyboard during correct play
//
// ROOT CAUSE IDENTIFIED:
//   In NO_EVENTS_FALLBACK path (line ~2042), the sustain skip condition was:
//     if (!sample.isTriggerOrFailsafe && msSinceHit < 350) continue;
//   When isTriggerOrFailsafe=true, samples bypassed the msSinceHit<350 gate
//   even when msSinceHit=0ms (HIT just happened in same tick).
//   This caused the pitch event that validated noteIdx=5 to also trigger
//   WRONG_FLASH for noteIdx=6 which expected a different pitch.
//
// CORRECTION:
//   Add hard gate: ALWAYS skip if msSinceHit < 10ms (same tick)
//   New condition: if (msSinceHit < 10 || (!isTriggerOrFailsafe && msSinceHit < 350))
//   This ensures pitch events consumed by HIT are never reused for WRONG_FLASH.
//
// VALIDATION CRITERIA:
//   1. Play sequence: HIT noteIdx=N, then immediately noteIdx=N+1 with different pitch
//   2. No WRONG_FLASH should be emitted with detectedMidi matching the HIT pitch
//   3. Red flash should NOT appear when playing correct notes
//
// TEST: Replay session-035 sequence (C# spam then correct notes)
// ============================================================================
// ============================================================================
// PATCH LEDGER - SESSION-032 (2026-01-26) - WRONG FLASH FUNCTIONAL FIX
// ============================================================================
// BUG: session-032 video shows NO red flash at session start despite
//      WRONG_FLASH_EMIT/NO_EVENTS_FALLBACK_USED logged in MicEngine.
//   PREUVE: frame 88-90 (elapsed~1.6s) keyboard plain, no red on C5
//           logcat 3558: NO_EVENTS_FALLBACK_USED noteIdx=1 flashedMidi=72
//           No SESSION4_SKIP logs = decision reached UI but was silently dropped
//
// ROOT CAUSE IDENTIFIED:
//   In practice_notes_logic.part.dart, _registerWrongHit() was INSIDE guard:
//     if (_useNewScoringSystem && _newController != null && decision.detectedMidi != null)
//   At session start, while _useNewScoringSystem=true and _newController was init'd,
//   the guard structure caused wrongFlash to be processed but NOT trigger red flash
//   if any sub-condition failed or if early break occurred before _registerWrongHit.
//
// CORRECTION:
//   A) UI FIX: Move _registerWrongHit() OUTSIDE scoring system guard
//      - Red flash now triggers for ANY wrongFlash decision with valid detectedMidi
//      - Sustain/anti-spam checks still apply (prevent false flashes)
//      - Scoring controller send remains inside guard (optional feature)
//   B) TRACEABILITY: Add logs at each pipeline stage
//      - MicEngine: WRONG_FLASH_EMIT ... trigger=NO_EVENTS_FALLBACK
//      - UI: WRONGFLASH_UI_RECEIVED midi=X hasController=Y useNew=Z
//      - UI: WRONGFLASH_UI_TRIGGERED midi=X elapsed=Yms
//      - UI: WRONGFLASH_REGISTER_BLOCKED midi=X reason=tooSoon_sameMidi
//
// VALIDATION CRITERIA:
//   1. At session start, play wrong note → red flash visible
//   2. Logcat shows: WRONG_FLASH_EMIT → WRONGFLASH_UI_RECEIVED → UI_TRIGGERED
//   3. No cooldownOk=false on FIRST wrong flash attempt
//
// TEST: session-033 - verify red flash at elapsed<2s when playing wrong note
// ============================================================================
// PATCH LEDGER - SESSION-031 (2026-01-26) - WRONG FLASH RESTORATION
// ============================================================================
// BUG A: "ALLOW puis SKIP" - Multiple wrong flash paths check/update same
//        cooldown state, causing confusing ALLOW→SKIP logs without emission.
//   PREUVE: session-031 logcat shows:
//           - WRONG_FLASH ... cooldownOk=true ... trigger=HIT_DECISION_REJECT_MISMATCH
//           - WRONG_FLASH_ALLOW reason=highConfAttack midi=71
//           - WRONG_FLASH_SKIP reason=gated ... globalCooldownOk=false perMidiDedupOk=false
//   CAUSE: First path emits and updates _lastWrongFlashAt, second path checks
//          and finds cooldown consumed → logs SKIP (but decision already added)
//
// BUG B: "no_events_in_buffer" - When main buffer empty, no wrong flash emitted
//        even though audio detects wrong notes (PROBE/failsafe).
//   PREUVE: session-031 noteIdx=7 expectedMidi=60:
//           - HIT_DECISION REJECT reason=no_events_in_buffer (repeated)
//           - Audio continues detecting but buffer empty → no red flash
//
// CORRECTION:
//   A) Per-tick flag: _wrongFlashEmittedThisTick reset at start of _matchNotes
//      - All paths check flag before emitting, set flag when emitting
//      - WRONG_FLASH_ALLOW only logged if flag not set (cleaner logs)
//      - Log: WRONG_FLASH_EMIT (unified, replaces old WRONG_FLASH log)
//   B) Fallback ring buffer: _recentWrongSamples captures ALL high-conf detections
//      - Added BEFORE NoteTracker gate (includes suppressed events)
//      - On no_events_in_buffer REJECT, check buffer for wrong midi
//      - Emit wrong flash if: conf >= 0.95, midi != expected, has energy
//      - Log: NO_EVENTS_FALLBACK_USED noteIdx expectedMidi flashedMidi sampleAgeMs
//
// GARDE-FOUS: Sustain protection for fallback (avoid false red):
//   - Skip if midi pitchClass was recently hit AND not trigger/failsafe
//   - Skip if midi matches expected pitch class (octave of correct note)
//   - Require energy signal (rms >= 0.08 OR dRms >= 0.015 OR isTriggerOrFailsafe)
//
// TEST: session-032 - At least 1 WRONG_FLASH_EMIT when wrong note played
// ============================================================================
// PATCH LEDGER - SESSION-030 (2026-01-25) - HIT_ROBUST STRICT GARDE-FOUS
// ============================================================================
// CAUSE: False "white" (MISS) when user replays a note but events are suppressed
//   PREUVE: session-030 noteIdx=6 expectedMidi=60, window=[5.950..7.900]
//           - 7276ms: ONSET_TRIGGER (ratio=3.05) → user replays C4
//           - 7361ms: NOTE_SUPPRESS reason=cooldown (85ms < 160ms)
//           - 7541ms: NOTE_SUPPRESS reason=tail_falling (dRms=-0.04)
//           - 7926ms: HIT_DECISION MISS timeout_no_match ← buffer empty!
//
// CORRECTION v2 (STRICT GARDE-FOUS - avoid false greens):
//   A) cooldownOnly: ONLY accept reason=cooldown (NOT tail_falling)
//      → tail_falling = resonance, cooldown = real replay too fast
//   B) exactMidiMatch: candidate.midi == expectedMidi (NOT just pitchClass)
//      → avoid octave confusion C3≠C4
//   C) onsetLink: dtFromOnset <= 250ms (linked to real ONSET_TRIGGER)
//      → proves candidate follows real user attack
//   D) energySignal: rms >= 0.08 OR dRms >= 0.015
//      → proves candidate has real energy, not just resonance
//   E) edgeTolerance: 50ms max outside window
//      → tight tolerance for fallback matching
//   F) cleanup: TTL <= 1000ms, cap <= 64, clear on reset/pointer advance
//      → prevent stale candidates from causing delayed false greens
//
// IMPLEMENTATION:
//   - HitCandidate class: {midi, tMs, rms, conf, source, suppressReason, dtFromOnsetMs, dRms}
//   - _lastOnsetTriggerMsByPc[pitchClass] = elapsedMs on each ONSET_TRIGGER
//   - Candidate added ONLY IF: cooldownOnly ∧ exactMidiMatch ∧ onsetLink ∧ energySignal
//   - Fallback in _matchNotes: exact midi + edge tolerance + closest dtFromOnset
//   - Logs: HIT_CANDIDATE_ADD (accept/reject), HIT_CANDIDATE_MATCH (fallback)
//
// TEST: session-031 - noteIdx=6 should HIT via HIT_CANDIDATE_MATCH
//   Validation logs: HIT_CANDIDATE_ADD accept=true reason=cooldown dtFromOnset=85ms
// ============================================================================
// PATCH LEDGER - SESSION-029 (2026-01-25) - TAIL-AWARE SUSTAIN SUPPRESSION
// ============================================================================
// CAUSE: Fixed 500ms window too short for long piano sustain, but too long might
//   mask real errors when user intentionally plays wrong note shortly after HIT.
//   PREUVE: session-029 logcat shows SUPPRESS up to 459ms, then WRONG at 543ms
//   The first WRONG at 543ms is likely still sustain, but later ones are real errors.
// CORRECTION: Tail-aware suppression based on event source:
//   - TRIGGER events (new attacks): use short window (350ms) to catch real errors
//   - PROBE events (sustain/tail): use long window (600ms) for piano resonance
//   - New constants: kSustainWrongSuppressTriggerMs=350, kSustainWrongSuppressProbeMs=600
//   - Log now includes: source=trigger/probe thresholdMs=350/600
// RISQUE: Minimal - probes are inherently low-energy sustain detections
//   - Real new attacks produce TRIGGER events which have shorter window
// TEST: session-030 - expect more SUPPRESS for probe, fewer false WRONG
// ============================================================================
// PATCH LEDGER - SESSION-028 (2026-01-24) - PRE-EMISSION SUSTAIN WRONG SUPPRESS
// ============================================================================
// CAUSE: False WRONG_FLASH (red) emitted after HIT due to sustain/tail re-detection
//   PREUVE: logcat session-028 at 18:25:01.739-740:
//           - HIT_DECISION noteIdx=3 detectedMidi=61 result=HIT
//           - WRONG_FLASH noteIdx=4 expectedMidi=63 detectedMidi=61 ← FALSE RED!
//           - SESSION4_SKIP_SUSTAIN_WRONG: Skip midi=61 dt=88ms ← SKIP TOO LATE!
//   The WRONG_FLASH is emitted BEFORE the UI-layer skip logic runs.
// CORRECTION: Add GATE 4 (sustainSuppressOk) BEFORE emitting WRONG_FLASH
//   - Check if detectedPC has recent HIT in _recentlyHitPitchClasses
//   - (SESSION-029: now uses tail-aware thresholds instead of fixed 500ms)
// ============================================================================
// PATCH LEDGER - SESSION-027 (2026-01-24) - STABILITY BYPASS FOR TRIGGER FIX
// ============================================================================
// CAUSE: First-time pitch class detections blocked by stability filter
//   PREUVE: logcat session-027 at 16:48:14.752:
//           - ONSET_TRIGGER t=9091ms ratio=4.67 cooldownOk=true
//           - YIN_CALLED expected=[70] detectedMidi=70 conf=1.00
//           - PITCH_ROUTER expected=[70] events=1 t=9.091
//           - (NO NOTE_START midi=70) ← BLOCKED by stability=1 < required=2
//           - BUFFER_STATE totalEvents=0 eventsInWindow=0
//           - HIT_DECISION noteIdx=7 result=REJECT reason=no_events_in_buffer
//           - HIT_DECISION noteIdx=7 result=MISS reason=timeout_no_match
// CORRECTION: Bypass stability filter for ONSET_TRIGGER events (line ~805)
//   - isTriggerEvent = onsetState == OnsetState.trigger
//   - if (!isTriggerEvent && stabilityFrames < kPitchStabilityMinFrames) skip
//   - ONSET_TRIGGER already gated by ratio>1.4 + cooldown, doesn't need
//     multi-frame stability confirmation. Only BURST/PROBE need filter.
// RISQUE: Minimal - TRIGGER events are high-confidence attacks by definition
//   - ratio check (>1.4) ensures strong signal delta
//   - cooldown check prevents double-trigger
//   - YIN conf check (>=0.75) filters noise
// TEST: session-028 - last note (noteIdx=7, midi=70) should produce:
//   - STABILITY_BYPASS_TRIGGER midi=70 pc=10 frames=1 ...
//   - NOTE_START midi=70 pc=10 t=~9000ms ...
//   - HIT_DECISION noteIdx=7 result=HIT
// ============================================================================
// PATCH LEDGER - SESSION-025 (2026-01-24) - WRONG FLASH UI GATE FIX
// ============================================================================
// CAUSE: _registerWrongHit gate uses _successFlashDuration (200ms) not aligned
//   PREUVE: logcat session-025 WRONG_FLASH EMIT intervals: 161ms, 186ms, 180ms...
//           ~50% < 200ms → silently blocked by _registerWrongHit
// CORRECTION: New _wrongFlashGateDuration=150ms (practice_page.dart)
//             Used in _registerWrongHit instead of _successFlashDuration
// TEST: Spam C5 should flash at ~150ms intervals consistently
// ============================================================================
// PATCH LEDGER - SESSION-024 (2026-01-23) - WRONG FLASH DEDUP FIX
// ============================================================================
// CAUSE: wrongFlashDedupMs=400 + _antiSpamWrongMs=500 too aggressive
//   PREUVE: logcat session-024 "perMidiDedupOk=false" blocking ~80% of flashes
// CORRECTION: wrongFlashDedupMs 400→150ms, _antiSpamWrongMs 500→150ms
// TEST: Spam C5 should trigger flash every ~150ms, not ~450ms
// ============================================================================
// PATCH LEDGER - SESSION-023 (2026-01-23) - WRONG FLASH FIXES
// ============================================================================
// CAUSE #1: Wrong flashes dropped with minDelta=999 (no expected notes active)
//   PREUVE: logcat "WRONG_FLASH_DROP reason=outlier minDelta=999 threshold=12"
//   CORRECTION: Check activeExpectedMidis.isEmpty BEFORE outlier filter
//               New log: WRONG_FLASH_SKIP reason=no_expected_active
//   RISQUE: None - just clearer logging, no behavior change
//   TEST: Observe WRONG_FLASH_SKIP instead of DROP for empty windows
//
// CAUSE #2: Octave errors (same pitch class, wrong octave) produce no flash
//   PREUVE: logcat "distance_too_large=12.0_threshold=3.0" with F5 vs F4 expected
//           User plays correct pitch class but wrong octave = silent rejection
//   CORRECTION: Emit WRONG_FLASH on distance_too_large WHEN pitchClass matches
//               New log: WRONG_FLASH trigger=OCTAVE_ERROR octaveOffset=+/-N
//   RISQUE: More flashes for octave errors - desired behavior for beginners
//   TEST: Play F5 when F4 expected, verify red flash appears
//
// CAUSE #3: maxSemitoneDeltaForWrong=12 too strict for beginners
//   PREUVE: logcat "WRONG_FLASH_DROP reason=outlier minDelta=16 threshold=12"
//   CORRECTION: Increased to 24 (2 octaves) - SESSION-023 previous patch
//   RISQUE: May flash for harmonics 2 octaves away - mitigated by conf>=0.75
//   TEST: Octave errors now produce flash instead of silent drop
// ============================================================================
// PATCH LEDGER - SESSION-021 (2026-01-22) - REVISED
// ============================================================================
// CAUSE #1: Pitch drift +-1 semitone (D#4=63 detected as E4=64)
//   PREUVE: logcat L3647 "YIN_CALLED expected=[63] detectedMidi=64 freq=331.2"
//           331.2 Hz is E4 (329.63 Hz), but D#4 (311.13 Hz) was expected
//   CORRECTION: LOCAL conditional snap in _matchNotes() - see _shouldSnapToExpected()
//               If detected midi is within +-1 semitone of expected AND
//               conf >= minConfForPitch AND stability >= kPitchStabilityMinFrames,
//               treat as match. (NO modification to core/ files)
//   RISQUE: May accept adjacent wrong notes - mitigated by conf+stability gates
//   TEST: Play D#4 slowly, verify HIT instead of MISS
//
// CAUSE #2: Sustain pollution for long notes (C4 sustain blocks C#4 detection)
//   PREUVE: logcat L3850-3900 shows C4(60) sustain blocking C#4(61) detection
//           "pitch_class_mismatch_expected=1_detected=0" for 1.25s
//   CORRECTION: sustainFilterMs=800 (was 600) via kSustainFilterMsExtended
//   RISQUE: May delay detection of rapid repeated notes - acceptable for practice
//   TEST: Play long C#4 (1.25s), verify HIT instead of MISS
//
// CAUSE #3: Latency spike (485ms) skewing average
//   PREUVE: logcat L3828 "LATENCY_SAMPLE dtMs=485.0" skews EMA
//   CORRECTION: _isLatencySpike() rejects samples > 2x median
//   RISQUE: May reject legitimate high-latency samples on very slow devices
//   TEST: Observe LATENCY_SPIKE_REJECT logs, verify stable latencyCompMs
//
// CAUSE #4: No onset trigger for last note (only PROBE, RMS too low)
//   PREUVE: logcat L3957 "result=MISS reason=timeout_no_match" for A#4@8.75s
//   CORRECTION: Not addressed (requires onset detector tuning)
//   TEST: N/A for this patch
//
// B.2) Sample-rate mismatch: CONFIRMED NOT A CAUSE
//   PREUVE: logcat "detected=32000, forced=YES, semitoneShift=-5.55" BUT
//           pitch detection is CORRECT for most notes. -5.55 would cause
//           systematic errors, not sporadic +-1. Root cause is harmonics.
// ============================================================================
import 'package:shazapiano/core/practice/pitch/onset_detector.dart';
import 'package:shazapiano/core/practice/pitch/note_tracker.dart';
import 'package:shazapiano/core/practice/pitch/mic_tuning.dart';

// SESSION-036: Re-export OnsetState for use with 'mic' prefix in practice_page.dart
export 'package:shazapiano/core/practice/pitch/onset_detector.dart'
    show OnsetState;

/// Feature flag: Enable hybrid YIN/Goertzel detection.
/// - OFF: Use existing MPM path.
/// - ON (default): Use YIN for mono notes, Goertzel for chords.
const bool kUseHybridDetector = true;

/// SESSION-019 FIX: Refresh UI during sustained notes.
/// When true, _uiMidi is updated even when NoteTracker blocks emission (held state).
/// This prevents the keyboard from going black while holding a note.
/// Set to false to rollback if this causes issues.
const bool kRefreshUiDuringSustain = true;

// ============================================================================
// SESSION-021 PATCH FLAGS
// ============================================================================
/// SESSION-021 FIX #1: Allow +-1 semitone snap in YIN mono detection.
/// When true, if YIN detects a pitch within 1 semitone of expected, snap to expected.
/// This fixes the D#4(63) detected as E4(64) issue caused by pitch drift.
/// Set to false to rollback to strict mode (no tolerance).
const bool kYinSnapTolerance1Semitone = true;

/// SESSION-021 FIX #2: Extended sustain filter for long notes.
/// When true, uses 800ms instead of 600ms for sustainFilterMs.
/// This prevents sustain of previous note from polluting buffer during long holds.
const int kSustainFilterMsExtended = 800;

/// SESSION-028 FIX: Suppress WRONG_FLASH for recent HIT sustain.
/// When a note is hit, its sustain/tail may be re-detected while the NEXT
/// expected note is active, causing a false WRONG_FLASH.
///
/// SESSION-029 FIX: Tail-aware suppression - different windows based on source:
/// - TRIGGER events (new attacks) use shorter window to not mask real errors
/// - PROBE events (sustain/tail) use longer window for piano resonance
const int kSustainWrongSuppressTriggerMs = 350; // New attack - short window
const int kSustainWrongSuppressProbeMs = 600; // Sustain/tail - long window

/// SESSION-030 FIX: HIT_ROBUST - Dual-path suppression for HIT matching.
/// Fixes "false white" (MISS despite real hit) when NoteTracker suppresses
/// valid events due to cooldown.
///
/// PREUVE: session-030 noteIdx=6 expectedMidi=60:
/// - 7276ms: ONSET_TRIGGER (user replays C4)
/// - 7361ms: NOTE_SUPPRESS reason=cooldown (85ms < 160ms)
/// - 7926ms: HIT_DECISION MISS timeout_no_match (buffer empty!)
///
/// FIX: Store suppressed cooldown events as HitCandidates for fallback matching.
///
/// STRICT GARDE-FOUS (anti faux-verts):
/// A) cooldownOnly: ONLY accept reason=cooldown (not tail_falling)
/// B) exactMidiMatch: candidate.midi == expectedMidi (not just pitchClass)
/// C) onsetLink: (tCandidate - lastOnsetTriggerMs) <= kHitOnsetLinkMs
/// D) energySignal: rms >= kHitCandidateRmsMin OR dRms >= kHitCandidateDRmsMin
/// E) edgeTolerance: accept within window ± kHitEdgeToleranceMs
/// F) cleanup: TTL <= 1000ms, cap <= 64, clear on reset/pointer advance
const bool kHitRobustEnabled = true;

/// Maximum time (ms) between ONSET_TRIGGER and candidate to accept it.
/// Ensures candidate is linked to a real attack, not resonance.
const int kHitOnsetLinkMs = 250;

/// Minimum RMS for a candidate to be considered a real attack.
const double kHitCandidateRmsMin = 0.08;

/// Minimum dRms for a candidate (alternative to rms check).
const double kHitCandidateDRmsMin = 0.015;

/// Edge tolerance (ms) for hit candidates at window boundaries.
const int kHitEdgeToleranceMs = 50;

/// Maximum age (ms) for a candidate before it's pruned.
const int kHitCandidateTtlMs = 1000;

/// Maximum number of candidates to keep (cap to prevent memory issues).
const int kHitCandidateMaxCount = 64;

/// SESSION-031 FIX: Wrong flash restoration + no_events_in_buffer fallback.
///
/// BUG A: ALLOW→SKIP pattern - multiple paths check/update same cooldown,
///        causing confusing logs and blocking emissions.
/// BUG B: no_events_in_buffer - when _events buffer is empty, no wrong flash
///        even though audio continues detecting wrong notes.
///
/// FIX A: Use _wrongFlashEmittedThisTick flag to prevent duplicate emissions
///        in same _matchNotes call. State only updates on actual emit.
/// FIX B: Use _recentWrongSamples ring buffer to detect wrong notes even
///        when main buffer is empty (fallback for probe/failsafe detections).
const bool kWrongFlashRestoreEnabled = true;

/// SESSION-047: Arbiter shadow mode - runs DecisionArbiter in parallel for validation
/// When true, logs ARBITER_SHADOW_MATCH/MISMATCH without affecting legacy behavior
const bool kArbiterShadowEnabled = true;

/// Maximum age (ms) for a wrong sample to be considered for fallback.
const int kWrongSampleMaxAgeMs = 200;

/// Maximum number of recent wrong samples to keep.
const int kWrongSampleMaxCount = 16;

/// Minimum confidence for a wrong sample fallback.
const double kWrongSampleMinConf = 0.95;

/// SESSION-038 FIX: Grace period before emitting fallback wrong flash.
/// SESSION-054 FIX: 400→150ms - too long was blocking early attacks
/// PREUVE: session-054 had 9 WRONG_FLASH_SKIP due to grace_period (only 3 emits!)
/// Human reaction ~150-250ms, so 150ms grace is sufficient.
const double kFallbackGracePeriodMs = 150.0;

/// SESSION-021 FIX #3: Enable spike clamp for latency estimation.
/// When true, rejects latency samples > 2x current median to filter spikes.
/// This prevents outliers like 485ms from skewing the average.
const bool kLatencySpikeClamp = true;
const double kLatencySpikeClampRatio = 2.0;

/// SESSION-040 FIX: Maximum allowed dt (ms) for a HIT to be valid.
/// Events with |dt| > this are rejected even if distance is OK.
/// CAUSE: session-040 HIT with dt=-443ms (way too early after latency comp).
/// 250ms = reasonable window for human reaction + latency compensation error.
const double kHitDtMaxMs = 250.0;

/// SESSION-021 FIX #4: Pitch stability frames required before emission.
/// Require N consecutive frames detecting the same pitchClass before emitting.
/// This filters single-frame pitch glitches and sub-harmonic flickers.
/// Set to 1 to disable (original behavior).
const int kPitchStabilityMinFrames = 2;

/// SESSION-021 DEBUG: Enable debug report logging.
/// Activated via --dart-define=PRACTICE_DEBUG=true
const bool kPracticeDebugEnabled = bool.fromEnvironment(
  'PRACTICE_DEBUG',
  defaultValue: false,
);

/// SESSION-019 FIX P2: Extend UI hold when no pitch detected but likely still sustaining.
/// When routerEvents is empty (RMS too low for pitch detection), extend _uiMidiSetAt
/// if we're within sustainExtendMs of the last valid pitch detection.
/// This prevents keyboard from going black during quiet sustain phases.
/// Set to false to rollback if this causes ghost highlights.
const bool kExtendUiDuringSilentSustain = true;
const int kSustainExtendWindowMs =
    400; // Max time to extend UI without new pitch (was 600, reduced)
const double kSustainExtendMinRms =
    0.025; // Min RMS to allow extension (presence gate)

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
    // SESSION-053: 150→65ms to allow flash on every real attack (covers fast trills)
    this.wrongFlashCooldownSec = 0.065,
    // SESSION-014: Per-midi dedup for WRONG_FLASH (prevents spam of same wrong note)
    // SESSION-024 FIX: 400→150ms to allow rapid re-attack feedback
    // SESSION-053: 150→65ms for real-time human feedback (trills up to 15/sec)
    this.wrongFlashDedupMs = 65.0,
    // SESSION-014: Max semitone distance for WRONG_FLASH (filters outliers like subharmonics)
    // If detected midi is > 24 semitones from ALL expected midis, ignore it
    // SESSION-023 FIX: Increased from 12 to 24 (2 octaves) to allow octave errors
    // common in beginners (e.g., playing F5 instead of F4 = delta 12)
    // Protection: high confidence (0.75) + confirmation still required
    this.maxSemitoneDeltaForWrong = 24,
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
    // SESSION-020 FIX BUG #3: Reduced from 2 to 1 for faster latency (<120ms target)
    // Anti-spam is still enforced by cooldown + dedup gates.
    this.wrongFlashConfirmCount = 1,
    this.wrongFlashConfirmWindowMs = 150.0,
    // SESSION-009: Sustain filter - ignore previous note's pitch for wrong detection
    double? sustainFilterMs,
    // SESSION-053: 200→150ms for more reactive UI (still > 50ms retinal persistence)
    this.uiHoldMs = 150,
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
    // SESSION-021 FIX #2: Use extended sustain filter (800ms) by default.
    // This prevents sustain of previous note from polluting buffer during long holds.
    // Evidence: session-021 shows C4(60) sustain blocking C#4(61) detection for 1.25s note.
  }) : tuning = tuning ?? MicTuning.forProfile(ReverbProfile.medium),
       sustainFilterMs =
           sustainFilterMs ??
           (tuning?.sustainFilterMs ?? kSustainFilterMsExtended.toDouble()),
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

  /// SESSION-047: Decision arbiter for unified HIT/WRONG/MISS logic (shadow mode)
  final DecisionArbiter _arbiter = DecisionArbiter();

  String? _sessionId;
  final List<PitchEvent> _events = [];

  /// SESSION-030: HitCandidates for dual-path HIT matching.
  /// Stores suppressed cooldown events that may still be valid for HIT detection.
  /// Strict garde-fous: cooldownOnly, exactMidi, onsetLink, energySignal.
  final List<HitCandidate> _hitCandidates = [];

  /// SESSION-030: Track last ONSET_TRIGGER timestamp per pitchClass (0-11).
  /// Used to verify candidates are linked to a real attack (dtFromOnset <= 250ms).
  final Map<int, double> _lastOnsetTriggerMsByPc = {};

  // SESSION-028: One-time flag to log patch confirmation at first session start
  static bool _patchConfirmLogged = false;
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

  // SESSION-031: Flag to prevent duplicate wrong flash emissions in same tick.
  // Reset at start of _matchNotes, set when any path emits.
  bool _wrongFlashEmittedThisTick = false;

  // SESSION-040: Per-(noteIdx, expectedMidi, detectedMidi) dedup to prevent multi-emit
  // when sources alternate (burst/trigger/probe). Key: "noteIdx_expected_detected"
  // TTL: 200ms - same triple can only emit once per window regardless of source.
  final Map<String, DateTime> _wrongFlashTripleDedupHistory = {};
  static const int _wrongFlashTripleDedupMs = 200;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-042: Centralized TTL-based dedup for wrong flash
  // INVARIANT: Max 1 WRONG_FLASH_EMIT per (noteIdx, attackId) within TTL window.
  // Cross-tick persistent: NOT cleared per tick, only purged when expired.
  // Key: "noteIdx_attackId" where attackId = _lastOnsetTriggerElapsedMs.round()
  // Value: nowMs (int) when last emitted
  // ══════════════════════════════════════════════════════════════════════════
  final Map<String, int> _wfDedupHistory = {}; // key -> lastEmitMs (int)
  static const int _wfDedupTtlMs = 1500; // TTL for dedup (int)

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-043: Block WRONG_FLASH for attackIds that produced a recent HIT
  // CAUSE: Same attackId can produce HIT for noteIdx=N then WRONG_FLASH for noteIdx=N+1
  //        because dedup key is "noteIdx_attackId" (different noteIdx = different key)
  // FIX: Track attackIds that produced HIT, block WRONG_FLASH for same attackId
  // INVARIANT: If attackId produced HIT within TTL, no WRONG_FLASH for that attackId
  // ══════════════════════════════════════════════════════════════════════════
  final Map<int, int> _hitAttackIdHistory = {}; // attackId -> hitMs (int)
  static const int _hitAttackIdTtlMs = 500; // TTL for HIT->WRONG block (int)

  /// SESSION-042: Centralized dedup helper for wrong-flash emission.
  /// Returns true if emission is ALLOWED, false if BLOCKED by TTL.
  /// If allowed, automatically records the emit time in history.
  /// If blocked, logs S42_DEDUP_SKIP or S43_HIT_BLOCK and caller must bail out.
  bool _wfDedupAllow({
    required int noteIdx,
    required int attackId,
    required int nowMs,
    required String path,
  }) {
    final key = '${noteIdx}_$attackId';

    // Purge old entries (> 2*TTL) to prevent unbounded growth
    if (_wfDedupHistory.length > 50) {
      _wfDedupHistory.removeWhere(
        (k, lastMs) => (nowMs - lastMs) > _wfDedupTtlMs * 2,
      );
    }

    // SESSION-043: Check if this attackId produced a recent HIT
    // CAUSE: Same attack can produce HIT for noteIdx=N, then WRONG for noteIdx=N+1
    // This is incoherent - if an attack produced a HIT, it shouldn't also produce WRONG
    final hitMs = _hitAttackIdHistory[attackId];
    if (hitMs != null) {
      final ageMs = nowMs - hitMs;
      if (ageMs < _hitAttackIdTtlMs) {
        // BLOCKED: this attackId produced a HIT recently
        if (kDebugMode) {
          debugPrint(
            'S43_HIT_BLOCK attackId=$attackId ageMs=$ageMs ttl=$_hitAttackIdTtlMs noteIdx=$noteIdx path=$path',
          );
        }
        return false;
      }
    }

    // Check if within TTL window (original S42 dedup)
    final lastEmitMs = _wfDedupHistory[key];
    if (lastEmitMs != null) {
      final ageMs = nowMs - lastEmitMs;
      if (ageMs < _wfDedupTtlMs) {
        // BLOCKED: within TTL
        if (kDebugMode) {
          debugPrint(
            'S42_DEDUP_SKIP key=$key ageMs=$ageMs ttl=$_wfDedupTtlMs path=$path',
          );
        }
        return false;
      }
    }

    // ALLOWED: record emit time
    _wfDedupHistory[key] = nowMs;
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-044: Lookahead check - block WRONG_FLASH if detected midi matches
  // a future note whose window overlaps with the current note.
  // CAUSE: User plays next note early → WRONG for current + HIT for next = confusing
  // FIX: If detectedMidi == expectedMidi of a future overlapping note, block WRONG
  // ══════════════════════════════════════════════════════════════════════════

  /// SESSION-044: Check if detected midi matches a future note with overlapping window.
  /// Returns true if WRONG_FLASH should be BLOCKED (lookahead match found).
  bool _isLookaheadMatch({
    required int detectedMidi,
    required int currentNoteIdx,
    required List<NoteEvent> noteEvents,
    required List<bool> hitNotes,
    required double elapsed,
    required double headWindowSec,
    required double tailWindowSec,
    required String path,
  }) {
    if (currentNoteIdx >= noteEvents.length) return false;

    final currentNote = noteEvents[currentNoteIdx];
    final currentWindowEnd = currentNote.end + tailWindowSec;

    // Check next few notes (limit to 3 to avoid over-reaching)
    final maxLookahead = (currentNoteIdx + 3).clamp(0, noteEvents.length);

    for (
      var futureIdx = currentNoteIdx + 1;
      futureIdx < maxLookahead;
      futureIdx++
    ) {
      if (hitNotes[futureIdx]) continue; // Already hit, skip

      final futureNote = noteEvents[futureIdx];
      final futureWindowStart = futureNote.start - headWindowSec;

      // Check: windows overlap AND midi matches exactly
      final hasOverlap = currentWindowEnd > futureWindowStart;
      final midiMatches = detectedMidi == futureNote.pitch;

      if (hasOverlap && midiMatches) {
        if (kDebugMode) {
          debugPrint(
            'S44_LOOKAHEAD_BLOCK noteIdx=$currentNoteIdx futureIdx=$futureIdx '
            'detectedMidi=$detectedMidi futureMidi=${futureNote.pitch} '
            'overlap=${(currentWindowEnd - futureWindowStart).toStringAsFixed(3)}s '
            'path=$path',
          );
        }
        return true; // BLOCK: midi matches future overlapping note
      }
    }

    return false; // No lookahead match, allow emission
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-038: WrongFlash Engine Counters (kDebugMode only)
  // Track where wrong flashes are emitted/skipped at MicEngine level
  // ══════════════════════════════════════════════════════════════════════════
  int _engineEmitCount = 0; // Total WRONG_FLASH_EMIT from MicEngine
  int _engineSkipGatedCount = 0; // Skipped due to cooldown gating
  int _engineSkipAlreadyEmittedTickCount =
      0; // Skipped due to already_emitted_this_tick
  int _engineSkipPerMidiDedupCount =
      0; // Skipped due to per-midi dedup (if applicable)
  int _engineSkipOtherCount =
      0; // Other skip reasons (low_conf, no_candidate, etc.)

  // SESSION-031: Ring buffer for recent pitch samples (fallback for no_events_in_buffer).
  // Stores all detections (including PROBE) for wrong flash when main buffer empty.
  final List<WrongSample> _recentWrongSamples = [];

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

  // ============================================================================
  // SESSION-021: Debug report (see practice_debug_report.dart for full impl)
  // ============================================================================
  /// SESSION-021: Counter for latency spikes (used by _isLatencySpike).
  int _debugLatencySpikeCount = 0;

  /// SESSION-021: Get basic debug stats as map.
  /// For full debug report, use PracticeDebugReport class.
  Map<String, dynamic> get debugStats => {
    'latencyCompMs': _latencyCompMs,
    'latencyMedianMs': _latencyMedianMs,
    'latencySamples': _latencySamples.length,
    'latencySpikeCount': _debugLatencySpikeCount,
    'timebase': 'DateTime.now() elapsed',
  };

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-038: WrongFlash Engine Telemetry API
  // ══════════════════════════════════════════════════════════════════════════
  int get engineEmitCount => _engineEmitCount;
  int get engineSkipGatedCount => _engineSkipGatedCount;
  int get engineSkipAlreadyEmittedTickCount =>
      _engineSkipAlreadyEmittedTickCount;
  int get engineSkipPerMidiDedupCount => _engineSkipPerMidiDedupCount;
  int get engineSkipOtherCount => _engineSkipOtherCount;

  /// Log WRONGFLASH_ENGINE_SUMMARY (call from UI layer at session end)
  void logEngineSummary() {
    if (!kDebugMode) return;
    debugPrint(
      'WRONGFLASH_ENGINE_SUMMARY sessionId=$_sessionId '
      'emits=$_engineEmitCount '
      'skipGated=$_engineSkipGatedCount '
      'skipTick=$_engineSkipAlreadyEmittedTickCount '
      'skipDedup=$_engineSkipPerMidiDedupCount '
      'skipOther=$_engineSkipOtherCount',
    );
  }

  // SESSION-016: Auto-baseline noise floor detection
  double _noiseFloorRms = 0.0; // Estimated noise floor during baseline
  double _dynamicOnsetMinRms = 0.0; // Dynamic onset threshold (after baseline)
  double _baselineStartMs = 0.0; // When baseline measurement started
  bool _baselineComplete = false; // Whether baseline measurement is done
  int _baselineSampleCount = 0; // Number of samples in baseline
  double _lastOnsetTriggerMs =
      -10000.0; // Last onset trigger time (for baseline guard)
  double _lastBaselineLogMs = -10000.0; // Rate limit baseline logs

  /// SESSION-016: Dynamic onset minimum RMS (after auto-baseline).
  double get dynamicOnsetMinRms => _dynamicOnsetMinRms;

  /// Whether noise baseline calibration is complete.
  bool get isBaselineComplete => _baselineComplete;

  /// Current noise floor RMS estimate.
  double get noiseFloorRms => _noiseFloorRms;

  // ══════════════════════════════════════════════════════════════════════════
  // COUNTDOWN CALIBRATION: Noise floor measurement during Play→Notes delay
  // ══════════════════════════════════════════════════════════════════════════

  /// Ingest audio samples during countdown for noise floor calibration.
  ///
  /// This method is called during the countdown phase (before notes start falling)
  /// to measure the room's ambient noise level. Unlike [onAudioChunk], this:
  /// - Does NOT perform pitch detection
  /// - Does NOT update scoring state
  /// - ONLY measures RMS and updates noise baseline
  ///
  /// Call this during the 2-3 second countdown delay to calibrate microphone
  /// sensitivity to the user's environment.
  void ingestCountdownSamples(List<double> samples) {
    if (samples.isEmpty) return;
    if (_baselineComplete) return; // Already calibrated

    // Compute RMS
    final rms = _computeRms(samples);
    _lastRms = rms;

    // During countdown, we assume the environment is "silent" (user not playing)
    // So we can directly update the noise floor without onset guards
    // Use a higher silence threshold since this is explicitly a calibration phase
    const double countdownSilenceMaxRms = 0.02; // Max RMS to consider "silent"

    if (rms < countdownSilenceMaxRms && rms > 0.0001) {
      // Update noise floor with EMA
      _baselineSampleCount++;
      if (_baselineSampleCount == 1) {
        _noiseFloorRms = rms;
      } else {
        // Slow EMA (alpha=0.1) for stable noise floor estimation
        _noiseFloorRms = _noiseFloorRms * 0.9 + rms * 0.1;
      }

      if (kDebugMode && _baselineSampleCount % 20 == 0) {
        debugPrint(
          'COUNTDOWN_NOISE_BASELINE floor=${_noiseFloorRms.toStringAsFixed(5)} '
          'rms=${rms.toStringAsFixed(5)} samples=$_baselineSampleCount',
        );
      }
    }
  }

  /// Finalize the noise baseline after countdown completes.
  ///
  /// Call this when countdown ends and notes are about to start falling.
  /// This computes the dynamic onset threshold from the measured noise floor.
  void finalizeCountdownBaseline() {
    if (_baselineComplete) return; // Already finalized

    _baselineComplete = true;

    if (_baselineSampleCount > 0) {
      // Compute dynamic threshold from measured noise floor
      _dynamicOnsetMinRms =
          (_noiseFloorRms * tuning.noiseFloorMultiplier +
                  tuning.noiseFloorMargin)
              .clamp(tuning.onsetMinRms, tuning.onsetMinRms * 5);

      // SESSION-052: Pass noise floor to router for YIN override guard
      _router.noiseFloorRms = _noiseFloorRms;

      if (kDebugMode) {
        debugPrint(
          'COUNTDOWN_BASELINE_FINALIZED floor=${_noiseFloorRms.toStringAsFixed(5)} '
          'dynamicOnsetMinRms=${_dynamicOnsetMinRms.toStringAsFixed(5)} '
          'samples=$_baselineSampleCount routerNoiseFloor=${_noiseFloorRms.toStringAsFixed(5)}',
        );
      }
    } else {
      // No samples collected, use preset threshold
      _dynamicOnsetMinRms = tuning.onsetMinRms;

      if (kDebugMode) {
        debugPrint(
          'COUNTDOWN_BASELINE_FINALIZED no_samples, using preset '
          'dynamicOnsetMinRms=${_dynamicOnsetMinRms.toStringAsFixed(5)}',
        );
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-036: Onset state exposure for anticipated flash (zero-lag feel)
  // ══════════════════════════════════════════════════════════════════════════
  OnsetState _lastOnsetState = OnsetState.skip;
  double _lastOnsetTriggerElapsedMs = -10000.0;
  int? _onsetActiveNoteIdx;
  int? _onsetExpectedMidi;
  bool _onsetInActiveWindow = false;
  double _onsetRmsRatio = 0.0;
  double _onsetDRms = 0.0;

  /// SESSION-036: Last onset state from OnsetDetector.
  OnsetState get lastOnsetState => _lastOnsetState;

  /// SESSION-036: ElapsedMs when last ONSET_TRIGGER fired.
  double get lastOnsetTriggerElapsedMs => _lastOnsetTriggerElapsedMs;

  /// SESSION-036: Active note index at time of onset (if in window).
  int? get onsetActiveNoteIdx => _onsetActiveNoteIdx;

  /// SESSION-036: Expected MIDI at time of onset (if in window).
  int? get onsetExpectedMidi => _onsetExpectedMidi;

  /// SESSION-036: Whether onset occurred within an active HIT window.
  bool get onsetInActiveWindow => _onsetInActiveWindow;

  /// SESSION-036: RMS ratio at onset (for debugging).
  double get onsetRmsRatio => _onsetRmsRatio;

  /// SESSION-036: Delta RMS at onset (for debugging).
  double get onsetDRms => _onsetDRms;

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-036c: Last detected pitch exposure for "REAL-TIME FEEL" keyboard
  // This allows UI to show what the mic actually hears (independent of scoring)
  // ══════════════════════════════════════════════════════════════════════════
  int? _lastDetectedMidi;
  double? _lastDetectedFreq;
  double? _lastDetectedConf;
  double _lastDetectedElapsedMs = -10000.0;
  String _lastDetectedSource = 'none'; // 'yin', 'goertzel', 'none'

  /// SESSION-036c: Last detected MIDI note (regardless of scoring/filtering).
  int? get lastDetectedMidi => _lastDetectedMidi;

  /// SESSION-036c: Last detected frequency in Hz.
  double? get lastDetectedFreq => _lastDetectedFreq;

  /// SESSION-036c: Last detected confidence (0-1).
  double? get lastDetectedConf => _lastDetectedConf;

  /// SESSION-036c: ElapsedMs when last pitch was detected.
  double get lastDetectedElapsedMs => _lastDetectedElapsedMs;

  /// SESSION-036c: Detection source ('yin', 'goertzel', 'none').
  String get lastDetectedSource => _lastDetectedSource;

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION-037: Raw detection (BEFORE confidence filtering) for "REAL-TIME FEEL"
  // These expose the router's raw detection even for low-conf pitches
  // ═══════════════════════════════════════════════════════════════════════════
  int? get lastRawMidi => _router.lastRawMidi;
  double? get lastRawFreq => _router.lastRawFreq;
  double? get lastRawConf => _router.lastRawConf;
  double get lastRawTSec => _router.lastRawTSec;
  String get lastRawSource => _router.lastRawSource;

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

    // SESSION-028/029/030: Log patch confirmation once at first session
    if (kDebugMode && !_patchConfirmLogged) {
      _patchConfirmLogged = true;
      debugPrint(
        'PATCH_ACTIVE: SESSION-030 HIT_ROBUST=${kHitRobustEnabled ? "ENABLED" : "DISABLED"} '
        'edgeToleranceMs=$kHitEdgeToleranceMs onsetLinkMs=$kHitOnsetLinkMs '
        'candidateRmsMin=$kHitCandidateRmsMin dRmsMin=$kHitCandidateDRmsMin mode=cooldownOnly '
        'tailAware=ENABLED triggerMs=$kSustainWrongSuppressTriggerMs probeMs=$kSustainWrongSuppressProbeMs',
      );
    }
    _events.clear();
    _hitCandidates.clear(); // SESSION-030: Clear hit candidates on reset
    _lastOnsetTriggerMsByPc.clear(); // SESSION-030: Clear onset tracking
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
    _wrongFlashTripleDedupHistory.clear(); // SESSION-040: Reset triple dedup
    _wfDedupHistory
        .clear(); // SESSION-042: Reset centralized TTL dedup on new session
    _hitAttackIdHistory
        .clear(); // SESSION-043: Reset HIT attackId history on new session
    _recentWrongSamples.clear(); // SESSION-031: Reset wrong samples
    _wrongFlashEmittedThisTick = false; // SESSION-031: Reset per-tick flag
    // SESSION-038: Reset engine counters for new session
    _engineEmitCount = 0;
    _engineSkipGatedCount = 0;
    _engineSkipAlreadyEmittedTickCount = 0;
    _engineSkipPerMidiDedupCount = 0;
    _engineSkipOtherCount = 0;
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
    _dynamicOnsetMinRms =
        tuning.onsetMinRms; // Start with preset, refine with baseline
    _baselineStartMs = 0.0;
    _baselineComplete = false;
    _baselineSampleCount = 0;
    _lastOnsetTriggerMs = -10000.0;
    _lastBaselineLogMs = -10000.0;

    // SESSION-036: Reset onset state exposure
    _lastOnsetState = OnsetState.skip;
    _lastOnsetTriggerElapsedMs = -10000.0;
    _onsetActiveNoteIdx = null;
    _onsetExpectedMidi = null;
    _onsetInActiveWindow = false;
    _onsetRmsRatio = 0.0;
    _onsetDRms = 0.0;

    // SESSION-036c: Reset detected pitch exposure
    _lastDetectedMidi = null;
    _lastDetectedFreq = null;
    _lastDetectedConf = null;
    _lastDetectedElapsedMs = -10000.0;
    _lastDetectedSource = 'none';

    // SESSION-037: Reset raw detection in router
    _router.clearRawDetection();

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
        const double baselineSilenceMaxMult =
            0.6; // Max RMS as multiple of onsetMinRms
        const double onsetRecentMs = 300.0; // "Recent" onset window

        final bool onsetTriggeredRecently =
            (elapsedMs - _lastOnsetTriggerMs) < onsetRecentMs;
        final bool isSilent = rms < baselineSilenceMaxMult * tuning.onsetMinRms;

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
        _dynamicOnsetMinRms =
            (_noiseFloorRms * tuning.noiseFloorMultiplier +
                    tuning.noiseFloorMargin)
                .clamp(tuning.onsetMinRms, tuning.onsetMinRms * 5);

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
        final modeStr = _router.lastMode == DetectionMode.yin
            ? 'YIN'
            : _router.lastMode == DetectionMode.goertzel
            ? 'GOERTZEL'
            : 'NONE';
        if (kDebugMode) {
          debugPrint(
            'PITCH_ROUTER expected=$activeExpectedMidis mode=$modeStr events=${routerEvents.length} t=${elapsedSec.toStringAsFixed(3)}',
          );
        }

        // ═══════════════════════════════════════════════════════════════════
        // SESSION-036c: Update last detected pitch (BEFORE filtering)
        // This ensures UI always shows what the mic heard, regardless of scoring
        // ═══════════════════════════════════════════════════════════════════
        if (routerEvents.isNotEmpty) {
          final re = routerEvents.first;
          _lastDetectedMidi = re.midi;
          _lastDetectedFreq = re.freq;
          _lastDetectedConf = re.conf;
          _lastDetectedElapsedMs = elapsedMs;
          _lastDetectedSource = modeStr.toLowerCase();

          if (kDebugMode) {
            debugPrint(
              'DETECTED_NOTE_UPDATE midi=${re.midi} freq=${re.freq.toStringAsFixed(1)} '
              'conf=${re.conf.toStringAsFixed(2)} source=$_lastDetectedSource '
              'nowMs=${elapsedMs.toStringAsFixed(0)}',
            );
          }
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

        // ═══════════════════════════════════════════════════════════════════
        // SESSION-036: Expose onset state for anticipated flash (zero-lag)
        // ═══════════════════════════════════════════════════════════════════
        _lastOnsetState = onsetState;
        final prevRmsForDelta = _lastRms ?? rms;
        _onsetDRms = rms - prevRmsForDelta;
        _onsetRmsRatio = _onsetDetector.rmsEma > 0.0001
            ? rms / _onsetDetector.rmsEma
            : 0.0;

        // Find the first active note in window to get expected midi
        _onsetActiveNoteIdx = null;
        _onsetExpectedMidi = null;
        _onsetInActiveWindow = false;

        for (var idx = 0; idx < noteEvents.length; idx++) {
          if (hitNotes.length > idx && hitNotes[idx]) continue;
          final note = noteEvents[idx];
          final windowStart = note.start - headWindowSec;
          final windowEnd = note.end + tailWindowSec;
          if (elapsedSec >= windowStart && elapsedSec <= windowEnd) {
            _onsetActiveNoteIdx = idx;
            _onsetExpectedMidi = note.pitch;
            _onsetInActiveWindow = true;
            break;
          }
        }

        // Track trigger elapsed time
        if (onsetState == OnsetState.trigger) {
          _lastOnsetTriggerElapsedMs = elapsedMs;

          if (kDebugMode && _onsetInActiveWindow) {
            debugPrint(
              'ONSET_TRIGGER_EXPOSED t=${elapsedMs.toStringAsFixed(0)}ms '
              'noteIdx=$_onsetActiveNoteIdx expectedMidi=$_onsetExpectedMidi '
              'ratio=${_onsetRmsRatio.toStringAsFixed(2)} dRms=${_onsetDRms.toStringAsFixed(4)}',
            );
          }
        }
        // ═══════════════════════════════════════════════════════════════════

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

          // SESSION-021 FIX #4: Require minimum stability frames before emission.
          // This filters single-frame pitch glitches and sub-harmonic flickers.
          //
          // SESSION-027 FIX: Bypass stability filter for ONSET_TRIGGER events.
          // CAUSE: First-time detections of a pitch class are blocked by stability=1 < required=2
          // PREUVE: session-027 YIN_CALLED midi=70 conf=1.00 at t=9091ms but no NOTE_START
          //         because midi=70 was never played before in session (stability=1)
          // FIX: ONSET_TRIGGER is already gated by ratio check (>1.4) + cooldown, so it
          //      doesn't need multi-frame stability confirmation. Only BURST/PROBE need it.
          final bool isTriggerEvent = onsetState == OnsetState.trigger;

          // SESSION-030: Track ONSET_TRIGGER timestamp for HIT_ROBUST onsetLink check
          if (kHitRobustEnabled && isTriggerEvent) {
            _lastOnsetTriggerMsByPc[pitchClass] = elapsedMs;
          }

          if (!isTriggerEvent && stabilityFrames < kPitchStabilityMinFrames) {
            if (kDebugMode && verboseDebug) {
              debugPrint(
                'PITCH_STABILITY_SKIP midi=${re.midi} pc=$pitchClass '
                'frames=$stabilityFrames required=$kPitchStabilityMinFrames '
                't=${elapsedMs.toStringAsFixed(0)}ms',
              );
            }
            continue;
          }

          // SESSION-027: Log when stability bypass is applied for TRIGGER events
          if (kDebugMode &&
              isTriggerEvent &&
              stabilityFrames < kPitchStabilityMinFrames) {
            debugPrint(
              'STABILITY_BYPASS_TRIGGER midi=${re.midi} pc=$pitchClass '
              'frames=$stabilityFrames required=$kPitchStabilityMinFrames '
              't=${elapsedMs.toStringAsFixed(0)}ms reason=onset_trigger_gate',
            );
          }

          // ═══════════════════════════════════════════════════════════════════
          // SESSION-031: Capture sample for wrong flash fallback (no_events_in_buffer)
          // Add ALL high-confidence detections to ring buffer BEFORE NoteTracker gate.
          // This allows wrong flash detection even when main buffer is empty.
          // ═══════════════════════════════════════════════════════════════════
          if (kWrongFlashRestoreEnabled && re.conf >= kWrongSampleMinConf) {
            // Compute dRms from previous RMS
            final dRmsWrong = (_lastRms != null) ? (re.rms - _lastRms!) : 0.0;
            final isTriggerOrFailsafe =
                isTriggerEvent || eventSource == PitchEventSource.probe;

            // Prune old samples
            _recentWrongSamples.removeWhere(
              (s) => elapsedMs - s.tMs > kWrongSampleMaxAgeMs,
            );

            // Cap to max count
            while (_recentWrongSamples.length >= kWrongSampleMaxCount) {
              _recentWrongSamples.removeAt(0);
            }

            _recentWrongSamples.add(
              WrongSample(
                midi: re.midi,
                tMs: elapsedMs,
                rms: re.rms,
                conf: re.conf,
                source: eventSource,
                dRms: dRmsWrong,
                isTriggerOrFailsafe: isTriggerOrFailsafe,
              ),
            );
          }
          // ═══════════════════════════════════════════════════════════════════

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

            // ═══════════════════════════════════════════════════════════════════
            // SESSION-030 FIX: HIT_ROBUST - Save suppressed cooldown events as candidates
            // STRICT GARDE-FOUS (anti faux-verts):
            // A) cooldownOnly: ONLY accept reason=cooldown
            // B) exactMidiMatch: candidate.midi must be in activeExpectedMidis
            // C) onsetLink: dtFromOnset <= kHitOnsetLinkMs (250ms)
            // D) energySignal: rms >= 0.08 OR dRms >= 0.015
            // E) cap: max 64 candidates
            // ═══════════════════════════════════════════════════════════════════
            if (kHitRobustEnabled && re.conf >= minConfForPitch) {
              // A) cooldownOnly: ONLY accept reason=cooldown
              final isCooldownReason = trackerResult.reason == 'cooldown';
              if (!isCooldownReason) {
                // Skip non-cooldown suppressions (tail_falling, held, etc.)
                // These are more likely resonance than real attacks
                continue;
              }

              // B) exactMidiMatch: candidate.midi must be in activeExpectedMidis
              final matchesExactMidi = activeExpectedMidis.contains(re.midi);
              if (!matchesExactMidi) {
                if (kDebugMode) {
                  debugPrint(
                    'HIT_CANDIDATE_DROP midi=${re.midi} t=${elapsedMs.toStringAsFixed(0)}ms '
                    'reason=notExpected expectedSet=$activeExpectedMidis',
                  );
                }
                continue;
              }

              // C) onsetLink: check dtFromOnset <= kHitOnsetLinkMs
              final lastOnsetMs = _lastOnsetTriggerMsByPc[pitchClass];
              final dtFromOnsetMs = lastOnsetMs != null
                  ? elapsedMs - lastOnsetMs
                  : double.infinity;
              if (dtFromOnsetMs > kHitOnsetLinkMs) {
                if (kDebugMode) {
                  debugPrint(
                    'HIT_CANDIDATE_DROP midi=${re.midi} t=${elapsedMs.toStringAsFixed(0)}ms '
                    'reason=tooFarFromOnset dtFromOnset=${dtFromOnsetMs.toStringAsFixed(0)}ms '
                    'maxAllowed=$kHitOnsetLinkMs',
                  );
                }
                continue;
              }

              // D) energySignal: rms >= kHitCandidateRmsMin OR dRms >= kHitCandidateDRmsMin
              // Calculate dRms from previous RMS for this pitchClass
              final prevRms = _lastRms ?? 0.0;
              final dRms = re.rms - prevRms;
              final hasEnergy =
                  re.rms >= kHitCandidateRmsMin || dRms >= kHitCandidateDRmsMin;
              if (!hasEnergy) {
                if (kDebugMode) {
                  debugPrint(
                    'HIT_CANDIDATE_DROP midi=${re.midi} t=${elapsedMs.toStringAsFixed(0)}ms '
                    'reason=lowEnergy rms=${re.rms.toStringAsFixed(3)} dRms=${dRms.toStringAsFixed(3)} '
                    'minRms=$kHitCandidateRmsMin minDRms=$kHitCandidateDRmsMin',
                  );
                }
                continue;
              }

              // E) cap: enforce max candidates
              if (_hitCandidates.length >= kHitCandidateMaxCount) {
                if (kDebugMode) {
                  debugPrint(
                    'HIT_CANDIDATE_DROP midi=${re.midi} t=${elapsedMs.toStringAsFixed(0)}ms '
                    'reason=cap count=${_hitCandidates.length} max=$kHitCandidateMaxCount',
                  );
                }
                continue;
              }

              // All garde-fous passed - add candidate
              _hitCandidates.add(
                HitCandidate(
                  midi: re.midi,
                  tMs: elapsedMs,
                  rms: re.rms,
                  conf: re.conf,
                  source: eventSource,
                  suppressReason: trackerResult.reason,
                  dtFromOnsetMs: dtFromOnsetMs,
                  dRms: dRms,
                ),
              );

              if (kDebugMode) {
                debugPrint(
                  'HIT_CANDIDATE_ADD midi=${re.midi} t=${elapsedMs.toStringAsFixed(0)}ms '
                  'suppressReason=${trackerResult.reason} rms=${re.rms.toStringAsFixed(3)} '
                  'dRms=${dRms.toStringAsFixed(3)} dtFromOnset=${dtFromOnsetMs.toStringAsFixed(0)}ms '
                  'expectedSet=$activeExpectedMidis',
                );
              }
            }
            // ═══════════════════════════════════════════════════════════════════

            // Tail/held/cooldown - skip adding to main buffer
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

  /// SESSION-021 FIX #1: Local conditional snap for pitch drift tolerance.
  ///
  /// Returns true if the detected event should be snapped to the expected note.
  /// Conditions for snap (ALL must be true):
  /// 1. kYinSnapTolerance1Semitone is enabled
  /// 2. Detected MIDI is within +-1 semitone of expected
  /// 3. Confidence >= minConfForPitch (trust the detection)
  /// 4. Stability >= kPitchStabilityMinFrames (not a single-frame glitch)
  ///
  /// This fixes the D#4(63) detected as E4(64) issue caused by harmonics/overtones
  /// without modifying the core PracticePitchRouter.
  bool _shouldSnapToExpected({
    required int detectedMidi,
    required int expectedMidi,
    required double conf,
    required int stabilityFrames,
  }) {
    if (!kYinSnapTolerance1Semitone) return false;

    final delta = (detectedMidi - expectedMidi).abs();
    if (delta > 1) return false; // More than 1 semitone away
    if (delta == 0) return true; // Exact match, always "snap"

    // For delta == 1 (adjacent semitone), require high confidence + stability
    if (conf < minConfForPitch) return false;
    if (stabilityFrames < kPitchStabilityMinFrames) return false;

    return true;
  }

  /// SESSION-015: Update latency compensation estimate from collected samples.
  ///
  /// Uses median of recent samples (robust to outliers) with EMA smoothing.
  /// Clamps result to [-latencyCompMaxMs, +latencyCompMaxMs].
  ///
  /// SESSION-021 FIX #3: Added spike clamp - rejects samples > 2x median.
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

  /// SESSION-021 FIX #3: Check if a latency sample is a spike (outlier).
  ///
  /// A spike is defined as a sample > kLatencySpikeClampRatio * current median.
  /// This filters outliers like 485ms when median is ~250ms.
  bool _isLatencySpike(double sampleMs) {
    if (!kLatencySpikeClamp) return false;
    if (_latencyMedianMs == null || _latencyMedianMs! <= 0) return false;

    final threshold = _latencyMedianMs! * kLatencySpikeClampRatio;
    final isSpike = sampleMs.abs() > threshold;

    if (isSpike && kDebugMode) {
      _debugLatencySpikeCount++;
      debugPrint(
        'LATENCY_SPIKE_REJECT sampleMs=${sampleMs.toStringAsFixed(1)} '
        'medianMs=${_latencyMedianMs!.toStringAsFixed(1)} '
        'threshold=${threshold.toStringAsFixed(1)} ratio=$kLatencySpikeClampRatio',
      );
    }

    return isSpike;
  }

  List<NoteDecision> _matchNotes(double elapsed, DateTime now) {
    final decisions = <NoteDecision>[];

    // SESSION-031: Reset per-tick flag at start of matching
    if (kWrongFlashRestoreEnabled) {
      _wrongFlashEmittedThisTick = false;
    }

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

    // SESSION-030: Prune old hit candidates (TTL = 1000ms)
    if (kHitRobustEnabled) {
      final elapsedMs = elapsed * 1000.0;
      _hitCandidates.removeWhere((c) => elapsedMs - c.tMs > kHitCandidateTtlMs);
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
          // SESSION-030: Enhanced MISS diagnostic with candidate info
          final windowStartMs = windowStart * 1000.0;
          final windowEndMs = windowEnd * 1000.0;
          final candidatesInWindow = kHitRobustEnabled
              ? _hitCandidates.where((c) {
                  return c.midi == note.pitch &&
                      c.tMs >= windowStartMs - kHitEdgeToleranceMs &&
                      c.tMs <= windowEndMs + kHitEdgeToleranceMs;
                }).length
              : 0;
          debugPrint(
            'HIT_DECISION sessionId=$_sessionId noteIdx=$idx elapsed=${elapsed.toStringAsFixed(3)} '
            'expectedMidi=${note.pitch} window=[${windowStart.toStringAsFixed(3)}..${windowEnd.toStringAsFixed(3)}] '
            'result=MISS reason=timeout_no_match',
          );
          if (kHitRobustEnabled) {
            debugPrint(
              'HIT_MISS_DIAG noteIdx=$idx expectedMidi=${note.pitch} '
              'reason=no_events_in_buffer candidatesInWindow=$candidatesInWindow '
              'totalCandidates=${_hitCandidates.length}',
            );
          }
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

        // SESSION-021 FIX #1: Check if we should snap to expected (+-1 semitone tolerance)
        // This allows D#4(63) detected as E4(64) to match, fixing harmonics-induced drift
        final shouldSnap = _shouldSnapToExpected(
          detectedMidi: event.midi,
          expectedMidi: note.pitch,
          conf: event.conf,
          stabilityFrames: event.stabilityFrames,
        );

        // Reject: pitch class mismatch (unless snap is allowed)
        if (detectedPitchClass != expectedPitchClass && !shouldSnap) {
          // Always track pitch_class_mismatch (not just verboseDebug) for accurate logging
          if (kDebugMode && rejectReason == null) {
            rejectReason =
                'pitch_class_mismatch_expected=${expectedPitchClass}_detected=$detectedPitchClass';
          }
          continue;
        }

        // SESSION-040 ADDENDUM: dt guard BEFORE bestEvent selection (not accept-then-undo)
        // Calculate adjusted event time with latency compensation
        final adjustedEventTSec = latencyCompEnabled
            ? event.tSec - (_latencyCompMs / 1000.0)
            : event.tSec;
        // Calculate dt: how far from note window (0 if during note)
        final double candidateDtSec;
        if (adjustedEventTSec < note.start) {
          candidateDtSec = adjustedEventTSec - note.start; // negative (early)
        } else if (adjustedEventTSec <= note.end) {
          candidateDtSec = 0.0; // during note = perfect
        } else {
          candidateDtSec = adjustedEventTSec - note.end; // positive (late)
        }
        final candidateDtMs = candidateDtSec.abs() * 1000.0;
        if (candidateDtMs > kHitDtMaxMs) {
          if (kDebugMode && rejectReason == null) {
            rejectReason =
                'dt_exceeds_max_${candidateDtMs.toStringAsFixed(0)}ms>${kHitDtMaxMs.toStringAsFixed(0)}ms';
          }
          continue;
        }

        // Now we have pitch class match OR snap allowed, test direct midi
        // (octave shifts ±12/±24 disabled to prevent harmonics false hits)
        // SESSION-040 FIX: Always use actual distance (not 0.0 for snap)
        // CAUSE: distance=0.0 when midi differs was misleading in logs
        final distDirect = (event.midi - note.pitch).abs().toDouble();
        if (distDirect < bestDistance) {
          bestDistance = distDirect;
          bestEvent = event;
          // Log snap event for debugging
          if (shouldSnap &&
              detectedPitchClass != expectedPitchClass &&
              kDebugMode) {
            debugPrint(
              'PITCH_SNAP detected=${event.midi} expected=${note.pitch} '
              'conf=${event.conf.toStringAsFixed(2)} stability=${event.stabilityFrames} '
              't=${event.tSec.toStringAsFixed(3)} distance=${distDirect.toStringAsFixed(1)}',
            );
          }
        }
      }

      // ═══════════════════════════════════════════════════════════════════════
      // SESSION-030 FIX: HIT_ROBUST fallback - check _hitCandidates
      // If no match in main buffer, use candidates that passed strict garde-fous:
      // - cooldownOnly, exactMidiMatch, onsetLink, energySignal
      // ═══════════════════════════════════════════════════════════════════════
      HitCandidate? matchedCandidate;
      if (kHitRobustEnabled && bestEvent == null) {
        final windowStartMs = windowStart * 1000.0;
        final windowEndMs = windowEnd * 1000.0;
        final extendedWindowStartMs = windowStartMs - kHitEdgeToleranceMs;
        final extendedWindowEndMs = windowEndMs + kHitEdgeToleranceMs;

        HitCandidate? bestCandidate;
        double bestCandidateDt = double.infinity;

        for (final candidate in _hitCandidates) {
          // B) exactMidiMatch: candidate.midi must equal expectedMidi
          if (candidate.midi != note.pitch) {
            continue;
          }

          // Check extended time window (with edge tolerance)
          if (candidate.tMs < extendedWindowStartMs ||
              candidate.tMs > extendedWindowEndMs) {
            continue;
          }

          // Skip consumed candidates
          final candidateTSec = candidate.tMs / 1000.0;
          if (consumedEventTimes.contains(candidateTSec)) {
            continue;
          }

          // SESSION-040 ADDENDUM: dt guard BEFORE bestCandidate selection
          // Calculate adjusted candidate time with latency compensation
          final adjustedCandTSec = latencyCompEnabled
              ? candidateTSec - (_latencyCompMs / 1000.0)
              : candidateTSec;
          // Calculate dt: how far from note window (0 if during note)
          final double candDtSec;
          if (adjustedCandTSec < note.start) {
            candDtSec = adjustedCandTSec - note.start; // negative (early)
          } else if (adjustedCandTSec <= note.end) {
            candDtSec = 0.0; // during note = perfect
          } else {
            candDtSec = adjustedCandTSec - note.end; // positive (late)
          }
          final candDtMs = candDtSec.abs() * 1000.0;
          if (candDtMs > kHitDtMaxMs) {
            continue; // Skip candidate with dt too large
          }

          // Select closest to window center
          final windowCenterMs = (windowStartMs + windowEndMs) / 2.0;
          final dtToCenter = (candidate.tMs - windowCenterMs).abs();
          if (dtToCenter < bestCandidateDt) {
            bestCandidateDt = dtToCenter;
            bestCandidate = candidate;
          }
        }

        if (bestCandidate != null) {
          // Convert candidate to PitchEvent for compatibility with existing code
          final candidateTSec = bestCandidate.tMs / 1000.0;
          bestEvent = PitchEvent(
            tSec: candidateTSec,
            midi: bestCandidate.midi,
            freq: 0.0, // Not available from candidate
            conf: bestCandidate.conf,
            rms: bestCandidate.rms,
            stabilityFrames: 1,
            source: bestCandidate.source,
          );
          bestDistance = 0.0; // Exact midi match
          matchedCandidate = bestCandidate;

          // Log candidate match
          final isEdge =
              bestCandidate.tMs < windowStartMs ||
              bestCandidate.tMs > windowEndMs;
          final dtToWindowMs = isEdge
              ? (bestCandidate.tMs < windowStartMs
                    ? windowStartMs - bestCandidate.tMs
                    : bestCandidate.tMs - windowEndMs)
              : 0.0;
          if (kDebugMode) {
            debugPrint(
              'HIT_CANDIDATE_MATCH noteIdx=$idx expectedMidi=${note.pitch} '
              'candMidi=${bestCandidate.midi} t=${bestCandidate.tMs.toStringAsFixed(0)}ms '
              'dtToWindow=${dtToWindowMs.toStringAsFixed(0)}ms usedFallback=true '
              'dtFromOnset=${bestCandidate.dtFromOnsetMs.toStringAsFixed(0)}ms '
              'rms=${bestCandidate.rms.toStringAsFixed(3)}',
            );
          }
        }
      }
      // ═══════════════════════════════════════════════════════════════════════

      // Check HIT with very tolerant distance (≤3 semitones for real piano+mic)
      if (bestEvent != null && bestDistance <= 3.0) {
        hitNotes[idx] = true;

        // FIX BUG SESSION-003 #4: Mark this event as consumed so it can't
        // validate another note with the same pitch class
        consumedEventTimes.add(bestEvent.tSec);

        // SESSION-030: Remove matched candidate from list
        if (kHitRobustEnabled && matchedCandidate != null) {
          _hitCandidates.remove(matchedCandidate);
        }

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

        // SESSION-040 ADDENDUM: dt guard moved to BEFORE bestEvent selection
        // (no more "accept then undo" - candidates filtered upstream)

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

          // SESSION-021 FIX #3: Reject spike samples before adding to window
          // Only check after we have a valid median (2+ samples)
          if (_isLatencySpike(rawDtMs)) {
            // Spike rejected - don't add to samples, don't update estimate
            // Log already emitted by _isLatencySpike
          } else {
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

        // SESSION-043: Record attackId that produced this HIT to block WRONG_FLASH
        // CAUSE: Same attack can produce HIT for noteIdx=N, then WRONG for noteIdx=N+1
        final hitAttackId = _lastOnsetTriggerElapsedMs.round();
        final hitNowMs = (elapsed * 1000).round();
        _hitAttackIdHistory[hitAttackId] = hitNowMs;
        // Purge old entries to prevent unbounded growth
        if (_hitAttackIdHistory.length > 20) {
          _hitAttackIdHistory.removeWhere(
            (k, v) => (hitNowMs - v) > _hitAttackIdTtlMs * 2,
          );
        }

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

        // ═══════════════════════════════════════════════════════════════════
        // SESSION-031 FIX: Fallback wrong flash for no_events_in_buffer
        // When main buffer is empty but we have recent pitch samples, check
        // if any of them are wrong notes and emit wrong flash.
        // ═══════════════════════════════════════════════════════════════════
        if (kWrongFlashRestoreEnabled &&
            bestEvent == null &&
            !_wrongFlashEmittedThisTick) {
          final elapsedMs = elapsed * 1000.0;

          // Prune old samples
          _recentWrongSamples.removeWhere(
            (s) => elapsedMs - s.tMs > kWrongSampleMaxAgeMs,
          );

          // Find best wrong sample (high conf, wrong midi, good energy)
          WrongSample? bestWrongSample;
          for (final sample in _recentWrongSamples) {
            // Skip if same as expected (not wrong)
            if (sample.midi == note.pitch) continue;

            // Skip if pitch class matches expected (might be octave of correct note)
            if (sample.midi % 12 == expectedPitchClass) continue;

            // Skip if same as recently hit (sustain, not new attack)
            final recentHit = _recentlyHitPitchClasses[sample.midi % 12];
            if (recentHit != null) {
              final msSinceHit = now.difference(recentHit).inMilliseconds;
              // SESSION-035 FIX: Always skip if HIT just happened (< 10ms)
              // PREUVE: elapsed=7.317 HIT noteIdx=5 midi=61, then WRONG noteIdx=6
              //         with same midi=61 because isTriggerOrFailsafe bypassed check
              // Bug: trigger/failsafe samples bypassed msSinceHit<350 gate
              if (msSinceHit < 10 ||
                  (!sample.isTriggerOrFailsafe && msSinceHit < 350)) {
                continue;
              }
            }

            // Energy check: require trigger/failsafe OR significant dRms
            final hasEnergy =
                sample.isTriggerOrFailsafe ||
                sample.rms >= kHitCandidateRmsMin ||
                sample.dRms >= kHitCandidateDRmsMin;
            if (!hasEnergy) continue;

            // Take highest confidence
            if (bestWrongSample == null || sample.conf > bestWrongSample.conf) {
              bestWrongSample = sample;
            }
          }

          if (bestWrongSample != null) {
            // Emit fallback wrong flash
            final globalCooldownOk =
                _lastWrongFlashAt == null ||
                now.difference(_lastWrongFlashAt!).inMilliseconds >
                    (wrongFlashCooldownSec * 1000);
            final lastFlashForMidi =
                _lastWrongFlashByMidi[bestWrongSample.midi];
            final perMidiDedupOk =
                lastFlashForMidi == null ||
                now.difference(lastFlashForMidi).inMilliseconds >
                    wrongFlashDedupMs;

            // SESSION-038 FIX: Grace period - don't emit fallback wrong in first 400ms
            // PREUVE: session-038 noteIdx=1 got 6 WRONG_FLASH_EMIT before player played
            final timeSinceWindowStartMs = (elapsed - windowStart) * 1000.0;
            final gracePeriodOk =
                timeSinceWindowStartMs >= kFallbackGracePeriodMs;
            if (!gracePeriodOk && kDebugMode) {
              debugPrint(
                'WRONG_FLASH_SKIP reason=fallback_grace_period noteIdx=$idx '
                'expectedMidi=${note.pitch} detectedMidi=${bestWrongSample.midi} '
                'timeSinceWindowStartMs=${timeSinceWindowStartMs.toStringAsFixed(0)} '
                'gracePeriodMs=$kFallbackGracePeriodMs',
              );
            }

            // SESSION-040: Triple dedup (noteIdx, expected, detected) - prevents multi-emit
            final tripleKey = '${idx}_${note.pitch}_${bestWrongSample.midi}';
            final lastTripleFlash = _wrongFlashTripleDedupHistory[tripleKey];
            final tripleDedupOk =
                lastTripleFlash == null ||
                now.difference(lastTripleFlash).inMilliseconds >
                    _wrongFlashTripleDedupMs;

            // SESSION-042: Centralized TTL dedup - MUST pass before any emission
            final attackIdInt = _lastOnsetTriggerElapsedMs.round();
            final nowMsInt = (elapsed * 1000).round();
            if (!_wfDedupAllow(
              noteIdx: idx,
              attackId: attackIdInt,
              nowMs: nowMsInt,
              path: 'NO_EVENTS_FALLBACK',
            )) {
              continue; // STRICT: Bail out, no fall-through
            }

            // SESSION-044: Lookahead check - block if midi matches future overlapping note
            if (_isLookaheadMatch(
              detectedMidi: bestWrongSample.midi,
              currentNoteIdx: idx,
              noteEvents: noteEvents,
              hitNotes: hitNotes,
              elapsed: elapsed,
              headWindowSec: headWindowSec,
              tailWindowSec: tailWindowSec,
              path: 'NO_EVENTS_FALLBACK',
            )) {
              continue; // STRICT: Bail out, midi will HIT future note
            }

            if (globalCooldownOk &&
                perMidiDedupOk &&
                gracePeriodOk &&
                tripleDedupOk) {
              decisions.add(
                NoteDecision(
                  type: DecisionType.wrongFlash,
                  noteIndex: idx,
                  expectedMidi: note.pitch,
                  detectedMidi: bestWrongSample.midi,
                  confidence: bestWrongSample.conf,
                ),
              );
              _lastWrongFlashAt = now;
              _lastWrongFlashByMidi[bestWrongSample.midi] = now;
              _wrongFlashTripleDedupHistory[tripleKey] = now; // SESSION-040
              // SESSION-042: emit time already recorded by _wfDedupAllow
              _wrongFlashEmittedThisTick = true;
              _engineEmitCount++; // SESSION-038: Count engine emit

              if (kDebugMode) {
                // SESSION-042: Unified WRONG_FLASH_EMIT log with key for proof
                final key = '${idx}_$attackIdInt';
                debugPrint(
                  'WRONG_FLASH_EMIT key=$key attackId=$attackIdInt nowMs=$nowMsInt '
                  'noteIdx=$idx midi=${bestWrongSample.midi} path=NO_EVENTS_FALLBACK',
                );
              }
            } else if (lastTripleFlash != null &&
                !tripleDedupOk &&
                kDebugMode) {
              final dtSkipMs = now.difference(lastTripleFlash).inMilliseconds;
              debugPrint(
                'WHY_SKIPPED_DUP_KEY key=$tripleKey dt=${dtSkipMs}ms trigger=NO_EVENTS_FALLBACK',
              );
            }
          }
        }
        // ═══════════════════════════════════════════════════════════════════

        // ─────────────────────────────────────────────────────────────────────
        // SESSION-017 FIX: Emit WRONG_FLASH on pitch_class_mismatch REJECT
        // When user plays wrong pitch during an active note window, show red flash
        // This catches cases where detectedPC is in activeExpectedPitchClasses
        // (e.g., D# sustain from previous note) but mismatches current note's expectedPC
        // ─────────────────────────────────────────────────────────────────────
        // ─────────────────────────────────────────────────────────────────────
        // SESSION-023 FIX #2: Emit WRONG_FLASH on distance_too_large with SAME pitch class
        // This catches octave errors: user plays F5 instead of F4 (same PC, wrong octave)
        // Without this, the rejection is silent and confusing for beginners.
        // ─────────────────────────────────────────────────────────────────────
        if (bestEvent != null && bestDistance > 3.0) {
          // Check if pitch class actually matches (octave error)
          final detectedPC = bestEvent.midi % 12;
          final isPitchClassMatch = detectedPC == expectedPitchClass;

          if (isPitchClassMatch) {
            // This is an octave error - emit WRONG_FLASH with special tag

            // GATE 1: Global cooldown
            final globalCooldownOk =
                _lastWrongFlashAt == null ||
                now.difference(_lastWrongFlashAt!).inMilliseconds >
                    (wrongFlashCooldownSec * 1000);

            // GATE 2: Per-(noteIdx, detectedMidi) dedup
            final dedupKey = 'octave_${idx}_${bestEvent.midi}';
            final lastFlashForKey = _mismatchDedupHistory[dedupKey];
            final perNoteDedupOk =
                lastFlashForKey == null ||
                now.difference(lastFlashForKey).inMilliseconds >
                    wrongFlashDedupMs;

            // GATE 3: Confidence check
            final confOk = bestEvent.conf >= wrongFlashMinConf;

            // SESSION-028 FIX: GATE 4 - Suppress sustain of recent HIT
            // If the detected pitchClass was recently HIT, suppress WRONG_FLASH
            // to avoid false red flash from note sustain/tail.
            // SESSION-029 FIX: Tail-aware - use longer window for probe (sustain)
            final recentHitTimeForDetected =
                _recentlyHitPitchClasses[detectedPC];
            final msSinceHitForDetected = recentHitTimeForDetected != null
                ? now.difference(recentHitTimeForDetected).inMilliseconds
                : null;
            final sustainThresholdMs =
                bestEvent.source == PitchEventSource.probe
                ? kSustainWrongSuppressProbeMs
                : kSustainWrongSuppressTriggerMs;
            final sustainSuppressOk =
                msSinceHitForDetected == null ||
                msSinceHitForDetected > sustainThresholdMs;

            // SESSION-031: Check per-tick flag
            final tickOk =
                !kWrongFlashRestoreEnabled || !_wrongFlashEmittedThisTick;

            // SESSION-040: Triple dedup (noteIdx, expected, detected) - prevents multi-emit
            final tripleKey = '${idx}_${note.pitch}_${bestEvent.midi}';
            final lastTripleFlash = _wrongFlashTripleDedupHistory[tripleKey];
            final tripleDedupOk =
                lastTripleFlash == null ||
                now.difference(lastTripleFlash).inMilliseconds >
                    _wrongFlashTripleDedupMs;

            // SESSION-042: Centralized TTL dedup - MUST pass before any emission
            final attackIdInt = _lastOnsetTriggerElapsedMs.round();
            final nowMsInt = (elapsed * 1000).round();
            if (!_wfDedupAllow(
              noteIdx: idx,
              attackId: attackIdInt,
              nowMs: nowMsInt,
              path: 'OCTAVE_ERROR',
            )) {
              continue; // STRICT: Bail out, no fall-through
            }

            // SESSION-044: Lookahead check - block if midi matches future overlapping note
            if (_isLookaheadMatch(
              detectedMidi: bestEvent.midi,
              currentNoteIdx: idx,
              noteEvents: noteEvents,
              hitNotes: hitNotes,
              elapsed: elapsed,
              headWindowSec: headWindowSec,
              tailWindowSec: tailWindowSec,
              path: 'OCTAVE_ERROR',
            )) {
              continue; // STRICT: Bail out, midi will HIT future note
            }

            if (globalCooldownOk &&
                perNoteDedupOk &&
                confOk &&
                sustainSuppressOk &&
                tickOk &&
                tripleDedupOk) {
              // All gates passed - emit WRONG_FLASH for octave error
              decisions.add(
                NoteDecision(
                  type: DecisionType.wrongFlash,
                  noteIndex: idx,
                  expectedMidi: note.pitch,
                  detectedMidi: bestEvent.midi,
                  confidence: bestEvent.conf,
                ),
              );
              _lastWrongFlashAt = now;
              _mismatchDedupHistory[dedupKey] = now;
              _lastWrongFlashByMidi[bestEvent.midi] = now;
              _wrongFlashTripleDedupHistory[tripleKey] = now; // SESSION-040
              // SESSION-042: emit time already recorded by _wfDedupAllow
              if (kWrongFlashRestoreEnabled) {
                _wrongFlashEmittedThisTick = true;
              }
              _engineEmitCount++; // SESSION-038: Count engine emit

              if (kDebugMode) {
                // SESSION-042: Unified WRONG_FLASH_EMIT log with key for proof
                final key = '${idx}_$attackIdInt';
                debugPrint(
                  'WRONG_FLASH_EMIT key=$key attackId=$attackIdInt nowMs=$nowMsInt '
                  'noteIdx=$idx midi=${bestEvent.midi} path=OCTAVE_ERROR',
                );
              }
            } else if (!tripleDedupOk && kDebugMode) {
              debugPrint(
                'WHY_SKIPPED_DUP_KEY key=$tripleKey trigger=OCTAVE_ERROR',
              );
            } else if (!sustainSuppressOk) {
              // SESSION-028/029: Suppressed due to recent HIT sustain (tail-aware)
              if (kDebugMode) {
                debugPrint(
                  'SUPPRESS_SUSTAIN_WRONG_PRE midi=${bestEvent.midi} pc=$detectedPC '
                  'msSinceHit=$msSinceHitForDetected thresholdMs=$sustainThresholdMs '
                  'source=${bestEvent.source.name} noteIdx=$idx expectedMidi=${note.pitch} '
                  'trigger=OCTAVE_ERROR reason=recent_hit_sustain',
                );
              }
            } else {
              // Gates blocked - log skip
              // SESSION-038: Count gated skip
              if (!globalCooldownOk) {
                _engineSkipGatedCount++;
              } else if (!perNoteDedupOk) {
                _engineSkipPerMidiDedupCount++;
              } else {
                _engineSkipOtherCount++;
              }
              if (kDebugMode) {
                debugPrint(
                  'WRONG_FLASH_SKIP reason=octave_gated noteIdx=$idx '
                  'expectedMidi=${note.pitch} detectedMidi=${bestEvent.midi} '
                  'distance=${bestDistance.toStringAsFixed(1)} '
                  'conf=${bestEvent.conf.toStringAsFixed(2)} '
                  'cooldownOk=$globalCooldownOk dedupOk=$perNoteDedupOk confOk=$confOk',
                );
              }
            }
          }
        }

        if (rejectReason != null &&
            rejectReason.startsWith('pitch_class_mismatch_expected=')) {
          // Parse detected info from rejectReason: "pitch_class_mismatch_expected=X_detected=Y"
          // Robust regex: captures both expectedPC and detectedPC
          final mismatchRegex = RegExp(
            r'pitch_class_mismatch_expected=(\d+)_detected=(\d+)',
          );
          final mismatchMatch = mismatchRegex.firstMatch(rejectReason);

          if (mismatchMatch == null) {
            // FAIL-SAFE: Parse failed - log and skip
            _engineSkipOtherCount++; // SESSION-038: Count other skip
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
                  if (mismatchEvent == null ||
                      event.conf > mismatchEvent.conf) {
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
                  now.difference(lastFlashForKey).inMilliseconds >
                      wrongFlashDedupMs;

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
              final confirmationOk =
                  candidateList.length >= wrongFlashConfirmCount;

              // SESSION-028 FIX: GATE 4 - Suppress sustain of recent HIT
              // If the detected pitchClass was recently HIT, suppress WRONG_FLASH
              // to avoid false red flash from note sustain/tail.
              // SESSION-029 FIX: Tail-aware - use longer window for probe (sustain)
              final recentHitTimeForDetected =
                  _recentlyHitPitchClasses[detectedPC];
              final msSinceHitForDetected = recentHitTimeForDetected != null
                  ? now.difference(recentHitTimeForDetected).inMilliseconds
                  : null;
              final sustainThresholdMs =
                  mismatchEvent.source == PitchEventSource.probe
                  ? kSustainWrongSuppressProbeMs
                  : kSustainWrongSuppressTriggerMs;
              final sustainSuppressOk =
                  msSinceHitForDetected == null ||
                  msSinceHitForDetected > sustainThresholdMs;

              // SESSION-031: Check per-tick flag
              final tickOk =
                  !kWrongFlashRestoreEnabled || !_wrongFlashEmittedThisTick;

              // SESSION-040: Triple dedup (noteIdx, expected, detected) - prevents multi-emit
              final tripleKey = '${idx}_${note.pitch}_${mismatchEvent.midi}';
              final lastTripleFlash = _wrongFlashTripleDedupHistory[tripleKey];
              final tripleDedupOk =
                  lastTripleFlash == null ||
                  now.difference(lastTripleFlash).inMilliseconds >
                      _wrongFlashTripleDedupMs;

              // SESSION-042: Centralized TTL dedup - MUST pass before any emission
              final attackIdInt = _lastOnsetTriggerElapsedMs.round();
              final nowMsInt = (elapsed * 1000).round();
              if (!_wfDedupAllow(
                noteIdx: idx,
                attackId: attackIdInt,
                nowMs: nowMsInt,
                path: 'HIT_REJECT_MISMATCH',
              )) {
                continue; // STRICT: Bail out, no fall-through
              }

              // SESSION-044: Lookahead check - block if midi matches future overlapping note
              if (_isLookaheadMatch(
                detectedMidi: mismatchEvent.midi,
                currentNoteIdx: idx,
                noteEvents: noteEvents,
                hitNotes: hitNotes,
                elapsed: elapsed,
                headWindowSec: headWindowSec,
                tailWindowSec: tailWindowSec,
                path: 'HIT_REJECT_MISMATCH',
              )) {
                continue; // STRICT: Bail out, midi will HIT future note
              }

              if (globalCooldownOk &&
                  perNoteDedupOk &&
                  confirmationOk &&
                  sustainSuppressOk &&
                  tickOk &&
                  tripleDedupOk) {
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
                // SESSION-020 FIX: Also update per-midi dedup to prevent spam from post-match scan
                _lastWrongFlashByMidi[mismatchEvent.midi] = now;
                _wrongFlashTripleDedupHistory[tripleKey] = now; // SESSION-040
                // SESSION-042: emit time already recorded by _wfDedupAllow
                _mismatchConfirmHistory.remove(confirmKey);
                if (kWrongFlashRestoreEnabled) {
                  _wrongFlashEmittedThisTick = true;
                }
                _engineEmitCount++; // SESSION-038: Count engine emit

                if (kDebugMode) {
                  // SESSION-042: Unified WRONG_FLASH_EMIT log with key for proof
                  final key = '${idx}_$attackIdInt';
                  debugPrint(
                    'WRONG_FLASH_EMIT key=$key attackId=$attackIdInt nowMs=$nowMsInt '
                    'noteIdx=$idx midi=${mismatchEvent.midi} path=HIT_REJECT_MISMATCH',
                  );
                }
              } else if (!tripleDedupOk && kDebugMode) {
                debugPrint(
                  'WHY_SKIPPED_DUP_KEY key=$tripleKey trigger=HIT_DECISION_REJECT_MISMATCH',
                );
              } else if (!sustainSuppressOk) {
                // SESSION-028/029: Suppressed due to recent HIT sustain (tail-aware)
                if (kDebugMode) {
                  debugPrint(
                    'SUPPRESS_SUSTAIN_WRONG_PRE midi=${mismatchEvent.midi} pc=$detectedPC '
                    'msSinceHit=$msSinceHitForDetected thresholdMs=$sustainThresholdMs '
                    'source=${mismatchEvent.source.name} noteIdx=$idx expectedMidi=${note.pitch} '
                    'trigger=HIT_DECISION_REJECT_MISMATCH reason=recent_hit_sustain',
                  );
                }
              } else {
                // Gates blocked - log skip with details
                // SESSION-038: Count gated skip
                if (!globalCooldownOk) {
                  _engineSkipGatedCount++;
                } else if (!perNoteDedupOk) {
                  _engineSkipPerMidiDedupCount++;
                }
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
    final double effectiveOnsetMinRms = _baselineComplete
        ? _dynamicOnsetMinRms
        : tuning.onsetMinRms;

    // Multiplier for PROBE override RMS check
    const double probeOverrideRmsMult = 2.0;
    const double probeOverrideConfMin = 0.92;
    const double highConfAttackConfMin = 0.90;
    // SESSION-020 FIX BUG #1: Max delta for PROBE override
    // PROBE events with delta >= this threshold are NEVER allowed through probeOverride
    // because they are likely harmonics/artifacts, not real wrong notes.
    // Value 7 = perfect 5th - anything beyond is suspicious for a "wrong key" scenario.
    const int probeOverrideMaxDelta = 7;

    /// Check if event is a high-confidence attack (for logging purposes).
    bool isHighConfidenceAttack(PitchEvent e) {
      return e.conf >= highConfAttackConfMin;
    }

    /// Check if PROBE event can override the probe block.
    /// Requires: very high conf + RMS well above effective onset threshold.
    /// SESSION-020 FIX: Also requires minDelta < probeOverrideMaxDelta to filter harmonics.
    bool canOverrideProbe(PitchEvent e, int minDelta) {
      if (e.source != PitchEventSource.probe) return false;
      if (e.conf < probeOverrideConfMin) return false;
      if (e.rms < probeOverrideRmsMult * effectiveOnsetMinRms) return false;
      // SESSION-020 FIX BUG #1: Block probe override for large deltas (harmonics)
      // A PROBE 10 semitones away is almost certainly a harmonic, not a pressed key.
      if (minDelta >= probeOverrideMaxDelta) return false;
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
      // SESSION-020 FIX BUG #1: Pass minDelta to block probe override for harmonics
      final bool probeOverride = canOverrideProbe(event, minDeltaToExpected);

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
      // SESSION-020 FIX BUG #1: REMOVED highConfAttack bypass for outlier filter
      // Previously: highConfAttack could bypass this, causing wrong flashes 10+ semitones away
      // Now: outlier filter ALWAYS applies regardless of confidence
      // Rationale: A note 10 semitones away is NEVER the "wrong key pressed" - it's noise/harmonic
      //
      // SESSION-023 FIX #1: Don't DROP outlier when no expected notes active
      // When activeExpectedMidis is empty, minDelta=999 (sentinel) causes false DROP.
      // Instead, SKIP with explicit reason to avoid polluting logs.
      if (activeExpectedMidis.isEmpty) {
        _engineSkipOtherCount++; // SESSION-038: Count other skip
        if (kDebugMode) {
          debugPrint(
            'WRONG_FLASH_SKIP reason=no_expected_active midi=${event.midi} '
            'conf=${event.conf.toStringAsFixed(2)} '
            'activeExpectedCount=0',
          );
        }
        continue;
      }
      if (minDeltaToExpected > maxSemitoneDeltaForWrong) {
        if (kDebugMode) {
          debugPrint(
            'WRONG_FLASH_DROP reason=outlier midi=${event.midi} '
            'conf=${event.conf.toStringAsFixed(2)} minDelta=$minDeltaToExpected '
            'threshold=$maxSemitoneDeltaForWrong activeExpected=$activeExpectedMidis',
          );
        }
        continue;
      }

      // FILTER 4: Out of plausible keyboard range
      // SESSION-020 FIX BUG #1: REMOVED highConfAttack bypass for range filter
      // Previously: highConfAttack could bypass this, causing wrong flashes outside keyboard range
      // Now: range filter ALWAYS applies regardless of confidence
      if (activeExpectedMidis.isNotEmpty &&
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
        // SESSION-031: Only log ALLOW if we haven't already emitted this tick
        // This prevents confusing ALLOW→SKIP sequences in logs
        if (kDebugMode &&
            !(kWrongFlashRestoreEnabled && _wrongFlashEmittedThisTick)) {
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
    final bool silenceGateOk =
        !isSilenceMode ||
        (bestWrongEvent != null &&
            bestWrongEvent.source != PitchEventSource.probe &&
            bestWrongEvent.conf >= silenceModeMinConf);

    if (bestWrongEvent != null && silenceGateOk) {
      // SESSION-031: Check per-tick flag first (skip if already emitted this tick)
      final tickOk = !kWrongFlashRestoreEnabled || !_wrongFlashEmittedThisTick;

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

      if (tickOk && globalCooldownOk && perMidiDedupOk) {
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

        // SESSION-042: Centralized TTL dedup - MUST pass before any emission
        // Use -1 for noteIdx in silence mode (no dominant note)
        final attackIdInt = _lastOnsetTriggerElapsedMs.round();
        final nowMsInt = (elapsed * 1000).round();
        final pathName = isSilenceMode ? 'SILENCE_MODE' : 'POST_MATCH_MISMATCH';
        if (!_wfDedupAllow(
          noteIdx: dominantNoteIdx ?? -1,
          attackId: attackIdInt,
          nowMs: nowMsInt,
          path: pathName,
        )) {
          // STRICT: Bail out, skip this emission entirely
        } else {
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
          if (kWrongFlashRestoreEnabled) {
            _wrongFlashEmittedThisTick = true;
          }
          _engineEmitCount++; // SESSION-038: Count engine emit

          if (kDebugMode) {
            // SESSION-042: Unified WRONG_FLASH_EMIT log with key for proof
            final key = '${dominantNoteIdx ?? -1}_$attackIdInt';
            debugPrint(
              'WRONG_FLASH_EMIT key=$key attackId=$attackIdInt nowMs=$nowMsInt '
              'noteIdx=${dominantNoteIdx ?? -1} midi=$bestWrongMidi path=$pathName',
            );
          }
        }
      } else if (!tickOk) {
        // SESSION-031: Skip because already emitted this tick (not an error)
        _engineSkipAlreadyEmittedTickCount++; // SESSION-038: Count skip
        if (kDebugMode) {
          final mode = isSilenceMode ? 'silence' : 'mismatch';
          debugPrint(
            'WRONG_FLASH_SKIP reason=already_emitted_this_tick mode=$mode midi=$bestWrongMidi '
            'conf=${bestWrongEvent.conf.toStringAsFixed(2)}',
          );
        }
      } else {
        // Log skip with reason
        // SESSION-038: Count gated skip (could be global cooldown or per-midi dedup)
        if (!globalCooldownOk) {
          _engineSkipGatedCount++;
        } else if (!perMidiDedupOk) {
          _engineSkipPerMidiDedupCount++;
        }
        if (kDebugMode) {
          final mode = isSilenceMode ? 'silence' : 'mismatch';
          debugPrint(
            'WRONG_FLASH_SKIP reason=gated mode=$mode midi=$bestWrongMidi '
            'conf=${bestWrongEvent.conf.toStringAsFixed(2)} '
            'globalCooldownOk=$globalCooldownOk perMidiDedupOk=$perMidiDedupOk',
          );
        }
      }
    } else if (bestWrongEvent != null && !silenceGateOk) {
      // Log silence gate rejection
      _engineSkipOtherCount++; // SESSION-038: Count other skip
      if (kDebugMode) {
        debugPrint(
          'WRONG_FLASH_SKIP reason=silence_gate midi=$bestWrongMidi '
          'conf=${bestWrongEvent.conf.toStringAsFixed(2)} source=${bestWrongEvent.source.name} '
          'requiredConf=$silenceModeMinConf',
        );
      }
    }

    // SESSION-047: Arbiter shadow comparison (debug-only validation)
    if (kArbiterShadowEnabled && kDebugMode) {
      _runArbiterShadow(decisions, elapsed, now);
    }

    return decisions;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SESSION-047: ARBITER SHADOW - Validate DecisionArbiter against legacy
  // ═══════════════════════════════════════════════════════════════════════════

  void _runArbiterShadow(
    List<NoteDecision> legacyDecisions,
    double elapsed,
    DateTime now,
  ) {
    final elapsedMs = elapsed * 1000.0;
    final nowMs = now.millisecondsSinceEpoch.toDouble();

    for (final legacy in legacyDecisions) {
      final idx = legacy.noteIndex;
      if (idx == null || idx < 0 || idx >= noteEvents.length) continue;

      final note = noteEvents[idx];
      // SESSION-048: Pass overrides to simulate PRE-MUTATION state
      // Legacy mutates hitNotes[idx] and _wfDedupHistory BEFORE shadow runs
      // SESSION-049: alreadyHitOverride=false for HIT+MISS (not just MISS)
      final inputs = _collectArbiterInputs(
        noteIdx: idx,
        note: note,
        elapsedMs: elapsedMs,
        nowMs: nowMs,
        alreadyHitOverride:
            (legacy.type == DecisionType.miss ||
                legacy.type == DecisionType.hit)
            ? false
            : null,
        wrongFlashEmittedThisTickOverride: false,
        wfDedupLastEmitMsOverride: -1,
      );

      final arbiterOut = _arbiter.process(inputs);

      // Map arbiter result to legacy DecisionType
      final arbiterType = switch (arbiterOut.result) {
        DecisionResult.hit => DecisionType.hit,
        DecisionResult.miss => DecisionType.miss,
        DecisionResult.wrong => DecisionType.wrongFlash,
        DecisionResult.skip => null,
        DecisionResult.ambiguous => null,
      };

      final isMatch =
          (arbiterType == legacy.type) ||
          (arbiterType == null &&
              legacy.type != DecisionType.hit &&
              legacy.type != DecisionType.miss &&
              legacy.type != DecisionType.wrongFlash);

      if (isMatch) {
        debugPrint(
          'ARBITER_SHADOW_MATCH noteIdx=$idx legacy=${legacy.type.name} '
          'arbiter=${arbiterOut.result.name} path=${arbiterOut.path}',
        );
      } else {
        debugPrint(
          'ARBITER_SHADOW_MISMATCH noteIdx=$idx legacy=${legacy.type.name} '
          'arbiter=${arbiterOut.result.name} reason=${arbiterOut.reason} '
          'path=${arbiterOut.path} gatedBy=${arbiterOut.gatedBy ?? "none"}',
        );
      }
    }
  }

  DecisionInputs _collectArbiterInputs({
    required int noteIdx,
    required NoteEvent note,
    required double elapsedMs,
    required double nowMs,
    bool? alreadyHitOverride,
    bool? wrongFlashEmittedThisTickOverride,
    int? wfDedupLastEmitMsOverride,
  }) {
    final windowStartMs = (note.start - headWindowSec) * 1000.0;
    final windowEndMs = (note.end + tailWindowSec) * 1000.0;
    final attackId = _lastOnsetTriggerElapsedMs.round();
    final wfDedupKey = '${noteIdx}_$attackId';

    // Collect best event from buffer
    ArbiterPitchEvent? bestEvent;
    double? bestDistance;
    int bestStabilityFrames = 0;
    for (final e in _events) {
      final eTms = e.tSec * 1000.0;
      if (eTms < windowStartMs || eTms > windowEndMs) continue;
      final dist = (e.midi - note.pitch).abs().toDouble();
      if (bestDistance == null || dist < bestDistance) {
        bestDistance = dist;
        bestStabilityFrames = e.stabilityFrames;
        bestEvent = ArbiterPitchEvent(
          midi: e.midi,
          conf: e.conf,
          tSec: e.tSec,
          source: _mapSourceType(e.source),
          rms: e.rms,
        );
      }
    }

    // Compute dt if we have a match
    double? candidateDtMs;
    if (bestEvent != null && bestDistance != null && bestDistance <= 3.0) {
      candidateDtMs = (bestEvent.tSec - note.start) * 1000.0;
    }

    // Check lookahead
    final isLookahead =
        bestEvent != null &&
        _isLookaheadMatch(
          detectedMidi: bestEvent.midi,
          currentNoteIdx: noteIdx,
          noteEvents: noteEvents,
          hitNotes: hitNotes,
          elapsed: elapsedMs / 1000.0,
          headWindowSec: headWindowSec,
          tailWindowSec: tailWindowSec,
          path: 'arbiter_shadow',
        );

    // wfDedup with override support for PRE-MUTATION state
    final int? wfDedupLastEmitMs;
    if (wfDedupLastEmitMsOverride != null) {
      wfDedupLastEmitMs = wfDedupLastEmitMsOverride < 0
          ? null
          : wfDedupLastEmitMsOverride;
    } else {
      wfDedupLastEmitMs = _wfDedupHistory[wfDedupKey];
    }

    // Convert DateTime fields to ms
    final lastWfAtMs = _lastWrongFlashAt?.millisecondsSinceEpoch.toDouble();
    final lastWfForMidiMs = bestEvent != null
        ? _lastWrongFlashByMidi[bestEvent.midi]?.millisecondsSinceEpoch
              .toDouble()
        : null;
    final recentHitPcMs = bestEvent != null
        ? _recentlyHitPitchClasses[bestEvent.midi % 12]?.millisecondsSinceEpoch
              .toDouble()
        : null;

    return DecisionInputs(
      elapsedMs: elapsedMs,
      noteWindowStartMs: windowStartMs,
      noteWindowEndMs: windowEndMs,
      noteIdx: noteIdx,
      expectedMidi: note.pitch,
      alreadyHit: alreadyHitOverride ?? hitNotes[noteIdx],
      bestEvent: bestEvent,
      bestDistance: bestDistance,
      matchedCandidate: null, // Simplified - no candidate fallback in shadow
      fallbackSample: null, // Simplified - no fallback sample in shadow
      onsetState: _lastOnsetState,
      lastOnsetTriggerMs: _lastOnsetTriggerElapsedMs,
      attackId: attackId,
      isWithinGracePeriod: (elapsedMs - windowStartMs) < kFallbackGracePeriodMs,
      isLookaheadMatch: isLookahead,
      wrongFlashEmittedThisTick:
          wrongFlashEmittedThisTickOverride ?? _wrongFlashEmittedThisTick,
      lastWrongFlashAtMs: lastWfAtMs,
      lastWrongFlashForMidiMs: lastWfForMidiMs,
      lastTripleFlashMs: null, // Simplified
      wfDedupLastEmitMs: wfDedupLastEmitMs,
      hitAttackIdMs: _hitAttackIdHistory[attackId],
      recentHitForDetectedPCMs: recentHitPcMs,
      clearPitchAgeMs: _lastDetectedElapsedMs > 0
          ? (elapsedMs - _lastDetectedElapsedMs * 1000.0)
          : 9999.0,
      hitDistanceThreshold: 3.0,
      dtMaxMs: kHitDtMaxMs.toDouble(),
      wrongFlashMinConf: wrongFlashMinConf,
      gracePeriodMs: kFallbackGracePeriodMs.toDouble(),
      sustainThresholdMs: kSustainWrongSuppressTriggerMs.toDouble(),
      confirmationCount: 1, // Simplified
      candidateDtMs: candidateDtMs,
      snapAllowed:
          bestEvent != null &&
          _shouldSnapToExpected(
            detectedMidi: bestEvent.midi,
            expectedMidi: note.pitch,
            conf: bestEvent.conf,
            stabilityFrames: bestStabilityFrames,
          ),
      nowMs: nowMs,
    );
  }

  PitchSourceType _mapSourceType(PitchEventSource source) {
    return switch (source) {
      PitchEventSource.trigger => PitchSourceType.trigger,
      PitchEventSource.burst => PitchSourceType.burst,
      PitchEventSource.probe => PitchSourceType.probe,
      PitchEventSource.legacy => PitchSourceType.legacy,
    };
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

/// SESSION-030: HitCandidate for dual-path HIT matching.
/// Stores suppressed events that may still be valid for HIT detection.
class HitCandidate {
  const HitCandidate({
    required this.midi,
    required this.tMs,
    required this.rms,
    required this.conf,
    required this.source,
    required this.suppressReason,
    required this.dtFromOnsetMs,
    required this.dRms,
  });

  final int midi;
  final double tMs; // elapsed time in milliseconds
  final double rms;
  final double conf;
  final PitchEventSource source;
  final String suppressReason; // 'cooldown', 'tail_falling', etc.
  final double
  dtFromOnsetMs; // time since last ONSET_TRIGGER for this pitchClass
  final double dRms; // delta RMS (for energy signal check)
}

/// SESSION-031: WrongSample for no_events_in_buffer fallback.
/// Stores recent pitch detections (including PROBE) for wrong flash fallback.
class WrongSample {
  const WrongSample({
    required this.midi,
    required this.tMs,
    required this.rms,
    required this.conf,
    required this.source,
    required this.dRms,
    required this.isTriggerOrFailsafe,
  });

  final int midi;
  final double tMs; // elapsed time in milliseconds
  final double rms;
  final double conf;
  final PitchEventSource source;
  final double dRms;
  final bool isTriggerOrFailsafe; // true if source=trigger or probe (failsafe)
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

// ============================================================================
// SESSION-021: Debug event for ring buffer
// ============================================================================
/// SESSION-021: Debug event stored in ring buffer for post-session analysis.
class DebugPitchEvent {
  const DebugPitchEvent({
    required this.timestampMs,
    required this.midi,
    required this.rms,
    required this.conf,
    required this.state,
    this.source,
    this.hz,
    this.stableFrames,
    this.heldMidi,
    this.gateOn,
    this.detectedSampleRate,
    this.forcedSampleRate,
    this.sampleRateRatio,
  });

  final double timestampMs;
  final int midi;
  final double rms;
  final double conf;
  final String
  state; // 'noteOn', 'noteOff', 'held', 'rejected', 'spike', 'stabilitySkip'
  final String? source; // 'trigger', 'burst', 'probe', 'legacy'
  final double? hz; // Detected frequency
  final int? stableFrames; // Consecutive frames with same pitchClass
  final int? heldMidi; // Currently held MIDI (from NoteTracker)
  final bool? gateOn; // Onset gate state
  final int? detectedSampleRate; // Detected sample rate from mic
  final int? forcedSampleRate; // Forced sample rate (if kForceFixedSampleRate)
  final double? sampleRateRatio; // detected/forced ratio

  @override
  String toString() {
    final srInfo = sampleRateRatio != null
        ? ' sr=$detectedSampleRate/$forcedSampleRate(${sampleRateRatio!.toStringAsFixed(3)})'
        : '';
    return 'DebugPitchEvent(t=${timestampMs.toStringAsFixed(0)}ms midi=$midi '
        'hz=${hz?.toStringAsFixed(1) ?? "n/a"} '
        'rms=${rms.toStringAsFixed(4)} conf=${conf.toStringAsFixed(2)} '
        'state=$state source=$source stable=$stableFrames$srInfo)';
  }
}
