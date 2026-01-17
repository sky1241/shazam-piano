// Device Calibration Profiles for Practice Mode
//
// This file contains calibration settings for different device tiers.
// These values are derived from real-world testing sessions.
//
// SESSION-009 (2026-01-17): Initial calibration from low-end device testing
// - Device: ~120 CHF Android phone
// - Connection: 4G
// - Observed latency: ~500-800ms from note hit to detection
// - False wrong notes: 3 (caused by sustain/reverb of previous notes)

/// Device tier classification
enum DeviceTier {
  /// Budget phones (~100-200 CHF)
  /// Characteristics: slower CPU, basic microphone, higher audio latency
  lowEnd,

  /// Mid-range phones (~300-500 CHF)
  /// Characteristics: decent performance, reasonable audio latency
  midRange,

  /// Flagship phones (~800+ CHF)
  /// Characteristics: fast CPU, quality microphone, low audio latency
  highEnd,
}

/// Calibration profile for practice mode
class PracticeCalibration {
  const PracticeCalibration({
    // Timing windows
    required this.headWindowSec,
    required this.tailWindowSec,
    required this.micLatencyMs,

    // Pitch detection
    required this.clarityThreshold,
    required this.minConfForPitch,
    required this.minConfForWrong,
    required this.absMinRms,

    // Anti-ghost/sustain
    required this.sustainFilterMs,
    required this.eventDebounceSec,
    required this.wrongFlashCooldownSec,

    // Stability
    required this.minStabilityFrames,
    required this.pitchWindowSize,
    required this.minPitchIntervalMs,
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING WINDOWS
  // ═══════════════════════════════════════════════════════════════════════════

  /// How early before note.start we accept a hit (seconds)
  /// Larger = more forgiving for early plays
  final double headWindowSec;

  /// How late after note.end we accept a hit (seconds)
  /// Larger = more forgiving for late plays (compensates for mic latency)
  final double tailWindowSec;

  /// Estimated microphone latency in milliseconds
  /// Used by PracticeController for miss timeout calculation
  final double micLatencyMs;

  // ═══════════════════════════════════════════════════════════════════════════
  // PITCH DETECTION THRESHOLDS
  // ═══════════════════════════════════════════════════════════════════════════

  /// MPM clarity threshold (0.0-1.0)
  /// Higher = stricter pitch detection, fewer false positives
  /// Lower = more sensitive, may detect harmonics/noise
  final double clarityThreshold;

  /// Minimum confidence to accept a pitch detection at all
  /// Below this, the detection is ignored (likely noise)
  final double minConfForPitch;

  /// Minimum confidence to consider a note as "wrong"
  /// Avoids false wrong-notes from weak noise detections
  final double minConfForWrong;

  /// Absolute minimum RMS amplitude to process audio
  /// Filters out background noise when no note is playing
  final double absMinRms;

  // ═══════════════════════════════════════════════════════════════════════════
  // ANTI-GHOST / SUSTAIN FILTERING
  // ═══════════════════════════════════════════════════════════════════════════

  /// Time (ms) after a note is hit to ignore its pitch-class for wrong detection
  /// Prevents sustain/reverb of previous note from triggering false "wrong"
  /// SESSION-009: Main cause of 3 false wrong notes
  final double sustainFilterMs;

  /// Minimum time between two pitch events of same MIDI note (seconds)
  /// Prevents rapid-fire duplicate events from same keystroke
  final double eventDebounceSec;

  /// Cooldown between wrong flash events (seconds)
  /// Prevents spamming wrong feedback
  final double wrongFlashCooldownSec;

  // ═══════════════════════════════════════════════════════════════════════════
  // STABILITY & PERFORMANCE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Minimum consecutive frames a pitch must be stable to count
  /// Higher = more reliable but slower response
  final int minStabilityFrames;

  /// Audio samples for pitch detection window
  /// Larger = more accurate pitch, higher latency
  final int pitchWindowSize;

  /// Minimum interval between pitch detections (ms)
  /// Prevents CPU overload on low-end devices
  final int minPitchIntervalMs;

  // ═══════════════════════════════════════════════════════════════════════════
  // FACTORY CONSTRUCTORS FOR DEVICE TIERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// LOW-END DEVICE PROFILE (Session-009 baseline)
  ///
  /// Optimized for:
  /// - Budget phones (~100-200 CHF)
  /// - High audio latency (~500-800ms observed)
  /// - Basic microphones with noise/harmonic issues
  ///
  /// Key adjustments:
  /// - Larger tail window to compensate for latency
  /// - Longer sustain filter to ignore reverb
  /// - Higher confidence thresholds to reduce false positives
  /// - Slower pitch interval to reduce CPU load
  factory PracticeCalibration.lowEnd() {
    return const PracticeCalibration(
      // Timing: very forgiving windows for high latency
      headWindowSec: 0.15, // 150ms early tolerance
      tailWindowSec: 0.60, // 600ms late tolerance (SESSION-009: was 0.45)
      micLatencyMs: 200.0, // Assume 200ms mic latency (SESSION-009: was 100)

      // Pitch detection: stricter to reduce false positives
      clarityThreshold: 0.82, // SESSION-009: increased from 0.80
      minConfForPitch: 0.45, // SESSION-009: increased from 0.40
      minConfForWrong: 0.35, // SESSION-009: increased from 0.25

      // RMS: slightly higher to filter phone mic noise
      absMinRms: 0.0012, // SESSION-009: increased from 0.0008

      // Anti-ghost: aggressive sustain filtering
      sustainFilterMs: 600.0, // SESSION-009: NEW - ignore previous note for 600ms
      eventDebounceSec: 0.08, // 80ms debounce (SESSION-009: was 0.05)
      wrongFlashCooldownSec: 0.25, // 250ms cooldown (SESSION-009: was 0.15)

      // Stability: prioritize reliability over speed
      minStabilityFrames: 1, // Keep at 1 (piano needs fast response)
      pitchWindowSize: 2048, // Standard buffer
      minPitchIntervalMs: 50, // 50ms between detections (SESSION-009: was 40)
    );
  }

  /// MID-RANGE DEVICE PROFILE
  ///
  /// Optimized for:
  /// - Mid-tier phones (~300-500 CHF)
  /// - Moderate audio latency (~200-400ms)
  /// - Decent microphones
  factory PracticeCalibration.midRange() {
    return const PracticeCalibration(
      // Timing: moderate windows
      headWindowSec: 0.12,
      tailWindowSec: 0.45,
      micLatencyMs: 150.0,

      // Pitch detection: balanced
      clarityThreshold: 0.80,
      minConfForPitch: 0.40,
      minConfForWrong: 0.30,

      // RMS: standard
      absMinRms: 0.0010,

      // Anti-ghost: moderate filtering
      sustainFilterMs: 400.0,
      eventDebounceSec: 0.05,
      wrongFlashCooldownSec: 0.18,

      // Stability: balanced
      minStabilityFrames: 1,
      pitchWindowSize: 2048,
      minPitchIntervalMs: 40,
    );
  }

  /// HIGH-END DEVICE PROFILE
  ///
  /// Optimized for:
  /// - Flagship phones (~800+ CHF)
  /// - Low audio latency (~100-200ms)
  /// - Quality microphones
  factory PracticeCalibration.highEnd() {
    return const PracticeCalibration(
      // Timing: tighter windows for precision
      headWindowSec: 0.10,
      tailWindowSec: 0.35,
      micLatencyMs: 100.0,

      // Pitch detection: can be more sensitive
      clarityThreshold: 0.78,
      minConfForPitch: 0.35,
      minConfForWrong: 0.25,

      // RMS: lower threshold (better mic = less noise)
      absMinRms: 0.0008,

      // Anti-ghost: lighter filtering (better mic isolation)
      sustainFilterMs: 300.0,
      eventDebounceSec: 0.04,
      wrongFlashCooldownSec: 0.12,

      // Stability: faster response
      minStabilityFrames: 1,
      pitchWindowSize: 2048,
      minPitchIntervalMs: 35,
    );
  }

  /// Get calibration for a specific device tier
  factory PracticeCalibration.forTier(DeviceTier tier) {
    switch (tier) {
      case DeviceTier.lowEnd:
        return PracticeCalibration.lowEnd();
      case DeviceTier.midRange:
        return PracticeCalibration.midRange();
      case DeviceTier.highEnd:
        return PracticeCalibration.highEnd();
    }
  }

  /// Current default profile (can be changed based on device detection)
  /// SESSION-009: Using lowEnd as baseline until auto-detection is implemented
  static PracticeCalibration get defaultProfile => PracticeCalibration.lowEnd();
}
