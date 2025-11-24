import 'dart:io';
import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../models/process_response_dto.dart';

part 'api_client.g.dart';

@RestApi()
abstract class ApiClient {
  factory ApiClient(Dio dio, {String baseUrl}) = _ApiClient;

  @GET('/health')
  Future<Map<String, dynamic>> getHealth();

  @MultiPart()
  @POST('/process')
  Future<ProcessResponseDto> processAudio({
    @Part(name: 'audio') required File audio,
    @Part(name: 'with_audio') bool withAudio = false,
    @Part(name: 'levels') String levels = '1,2,3,4',
  });

  @DELETE('/cleanup/{jobId}')
  Future<Map<String, dynamic>> cleanupJob(@Path('jobId') String jobId);
}

