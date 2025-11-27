import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import '../../data/datasources/api_client.dart';

/// App configuration provider
final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

/// Dio instance provider
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  
  final dio = Dio(BaseOptions(
    baseUrl: config.backendBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 5), // Video processing can take time
    headers: {
      'Accept': 'application/json',
    },
  ));
  
  // Add interceptors for logging in debug mode
  if (config.debugMode) {
    dio.interceptors.add(LogInterceptor(
      requestBody: true,
      responseBody: true,
    ));
  }
  
  return dio;
});

/// API client provider
final apiClientProvider = Provider<ApiClient>((ref) {
  final dio = ref.watch(dioProvider);
  final config = ref.watch(appConfigProvider);
  
  return ApiClient(dio, baseUrl: config.backendBaseUrl);
});


