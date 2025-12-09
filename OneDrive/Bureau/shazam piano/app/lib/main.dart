import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';
import 'core/services/firebase_service.dart';
import 'presentation/pages/home/home_page.dart';

void main() {
  // Keep all initialization and runApp in the same zone to avoid zone mismatch.
  runZonedGuarded(() async {
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
  }, (error, stackTrace) {
    debugPrint('Uncaught error: $error');
    debugPrint('Stack trace: $stackTrace');
    try {
      FirebaseService.crashlytics.recordError(error, stackTrace);
    } catch (_) {}
  });
}

class ShazaPianoApp extends StatelessWidget {
  const ShazaPianoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShazaPiano',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomePage(),
    );
  }
}
