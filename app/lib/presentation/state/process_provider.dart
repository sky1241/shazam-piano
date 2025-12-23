import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../core/providers/app_providers.dart';
import 'process_state.dart';

/// Process state provider
final processProvider = StateNotifierProvider<ProcessNotifier, ProcessState>((
  ref,
) {
  final apiClient = ref.watch(apiClientProvider);
  return ProcessNotifier(apiClient);
});

class ProcessNotifier extends StateNotifier<ProcessState> {
  final dynamic _apiClient;

  ProcessNotifier(this._apiClient) : super(const ProcessState());

  /// Process audio file
  Future<void> processAudio({
    required File audioFile,
    bool withAudio = false,
    List<int> levels = const [1, 2, 3, 4],
  }) async {
    try {
      // Reset state
      state = const ProcessState(isUploading: true);

      // Upload with progress
      final levelsString = levels.join(',');

      // Note: Actual upload with progress tracking would need custom implementation
      // For now, simple upload
      state = state.copyWith(uploadProgress: 0.5);

      final response = await _apiClient.processAudio(
        audio: audioFile,
        withAudio: withAudio,
        levels: levelsString,
      );

      state = state.copyWith(
        isUploading: false,
        isProcessing: false,
        uploadProgress: 1.0,
        result: response.toDomain(),
      );
    } on DioException catch (e) {
      String errorMessage = 'Upload failed';

      if (e.response != null) {
        errorMessage = e.response?.data['detail'] ?? errorMessage;
      } else if (e.type == DioExceptionType.connectionTimeout) {
        errorMessage = 'Connection timeout';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMessage = 'Server timeout - processing may take longer';
      }

      state = state.copyWith(
        isUploading: false,
        isProcessing: false,
        error: errorMessage,
      );
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        isProcessing: false,
        error: 'Unexpected error: $e',
      );
    }
  }

  /// Reset state
  void reset() {
    state = const ProcessState();
  }
}
