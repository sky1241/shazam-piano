import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';
import 'core/config/build_info.dart';
import 'core/services/firebase_service.dart';
import 'presentation/pages/home/home_page.dart';

void main() {
  // Keep all initialization and runApp in the same zone to avoid zone mismatch.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      AppConfig.fromEnvironment();

      try {
        await FirebaseService.initialize();
        debugPrint('App initialization successful');
      } catch (e, stackTrace) {
        debugPrint('App initialization failed: $e');
        debugPrint('Stack trace: $stackTrace');
      }

      runApp(
        ProviderScope(
          overrides: [
            // Add config provider override here
          ],
          child: const ShazaPianoApp(),
        ),
      );
    },
    (error, stackTrace) {
      debugPrint('Uncaught error: $error');
      debugPrint('Stack trace: $stackTrace');
      try {
        FirebaseService.crashlytics.recordError(error, stackTrace);
      } catch (_) {}
    },
  );
}

class ShazaPianoApp extends StatelessWidget {
  const ShazaPianoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final config = AppConfig.fromEnvironment();
    return MaterialApp(
      title: 'ShazaPiano',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomePage(),
      builder: (context, child) {
        if (!kDebugMode) {
          return child ?? const SizedBox.shrink();
        }
        return Stack(
          children: [
            if (child != null) child,
            _BuildStampOverlay(
              stamp: BuildInfo.stamp,
              backendBaseUrl: config.backendBaseUrl,
            ),
          ],
        );
      },
    );
  }
}

class _BuildStampOverlay extends StatelessWidget {
  final String stamp;
  final String backendBaseUrl;

  const _BuildStampOverlay({required this.stamp, required this.backendBaseUrl});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              height: 1.2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('BUILD: $stamp'),
                Text('BACKEND: $backendBaseUrl'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
