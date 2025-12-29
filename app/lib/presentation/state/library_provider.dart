import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/providers/app_providers.dart';
import '../../data/datasources/api_client.dart';
import '../../domain/entities/level_result.dart';

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((
  ref,
) {
  final dio = ref.watch(dioProvider);
  final apiClient = ref.watch(apiClientProvider);
  return LibraryNotifier(dio, apiClient);
});

class LibraryState {
  final List<LibraryItem> items;
  final bool isDownloading;
  final String? activeJobId;
  final double downloadProgress;
  final String? downloadError;

  const LibraryState({
    this.items = const [],
    this.isDownloading = false,
    this.activeJobId,
    this.downloadProgress = 0.0,
    this.downloadError,
  });

  LibraryState copyWith({
    List<LibraryItem>? items,
    bool? isDownloading,
    String? activeJobId,
    double? downloadProgress,
    String? downloadError,
    bool resetDownloadError = false,
  }) {
    return LibraryState(
      items: items ?? this.items,
      isDownloading: isDownloading ?? this.isDownloading,
      activeJobId: activeJobId ?? this.activeJobId,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      downloadError: resetDownloadError
          ? null
          : downloadError ?? this.downloadError,
    );
  }
}

class LibraryItem {
  final String jobId;
  final String createdAt;
  final String? trackTitle;
  final String? trackArtist;
  final Map<int, String> previewPaths;
  final Map<int, String> fullPaths;

  const LibraryItem({
    required this.jobId,
    required this.createdAt,
    this.trackTitle,
    this.trackArtist,
    this.previewPaths = const {},
    this.fullPaths = const {},
  });

  LibraryItem copyWith({
    String? createdAt,
    String? trackTitle,
    String? trackArtist,
    Map<int, String>? previewPaths,
    Map<int, String>? fullPaths,
  }) {
    return LibraryItem(
      jobId: jobId,
      createdAt: createdAt ?? this.createdAt,
      trackTitle: trackTitle ?? this.trackTitle,
      trackArtist: trackArtist ?? this.trackArtist,
      previewPaths: previewPaths ?? this.previewPaths,
      fullPaths: fullPaths ?? this.fullPaths,
    );
  }

  bool hasFullForLevels(List<LevelResult> levels) {
    for (final level in levels) {
      if (level.videoUrl.isEmpty) {
        continue;
      }
      if (!fullPaths.containsKey(level.level)) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'jobId': jobId,
      'createdAt': createdAt,
      'trackTitle': trackTitle,
      'trackArtist': trackArtist,
      'previewPaths': previewPaths.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
      'fullPaths': fullPaths.map(
        (key, value) => MapEntry(key.toString(), value),
      ),
    };
  }

