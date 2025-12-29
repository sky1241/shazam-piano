import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import 'pitch_detector.dart';

class PracticePage extends StatefulWidget {
  final LevelResult level;

  const PracticePage({super.key, required this.level});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage>
    with SingleTickerProviderStateMixin {
  // MIDI helpers
  String noteName(int midi) {
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
    return names[midi % 12];
  }

  int noteOctave(int midi) => (midi ~/ 12) - 1; // 60 -> C4

  String noteLabel(int midi, {bool withOctave = false}) {
    final base = noteName(midi);
    return withOctave ? '$base${noteOctave(midi)}' : base;
  }

  bool _isListening = false;
  int? _detectedNote;
  int? _expectedNote;
  NoteAccuracy _accuracy = NoteAccuracy.miss;
  int _score = 0;
  int _totalNotes = 0;
  int _correctNotes = 0;
  DateTime? _startTime;
  StreamSubscription<List<int>>? _micSub;
  final RecorderStream _recorder = RecorderStream();
  StreamSubscription<MidiPacket>? _midiSub;
  final _pitchDetector = PitchDetector();
  List<_ExpectedNote> _expectedNotes = [];
  List<bool> _hitNotes = [];
  double _latencyMs = 0;
  final AudioPlayer _beepPlayer = AudioPlayer();
  static const double _fallbackLatencyMs =
      100.0; // Default offset if calibration fails
  bool _useMidi = false;
  bool _midiAvailable = false;
  List<_PracticeSession> _sessions = [];
  late final Ticker _ticker;
  static const double _fallAreaHeight = 320;
  static const double _fallLeadSec = 2.0;
  static const double _fallTailSec = 0.6;
  static const int _micMaxBufferSamples = PitchDetector.bufferSize * 4;
  final List<double> _micBuffer = <double>[];
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _videoLoading = true;
  String? _videoError;

  // Piano keyboard alignee avec la video (C2 a C7 = 61 touches)
  static const int _firstKey = 36; // C2
  static const int _lastKey = 96; // C7
  static const List<int> _blackKeys = [1, 3, 6, 8, 10]; // C#, D#, F#, G#, A#

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted && _isListening) {
        setState(() {});
      }
    })..start();
    _initVideo();
    _loadExpectedNotes();
    _loadSavedLatency();
    _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Practice - ${widget.level.name}'),
        actions: [
          IconButton(
            icon: Icon(
              _isListening ? Icons.stop : Icons.play_arrow,
              color: AppColors.primary,
            ),
            onPressed: () => _togglePractice(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing16,
                vertical: AppConstants.spacing8,
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppConstants.spacing8,
                runSpacing: AppConstants.spacing8,
                children: [
                  Wrap(
                    spacing: AppConstants.spacing8,
                    runSpacing: AppConstants.spacing8,
                    children: [
                      _buildChip(
                        label: _latencyMs > 0
                            ? 'Sync ${_latencyMs.toStringAsFixed(0)}ms'
                            : 'Sync auto',
                        color: AppColors.primary,
                      ),
                      _buildChip(
                        label: _midiAvailable ? 'MIDI connecte' : 'MIDI off',
                        color: _midiAvailable
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => _calibrateLatency(force: true),
                    child: const Text(
                      'Recalibrer',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Score display
            Container(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  bottom: BorderSide(color: AppColors.divider, width: 1),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceEvenly,
                runSpacing: AppConstants.spacing8,
                spacing: AppConstants.spacing16,
                children: [
                  _buildScoreStat('Score', _score.toString()),
                  _buildScoreStat(
                    'Precision',
                    _totalNotes > 0
                        ? '${(_correctNotes / _totalNotes * 100).toStringAsFixed(1)}%'
                        : '0%',
                  ),
                  _buildScoreStat('Notes', '$_correctNotes/$_totalNotes'),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.spacing24),

            // Current note display
            Center(
              child: Text(
                _isListening ? 'Ecoute...' : 'Appuie sur Play',
                style: AppTextStyles.title,
              ),
            ),

            const SizedBox(height: AppConstants.spacing16),

            // Accuracy indicator
            if (_detectedNote != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacing24,
                    vertical: AppConstants.spacing12,
                  ),
                  decoration: BoxDecoration(
                    color: _getAccuracyColor().withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusCard,
                    ),
                    border: Border.all(color: _getAccuracyColor(), width: 2),
                  ),
                  child: Text(
                    _getAccuracyText(),
                    style: AppTextStyles.title.copyWith(
                      color: _getAccuracyColor(),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: AppConstants.spacing24),
            // Piano roll + clavier uniquement
            _buildPracticeStage(),

            const SizedBox(height: AppConstants.spacing16),

            // Instructions
            Padding(
              padding: const EdgeInsets.all(AppConstants.spacing16),
              child: Text(
                'Joue les notes sur ton piano.\nLes touches s\'allumeront selon ta precision.',
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: AppConstants.spacing16),

            // Historique (scores précédents)
            _buildHistory(),
            const SizedBox(height: AppConstants.spacing24),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    if (_sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppConstants.spacing16),
        child: Text('Pas encore de sessions', style: AppTextStyles.caption),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacing16,
          ),
          child: Text('Historique Practice', style: AppTextStyles.title),
        ),
        const SizedBox(height: AppConstants.spacing8),
        ..._sessions.map((s) {
          final subtitleParts = <String>[];
          if (s.date != null) subtitleParts.add(s.date!);
          if (s.score != null) {
            subtitleParts.add('Score ${s.score!.toStringAsFixed(1)}');
          }
          if (s.level != null) subtitleParts.add('L${s.level}');
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing16,
              vertical: AppConstants.spacing8,
            ),
            child: Card(
              color: AppColors.surface,
              child: ListTile(
                title: Text(
                  s.title ?? 'Session ${s.jobId}',
                  style: AppTextStyles.body,
                ),
                subtitle: Text(
                  subtitleParts.join(' | '),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: Colors.white),
      ),
    );
  }

  Widget _buildScoreStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.display.copyWith(
            fontSize: 28,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  Widget _buildPracticeStage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = MediaQuery.of(context).size.width;
          // If constraints are unbounded (e.g. inside a scroll view), fall back to screen width
          final availableWidth =
              constraints.hasBoundedWidth &&
                  constraints.maxWidth.isFinite &&
                  constraints.maxWidth > 0
              ? constraints.maxWidth
              : screenWidth - (AppConstants.spacing16 * 2);

          final isPortrait =
              MediaQuery.of(context).orientation == Orientation.portrait;
          const double stagePadding = AppConstants.spacing12;
          final innerAvailableWidth = max(
            0.0,
            availableWidth - (stagePadding * 2),
          );

          final whiteCount = _countWhiteKeys();
          const double minWhiteKeyWidth = 8;
          final rawWhiteWidth = innerAvailableWidth / whiteCount;
          final whiteWidth = max(minWhiteKeyWidth, rawWhiteWidth);
          final blackWidth = whiteWidth * 0.65;
          final contentWidth = whiteWidth * whiteCount;
          final shouldScroll = contentWidth > innerAvailableWidth;
          final displayWidth = shouldScroll
              ? contentWidth
              : innerAvailableWidth;
          final outerWidth = displayWidth + (stagePadding * 2);

          final whiteHeight = isPortrait ? 90.0 : 120.0;
          final blackHeight = isPortrait ? 60.0 : 80.0;
          final fallAreaHeight = isPortrait ? 260.0 : _fallAreaHeight;

          final now = DateTime.now();
          final elapsedSec = _startTime == null
              ? 0.0
              : max(
                  0.0,
                  (now.difference(_startTime!).inMilliseconds - _latencyMs) /
                      1000.0,
                ).toDouble();

          final content = Container(
            width: outerWidth,
            padding: const EdgeInsets.all(stagePadding),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: fallAreaHeight,
                  width: displayWidth,
                  child: _expectedNotes.isEmpty
                      ? Center(
                          child: Text(
                            'Chargement des notes...',
                            style: AppTextStyles.caption,
                          ),
                        )
                      : CustomPaint(
                          painter: _FallingNotesPainter(
                            expectedNotes: _expectedNotes,
                            elapsedSec: elapsedSec,
                            whiteWidth: whiteWidth,
                            blackWidth: blackWidth,
                            fallAreaHeight: fallAreaHeight,
                            fallLead: _fallLeadSec,
                            fallTail: _fallTailSec,
                            noteToX: (n) => _noteToX(n, whiteWidth, blackWidth),
                          ),
                        ),
                ),
                const SizedBox(height: AppConstants.spacing8),
                _buildKeyboardWithSizes(
                  totalWidth: displayWidth,
                  whiteWidth: whiteWidth,
                  blackWidth: blackWidth,
                  whiteHeight: whiteHeight,
                  blackHeight: blackHeight,
                ),
              ],
            ),
          );

          if (shouldScroll) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: content,
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
  }) {
    final whiteNotes = <int>[];
    for (int note = _firstKey; note <= _lastKey; note++) {
      if (!_isBlackKey(note)) whiteNotes.add(note);
    }

    return SizedBox(
      width: totalWidth,
      height: whiteHeight + AppConstants.spacing12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Touche blanches positionnées au pixel près
          for (int i = 0; i < whiteNotes.length; i++)
            Positioned(
              left: i * whiteWidth,
              child: _buildPianoKey(
                whiteNotes[i],
                isBlack: false,
                width: whiteWidth,
                height: whiteHeight,
              ),
            ),
          // Touche noires superposées
          for (int note = _firstKey; note <= _lastKey; note++)
            if (_isBlackKey(note))
              Positioned(
                left: _noteToX(note, whiteWidth, blackWidth),
                child: _buildPianoKey(
                  note,
                  isBlack: true,
                  width: blackWidth,
                  height: blackHeight,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildPianoKey(
    int note, {
    required bool isBlack,
    double width = 30,
    double height = 180,
  }) {
    final isExpected = note == _expectedNote;
    final isDetected = note == _detectedNote;

    Color keyColor;
    if (isDetected && isExpected) {
      keyColor = _getAccuracyColor();
    } else if (isExpected) {
      keyColor = AppColors.primary.withValues(alpha: 0.5);
    } else if (isBlack) {
      keyColor = AppColors.blackKey;
    } else {
      keyColor = AppColors.whiteKey;
    }

    final keyWidth = width;
    final keyHeight = height;

    final isC = note % 12 == 0;
    final label = isBlack
        ? ''
        : (isC ? noteLabel(note, withOctave: true) : noteLabel(note));
    final labelFontSize = max(7.0, min(11.0, keyWidth * 0.45));

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: keyWidth,
          height: keyHeight,
          margin: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: keyColor,
            border: Border.all(color: AppColors.divider, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        if (label.isNotEmpty)
          Positioned(
            bottom: 4,
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                fontSize: labelFontSize,
                color: isBlack ? AppColors.whiteKey : AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  bool _isBlackKey(int note) {
    return _blackKeys.contains(note % 12);
  }

  int _countWhiteKeys() {
    int count = 0;
    for (int n = _firstKey; n <= _lastKey; n++) {
      if (!_isBlackKey(n)) count++;
    }
    return count;
  }

  double _noteToX(int note, double whiteWidth, double blackWidth) {
    int whiteIndex = 0;
    for (int n = _firstKey; n < note; n++) {
      if (!_isBlackKey(n)) {
        whiteIndex += 1;
      }
    }
    double x = whiteIndex * whiteWidth;
    if (_isBlackKey(note)) {
      x -= (blackWidth / 2);
    }
    return x;
  }

  Color _getAccuracyColor() {
    switch (_accuracy) {
      case NoteAccuracy.correct:
        return AppColors.success;
      case NoteAccuracy.close:
        return AppColors.warning;
      case NoteAccuracy.wrong:
        return AppColors.error;
      case NoteAccuracy.miss:
        return AppColors.divider;
    }
  }

  String _getAccuracyText() {
    switch (_accuracy) {
      case NoteAccuracy.correct:
        return 'Parfait !';
      case NoteAccuracy.close:
        return '~ Proche';
      case NoteAccuracy.wrong:
        return 'Faux';
      case NoteAccuracy.miss:
        return 'Aucune note';
    }
  }

  Future<void> _togglePractice() async {
    final next = !_isListening;
    setState(() {
      _isListening = next;
    });

    if (next) {
      if (_videoController != null) {
        await _videoController!.pause();
      }
      await _startPractice();
    } else {
      await _stopPractice(showSummary: true);
    }
  }

  Future<void> _startPractice() async {
    // Try MIDI first
    _useMidi = await _tryStartMidi();

    if (!_useMidi) {
      // Permissions for mic
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        setState(() {
          _isListening = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission denied')),
          );
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
    await _loadExpectedNotes();
    _score = 0;
    _correctNotes = 0;
    _totalNotes = _expectedNotes.length;
    _hitNotes = List<bool>.filled(_expectedNotes.length, false);
    _startTime = DateTime.now();
    _micBuffer.clear();

    if (_useMidi) {
      // Already listening via MIDI subscription
    } else {
      // Start mic stream
      try {
        await _recorder.initialize(sampleRate: PitchDetector.sampleRate);
        await _recorder.start();
        _micSub = _recorder.audioStream.listen(_processAudioChunk);
      } catch (_) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  Future<void> _stopPractice({bool showSummary = false}) async {
    setState(() {
      _isListening = false;
    });
    _micSub?.cancel();
    _micSub = null;
    _recorder.stop();
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
    await _loadSessions();

    setState(() {
      _detectedNote = null;
      _expectedNote = null;
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
  void dispose() {
    _ticker.dispose();
    _micSub?.cancel();
    _midiSub?.cancel();
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _processAudioChunk(List<int> chunk) async {
    if (_startTime == null) return;
    final samples = _convertChunkToSamples(chunk);
    if (samples.isEmpty) return;
    _appendSamples(_micBuffer, samples);

    final window = _latestWindow(_micBuffer);
    if (window == null) return;

    final freq = _pitchDetector.detectPitch(window);
    if (freq == null) return;
    final midi = _pitchDetector.frequencyToMidiNote(freq);

    final now = DateTime.now();
    final elapsed =
        (now.difference(_startTime!).inMilliseconds - _latencyMs).clamp(
          0,
          1e9,
        ) /
        1000.0;

    // Find active expected notes
    final activeIndices = <int>[];
    for (var i = 0; i < _expectedNotes.length; i++) {
      final n = _expectedNotes[i];
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
      if ((midi - _expectedNotes[idx].pitch).abs() <= 1) {
        matched = true;
        _hitNotes[idx] = true;
        _correctNotes += 1;
        _score += 1;
        _accuracy = NoteAccuracy.correct;
        _expectedNote = _expectedNotes[idx].pitch;
        break;
      }
    }

    if (!matched && activeIndices.isNotEmpty) {
      _accuracy = NoteAccuracy.wrong;
    }

    setState(() {
      _detectedNote = midi;
      if (!_isListening) {
        _detectedNote = null;
      }
    });
    _updateNextExpected();
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

  Future<void> _loadExpectedNotes() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.backendBaseUrl,
          connectTimeout: const Duration(seconds: 15),
        ),
      );
      dio.options.headers['Authorization'] = 'Bearer $token';

      final jobId = _extractJobId(widget.level.midiUrl);
      if (jobId == null) return;
      final resp = await dio.get(
        '/practice/notes/$jobId/${widget.level.level}',
      );
      final data = resp.data;
      if (data == null || data['notes'] == null) return;
      final List<dynamic> notesJson = data['notes'];
      _expectedNotes = notesJson
          .map(
            (n) => _ExpectedNote(
              pitch: n['pitch'] as int,
              start: (n['start'] as num).toDouble(),
              end: (n['end'] as num).toDouble(),
            ),
          )
          .toList();
      _expectedNotes.sort((a, b) => a.start.compareTo(b.start));
      if (_expectedNotes.isNotEmpty) {
        _expectedNote = _expectedNotes.first.pitch;
      }
    } catch (_) {
      // fallback: empty expected notes
      _expectedNotes = [];
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

  Future<void> _calibrateLatency({bool force = false}) async {
    // Already calibrated
    if (_latencyMs > 0 && !force) return;
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
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

  Future<void> _loadSessions() async {
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      final uid = user?.uid;
      if (uid == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('practice_sessions')
          .orderBy('ended_at', descending: true)
          .limit(20)
          .get();

      final sessions = snapshot.docs
          .map((doc) => _PracticeSession.fromDoc(doc))
          .toList();
      if (mounted) {
        setState(() {
          _sessions = sessions;
        });
      }
    } catch (_) {
      // ignore history errors in UI
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
      final elapsed = now.difference(_startTime!).inMilliseconds / 1000.0;

      // Find active expected notes
      final activeIndices = <int>[];
      for (var i = 0; i < _expectedNotes.length; i++) {
        final n = _expectedNotes[i];
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
        if ((note - _expectedNotes[idx].pitch).abs() <= 1) {
          matched = true;
          _hitNotes[idx] = true;
          _correctNotes += 1;
          _score += 1;
          _accuracy = NoteAccuracy.correct;
          _expectedNote = _expectedNotes[idx].pitch;
          break;
        }
      }

      if (!matched && activeIndices.isNotEmpty) {
        _accuracy = NoteAccuracy.wrong;
      }

      setState(() {
        _detectedNote = note;
        if (!_isListening) {
          _detectedNote = null;
        }
      });
      _updateNextExpected();
    }
  }

  void _updateNextExpected() {
    for (var i = 0; i < _expectedNotes.length; i++) {
      if (!_hitNotes[i]) {
        _expectedNote = _expectedNotes[i].pitch;
        return;
      }
    }
    _expectedNote = null;
  }

  Future<void> _initVideo() async {
    try {
      setState(() {
        _videoLoading = true;
        _videoError = null;
      });

      String resolveUrl(String url) {
        if (url.isEmpty) return url;
        if (url.startsWith('http')) return url;
        final baseRaw = AppConstants.backendBaseUrl.trim();
        final base = baseRaw.isEmpty ? 'http://127.0.0.1:8000' : baseRaw;
        final baseWithSlash = base.endsWith('/') ? base : '$base/';
        final cleaned = url.startsWith('/') ? url.substring(1) : url;
        return Uri.parse(baseWithSlash).resolve(cleaned).toString();
      }

      final url = resolveUrl(
        widget.level.previewUrl.isNotEmpty
            ? widget.level.previewUrl
            : widget.level.videoUrl,
      );
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
      _videoController!.addListener(() {
        if (_videoController == null) return;
        final value = _videoController!.value;
        if (value.position >= value.duration && _isListening) {
          _stopPractice(showSummary: true);
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

  // ignore: unused_element
  Widget _buildVideoPlayer() {
    if (_videoError != null) {
      return Container(
        color: Colors.black,
        height: 200,
        alignment: Alignment.center,
        child: Text(
          _videoError!,
          style: AppTextStyles.caption.copyWith(color: Colors.white),
        ),
      );
    }
    if (_videoLoading || _chewieController == null) {
      return Container(
        color: Colors.black,
        height: 200,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    return AspectRatio(
      aspectRatio: _chewieController!.aspectRatio ?? 16 / 9,
      child: Chewie(controller: _chewieController!),
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

class _PracticeSession {
  final String id;
  final String? jobId;
  final String? title;
  final double? score;
  final double? accuracy;
  final int? level;
  final String? date;

  _PracticeSession({
    required this.id,
    this.jobId,
    this.title,
    this.score,
    this.accuracy,
    this.level,
    this.date,
  });

  factory _PracticeSession.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    DateTime? asDate(dynamic value) {
      try {
        if (value is Timestamp) return value.toDate();
        if (value is String) return DateTime.parse(value);
      } catch (_) {}
      return null;
    }

    String? formatDate(dynamic value) {
      final dt = asDate(value);
      if (dt == null) return null;
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
    }

    final rawTitle =
        data['title'] ?? data['identified_title'] ?? data['identifiedTitle'];

    return _PracticeSession(
      id: doc.id,
      jobId: data['job_id'] as String?,
      title: rawTitle is String ? rawTitle : null,
      score: (data['score'] as num?)?.toDouble(),
      accuracy: (data['accuracy'] as num?)?.toDouble(),
      level: (data['level'] as num?)?.toInt(),
      date: formatDate(data['ended_at'] ?? data['started_at']),
    );
  }
}

class _ExpectedNote {
  final int pitch;
  final double start;
  final double end;
  _ExpectedNote({required this.pitch, required this.start, required this.end});
}

class _FallingNotesPainter extends CustomPainter {
  final List<_ExpectedNote> expectedNotes;
  final double elapsedSec;
  final double whiteWidth;
  final double blackWidth;
  final double fallAreaHeight;
  final double fallLead;
  final double fallTail;
  final double Function(int) noteToX;
  static final Map<String, TextPainter> _labelCache = {};

  String _barLabel(int midi) {
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
    return '$base$octave';
  }

  TextPainter _getLabelPainter(String label, double fontSize) {
    final key = '$label:${fontSize.toStringAsFixed(1)}';
    final cached = _labelCache[key];
    if (cached != null) {
      return cached;
    }
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _labelCache[key] = painter;
    return painter;
  }

  _FallingNotesPainter({
    required this.expectedNotes,
    required this.elapsedSec,
    required this.whiteWidth,
    required this.blackWidth,
    required this.fallAreaHeight,
    required this.fallLead,
    required this.fallTail,
    required this.noteToX,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final n in expectedNotes) {
      final appear = n.start - fallLead;
      final disappear = n.end + fallTail;
      if (elapsedSec < appear || elapsedSec > disappear) continue;

      final progress = ((elapsedSec - appear) / (fallLead + fallTail)).clamp(
        0.0,
        1.0,
      );
      final y = progress * fallAreaHeight;
      final barHeight = max(10.0, (n.end - n.start) * 60);

      final x = noteToX(n.pitch);
      final isBlack = _PracticePageState._blackKeys.contains(n.pitch % 12);
      final width = isBlack ? blackWidth : whiteWidth;

      paint.color = const Color(0xFF4F9DFD).withValues(alpha: 0.8);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y - barHeight, width, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);

      if (width >= 14 && barHeight >= 22) {
        final label = _barLabel(n.pitch);
        final fontSize = max(9.0, min(12.0, min(width * 0.6, barHeight * 0.4)));
        final textPainter = _getLabelPainter(label, fontSize);
        final textOffset = Offset(
          x + (width - textPainter.width) / 2,
          (y - barHeight) + (barHeight - textPainter.height) / 2,
        );
        textPainter.paint(canvas, textOffset);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FallingNotesPainter oldDelegate) {
    return oldDelegate.elapsedSec != elapsedSec ||
        oldDelegate.expectedNotes != expectedNotes;
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
