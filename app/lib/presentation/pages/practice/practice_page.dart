import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ads/admob_ads.dart';
import '../../../core/config/build_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/strings_fr.dart';
import '../../../core/debug/debug_job_guard.dart';
import '../../../core/practice/model/practice_models.dart';
import '../../../core/practice/scoring/practice_scoring_engine.dart';
import '../../../core/practice/matching/note_matcher.dart';
import '../../../core/practice/debug/practice_debug_logger.dart';
import '../../../domain/entities/level_result.dart';
import '../../widgets/practice_keyboard.dart';
import '../../widgets/banner_ad_placeholder.dart';
import 'controller/practice_controller.dart';
import 'pitch_detector.dart';
import 'mic_engine.dart' as mic;

part 'parts/falling_notes_painter.part.dart';
part 'parts/practice_models.part.dart';
part 'parts/practice_note_utils.part.dart';
part 'parts/practice_mic_debug.part.dart';
part 'parts/practice_ui_video.part.dart';
part 'parts/practice_ui_stage.part.dart';
part 'parts/practice_video_logic.part.dart';
part 'parts/practice_input_logic.part.dart';
part 'parts/practice_notes_logic.part.dart';
part 'parts/practice_state_base.part.dart';
part 'parts/practice_lifecycle.part.dart';

/// Pitch comparator for microphone mode (wraps MicEngine logic)
/// P0 SESSION4 FIX: Octave shifts DISABLED (harmonics prevention)
///
/// Matches pitch class (midi % 12) and accepts direct match ≤3 semitones
/// (real piano micro-detuning tolerance)
bool micPitchComparator(int detected, int expected) {
  final detectedPC = detected % 12;
  final expectedPC = expected % 12;

  // Reject if pitch class mismatch
  if (detectedPC != expectedPC) return false;

  // Test direct match ONLY (no octave shifts)
  return (detected - expected).abs() <= 3;
}

/// Pitch comparator for MIDI mode (wraps existing practice_page.dart logic)
///
/// Accepts if distance ≤ 1 semitone
bool midiPitchComparator(int detected, int expected) {
  return (detected - expected).abs() <= 1;
}

@visibleForTesting
bool isVideoEnded(Duration position, Duration duration) {
  final endThreshold = duration - const Duration(milliseconds: 100);
  final safeThreshold = endThreshold.isNegative ? Duration.zero : endThreshold;
  return position >= safeThreshold;
}

enum NotesSource { json, midi, none }

@visibleForTesting
Set<int> resolveTargetNotesForTest({
  required List<int> pitches,
  required List<double> starts,
  required List<double> ends,
  required List<bool> hitNotes,
  required double? elapsedSec,
  required double windowTailSec,
  required double chordToleranceSec,
}) {
  if (pitches.isEmpty) {
    return <int>{};
  }
  final active = <int>{};
  double? earliestUpcomingStart;

  for (var i = 0; i < pitches.length; i++) {
    final wasHit = i < hitNotes.length && hitNotes[i];
    if (wasHit) {
      continue;
    }
    final start = starts[i];
    final end = ends[i];
    if (elapsedSec != null &&
        elapsedSec >= start &&
        elapsedSec <= end + windowTailSec) {
      active.add(pitches[i]);
      continue;
    }
    if (elapsedSec == null || elapsedSec < start) {
      if (earliestUpcomingStart == null || start < earliestUpcomingStart) {
        earliestUpcomingStart = start;
      }
    }
  }

  if (active.isNotEmpty) {
    return active;
  }
  if (earliestUpcomingStart == null) {
    return <int>{};
  }

  final nextChord = <int>{};
  for (var i = 0; i < pitches.length; i++) {
    final wasHit = i < hitNotes.length && hitNotes[i];
    if (wasHit) {
      continue;
    }
    if ((starts[i] - earliestUpcomingStart).abs() <= chordToleranceSec) {
      nextChord.add(pitches[i]);
    }
  }

  return nextChord;
}

class NormalizedNotesDebug {
  final List<List<num>> events;
  final int totalCount;
  final int dedupedCount;
  final int filteredCount;

  const NormalizedNotesDebug({
    required this.events,
    required this.totalCount,
    required this.dedupedCount,
    required this.filteredCount,
  });
}

@visibleForTesting
NormalizedNotesDebug normalizeNoteEventsForTest({
  required List<int> pitches,
  required List<double> starts,
  required List<double> ends,
  required int firstKey,
  required int lastKey,
  double epsilonSec = 0.001,
}) {
  final events = <_NoteEvent>[];
  for (var i = 0; i < pitches.length; i++) {
    events.add(
      _NoteEvent(
        pitch: pitches[i],
        start: i < starts.length ? starts[i] : 0.0,
        end: i < ends.length ? ends[i] : 0.0,
      ),
    );
  }
  final normalized = _normalizeEventsInternal(
    events: events,
    firstKey: firstKey,
    lastKey: lastKey,
    epsilonSec: epsilonSec,
  );
  final serialized = normalized.events
      .map((e) => <num>[e.pitch, e.start, e.end])
      .toList();
  return NormalizedNotesDebug(
    events: serialized,
    totalCount: normalized.totalCount,
    dedupedCount: normalized.dedupedCount,
    filteredCount: normalized.filteredCount,
  );
}

@visibleForTesting
double? effectiveElapsedForTest({
  required bool isPracticeRunning,
  required double? videoPosSec,
  required double? practiceClockSec,
  required double videoSyncOffsetSec,
}) {
  if (!isPracticeRunning) {
    return null;
  }
  if (videoPosSec != null) {
    return videoPosSec + videoSyncOffsetSec;
  }
  return practiceClockSec;
}

/// Maps countdown real time to synthetic elapsed time for falling notes.
///
/// During countdown (silent lead-in before playback):
/// - Real countdown time: [0..leadInSec]
/// - Synthetic elapsed: [-leadInSec..0]
///
/// This ensures first notes always spawn from top (y≈0) when countdown starts.
/// The mapping creates a 1:1 ratio (ratio=1.0) between countdown duration and
/// synthetic elapsed progression, preventing velocity compression.
///
/// At t=0: synthetic = -leadInSec (notes spawn at top, y≈0)
/// At t=leadInSec: synthetic = 0 (note hits keyboard, playback starts)
/// Clamped to prevent negative synthetic for t < 0.
/// FIXED VERSION - No fallLeadSec parameter
@visibleForTesting
double syntheticCountdownElapsedForTest({
  required double elapsedSinceCountdownStartSec,
  required double leadInSec,
}) {
  if (leadInSec <= 0) {
    return 0.0;
  }
  // FIX D2: Map [0, leadInSec] → [-leadInSec, 0] to ensure ratio=1.0
  // Notes must fall during the ENTIRE countdown duration
  // This prevents velocity compression and ensures notes spawn at top
  final progress = (elapsedSinceCountdownStartSec / leadInSec).clamp(0.0, 1.0);
  final syntheticElapsed = -leadInSec + (progress * leadInSec);
  return syntheticElapsed;
}

// FEATURE A: Lead-in Countdown state machine
enum _PracticeState {
  idle, // Before play is pressed
  countdown, // Playing lead-in (no audio, no mic)
  running, // Normal practice (audio + mic active)
}

class PracticePage extends ConsumerStatefulWidget {
  final LevelResult level;
  final bool forcePreview;
  final bool isTest;

