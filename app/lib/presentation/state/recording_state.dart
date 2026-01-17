import 'dart:io';
import 'package:flutter/foundation.dart';

/// State for audio recording
@immutable
class RecordingState {
  final bool isRecording;
  final bool isProcessing;
  final Duration? recordingDuration;
  final File? recordedFile;
  final String? error;
  // SESSION-008: Track microphone permission status
  // null = not yet checked, true = granted, false = denied
  final bool? micPermissionGranted;

  const RecordingState({
    this.isRecording = false,
    this.isProcessing = false,
    this.recordingDuration,
    this.recordedFile,
    this.error,
    this.micPermissionGranted,
  });

  RecordingState copyWith({
    bool? isRecording,
    bool? isProcessing,
    Duration? recordingDuration,
    File? recordedFile,
    String? error,
    bool? micPermissionGranted,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      isProcessing: isProcessing ?? this.isProcessing,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      recordedFile: recordedFile ?? this.recordedFile,
      error: error ?? this.error,
      micPermissionGranted: micPermissionGranted ?? this.micPermissionGranted,
    );
  }

  bool get isIdle => !isRecording && !isProcessing;
  bool get hasRecording => recordedFile != null;
  bool get hasError => error != null;
  // SESSION-008: Helper to check if permission is granted
  bool get hasMicPermission => micPermissionGranted == true;
}
