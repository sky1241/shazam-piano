import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shazapiano/presentation/pages/home/home_page.dart';
import 'package:shazapiano/core/theme/app_theme.dart';

void main() {
  group('HomePage Widget Tests', () {
    testWidgets('HomePage renders correctly', (WidgetTester tester) async {
      // Build HomePage wrapped in necessary providers
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HomePage(),
          ),
        ),
      );

      // Verify key elements are present
      expect(find.text('ShazaPiano'), findsOneWidget);
      expect(find.text('Appuie pour créer\ntes 4 vidéos piano'), findsOneWidget);
    });

    testWidgets('BigRecordButton is displayed', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HomePage(),
          ),
        ),
      );

      // Find the record button by icon
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('Level chips are displayed', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HomePage(),
          ),
        ),
      );

      // Verify progression text is shown
      expect(find.text('Progression des niveaux'), findsOneWidget);
    });

    testWidgets('Tapping record button changes state', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HomePage(),
          ),
        ),
      );

      // Find and tap the record button
      final recordButton = find.byIcon(Icons.mic);
      expect(recordButton, findsOneWidget);

      await tester.tap(recordButton);
      await tester.pump();

      // After tapping, should show recording state
      expect(find.text('Enregistrement...\n8s recommandés'), findsOneWidget);
    });
  });
}

