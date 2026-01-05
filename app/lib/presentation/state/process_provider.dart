import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import '../../data/models/job_progress_response_dto.dart';
import '../../domain/entities/level_result.dart';
import '../../domain/entities/process_response.dart';
import 'process_state.dart';

/// Process state provider
final processProvider = StateNotifierProvider<ProcessNotifier, ProcessState>((
  ref,
) {
  final dio = ref.watch(dioProvider);
  return ProcessNotifier(dio);
});

class ProcessNotifier extends StateNotifier<ProcessState> {
  final Dio _dio;
  Timer? _pollTimer;
  bool _isCreating = false;
  bool _isStarting = false;
  bool _pollingInFlight = false;
  String? _activeJobId;

  // BUG 1 FIX: Progress polling resilience
  int _consecutiveProgressFailures = 0;
  DateTime? _lastProgressOkAt;
  String? _lastProgressError;
  static const int _consecutiveFailureThreshold = 5;
  static const Duration _progressErrorTimeWindow = Duration(seconds: 10);

  ProcessNotifier(this._dio) : super(const ProcessState());

  Map<int, LevelProgress> _buildProgressMap(List<JobLevelDto> levels) {
    final progress = Map<int, LevelProgress>.from(
      ProcessState.defaultLevelProgress,
    );
    for (final level in levels) {
      progress[level.level] = LevelProgress(
        level: level.level,
        status: level.status,
        name: level.name,
        previewUrl: level.previewUrl,
        videoUrl: level.videoUrl,
        midiUrl: level.midiUrl,
        keyGuess: level.keyGuess,
        tempoGuess: level.tempoGuess,
        durationSec: level.durationSec,
        error: level.error,
      );
    }
    return progress;
  }

  ProcessResponse? _buildResultIfComplete({
    required String jobId,
    required String status,
    required String? timestamp,
    required List<LevelProgress> levels,
    required String? identifiedTitle,
    required String? identifiedArtist,
    required String? identifiedAlbum,
  }) {
    if (status != 'complete') {
      return null;
    }
    if (levels.any((level) => !level.hasUrls)) {
      return null;
    }
    final sorted = levels.toList()..sort((a, b) => a.level.compareTo(b.level));
    return ProcessResponse(
      jobId: jobId,
      timestamp: timestamp ?? DateTime.now().toIso8601String(),
      levels: sorted
          .map(
            (level) => LevelResult(
              level: level.level,
              name: level.name,
              previewUrl: level.previewUrl,
              videoUrl: level.videoUrl,
              midiUrl: level.midiUrl,
              keyGuess: level.keyGuess,
              tempoGuess: level.tempoGuess,
              durationSec: level.durationSec,
              status: level.status,
              error: level.error,
            ),
          )
          .toList(),
      identifiedTitle: identifiedTitle,
      identifiedArtist: identifiedArtist,
      identifiedAlbum: identifiedAlbum,
    );
  }

  ProcessState _applyJobResponse({
    required String jobId,
    required String status,
    required String? timestamp,
    required List<JobLevelDto> levels,
    required String? identifiedTitle,
    required String? identifiedArtist,
    required String? identifiedAlbum,
  }) {
    final progressMap = _buildProgressMap(levels);
    final result = _buildResultIfComplete(
      jobId: jobId,
      status: status,
      timestamp: timestamp,
      levels: progressMap.values.toList(),
      identifiedTitle: identifiedTitle,
      identifiedArtist: identifiedArtist,
      identifiedAlbum: identifiedAlbum,
    );
    return state.copyWith(
      jobId: jobId,
      jobStatus: status,
      result: result,
      identifiedTitle: identifiedTitle,
      identifiedArtist: identifiedArtist,
      identifiedAlbum: identifiedAlbum,
      levelProgress: progressMap,
      error: null,
    );
  }

  ProcessState _applyJobCreate(JobCreateResponseDto dto) {
    return _applyJobResponse(
      jobId: dto.jobId,
      status: dto.status,
      timestamp: dto.timestamp,
      levels: dto.levels,
      identifiedTitle: dto.identifiedTitle,
      identifiedArtist: dto.identifiedArtist,
      identifiedAlbum: dto.identifiedAlbum,
    );
  }

  ProcessState _applyJobProgress(JobProgressResponseDto dto) {
    return _applyJobResponse(
      jobId: dto.jobId,
      status: dto.status,
      timestamp: dto.timestamp,
      levels: dto.levels,
      identifiedTitle: dto.identifiedTitle,
      identifiedArtist: dto.identifiedArtist,
      identifiedAlbum: dto.identifiedAlbum,
    );
  }

