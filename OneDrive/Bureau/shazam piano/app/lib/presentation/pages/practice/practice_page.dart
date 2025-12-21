import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import 'pitch_detector.dart';

class PracticePage extends StatefulWidget {
  final LevelResult level;

  const PracticePage({
    super.key,
    required this.level,
  });

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  bool _isListening = false;
  int? _detectedNote;
  int? _expectedNote;
  NoteAccuracy _accuracy = NoteAccuracy.miss;
  int _score = 0;
  int _totalNotes = 0;
  int _correctNotes = 0;
  int _wrongNotes = 0;
  DateTime? _startTime;
  StreamSubscription<dynamic>? _micSub;
  final _pitchDetector = PitchDetector();
  List<_ExpectedNote> _expectedNotes = [];
  List<bool> _hitNotes = [];
  double _latencyMs = 0;
  bool _latencyLoaded = false;
  final AudioPlayer _beepPlayer = AudioPlayer();
  static const double _fallbackLatencyMs = 100.0; // Default offset if calibration fails

  // Piano keyboard (2 octaves for practice - C4 to C6)
  static const int _firstKey = 60; // C4
  static const int _lastKey = 84;  // C6
  static const List<int> _blackKeys = [1, 3, 6, 8, 10]; // C#, D#, F#, G#, A#

  @override
  void initState() {
    super.initState();
    _loadSavedLatency();
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
            onPressed: _togglePractice,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacing16,
              vertical: AppConstants.spacing8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _latencyMs > 0 ? 'Sync: ${_latencyMs.toStringAsFixed(0)} ms' : 'Sync auto',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
                ),
                Text(
                  _isListening ? 'En cours' : 'Prêt',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildScoreStat('Score', _score.toString()),
                _buildScoreStat(
                  'Précision',
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
          Text(
            _isListening ? 'Écoute...' : 'Appuie sur Play',
            style: AppTextStyles.title,
          ),
          
          const SizedBox(height: AppConstants.spacing16),

          // Accuracy indicator
          if (_detectedNote != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing24,
                vertical: AppConstants.spacing12,
              ),
              decoration: BoxDecoration(
                color: _getAccuracyColor().withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(
                  color: _getAccuracyColor(),
                  width: 2,
                ),
              ),
              child: Text(
                _getAccuracyText(),
                style: AppTextStyles.title.copyWith(
                  color: _getAccuracyColor(),
                ),
              ),
            ),

          const Spacer(),

          // Virtual Piano Keyboard
          _buildPianoKeyboard(),

          const SizedBox(height: AppConstants.spacing32),

          // Instructions
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacing16),
            child: Text(
              'Joue les notes sur ton piano.\n'
              'Les touches s\'allumeront selon ta précision.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
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
        Text(
          label,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  Widget _buildPianoKeyboard() {
    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing16),
      child: Stack(
        children: [
          // White keys
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int note = _firstKey; note <= _lastKey; note++)
                if (!_isBlackKey(note))
                  _buildPianoKey(note, isBlack: false),
            ],
          ),
          // Black keys (positioned absolutely)
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int note = _firstKey; note <= _lastKey; note++)
                  if (_isBlackKey(note))
                    _buildPianoKey(note, isBlack: true)
                  else
                    const SizedBox(width: 30), // Space for white keys
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPianoKey(int note, {required bool isBlack}) {
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

    return Container(
      width: isBlack ? 20 : 30,
      height: isBlack ? 120 : 180,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: keyColor,
        border: Border.all(color: AppColors.divider, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  bool _isBlackKey(int note) {
    return _blackKeys.contains(note % 12);
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
        return '✓ Parfait !';
      case NoteAccuracy.close:
        return '~ Proche';
      case NoteAccuracy.wrong:
        return '✗ Faux';
      case NoteAccuracy.miss:
        return 'Aucune note';
    }
  }

  void _togglePractice() {
    setState(() {
      _isListening = !_isListening;
      
      if (_isListening) {
        _startPractice();
      } else {
        _stopPractice();
      }
    });
  }

  Future<void> _startPractice() async {
    // Permissions
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      setState(() {
        _isListening = false;
      });
      return;
    }

    // Auto calibrate silently (latency)
    if (_latencyMs == 0) {
      await _calibrateLatency();
    }
    if (_latencyMs == 0) {
      _latencyMs = _fallbackLatencyMs; // fallback if calibration failed
    }

    // Fetch expected notes from backend
    await _loadExpectedNotes();
    _score = 0;
    _correctNotes = 0;
    _wrongNotes = 0;
    _totalNotes = _expectedNotes.length;
    _hitNotes = List<bool>.filled(_expectedNotes.length, false);
    _startTime = DateTime.now();

    // Start mic stream
    try {
      final stream = await MicStream.microphone(
        sampleRate: PitchDetector.sampleRate,
        audioFormat: AudioFormat.ENCODING_PCM_16BIT,
      );
      _micSub = stream?.listen(_processAudioChunk);
    } catch (_) {
      setState(() {
        _isListening = false;
      });
    }
  }

  void _stopPractice() {
    _micSub?.cancel();
    _micSub = null;
    _startTime = null;
    final finishedAt = DateTime.now().toIso8601String();
    final score = _score;
    final total = _totalNotes == 0 ? 1 : _totalNotes;
    final accuracy = total > 0 ? (_correctNotes / total) * 100.0 : 0.0;

    _sendPracticeSession(
      score: score.toDouble(),
      accuracy: accuracy,
      notesTotal: total,
      notesCorrect: _correctNotes,
      startedAt: finishedAt, // reuse as id if no start time tracked
      endedAt: finishedAt,
    );

    setState(() {
      _detectedNote = null;
      _expectedNote = null;
    });
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

      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.backendBaseUrl,
        connectTimeout: const Duration(seconds: 20),
      ));
      dio.options.headers['Authorization'] = 'Bearer $token';

