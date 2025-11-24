import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import 'recording_state.dart';

/// Recording state provider
final recordingProvider = StateNotifierProvider<RecordingNotifier, RecordingState>((ref) {
  return RecordingNotifier();
});

class RecordingNotifier extends StateNotifier<RecordingState> {
  RecordingNotifier() : super(const RecordingState());

  final _recorder = AudioRecorder();
  Timer? _durationTimer;
  DateTime? _startTime;

  /// Start recording
  Future<void> startRecording() async {
    try {
      // Check and request permission
      if (!await _recorder.hasPermission()) {
        state = state.copyWith(error: 'Microphone permission denied');
        return;
      }

      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        ),
        path: filePath,
      );

      _startTime = DateTime.now();
      state = state.copyWith(
        isRecording: true,
        recordingDuration: Duration.zero,
        error: null,
      );

      // Update duration every 100ms
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_startTime != null) {
          final duration = DateTime.now().difference(_startTime!);
          state = state.copyWith(recordingDuration: duration);

          // Auto-stop at max duration
          if (duration.inSeconds >= AppConstants.maxRecordingDurationSec) {
            stopRecording();
          }
        }
      });
    } catch (e) {
      state = state.copyWith(error: 'Failed to start recording: $e');
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    try {
      _durationTimer?.cancel();
      _durationTimer = null;

      final path = await _recorder.stop();
      
      if (path != null) {
        final file = File(path);
        
        // Validate file exists and has content
        if (await file.exists() && await file.length() > 0) {
          state = state.copyWith(
            isRecording: false,
            recordedFile: file,
          );
        } else {
          state = state.copyWith(
            isRecording: false,
            error: 'Recording failed: empty file',
          );
        }
      } else {
        state = state.copyWith(
          isRecording: false,
          error: 'Recording failed: no file',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isRecording: false,
        error: 'Failed to stop recording: $e',
      );
    }
  }

  /// Cancel recording and delete file
  Future<void> cancelRecording() async {
    try {
      _durationTimer?.cancel();
      _durationTimer = null;

      await _recorder.stop();

      if (state.recordedFile != null && await state.recordedFile!.exists()) {
        await state.recordedFile!.delete();
      }

      state = const RecordingState();
    } catch (e) {
      state = state.copyWith(error: 'Failed to cancel recording: $e');
    }
  }

  /// Reset state
  void reset() {
    state = const RecordingState();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}