  const PracticePage({
    super.key,
    required this.level,
    this.forcePreview = false,
    this.isTest = false,
  });

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

// ══════════════════════════════════════════════════════════════════════════
// Top-level constants (moved from class to avoid static member qualification)
// ══════════════════════════════════════════════════════════════════════════
const double _practiceLeadInSec = 1.5;
const int _antiSpamHitMs = 200;
const int _antiSpamWrongMs = 500;
const double _fallbackLatencyMs = 100.0;
const double _fallLeadSec = 2.0;
const double _fallTailSec = 0.6;
const double _targetWindowTailSec = 0.4;
const double _targetWindowHeadSec = 0.30;
const double _targetChordToleranceSec = 0.03;
const double _videoSyncOffsetSec = -0.06;
const double _mergeEventOverlapToleranceSec = 0.05;
const double _mergeEventGapToleranceSec = 0.08;
const Duration _successFlashDuration = Duration(milliseconds: 200);
const Duration _devTapWindow = Duration(seconds: 2);
const int _devTapTarget = 5;
const double _videoCropFactor = 0.65;
const Duration _recentHitWindow = Duration(milliseconds: 800);
const int _defaultFirstKey = 34; // A#1
const int _defaultLastKey = 96; // C7
const int _rangeMargin = 2;
const double _minNoteDurationSec = 0.03;
const double _maxNoteDurationFallbackSec = 10.0;
const double _dedupeToleranceSec = 0.001;
const double _videoDurationToleranceSec = 0.25;
const List<int> _blackKeys = [1, 3, 6, 8, 10]; // C#, D#, F#, G#, A#

class _PracticePageState extends _PracticePageStateBase
    with
        _PracticeMicDebugMixin,
        _PracticeUiVideoMixin,
        _PracticeUiStageMixin,
        _PracticeVideoLogicMixin,
        _PracticeInputLogicMixin,
        _PracticeNotesLogicMixin,
        _PracticeLifecycleMixin {
  @override
  Widget build(BuildContext context) {
    // FEATURE A: Update countdown every frame
    _updateCountdown();
    assert(() {
      _overlayBuiltInBuild = false;
      return true;
    }());
    // BUG 1 FIX: Removed instructionText variables (not needed anymore)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: GestureDetector(
          onTap: kDebugMode ? _handleDevHudTap : null,
          behavior: HitTestBehavior.translucent,
          child: Text('Practice - ${widget.level.name}'),
        ),
        actions: [
          // PATCH: Hide play/stop from AppBar (single entrypoint: centered CTA)
          // Only show in debug mode for testing
          if (kDebugMode)
            IconButton(
              icon: Icon(
                _practiceRunning ? Icons.stop : Icons.play_arrow,
                color: AppColors.primary,
              ),
              onPressed: _togglePractice,
              tooltip: '[DEBUG] Play/Stop',
            ),
          if (kDebugMode && _devHudEnabled)
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Diagnose',
              onPressed: _showDiagnostics,
            ),
        ],
      ),
      // FIX BUG 3: Replace banner with transparent spacer during practice/countdown
      // to prevent AdWorker blocking main thread while maintaining stable layout height
      bottomNavigationBar:
          (_practiceRunning || _practiceState == _PracticeState.countdown)
          ? const SizedBox(
              height: 50.0, // Match AdSize.banner.height to preserve layout
              child:
                  SizedBox.shrink(), // FIX BUG CRITIQUE #3: Zero-cost const widget
            )
          : const BannerAdPlaceholder(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final horizontalPadding = _practiceHorizontalPadding(maxWidth);
          final availableWidth = max(0.0, maxWidth - (horizontalPadding * 2));
          _lastLayoutMaxWidth = availableWidth;
          final layout = _computeKeyboardLayout(availableWidth);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: AppConstants.spacing8,
                ),
                child: _buildTopStatsLine(),
              ),
              _buildMicDebugHud(horizontalPadding: horizontalPadding),
              const SizedBox(height: AppConstants.spacing16),
              if (!_practiceRunning && _practiceState == _PracticeState.idle)
                // PATCH: Centered Play CTA overlay (only when NOT running AND idle)
                // FIX: Also check _practiceState to prevent double rendering during countdown
                Expanded(
                  child: Stack(
                    children: [
                      // Still render video/keyboard/overlay in background
                      // but show Play CTA on top
                      Opacity(
                        opacity: 0.3, // Dim the background
                        child: _buildPracticeContent(
                          layout: layout,
                          horizontalPadding: horizontalPadding,
                        ),
                      ),
                      // Play CTA overlay
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _togglePractice,
                              icon: const Icon(Icons.play_arrow, size: 32),
                              label: const Text(
                                'Play',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 20,
                                ),
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Appuie sur Play pour jouer',
                              style: AppTextStyles.body.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
              // When running: show practice content (text "ECOUTE LA NOTE" supprimé - BUG 1)
              ...[
                // BUG 1 FIX: Removed "ECOUTE LA NOTE" text (pollution visuelle)
                if (_practiceRunning && _micDisabled && !_useMidi)
                  Padding(
                    padding: const EdgeInsets.only(top: AppConstants.spacing4),
                    child: Center(
                      child: Text(
                        'Micro desactive',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                if (_showMicPermissionFallback) _buildMicPermissionFallback(),
                const SizedBox(height: AppConstants.spacing12),
                Expanded(
                  child: _buildPracticeContent(
                    layout: layout,
                    horizontalPadding: horizontalPadding,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  double _practiceHorizontalPadding(double screenWidth) {
    return screenWidth < 360 ? AppConstants.spacing8 : AppConstants.spacing16;
  }

  @override
  double _currentAvailableWidth() {
    if (_lastLayoutMaxWidth > 0) {
      return _lastLayoutMaxWidth;
    }
    return 0.0;
  }

  // _buildPracticeContent, _buildTopStatsLine, _buildMicPermissionFallback,
  // _buildPracticeStage, _buildKeyboardWithSizes, _buildNotesStatus
  // are provided by _PracticeUiStageMixin

  int? _normalizeToKeyboardRange(int? note) {
    if (note == null) return null;
    if (note < _displayFirstKey || note > _displayLastKey) return null;
    return note;
  }

  @override
  Set<int> _resolveTargetNotes(double? elapsedSec) {
    if (_noteEvents.isEmpty) {
      return <int>{};
    }
    final active = <int>{};
    double? earliestUpcomingStart;

    for (var i = 0; i < _noteEvents.length; i++) {
      final wasHit = i < _hitNotes.length && _hitNotes[i];
      if (wasHit) {
        continue;
      }
      final note = _noteEvents[i];
      if (elapsedSec != null &&
          elapsedSec >= note.start &&
          elapsedSec <= note.end + _targetWindowTailSec) {
        active.add(note.pitch);
        continue;
      }
      if (elapsedSec == null || elapsedSec < note.start) {
        if (earliestUpcomingStart == null ||
            note.start < earliestUpcomingStart) {
          earliestUpcomingStart = note.start;
        }
      }
    }

    if (active.isNotEmpty) {
      return active;
    }
    if (earliestUpcomingStart == null) {
      return <int>{};
    }

    final nextChord = <int>{};
    for (var i = 0; i < _noteEvents.length; i++) {
      final wasHit = i < _hitNotes.length && _hitNotes[i];
      if (wasHit) {
        continue;
      }
      final note = _noteEvents[i];
      if ((note.start - earliestUpcomingStart).abs() <=
          _targetChordToleranceSec) {
        nextChord.add(note.pitch);
      }
    }

    return nextChord;
  }

  // PATCH: Compute "impact notes" = notes currently active (touching keyboard)
  // These are notes where: start <= elapsedSec <= end (with no preview tail)
  // Used for: keyboard highlight color + wrongFlash gating
  @override
  Set<int> _computeImpactNotes({double? elapsedSec}) {
    final effective = elapsedSec ?? _effectiveElapsedSec();
    if (effective == null) {
      return <int>{};
    }

    final impact = <int>{};
    for (final note in _noteEvents) {
      // Impact: note is currently active (no preview, no tail)
      if (effective >= note.start && effective <= note.end) {
        impact.add(note.pitch);
      }
    }
    return impact;
  }

  @override
  Set<int> _uiTargetNotes({double? elapsedSec}) {
    // PATCH: Use _impactNotes (no preview) instead of nextChord
    // Keyboard highlights ONLY when notes are actually touching bottom (active)
    final effective = elapsedSec ?? _effectiveElapsedSec();
    if (effective == null) {
      return <int>{};
    }
    final impact = _computeImpactNotes(elapsedSec: effective);
    if (impact.isEmpty) {
      return <int>{};
    }
    return impact.map(_normalizeToKeyboardRange).whereType<int>().toSet();
  }

  @override
  int? _uiDetectedNote() {
    return _normalizeToKeyboardRange(_detectedNote);
  }

  // _handleDevHudTap, _buildMicDebugHud, _copyDebugReport, _permissionLabel
  // are provided by _PracticeMicDebugMixin

  @override
  _KeyboardLayout _computeKeyboardLayout(double availableWidth) {
    return _computeKeyboardLayoutForRange(
      availableWidth,
      _displayFirstKey,
      _displayLastKey,
    );
  }

  _KeyboardLayout _computeKeyboardLayoutForRange(
    double availableWidth,
    int firstKey,
    int lastKey,
  ) {
    final stagePadding = availableWidth < 360
        ? AppConstants.spacing8
        : AppConstants.spacing12;
    final innerAvailableWidth = max(0.0, availableWidth - (stagePadding * 2));
    final whiteCount = _countWhiteKeysForRange(firstKey, lastKey);
    const blackWidthFactor = 0.65;
    final whiteWidth = whiteCount > 0
        ? innerAvailableWidth / (whiteCount + blackWidthFactor)
        : 0.0;
    final blackWidth = whiteWidth * blackWidthFactor;
    final leftPadding = blackWidth / 2;
    final rightPadding = leftPadding;
    final displayWidth = (whiteCount * whiteWidth) + leftPadding + rightPadding;
    final outerWidth = displayWidth + (stagePadding * 2);

    return _KeyboardLayout(
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      displayWidth: displayWidth,
      outerWidth: outerWidth,
      stagePadding: stagePadding,
      shouldScroll: false,
      leftPadding: leftPadding,
      firstKey: firstKey,
      lastKey: lastKey,
      blackKeys: _blackKeys,
    );
  }

  @override
  double _practiceClockSec() {
    if (_startTime == null) {
      return 0.0;
    }
    final elapsedMs =
        DateTime.now().difference(_startTime!).inMilliseconds - _latencyMs;
    return max(0.0, elapsedMs / 1000.0);
  }

  @override
  double? _videoElapsedSec() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }
    return controller.value.position.inMilliseconds / 1000.0 +
        _videoSyncOffsetSec;
  }

  @override
  double? _guidanceElapsedSec() {
    // FEATURE A: Handle countdown state (synthetic elapsed time for falling notes)
    // D2 FIX: Map countdown time to [-leadInSec, 0] range to ensure ratio=1.0
    // Notes spawn from top and fall during entire countdown duration
    if (_practiceState == _PracticeState.countdown &&
        _countdownStartTime != null) {
      final elapsedSinceCountdownSec =
          DateTime.now().difference(_countdownStartTime!).inMilliseconds /
          1000.0;
      return syntheticCountdownElapsedForTest(
        elapsedSinceCountdownStartSec: elapsedSinceCountdownSec,
        leadInSec: _effectiveLeadInSec,
      );
    }
    // A) Guidance is tied to Practice running + video position.
    // Do NOT gate on _isListening. Users must see targets even if mic has no data.
    if (!_practiceRunning) {
      return null;
    }
    // D1: Timebase continuity - clock-based (simplified)
    final clock = _practiceClockSec();

    // BUG FIX #13 REVISED: Always use clock during practice running
    // The original video offset lock was causing issues:
    // - Video position can be null/stale during early frames after countdown
    // - Clock is more reliable and starts from 0 when practice begins
    // - This ensures guidanceElapsed starts near 0, allowing notes to fall from top
    return clock;
  }

  @override
  double? _effectiveElapsedSec() {
    final practiceClockSec = _startTime != null ? _practiceClockSec() : null;
    return effectiveElapsedForTest(
      isPracticeRunning: _practiceRunning,
      videoPosSec: _videoElapsedSec(),
      practiceClockSec: practiceClockSec,
      videoSyncOffsetSec: _videoSyncOffsetSec,
    );
  }

  double? _effectiveVideoDurationSec() {
    // C6: Stabilize duration (never decrease within session)
    if (_videoDurationSec != null && _videoDurationSec! > 0) {
      final candidate = _videoDurationSec!;
      _stableVideoDurationSec = max(_stableVideoDurationSec ?? 0, candidate);
      // D2: Lock duration to current sessionId (prevent fallback override in same session)
      _durationLockedSessionId = _practiceSessionId;
      return _stableVideoDurationSec;
    }
    // Fallback: metadata only if we haven't established a real duration yet
    // AND we're not in a session where we already locked a duration
    if (_stableVideoDurationSec == null &&
        _durationLockedSessionId != _practiceSessionId) {
      final levelDuration = widget.level.durationSec;
      if (levelDuration != null && levelDuration > 0) {
        _stableVideoDurationSec = levelDuration;
        return _stableVideoDurationSec;
      }
    }
    return _stableVideoDurationSec;
  }

  double _minDurationSecForTempo(int? tempoBpm) {
    if (tempoBpm != null && tempoBpm > 0) {
      final secondsPerBeat = 60.0 / tempoBpm;
      return max(_minNoteDurationSec, secondsPerBeat / 32);
    }
    return _minNoteDurationSec;
  }

  double _maxDurationSecForTempo(int? tempoBpm) {
    if (tempoBpm != null && tempoBpm > 0) {
      final secondsPerBeat = 60.0 / tempoBpm;
      return max(_maxNoteDurationFallbackSec, secondsPerBeat * 8);
    }
    return _maxNoteDurationFallbackSec;
  }

  @override
  bool _canStartPractice() {
    if (_videoLoading || _videoError != null) {
      return false;
    }
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return false;
    }
    final effectiveDuration = _effectiveVideoDurationSec();
    if (effectiveDuration == null || effectiveDuration <= 0) {
      return false;
    }
    // BUG FIX #14: Guard notes loaded before allowing practice start
    // If notes not loaded yet, MicEngine would be created with empty noteEvents
    // Then when notes load, _noteEvents reassignment creates desync
    if (_notesLoading || _noteEvents.isEmpty) {
      return false;
    }
    return true;
  }

  bool _isBlackKey(int note) {
    return _blackKeys.contains(note % 12);
  }

  int _countWhiteKeysForRange(int firstKey, int lastKey) {
    int count = 0;
    for (int n = firstKey; n <= lastKey; n++) {
      if (!_isBlackKey(n)) count++;
    }
    return count;
  }

  // _togglePractice, _resetPracticeSession, _startPractice, _stopPractice,
  // _computeEffectiveLeadIn, _updateCountdown, _startPlayback, _sendPracticeSession,
  // initState, dispose, didChangeAppLifecycleState, _maybeShowPracticeInterstitial
  // are provided by _PracticeLifecycleMixin

  @override
  Future<void> _processAudioChunk(List<int> chunk) async {
    if (_startTime == null) return;
    // C3: Session gate - capture sessionId to prevent obsolete callbacks
    final localSessionId = _practiceSessionId;
    if (!_isSessionActive(localSessionId)) {
      return;
    }
    final samples = _convertChunkToSamples(chunk);
    if (samples.isEmpty) return;
    _processSamples(samples, now: DateTime.now(), sessionId: localSessionId);
  }

  _SanitizedNotes _sanitizeNoteEvents({
    required List<_NoteEvent> rawEvents,
    required double minDurationSec,
    required double maxDurationSec,
    double? videoDurationSec,
  }) {
    var droppedInvalidTiming = 0;
    var droppedInvalidPitch = 0;
    var droppedDup = 0;
    var droppedOutOfVideo = 0;
    int? minPitch;
    int? maxPitch;
    final durationFilteredEvents = <_NoteEvent>[];
    final longNoteSamples = <String>[];

    final maxStartSec = videoDurationSec != null
        ? videoDurationSec + _videoDurationToleranceSec
        : null;

    for (final note in rawEvents) {
      // C1: Strict pitch validation (drop pitch < 0 || > 127)
      if (note.pitch < 0 || note.pitch > 127) {
        droppedInvalidPitch += 1;
        continue;
      }
      var start = note.start;
      var end = note.end;
      // C1: Strict time validation (drop NaN/Inf/negative)
      if (start.isNaN || start.isInfinite || end.isNaN || end.isInfinite) {
        droppedInvalidTiming += 1;
        continue;
      }
      if (start < 0 || end < 0) {
        droppedInvalidTiming += 1;
        continue;
      }
      if (videoDurationSec != null && maxStartSec != null) {
        if (start > maxStartSec) {
          droppedOutOfVideo += 1;
          continue;
        }
        if (end > maxStartSec) {
          droppedOutOfVideo += 1;
          continue;
        }
        if (end > videoDurationSec) {
          end = videoDurationSec;
        }
      }

      final duration = end - start;
      if (duration <= 0) {
        droppedInvalidTiming += 1;
        continue;
      }
      if (duration < minDurationSec) {
        continue;
      }
      if (duration > maxDurationSec) {
        if (longNoteSamples.length < 3) {
          longNoteSamples.add(
            'pitch=${note.pitch} start=${start.toStringAsFixed(2)} '
            'end=${end.toStringAsFixed(2)} dur=${duration.toStringAsFixed(2)}',
          );
        }
        continue;
      }

      final adjustedNote = end == note.end
          ? note
          : _NoteEvent(pitch: note.pitch, start: start, end: end);
      durationFilteredEvents.add(adjustedNote);
      minPitch = minPitch == null
          ? adjustedNote.pitch
          : min(minPitch, adjustedNote.pitch);
      maxPitch = maxPitch == null
          ? adjustedNote.pitch
          : max(maxPitch, adjustedNote.pitch);
    }

    final dedupedSet = <_NoteEvent>{};
    final sortedForDedupe = List<_NoteEvent>.from(durationFilteredEvents)
      ..sort((a, b) {
        final pitchCmp = a.pitch.compareTo(b.pitch);
        if (pitchCmp != 0) {
          return pitchCmp;
        }
        final startCmp = a.start.compareTo(b.start);
        if (startCmp != 0) {
          return startCmp;
        }
        return a.end.compareTo(b.end);
      });
    _NoteEvent? previous;
    for (final note in sortedForDedupe) {
      if (previous != null &&
          note.pitch == previous.pitch &&
          (note.start - previous.start).abs() < _dedupeToleranceSec &&
          (note.end - previous.end).abs() < _dedupeToleranceSec) {
        droppedDup += 1;
        continue;
      }
      dedupedSet.add(note);
      previous = note;
    }
    final dedupedEvents = durationFilteredEvents
        .where((note) => dedupedSet.contains(note))
        .toList();

    final int displayFirstKey;
    final int displayLastKey;
    if (minPitch == null || maxPitch == null) {
      displayFirstKey = _defaultFirstKey;
      displayLastKey = _defaultLastKey;
    } else {
      displayFirstKey = max(
        0,
        min(127, min(_defaultFirstKey, minPitch - _rangeMargin)),
      );
      displayLastKey = max(
        0,
        min(127, max(_defaultLastKey, maxPitch + _rangeMargin)),
      );
    }
    final clampedFirstKey = min(displayFirstKey, displayLastKey);
    final clampedLastKey = max(displayFirstKey, displayLastKey);

    final noteEvents = <_NoteEvent>[];
    for (final note in dedupedEvents) {
      if (note.pitch < clampedFirstKey || note.pitch > clampedLastKey) {
        continue;
      }
      noteEvents.add(note);
    }

    // B) Merge overlapping same-pitch events to fix "two streams" problem
    final mergedNoteEvents = _mergeOverlappingEventsByPitch(noteEvents);

    // C1: Store counts for debug report
    _notesDroppedInvalidPitch = droppedInvalidPitch;
    _notesDroppedInvalidTime = droppedInvalidTiming;
    if (kDebugMode) {
      final videoLabel = videoDurationSec == null
          ? '-'
          : videoDurationSec.toStringAsFixed(2);
      debugPrint(
        'Practice notes sanitized using stableDurationSec=$videoLabel',
      );
    }

    return _SanitizedNotes(
      events: mergedNoteEvents,
      displayFirstKey: clampedFirstKey,
      displayLastKey: clampedLastKey,
      droppedOutOfVideo: droppedOutOfVideo,
      droppedDup: droppedDup,
    );
  }

  _NormalizedNotes _normalizeEvents({
    required List<_NoteEvent> events,
    required _KeyboardLayout layout,
  }) {
    final normalized = _normalizeEventsInternal(
      events: events,
      firstKey: layout.firstKey,
      lastKey: layout.lastKey,
      epsilonSec: _dedupeToleranceSec,
    );
    if (kDebugMode) {
      debugPrint(
        'Practice notes normalized: total=${normalized.totalCount} '
        'deduped=${normalized.dedupedCount} '
        'filtered=${normalized.filteredCount} '
        'range=${layout.firstKey}-${layout.lastKey}',
      );
    }
    return normalized;
  }

  @override
  void _resanitizeNoteEventsForVideoDuration() {
    if (_rawNoteEvents.isEmpty || _notesLoading || _practiceRunning) {
      return;
    }
    // C7: Guard idempotent sanitize: skip if no stable duration or same as last (epsilon 0.05)
    final dur = _stableVideoDurationSec;
    if (dur == null) return;
    if (_lastSanitizedDurationSec != null &&
        (dur - _lastSanitizedDurationSec!).abs() < 0.05) {
      return;
    }
    final tempoBpm = widget.level.tempoGuess;
    final minDurationSec = _minDurationSecForTempo(tempoBpm);
    final maxDurationSec = _maxDurationSecForTempo(tempoBpm);
    final sanitized = _sanitizeNoteEvents(
      rawEvents: _rawNoteEvents,
      minDurationSec: minDurationSec,
      maxDurationSec: maxDurationSec,
      videoDurationSec: _effectiveVideoDurationSec(),
    );
    final layout = _computeKeyboardLayoutForRange(
      _currentAvailableWidth(),
      sanitized.displayFirstKey,
      sanitized.displayLastKey,
    );
    final normalized = _normalizeEvents(
      events: sanitized.events,
      layout: layout,
    );
    final sortedEvents = List<_NoteEvent>.from(normalized.events)
      ..sort((a, b) {
        final startCmp = a.start.compareTo(b.start);
        if (startCmp != 0) {
          return startCmp;
        }
        return a.pitch.compareTo(b.pitch);
      });
    final droppedOutOfRange = max(
      0,
      normalized.dedupedCount - normalized.filteredCount,
    );
    if (mounted) {
      setState(() {
        _noteEvents = sortedEvents;
        _displayFirstKey = sanitized.displayFirstKey;
        _displayLastKey = sanitized.displayLastKey;
        _notesRawCount = _rawNoteEvents.length;
        _notesDedupedCount = normalized.dedupedCount;
        _notesFilteredCount = normalized.filteredCount;
        _notesDroppedOutOfRange = droppedOutOfRange;
        _notesDroppedOutOfVideo = sanitized.droppedOutOfVideo;
        _notesDroppedDup = sanitized.droppedDup;
        _notesError = sortedEvents.isEmpty ? 'Notes indisponibles' : null;
        _lastSanitizedDurationSec =
            dur; // C7: Mark sanitization as done for this duration
      });
      // BUG FIX: Compute effective lead-in AFTER notes assigned
      _computeEffectiveLeadIn();
    } else {
      _noteEvents = sortedEvents;
      _displayFirstKey = sanitized.displayFirstKey;
      _displayLastKey = sanitized.displayLastKey;
      _notesRawCount = _rawNoteEvents.length;
      _notesDedupedCount = normalized.dedupedCount;
      _notesFilteredCount = normalized.filteredCount;
      _notesDroppedOutOfRange = droppedOutOfRange;
      _notesDroppedOutOfVideo = sanitized.droppedOutOfVideo;
      _notesDroppedDup = sanitized.droppedDup;
      _notesError = sortedEvents.isEmpty ? 'Notes indisponibles' : null;
      _lastSanitizedDurationSec =
          dur; // C7: Mark sanitization as done for this duration
      // BUG FIX: Compute effective lead-in AFTER notes assigned
      _computeEffectiveLeadIn();
    }
  }

  @override
  bool _isSessionActive(int sessionId) {
    // C3: Session gating - prevent stale async overwrites
    final active = sessionId == _practiceSessionId;
    if (!active && kDebugMode) {
      debugPrint(
        'Practice: session gating blocked update (expected=$sessionId, current=$_practiceSessionId)',
      );
    }
    return active;
  }

  @override
  Future<void> _loadNoteEvents({required int sessionId}) async {
    // C4: Guard already loaded - skip if notes already loaded for this session
    if (_notesLoadedSessionId == sessionId && _noteEvents.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          'Practice notes: already loaded for session=$sessionId; skip sequential reload',
        );
      }
      return;
    }

    // C4: Guard double load - skip if same load already in progress
    if (_notesLoadingSessionId == sessionId && _notesLoading) {
      if (kDebugMode) {
        debugPrint(
          'Practice notes: skipping duplicate load for session=$sessionId',
        );
      }
      return;
    }
    _notesLoadingSessionId = sessionId; // Mark this session's load as inflight
    void applyUpdate(VoidCallback update) {
      if (!_isSessionActive(sessionId)) {
        return;
      }
      if (mounted) {
        setState(update);
      } else {
        update();
      }
    }

    applyUpdate(() {
      _notesLoading = true;
      _notesError = null;
      _notesSource = NotesSource.none;
      _notesRawCount = 0;
      _notesDedupedCount = 0;
      _notesFilteredCount = 0;
      _notesDroppedOutOfRange = 0;
      _notesDroppedOutOfVideo = 0;
      _notesDroppedDup = 0;
      _rawNoteEvents = [];
      _noteEvents = [];
      // FIX: ALWAYS use max(), not practiceLeadIn (would cause mid-screen spawn)
      _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
    });

    final midiUrl = widget.level.midiUrl;
    final jobId = _extractJobId(midiUrl);
    if (jobId == null) {
      applyUpdate(() {
        _notesLoading = false;
        _notesError = 'Notes indisponibles';
        _rawNoteEvents = [];
        _noteEvents = [];
        // FIX: ALWAYS use max() even when jobId null
        _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
        _notesSource = NotesSource.none;
        _displayFirstKey = _defaultFirstKey;
        _displayLastKey = _defaultLastKey;
        _notesDroppedOutOfVideo = 0;
        _notesDroppedDup = 0;
      });
      debugPrint('Practice notes: invalid job id for $midiUrl');
      return;
    }

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (!_isSessionActive(sessionId)) {
        return;
      }
      if (token == null) {
        throw Exception('Missing auth token');
      }
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.backendBaseUrl,
          connectTimeout: const Duration(seconds: 15),
        ),
      );
      DebugJobGuard.attachToDio(dio);
      dio.options.headers['Authorization'] = 'Bearer $token';

      final expectedNotes = await _fetchExpectedNotes(dio, jobId);
      if (!_isSessionActive(sessionId)) {
        return;
      }
      final url = '/practice/notes/$jobId/${widget.level.level}';

      // C2: Single Notes Source Enforcement
      // Rule: If expected_json fetched successfully → NEVER fallback to MIDI.
      // Rule: If expected_json fails → fallback to MIDI ONLY (explicit).
      // Rule: During session, notesSource is locked (no mid-session switch).
      final hasExpected = expectedNotes != null && expectedNotes.isNotEmpty;
      NotesSource source;
      final List<_NoteEvent> rawEvents;

      if (hasExpected && !_notesSourceLocked) {
        // Use expected JSON exclusively
        source = NotesSource.json;
        rawEvents = expectedNotes;
        _notesSourceLocked = true; // C2: Lock source, prevent MIDI fallback
        if (kDebugMode) {
          debugPrint('Practice notes: using expected_json source, $jobId');
        }
      } else if (!_notesSourceLocked) {
        // Fallback to MIDI only if NOT locked (explicit one-time)
        source = NotesSource.midi;
        if (kDebugMode) {
          debugPrint('Practice notes: fallback to MIDI notes url=$url');
        }
        rawEvents = await () async {
          final resp = await dio.get(url);
          final data = _decodeNotesPayload(resp.data);
          return _parseNoteEvents(data['notes']);
        }();
        _notesSourceLocked = true; // C2: Lock source after first attempt
      } else {
        // Source already locked in previous session; use cached source
        source = _notesSource;
        rawEvents = [];
        if (kDebugMode) {
          debugPrint('Practice notes: source locked, skipping load');
        }
      }
      if (!_isSessionActive(sessionId)) {
        return;
      }
      _rawNoteEvents = rawEvents;
      final tempoBpm = widget.level.tempoGuess;
      final minDurationSec = _minDurationSecForTempo(tempoBpm);
      final maxDurationSec = _maxDurationSecForTempo(tempoBpm);
      final sanitized = _sanitizeNoteEvents(
        rawEvents: rawEvents,
        minDurationSec: minDurationSec,
        maxDurationSec: maxDurationSec,
        videoDurationSec: _effectiveVideoDurationSec(),
      );
      final clampedFirstKey = sanitized.displayFirstKey;
      final clampedLastKey = sanitized.displayLastKey;
      final layout = _computeKeyboardLayoutForRange(
        _currentAvailableWidth(),
        clampedFirstKey,
        clampedLastKey,
      );
      final normalized = _normalizeEvents(
        events: sanitized.events,
        layout: layout,
      );
      final sortedEvents = List<_NoteEvent>.from(normalized.events)
        ..sort((a, b) {
          final startCmp = a.start.compareTo(b.start);
          if (startCmp != 0) {
            return startCmp;
          }
          return a.pitch.compareTo(b.pitch);
        });
      final droppedOutOfRange = max(
        0,
        normalized.dedupedCount - normalized.filteredCount,
      );

      applyUpdate(() {
        _noteEvents = sortedEvents;
        _notesLoadedSessionId =
            sessionId; // C4: Mark session as successfully loaded
        _displayFirstKey = clampedFirstKey;
        _displayLastKey = clampedLastKey;
        _notesSource = source;
        _notesRawCount = rawEvents.length;
        _notesDedupedCount = normalized.dedupedCount;
        _notesFilteredCount = normalized.filteredCount;
        _notesDroppedOutOfRange = droppedOutOfRange;
        _notesDroppedOutOfVideo = sanitized.droppedOutOfVideo;
        _notesDroppedDup = sanitized.droppedDup;
        _notesLoading = false;
        _notesError = sortedEvents.isEmpty ? 'Notes indisponibles' : null;
      });
      // C4: Log success exactly once per session
      if (kDebugMode) {
        debugPrint(
          'Practice notes: loaded session=$sessionId count=${sortedEvents.length} source=${source.name}',
        );
      }
      // BUG FIX: Compute effective lead-in AFTER notes assigned
      _computeEffectiveLeadIn();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint(
        'Practice notes error: midiUrl=$midiUrl status=$status error=$e',
      );
      applyUpdate(() {
        _rawNoteEvents = [];
        _noteEvents = [];
        // FIX: ALWAYS use max() even on DioException
        _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
        _notesSource = NotesSource.none;
        _notesLoading = false;
        _notesError = 'Notes indisponibles';
        _displayFirstKey = _defaultFirstKey;
        _displayLastKey = _defaultLastKey;
        _notesDroppedOutOfVideo = 0;
        _notesDroppedDup = 0;
      });
    } catch (e) {
      debugPrint('Practice notes error: midiUrl=$midiUrl error=$e');
      applyUpdate(() {
        _rawNoteEvents = [];
        _noteEvents = [];
        // FIX: ALWAYS use max() even on general error
        _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
        _notesSource = NotesSource.none;
        _notesLoading = false;
        _notesError = 'Notes indisponibles';
        _displayFirstKey = _defaultFirstKey;
        _displayLastKey = _defaultLastKey;
        _notesDroppedOutOfVideo = 0;
        _notesDroppedDup = 0;
      });
    }
  }

  @override
  String? _extractJobId(String midiUrl) {
    try {
      final uri = Uri.parse(midiUrl);
      final file = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : midiUrl.split('/').last;
      if (file.contains('_L')) {
        return file.split('_L').first;
      }
    } catch (_) {}
    return null;
  }

  String _expectedNotesPath(String jobId, int level) {
    return '/media/out/${jobId}_expected_notes_L$level.json';
  }

  Map<String, dynamic> _decodeNotesPayload(dynamic data) {
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      throw const FormatException('Invalid notes payload');
    }
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw const FormatException('Invalid notes payload');
  }

  List<_NoteEvent> _parseNoteEvents(dynamic notesValue) {
    if (notesValue is! List) {
      throw const FormatException('Notes payload missing');
    }
    final events = <_NoteEvent>[];
    for (final entry in notesValue) {
      if (entry is! Map) {
        continue;
      }
      final pitch = entry['pitch'];
      final start = entry['start'];
      final end = entry['end'];
      if (pitch is! num || start is! num || end is! num) {
        continue;
      }
      events.add(
        _NoteEvent(
          pitch: pitch.toInt(),
          start: start.toDouble(),
          end: end.toDouble(),
        ),
      );
    }
    events.sort((a, b) {
      final startCmp = a.start.compareTo(b.start);
      if (startCmp != 0) {
        return startCmp;
      }
      return a.pitch.compareTo(b.pitch);
    });
    return events;
  }

  Future<List<_NoteEvent>?> _fetchExpectedNotes(Dio dio, String jobId) async {
    final url = _expectedNotesPath(jobId, widget.level.level);
    try {
      final resp = await dio.get(url);
      final data = _decodeNotesPayload(resp.data);
      final notes = _parseNoteEvents(data['notes']);
      if (kDebugMode) {
        debugPrint(
          'Practice notes: loaded expected_notes $url count=${notes.length}',
        );
      }
      return notes;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (kDebugMode) {
        debugPrint(
          'Practice notes: expected_notes error url=$url status=$status error=$e',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Practice notes: expected_notes parse error url=$url $e');
      }
      return null;
    }
  }

  @override
  Future<void> _calibrateLatency({bool force = false}) async {
    // Already calibrated
    if (_latencyMs > 0 && !force) return;

    // FIX BUG 2: Skip calibration if countdown/practice active to prevent beep during gameplay
    if (_practiceState == _PracticeState.countdown || _practiceRunning) {
      _latencyMs = _fallbackLatencyMs; // Use fallback instead
      return;
    }

    final micGranted = await _ensureMicPermission();
    if (!micGranted) {
      return;
    }
    final targetFreq = 880.0; // A5 beep
    final durationMs = 1200;
    DateTime? beepStart;
    StreamSubscription<List<int>>? calibSub;
    final calibBuffer = <double>[];
    final recorder = RecorderStream();
    try {
      _isCalibrating = true; // FIX BUG CRITIQUE #2: Flag active calibration
      await recorder.initialize(sampleRate: PitchDetector.sampleRate);
      await recorder.start();
      calibSub = recorder.audioStream.listen((chunk) {
        if (beepStart == null) return;
        final samples = _convertChunkToSamples(chunk);
        if (samples.isEmpty) return;
        calibBuffer.addAll(samples);
        if (calibBuffer.length > 8192) {
          calibBuffer.removeRange(0, calibBuffer.length - 8192);
        }
        if (calibBuffer.length < PitchDetector.bufferSize) return;
        final start = calibBuffer.length - PitchDetector.bufferSize;
        final window = Float32List.fromList(calibBuffer.sublist(start));
        final freq = _pitchDetector.detectPitch(window);
        if (freq == null) return;
        if ((freq - targetFreq).abs() < 80) {
          final delta = DateTime.now().difference(beepStart).inMilliseconds;
          _latencyMs = delta.toDouble();
        }
      });

      // Play beep from generated bytes
      // FIX BUG CRITIQUE: Generate beep with actual detected sampleRate for accurate calibration
      final actualSr =
          _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
      final beepBytes = _generateBeepBytes(
        durationMs: 400,
        freq: targetFreq,
        sampleRate: actualSr,
      );
      beepStart = DateTime.now();
      await _beepPlayer.play(BytesSource(beepBytes));
      await Future.delayed(Duration(milliseconds: durationMs));
    } catch (_) {
      // ignore
    } finally {
      _isCalibrating = false; // FIX BUG CRITIQUE #2: Reset flag
      await calibSub?.cancel();
      try {
        await recorder.stop();
      } catch (_) {}
      if (_latencyMs <= 0) {
        _latencyMs = _fallbackLatencyMs;
      }
      await _persistLatency();
    }
  }

  @override
  Future<void> _loadSavedLatency() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble('practice_latency_ms');
      if (saved != null) {
        _latencyMs = saved;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _persistLatency() async {
    try {
      if (_latencyMs <= 0) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('practice_latency_ms', _latencyMs);
    } catch (_) {
      // ignore
    }
  }

  @override
  Future<bool> _tryStartMidi() async {
    try {
      final midi = MidiCommand();
      final devices = await midi.devices;
      if (devices == null || devices.isEmpty) {
        _midiAvailable = false;
        return false;
      }
      final device = devices.first;
      await midi.connectToDevice(device);
      _midiAvailable = true;
      _midiSub = midi.onMidiDataReceived?.listen(_processMidiPacket);
      return true;
    } catch (_) {
      _midiAvailable = false;
      return false;
    }
  }

  void _processMidiPacket(MidiPacket packet) {
    if (_startTime == null) return;
    // FEATURE A: Disable MIDI processing during countdown
    if (_practiceState == _PracticeState.countdown) {
      return;
    }
    final data = packet.data;
    if (data.isEmpty) return;
    final status = data[0];
    final command = status & 0xF0;
    if (command == 0x90 && data.length >= 3) {
      final note = data[1];
      final velocity = data[2];
      if (velocity == 0) return; // note off
      final now = DateTime.now();
      _lastMidiFrameAt = now;
      _lastMidiNote = note;
      final elapsed = _effectiveElapsedSec();
      if (elapsed == null) {
        return;
      }

      // ═══════════════════════════════════════════════════════════════
      // SESSION 4: Send MIDI note to NEW controller
      // ═══════════════════════════════════════════════════════════════
      if (_useNewScoringSystem && _newController != null) {
        // FIX BUG #4 (CASCADE): Anti-spam aussi pour MIDI (cohérence avec micro)
        if (_lastHitMidi == note &&
            _lastHitAt != null &&
            now.difference(_lastHitAt!) < const Duration(milliseconds: 200)) {
          if (kDebugMode) {
            debugPrint(
              'SESSION4_ANTISPAM_MIDI: Skip duplicate midi=$note (< 200ms)',
            );
          }
          return; // Skip duplicate
        }

        _lastHitMidi = note;
        _lastHitAt = now;

        final stateBefore = _newController!.currentScoringState;
        final correctCountBefore =
            stateBefore.perfectCount +
            stateBefore.goodCount +
            stateBefore.okCount;
        final wrongCountBefore = stateBefore.wrongCount;

        final playedEvent = PracticeController.createPlayedEvent(
          midi: note,
          tPlayedMs: elapsed * 1000.0,
          source: NoteSource.midi,
        );
        _newController!.onPlayedNote(playedEvent);
        _newController!.onTimeUpdate(elapsed * 1000.0);

        final stateAfter = _newController!.currentScoringState;
        final correctCountAfter =
            stateAfter.perfectCount + stateAfter.goodCount + stateAfter.okCount;
        final wrongCountAfter = stateAfter.wrongCount;

        if (correctCountAfter > correctCountBefore) {
          _registerCorrectHit(targetNote: note, detectedNote: note, now: now);
          setState(() {});
        } else if (wrongCountAfter > wrongCountBefore) {
          _registerWrongHit(detectedNote: note, now: now);
          setState(() {});
        }
      }
      // ═══════════════════════════════════════════════════════════════

      setState(() {
        _detectedNote = note;
        if (!_isListening) {
          _detectedNote = null;
        }
      });
    }
  }

  Future<void> _showDiagnostics() async {
    if (!kDebugMode) {
      return;
    }
    final results = await _runDiagnostics();
    if (!mounted) {
      return;
    }
    final lines = results.map((result) => result.summary).join('\n');
    final debugReport = _buildDebugReport();

    // C6: Copy debug report to clipboard
    await Clipboard.setData(ClipboardData(text: debugReport));

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnose Assets & Notes'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Assets:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(lines, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              const Text(
                'Debug Report (copied):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                debugReport,
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _buildDebugReport() {
    // E) Debug Report with counts, source, layout, listener stats + merge metrics
    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'notesSource': _notesSource.toString(),
      'sessionId': _practiceSessionId,
      'practiceRunning': _practiceRunning,
      'isListening': _isListening,
      'counts': {
        'rawNotes': _notesRawCount,
        'dedupedNotes': _notesDedupedCount,
        'filteredNotes': _notesFilteredCount,
        'mergedPairs': _notesMergedPairs,
        'overlapsDetected': _notesOverlapsDetected,
        'droppedInvalidPitch': _notesDroppedInvalidPitch,
        'droppedInvalidTime': _notesDroppedInvalidTime,
        'droppedOutOfRange': _notesDroppedOutOfRange,
        'droppedOutOfVideo': _notesDroppedOutOfVideo,
        'droppedDup': _notesDroppedDup,
        'finalNotes': _noteEvents.length,
        'hitNotes': _hitNotes.where((h) => h).length,
        'totalNotes': _hitNotes.length,
      },
      'pitch': {
        'displayFirstKey': _displayFirstKey,
        'displayLastKey': _displayLastKey,
      },
      'timing': {
        'vpos': _videoElapsedSec()?.toStringAsFixed(3),
        'guidanceElapsed': _guidanceElapsedSec()?.toStringAsFixed(3),
        'practiceClock': (_startTime != null ? _practiceClockSec() : null)
            ?.toStringAsFixed(3),
        // Phase B instrumentation: clock vs video gap
        'clockVideoGapSec': (() {
          final vpos = _videoElapsedSec();
          final clock = _startTime != null ? _practiceClockSec() : null;
          if (vpos == null || clock == null) return null;
          return (clock - vpos).toStringAsFixed(3);
        })(),
        'effectiveLeadInSec': _effectiveLeadInSec.toStringAsFixed(3),
        'earliestNoteStartSec': _earliestNoteStartSec?.toStringAsFixed(3),
      },
      'mic': {
        'rmsMin': _micRmsMin?.toStringAsFixed(4),
        'rmsMax': _micRmsMax?.toStringAsFixed(4),
        'rmsMean': _micSampleCount > 0
            ? (_micRmsSum / _micSampleCount).toStringAsFixed(4)
            : null,
        'sampleCount': _micSampleCount,
        'absMinRms': _absMinRms.toStringAsFixed(4),
        'latencyCompSec': _micLatencyCompSec.toStringAsFixed(3),
        'scoringOffsetSec': _micScoringOffsetSec.toStringAsFixed(3),
      },
      'debug': {
        'overlayBuildCount': _overlayBuildCount,
        'listenerAttachCount': _listenerAttachCount,
        'painterInstanceId': _painterInstanceId,
        'devHudEnabled': _devHudEnabled,
        'mergeTolerances': {
          'overlapSec': _mergeEventOverlapToleranceSec,
          'gapSec': _mergeEventGapToleranceSec,
        },
      },
      'noteEvents': _noteEvents
          .take(20)
          .map(
            (e) => {
              'pitch': e.pitch,
              'start': e.start.toStringAsFixed(3),
              'end': e.end.toStringAsFixed(3),
              'duration': (e.end - e.start).toStringAsFixed(3),
            },
          )
          .toList(),
    };

    // 3) Detect simultaneous same-pitch events (proof of "two streams" source data)
    final elapsedSec = _guidanceElapsedSec() ?? 0.0;
    final simultaneousActiveSamePitch = <Map<String, dynamic>>[];
    final pitchActivityMap =
        <int, int>{}; // pitch -> count of simultaneous events

    for (final note in _noteEvents) {
      if (note.start <= elapsedSec && elapsedSec <= note.end) {
        pitchActivityMap[note.pitch] = (pitchActivityMap[note.pitch] ?? 0) + 1;
      }
    }

    // Extract pitches with >=2 simultaneous events
    for (final entry in pitchActivityMap.entries) {
      if (entry.value >= 2) {
        final pitch = entry.key;
        final activeEvents = _noteEvents
            .where(
              (n) =>
                  n.pitch == pitch &&
                  n.start <= elapsedSec &&
                  elapsedSec <= n.end,
            )
            .toList();
        if (simultaneousActiveSamePitch.length < 10) {
          simultaneousActiveSamePitch.add({
            'pitch': pitch,
            'count': entry.value,
            'ranges': activeEvents
                .map(
                  (e) => {
                    'start': e.start.toStringAsFixed(3),
                    'end': e.end.toStringAsFixed(3),
                  },
                )
                .toList(),
          });
        }
      }
    }

    report['simultaneousActiveSamePitch'] = simultaneousActiveSamePitch;

    return const JsonEncoder.withIndent('  ').convert(report);
  }

  Future<List<_DiagResult>> _runDiagnostics() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.backendBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    DebugJobGuard.attachToDio(dio);

    final targets = <_DiagTarget>[
      _DiagTarget('MIDI', widget.level.midiUrl),
      _DiagTarget('Video', widget.level.videoUrl),
      _DiagTarget('Preview', widget.level.previewUrl),
    ];

    final results = <_DiagResult>[];
    for (final target in targets) {
      results.add(await _checkUrl(dio, target));
    }
    return results;
  }

  Future<_DiagResult> _checkUrl(Dio dio, _DiagTarget target) async {
    if (target.url.isEmpty) {
      return _DiagResult.missing(target.label);
    }
    final resolved = _resolveBackendUrl(target.url);
    late Response<dynamic> response;
    String method = 'HEAD';
    try {
      response = await dio.requestUri(
        Uri.parse(resolved),
        options: Options(method: 'HEAD', validateStatus: (_) => true),
      );
    } on DioException catch (e) {
      final fallback = e.response;
      if (fallback == null) {
        return _DiagResult(
          label: target.label,
          url: resolved,
          method: method,
          error: e.toString(),
        );
      }
      response = fallback;
    } catch (e) {
      return _DiagResult(
        label: target.label,
        url: resolved,
        method: method,
        error: e.toString(),
      );
    }

    final status = response.statusCode;
    if (status == 405 || status == 404) {
      method = 'GET';
      try {
        response = await dio.requestUri(
          Uri.parse(resolved),
          options: Options(
            method: 'GET',
            headers: const {'range': 'bytes=0-1'},
            validateStatus: (_) => true,
          ),
        );
      } on DioException catch (e) {
        final fallback = e.response;
        if (fallback == null) {
          return _DiagResult(
            label: target.label,
            url: resolved,
            method: method,
            error: e.toString(),
          );
        }
        response = fallback;
      } catch (e) {
        return _DiagResult(
          label: target.label,
          url: resolved,
          method: method,
          error: e.toString(),
        );
      }
    }

    return _DiagResult(
      label: target.label,
      url: resolved,
      statusCode: response.statusCode,
      method: method,
    );
  }

  @override
  void _seedTestData() {
    _videoLoading = false;
    _videoError = null;
    _notesLoading = false;
    _notesError = null;
    _noteEvents = [_NoteEvent(pitch: 60, start: 0.0, end: 1.0)];
    // BUG FIX #12: Rebuild list in-place to maintain MicEngine reference
    _hitNotes.clear();
    _hitNotes.addAll(List<bool>.filled(_noteEvents.length, false));
    _notesSource = NotesSource.none;
    _notesRawCount = _noteEvents.length;
    _notesDedupedCount = _noteEvents.length;
    _notesFilteredCount = _noteEvents.length;
    _notesDroppedOutOfRange = 0;
    _notesDroppedOutOfVideo = 0;
    _notesDroppedDup = 0;
    // BUG FIX: Compute effective lead-in after notes assigned
    _computeEffectiveLeadIn();
  }

  // _wrapPracticeVideo, _buildVideoPlayer, _buildVideoContent, _buildNotesOverlay,
  // _buildCroppedVideoLayer, _isSuccessFlashActive, _isWrongFlashActive, _isMissFlashActive
  // are provided by _PracticeUiVideoMixin

  @override
  Future<void> _showScoreDialog({
    required double score,
    required double accuracy,
  }) async {
    if (!mounted) return;
    final total = _totalNotes;

    // SESSION 4: Compute stats from NEW system
    final state = _newController!.currentScoringState;
    final int correctNotes =
        state.perfectCount + state.goodCount + state.okCount;
    // FIX BUG SESSION-004 #3: Separate miss (not played) from wrong (incorrect note)
    final int missCount = state.missCount; // Notes not played in time
    final int wrongCount = state.wrongCount; // Incorrect notes played
    // FIX BUG SESSION-004 #2: Show max combo in session end
    final int maxCombo = state.maxCombo;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session terminée'),
        content: Text(
          'Notes justes: $correctNotes/$total\n'
          'Notes manquées: $missCount\n'
          'Fausses notes: $wrongCount\n'
          'Combo max: $maxCombo\n'
          'Précision: ${accuracy.toStringAsFixed(1)}%',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Generate a simple 16-bit PCM WAV beep as bytes.
Uint8List _generateBeepBytes({
  required int durationMs,
  required double freq,
  required int sampleRate,
  double volume = 0.8,
}) {
  final samplesCount = (sampleRate * (durationMs / 1000)).round();
  final bytesPerSample = 2; // 16-bit PCM
  final dataSize = samplesCount * bytesPerSample;
  final totalSize = 44 + dataSize;
  final buffer = BytesBuilder();

  void writeString(String s) {
    buffer.add(s.codeUnits);
  }

  void writeInt32(int value) {
    final b = ByteData(4);
    b.setUint32(0, value, Endian.little);
    buffer.add(b.buffer.asUint8List());
  }

  void writeInt16(int value) {
    final b = ByteData(2);
    b.setInt16(0, value, Endian.little);
    buffer.add(b.buffer.asUint8List());
  }

  // RIFF header
  writeString('RIFF');
  writeInt32(totalSize - 8);
  writeString('WAVE');

  // fmt chunk
  writeString('fmt ');
  writeInt32(16); // PCM chunk size
  writeInt16(1); // audio format PCM
  writeInt16(1); // channels
  writeInt32(sampleRate);
  writeInt32(sampleRate * bytesPerSample); // byte rate
  writeInt16(bytesPerSample); // block align
  writeInt16(16); // bits per sample

  // data chunk
  writeString('data');
  writeInt32(dataSize);

  for (var i = 0; i < samplesCount; i++) {
    final t = i / sampleRate;
    final sample = (volume * 32767 * sin(2 * pi * freq * t))
        .clamp(-32767, 32767)
        .toInt();
    writeInt16(sample);
  }

  return Uint8List.fromList(buffer.toBytes());
}