  static LibraryItem fromJson(Map<String, dynamic> json) {
    return LibraryItem(
      jobId: json['jobId'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      trackTitle: json['trackTitle'] as String?,
      trackArtist: json['trackArtist'] as String?,
      previewPaths: _decodePaths(json['previewPaths']),
      fullPaths: _decodePaths(json['fullPaths']),
    );
  }

  static Map<int, String> _decodePaths(dynamic raw) {
    if (raw is! Map) {
      return {};
    }
    final paths = <int, String>{};
    for (final entry in raw.entries) {
      final level = int.tryParse(entry.key.toString());
      final path = entry.value?.toString();
      if (level != null && path != null && path.isNotEmpty) {
        paths[level] = path;
      }
    }
    return paths;
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  static const String _storageKey = 'shazapiano_library';
  static const String _lastJobKey = 'shazapiano_last_job_id';

  final Dio _dio;
  final ApiClient _apiClient;
  Future<void>? _cacheFuture;
  bool _isDownloading = false;

  LibraryNotifier(this._dio, this._apiClient) : super(const LibraryState()) {
    unawaited(_loadFromStorage());
  }

  Future<void> cachePreviews({
    required String jobId,
    required List<LevelResult> levels,
    String? trackTitle,
    String? trackArtist,
  }) async {
    if (_cacheFuture != null) {
      await _cacheFuture;
    }
    final completer = Completer<void>();
    _cacheFuture = completer.future;
    try {
      final item = _getOrCreateItem(
        jobId: jobId,
        trackTitle: trackTitle,
        trackArtist: trackArtist,
      );
      final directory = await _jobDirectory(jobId);
      final previewPaths = Map<int, String>.from(item.previewPaths);

      for (final level in levels) {
        if (level.previewUrl.isEmpty) {
          continue;
        }
        final targetPath = _previewPath(directory, level.level);
        final file = File(targetPath);
        if (await file.exists() && await file.length() > 0) {
          previewPaths[level.level] = targetPath;
          continue;
        }
        await _downloadFile(level.previewUrl, targetPath);
        previewPaths[level.level] = targetPath;
      }

      _saveItem(
        item.copyWith(
          previewPaths: previewPaths,
          trackTitle: trackTitle,
          trackArtist: trackArtist,
        ),
      );
    } finally {
      completer.complete();
      _cacheFuture = null;
    }
  }

  Future<void> startFullDownload({
    required String jobId,
    required List<LevelResult> levels,
    String? trackTitle,
    String? trackArtist,
  }) async {
    if (_isDownloading) {
      return;
    }
    await _cleanupPreviousJob(jobId);
    await cachePreviews(
      jobId: jobId,
      levels: levels,
      trackTitle: trackTitle,
      trackArtist: trackArtist,
    );
    final existing = _findItem(jobId);
    if (existing != null && existing.hasFullForLevels(levels)) {
      return;
    }

    _isDownloading = true;
    state = state.copyWith(
      isDownloading: true,
      activeJobId: jobId,
      downloadProgress: 0.0,
      resetDownloadError: true,
    );

    try {
      final directory = await _jobDirectory(jobId);
      final targets = levels
          .where((level) => level.videoUrl.isNotEmpty)
          .toList();
      if (targets.isEmpty) {
        throw Exception('Aucune video full disponible');
      }

      int completed = 0;
      final total = targets.length;
      final fullPaths = Map<int, String>.from(existing?.fullPaths ?? {});

      for (final level in targets) {
        final targetPath = _fullPath(directory, level.level);
        final file = File(targetPath);
        if (await file.exists() && await file.length() > 0) {
          completed += 1;
          fullPaths[level.level] = targetPath;
          state = state.copyWith(downloadProgress: completed / total);
          continue;
        }

        await _downloadFile(
          level.videoUrl,
          targetPath,
          onProgress: (received, totalBytes) {
            if (totalBytes <= 0) {
              return;
            }
            final progress = (completed + (received / totalBytes)) / total;
            state = state.copyWith(downloadProgress: progress);
          },
        );

        completed += 1;
        fullPaths[level.level] = targetPath;
        state = state.copyWith(downloadProgress: completed / total);
      }

      final updated =
          (existing ??
                  LibraryItem(
                    jobId: jobId,
                    createdAt: DateTime.now().toIso8601String(),
                    trackTitle: trackTitle,
                    trackArtist: trackArtist,
                  ))
              .copyWith(
                fullPaths: fullPaths,
                trackTitle: trackTitle,
                trackArtist: trackArtist,
              );
      _saveItem(updated);

      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 1.0,
        resetDownloadError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        downloadError: 'Telechargement echoue: $e',
      );
    } finally {
      _isDownloading = false;
    }
  }

  LibraryItem? _findItem(String jobId) {
    try {
      return state.items.firstWhere((item) => item.jobId == jobId);
    } catch (_) {
      return null;
    }
  }

  LibraryItem _getOrCreateItem({
    required String jobId,
    String? trackTitle,
    String? trackArtist,
  }) {
    final existing = _findItem(jobId);
    if (existing != null) {
      return existing;
    }
    return LibraryItem(
      jobId: jobId,
      createdAt: DateTime.now().toIso8601String(),
      trackTitle: trackTitle,
      trackArtist: trackArtist,
    );
  }

  Future<void> _cleanupRemote(String jobId) async {
    try {
      await _apiClient.cleanupJob(jobId);
    } catch (_) {
      // Ignore cleanup failures to avoid blocking local success.
    }
  }

  Future<void> _cleanupPreviousJob(String currentJobId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastJobId = prefs.getString(_lastJobKey);
      if (lastJobId != null &&
          lastJobId.isNotEmpty &&
          lastJobId != currentJobId) {
        await _cleanupRemote(lastJobId);
      }
      await prefs.setString(_lastJobKey, currentJobId);
    } catch (_) {
      // Ignore cleanup persistence failures.
    }
  }

  Future<Directory> _jobDirectory(String jobId) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final path =
        '${baseDir.path}${Platform.pathSeparator}shazapiano${Platform.pathSeparator}library${Platform.pathSeparator}$jobId';
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _previewPath(Directory dir, int level) {
    return '${dir.path}${Platform.pathSeparator}preview_L$level.mp4';
  }

  String _fullPath(Directory dir, int level) {
    return '${dir.path}${Platform.pathSeparator}full_L$level.mp4';
  }

  Future<void> _downloadFile(
    String url,
    String targetPath, {
    void Function(int received, int totalBytes)? onProgress,
  }) async {
    try {
      await _dio.download(
        url,
        targetPath,
        onReceiveProgress: onProgress,
        options: Options(responseType: ResponseType.bytes),
      );
    } catch (e) {
      final file = File(targetPath);
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(LibraryItem.fromJson)
          .where((item) => item.jobId.isNotEmpty)
          .toList();
      state = state.copyWith(items: items);
    } catch (_) {
      state = const LibraryState(items: []);
    }
  }

  Future<void> _saveItem(LibraryItem item) async {
    final items = [...state.items];
    final index = items.indexWhere((existing) => existing.jobId == item.jobId);
    if (index >= 0) {
      items[index] = item;
    } else {
      items.insert(0, item);
    }
    state = state.copyWith(items: items);
    await _persistItems(items);
  }

  Future<void> _persistItems(List<LibraryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(items.map((item) => item.toJson()).toList());
      await prefs.setString(_storageKey, payload);
    } catch (_) {
      // Ignore persistence failures.
    }
  }
}
