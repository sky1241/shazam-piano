import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/domain/entities/level_result.dart';
import 'package:shazapiano/presentation/pages/practice/practice_page.dart';
import 'package:shazapiano/presentation/widgets/practice_keyboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LevelResult buildLevel() {
    return const LevelResult(
      level: 1,
      name: 'Test Level',
      previewUrl: 'https://example.com/preview.mp4',
      videoUrl: 'https://example.com/full.mp4',
      midiUrl: 'https://example.com/track.mid',
    );
  }

  Future<void> pumpPractice(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PracticePage(
          level: buildLevel(),
          forcePreview: true,
          isTest: true,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('PracticePage shows single video/keyboard/overlay', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.binding.setSurfaceSize(const Size(1080, 1920));
    await pumpPractice(tester);
    expect(find.byKey(const Key('practice_video')), findsOneWidget);
    expect(find.byKey(const Key('practice_keyboard')), findsOneWidget);
    expect(find.byKey(const Key('practice_notes_overlay')), findsOneWidget);
    expect(find.byType(PracticeKeyboard), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    await tester.pump();
    expect(find.byKey(const Key('practice_video')), findsOneWidget);
    expect(find.byKey(const Key('practice_keyboard')), findsOneWidget);
    expect(find.byKey(const Key('practice_notes_overlay')), findsOneWidget);
    expect(find.byType(PracticeKeyboard), findsOneWidget);
  });

  test('isVideoEnded uses 100ms threshold', () {
    expect(
      isVideoEnded(
        const Duration(milliseconds: 9950),
        const Duration(seconds: 10),
      ),
      isTrue,
    );
    expect(
      isVideoEnded(
        const Duration(milliseconds: 9800),
        const Duration(seconds: 10),
      ),
      isFalse,
    );
  });
}
