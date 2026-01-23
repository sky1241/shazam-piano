/// Reverb profile for microphone tuning.
///
/// SESSION-016: Different acoustic environments require different settings:
/// - [low]: Dry room, close mic, minimal reverb (more reactive)
/// - [medium]: Normal room acoustics (balanced - default)
/// - [high]: Reverberant space, far mic, long tails (more anti-ghost)
enum ReverbProfile {
  /// Dry room / close mic: shorter cooldowns, faster attack detection.
  low,

  /// Normal room acoustics: balanced settings (default).
  medium,

  /// Reverberant space / far mic: stricter filtering, longer cooldowns.
  high,
}

/// Microphone tuning parameters for Practice mode.
///
/// SESSION-016: Encapsulates all tunable parameters that affect:
/// - Attack/onset detection (OnsetDetector)
/// - Note tracking/tail filtering (NoteTracker)
/// - Wrong flash gate thresholds (MicEngine)
///
/// Use [MicTuning.forProfile] to get preset values for common scenarios.
class MicTuning {
  const MicTuning({
    required this.profile,
    // Attack / onset (OnsetDetector)
    required this.emaAlpha,
    required this.onsetMinRms,
    required this.onsetDeltaAbsMin,
    required this.onsetDeltaRatioMin,
    required this.onsetCooldownMs,
    required this.attackBurstMs,
    required this.maxEvalsPerBurst,
    required this.probeEnabled,
    required this.probeIntervalMs,
    // Cooldown / anti-tail (NoteTracker)
    required this.pitchClassCooldownMs,
    required this.postHitCooldownMs,
    required this.releaseRatio,
    required this.presenceEndThreshold,
    required this.endConsecutiveFrames,
    required this.confAttackMin,
    required this.minAttackDelta,
    required this.attackMarginAbs,
    required this.attackMarginRatio,
    // Goertzel (for chord detection)
    required this.dominanceRatioGoertzel,
    // Auto-baseline noise floor
    required this.autoNoiseBaseline,
    required this.baselineMs,
    required this.noiseFloorMultiplier,
    required this.noiseFloorMargin,
    // Sustain filter
    required this.sustainFilterMs,
    // SESSION-022 V1: Re-attack, silence release, and TTL (NoteTracker)
    this.reattackDeltaThreshold = 0.025,
    this.minInterOnsetMs = 80.0,
    this.silenceRmsThreshold = 0.015,
    this.silenceFramesForRelease = 6,
    this.maxHoldMs = 1200.0,
  });

  /// The profile this tuning was created from.
  final ReverbProfile profile;

  // ─────────────────────────────────────────────────────────────────────────
  // ATTACK / ONSET (OnsetDetector parameters)
  // ─────────────────────────────────────────────────────────────────────────

  /// EMA smoothing factor (0 = no smoothing, 1 = instant).
  /// Lower = slower adaptation, more stable. Higher = faster, more reactive.
  final double emaAlpha;

  /// Minimum RMS to consider an onset.
  /// Lower = more sensitive to soft attacks. Higher = filters weak signals.
  final double onsetMinRms;

  /// Minimum absolute delta (rmsNow - rmsEma) for onset.
  final double onsetDeltaAbsMin;

  /// Minimum ratio (rmsNow / rmsEma) for onset.
  final double onsetDeltaRatioMin;

  /// Cooldown after onset before allowing another onset (ms).
  final double onsetCooldownMs;

  /// Duration of attack burst window after onset (ms).
  final double attackBurstMs;

  /// Maximum pitch evaluations allowed per burst.
  final int maxEvalsPerBurst;

  /// Enable probe failsafe for missed soft onsets.
  final bool probeEnabled;

  /// Interval for probe failsafe when no onset detected (ms).
  final double probeIntervalMs;

  // ─────────────────────────────────────────────────────────────────────────
  // COOLDOWN / ANTI-TAIL (NoteTracker parameters)
  // ─────────────────────────────────────────────────────────────────────────

  /// Cooldown after attack before allowing another for same pitchClass (ms).
  final double pitchClassCooldownMs;

