import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class DebugJobGuard {
  static String? _currentJobId;
  static String? _previousJobId;

  static String? get currentJobId => _currentJobId;
  static String? get previousJobId => _previousJobId;

  static void setCurrentJobId(String jobId) {
    if (!kDebugMode) {
      return;
    }
    if (_currentJobId != jobId) {
      _previousJobId = _currentJobId;
      _currentJobId = jobId;
      debugPrint(
        'DebugJobGuard: currentJobId=$jobId previousJobId=$_previousJobId',
      );
    }
  }

  static void attachToDio(Dio dio) {
    if (!kDebugMode) {
      return;
    }
    final alreadyAttached = dio.interceptors.any(
      (interceptor) => interceptor is _DebugCleanupInterceptor,
    );
    if (alreadyAttached) {
      return;
    }
    dio.interceptors.add(_DebugCleanupInterceptor());
  }
}

class _DebugCleanupInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    if (method == 'DELETE') {
      final match = RegExp(r'/cleanup/([^/]+)').firstMatch(options.uri.path);
      final jobId = match?.group(1);
      final current = DebugJobGuard.currentJobId;
      if (jobId != null && current != null && jobId == current) {
        debugPrint('ILLEGAL CLEANUP CURRENT JOB: $jobId');
        Error.throwWithStackTrace(
          StateError('ILLEGAL CLEANUP CURRENT JOB: $jobId'),
          StackTrace.current,
        );
      }
    }
    handler.next(options);
  }
}
