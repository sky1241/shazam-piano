import 'package:json_annotation/json_annotation.dart';
import '../../core/constants/app_constants.dart';
import '../../domain/entities/level_result.dart';

part 'level_result_dto.g.dart';

@JsonSerializable()
class LevelResultDto {
  final int level;
  final String name;
  @JsonKey(name: 'preview_url')
  final String previewUrl;
  @JsonKey(name: 'video_url')
  final String videoUrl;
  @JsonKey(name: 'midi_url')
  final String midiUrl;
  @JsonKey(name: 'key_guess')
  final String? keyGuess;
  @JsonKey(name: 'tempo_guess')
  final int? tempoGuess;
  @JsonKey(name: 'duration_sec')
  final double? durationSec;
  final String status;
  final String? error;

  const LevelResultDto({
    required this.level,
    required this.name,
    required this.previewUrl,
    required this.videoUrl,
    required this.midiUrl,
    this.keyGuess,
    this.tempoGuess,
    this.durationSec,
    this.status = 'success',
    this.error,
  });

  factory LevelResultDto.fromJson(Map<String, dynamic> json) =>
      _$LevelResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$LevelResultDtoToJson(this);

  LevelResult toDomain() {
    String _abs(String url) {
      if (url.isEmpty) return url;
      if (url.startsWith('http')) return url;
      final base = AppConstants.backendBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
      if (url.startsWith('/')) return '$base$url';
      return '$base/$url';
    }

    return LevelResult(
      level: level,
      name: name,
      previewUrl: _abs(previewUrl),
      videoUrl: _abs(videoUrl),
      midiUrl: _abs(midiUrl),
      keyGuess: keyGuess,
      tempoGuess: tempoGuess,
      durationSec: durationSec,
      status: status,
      error: error,
    );
  }
}

