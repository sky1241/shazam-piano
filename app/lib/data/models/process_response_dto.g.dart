// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'process_response_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProcessResponseDto _$ProcessResponseDtoFromJson(Map<String, dynamic> json) =>
    ProcessResponseDto(
      jobId: json['job_id'] as String,
      timestamp: json['timestamp'] as String,
      levels: (json['levels'] as List<dynamic>)
          .map((e) => LevelResultDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      identifiedTitle: json['identified_title'] as String?,
      identifiedArtist: json['identified_artist'] as String?,
      identifiedAlbum: json['identified_album'] as String?,
    );

Map<String, dynamic> _$ProcessResponseDtoToJson(ProcessResponseDto instance) =>
    <String, dynamic>{
      'job_id': instance.jobId,
      'timestamp': instance.timestamp,
      'levels': instance.levels,
      'identified_title': instance.identifiedTitle,
      'identified_artist': instance.identifiedArtist,
      'identified_album': instance.identifiedAlbum,
    };