  /// Extra cooldown after HIT registration (prevents tail re-attack) (ms).
  final double postHitCooldownMs;

  /// Release ratio for END detection: rms < peakRms * releaseRatio.
  final double releaseRatio;

  /// Presence threshold for END detection (confidence below this = end).
  final double presenceEndThreshold;

  /// Consecutive frames below threshold to trigger END.
  final int endConsecutiveFrames;

  /// Minimum confidence to allow attack.
  final double confAttackMin;

  /// Minimum positive delta for attack (strictly rising edge).
  final double minAttackDelta;

  /// Absolute margin above EMA for attack gate.
  final double attackMarginAbs;

  /// Relative margin (ratio of EMA) for attack gate.
  final double attackMarginRatio;

  // ─────────────────────────────────────────────────────────────────────────
  // GOERTZEL (for chord detection)
  // ─────────────────────────────────────────────────────────────────────────

  /// Dominance ratio for Goertzel chord detection.
  /// Higher = stricter (needs clearer fundamental).
  final double dominanceRatioGoertzel;

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO-BASELINE NOISE FLOOR
  // ─────────────────────────────────────────────────────────────────────────

  /// Enable automatic noise baseline detection.
  final bool autoNoiseBaseline;

  /// Duration of baseline measurement period (ms).
  final int baselineMs;

  /// Multiplier for noise floor to get dynamic onset threshold.
  /// dynamicOnsetMinRms = max(onsetMinRms, noiseFloor * multiplier + margin)
  final double noiseFloorMultiplier;

  /// Margin added to noise floor for dynamic onset threshold.
  final double noiseFloorMargin;

  // ─────────────────────────────────────────────────────────────────────────
  // SUSTAIN FILTER
  // ─────────────────────────────────────────────────────────────────────────

  /// Time to ignore recently hit pitch classes (sustain/reverb filtering).
  final double sustainFilterMs;

  // ─────────────────────────────────────────────────────────────────────────
  // SESSION-022 V1: RE-ATTACK, SILENCE RELEASE, AND TTL (NoteTracker)
  // ─────────────────────────────────────────────────────────────────────────

  /// SESSION-022 V1: Minimum dRms jump to force re-attack on a held note.
  /// Lowered from 0.05 to 0.025 to catch more repeated strikes.
  final double reattackDeltaThreshold;

  /// SESSION-022 V1: Minimum time between re-attacks (ms).
  /// Prevents reverb/tail from triggering false re-attacks.
  final double minInterOnsetMs;

  /// SESSION-022 V1: RMS threshold for silence detection.
  /// If rmsNow < this for N consecutive frames, force release.
  final double silenceRmsThreshold;

  /// SESSION-022 V1: Consecutive silent frames to trigger hard release.
  final int silenceFramesForRelease;

  /// SESSION-022 V1: Maximum hold duration before auto-release (ms).
  /// Only kicks in if silence-based release didn't trigger.
  final double maxHoldMs;

