import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/config/app_config.dart';

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
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.5,
            colors: [
              Color(0x1F2AE6BE), // primary @ 12%
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // TODO: Replace with BigRecordButton
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2AE6BE), Color(0xFF21C7A3)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2AE6BE).withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'ShazaPiano',
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Appuie pour créer tes 4 vidéos piano',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFA9C3BC),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
