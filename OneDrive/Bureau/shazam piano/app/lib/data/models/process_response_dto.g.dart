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
    );

Map<String, dynamic> _$ProcessResponseDtoToJson(ProcessResponseDto instance) =>
    <String, dynamic>{
      'job_id': instance.jobId,
      'timestamp': instance.timestamp,
      'levels': instance.levels,
    };
