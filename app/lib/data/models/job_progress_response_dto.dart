class JobLevelDto {
  final int level;
  final String name;
  final String previewUrl;
  final String videoUrl;
  final String midiUrl;
  final String status;
  final String? keyGuess;
  final int? tempoGuess;
  final double? durationSec;
  final String? error;

  const JobLevelDto({
    required this.level,
    required this.name,
    required this.previewUrl,
    required this.videoUrl,
    required this.midiUrl,
    required this.status,
    this.keyGuess,
    this.tempoGuess,
    this.durationSec,
    this.error,
  });

  factory JobLevelDto.fromJson(Map<String, dynamic> json) {
    final level = (json['level'] as num?)?.toInt() ?? 0;
    return JobLevelDto(
      level: level,
      name: json['name'] as String? ?? 'Level $level',
      previewUrl: json['preview_url'] as String? ?? '',
      videoUrl: json['video_url'] as String? ?? '',
      midiUrl: json['midi_url'] as String? ?? '',
      status: json['status'] as String? ?? 'queued',
      keyGuess: json['key_guess'] as String?,
      tempoGuess: (json['tempo_guess'] as num?)?.toInt(),
      durationSec: (json['duration_sec'] as num?)?.toDouble(),
      error: json['error'] as String?,
    );
  }
}

class JobCreateResponseDto {
  final String jobId;
  final String status;
  final String? timestamp;
  final List<JobLevelDto> levels;
  final String? identifiedTitle;
  final String? identifiedArtist;
  final String? identifiedAlbum;

  const JobCreateResponseDto({
    required this.jobId,
    required this.status,
    required this.levels,
    this.timestamp,
    this.identifiedTitle,
    this.identifiedArtist,
    this.identifiedAlbum,
  });

  factory JobCreateResponseDto.fromJson(Map<String, dynamic> json) {
    return JobCreateResponseDto(
      jobId: json['job_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      timestamp: json['timestamp']?.toString(),
      levels: _parseLevels(json['levels']),
      identifiedTitle: json['identified_title'] as String?,
      identifiedArtist: json['identified_artist'] as String?,
      identifiedAlbum: json['identified_album'] as String?,
    );
  }
}

class JobProgressResponseDto {
  final String jobId;
  final String status;
  final String? timestamp;
  final List<JobLevelDto> levels;
  final String? identifiedTitle;
  final String? identifiedArtist;
  final String? identifiedAlbum;

  const JobProgressResponseDto({
    required this.jobId,
    required this.status,
    required this.levels,
    this.timestamp,
    this.identifiedTitle,
    this.identifiedArtist,
    this.identifiedAlbum,
  });

  factory JobProgressResponseDto.fromJson(Map<String, dynamic> json) {
    return JobProgressResponseDto(
      jobId: json['job_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      timestamp: json['timestamp']?.toString(),
      levels: _parseLevels(json['levels']),
      identifiedTitle: json['identified_title'] as String?,
      identifiedArtist: json['identified_artist'] as String?,
      identifiedAlbum: json['identified_album'] as String?,
    );
  }
}

List<JobLevelDto> _parseLevels(dynamic raw) {
  final levels = <JobLevelDto>[];
  if (raw is List) {
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        levels.add(JobLevelDto.fromJson(item));
      }
    }
  }
  return levels;
}