  String _formatDioError(DioException e) {
    if (e.response != null) {
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data['detail'] != null) {
        return data['detail'].toString();
      }
    }
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'Server timeout - processing may take longer';
    }
    return 'Upload failed';
  }

  /// Create job and run identification only.
  Future<void> createJob({
    required File audioFile,
    bool withAudio = false,
    List<int> levels = const [1, 2, 3, 4],
  }) async {
    if (_isCreating) {
      return;
    }
    _isCreating = true;
    _stopPolling();
    try {
      state = const ProcessState(
        isUploading: true,
        isProcessing: false,
        uploadProgress: 0.1,
      );

      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(audioFile.path),
        'with_audio': withAudio,
        'levels': levels.join(','),
      });
      final response = await _dio.post('/jobs', data: formData);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('Invalid job response');
      }
      final dto = JobCreateResponseDto.fromJson(data);
      state = _applyJobCreate(
        dto,
      ).copyWith(isUploading: false, uploadProgress: 1.0, isProcessing: false);
      _activeJobId = state.jobId;
    } on DioException catch (e) {
      state = state.copyWith(
        isUploading: false,
        isProcessing: false,
        error: _formatDioError(e),
      );
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        isProcessing: false,
        error: 'Unexpected error: $e',
      );
    } finally {
      _isCreating = false;
    }
  }

  /// Convenience wrapper for upload + start generation.
  Future<void> processAudio({
    required File audioFile,
    bool withAudio = false,
    List<int> levels = const [1, 2, 3, 4],
  }) async {
    await createJob(audioFile: audioFile, withAudio: withAudio, levels: levels);
    if (state.jobId == null || state.error != null) {
      return;
    }
    await startJob(jobId: state.jobId!, withAudio: withAudio, levels: levels);
  }

  /// Start generation for a job.
  Future<void> startJob({
    required String jobId,
    bool withAudio = false,
    List<int> levels = const [1, 2, 3, 4],
  }) async {
    if (_isStarting) {
      return;
    }
    if (state.jobId == jobId &&
        (state.jobStatus == 'running' || state.jobStatus == 'complete')) {
      return;
    }
    _isStarting = true;
    // BUG 1 FIX: Reset progress tracking when starting a new job
    _consecutiveProgressFailures = 0;
    _lastProgressOkAt = null;
    _lastProgressError = null;
    try {
      final formData = FormData.fromMap({
        'with_audio': withAudio,
        'levels': levels.join(','),
      });
      final response = await _dio.post('/jobs/$jobId/start', data: formData);
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('Invalid job start response');
      }
      final dto = JobProgressResponseDto.fromJson(data);
      state = _applyJobProgress(dto).copyWith(isProcessing: true);
      _activeJobId = jobId;
      _startPolling(jobId);
    } on DioException catch (e) {
      state = state.copyWith(isProcessing: false, error: _formatDioError(e));
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        error: 'Unexpected error: $e',
      );
    } finally {
      _isStarting = false;
    }
  }

  Future<void> fetchProgress({required String jobId}) async {
    if (_activeJobId != jobId) {
      return;
    }
    try {
      final response = await _dio.get('/jobs/$jobId/progress');
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('Invalid progress response');
      }
      final dto = JobProgressResponseDto.fromJson(data);
      if (_activeJobId != jobId) {
        return;
      }
      // BUG 1 FIX: Reset failure tracking on successful progress fetch
      _lastProgressOkAt = DateTime.now();
      _consecutiveProgressFailures = 0;
      state = _applyJobProgress(dto);
      final jobStatus = dto.status;
      if (jobStatus == 'complete' || jobStatus == 'error') {
        _stopPolling();
        state = state.copyWith(isProcessing: false);
      }
    } on DioException catch (e) {
      _consecutiveProgressFailures++;
      _lastProgressError = _formatDioError(e);

      // BUG 1 FIX: Only set error if threshold exceeded AND no recent success
      final timeSinceLastOk = _lastProgressOkAt != null
          ? DateTime.now().difference(_lastProgressOkAt!)
          : _progressErrorTimeWindow;
      final shouldShowError =
          _consecutiveProgressFailures >= _consecutiveFailureThreshold &&
          timeSinceLastOk >= _progressErrorTimeWindow;

      if (shouldShowError) {
        state = state.copyWith(error: _lastProgressError);
      }
      // else: transient error, keep state.error null or previous value
    } catch (e) {
      _consecutiveProgressFailures++;
      _lastProgressError = 'Unexpected error: $e';
      state = state.copyWith(error: _lastProgressError);
    }
  }

  void _startPolling(String jobId) {
    if (_pollTimer != null && _activeJobId == jobId) {
      return;
    }
    _pollTimer?.cancel();
    _activeJobId = jobId;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_pollingInFlight) {
        return;
      }
      _pollingInFlight = true;
      try {
        await fetchProgress(jobId: jobId);
      } finally {
        _pollingInFlight = false;
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void stopPolling() {
    _stopPolling();
  }

  void resumePollingIfActive() {
    final jobId = state.jobId;
    if (jobId == null) {
      return;
    }
    if (state.jobStatus == 'running') {
      _startPolling(jobId);
    }
  }

  /// Reset state
  void reset() {
    _stopPolling();
    _activeJobId = null;
    _consecutiveProgressFailures = 0;
    _lastProgressOkAt = null;
    _lastProgressError = null;
    state = const ProcessState();
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
