import 'package:flutter/foundation.dart';
import '../../domain/entities/process_response.dart';
import '../widgets/mode_chip.dart';

@immutable
class LevelProgress {
  final int level;
  final String status;
  final String name;
  final String previewUrl;
  final String videoUrl;
  final String midiUrl;
  final String? keyGuess;
  final int? tempoGuess;
  final double? durationSec;
  final String? error;

  const LevelProgress({
    required this.level,
    required this.status,
    required this.name,
    required this.previewUrl,
    required this.videoUrl,
    required this.midiUrl,
    this.keyGuess,
    this.tempoGuess,
    this.durationSec,
    this.error,
  });

  bool get hasUrls => videoUrl.isNotEmpty && midiUrl.isNotEmpty;
}

/// State for video processing
@immutable
class ProcessState {
  final bool isUploading;
  final bool isProcessing;
  final double uploadProgress;
  final ProcessResponse? result;
  final String? error;
  final String? jobId;
  final String? jobStatus;
  final String? identifiedTitle;
  final String? identifiedArtist;
  final String? identifiedAlbum;
  final Map<int, LevelProgress> levelProgress;

  static const Map<int, LevelProgress> defaultLevelProgress = {
    1: LevelProgress(
      level: 1,
      status: 'queued',
      name: 'Level 1',
      previewUrl: '',
      videoUrl: '',
      midiUrl: '',
    ),
    2: LevelProgress(
      level: 2,
      status: 'queued',
      name: 'Level 2',
      previewUrl: '',
      videoUrl: '',
      midiUrl: '',
    ),
    3: LevelProgress(
      level: 3,
      status: 'queued',
      name: 'Level 3',
      previewUrl: '',
      videoUrl: '',
      midiUrl: '',
    ),
    4: LevelProgress(
      level: 4,
      status: 'queued',
      name: 'Level 4',
      previewUrl: '',
      videoUrl: '',
      midiUrl: '',
    ),
  };
  static const Object _unset = Object();

  const ProcessState({
    this.isUploading = false,
    this.isProcessing = false,
    this.uploadProgress = 0.0,
    this.result,
    this.error,
    this.jobId,
    this.jobStatus,
    this.identifiedTitle,
    this.identifiedArtist,
    this.identifiedAlbum,
    this.levelProgress = defaultLevelProgress,
  });

  ProcessState copyWith({
    bool? isUploading,
    bool? isProcessing,
    double? uploadProgress,
    Object? result = _unset,
    Object? error = _unset,
    String? jobId,
    String? jobStatus,
    String? identifiedTitle,
    String? identifiedArtist,
    String? identifiedAlbum,
    Map<int, LevelProgress>? levelProgress,
  }) {
    return ProcessState(
      isUploading: isUploading ?? this.isUploading,
      isProcessing: isProcessing ?? this.isProcessing,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      result: result == _unset ? this.result : result as ProcessResponse?,
      error: error == _unset ? this.error : error as String?,
      jobId: jobId ?? this.jobId,
      jobStatus: jobStatus ?? this.jobStatus,
      identifiedTitle: identifiedTitle ?? this.identifiedTitle,
      identifiedArtist: identifiedArtist ?? this.identifiedArtist,
      identifiedAlbum: identifiedAlbum ?? this.identifiedAlbum,
      levelProgress: levelProgress ?? this.levelProgress,
    );
  }

  Map<int, ModeChipStatus> get levelStatuses {
    final statuses = <int, ModeChipStatus>{};
    for (final entry in levelProgress.entries) {
      statuses[entry.key] = _chipStatus(entry.value.status);
    }
    return statuses;
  }

  ModeChipStatus _chipStatus(String status) {
    switch (status) {
      case 'success':
        return ModeChipStatus.completed;
      case 'processing':
        return ModeChipStatus.processing;
      case 'error':
        return ModeChipStatus.error;
      case 'queued':
      case 'pending':
      default:
        return ModeChipStatus.queued;
    }
  }

  bool get isIdle => !isUploading && !isProcessing;
  bool get isActive => isUploading || isProcessing;
  bool get hasResult => result != null;
  bool get hasError => error != null || jobStatus == 'error';
  bool get isSuccess => result != null && result!.allSuccess;
}
