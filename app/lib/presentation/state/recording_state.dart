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

  const RecordingState({
    this.isRecording = false,
    this.isProcessing = false,
    this.recordingDuration,
    this.recordedFile,
    this.error,
  });

  RecordingState copyWith({
    bool? isRecording,
    bool? isProcessing,
    Duration? recordingDuration,
    File? recordedFile,
    String? error,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      isProcessing: isProcessing ?? this.isProcessing,
      recordingDuration: recordingDuration ?? this.recordingDuration,
      recordedFile: recordedFile ?? this.recordedFile,
      error: error ?? this.error,
    );
  }

  bool get isIdle => !isRecording && !isProcessing;
  bool get hasRecording => recordedFile != null;
  bool get hasError => error != null;
}
