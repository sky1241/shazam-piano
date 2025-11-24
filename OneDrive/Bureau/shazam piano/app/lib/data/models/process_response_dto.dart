import 'package:json_annotation/json_annotation.dart';
import '../../domain/entities/process_response.dart';
import 'level_result_dto.dart';

part 'process_response_dto.g.dart';

@JsonSerializable()
class ProcessResponseDto {
  @JsonKey(name: 'job_id')
  final String jobId;
  final String timestamp;
  final List<LevelResultDto> levels;

  const ProcessResponseDto({
    required this.jobId,
    required this.timestamp,
    required this.levels,
  });

  factory ProcessResponseDto.fromJson(Map<String, dynamic> json) =>
      _$ProcessResponseDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ProcessResponseDtoToJson(this);

  ProcessResponse toDomain() {
    return ProcessResponse(
      jobId: jobId,
      timestamp: timestamp,
      levels: levels.map((dto) => dto.toDomain()).toList(),
    );
  }
}

