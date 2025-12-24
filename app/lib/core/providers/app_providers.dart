import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' as riverpod;
import 'package:firebase_auth/firebase_auth.dart';
import '../config/app_config.dart';
import '../../data/datasources/api_client.dart';

/// App configuration provider
final appConfigProvider = riverpod.Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

/// Dio instance provider
final dioProvider = riverpod.Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.backendBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(
        minutes: 15,
      ), // BasicPitch + video rendering can be very slow
      headers: {'Accept': 'application/json'},
    ),
  );

  // Attach Firebase ID token to every request
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final auth = FirebaseAuth.instance;
          if (auth.currentUser == null) {
            await auth.signInAnonymously();
          }
          final token = await auth.currentUser?.getIdToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (_) {
          // ignore token errors to avoid blocking request; backend will reject if needed
        }
        return handler.next(options);
      },
    ),
  );

  // Add interceptors for logging in debug mode
  if (config.debugMode) {
    dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
  }

  return dio;
});

/// API client provider
final apiClientProvider = riverpod.Provider<ApiClient>((ref) {
  final dio = ref.watch(dioProvider);
  final config = ref.watch(appConfigProvider);

  return ApiClient(dio, baseUrl: config.backendBaseUrl);
});
