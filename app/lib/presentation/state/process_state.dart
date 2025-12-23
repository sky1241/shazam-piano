import 'package:flutter/foundation.dart';
import '../../domain/entities/process_response.dart';

/// State for video processing
@immutable
class ProcessState {
  final bool isUploading;
  final bool isProcessing;
  final double uploadProgress;
  final ProcessResponse? result;
  final String? error;

  const ProcessState({
    this.isUploading = false,
    this.isProcessing = false,
    this.uploadProgress = 0.0,
    this.result,
    this.error,
  });

  ProcessState copyWith({
    bool? isUploading,
    bool? isProcessing,
    double? uploadProgress,
    ProcessResponse? result,
    String? error,
  }) {
    return ProcessState(
      isUploading: isUploading ?? this.isUploading,
      isProcessing: isProcessing ?? this.isProcessing,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      result: result ?? this.result,
      error: error ?? this.error,
    );
  }

  bool get isIdle => !isUploading && !isProcessing;
  bool get isActive => isUploading || isProcessing;
  bool get hasResult => result != null;
  bool get hasError => error != null;
  bool get isSuccess => result != null && result!.allSuccess;
}