  // ─────────────────────────────────────────────────────────────────────────
  // FACTORY: Create tuning for a given profile
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a [MicTuning] for the given [ReverbProfile].
  ///
  /// Presets are based on current baseline values from the codebase:
  /// - OnsetDetector: emaAlpha=0.15, onsetMinRms=0.008, etc.
  /// - NoteTracker: cooldownMs=160, confAttackMin=0.70, etc.
  factory MicTuning.forProfile(ReverbProfile profile) {
    switch (profile) {
      case ReverbProfile.low:
        // DRY ROOM / CLOSE MIC: More reactive, shorter cooldowns
        return const MicTuning(
          profile: ReverbProfile.low,
          // Attack / onset - MORE REACTIVE
          emaAlpha: 0.20, // Faster adaptation (was 0.15)
          onsetMinRms: 0.006, // More sensitive (was 0.008)
          onsetDeltaAbsMin: 0.003, // Same as baseline
          onsetDeltaRatioMin: 1.5, // Lower ratio needed (was 1.8)
          onsetCooldownMs: 120.0, // Shorter cooldown (was 180)
          attackBurstMs: 150.0, // Shorter burst (was 200)
          maxEvalsPerBurst: 3, // Same
          probeEnabled: true,
          probeIntervalMs: 250.0, // Faster probes (was 300)
          // Cooldown / anti-tail - FASTER RELEASE
          pitchClassCooldownMs: 120.0, // Shorter (was 160)
          postHitCooldownMs: 150.0, // Shorter (was 200)
          releaseRatio: 0.35, // Faster release (was 0.40)
          presenceEndThreshold: 0.25, // Lower threshold (was 0.30)
          endConsecutiveFrames: 3, // Fewer frames (was 4)
          confAttackMin: 0.65, // Slightly lower (was 0.70)
          minAttackDelta: 0.002, // More sensitive (was 0.003)
          attackMarginAbs: 0.005, // Lower margin (was 0.006)
          attackMarginRatio: 0.20, // Lower ratio (was 0.25)
          // Goertzel
          dominanceRatioGoertzel: 1.8, // Same as baseline
          // Auto-baseline
          autoNoiseBaseline: true,
          baselineMs: 1000, // 1 second baseline
          noiseFloorMultiplier: 3.0,
          noiseFloorMargin: 0.003,
          // Sustain filter - SHORTER
          sustainFilterMs: 400.0, // Shorter (was 600)
        );

      case ReverbProfile.medium:
        // ─────────────────────────────────────────────────────────────────────
        // PATCH LEDGER: medium = exact baseline values from codebase
        // Each param has: baseline(old): <value> (source: <file>:<line>)
        // ─────────────────────────────────────────────────────────────────────
        return const MicTuning(
          profile: ReverbProfile.medium,

          // === ONSET DETECTOR (onset_detector.dart) ===
          // baseline(old): 0.15 (source: onset_detector.dart:37 emaAlpha default)
          emaAlpha: 0.15,
          // baseline(old): 0.008 (source: onset_detector.dart:38 onsetMinRms default)
          onsetMinRms: 0.008,
          // baseline(old): 0.004 (source: onset_detector.dart:39 onsetDeltaAbsMin default)
          onsetDeltaAbsMin: 0.004,
          // baseline(old): 1.8 (source: onset_detector.dart:40 onsetDeltaRatioMin default)
          onsetDeltaRatioMin: 1.8,
          // baseline(old): 180 (source: onset_detector.dart:41 onsetCooldownMs default)
          onsetCooldownMs: 180.0,
          // baseline(old): 200 (source: onset_detector.dart:42 attackBurstMs default)
          attackBurstMs: 200.0,
          // baseline(old): 3 (source: onset_detector.dart:43 maxEvalsPerBurst default)
          maxEvalsPerBurst: 3,
          // baseline(old): true (source: onset_detector.dart:45 probeEnabled default)
          probeEnabled: true,
          // baseline(old): 300 (source: onset_detector.dart:44 probeIntervalMs default)
          probeIntervalMs: 300.0,

          // === NOTE TRACKER (note_tracker.dart) ===
          // baseline(old): 160.0 (source: note_tracker.dart:59 cooldownMs default)
          pitchClassCooldownMs: 160.0,
          // baseline(old): 200.0 (source: note_tracker.dart:60 postHitCooldownMs default)
          postHitCooldownMs: 200.0,
          // baseline(old): 0.40 (source: note_tracker.dart:62 releaseRatio default)
          releaseRatio: 0.40,
          // baseline(old): 0.30 (source: note_tracker.dart:64 presenceEndThreshold default)
          presenceEndThreshold: 0.30,
          // baseline(old): 4 (source: note_tracker.dart:65 endConsecutiveFrames default)
          endConsecutiveFrames: 4,
          // baseline(old): 0.70 (source: note_tracker.dart:53 confAttackMin default - HOTFIX P4)
          confAttackMin: 0.70,
          // baseline(old): 0.003 (source: note_tracker.dart:52 minAttackDelta default)
          minAttackDelta: 0.003,
          // baseline(old): 0.006 (source: note_tracker.dart:50 attackMarginAbs default)
          attackMarginAbs: 0.006,
          // baseline(old): 0.25 (source: note_tracker.dart:51 attackMarginRatio default)
          attackMarginRatio: 0.25,

          // === PRACTICE PITCH ROUTER ===
          // baseline(old): ~1.8 (source: practice_pitch_router.dart - goertzel dominance)
          dominanceRatioGoertzel: 1.8,

          // === AUTO-BASELINE (new in SESSION-016) ===
          // No baseline(old) - these are new params
          autoNoiseBaseline: true,
          baselineMs: 1500,
          noiseFloorMultiplier: 4.0,
          noiseFloorMargin: 0.004,

          // === MIC ENGINE (mic_engine.dart) ===
          // baseline(old): 600.0 (source: mic_engine.dart:61 sustainFilterMs default)
          sustainFilterMs: 600.0,
        );

      case ReverbProfile.high:
        // REVERBERANT SPACE / FAR MIC: Stricter filtering, longer cooldowns
        return const MicTuning(
          profile: ReverbProfile.high,
          // Attack / onset - STRICTER
          emaAlpha: 0.10, // Slower adaptation (was 0.15)
          onsetMinRms: 0.012, // Higher threshold (was 0.008)
          onsetDeltaAbsMin: 0.006, // Higher delta needed (was 0.004)
          onsetDeltaRatioMin: 2.2, // Higher ratio needed (was 1.8)
          onsetCooldownMs: 250.0, // Longer cooldown (was 180)
          attackBurstMs: 250.0, // Longer burst (was 200)
          maxEvalsPerBurst: 4, // More evals to find stable pitch
          probeEnabled: true,
          probeIntervalMs: 400.0, // Slower probes (was 300)
          // Cooldown / anti-tail - MORE CONSERVATIVE
          pitchClassCooldownMs: 220.0, // Longer (was 160)
          postHitCooldownMs: 300.0, // Longer (was 200)
          releaseRatio: 0.50, // Slower release (was 0.40)
          presenceEndThreshold: 0.40, // Higher threshold (was 0.30)
          endConsecutiveFrames: 6, // More frames (was 4)
          confAttackMin: 0.78, // Higher confidence (was 0.70)
          minAttackDelta: 0.005, // Higher delta (was 0.003)
          attackMarginAbs: 0.008, // Higher margin (was 0.006)
          attackMarginRatio: 0.35, // Higher ratio (was 0.25)
          // Goertzel
          dominanceRatioGoertzel: 2.0, // Higher for clearer detection
          // Auto-baseline
          autoNoiseBaseline: true,
          baselineMs: 2000, // 2 second baseline
          noiseFloorMultiplier: 5.0,
          noiseFloorMargin: 0.006,
          // Sustain filter - LONGER
          sustainFilterMs: 800.0, // Longer (was 600)
        );
    }
  }

