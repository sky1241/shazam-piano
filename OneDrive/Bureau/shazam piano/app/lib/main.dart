import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';
import 'core/services/firebase_service.dart';
import 'presentation/pages/home/home_page.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize app config
  final config = AppConfig.fromEnvironment();

  // Initialize Firebase with error handling
  try {
    await FirebaseService.initialize();
    print('✅ App initialization successful');
  } catch (e, stackTrace) {
    print('❌ App initialization failed: $e');
    print('Stack trace: $stackTrace');
    // Continue anyway - Firebase errors shouldn't crash the app
  }

  // Run app with error handling
  runZonedGuarded(
    () {
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
      print('❌ Uncaught error: $error');
      print('Stack trace: $stackTrace');
      // Log to Crashlytics if available
      try {
        FirebaseService.crashlytics.recordError(error, stackTrace);
      } catch (_) {
        // Ignore if Crashlytics not initialized
      }
    },
  );
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
