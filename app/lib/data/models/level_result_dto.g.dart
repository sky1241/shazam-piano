// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'level_result_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LevelResultDto _$LevelResultDtoFromJson(Map<String, dynamic> json) =>
    LevelResultDto(
      level: (json['level'] as num).toInt(),
      name: json['name'] as String,
      previewUrl: json['preview_url'] as String,
      videoUrl: json['video_url'] as String,
      midiUrl: json['midi_url'] as String,
      keyGuess: json['key_guess'] as String?,
      tempoGuess: (json['tempo_guess'] as num?)?.toInt(),
      durationSec: (json['duration_sec'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'success',
      error: json['error'] as String?,
    );

Map<String, dynamic> _$LevelResultDtoToJson(LevelResultDto instance) =>
    <String, dynamic>{
      'level': instance.level,
      'name': instance.name,
      'preview_url': instance.previewUrl,
      'video_url': instance.videoUrl,
      'midi_url': instance.midiUrl,
      'key_guess': instance.keyGuess,
      'tempo_guess': instance.tempoGuess,
      'duration_sec': instance.durationSec,
      'status': instance.status,
      'error': instance.error,
    };