  /// Default tuning (medium profile).
  static const MicTuning defaultTuning = MicTuning(
    profile: ReverbProfile.medium,
    emaAlpha: 0.15,
    onsetMinRms: 0.008,
    onsetDeltaAbsMin: 0.004,
    onsetDeltaRatioMin: 1.8,
    onsetCooldownMs: 180.0,
    attackBurstMs: 200.0,
    maxEvalsPerBurst: 3,
    probeEnabled: true,
    probeIntervalMs: 300.0,
    pitchClassCooldownMs: 160.0,
    postHitCooldownMs: 200.0,
    releaseRatio: 0.40,
    presenceEndThreshold: 0.30,
    endConsecutiveFrames: 4,
    confAttackMin: 0.70,
    minAttackDelta: 0.003,
    attackMarginAbs: 0.006,
    attackMarginRatio: 0.25,
    dominanceRatioGoertzel: 1.8,
    autoNoiseBaseline: true,
    baselineMs: 1500,
    noiseFloorMultiplier: 4.0,
    noiseFloorMargin: 0.004,
    sustainFilterMs: 600.0,
  );

  @override
  String toString() {
    return 'MicTuning(profile=$profile, onsetMinRms=$onsetMinRms, '
        'cooldown=$pitchClassCooldownMs, releaseRatio=$releaseRatio, '
        'confAttackMin=$confAttackMin)';
  }
}