      await dio.post('/practice/session', data: {
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
      });
    } catch (_) {
      // ignore errors for now in UI; backend will log if it receives request
    }
  }

  Future<void> _processAudioChunk(dynamic chunk) async {
    if (_startTime == null) return;
    // chunk is likely List<int> PCM 16-bit
    if (chunk is! List) return;
    final int16 = Int16List.fromList(List<int>.from(chunk));
    if (int16.isEmpty) return;

    final floatSamples = Float32List(int16.length);
    for (var i = 0; i < int16.length; i++) {
      floatSamples[i] = int16[i] / 32768.0;
    }

    final freq = _pitchDetector.detectPitch(floatSamples);
    if (freq == null) return;
    final midi = _pitchDetector.frequencyToMidiNote(freq);

    final now = DateTime.now();
    final elapsed = (now.difference(_startTime!).inMilliseconds - _latencyMs)
            .clamp(0, 1e9) /
        1000.0;

    // Find active expected notes
    final activeIndices = <int>[];
    for (var i = 0; i < _expectedNotes.length; i++) {
      final n = _expectedNotes[i];
      if (elapsed >= n.start && elapsed <= n.end + 0.2) {
        activeIndices.add(i);
      }
      if (elapsed > n.end + 0.2 && !_hitNotes[i]) {
        _wrongNotes += 1;
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
      _wrongNotes += 1;
    }

    setState(() {
      _detectedNote = midi;
      if (!_isListening) {
        _detectedNote = null;
      }
    });
  }

  Future<void> _loadExpectedNotes() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final dio = Dio(BaseOptions(
        baseUrl: AppConstants.backendBaseUrl,
        connectTimeout: const Duration(seconds: 15),
      ));
      dio.options.headers['Authorization'] = 'Bearer $token';

      final jobId = _extractJobId(widget.level.midiUrl);
      if (jobId == null) return;
      final resp = await dio.get('/practice/notes/$jobId/${widget.level.level}');
      final data = resp.data;
      if (data == null || data['notes'] == null) return;
      final List<dynamic> notesJson = data['notes'];
      _expectedNotes = notesJson
          .map((n) => _ExpectedNote(
                pitch: n['pitch'] as int,
                start: (n['start'] as num).toDouble(),
                end: (n['end'] as num).toDouble(),
              ))
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
      final file = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : midiUrl.split('/').last;
      if (file.contains('_L')) {
        return file.split('_L').first;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _calibrateLatency() async {
    // Already calibrated
    if (_latencyMs > 0) return;
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      return;
    }
    final targetFreq = 880.0; // A5 beep
    final durationMs = 1200;
    DateTime? beepStart;
    StreamSubscription<dynamic>? calibSub;
    try {
      // Start mic stream
      final stream = await MicStream.microphone(
        sampleRate: PitchDetector.sampleRate,
        audioFormat: AudioFormat.ENCODING_PCM_16BIT,
      );
      calibSub = stream?.listen((chunk) {
        if (beepStart == null) return;
        if (chunk is! List) return;
        final int16 = Int16List.fromList(List<int>.from(chunk));
        if (int16.isEmpty) return;
        final floatSamples = Float32List(int16.length);
        for (var i = 0; i < int16.length; i++) {
          floatSamples[i] = int16[i] / 32768.0;
        }
        final freq = _pitchDetector.detectPitch(floatSamples);
        if (freq == null) return;
        if ((freq - targetFreq).abs() < 80) {
          final delta = DateTime.now().difference(beepStart!).inMilliseconds;
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
      _latencyLoaded = true;
      if (mounted) setState(() {});
    } catch (_) {
      _latencyLoaded = true;
    }
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
}

class _ExpectedNote {
  final int pitch;
  final double start;
  final double end;
  _ExpectedNote({required this.pitch, required this.start, required this.end});
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
    final sample =
        (volume * 32767 * sin(2 * pi * freq * t)).clamp(-32767, 32767).toInt();
    writeInt16(sample);
  }

  return Uint8List.fromList(buffer.toBytes());
}
