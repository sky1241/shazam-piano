import 'level_result.dart';

/// Domain entity for API process response
class ProcessResponse {
  final String jobId;
  final String timestamp;
  final List<LevelResult> levels;
  final String? identifiedTitle;
  final String? identifiedArtist;
  final String? identifiedAlbum;

  const ProcessResponse({
    required this.jobId,
    required this.timestamp,
    required this.levels,
    this.identifiedTitle,
    this.identifiedArtist,
    this.identifiedAlbum,
  });

  int get successCount => levels.where((l) => l.isSuccess).length;
  int get errorCount => levels.where((l) => l.isError).length;
  bool get hasErrors => errorCount > 0;
  bool get allSuccess => successCount == levels.length;
}
