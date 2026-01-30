import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/constants/app_constants.dart';
import 'recording_state.dart';

// Logger helpers
void _logInfo(String message) =>
    developer.log(message, name: 'RecordingProvider');
void _logWarning(String message) =>
    developer.log(message, name: 'RecordingProvider', level: 900);

/// Recording state provider
final recordingProvider =
    StateNotifierProvider<RecordingNotifier, RecordingState>((ref) {
      return RecordingNotifier();
    });

class RecordingNotifier extends StateNotifier<RecordingState> {
  RecordingNotifier() : super(const RecordingState());

  final _recorder = AudioRecorder();
  Timer? _durationTimer;
  DateTime? _startTime;
  bool _isStopping = false;
  bool _recommendedLogged = false;
  // SESSION-008: Track if permission was already checked
  bool _permissionChecked = false;

  /// SESSION-008: Pre-request microphone permission at app load
  /// Call this from HomePage.initState() to avoid popup at record time
  /// This stabilizes the recording start timing
  Future<void> preflightMicrophonePermission() async {
    // Avoid multiple calls
    if (_permissionChecked) {
      return;
    }
    _permissionChecked = true;

    try {
      final granted = await _recorder.hasPermission();
      state = state.copyWith(micPermissionGranted: granted);
      _logInfo('Preflight mic permission: ${granted ? "granted" : "denied"}');
    } catch (e) {
      _logWarning('Preflight mic permission failed: $e');
      state = state.copyWith(micPermissionGranted: false);
    }
  }

  /// Start recording
  Future<void> startRecording() async {
    try {
      // SESSION-008: Check cached permission status instead of prompting
      // Permission should have been requested via preflightMicrophonePermission()
      if (state.micPermissionGranted != true) {
        // If permission not yet checked, check now (fallback)
        if (state.micPermissionGranted == null) {
          await preflightMicrophonePermission();
        }
        // If still not granted, abort
        if (state.micPermissionGranted != true) {
          state = state.copyWith(error: 'Microphone permission denied');
          return;
        }
      }

      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final filePath =
          '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // Start recording
      // SESSION-053: bitRate 128k→256k for better piano harmonics/transients
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 256000,
        ),
        path: filePath,
      );

      _startTime = DateTime.now();
      _recommendedLogged = false;
      state = state.copyWith(
        isRecording: true,
        recordingDuration: Duration.zero,
        error: null,
      );

      // Update duration every 100ms
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        if (_startTime != null) {
          final duration = DateTime.now().difference(_startTime!);
          state = state.copyWith(recordingDuration: duration);

          // Auto-stop only at max duration
          if (duration.inSeconds >= AppConstants.maxRecordingDurationSec) {
            _logWarning('Max duration reached, stopping...');
            stopRecording();
          } else if (!_recommendedLogged &&
              duration.inSeconds >=
                  AppConstants.recommendedRecordingDurationSec) {
            _recommendedLogged = true;
            _logInfo('Recommended duration reached (${duration.inSeconds}s).');
          }
        }
      });
    } catch (e) {
      state = state.copyWith(error: 'Failed to start recording: $e');
    }
  }

  /// Stop recording
  Future<void> stopRecording() async {
    if (_isStopping || !state.isRecording) {
      return;
    }
    _isStopping = true;
    try {
      _durationTimer?.cancel();
      _durationTimer = null;

      final path = await _recorder.stop();

      if (path != null) {
        final file = File(path);

        // Validate file exists and has content
        if (await file.exists() && await file.length() > 0) {
          state = state.copyWith(isRecording: false, recordedFile: file);
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
    } finally {
      _isStopping = false;
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

  /// Reset state (preserves permission status)
  void reset() {
    // SESSION-008: Preserve permission status across resets
    final permissionStatus = state.micPermissionGranted;
    state = RecordingState(micPermissionGranted: permissionStatus);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
