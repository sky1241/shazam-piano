import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';
import 'presentation/pages/home/home_page.dart';

void main() {
  // Initialize app config
  final config = AppConfig.fromEnvironment();

  runApp(
    ProviderScope(
      overrides: [
        // Add config provider override here
      ],
      child: const ShazaPianoApp(),
    ),
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
