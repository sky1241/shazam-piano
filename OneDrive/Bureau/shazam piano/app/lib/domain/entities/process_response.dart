import 'level_result.dart';

/// Domain entity for API process response
class ProcessResponse {
  final String jobId;
  final String timestamp;
  final List<LevelResult> levels;

  const ProcessResponse({
    required this.jobId,
    required this.timestamp,
    required this.levels,
  });

  int get successCount => levels.where((l) => l.isSuccess).length;
  int get errorCount => levels.where((l) => l.isError).length;
  bool get hasErrors => errorCount > 0;
  bool get allSuccess => successCount == levels.length;
}

