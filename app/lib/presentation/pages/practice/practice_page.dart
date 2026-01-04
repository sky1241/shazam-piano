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
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/strings_fr.dart';
import '../../../core/debug/debug_job_guard.dart';
import '../../../domain/entities/level_result.dart';
import '../../widgets/practice_keyboard.dart';
import '../../widgets/banner_ad_placeholder.dart';
import 'pitch_detector.dart';

@visibleForTesting
bool isVideoEnded(Duration position, Duration duration) {
  final endThreshold = duration - const Duration(milliseconds: 100);
  final safeThreshold = endThreshold.isNegative ? Duration.zero : endThreshold;
  return position >= safeThreshold;
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

  bool _isListening = false;
  int? _detectedNote;
  NoteAccuracy _accuracy = NoteAccuracy.miss;
  int _score = 0;
  int _totalNotes = 0;
  int _correctNotes = 0;
  DateTime? _startTime;
  StreamSubscription<List<int>>? _micSub;
  final RecorderStream _recorder = RecorderStream();
  StreamSubscription<MidiPacket>? _midiSub;
  final _pitchDetector = PitchDetector();
  List<_NoteEvent> _rawNoteEvents = [];
  List<_NoteEvent> _noteEvents = [];
  List<bool> _hitNotes = [];
  double _latencyMs = 0;
  final AudioPlayer _beepPlayer = AudioPlayer();
  static const double _fallbackLatencyMs =
      100.0; // Default offset if calibration fails
  bool _useMidi = false;
  bool _midiAvailable = false;
  late final Ticker _ticker;
  static const double _fallLeadSec = 2.0;
  static const double _fallTailSec = 0.6;
  static const Duration _successFlashDuration = Duration(milliseconds: 200);
  static const double _minConfidenceForFeedback = 0.2;
  static const Duration _devTapWindow = Duration(seconds: 2);
  static const int _devTapTarget = 5;
  static const double _videoCropFactor = 0.65;
  final ScrollController _keyboardScrollController = ScrollController();
  double _keyboardScrollOffset = 0.0;
  static const int _micMaxBufferSamples = PitchDetector.bufferSize * 4;
  final List<double> _micBuffer = <double>[];
  VideoPlayerController? _videoController;
  double? _videoDurationSec;
  ChewieController? _chewieController;
  bool _videoLoading = true;
  String? _videoError;
  bool _notesLoading = false;
  String? _notesError;
  PermissionStatus? _micPermissionStatus;
  bool _showMicPermissionFallback = false;
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
  bool _devHudEnabled = false;
  int _devTapCount = 0;
  DateTime? _devTapStartAt;
  DateTime? _lastCorrectHitAt;
  int? _lastCorrectNote;
  int? _lastCorrectDetectedNote;
  DateTime? _lastWrongHitAt;
  int? _lastWrongDetectedNote;

  // Default keyboard range (A#1 to C7 = 63 keys).
  static const int _defaultFirstKey = 34; // A#1
  static const int _defaultLastKey = 96; // C7
  static const int _rangeMargin = 2;
  static const double _minNoteDurationSec = 0.03;
  static const double _maxNoteDurationFallbackSec = 10.0;
  static const double _dedupeToleranceSec = 0.01;
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
      if (mounted && _isListening) {
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
      _loadNoteEvents();
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
    final instructionText = _isListening ? 'ECOUTE LA NOTE' : 'APPUIE SUR PLAY';
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
          IconButton(
            icon: Icon(
              _isListening ? Icons.stop : Icons.play_arrow,
              color: AppColors.primary,
            ),
            onPressed: _togglePractice,
          ),
          if (kDebugMode && _devHudEnabled)
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Diagnose',
              onPressed: _showDiagnostics,
            ),
        ],
      ),
      bottomNavigationBar: const BannerAdPlaceholder(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _practiceHorizontalPadding(
                MediaQuery.of(context).size.width,
              ),
              vertical: AppConstants.spacing8,
            ),
            child: _buildTopStatsLine(),
          ),
          _buildMicDebugHud(),
          const SizedBox(height: AppConstants.spacing16),
          Center(
            child: Text(
              instructionText,
              style: instructionStyle,
              textAlign: TextAlign.center,
            ),
          ),
          if (_showMicPermissionFallback) _buildMicPermissionFallback(),
          const SizedBox(height: AppConstants.spacing12),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildVideoPlayer()),
                _buildPracticeStage(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _practiceHorizontalPadding(double screenWidth) {
    return screenWidth < 360 ? AppConstants.spacing8 : AppConstants.spacing16;
  }

  Widget _buildTopStatsLine() {
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

  int? _resolveTargetNote() {
    if (_noteEvents.isEmpty) {
      return null;
    }
    final elapsed = _startTime == null ? null : _practiceClockSec();
    int? nextUpcoming;

    for (var i = 0; i < _noteEvents.length; i++) {
      final wasHit = i < _hitNotes.length && _hitNotes[i];
      if (wasHit) {
        continue;
      }
      final note = _noteEvents[i];
      if (elapsed != null &&
          elapsed >= note.start &&
          elapsed <= note.end + 0.2) {
        return note.pitch;
      }
      if (nextUpcoming == null && (elapsed == null || elapsed < note.start)) {
        nextUpcoming = note.pitch;
      }
    }

    return nextUpcoming;
  }

  int? _uiTargetNote() {
    return _normalizeToKeyboardRange(_resolveTargetNote());
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

  Widget _buildMicDebugHud() {
    if (!kDebugMode || !_devHudEnabled) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final horizontalPadding = _practiceHorizontalPadding(
      MediaQuery.of(context).size.width,
    );
    final targetRaw = _resolveTargetNote();
    final accuracyText = _accuracy.toString().split('.').last;
    final midiAvailText = _midiAvailable ? 'yes' : 'no';
    final micNoData =
        _isListening &&
        !_useMidi &&
        (_lastMicFrameAt == null ||
            now.difference(_lastMicFrameAt!) > const Duration(seconds: 2));
    final micStatus = _isListening && !_useMidi
        ? (micNoData ? 'NO DATA' : 'ON')
        : 'OFF';
    final midiNoData =
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
    final stateLine =
        'target: ${targetRaw ?? '--'} | detected: ${_detectedNote ?? '--'} | '
        'accuracy: $accuracyText | midiAvail: $midiAvailText';

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
            line,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Row(
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
            ],
          ),
        ],
      ),
    );
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
    if (_isListening) {
      return;
    }
    _setMicPermissionFallback(false);
    await _togglePractice();
  }

  double _computeRms(List<double> samples) {
    if (samples.isEmpty) {
      return 0.0;
    }
    double sum = 0.0;
    for (final value in samples) {
      sum += value * value;
    }
    return sqrt(sum / samples.length);
  }

  double _confidenceFromRms(double rms) {
    return (rms * 4).clamp(0.0, 1.0);
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
    return mounted && _isListening && !_useMidi;
  }

  Future<void> _startMicStream() async {
    _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}

    try {
      await _recorder.initialize(sampleRate: PitchDetector.sampleRate);
      await _recorder.start();
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
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      } else {
        _isListening = false;
      }
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
    for (int i = 0; i < samples.length; i++) {
      samples[i] = sin(2 * pi * freq * i / PitchDetector.sampleRate);
    }
    final detected = _pitchDetector.detectPitch(samples);
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
    if (!_isListening || _startTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Press Play to inject A4')),
        );
      }
      return;
    }
    const freq = 440.0;
    final samples = Float32List(PitchDetector.bufferSize);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = sin(2 * pi * freq * i / PitchDetector.sampleRate);
    }
    _processSamples(samples, now: DateTime.now(), injected: true);
  }

  Widget _buildPracticeStage() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _practiceHorizontalPadding(
          MediaQuery.of(context).size.width,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = MediaQuery.of(context).size.width;
          final horizontalPadding = _practiceHorizontalPadding(screenWidth);
          // If constraints are unbounded (e.g. inside a scroll view), fall back to screen width
          final availableWidth =
              constraints.hasBoundedWidth &&
                  constraints.maxWidth.isFinite &&
                  constraints.maxWidth > 0
              ? constraints.maxWidth
              : screenWidth - (horizontalPadding * 2);

          final isPortrait =
              MediaQuery.of(context).orientation == Orientation.portrait;
          final layout = _computeKeyboardLayout(availableWidth);
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
                if (showNotesStatus)
                  const SizedBox(height: AppConstants.spacing8),
                _buildKeyboardWithSizes(
                  totalWidth: displayWidth,
                  whiteWidth: whiteWidth,
                  blackWidth: blackWidth,
                  whiteHeight: whiteHeight,
                  blackHeight: blackHeight,
                  leftPadding: layout.leftPadding,
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
        },
      ),
    );
  }

  Widget _buildKeyboardWithSizes({
    required double totalWidth,
    required double whiteWidth,
    required double blackWidth,
    required double whiteHeight,
    required double blackHeight,
    required double leftPadding,
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
      targetNote: _uiTargetNote(),
      detectedNote: _uiDetectedNote(),
      successFlashNote: _lastCorrectDetectedNote,
      successFlashActive: successFlashActive,
      wrongFlashNote: _lastWrongDetectedNote,
      wrongFlashActive: wrongFlashActive,
      leftPadding: leftPadding,
    );
  }

  Widget _buildNotesStatus(double width) {
    if (_notesLoading) {
      return SizedBox(
        width: width,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: AppConstants.spacing8),
              Text('Chargement des notes...', style: AppTextStyles.caption),
            ],
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
                onPressed: _loadNoteEvents,
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
    final stagePadding = availableWidth < 360
        ? AppConstants.spacing8
        : AppConstants.spacing12;
    final innerAvailableWidth = max(0.0, availableWidth - (stagePadding * 2));
    final whiteCount = _countWhiteKeys();
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
    );
  }

  double _practiceClockSec() {
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      final positionMs = controller.value.position.inMilliseconds.toDouble();
      final adjustedMs = (positionMs - _latencyMs).clamp(0.0, 1e12);
      return adjustedMs / 1000.0;
    }
    if (_startTime == null) {
      return 0.0;
    }
    final elapsedMs =
        DateTime.now().difference(_startTime!).inMilliseconds - _latencyMs;
    return max(0.0, elapsedMs / 1000.0);
  }

  double? _effectiveVideoDurationSec() {
    if (_videoDurationSec != null && _videoDurationSec! > 0) {
      return _videoDurationSec;
    }
    final levelDuration = widget.level.durationSec;
    if (levelDuration != null && levelDuration > 0) {
      return levelDuration;
    }
    return null;
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
    return true;
  }

  void _showVideoNotReadyHint() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Video en cours de chargement, reessaye dans un instant.',
        ),
      ),
    );
  }

  bool _isBlackKey(int note) {
    return _blackKeys.contains(note % 12);
  }

  int _countWhiteKeys() {
    int count = 0;
    for (int n = _displayFirstKey; n <= _displayLastKey; n++) {
      if (!_isBlackKey(n)) count++;
    }
    return count;
  }

  Future<void> _togglePractice() async {
    final next = !_isListening;
    if (next && !_canStartPractice()) {
      _showVideoNotReadyHint();
      return;
    }
    if (mounted) {
      setState(() {
        _isListening = next;
      });
    } else {
      _isListening = next;
    }

    if (next) {
      if (_videoController != null) {
        await _videoController!.pause();
      }
      await _startPractice();
    } else {
      await _stopPractice(showSummary: true, reason: 'user_stop');
    }
  }

  Future<void> _startPractice() async {
    if (!_canStartPractice()) {
      _showVideoNotReadyHint();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      } else {
        _isListening = false;
      }
      return;
    }
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

    // Try MIDI first
    _useMidi = await _tryStartMidi();

    if (!_useMidi) {
      final micGranted = await _ensureMicPermission();
      if (!micGranted) {
        final status = _micPermissionStatus;
        final reason = status?.isPermanentlyDenied == true
            ? 'permission_permanently_denied'
            : 'permission_denied';
        _setStopReason(reason);
        if (mounted) {
          setState(() {
            _isListening = false;
          });
        } else {
          _isListening = false;
        }
        return;
      }

      // Auto calibrate silently (latency)
      if (_latencyMs == 0) {
        await _calibrateLatency();
      }
      if (_latencyMs == 0) {
        _latencyMs = _fallbackLatencyMs; // fallback if calibration failed
      }
    }

    // Fetch expected notes from backend
    await _loadNoteEvents();
    await _startPracticeVideo();
    _score = 0;
    _correctNotes = 0;
    _totalNotes = _noteEvents.length;
    _hitNotes = List<bool>.filled(_noteEvents.length, false);
    _lastCorrectHitAt = null;
    _lastCorrectNote = null;
    _lastCorrectDetectedNote = null;
    _lastWrongHitAt = null;
    _lastWrongDetectedNote = null;
    _startTime = DateTime.now();
    _micBuffer.clear();

    if (_useMidi) {
      // Already listening via MIDI subscription
    } else {
      await _startMicStream();
    }
  }

  Future<void> _startPracticeVideo() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.seekTo(Duration.zero);
      await controller.play();
    } catch (_) {}
  }

  Future<void> _stopPractice({
    bool showSummary = false,
    String reason = 'user_stop',
  }) async {
    _setStopReason(reason);
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    } else {
      _isListening = false;
    }
    _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
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
      _lastMidiFrameAt = null;
      _lastMidiNote = null;
      _lastCorrectHitAt = null;
      _lastCorrectNote = null;
      _lastCorrectDetectedNote = null;
      _lastWrongHitAt = null;
      _lastWrongDetectedNote = null;
    });

    if (showSummary && mounted) {
      _showScoreDialog(score: score, accuracy: accuracy);
    }
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
          connectTimeout: const Duration(seconds: 20),
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
        _isListening) {
      _stopPractice(showSummary: false, reason: 'lifecycle_pause');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _keyboardScrollController.dispose();
    _micSub?.cancel();
    _midiSub?.cancel();
    try {
      _recorder.stop();
    } catch (_) {}
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _processAudioChunk(List<int> chunk) async {
    if (_startTime == null) return;
    final samples = _convertChunkToSamples(chunk);
    if (samples.isEmpty) return;
    _processSamples(samples, now: DateTime.now());
  }

  void _processSamples(
    List<double> samples, {
    required DateTime now,
    bool injected = false,
  }) {
    if (_startTime == null && !injected) return;
    _lastMicFrameAt = now;
    _micRms = _computeRms(samples);
    _appendSamples(_micBuffer, samples);

    final window = _latestWindow(_micBuffer);
    int? nextDetected;
    if (window == null) {
      _micFrequency = null;
      _micNote = null;
      _micConfidence = 0.0;
      _logMicDebug(now);
      _updateDetectedNote(null, now);
      return;
    }

    final freq = _pitchDetector.detectPitch(window);
    if (freq == null) {
      _micFrequency = null;
      _micNote = null;
      _micConfidence = 0.0;
      _logMicDebug(now);
      _updateDetectedNote(null, now);
      return;
    }
    final midi = _pitchDetector.frequencyToMidiNote(freq);
    _micFrequency = freq;
    _micNote = midi;
    _micConfidence = _confidenceFromRms(_micRms);
    _logMicDebug(now);
    nextDetected = midi;
    if (!_isListening && !injected) {
      nextDetected = null;
    }

    final prevAccuracy = _accuracy;
    final elapsed = _practiceClockSec();

    // Find active expected notes
    final activeIndices = <int>[];
    for (var i = 0; i < _noteEvents.length; i++) {
      final n = _noteEvents[i];
      if (elapsed >= n.start && elapsed <= n.end + 0.2) {
        activeIndices.add(i);
      }
      if (elapsed > n.end + 0.2 && !_hitNotes[i]) {
        _hitNotes[i] = true; // mark as processed
      }
    }

    bool matched = false;
    for (final idx in activeIndices) {
      if (_hitNotes[idx]) continue;
      if ((midi - _noteEvents[idx].pitch).abs() <= 1) {
        matched = true;
        _hitNotes[idx] = true;
        _correctNotes += 1;
        _score += 1;
        _accuracy = NoteAccuracy.correct;
        _registerCorrectHit(
          targetNote: _noteEvents[idx].pitch,
          detectedNote: midi,
          now: now,
        );
        break;
      }
    }

    if (!matched && activeIndices.isNotEmpty) {
      _accuracy = NoteAccuracy.wrong;
      final isConfident = _micConfidence >= _minConfidenceForFeedback;
      if (nextDetected != null && isConfident) {
        _registerWrongHit(detectedNote: nextDetected, now: now);
      }
    }

    final accuracyChanged = prevAccuracy != _accuracy;
    _updateDetectedNote(nextDetected, now, accuracyChanged: accuracyChanged);
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
    _lastCorrectDetectedNote = detectedNote;
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
    if (tooSoon && _lastWrongDetectedNote == detectedNote) {
      return;
    }
    _lastWrongHitAt = now;
    _lastWrongDetectedNote = detectedNote;
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

    for (final value in chunk) {
      if (value < -32768 || value > 32767) {
        continue;
      }
      samples.add(value / 32768.0);
    }
    return samples;
  }

  void _appendSamples(List<double> buffer, List<double> samples) {
    if (samples.isEmpty) return;
    buffer.addAll(samples);
    if (buffer.length > _micMaxBufferSamples) {
      buffer.removeRange(0, buffer.length - _micMaxBufferSamples);
    }
  }

  Float32List? _latestWindow(List<double> buffer) {
    if (buffer.length < PitchDetector.bufferSize) return null;
    final start = buffer.length - PitchDetector.bufferSize;
    return Float32List.fromList(buffer.sublist(start));
  }

  _SanitizedNotes _sanitizeNoteEvents({
    required List<_NoteEvent> rawEvents,
    required double minDurationSec,
    required double maxDurationSec,
    double? videoDurationSec,
  }) {
    var droppedInvalidTiming = 0;
    var droppedTooShort = 0;
    var droppedTooLong = 0;
    var droppedDup = 0;
    var droppedOutOfRange = 0;
    var droppedOutOfVideo = 0;
    var clampedToVideo = 0;
    int? minPitch;
    int? maxPitch;
    final durationFilteredEvents = <_NoteEvent>[];
    final longNoteSamples = <String>[];

    final maxStartSec = videoDurationSec != null
        ? videoDurationSec + _videoDurationToleranceSec
        : null;

    for (final note in rawEvents) {
      var start = note.start;
      var end = note.end;
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
          clampedToVideo += 1;
        }
      }

      final duration = end - start;
      if (duration <= 0) {
        droppedInvalidTiming += 1;
        continue;
      }
      if (duration < minDurationSec) {
        droppedTooShort += 1;
        continue;
      }
      if (duration > maxDurationSec) {
        droppedTooLong += 1;
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
        droppedOutOfRange += 1;
        continue;
      }
      noteEvents.add(note);
    }

    if (kDebugMode) {
      final videoLabel = videoDurationSec == null
          ? '-'
          : videoDurationSec.toStringAsFixed(2);
      debugPrint(
        'Practice notes sanitized: kept=${noteEvents.length} '
        'minPitch=${minPitch ?? '-'} maxPitch=${maxPitch ?? '-'} '
        'displayFirstKey=$clampedFirstKey displayLastKey=$clampedLastKey '
        'videoDurationSec=$videoLabel '
        'droppedTiming=$droppedInvalidTiming '
        'droppedTooShort=$droppedTooShort '
        'droppedTooLong=$droppedTooLong '
        'droppedDup=$droppedDup '
        'droppedOutOfVideo=$droppedOutOfVideo '
        'clampedToVideo=$clampedToVideo '
        'droppedOutOfRange=$droppedOutOfRange',
      );
      if (longNoteSamples.isNotEmpty) {
        debugPrint(
          'Practice notes long samples: ${longNoteSamples.join(' | ')}',
        );
      }
    }

    return _SanitizedNotes(
      events: noteEvents,
      displayFirstKey: clampedFirstKey,
      displayLastKey: clampedLastKey,
    );
  }

  void _resanitizeNoteEventsForVideoDuration() {
    if (_rawNoteEvents.isEmpty || _notesLoading || _isListening) {
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
    if (mounted) {
      setState(() {
        _noteEvents = sanitized.events;
        _displayFirstKey = sanitized.displayFirstKey;
        _displayLastKey = sanitized.displayLastKey;
        _notesError = sanitized.events.isEmpty ? 'Notes indisponibles' : null;
      });
    } else {
      _noteEvents = sanitized.events;
      _displayFirstKey = sanitized.displayFirstKey;
      _displayLastKey = sanitized.displayLastKey;
      _notesError = sanitized.events.isEmpty ? 'Notes indisponibles' : null;
    }
  }

  Future<void> _loadNoteEvents() async {
    if (mounted) {
      setState(() {
        _notesLoading = true;
        _notesError = null;
      });
    } else {
      _notesLoading = true;
      _notesError = null;
    }

    final midiUrl = widget.level.midiUrl;
    final jobId = _extractJobId(midiUrl);
    if (jobId == null) {
      if (mounted) {
        setState(() {
          _notesLoading = false;
          _notesError = 'Notes indisponibles';
          _rawNoteEvents = [];
          _noteEvents = [];
          _displayFirstKey = _defaultFirstKey;
          _displayLastKey = _defaultLastKey;
        });
      } else {
        _notesLoading = false;
        _notesError = 'Notes indisponibles';
        _rawNoteEvents = [];
        _noteEvents = [];
        _displayFirstKey = _defaultFirstKey;
        _displayLastKey = _defaultLastKey;
      }
      debugPrint('Practice notes: invalid job id for $midiUrl');
      return;
    }

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
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
      final url = '/practice/notes/$jobId/${widget.level.level}';
      final rawEvents =
          expectedNotes ??
          await () async {
            if (kDebugMode) {
              debugPrint('Practice notes: fallback to MIDI notes url=$url');
            }
            final resp = await dio.get(url);
            final data = _decodeNotesPayload(resp.data);
            return _parseNoteEvents(data['notes']);
          }();
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
      final noteEvents = sanitized.events;
      final clampedFirstKey = sanitized.displayFirstKey;
      final clampedLastKey = sanitized.displayLastKey;

      if (mounted) {
        setState(() {
          _noteEvents = noteEvents;
          _displayFirstKey = clampedFirstKey;
          _displayLastKey = clampedLastKey;
          _notesLoading = false;
          _notesError = noteEvents.isEmpty ? 'Notes indisponibles' : null;
        });
      } else {
        _noteEvents = noteEvents;
        _displayFirstKey = clampedFirstKey;
        _displayLastKey = clampedLastKey;
        _notesLoading = false;
        _notesError = noteEvents.isEmpty ? 'Notes indisponibles' : null;
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint(
        'Practice notes error: midiUrl=$midiUrl status=$status error=$e',
      );
      if (mounted) {
        setState(() {
          _rawNoteEvents = [];
          _noteEvents = [];
          _notesLoading = false;
          _notesError = 'Notes indisponibles';
          _displayFirstKey = _defaultFirstKey;
          _displayLastKey = _defaultLastKey;
        });
      } else {
        _rawNoteEvents = [];
        _noteEvents = [];
        _notesLoading = false;
        _notesError = 'Notes indisponibles';
        _displayFirstKey = _defaultFirstKey;
        _displayLastKey = _defaultLastKey;
      }
    } catch (e) {
      debugPrint('Practice notes error: midiUrl=$midiUrl error=$e');
      if (mounted) {
        setState(() {
          _rawNoteEvents = [];
          _noteEvents = [];
          _notesLoading = false;
          _notesError = 'Notes indisponibles';
          _displayFirstKey = _defaultFirstKey;
          _displayLastKey = _defaultLastKey;
        });
      } else {
        _rawNoteEvents = [];
        _noteEvents = [];
        _notesLoading = false;
        _notesError = 'Notes indisponibles';
        _displayFirstKey = _defaultFirstKey;
        _displayLastKey = _defaultLastKey;
      }
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
    events.sort((a, b) => a.start.compareTo(b.start));
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
      await recorder.initialize(sampleRate: PitchDetector.sampleRate);
      await recorder.start();
      calibSub = recorder.audioStream.listen((chunk) {
        if (beepStart == null) return;
        final samples = _convertChunkToSamples(chunk);
        if (samples.isEmpty) return;
        _appendSamples(calibBuffer, samples);
        final window = _latestWindow(calibBuffer);
        if (window == null) return;
        final freq = _pitchDetector.detectPitch(window);
        if (freq == null) return;
        if ((freq - targetFreq).abs() < 80) {
          final delta = DateTime.now().difference(beepStart).inMilliseconds;
          _latencyMs = delta.toDouble();
        }
      });

      // Play beep from generated bytes
      final beepBytes = _generateBeepBytes(
        durationMs: 400,
        freq: targetFreq,
        sampleRate: PitchDetector.sampleRate,
      );
      beepStart = DateTime.now();
      await _beepPlayer.play(BytesSource(beepBytes));
      await Future.delayed(Duration(milliseconds: durationMs));
    } catch (_) {
      // ignore
    } finally {
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
      final elapsed = _practiceClockSec();

      // Find active expected notes
      final activeIndices = <int>[];
      for (var i = 0; i < _noteEvents.length; i++) {
        final n = _noteEvents[i];
        if (elapsed >= n.start && elapsed <= n.end + 0.2) {
          activeIndices.add(i);
        }
        if (elapsed > n.end + 0.2 && !_hitNotes[i]) {
          _hitNotes[i] = true; // mark as processed
        }
      }

      bool matched = false;
      for (final idx in activeIndices) {
        if (_hitNotes[idx]) continue;
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
        _accuracy = NoteAccuracy.wrong;
        _registerWrongHit(detectedNote: note, now: now);
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
    try {
      await _disposeVideoControllers();
      _videoEndFired = false;
      setState(() {
        _videoLoading = true;
        _videoError = null;
      });

      final previewUrl = widget.level.previewUrl;
      final fullUrl = widget.level.videoUrl;
      String selectedUrl;
      if (widget.forcePreview) {
        if (previewUrl.isEmpty) {
          setState(() {
            _videoError = 'Aucun aperçu disponible';
            _videoLoading = false;
          });
          return;
        }
        selectedUrl = previewUrl;
      } else {
        selectedUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
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
      _videoController!.addListener(() {
        if (_videoController == null) return;
        final value = _videoController!.value;
        if (!value.isInitialized || value.duration == Duration.zero) {
          return;
        }
        if (_videoEndFired) {
          return;
        }
        if (_isListening && isVideoEnded(value.position, value.duration)) {
          _videoEndFired = true;
          unawaited(_stopPractice(showSummary: true, reason: 'video_end'));
        }
      });
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: false,
        showControls: true,
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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnose Assets'),
        content: Text(lines),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    _hitNotes = List<bool>.filled(_noteEvents.length, false);
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
        _lastWrongDetectedNote != null &&
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

  Widget _buildVideoPlayer() {
    return _wrapPracticeVideo(
      LayoutBuilder(
        builder: (context, constraints) {
          final aspectRatio = _chewieController?.aspectRatio ?? 16 / 9;
          final videoLayer = _buildCroppedVideoLayer(
            aspectRatio: aspectRatio,
            child: _buildVideoContent(),
          );
          return Stack(
            children: [
              Positioned.fill(child: videoLayer),
              Positioned.fill(child: _buildNotesOverlay(constraints)),
            ],
          );
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

  Widget _buildNotesOverlay(BoxConstraints constraints) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = _practiceHorizontalPadding(screenWidth);
    final availableWidth = min(
      constraints.maxWidth,
      screenWidth - (horizontalPadding * 2),
    );
    final now = DateTime.now();
    final successFlashActive = _isSuccessFlashActive(now);
    final wrongFlashActive = _isWrongFlashActive(now);
    final shouldPaintNotes = _isListening && _startTime != null;
    final targetNote = shouldPaintNotes ? _uiTargetNote() : null;
    final noteEvents = shouldPaintNotes ? _noteEvents : const <_NoteEvent>[];
    final layout = _computeKeyboardLayout(availableWidth);
    final scrollOffset = layout.shouldScroll ? _keyboardScrollOffset : 0.0;
    double noteToX(int note) {
      final x = PracticeKeyboard.noteToX(
        note: note,
        firstKey: _displayFirstKey,
        whiteWidth: layout.whiteWidth,
        blackWidth: layout.blackWidth,
        blackKeys: _blackKeys,
        offset: layout.leftPadding,
      );
      return x - scrollOffset;
    }

    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: layout.outerWidth,
          height: constraints.maxHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: layout.stagePadding),
            child: CustomPaint(
              key: const Key('practice_notes_overlay'),
              size: Size(layout.displayWidth, constraints.maxHeight),
              painter: _FallingNotesPainter(
                noteEvents: noteEvents,
                elapsedSec: shouldPaintNotes ? _practiceClockSec() : 0.0,
                whiteWidth: layout.whiteWidth,
                blackWidth: layout.blackWidth,
                fallAreaHeight: constraints.maxHeight,
                fallLead: _fallLeadSec,
                fallTail: _fallTailSec,
                noteToX: noteToX,
                targetNote: targetNote,
                successNote: _lastCorrectNote,
                successFlashActive: successFlashActive,
                wrongNote: _lastWrongDetectedNote,
                wrongFlashActive: wrongFlashActive,
                forceLabels: widget.forcePreview,
              ),
            ),
          ),
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

class _SanitizedNotes {
  final List<_NoteEvent> events;
  final int displayFirstKey;
  final int displayLastKey;

  const _SanitizedNotes({
    required this.events,
    required this.displayFirstKey,
    required this.displayLastKey,
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

  const _KeyboardLayout({
    required this.whiteWidth,
    required this.blackWidth,
    required this.displayWidth,
    required this.outerWidth,
    required this.stagePadding,
    required this.shouldScroll,
    required this.leftPadding,
  });
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
  final int? targetNote;
  final int? successNote;
  final bool successFlashActive;
  final int? wrongNote;
  final bool wrongFlashActive;
  final bool forceLabels;

  static const List<int> _blackKeySteps = [1, 3, 6, 8, 10];
  static final Map<String, TextPainter> _labelFillCache = {};
  static final Map<String, TextPainter> _labelStrokeCache = {};

  _FallingNotesPainter({
    required this.noteEvents,
    required this.elapsedSec,
    required this.whiteWidth,
    required this.blackWidth,
    required this.fallAreaHeight,
    required this.fallLead,
    required this.fallTail,
    required this.noteToX,
    required this.targetNote,
    required this.successNote,
    required this.successFlashActive,
    required this.wrongNote,
    required this.wrongFlashActive,
    required this.forceLabels,
  });

  String _labelForSpace(int midi, double width, double barHeight) {
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
    final fullLabel = base == 'C' ? '$base$octave' : base;
    final noSharp = base.replaceAll('#', '');

    if (width < 10 || barHeight < 12) {
      return noSharp;
    }
    if (width < 16 || barHeight < 16) {
      return base;
    }
    return fullLabel;
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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final n in noteEvents) {
      final appear = n.start - fallLead;
      final disappear = n.end + fallTail;
      if (elapsedSec < appear || elapsedSec > disappear) continue;

      final progress = ((elapsedSec - appear) / (fallLead + fallTail)).clamp(
        0.0,
        1.0,
      );
      final y = progress * fallAreaHeight;
      final barHeight = max(10.0, (n.end - n.start) * 60);
      final rectTop = y - barHeight;
      final rectBottom = y;
      if (rectBottom < 0 || rectTop > fallAreaHeight) {
        continue;
      }

      final x = noteToX(n.pitch);
      final isBlack = _blackKeySteps.contains(n.pitch % 12);
      final width = isBlack ? blackWidth : whiteWidth;
      if (x + width < 0 || x > size.width) {
        continue;
      }

      final isTarget = targetNote != null && n.pitch == targetNote;
      final isSuccessFlash =
          successFlashActive && successNote != null && n.pitch == successNote;
      final isWrongFlash =
          wrongFlashActive && wrongNote != null && n.pitch == wrongNote;

      if (isTarget) {
        final glowPaint = Paint()
          ..color = AppColors.accent.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        final glowRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2, y - barHeight - 2, width + 4, barHeight + 4),
          const Radius.circular(5),
        );
        canvas.drawRRect(glowRect, glowPaint);
      }

      paint.color = isSuccessFlash
          ? AppColors.success.withValues(alpha: 0.95)
          : isWrongFlash
          ? AppColors.error.withValues(alpha: 0.9)
          : AppColors.warning.withValues(alpha: 0.85);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y - barHeight, width, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);

      final label = _labelForSpace(n.pitch, width, barHeight);
      final fontSize = _labelFontSize(width, barHeight, label);
      final textPainter = _getLabelPainter(label, fontSize, stroke: false);
      final labelY = max(y - textPainter.height - 4, y - barHeight + 2);
      final maxLabelY = max(0.0, fallAreaHeight - textPainter.height);
      final clampedLabelY = labelY.clamp(0.0, maxLabelY);
      final textOffset = Offset(
        x + (width - textPainter.width) / 2,
        clampedLabelY,
      );
      final canDrawLabel =
          width > 4 && (barHeight > textPainter.height + 4 || forceLabels);
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
        oldDelegate.targetNote != targetNote ||
        oldDelegate.successNote != successNote ||
        oldDelegate.successFlashActive != successFlashActive ||
        oldDelegate.wrongNote != wrongNote ||
        oldDelegate.wrongFlashActive != wrongFlashActive ||
        oldDelegate.forceLabels != forceLabels;
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
