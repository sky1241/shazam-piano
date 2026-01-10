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

import '../../../ads/admob_ads.dart';
import '../../../core/config/build_info.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/strings_fr.dart';
import '../../../core/debug/debug_job_guard.dart';
import '../../../domain/entities/level_result.dart';
import '../../widgets/practice_keyboard.dart';
import '../../widgets/banner_ad_placeholder.dart';
import 'pitch_detector.dart';
import 'mic_engine.dart' as mic;

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

class PracticePage extends StatefulWidget {
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
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool get _isTestEnv =>
      widget.isTest || const bool.fromEnvironment('FLUTTER_TEST');

  String _formatMidiNote(int midi, {bool withOctave = false}) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final base = names[midi % 12];
    if (!withOctave) {
      return base;
    }
    final octave = (midi ~/ 12) - 1;
    return '$base$octave';
  }

  bool _practiceRunning = false;
  bool _practiceStarting =
      false; // Prevent race: don't show countdown until all ready
  int _practiceSessionId =
      0; // Increment on each new start; prevents stale callbacks
  bool _isListening = false;
  bool _isCalibrating = false; // FIX BUG CRITIQUE #2: Track active calibration beep
  int? _detectedNote;
  NoteAccuracy _accuracy = NoteAccuracy.miss;
  // PATCH: Shows only notes currently touching keyboard (no preview)
  // Computed fresh in _onMidiFrame and _onMicFrame
  // FEATURE A: Lead-in countdown state
  _PracticeState _practiceState = _PracticeState.idle;
  DateTime? _countdownStartTime;
  static const double _practiceLeadInSec = 1.5;
  // C8+FIX: Add buffer to prevent notes spawning mid-screen at countdown→running transition
  // Notes spawn at t=-fallLeadSec during countdown and fall to hit line at t=0
  // +1.0 sec buffer ensures notes are well above screen when running state starts
  // Without buffer: If countdown ends exactly at fallLeadSec, first running frame may
  // show notes already past spawn point, causing "notes appear at bottom" bug

  // FIX BUG 1: Helper to check if layout is stable (200ms after countdown start)
  // Increased from 100ms to 200ms to prevent preview flash during first frames
  // CRITICAL: Return false if countdown hasn't started yet to prevent preview during loading
  bool _isLayoutStable() {
    if (_countdownStartTime == null) return false; // Countdown not started = NOT stable
    return DateTime.now().difference(_countdownStartTime!).inMilliseconds >= 200;
  }
  late double _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
  double? _earliestNoteStartSec; // Clamped to >= 0, used for effective lead-in

  int _score = 0;
  int _totalNotes = 0;
  int _correctNotes = 0;
  DateTime? _startTime;
  StreamSubscription<List<int>>? _micSub;
  final RecorderStream _recorder = RecorderStream();
  StreamSubscription<MidiPacket>? _midiSub;
  final _pitchDetector = PitchDetector();
  mic.MicEngine? _micEngine;
  double _micLatencyCompSec = 0.0; // Compensation for buffer latency
  // D1: Micro scoring offset (auto-calibrated via EMA on pitch_match confidence)
  double _micScoringOffsetSec =
      0.0; // Offset between micro elapsed and scoring elapsed
  // Timebase continuity variables removed (clock-based simplified)
  bool _micConfigLogged = false; // Log MIC_CONFIG only once per session
  List<_NoteEvent> _rawNoteEvents = [];
  List<_NoteEvent> _noteEvents = [];
  NotesSource _notesSource = NotesSource.none;
  int _notesRawCount = 0;
  int _notesDedupedCount = 0;
  int _notesFilteredCount = 0;
  int _notesDroppedOutOfRange = 0;
  int _notesDroppedDup = 0;
  int _notesDroppedOutOfVideo = 0;
  int _notesDroppedInvalidPitch = 0;
  int _notesDroppedInvalidTime = 0;
  int _notesMergedPairs = 0;
  int _notesOverlapsDetected = 0;
  final List<bool> _hitNotes = [];
  // Debug tracking (C4: Prove/stop duplicate overlays)
  int _overlayBuildCount = 0;
  int _listenerAttachCount = 0;
  int _painterInstanceId = 0;
  int _spawnLogCount = 0; // D2: Track SPAWN logs (reset per session)
  double _latencyMs = 0;
  final AudioPlayer _beepPlayer = AudioPlayer();
  bool _notesSourceLocked = false; // C2: Prevent mid-session source switch
  static const double _fallbackLatencyMs =
      100.0; // Default offset if calibration fails
  bool _useMidi = false;
  bool _midiAvailable = false;
  late final Ticker _ticker;
  static const double _fallLeadSec = 2.0;
  static const double _fallTailSec = 0.6;
  static const double _targetWindowTailSec =
      0.4; // C8: increased from 0.2 to reduce misses
  static const double _targetWindowHeadSec =
      0.05; // PATCH D1: Early note capture
  static const double _targetChordToleranceSec = 0.03;
  static const double _videoSyncOffsetSec = -0.06; // SYNC with Backend VIDEO_TIME_OFFSET_MS = -60ms
  // B) Configurable merge tolerance for overlapping same-pitch events
  static const double _mergeEventOverlapToleranceSec = 0.05; // 50ms
  static const double _mergeEventGapToleranceSec = 0.08; // 80ms gap threshold
  // PATCH: Mic gating thresholds
  // NOTE: _minConfidenceForHeardNote was removed (redundant with dynamicMinRms)
  static const Duration _successFlashDuration = Duration(milliseconds: 200);
  static const Duration _devTapWindow = Duration(seconds: 2);
  static const int _devTapTarget = 5;
  static const double _videoCropFactor = 0.65;
  final ScrollController _keyboardScrollController = ScrollController();
  double _keyboardScrollOffset = 0.0;
  double _lastLayoutMaxWidth = 0.0;
  VideoPlayerController? _videoController;
  double? _videoDurationSec;
  double? _stableVideoDurationSec; // C6: Non-decreasing duration per session
  ChewieController? _chewieController;
  VoidCallback? _videoListener;
  bool _videoLoading = true;
  String? _videoError;
  bool _notesLoading = false;
  String? _notesError;
  int? _notesLoadingSessionId; // C4: Guard double load by sessionId
  int? _notesLoadedSessionId; // C4: Guard already loaded (prevent sequential reload)
  double? _lastSanitizedDurationSec; // C7: Guard idempotent sanitize (epsilon 0.05)
  int _videoInitToken = 0; // Token guard for video init
  int?
  _durationLockedSessionId; // D2: Lock stable duration once per sessionId (prevent flip)
  PermissionStatus? _micPermissionStatus;
  bool _showMicPermissionFallback = false;
  bool _micDisabled = false;
  DateTime? _lastMicFrameAt;
  double _micRms = 0.0;
  double? _micFrequency;
  int? _micNote;
  double _micConfidence = 0.0;
  DateTime? _lastMicLogAt;
  DateTime? _lastMidiFrameAt;
  int? _lastMidiNote;
  String? _stopReason;
  int _micRestartAttempts = 0;
  bool _micRestarting = false;
  DateTime? _lastMicRestartAt;
  DateTime? _lastUiUpdateAt;
  bool _videoEndFired = false;
  DateTime? _lastVideoEndAt; // FIX BUG 4: Track when video ended to prevent instant replay
  bool _devHudEnabled = false;
  bool _overlayBuiltInBuild = false;
  bool _showKeyboardGuides = false;
  bool _showKeyboardDebugLabels = true;
  bool _showMidiNumbers = true;
  bool _showOnlyTargets = false; // Toggle: paint only target notes (ghost test)
  // BUG 2 FIX: Track which variant was selected in preview to use consistently in practice
  String?
  _selectedVideoVariant; // 'preview' or 'full' - tracks what user chose in preview
  int _devTapCount = 0;
  DateTime? _devTapStartAt;
  DateTime? _lastCorrectHitAt;
  int? _lastCorrectNote;
  DateTime? _lastWrongHitAt;
  int? _lastWrongNote;

  // Default keyboard range (A#1 to C7 = 63 keys).
  static const int _defaultFirstKey = 34; // A#1
  static const int _defaultLastKey = 96; // C7
  static const int _rangeMargin = 2;
  static const double _minNoteDurationSec = 0.03;
  static const double _maxNoteDurationFallbackSec = 10.0;
  static const double _dedupeToleranceSec = 0.001;
  static const double _videoDurationToleranceSec = 0.25;
  static const List<int> _blackKeys = [1, 3, 6, 8, 10]; // C#, D#, F#, G#, A#
  int _displayFirstKey = _defaultFirstKey;
  int _displayLastKey = _defaultLastKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final jobId = _extractJobId(widget.level.midiUrl);
    if (jobId != null) {
      DebugJobGuard.setCurrentJobId(jobId);
    }
    if (!_isTestEnv) {
      unawaited(_refreshMicPermission());
    }
    _ticker = createTicker((_) {
      final isPlaying = _videoController?.value.isPlaying ?? false;
      if (mounted && (_practiceRunning || isPlaying)) {
        setState(() {});
      }
    })..start();
    _keyboardScrollController.addListener(() {
      final next = _keyboardScrollController.offset;
      if (next == _keyboardScrollOffset) {
        return;
      }
      _keyboardScrollOffset = next;
      if (mounted) {
        setState(() {});
      }
    });
    if (_isTestEnv) {
      _seedTestData();
    } else {
      _initVideo();
      _loadNoteEvents(sessionId: _practiceSessionId);
      _loadSavedLatency();
      _maybeShowPracticeInterstitial();
    }
  }

  void _maybeShowPracticeInterstitial() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isTestEnv) {
        return;
      }
      AdmobInterstitialOnce.maybeShowPractice();
    });
  }

  @override
  Widget build(BuildContext context) {
    // FEATURE A: Update countdown every frame
    _updateCountdown();
    assert(() {
      _overlayBuiltInBuild = false;
      return true;
    }());
    final instructionText = _practiceRunning
        ? 'ECOUTE LA NOTE'
        : 'APPUIE SUR PLAY';
    final instructionStyle = AppTextStyles.display.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
      color: AppColors.textPrimary,
    );
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
      bottomNavigationBar: (_practiceRunning || _practiceState == _PracticeState.countdown)
          ? const SizedBox(
              height: 50.0, // Match AdSize.banner.height to preserve layout
              child: SizedBox.shrink(), // FIX BUG CRITIQUE #3: Zero-cost const widget
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
              // When running: show instruction text + practice content
              ...[
                Center(
                  child: Text(
                    instructionText,
                    style: instructionStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
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

  double _currentAvailableWidth() {
    if (_lastLayoutMaxWidth > 0) {
      return _lastLayoutMaxWidth;
    }
    return 0.0;
  }

  Widget _buildPracticeContent({
    required _KeyboardLayout layout,
    required double horizontalPadding,
  }) {
    final elapsedSec = _guidanceElapsedSec();
    // FIX: Also check _practiceState to prevent painting during transition frames
    // This ensures notes are only painted during countdown or running, not during idle
    // FIX BUG 4: Wait for layout to stabilize before painting notes
    final shouldPaintNotes =
        (_practiceRunning || _practiceState == _PracticeState.countdown) &&
        _practiceState != _PracticeState.idle &&
        elapsedSec != null &&
        _noteEvents.isNotEmpty &&
        _isLayoutStable();
    final targetNotes = shouldPaintNotes
        ? _uiTargetNotes(elapsedSec: elapsedSec)
        : const <int>{};

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        children: [
          Expanded(
            child: _buildVideoPlayer(
              layout: layout,
              targetNotes: targetNotes,
              elapsedSec: elapsedSec,
            ),
          ),
          _buildPracticeStage(
            layout: layout,
            targetNotes: targetNotes,
            showMidiNumbers: _showMidiNumbers,
          ),
        ],
      ),
    );
  }

  Widget _buildTopStatsLine() {
    // Hide stats when in idle state (before play or after stop)
    if (_practiceState == _PracticeState.idle) {
      return SizedBox.shrink();
    }
    final precisionValue = _totalNotes > 0
        ? '${(_correctNotes / _totalNotes * 100).toStringAsFixed(1)}%'
        : '0%';
    final statsText =
        'Précision: $precisionValue   Notes justes: $_correctNotes/$_totalNotes   Score: $_score';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing12,
        vertical: AppConstants.spacing8,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          statsText,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  int? _normalizeToKeyboardRange(int? note) {
    if (note == null) return null;
    if (note < _displayFirstKey || note > _displayLastKey) return null;
    return note;
  }

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

  int? _uiDetectedNote() {
    return _normalizeToKeyboardRange(_detectedNote);
  }

  void _handleDevHudTap() {
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now();
    if (_devTapStartAt == null ||
        now.difference(_devTapStartAt!) > _devTapWindow) {
      _devTapStartAt = now;
      _devTapCount = 1;
    } else {
      _devTapCount += 1;
    }

    if (_devTapCount >= _devTapTarget) {
      _devTapCount = 0;
      _devTapStartAt = null;
      if (mounted) {
        setState(() {
          _devHudEnabled = !_devHudEnabled;
        });
      } else {
        _devHudEnabled = !_devHudEnabled;
      }
    }
  }

  Widget _buildMicDebugHud({required double horizontalPadding}) {
    if (!kDebugMode || !_devHudEnabled) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final targetRaw = _practiceRunning
        ? _resolveTargetNotes(_effectiveElapsedSec())
        : const <int>{};
    final sortedTargets = targetRaw.toList()..sort();
    final targetText = sortedTargets.isEmpty ? '--' : sortedTargets.join(',');
    int? minPitch;
    int? maxPitch;
    for (final event in _noteEvents) {
      minPitch = minPitch == null ? event.pitch : min(minPitch, event.pitch);
      maxPitch = maxPitch == null ? event.pitch : max(maxPitch, event.pitch);
    }
    final accuracyText = _accuracy.toString().split('.').last;
    final midiAvailText = _midiAvailable ? 'yes' : 'no';
    final micNoData =
        _practiceRunning &&
        !_useMidi &&
        !_micDisabled &&
        (_lastMicFrameAt == null ||
            now.difference(_lastMicFrameAt!) > const Duration(seconds: 2));
    final micStatus = !_practiceRunning || _useMidi
        ? 'OFF'
        : (_micDisabled ? 'DISABLED' : (micNoData ? 'NO DATA' : 'ON'));
    final midiNoData =
        _practiceRunning &&
        _useMidi &&
        (_lastMidiFrameAt == null ||
            now.difference(_lastMidiFrameAt!) > const Duration(seconds: 2));
    final midiStatus = _useMidi ? (midiNoData ? 'NO DATA' : 'ON') : 'OFF';
    final rmsText = _micRms.toStringAsFixed(3);
    final freqText = _micFrequency != null
        ? _micFrequency!.toStringAsFixed(1)
        : '--';
    final noteText = _useMidi
        ? (_lastMidiNote != null
              ? _formatMidiNote(_lastMidiNote!, withOctave: true)
              : '--')
        : (_micNote != null
              ? _formatMidiNote(_micNote!, withOctave: true)
              : '--');
    final confText = _micConfidence.toStringAsFixed(2);
    final permText = _permissionLabel(_micPermissionStatus);
    final ageText = _useMidi || _lastMicFrameAt == null
        ? '--'
        : '${now.difference(_lastMicFrameAt!).inMilliseconds}ms';
    final subActive = _micSub != null && !_micSub!.isPaused;
    final subText = _useMidi ? '--' : (subActive ? 'ON' : 'OFF');
    final stopText = _stopReason ?? '--';
    final line =
        'MIC: $micStatus | MIDI: $midiStatus | RMS: $rmsText | '
        'f0: $freqText Hz | note: $noteText | conf: $confText | '
        'age: $ageText | sub: $subText | stop: $stopText | perm: $permText';
    final videoPosSec = _videoElapsedSec();
    final guidanceElapsedSec = _guidanceElapsedSec();
    final practiceClockSec = _startTime != null ? _practiceClockSec() : null;
    final deltaSec = videoPosSec != null && practiceClockSec != null
        ? practiceClockSec - videoPosSec
        : null;
    final videoText = videoPosSec != null
        ? videoPosSec.toStringAsFixed(3)
        : '--';
    final guidanceText = guidanceElapsedSec != null
        ? guidanceElapsedSec.toStringAsFixed(3)
        : '--';
    final clockText = practiceClockSec != null
        ? practiceClockSec.toStringAsFixed(3)
        : '--';
    final deltaText = deltaSec != null ? deltaSec.toStringAsFixed(3) : '--';
    final stateLine =
        'target: $targetText | detected: ${_detectedNote ?? '--'} | '
        'accuracy: $accuracyText | midiAvail: $midiAvailText | '
        'vpos: $videoText | guidance: $guidanceText | clock: $clockText | '
        'delta: $deltaText';
    final sessionLine =
        'session: $_practiceSessionId | running: $_practiceRunning | '
        'listening: $_isListening | micGranted: '
        '${_micPermissionStatus?.isGranted == true ? 'yes' : 'no'}';
    final notesLine =
        'source: ${_notesSource.name} | notes: ${_noteEvents.length} | '
        'range: ${minPitch ?? '--'}-${maxPitch ?? '--'} | '
        'display: $_displayFirstKey-$_displayLastKey | '
        'merged: $_notesMergedPairs | overlaps: $_notesOverlapsDetected';
    final impactNotes = _computeImpactNotes();
    final impactList = impactNotes.isEmpty ? ['--'] : impactNotes.toList()
      ..sort();
    final impactText = impactList.toString();
    // FEATURE A: Lead-in countdown info
    final practiceStateText = _practiceState.toString().split('.').last;
    // BUG FIX #9: Use _effectiveLeadInSec (3.0s) instead of _practiceLeadInSec (1.5s)
    final countdownRemainingSec = _countdownStartTime != null
        ? max(
            0.0,
            _effectiveLeadInSec -
                (DateTime.now()
                        .difference(_countdownStartTime!)
                        .inMilliseconds /
                    1000.0),
          )
        : null;
    final countdownText = countdownRemainingSec != null
        ? countdownRemainingSec.toStringAsFixed(2)
        : '--';
    // BUG 2 FIX: Proof field for video variant tracking
    final videoVariantLine =
        'videoVariant: ${_selectedVideoVariant ?? "unset"} | forcePreview: ${widget.forcePreview}';

    // CRITICAL FIX: Falling notes geometry proof fields
    // These values prove the canonical mapping is correct
    final offsetAppliedSec = videoPosSec != null && guidanceElapsedSec != null
        ? videoPosSec - guidanceElapsedSec
        : null;
    final offsetText = offsetAppliedSec != null
        ? offsetAppliedSec.toStringAsFixed(3)
        : '--';

    // Compute y-coordinates for first note to prove the mapping
    String firstNoteStartSecStr = '--';
    String yAtSpawnStr = '--';
    String yAtHitStr = '--';
    if (_noteEvents.isNotEmpty && guidanceElapsedSec != null) {
      final firstNote = _noteEvents.first;
      firstNoteStartSecStr = firstNote.start.toStringAsFixed(3);
      // D2 FIX: Use effectiveLeadInSec during countdown for accurate Y calculation
      final fallLeadForCalc = _practiceState == _PracticeState.countdown 
          ? _effectiveLeadInSec 
          : _fallLeadSec;
      // Current y position of first note (where it appears on screen NOW)
      final yAtSpawn =
          (guidanceElapsedSec - (firstNote.start - fallLeadForCalc)) /
          fallLeadForCalc *
          400.0;
      yAtSpawnStr = yAtSpawn.toStringAsFixed(1);
      // What y WOULD BE when the note hits the keyboard (at elapsed = note.start)
      // Note: yAtHit should equal 400px (fallAreaHeight) by definition
      final yAtHitTheoretical =
          (firstNote.start - (firstNote.start - fallLeadForCalc)) /
          fallLeadForCalc *
          400.0;
      yAtHitStr = yAtHitTheoretical.toStringAsFixed(1);
    }

    final geometryLine =
        'fallLead: $_fallLeadSec | hitLine: 400px | firstNoteStart: $firstNoteStartSecStr | '
        'yAtSpawn: $yAtSpawnStr | yAtHit: $yAtHitStr | offsetApplied: $offsetText';

    // CRITICAL FIX: Video start position proof
    // Prove that practice always starts from t=0, never mid-video
    String startTargetSecStr = '--';
    String posAfterSeekSecStr = '--';
    if (_videoController != null && _videoController!.value.isInitialized) {
      startTargetSecStr = '0.000'; // Always target Duration.zero
      final posAfterSeek =
          _videoController!.value.position.inMilliseconds / 1000.0;
      posAfterSeekSecStr = posAfterSeek.toStringAsFixed(3);
    }
    final videoStartLine =
        'startTarget: $startTargetSecStr | posAfterSeek: $posAfterSeekSecStr | '
        'videoPos: ${(_videoElapsedSec()?.toStringAsFixed(3) ?? '--')}';

    final debugLine =
        'state: $practiceStateText | leadIn: $_practiceLeadInSec | '
        'countdownRemaining: $countdownText | '
        'videoLayerHidden: true | impactNotes: $impactText | impactCount: ${impactNotes.length}';

    // BUG FIX: Proof fields for dynamic lead-in to prevent mid-screen note spawn
    String earliestNoteStartSecStr = '--';
    if (_noteEvents.isNotEmpty) {
      earliestNoteStartSecStr = _noteEvents.first.start.toStringAsFixed(3);
    }
    final effectiveLeadInLine =
        'earliestNote: $earliestNoteStartSecStr | baseLeadIn: ${_practiceLeadInSec.toStringAsFixed(3)} | '
        'effectiveLeadIn: ${_effectiveLeadInSec.toStringAsFixed(3)} | fallLead: ${_fallLeadSec.toStringAsFixed(3)}';

    // BUG FIX: Proof that countdown is armed and lead-in is computed correctly
    final countdownArmed = _countdownStartTime != null ? 'yes' : 'no';
    final notesReady = _noteEvents.isNotEmpty ? 'yes' : 'no';
    // D2 FIX: During countdown, use effectiveLeadInSec
    final fallLeadForCountdownCalc = _practiceState == _PracticeState.countdown 
        ? _effectiveLeadInSec 
        : _fallLeadSec;
    final syntheticSpanSec = fallLeadForCountdownCalc.toStringAsFixed(2);
    final yAtCountdownStartStr =
        _countdownStartTime != null && _earliestNoteStartSec != null
        ? (((-fallLeadForCountdownCalc) - (_earliestNoteStartSec! - fallLeadForCountdownCalc)) /
                  fallLeadForCountdownCalc *
                  400.0)
              .toStringAsFixed(1)
        : '--';
    final countdownProofLine =
        'countdownStarted: $countdownArmed | notesReady: $notesReady | '
        'syntheticSpan: [-$syntheticSpanSec..0] | yAtSpawn: $yAtCountdownStartStr';

    // BUG FIX: Proof of paint phase continuity (countdown→running transition)
    final paintPhase = _practiceState == _PracticeState.countdown
        ? 'countdown'
        : 'running';
    final stateCondition =
        (_practiceRunning || _practiceState == _PracticeState.countdown);
    final elapsedCondition = guidanceElapsedSec != null;
    final notesCondition = _noteEvents.isNotEmpty;
    final shouldPaintEval =
        stateCondition && elapsedCondition && notesCondition;
    final paintPhaseProofLine =
        'paintPhase: $paintPhase | state=$stateCondition | elapsed=$elapsedCondition | notes=$notesCondition | shouldPaint: $shouldPaintEval | elapsedVal: ${guidanceElapsedSec?.toStringAsFixed(3) ?? "null"}';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: AppConstants.spacing4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stateLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            sessionLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            notesLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            line,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            debugLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            geometryLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            videoStartLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            effectiveLeadInLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            countdownProofLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            paintPhaseProofLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            videoVariantLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Wrap(
            spacing: AppConstants.spacing8,
            runSpacing: AppConstants.spacing4,
            children: [
              TextButton(
                onPressed: _runDetectionSelfTest,
                child: const Text('Test detection'),
              ),
              TextButton(onPressed: _injectA4, child: const Text('Inject A4')),
              TextButton(
                onPressed: _refreshMicPermission,
                child: const Text('Check mic'),
              ),
              TextButton(
                onPressed: () => _calibrateLatency(force: true),
                child: const Text('Recalibrer'),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showMidiNumbers = !_showMidiNumbers;
                    });
                  } else {
                    _showMidiNumbers = !_showMidiNumbers;
                  }
                },
                child: Text(
                  _showMidiNumbers ? 'MIDI labels ON' : 'MIDI labels OFF',
                ),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showKeyboardGuides = !_showKeyboardGuides;
                    });
                  } else {
                    _showKeyboardGuides = !_showKeyboardGuides;
                  }
                },
                child: Text(_showKeyboardGuides ? 'Guides ON' : 'Guides OFF'),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showKeyboardDebugLabels = !_showKeyboardDebugLabels;
                    });
                  } else {
                    _showKeyboardDebugLabels = !_showKeyboardDebugLabels;
                  }
                },
                child: Text(
                  _showKeyboardDebugLabels ? 'Key labels ON' : 'Key labels OFF',
                ),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showOnlyTargets = !_showOnlyTargets;
                    });
                  } else {
                    _showOnlyTargets = !_showOnlyTargets;
                  }
                },
                child: Text(_showOnlyTargets ? 'All Notes' : 'Only Targets'),
              ),
              TextButton(
                onPressed: _copyDebugReport,
                child: const Text('Copy debug report'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyDebugReport() async {
    if (!mounted) {
      return;
    }
    final media = MediaQuery.of(context);
    final layout = _computeKeyboardLayout(_currentAvailableWidth());
    final videoPosSec = _videoElapsedSec();
    final elapsedSec = _effectiveElapsedSec();
    final practiceClockSec = _startTime != null ? _practiceClockSec() : null;
    final deltaSec = videoPosSec != null && practiceClockSec != null
        ? practiceClockSec - videoPosSec
        : null;
    final pitches = _rawNoteEvents.isNotEmpty ? _rawNoteEvents : _noteEvents;
    int? minPitch;
    int? maxPitch;
    for (final event in pitches) {
      minPitch = minPitch == null ? event.pitch : min(minPitch, event.pitch);
      maxPitch = maxPitch == null ? event.pitch : max(maxPitch, event.pitch);
    }
    final targetNotes = _practiceRunning && elapsedSec != null
        ? _uiTargetNotes(elapsedSec: elapsedSec)
        : const <int>{};
    final micEnabled =
        _practiceRunning && !_useMidi && !_micDisabled && _isListening;
    final midiEnabled = _practiceRunning && _useMidi;
    final report = <String, dynamic>{
      'buildStamp': BuildInfo.stamp,
      'screenWidth': media.size.width,
      'devicePixelRatio': media.devicePixelRatio,
      'layoutMaxWidth': _lastLayoutMaxWidth,
      'practiceRunning': _practiceRunning,
      'listening': _isListening,
      'notesSource': _notesSource.name,
      'notesCount': _noteEvents.length,
      'notesRawCount': _notesRawCount,
      'dedupedCount': _notesDedupedCount,
      'filteredCount': _notesFilteredCount,
      'droppedOutOfRange': _notesDroppedOutOfRange,
      'droppedOutOfVideo': _notesDroppedOutOfVideo,
      'droppedDup': _notesDroppedDup,
      'minPitch': minPitch,
      'maxPitch': maxPitch,
      'layout': {
        'stagePadding': layout.stagePadding,
        'leftPadding': layout.leftPadding,
        'whiteWidth': layout.whiteWidth,
        'blackWidth': layout.blackWidth,
        'displayWidth': layout.displayWidth,
        'outerWidth': layout.outerWidth,
        'firstKey': layout.firstKey,
        'lastKey': layout.lastKey,
        'scrollOffset': _keyboardScrollOffset,
      },
      'displayFirstKey': _displayFirstKey,
      'displayLastKey': _displayLastKey,
      'videoUrl': widget.level.videoUrl,
      'midiUrl': widget.level.midiUrl,
      'jobId': _extractJobId(widget.level.midiUrl),
      'level': widget.level.level,
      'elapsedSec': elapsedSec,
      'videoPosSec': videoPosSec,
      'practiceClockSec': practiceClockSec,
      'deltaSec': deltaSec,
      'sessionId': _practiceSessionId,
      'targetNotes': targetNotes.toList()..sort(),
      'detectedNote': _detectedNote,
      'micEnabled': micEnabled,
      'midiEnabled': midiEnabled,
      'midiAvailable': _midiAvailable,
      'micPermissionGranted': _micPermissionStatus?.isGranted == true,
      'events': _noteEvents
          .take(15)
          .map((e) => {'pitch': e.pitch, 'start': e.start, 'end': e.end})
          .toList(),
    };
    final payload = jsonEncode(report);
    if (kDebugMode) {
      debugPrint('Practice debug report: $payload');
    }
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug report copied')));
  }

  String _permissionLabel(PermissionStatus? status) {
    if (status == null) {
      return 'unknown';
    }
    return status.toString().split('.').last;
  }

  Future<void> _refreshMicPermission() async {
    try {
      final status = await Permission.microphone.status;
      if (mounted) {
        setState(() {
          _micPermissionStatus = status;
        });
      } else {
        _micPermissionStatus = status;
      }
    } catch (_) {
      // ignore permission errors
    }
  }

  Future<bool> _ensureMicPermission() async {
    if (_isTestEnv) {
      return true;
    }
    PermissionStatus status;
    try {
      status = await Permission.microphone.status;
    } catch (_) {
      return false;
    }
    _setMicPermissionStatus(status);
    if (status.isGranted) {
      _setMicPermissionFallback(false);
      return true;
    }
    if (status.isPermanentlyDenied) {
      _setMicPermissionFallback(true);
      return false;
    }
    final proceed = await _showMicRationaleDialog();
    if (!proceed) {
      return false;
    }
    final requestStatus = await Permission.microphone.request();
    _setMicPermissionStatus(requestStatus);
    if (!requestStatus.isGranted) {
      _setMicPermissionFallback(true);
      return false;
    }
    _setMicPermissionFallback(false);
    return true;
  }

  void _setMicPermissionStatus(PermissionStatus status) {
    if (mounted) {
      setState(() {
        _micPermissionStatus = status;
      });
    } else {
      _micPermissionStatus = status;
    }
  }

  void _setMicPermissionFallback(bool show) {
    if (mounted) {
      setState(() {
        _showMicPermissionFallback = show;
      });
    } else {
      _showMicPermissionFallback = show;
    }
  }

  void _setMicDisabled(bool disabled) {
    if (_micDisabled == disabled) {
      return;
    }
    if (mounted) {
      setState(() {
        _micDisabled = disabled;
        if (disabled && !_useMidi) {
          _isListening = false;
        }
      });
    } else {
      _micDisabled = disabled;
      if (disabled && !_useMidi) {
        _isListening = false;
      }
    }
  }

  Future<bool> _showMicRationaleDialog() async {
    if (!mounted) {
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(StringsFr.micAccessTitle),
        content: const Text(StringsFr.micRationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(StringsFr.micRationaleCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(StringsFr.micRationaleContinue),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildMicPermissionFallback() {
    final status = _micPermissionStatus;
    final isPermanentlyDenied = status?.isPermanentlyDenied ?? false;
    final title = StringsFr.micAccessTitle;
    final body = isPermanentlyDenied
        ? StringsFr.micPermanentlyDeniedMessage
        : StringsFr.micDeniedMessage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing16,
        AppConstants.spacing12,
        AppConstants.spacing16,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacing12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              body,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppConstants.spacing12),
            Wrap(
              spacing: AppConstants.spacing8,
              children: [
                TextButton(
                  onPressed: _handleRetryMicPermission,
                  child: const Text(StringsFr.micRetry),
                ),
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text(StringsFr.micOpenSettings),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRetryMicPermission() async {
    _setMicPermissionFallback(false);
    if (_practiceRunning) {
      final granted = await _ensureMicPermission();
      if (!granted || _useMidi) {
        return;
      }
      _setMicDisabled(false);
      if (mounted) {
        setState(() {
          _isListening = true;
        });
      } else {
        _isListening = true;
      }
      await _startMicStream();
      return;
    }
    await _togglePractice();
  }

  void _logMicDebug(DateTime now) {
    if (!kDebugMode) {
      return;
    }
    if (_lastMicLogAt != null &&
        now.difference(_lastMicLogAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastMicLogAt = now;
    final freqText = _micFrequency?.toStringAsFixed(1) ?? '--';
    final noteText = _micNote != null
        ? _formatMidiNote(_micNote!, withOctave: true)
        : '--';
    debugPrint(
      'MIC: rms=${_micRms.toStringAsFixed(3)} '
      'f0=$freqText note=$noteText conf=${_micConfidence.toStringAsFixed(2)}',
    );
  }

  void _setStopReason(String reason) {
    if (_stopReason == reason) {
      return;
    }
    _stopReason = reason;
    if (kDebugMode) {
      debugPrint('Practice stop reason: $reason');
    }
    if (mounted) {
      setState(() {});
    }
  }

  bool _shouldKeepMicOn() {
    return mounted && _practiceRunning && !_useMidi && !_micDisabled;
  }

  Future<void> _startMicStream() async {
    _micSub?.cancel();
    _micSub = null;
    _micConfigLogged = false; // Reset config logging for new session
    try {
      await _recorder.stop();
    } catch (_) {}

    try {
      await _recorder.initialize(sampleRate: PitchDetector.sampleRate);
      await _recorder.start();
      // D1+D3: Log MIC_FORMAT once per session (audio setup diagnostic)
      if (!_micConfigLogged && kDebugMode) {
        _micConfigLogged = true;
        // FIX BUG CRITIQUE: Log actual detected sampleRate from MicEngine (may differ from requested)
        final actualSr = _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
        debugPrint(
          'MIC_FORMAT sessionId=$_practiceSessionId requested=${PitchDetector.sampleRate} actual=$actualSr '
          'bufferMs=${(PitchDetector.bufferSize * 1000 ~/ actualSr)} '
          'offset=${_micScoringOffsetSec.toStringAsFixed(3)}s',
        );
      }
      // D3: Default latency compensation (~100ms for buffer latency)
      _micLatencyCompSec = 0.10;
      if (kDebugMode) {
        debugPrint(
          'MIC_LATENCY_COMP sessionId=$_practiceSessionId compSec=${_micLatencyCompSec.toStringAsFixed(3)}',
        );
      }
      _micSub = _recorder.audioStream.listen(
        _processAudioChunk,
        onError: (error, _) {
          _handleMicStreamStop('mic_error', error: error);
        },
        onDone: () {
          _handleMicStreamStop('mic_done');
        },
        cancelOnError: true,
      );
    } catch (e) {
      await _handleMicStreamStop('mic_start_error', error: e);
    }
  }

  Future<void> _handleMicStreamStop(String reason, {Object? error}) async {
    if (kDebugMode && error != null) {
      debugPrint('Mic stream error ($reason): $error');
    }
    if (!_shouldKeepMicOn()) {
      if (_isListening) {
        _setStopReason(reason);
      }
      return;
    }
    if (_micRestarting) {
      return;
    }
    final now = DateTime.now();
    if (_lastMicRestartAt != null &&
        now.difference(_lastMicRestartAt!) < const Duration(seconds: 2)) {
      return;
    }
    const maxAttempts = 2;
    if (_micRestartAttempts >= maxAttempts) {
      _setStopReason(reason);
      _setMicDisabled(true);
      return;
    }
    _micRestarting = true;
    _micRestartAttempts += 1;
    _lastMicRestartAt = now;
    _setStopReason('mic_restart_$reason');
    await Future.delayed(const Duration(milliseconds: 250));
    if (_shouldKeepMicOn()) {
      await _startMicStream();
    }
    _micRestarting = false;
  }

  Future<void> _runDetectionSelfTest() async {
    if (!kDebugMode) {
      return;
    }
    const freq = 440.0;
    final samples = Float32List(PitchDetector.bufferSize);
    // FIX BUG CRITIQUE: Generate test samples with actual detected sampleRate
    final actualSr = _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
    for (int i = 0; i < samples.length; i++) {
      samples[i] = sin(2 * pi * freq * i / actualSr);
    }
    final detected = _pitchDetector.detectPitch(samples, sampleRate: actualSr);
    if (!mounted) {
      return;
    }
    final message = detected == null
        ? 'No pitch detected'
        : 'Detected ${detected.toStringAsFixed(1)} Hz '
              '(${_formatMidiNote(_pitchDetector.frequencyToMidiNote(detected), withOctave: true)})';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _injectA4() {
    if (!kDebugMode) {
      return;
    }
    if (!_practiceRunning || _startTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Press Play to inject A4')),
        );
      }
      return;
    }
    const freq = 440.0;
    final samples = Float32List(PitchDetector.bufferSize);
    // FIX BUG CRITIQUE: Generate injection with actual detected sampleRate
    final actualSr = _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
    for (int i = 0; i < samples.length; i++) {
      samples[i] = sin(2 * pi * freq * i / actualSr);
    }
    _processSamples(samples, now: DateTime.now(), injected: true);
  }

  Widget _buildPracticeStage({
    required _KeyboardLayout layout,
    required Set<int> targetNotes,
    required bool showMidiNumbers,
  }) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final whiteWidth = layout.whiteWidth;
    final blackWidth = layout.blackWidth;
    final displayWidth = layout.displayWidth;
    final outerWidth = layout.outerWidth;
    final shouldScroll = layout.shouldScroll;

    final whiteHeight = isPortrait ? 90.0 : 120.0;
    final blackHeight = isPortrait ? 60.0 : 80.0;
    final showNotesStatus =
        _notesLoading || _notesError != null || _noteEvents.isEmpty;

    final content = Container(
      width: outerWidth,
      padding: EdgeInsets.fromLTRB(
        layout.stagePadding,
        0,
        layout.stagePadding,
        layout.stagePadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showNotesStatus) _buildNotesStatus(displayWidth),
          if (showNotesStatus) const SizedBox(height: AppConstants.spacing8),
          _buildKeyboardWithSizes(
            totalWidth: displayWidth,
            whiteWidth: whiteWidth,
            blackWidth: blackWidth,
            whiteHeight: whiteHeight,
            blackHeight: blackHeight,
            targetNotes: targetNotes,
            noteToXFn: layout.noteToX,
            showDebugLabels: _showKeyboardDebugLabels,
            showMidiNumbers: showMidiNumbers,
          ),
        ],
      ),
    );

    if (shouldScroll) {
      return SingleChildScrollView(
        controller: _keyboardScrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Align(alignment: Alignment.centerLeft, child: content),
      );
    }
    return Align(alignment: Alignment.center, child: content);
  }

  Widget _buildKeyboardWithSizes({
    required double totalWidth,
    required double whiteWidth,
    required double blackWidth,
    required double whiteHeight,
    required double blackHeight,
    required Set<int> targetNotes,
    required double Function(int) noteToXFn,
    required bool showDebugLabels,
    required bool showMidiNumbers,
  }) {
    final now = DateTime.now();
    final successFlashActive = _isSuccessFlashActive(now);
    final wrongFlashActive = _isWrongFlashActive(now);
    return PracticeKeyboard(
      key: const Key('practice_keyboard'),
      totalWidth: totalWidth,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      whiteHeight: whiteHeight,
      blackHeight: blackHeight,
      firstKey: _displayFirstKey,
      lastKey: _displayLastKey,
      blackKeys: _blackKeys,
      targetNotes: targetNotes,
      detectedNote: _uiDetectedNote(),
      // Flash the expected/target note (more consistent with falling overlay feedback).
      successFlashNote: _lastCorrectNote,
      successFlashActive: successFlashActive,
      wrongFlashNote: _lastWrongNote,
      wrongFlashActive: wrongFlashActive,
      noteToXFn: noteToXFn,
      showDebugLabels: showDebugLabels,
      showMidiNumbers: showMidiNumbers,
    );
  }

  Widget _buildNotesStatus(double width) {
    if (_notesLoading) {
      return SizedBox(
        width: width,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_notesError != null) {
      return SizedBox(
        width: width,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _notesError!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacing8),
              TextButton(
                onPressed: () => _loadNoteEvents(sessionId: _practiceSessionId),
                child: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_noteEvents.isEmpty) {
      return SizedBox(
        width: width,
        child: Center(
          child: Text('Aucune note disponible', style: AppTextStyles.caption),
        ),
      );
    }
    return const SizedBox.shrink();
  }

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

  double _practiceClockSec() {
    if (_startTime == null) {
      return 0.0;
    }
    final elapsedMs =
        DateTime.now().difference(_startTime!).inMilliseconds - _latencyMs;
    return max(0.0, elapsedMs / 1000.0);
  }

  double? _videoElapsedSec() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return null;
    }
    return controller.value.position.inMilliseconds / 1000.0 +
        _videoSyncOffsetSec;
  }

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

  void _showVideoNotReadyHint() {
    if (!mounted) return;
    // BUG FIX #14: Message plus précis selon ce qui manque
    String message;
    if (_notesLoading) {
      message = 'Notes en cours de chargement, reessaye dans un instant.';
    } else if (_noteEvents.isEmpty) {
      message = 'Notes indisponibles pour ce niveau.';
    } else if (_videoLoading) {
      message = 'Video en cours de chargement, reessaye dans un instant.';
    } else {
      message = 'Chargement en cours, reessaye dans un instant.';
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
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

  Future<void> _togglePractice() async {
    final next = !_practiceRunning;
    if (next && !_canStartPractice()) {
      _showVideoNotReadyHint();
      return;
    }

    if (next) {
      // Reset state from any previous run
      await _resetPracticeSession();
      ++_practiceSessionId; // New session: invalidate old callbacks

      if (mounted) {
        setState(() {
          _practiceRunning = true;
          _practiceStarting = true; // Flag that startup is in progress
        });
      } else {
        _practiceRunning = true;
        _practiceStarting = true;
      }
      if (_videoController != null) {
        await _videoController!.pause();
      }
      // RACE FIX: Don't set countdown state here. Wait for notes/video to load in _startPractice()
      // _togglePractice just signals start-in-progress; actual countdown state set after await
      await _startPractice();
    } else {
      await _stopPractice(showSummary: true, reason: 'user_stop');
    }
  }

  /// Reset practice session completely for replay or stop
  Future<void> _resetPracticeSession() async {
    _practiceState = _PracticeState.idle;
    _practiceRunning = false;
    _practiceStarting = false;
    _countdownStartTime = null;
    _videoEndFired = false;
    _score = 0;
    _correctNotes = 0;
    _totalNotes = 0;
    // BUG FIX #12: Use clear() instead of reassignment to maintain MicEngine reference
    _hitNotes.clear();
    _micEngine = null; // Recreate per-session after notes + hitNotes are ready
    _notesSourceLocked = false; // C2: Reset source lock for next session
    _notesLoadingSessionId = null; // C4: Reset load guard for next session
    _notesLoadedSessionId = null; // C4: Reset loaded flag for next session
    _stableVideoDurationSec =
        null; // C6: Reset stable duration for next session
    _lastSanitizedDurationSec = null; // C7: Reset sanitize epsilon guard
    _lastCorrectNote = null;
    _lastWrongNote = null;
    if (_videoController != null && _videoController!.value.isInitialized) {
      await _videoController!.pause();
      await _videoController!.seekTo(Duration.zero);
    }
  }

  Future<void> _startPractice({Duration? startPosition}) async {
    // FIX BUG 4: Prevent instant replay after video end - require 2s delay
    if (_lastVideoEndAt != null) {
      final timeSinceEnd = DateTime.now().difference(_lastVideoEndAt!).inMilliseconds;
      if (timeSinceEnd < 2000) {
        return; // Ignore replay attempts within 2s of video end
      }
      _lastVideoEndAt = null; // Clear guard after delay passed
    }
    
    if (!_canStartPractice()) {
      _showVideoNotReadyHint();
      if (mounted) {
        setState(() {
          _practiceRunning = false;
          _isListening = false;
        });
      } else {
        _practiceRunning = false;
        _isListening = false;
      }
      return;
    }
    if (!_practiceRunning) {
      if (mounted) {
        setState(() {
          _practiceRunning = true;
        });
      } else {
        _practiceRunning = true;
      }
    }
    final sessionId = _practiceSessionId;
    _lastMicFrameAt = null;
    _micRms = 0.0;
    _micFrequency = null;
    _micNote = null;
    _micConfidence = 0.0;
    _lastMicLogAt = null;
    _lastMidiFrameAt = null;
    _lastMidiNote = null;
    _stopReason = null;
    _micRestartAttempts = 0;
    _micRestarting = false;
    _lastMicRestartAt = null;
    _lastUiUpdateAt = null;
    _videoEndFired = false;

    // NOTE: MicEngine will be initialized AFTER _loadNoteEvents to avoid race condition
    // (hitNotes must be synced with noteEvents length)
    _setMicDisabled(false);
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    } else {
      _isListening = false;
    }

    // Try MIDI first
    _useMidi = await _tryStartMidi();
    if (!_isSessionActive(sessionId)) {
      return;
    }
    if (_useMidi) {
      if (mounted) {
        setState(() {
          _isListening = true;
        });
      } else {
        _isListening = true;
      }
    }

    if (!_useMidi) {
      final micGranted = await _ensureMicPermission();
      if (!_isSessionActive(sessionId)) {
        return;
      }
      if (!micGranted) {
        final status = _micPermissionStatus;
        final reason = status?.isPermanentlyDenied == true
            ? 'permission_permanently_denied'
            : 'permission_denied';
        _setStopReason(reason);
        _setMicDisabled(true);
      } else {
        _setMicDisabled(false);
        if (mounted) {
          setState(() {
            _isListening = true;
          });
        } else {
          _isListening = true;
        }
        // Auto calibrate silently (latency)
        if (_latencyMs == 0) {
          await _calibrateLatency();
        }
        if (_latencyMs == 0) {
          _latencyMs = _fallbackLatencyMs; // fallback if calibration failed
        }
        if (!_isSessionActive(sessionId)) {
          return;
        }
      }
    }

    // Fetch expected notes from backend
    await _loadNoteEvents(sessionId: sessionId);
    if (!_isSessionActive(sessionId)) {
      return;
    }
    // Compute effective lead-in based on loaded notes
    _computeEffectiveLeadIn();
    await _startPracticeVideo(startPosition: startPosition);
    if (!_isSessionActive(sessionId)) {
      return;
    }
    // RACE FIX: Arm countdown NOW that BOTH notes AND video are ready
    // Set state + timestamp TOGETHER to guarantee elapsedOk && notesOk both true for painter
    if (_practiceStarting && _countdownStartTime == null) {
      _spawnLogCount = 0; // D2: Reset log counter for new session
      if (mounted) {
        setState(() {
          _practiceState = _PracticeState.countdown;
          _countdownStartTime = DateTime.now();
          _practiceStarting = false; // Cleanup flag
        });
      } else {
        _practiceState = _PracticeState.countdown;
        _countdownStartTime = DateTime.now();
        _practiceStarting = false;
      }
      // C8: Log countdown timing to verify no chute compression
      // D2 FIX: During countdown, notes use effectiveLeadInSec for fall calculation
      // so ratio should be 1.00 (leadIn / leadIn) not (leadIn / fallLead)
      if (kDebugMode) {
        final leadIn = _effectiveLeadInSec;
        final effectiveFallDuringCountdown = _effectiveLeadInSec; // Notes actually use this
        final firstStart = _earliestNoteStartSec ?? 0;
        debugPrint(
          'Countdown C8: leadInSec=$leadIn fallLeadUsedInPainter=$effectiveFallDuringCountdown '
          'ratio=${(leadIn / effectiveFallDuringCountdown).toStringAsFixed(2)} '
          'earliestNoteStart=$firstStart synthAt_t0=-$effectiveFallDuringCountdown synthAt_tEnd=0',
        );
      }
    }
    _score = 0;
    _correctNotes = 0;
    _totalNotes = _noteEvents.length;
    // BUG FIX #12: Rebuild list in-place to maintain MicEngine reference
    _hitNotes.clear();
    _hitNotes.addAll(List<bool>.filled(_noteEvents.length, false));
    
    // Initialize MicEngine NOW (after notes loaded, hitNotes synced)
    // Previously MicEngine was created before _hitNotes was populated, causing
    // SCORING_DESYNC ABORT and no hits / no key highlights.
    _micEngine = mic.MicEngine(
      noteEvents: _noteEvents
          .map((n) => mic.NoteEvent(start: n.start, end: n.end, pitch: n.pitch))
          .toList(),
      hitNotes: _hitNotes,
      detectPitch: (samples, sr) {
        // samples are already List<double>, no conversion needed
        final float32Samples = Float32List.fromList(samples);
        // FIX BUG 6: Use actual detected sample rate from MicEngine, not hardcoded constant
        // MicEngine calculates sr based on audio chunk timing (e.g., 32784 Hz on some devices)
        // Using wrong sr causes semitoneShift (e.g., 32784→44100 = -5.13 semitones = all notes wrong)
        final result = _pitchDetector.detectPitch(
          float32Samples,
          sampleRate: sr.round(),
        );
        return result ?? 0.0;
      },
      headWindowSec: _targetWindowHeadSec,
      tailWindowSec: _targetWindowTailSec,
      // FIX BUG 3: Increase RMS threshold to reduce false positives from ambient noise
      // Previous: 0.0008 was too sensitive, captured background noise as wrong notes
      // New: 0.0020 filters out quiet ambient noise while preserving real piano input
      absMinRms: 0.0020,
    );
    _micEngine!.reset('$sessionId');
    
    _lastCorrectHitAt = null;
    _lastCorrectNote = null;
    _lastWrongHitAt = null;
    _lastWrongNote = null;
    // BUG FIX #15: Do NOT set _startTime here - it will be set when countdown finishes
    // If set here, clock advances during countdown and guidanceElapsed starts at 2s instead of 0
    // _startTime = DateTime.now(); // REMOVED

    if (_useMidi) {
      // Already listening via MIDI subscription
    } else if (!_micDisabled) {
      await _startMicStream();
    }
  }

  /// Compute effective lead-in to guarantee first note spawns at y≈0 when countdown starts.
  /// D1 FIX: Ensure countdown ratio = 1.0 (no velocity compression).
  /// Formula: effectiveLeadInSec = max(baseLeadIn, fallLead) to prevent chute compression.
  void _computeEffectiveLeadIn() {
    if (_noteEvents.isEmpty) {
      // FIX: ALWAYS use max(), not practiceLeadIn (would cause 1.5s countdown instead of 2.0s)
      _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
      _earliestNoteStartSec = null;
    } else {
      final minStart = _noteEvents.fold<double>(
        double.infinity,
        (min, note) => min < note.start ? min : note.start,
      );
      // Clamp to >= 0
      _earliestNoteStartSec = max(0.0, minStart);
      // D1: Ensure countdown ratio = 1.0 (no velocity > 1.0 compression)
      _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
      if (kDebugMode) {
        debugPrint('EFFECTIVE_LEADIN computed=${_effectiveLeadInSec.toStringAsFixed(3)}s (practiceLeadIn=$_practiceLeadInSec fallLead=$_fallLeadSec)');
      }
    }
  }

  Future<void> _startPracticeVideo({Duration? startPosition}) async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      // CRITICAL FIX: Always start from t=0, ignore any non-zero startPosition
      // (unintended auto-start was passing controller.value.position, causing mid-screen spawn)
      final target = Duration.zero;
      await controller.seekTo(target);
      // FEATURE A: Don't play immediately; wait for countdown to finish
      // Play is triggered in _updateCountdown()
    } catch (_) {}
  }

  // FEATURE A: Monitor countdown and transition to running when time expires
  void _updateCountdown() {
    if (_practiceState != _PracticeState.countdown) {
      return;
    }
    if (_countdownStartTime == null) {
      return;
    }
    final elapsedMs = DateTime.now()
        .difference(_countdownStartTime!)
        .inMilliseconds;
    // BUG FIX: Use effectiveLeadInSec to prevent mid-screen note spawn
    final countdownCompleteSec = _effectiveLeadInSec;
    if (elapsedMs >= countdownCompleteSec * 1000) {
      // Countdown finished: start video + mic + enter running state
      // FIX BUG 5 REVISED: Set _startTime to NOW, _practiceClockSec handles latency subtraction
      // This ensures smooth transition: synthetic countdown ends at 0.0s, running starts at 0.0s
      // The latency compensation in _practiceClockSec() will naturally delay elapsed by ~100ms
      _startTime = DateTime.now();
      if (kDebugMode) {
        final finalElapsed = _guidanceElapsedSec();
        debugPrint('COUNTDOWN_FINISH elapsedMs=$elapsedMs countdownCompleteSec=$countdownCompleteSec finalElapsed=${finalElapsed?.toStringAsFixed(3)} latency=${_latencyMs.toStringAsFixed(1)}ms -> RUNNING');
      }
      if (mounted) {
        setState(() {
          _practiceState = _PracticeState.running;
        });
      } else {
        _practiceState = _PracticeState.running;
      }
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.play();
    } catch (_) {}
    // Mic listening should already be set up in _startPractice()
  }

  Future<void> _stopPractice({
    bool showSummary = false,
    String reason = 'user_stop',
  }) async {
    _setStopReason(reason);
    if (mounted) {
      setState(() {
        _practiceRunning = false;
        _isListening = false;
        _micDisabled = false;
        // PATCH: Clear all overlay/highlight state on stop
        // This prevents leftover orange bars after practice ends
        _detectedNote = null;
        _accuracy = NoteAccuracy.miss;
        // FEATURE A: Reset countdown state
        _practiceState = _PracticeState.idle;
        _countdownStartTime = null;
      });
    } else {
      _practiceRunning = false;
      _isListening = false;
      _micDisabled = false;
      _detectedNote = null;
      _accuracy = NoteAccuracy.miss;
      _practiceState = _PracticeState.idle;
      _countdownStartTime = null;
    }
    // FIX PASS2: Cancel subscription BEFORE stop to prevent AudioRecord -38
    _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    // End FIX PASS2
    _midiSub?.cancel();
    _midiSub = null;
    await _videoController?.pause();
    _useMidi = false;
    _midiAvailable = false;
    final startedAtIso = _startTime?.toIso8601String();
    _startTime = null;
    final finishedAt = DateTime.now().toIso8601String();
    final score = _score.toDouble();
    final total = _totalNotes == 0 ? 1 : _totalNotes;
    final accuracy = total > 0 ? (_correctNotes / total) * 100.0 : 0.0;

    await _sendPracticeSession(
      score: score.toDouble(),
      accuracy: accuracy,
      notesTotal: total,
      notesCorrect: _correctNotes,
      startedAt: startedAtIso ?? finishedAt,
      endedAt: finishedAt,
    );

    setState(() {
      _detectedNote = null;
      _lastMicFrameAt = null;
      _micRms = 0.0;
      _micFrequency = null;
      _micNote = null;
      _micConfidence = 0.0;
      _micScoringOffsetSec = 0.0; // D1: Reset offset for new session
      _lastMidiFrameAt = null;
      _lastMidiNote = null;
      _lastCorrectHitAt = null;
      _lastCorrectNote = null;
      _lastWrongHitAt = null;
      _lastWrongNote = null;
      // D1, D3: Reset mic config logging and latency comp for new session
      _micConfigLogged = false;
      _micLatencyCompSec = 0.0;
    });

    // FIX BUG 2: Await score dialog to prevent screen returning to Play immediately
    // Before: async call continued, UI returned to idle while dialog was opening
    // After: Wait for dialog close before marking video end
    if (showSummary && mounted) {
      await _showScoreDialog(score: score, accuracy: accuracy);
    }
    
    // FIX BUG 4: Mark video end time to prevent instant replay
    _lastVideoEndAt = DateTime.now();
  }

  Future<void> _sendPracticeSession({
    required double score,
    required double accuracy,
    required int notesTotal,
    required int notesCorrect,
    String? startedAt,
    String? endedAt,
  }) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final jobId = _extractJobId(widget.level.midiUrl);

      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.backendBaseUrl,
          connectTimeout: const Duration(seconds: 15), // SYNC: uniform API timeout
        ),
      );
      DebugJobGuard.attachToDio(dio);
      dio.options.headers['Authorization'] = 'Bearer $token';

      await dio.post(
        '/practice/session',
        data: {
          'job_id': jobId ?? widget.level.videoUrl,
          'level': widget.level.level,
          'score': score,
          'accuracy': accuracy,
          'notes_total': notesTotal,
          'notes_correct': notesCorrect,
          'notes_missed': notesTotal - notesCorrect,
          'started_at': startedAt,
          'ended_at': endedAt,
          'app_version': 'mobile',
        },
      );
    } catch (_) {
      // ignore errors for now in UI; backend will log if it receives request
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _practiceRunning) {
      _stopPractice(showSummary: false, reason: 'lifecycle_pause');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _keyboardScrollController.dispose();
    // FIX PASS2: Cancel subscription BEFORE stop to prevent AudioRecord -38
    _micSub?.cancel();
    _midiSub?.cancel();
    try {
      _recorder.stop();
    } catch (_) {}
    // End FIX PASS2
    // FIX BUG CRITIQUE #2: Cancel calibration beep before disposing player
    if (_isCalibrating) {
      try {
        _beepPlayer.stop();
      } catch (_) {}
      _isCalibrating = false;
    }
    _beepPlayer.dispose(); // FIX: Dispose AudioPlayer to prevent memory leak
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

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

  void _processSamples(
    List<double> samples, {
    required DateTime now,
    bool injected = false,
    int? sessionId,
  }) {
    // C3: Session gate - skip if sessionId mismatch (stale callback)
    if (sessionId != null && !_isSessionActive(sessionId)) {
      return;
    }
    if (_startTime == null && !injected) return;
    // D1: Disable mic during countdown (anti-pollution: avoid capturing app's reference note)
    if (_practiceState == _PracticeState.countdown) {
      return;
    }
    _lastMicFrameAt = now;

    // ═══════════════════════════════════════════════════════════════
    // CRITICAL: MicEngine scoring (all gating + buffering internal)
    // ═══════════════════════════════════════════════════════════════
    final elapsed = _guidanceElapsedSec();
    if (elapsed != null && _micEngine != null) {
      final prevAccuracy = _accuracy;
      final decisions = _micEngine!.onAudioChunk(
        samples,
        now,
        elapsed,
      );

      // Apply decisions (HIT/MISS/wrongFlash)
      for (final decision in decisions) {
        switch (decision.type) {
          case mic.DecisionType.hit:
            _correctNotes += 1;
            _score += 1;
            _accuracy = NoteAccuracy.correct;
            _registerCorrectHit(
              targetNote: decision.expectedMidi!,
              detectedNote: decision.detectedMidi!,
              now: now,
            );
            _updateDetectedNote(decision.detectedMidi, now, accuracyChanged: true);
            break;

          case mic.DecisionType.miss:
            if (_accuracy != NoteAccuracy.correct) {
              _accuracy = NoteAccuracy.wrong;
            }
            break;

          case mic.DecisionType.wrongFlash:
            _accuracy = NoteAccuracy.wrong;
            _registerWrongHit(detectedNote: decision.detectedMidi!, now: now);
            _updateDetectedNote(decision.detectedMidi, now, accuracyChanged: true);
            break;
        }
      }

      // Update UI with MicEngine's held note (200ms hold)
      final uiMidi = _micEngine!.uiDetectedMidi;
      final accuracyChanged = prevAccuracy != _accuracy;
      _updateDetectedNote(uiMidi, now, accuracyChanged: accuracyChanged);
    }

    // Mirror MicEngine state to HUD
    _micFrequency = _micEngine?.lastFreqHz;
    _micNote = _micEngine?.lastMidi;
    _micConfidence = _micEngine?.lastConfidence ?? 0.0;
    _micRms = _micEngine?.lastRms ?? 0.0;

    _logMicDebug(now);
  }

  void _updateDetectedNote(
    int? nextDetected,
    DateTime now, {
    bool accuracyChanged = false,
  }) {
    final prevDetected = _detectedNote;
    final tooSoon =
        _lastUiUpdateAt != null &&
        now.difference(_lastUiUpdateAt!) < const Duration(milliseconds: 120);
    final shouldUpdate =
        !tooSoon || prevDetected != nextDetected || accuracyChanged;

    if (shouldUpdate && mounted) {
      setState(() {
        _detectedNote = nextDetected;
      });
      _lastUiUpdateAt = now;
    } else {
      _detectedNote = nextDetected;
    }
  }

  void _registerCorrectHit({
    required int targetNote,
    required int detectedNote,
    required DateTime now,
  }) {
    _lastCorrectNote = targetNote;
    _lastCorrectHitAt = now;
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {});
    }
  }

  void _registerWrongHit({required int detectedNote, required DateTime now}) {
    final tooSoon =
        _lastWrongHitAt != null &&
        now.difference(_lastWrongHitAt!) < _successFlashDuration;
    if (tooSoon && _lastWrongNote == detectedNote) {
      return;
    }
    _lastWrongHitAt = now;
    _lastWrongNote = detectedNote;
    HapticFeedback.selectionClick();
    if (mounted) {
      setState(() {});
    }
  }

  List<double> _convertChunkToSamples(List<int> chunk) {
    if (chunk.isEmpty) return const [];
    final looksLikeBytes =
        chunk is Uint8List ||
        (chunk is! Int16List && chunk.every((v) => v >= 0 && v <= 255));

    final samples = <double>[];
    if (looksLikeBytes) {
      final evenLength = chunk.length - (chunk.length % 2);
      // D1: Convert bytes to int16 samples
      for (var i = 0; i < evenLength; i += 2) {
        final lo = chunk[i];
        final hi = chunk[i + 1];
        int value = (hi << 8) | lo;
        if (value >= 0x8000) {
          value -= 0x10000;
        }
        samples.add(value / 32768.0);
      }
      return samples;
    }

    // D1: If input is Int16List (could be stereo), treat as raw int16 values
    // and downmix to mono if needed (take every sample, assuming they're already interleaved properly)
    for (final value in chunk) {
      if (value < -32768 || value > 32767) {
        continue;
      }
      samples.add(value / 32768.0);
    }
    return samples;
  }

  // B) Merge overlapping same-pitch events (fix "two streams" problem)
  List<_NoteEvent> _mergeOverlappingEventsByPitch(
    List<_NoteEvent> events, {
    double? mergeTolerance,
    double? mergeGapTolerance,
  }) {
    mergeTolerance ??= _mergeEventOverlapToleranceSec;
    mergeGapTolerance ??= _mergeEventGapToleranceSec;
    if (events.isEmpty) {
      _notesMergedPairs = 0;
      _notesOverlapsDetected = 0;
      return events;
    }

    // Group events by pitch
    final byPitch = <int, List<_NoteEvent>>{};
    for (final event in events) {
      byPitch.putIfAbsent(event.pitch, () => []).add(event);
    }

    var mergedPairs = 0;
    var overlapsDetected = 0;
    final merged = <_NoteEvent>[];

    // Process each pitch group
    for (final pitchEvents in byPitch.values) {
      // Sort by start then end
      pitchEvents.sort((a, b) {
        final startCmp = a.start.compareTo(b.start);
        if (startCmp != 0) return startCmp;
        return a.end.compareTo(b.end);
      });

      final mergedGroup = <_NoteEvent>[];
      _NoteEvent? current = pitchEvents.isNotEmpty ? pitchEvents[0] : null;

      for (var i = 1; i < pitchEvents.length; i++) {
        final next = pitchEvents[i];
        if (current != null) {
          // Check for overlap: next.start <= current.end + tolerance
          final gap = next.start - current.end;
          if (gap <= mergeGapTolerance) {
            // Merge: extend current.end to max(current.end, next.end)
            overlapsDetected++;
            current = _NoteEvent(
              pitch: current.pitch,
              start: current.start,
              end: max(current.end, next.end),
            );
            mergedPairs++;
          } else {
            // No overlap, save current and move to next
            mergedGroup.add(current);
            current = next;
          }
        }
      }
      if (current != null) {
        mergedGroup.add(current);
      }

      merged.addAll(mergedGroup);
    }

    // Re-sort globally by start then pitch
    merged.sort((a, b) {
      final startCmp = a.start.compareTo(b.start);
      if (startCmp != 0) return startCmp;
      return a.pitch.compareTo(b.pitch);
    });

    _notesMergedPairs = mergedPairs;
    _notesOverlapsDetected = overlapsDetected;

    if (kDebugMode && overlapsDetected > 0) {
      debugPrint(
        'Practice notes merged: mergedPairs=$mergedPairs overlapsDetected=$overlapsDetected',
      );
    }

    return merged;
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
      final actualSr = _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
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

      // Find active expected notes
      final activeIndices = <int>[];
      for (var i = 0; i < _noteEvents.length; i++) {
        final n = _noteEvents[i];
        if (elapsed >= n.start && elapsed <= n.end + _targetWindowTailSec) {
          activeIndices.add(i);
        }
        // BUG FIX #10: Bounds check to prevent RangeError if _hitNotes desync
        if (elapsed > n.end + _targetWindowTailSec && i < _hitNotes.length && !_hitNotes[i]) {
          _hitNotes[i] = true; // mark as processed
        }
      }

      bool matched = false;
      for (final idx in activeIndices) {
        // BUG FIX #10: Bounds check to prevent RangeError
        if (idx >= _hitNotes.length || _hitNotes[idx]) continue;
        if ((note - _noteEvents[idx].pitch).abs() <= 1) {
          matched = true;
          _hitNotes[idx] = true;
          _correctNotes += 1;
          _score += 1;
          _accuracy = NoteAccuracy.correct;
          _registerCorrectHit(
            targetNote: _noteEvents[idx].pitch,
            detectedNote: note,
            now: now,
          );
          break;
        }
      }

      if (!matched && activeIndices.isNotEmpty) {
        // PATCH: Only trigger wrongFlash if there's an active note to play
        final impactNotes = _computeImpactNotes(elapsedSec: elapsed);
        if (impactNotes.isNotEmpty) {
          _accuracy = NoteAccuracy.wrong;
          _registerWrongHit(detectedNote: note, now: now);
        }
      }

      setState(() {
        _detectedNote = note;
        if (!_isListening) {
          _detectedNote = null;
        }
      });
    }
  }

  Future<void> _initVideo() async {
    // Token guard against double concurrent init
    final token = ++_videoInitToken;

    try {
      await _disposeVideoControllers();
      _videoEndFired = false;

      // Check token again after async gap
      if (token != _videoInitToken) {
        return; // Another init started, abort this one
      }

      setState(() {
        _videoLoading = true;
        _videoError = null;
      });

      final previewUrl = widget.level.previewUrl;
      final fullUrl = widget.level.videoUrl;
      String selectedUrl;

      // BUG 2 FIX: Use the variant that was selected in preview, or fall back to logic
      if (widget.forcePreview) {
        // Always use preview if forced
        if (previewUrl.isEmpty) {
          setState(() {
            _videoError = 'Aucun aperçu disponible';
            _videoLoading = false;
          });
          return;
        }
        selectedUrl = previewUrl;
        _selectedVideoVariant = 'preview';
      } else if (_selectedVideoVariant == 'preview') {
        // User explicitly chose preview in preview mode - stick with it
        if (previewUrl.isEmpty) {
          // Fallback to full if preview no longer available
          selectedUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
          _selectedVideoVariant = 'full';
        } else {
          selectedUrl = previewUrl;
        }
      } else if (_selectedVideoVariant == 'full') {
        // User explicitly chose full in preview mode - stick with it
        selectedUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
      } else {
        // First time in practice: default to full, fallback to preview if needed
        selectedUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
        _selectedVideoVariant = fullUrl.isNotEmpty ? 'full' : 'preview';
      }

      final url = _resolveBackendUrl(selectedUrl);
      if (url.isEmpty) {
        setState(() {
          _videoError = 'Aucune video';
          _videoLoading = false;
        });
        return;
      }

      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoController!.initialize();
      _videoController!.setLooping(false);
      await _videoController!.pause();
      final duration = _videoController!.value.duration;
      _videoDurationSec = duration > Duration.zero
          ? duration.inMilliseconds / 1000.0
          : null;
      _videoListener = () {
        if (_videoController == null) return;
        final value = _videoController!.value;
        if (!value.isInitialized || value.duration == Duration.zero) {
          return;
        }
        if (_videoEndFired) {
          return;
        }
        if (_practiceRunning && isVideoEnded(value.position, value.duration)) {
          _videoEndFired = true;
          unawaited(_stopPractice(showSummary: true, reason: 'video_end'));
        }
      };
      // C4: Track listener attachment for debugging
      _listenerAttachCount += 1;
      _videoController!.addListener(_videoListener!);
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: false,
        showControls: false,
        // PATCH: Disable center play button to prevent dual entrypoint
        // Users must use AppBar _togglePractice() only for consistent state
        aspectRatio: _videoController!.value.aspectRatio == 0
            ? 16 / 9
            : _videoController!.value.aspectRatio,
      );
      _resanitizeNoteEventsForVideoDuration();

      setState(() {
        _videoLoading = false;
      });
    } catch (e) {
      setState(() {
        _videoError = 'Erreur video: $e';
        _videoLoading = false;
      });
    }
  }

  Future<void> _disposeVideoControllers() async {
    _chewieController?.dispose();
    _chewieController = null;
    if (_videoListener != null && _videoController != null) {
      _videoController!.removeListener(_videoListener!);
    }
    _videoListener = null;
    _videoController?.dispose();
    _videoController = null;
    _videoDurationSec = null;
  }

  String _resolveBackendUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http')) return url;
    final baseRaw = AppConstants.backendBaseUrl.trim();
    final base = baseRaw.isEmpty ? 'http://127.0.0.1:8000' : baseRaw;
    final baseWithSlash = base.endsWith('/') ? base : '$base/';
    final cleaned = url.startsWith('/') ? url.substring(1) : url;
    return Uri.parse(baseWithSlash).resolve(cleaned).toString();
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

  Widget _wrapPracticeVideo(Widget child) {
    return KeyedSubtree(key: const Key('practice_video'), child: child);
  }

  bool _isSuccessFlashActive(DateTime now) {
    return _lastCorrectHitAt != null &&
        _lastCorrectNote != null &&
        now.difference(_lastCorrectHitAt!) <= _successFlashDuration;
  }

  bool _isWrongFlashActive(DateTime now) {
    return _lastWrongHitAt != null &&
        _lastWrongNote != null &&
        now.difference(_lastWrongHitAt!) <= _successFlashDuration;
  }

  Widget _buildCroppedVideoLayer({
    required Widget child,
    required double aspectRatio,
  }) {
    final safeAspect = aspectRatio > 0 ? aspectRatio : 16 / 9;
    const baseWidth = 1000.0;
    final baseHeight = baseWidth / safeAspect;

    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _videoCropFactor,
          child: SizedBox(width: baseWidth, height: baseHeight, child: child),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer({
    required _KeyboardLayout layout,
    required Set<int> targetNotes,
    required double? elapsedSec,
  }) {
    return _wrapPracticeVideo(
      LayoutBuilder(
        builder: (context, constraints) {
          final aspectRatio = _chewieController?.aspectRatio ?? 16 / 9;
          final videoLayer = _buildCroppedVideoLayer(
            aspectRatio: aspectRatio,
            child: _buildVideoContent(),
          );
          assert(() {
            if (_overlayBuiltInBuild) {
              debugPrint(
                'Practice overlay built more than once in a build pass',
              );
            }
            _overlayBuiltInBuild = true;
            return true;
          }());
          // Now constraints.maxHeight is stable (bottomNavigationBar always present as 50px spacer)
          final overlay = _buildNotesOverlay(
            layout: layout,
            overlayHeight: constraints.maxHeight,
            targetNotes: targetNotes,
            elapsedSec: elapsedSec,
          );
          // PATCH: Hide video layer permanently + show only Flutter overlay
          // Chewie continues running for timing, but is opacity=0 to prevent "two streams"
          // All visual notes come from _FallingNotesPainter only
          // FIX BUG 1: Use SizedBox with explicit dimensions instead of Positioned.fill
          // to respect CustomPaint.size (otherwise Stack collapses canvas to parent height)
          final stack = Stack(
            children: [
              // Opacity 0: video runs for timing/audio but isn't visible
              Positioned.fill(child: Opacity(opacity: 0.0, child: videoLayer)),
              // Paint overlay during countdown + running (notes visible during lead-in)
              // FIX: Wrap overlay in SizedBox matching constraints.maxHeight (now stable)
              if (_practiceRunning ||
                  _practiceState == _PracticeState.countdown)
                SizedBox(
                  width: layout.displayWidth,
                  height: constraints.maxHeight,
                  child: overlay,
                ),
              // Render empty overlay container for key when not in countdown/running
              if (!(_practiceRunning ||
                  _practiceState == _PracticeState.countdown))
                const KeyedSubtree(
                  key: Key('practice_notes_overlay'),
                  child: SizedBox.expand(),
                ),
            ],
          );
          final stage = SizedBox(
            width: layout.outerWidth,
            height: constraints.maxHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.stagePadding),
              child: stack,
            ),
          );
          final aligned = layout.shouldScroll
              ? Align(alignment: Alignment.centerLeft, child: stage)
              : Align(alignment: Alignment.center, child: stage);
          return ClipRect(child: aligned);
        },
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_isTestEnv) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text(
          'Video placeholder',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    if (_videoError != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppConstants.spacing12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _videoError!,
              style: AppTextStyles.caption.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing8),
            TextButton(onPressed: _initVideo, child: const Text('Reessayer')),
          ],
        ),
      );
    }
    if (_videoLoading || _chewieController == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    return Chewie(controller: _chewieController!);
  }

  Widget _buildNotesOverlay({
    required _KeyboardLayout layout,
    required double overlayHeight,
    required Set<int> targetNotes,
    required double? elapsedSec,
  }) {
    // C4: Track overlay build count for debugging
    _overlayBuildCount += 1;

    final now = DateTime.now();
    final successFlashActive = _isSuccessFlashActive(now);
    final wrongFlashActive = _isWrongFlashActive(now);
    final elapsed = elapsedSec;
    // BUG FIX #9: Must paint notes during COUNTDOWN to allow falling animation
    // Notes need to spawn offscreen (spawnY < 0) and fall during countdown
    // Previous condition blocked countdown rendering, causing "notes pop mid-screen" bug
    // FIX BUG 4: Wait 100ms after countdown start for layout to stabilize
    // Prevents notes appearing "en bas" with incorrect overlayHeight
    final shouldPaintNotes =
        (_practiceRunning || _practiceState == _PracticeState.countdown) &&
        elapsed != null &&
        _noteEvents.isNotEmpty &&
        _isLayoutStable(); // Only paint when layout is stable
    final paintElapsedSec = elapsed ?? 0.0;
    final resolvedTargets = shouldPaintNotes ? targetNotes : <int>{};
    var noteEvents = shouldPaintNotes ? _noteEvents : const <_NoteEvent>[];

    // D2: Debug log to track note spawning during countdown
    if (kDebugMode && 
        _practiceState == _PracticeState.countdown && 
        shouldPaintNotes && 
        _noteEvents.isNotEmpty) {
      if (_spawnLogCount < 3) { // Log only first 3 frames to avoid spam
        _spawnLogCount++;
        final firstNote = _noteEvents.first;
        final effectiveFallForLog = _effectiveLeadInSec; // Use effective lead during countdown
        final spawnTimeTheoreticalSec = firstNote.start - effectiveFallForLog;
        final yTop = (paintElapsedSec - spawnTimeTheoreticalSec) / effectiveFallForLog * overlayHeight;
        final yBottom = (paintElapsedSec - (firstNote.end - effectiveFallForLog)) / effectiveFallForLog * overlayHeight;
        debugPrint(
          'SPAWN note midi=${firstNote.pitch} at guidanceElapsed=${paintElapsedSec.toStringAsFixed(3)} '
          'yTop=${yTop.toStringAsFixed(1)} yBottom=${yBottom.toStringAsFixed(1)} '
          'noteStart=${firstNote.start.toStringAsFixed(3)} spawnAt=${spawnTimeTheoreticalSec.toStringAsFixed(3)}',
        );
      }
    }

    // 4) Debug toggle: show only target notes (ghost test isolation)
    if (_showOnlyTargets && shouldPaintNotes) {
      noteEvents = noteEvents
          .where((n) => resolvedTargets.contains(n.pitch))
          .toList();
    }

    final scrollOffset = layout.shouldScroll ? _keyboardScrollOffset : 0.0;
    final showGuides = kDebugMode && _showKeyboardGuides;
    final baseNoteToX = layout.noteToX;
    double noteToX(int note) => baseNoteToX(note) - scrollOffset;

    // C4: Track painter instance for debugging duplicate overlays
    _painterInstanceId += 1;

    // FIX BUG 2: Always use constant fallLead to prevent visual jump at countdown→running transition
    // Previous: Used _effectiveLeadInSec (3.0s) during countdown, _fallLeadSec (2.0s) during running
    // Problem: When transitioning, all note Y positions suddenly shifted (3.0→2.0 ratio change)
    // Solution: Use constant _fallLeadSec (2.0s) for both states - notes fall at consistent speed
    final effectiveFallLead = _fallLeadSec;

    return IgnorePointer(
      child: CustomPaint(
        key: const Key('practice_notes_overlay'),
        size: Size(layout.displayWidth, overlayHeight),
        painter: _FallingNotesPainter(
          noteEvents: noteEvents,
          elapsedSec: paintElapsedSec,
          whiteWidth: layout.whiteWidth,
          blackWidth: layout.blackWidth,
          fallAreaHeight: overlayHeight,
          fallLead: effectiveFallLead,
          fallTail: _fallTailSec,
          noteToX: noteToX,
          firstKey: layout.firstKey,
          lastKey: layout.lastKey,
          targetNotes: resolvedTargets,
          successNote: _lastCorrectNote,
          successFlashActive: successFlashActive,
          wrongNote: _lastWrongNote,
          wrongFlashActive: wrongFlashActive,
          forceLabels: true,
          showGuides: showGuides,
          showMidiNumbers: _showMidiNumbers,
        ),
      ),
    );
  }

  Future<void> _showScoreDialog({
    required double score,
    required double accuracy,
  }) async {
    if (!mounted) return;
    final total = _totalNotes;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Session terminée'),
        content: Text(
          'Score: ${score.toStringAsFixed(0)}\n'
          'Précision: ${accuracy.toStringAsFixed(1)}%\n'
          'Notes jouées: $total',
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

class _DiagTarget {
  final String label;
  final String url;

  const _DiagTarget(this.label, this.url);
}

class _DiagResult {
  final String label;
  final String url;
  final int? statusCode;
  final String method;
  final String? error;

  const _DiagResult({
    required this.label,
    required this.url,
    this.statusCode,
    required this.method,
    this.error,
  });

  factory _DiagResult.missing(String label) {
    return _DiagResult(label: label, url: '', method: 'N/A', error: 'missing');
  }

  String get _safeUrl {
    if (url.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return url;
    }
    return parsed.replace(query: '', fragment: '').toString();
  }

  String get summary {
    if (statusCode != null) {
      final ok = statusCode! >= 200 && statusCode! < 300;
      final tag = ok ? 'OK' : 'HTTP $statusCode';
      return '$label: $tag ($method) $_safeUrl';
    }
    final detail = error ?? 'error';
    return '$label: $detail ($method) $_safeUrl';
  }
}

class _NoteEvent {
  final int pitch;
  final double start;
  final double end;
  _NoteEvent({required this.pitch, required this.start, required this.end});
}

class _NormalizedNotes {
  final List<_NoteEvent> events;
  final int totalCount;
  final int dedupedCount;
  final int filteredCount;

  const _NormalizedNotes({
    required this.events,
    required this.totalCount,
    required this.dedupedCount,
    required this.filteredCount,
  });
}

_NormalizedNotes _normalizeEventsInternal({
  required List<_NoteEvent> events,
  required int firstKey,
  required int lastKey,
  required double epsilonSec,
}) {
  final totalCount = events.length;
  if (events.isEmpty) {
    return const _NormalizedNotes(
      events: [],
      totalCount: 0,
      dedupedCount: 0,
      filteredCount: 0,
    );
  }
  final sorted = List<_NoteEvent>.from(events)
    ..sort((a, b) {
      final startCmp = a.start.compareTo(b.start);
      if (startCmp != 0) {
        return startCmp;
      }
      final pitchCmp = a.pitch.compareTo(b.pitch);
      if (pitchCmp != 0) {
        return pitchCmp;
      }
      return a.end.compareTo(b.end);
    });

  final deduped = <_NoteEvent>[];
  _NoteEvent? previous;
  for (final note in sorted) {
    if (previous != null &&
        note.pitch == previous.pitch &&
        (note.start - previous.start).abs() <= epsilonSec &&
        (note.end - previous.end).abs() <= epsilonSec) {
      continue;
    }
    deduped.add(note);
    previous = note;
  }

  final filtered = <_NoteEvent>[];
  for (final note in deduped) {
    if (note.pitch < firstKey || note.pitch > lastKey) {
      continue;
    }
    filtered.add(note);
  }

  return _NormalizedNotes(
    events: filtered,
    totalCount: totalCount,
    dedupedCount: deduped.length,
    filteredCount: filtered.length,
  );
}

class _SanitizedNotes {
  final List<_NoteEvent> events;
  final int displayFirstKey;
  final int displayLastKey;
  final int droppedOutOfVideo;
  final int droppedDup;

  const _SanitizedNotes({
    required this.events,
    required this.displayFirstKey,
    required this.displayLastKey,
    required this.droppedOutOfVideo,
    required this.droppedDup,
  });
}

class _KeyboardLayout {
  final double whiteWidth;
  final double blackWidth;
  final double displayWidth;
  final double outerWidth;
  final double stagePadding;
  final bool shouldScroll;
  final double leftPadding;
  final int firstKey;
  final int lastKey;
  final List<int> blackKeys;

  const _KeyboardLayout({
    required this.whiteWidth,
    required this.blackWidth,
    required this.displayWidth,
    required this.outerWidth,
    required this.stagePadding,
    required this.shouldScroll,
    required this.leftPadding,
    required this.firstKey,
    required this.lastKey,
    required this.blackKeys,
  });

  double noteToX(int note) {
    return PracticeKeyboard.noteToX(
      note: note,
      firstKey: firstKey,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      blackKeys: blackKeys,
      offset: leftPadding,
    );
  }
}

class _FallingNotesPainter extends CustomPainter {
  final List<_NoteEvent> noteEvents;
  final double elapsedSec;
  final double whiteWidth;
  final double blackWidth;
  final double fallAreaHeight;
  final double fallLead;
  final double fallTail;
  final double Function(int) noteToX;
  final int firstKey;
  final int lastKey;
  final Set<int> targetNotes;
  final int? successNote;
  final bool successFlashActive;
  final int? wrongNote;
  final bool wrongFlashActive;
  final bool forceLabels;
  final bool showGuides;
  final bool showMidiNumbers;

  static const List<int> _blackKeySteps = [1, 3, 6, 8, 10];
  static final Map<String, TextPainter> _labelFillCache = {};
  static final Map<String, TextPainter> _labelStrokeCache = {};
  static int _paintCallCount = 0;

  _FallingNotesPainter({
    required this.noteEvents,
    required this.elapsedSec,
    required this.whiteWidth,
    required this.blackWidth,
    required this.fallAreaHeight,
    required this.fallLead,
    required this.fallTail,
    required this.noteToX,
    required this.firstKey,
    required this.lastKey,
    required this.targetNotes,
    required this.successNote,
    required this.successFlashActive,
    required this.wrongNote,
    required this.wrongFlashActive,
    required this.forceLabels,
    required this.showGuides,
    required this.showMidiNumbers,
  });

  String _labelForSpace(
    int midi,
    double width,
    double barHeight, {
    required bool forceFull,
  }) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final base = names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    final fullLabel = '$base$octave ($midi)';
    final octaveLabel = '$base$octave';
    if (width < 16 || barHeight < 16) {
      return base;
    }
    return forceFull ? fullLabel : octaveLabel;
  }

  double _labelFontSize(double width, double barHeight, String label) {
    final widthFactor = label.length <= 2 ? 0.75 : 0.6;
    final raw = min(barHeight * 0.55, width * widthFactor);
    return raw.clamp(12.0, 18.0);
  }

  TextPainter _getLabelPainter(
    String label,
    double fontSize, {
    required bool stroke,
  }) {
    final key = '$label:${fontSize.toStringAsFixed(1)}:${stroke ? 's' : 'f'}';
    final cache = stroke ? _labelStrokeCache : _labelFillCache;
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }
    final paint = Paint()
      ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = stroke ? 2.0 : 0.0
      ..color = stroke ? Colors.black : Colors.white;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          foreground: paint,
          shadows: stroke
              ? null
              : [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    cache[key] = painter;
    return painter;
  }

  /// CANONICAL MAPPING: time → screen y-coordinate
  /// Mathematically proven formula for falling notes.
  ///
  /// Coordinate system:
  /// - y=0 at TOP of falling area
  /// - y increases DOWNWARD
  /// - hitLineY = y position where note "hits" (typically fallAreaHeight)
  ///
  /// Given:
  /// - note.startSec: absolute time note should hit the target
  /// - fallLead: time (seconds) for note to travel from top to hit line
  /// - elapsedSec: current elapsed time
  /// - fallAreaHeight: vertical pixels from top to hit line
  ///
  /// Formula:
  /// progress = (elapsedSec - (note.startSec - fallLead)) / fallLead
  /// y = progress * fallAreaHeight
  ///
  /// Boundary conditions:
  /// - elapsed = note.start - fallLead => y = 0 (note spawns at top)
  /// - elapsed = note.start => y = fallAreaHeight (note hits line)
  /// - progress < 0 => note not yet visible (above screen)
  /// - progress > (1 + tailDuration/fallLead) => note has disappeared below
  double _computeNoteYPosition(
    double noteStartSec,
    double currentElapsedSec, {
    required double fallLeadSec,
    required double fallAreaHeightPx,
  }) {
    if (fallLeadSec <= 0) return 0;
    final progress =
        (currentElapsedSec - (noteStartSec - fallLeadSec)) / fallLeadSec;
    return progress * fallAreaHeightPx;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    
    // DEBUG: Log paint calls during countdown (limit to first 10)
    if (elapsedSec < 0 && _paintCallCount < 10) {
      _paintCallCount++;
      debugPrint('[PAINTER] paint() call #$_paintCallCount: elapsed=$elapsedSec fallLead=$fallLead noteCount=${noteEvents.length} size=$size');
    }
    
    if (showGuides) {
      final guidePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      for (int note = firstKey; note <= lastKey; note++) {
        if (_blackKeySteps.contains(note % 12)) {
          continue;
        }
        final x = noteToX(note) + (whiteWidth / 2);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), guidePaint);
      }
    }

    // CULLING: only draw notes within active window
    int drawnCount = 0;
    for (final n in noteEvents) {
      if (n.pitch < firstKey || n.pitch > lastKey) {
        continue;
      }
      // CRITICAL FIX: Allow negative elapsed (countdown) - notes must spawn offscreen top
      // Only cull notes that are completely past (not future - countdown has elapsed < 0)
      final disappear = n.end + fallTail;
      if (elapsedSec > disappear && elapsedSec > 0) continue; // Skip only if past AND not countdown

      // Use CANONICAL mapping for vertical position
      final bottomY = _computeNoteYPosition(
        n.start,
        elapsedSec,
        fallLeadSec: fallLead,
        fallAreaHeightPx: fallAreaHeight,
      );
      final topY = _computeNoteYPosition(
        n.end,
        elapsedSec,
        fallLeadSec: fallLead,
        fallAreaHeightPx: fallAreaHeight,
      );

      // DEBUG: Log Y positions for first few notes during countdown
      if (elapsedSec < 0 && _paintCallCount <= 3 && drawnCount < 3) {
        debugPrint('[PAINTER] Note midi=${n.pitch} start=${n.start} end=${n.end}: topY=$topY bottomY=$bottomY (elapsed=$elapsedSec fallLead=$fallLead height=$fallAreaHeight)');
      }

      final rectTop = topY;
      final rectBottom = bottomY;
      // Cull notes completely outside visible area (allows spawnY < 0 offscreen)
      if (rectBottom < 0 || rectTop > fallAreaHeight) {
        continue;
      }
      final barHeight = max(1.0, rectBottom - rectTop);

      final x = noteToX(n.pitch);
      // C5: Skip if noteToX returns null (safety) - should never happen
      if (x.isNaN || x.isInfinite || x < -1000 || x > size.width + 1000) {
        continue;
      }
      final isBlack = _blackKeySteps.contains(n.pitch % 12);
      final width = isBlack ? blackWidth : whiteWidth;
      if (x + width < 0 || x > size.width) {
        continue;
      }

      // FIX FINAL V2: Check if note rectangle CROSSES keyboard line (visual intersection)
      // BUG WAS: targetNotes contains all pitches → colored ALL notes with same pitch
      // ATTEMPT 1 FAILED: elapsedSec >= n.start (fails during countdown when elapsed negative)
      // ATTEMPT 2 FAILED: Time window ±0.5s (doesn't match _computeImpactNotes duration logic)
      // ATTEMPT 3 FAILED: Check bottomY only (misses long notes crossing keyboard)
      // SOLUTION: Check if rectangle [topY, bottomY] intersects keyboard zone
      // Long notes: topY=200px, bottomY=600px → crosses keyboard@400px ✓
      final hitZonePixels = 50.0; // Visual tolerance around keyboard line
      final keyboardY = fallAreaHeight;
      final rectTop = min(topY, bottomY);
      final rectBot = max(topY, bottomY);
      final isCrossingKeyboard = (rectTop <= keyboardY + hitZonePixels) && 
                                  (rectBot >= keyboardY - hitZonePixels);
      final isTarget = isCrossingKeyboard && targetNotes.contains(n.pitch);
      final isSuccessFlash =
          successFlashActive && successNote != null && n.pitch == successNote;
      final isWrongFlash =
          wrongFlashActive && wrongNote != null && n.pitch == wrongNote;

      // FIX BUG 5+7: Change rectangle color when note hit, not just halo
      // Before: Rectangle stayed orange with blue halo overlay (inconsistent)
      // After: Rectangle becomes green/cyan like keyboard key (consistent visual feedback)
      if (isTarget) {
        final glowPaint = Paint()
          ..color = AppColors.success.withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        final glowRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - 2,
            rectBottom - barHeight - 2,
            width + 4,
            barHeight + 4,
          ),
          const Radius.circular(5),
        );
        canvas.drawRRect(glowRect, glowPaint);
      }

      // Priority: successFlash > wrongFlash > isTarget (note hit) > default (orange)
      paint.color = isSuccessFlash
          ? AppColors.success.withValues(alpha: 0.95)
          : isWrongFlash
          ? AppColors.error.withValues(alpha: 0.9)
          : isTarget
          ? AppColors.success.withValues(alpha: 0.85)
          : AppColors.warning.withValues(alpha: 0.85);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, rectBottom - barHeight, width, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);

      final label = _labelForSpace(
        n.pitch,
        width,
        barHeight,
        forceFull: showMidiNumbers || isTarget,
      );
      final fontSize = _labelFontSize(width, barHeight, label);
      final textPainter = _getLabelPainter(label, fontSize, stroke: false);
      final labelY = max(
        rectBottom - textPainter.height - 4,
        rectBottom - barHeight + 2,
      );
      final maxLabelY = max(0.0, fallAreaHeight - textPainter.height);
      final clampedLabelY = labelY.clamp(0.0, maxLabelY);
      final textOffset = Offset(
        x + (width - textPainter.width) / 2,
        clampedLabelY,
      );
      final canDrawLabel =
          width > 4 &&
          (barHeight > textPainter.height + 4 || forceLabels || isTarget);
      if (canDrawLabel) {
        final background = Paint()..color = Colors.black.withValues(alpha: 0.4);
        final padX = 3.0;
        final padY = 2.0;
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            textOffset.dx - padX,
            textOffset.dy - padY,
            textPainter.width + (padX * 2),
            textPainter.height + (padY * 2),
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(bgRect, background);
        final strokePainter = _getLabelPainter(label, fontSize, stroke: true);
        strokePainter.paint(canvas, textOffset);
        textPainter.paint(canvas, textOffset);
      }
      
      drawnCount++;
    }
    
    // DEBUG: Log drawn notes during countdown (limit)
    if (elapsedSec < 0 && _paintCallCount <= 10) {
      debugPrint('[PAINTER] Drawn $drawnCount notes during countdown');
    }
  }

  @override
  bool shouldRepaint(covariant _FallingNotesPainter oldDelegate) {
    return oldDelegate.elapsedSec != elapsedSec ||
        oldDelegate.noteEvents != noteEvents ||
        oldDelegate.whiteWidth != whiteWidth ||
        oldDelegate.blackWidth != blackWidth ||
        oldDelegate.fallAreaHeight != fallAreaHeight ||
        oldDelegate.fallLead != fallLead ||
        oldDelegate.fallTail != fallTail ||
        oldDelegate.noteToX != noteToX ||
        !setEquals(oldDelegate.targetNotes, targetNotes) ||
        oldDelegate.firstKey != firstKey ||
        oldDelegate.lastKey != lastKey ||
        oldDelegate.successNote != successNote ||
        oldDelegate.successFlashActive != successFlashActive ||
        oldDelegate.wrongNote != wrongNote ||
        oldDelegate.wrongFlashActive != wrongFlashActive ||
        oldDelegate.forceLabels != forceLabels ||
        oldDelegate.showGuides != showGuides ||
        oldDelegate.showMidiNumbers != showMidiNumbers;
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
