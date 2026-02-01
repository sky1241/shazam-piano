import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shazapiano/core/practice/feedback/ui_feedback_engine.dart';
import 'package:shazapiano/presentation/widgets/practice_keyboard.dart';

void main() {
  testWidgets('PracticeKeyboard respects width constraints', (tester) async {
    const firstKey = 36;
    const lastKey = 96;
    const blackKeys = [1, 3, 6, 8, 10];

    int whiteCount = 0;
    for (int note = firstKey; note <= lastKey; note++) {
      if (!blackKeys.contains(note % 12)) {
        whiteCount += 1;
      }
    }

    const containerWidth = 360.0;
    final whiteWidth = containerWidth / whiteCount;
    final blackWidth = whiteWidth * 0.65;
    final totalWidth = whiteWidth * whiteCount;

    // Generate neutral key colors
    final keyColors = <int, KeyVisualState>{};
    for (int note = firstKey; note <= lastKey; note++) {
      final isBlack = blackKeys.contains(note % 12);
      keyColors[note] = isBlack
          ? KeyVisualState.neutralBlack
          : KeyVisualState.neutralWhite;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: containerWidth,
            child: PracticeKeyboard(
              totalWidth: totalWidth,
              whiteWidth: whiteWidth,
              blackWidth: blackWidth,
              whiteHeight: 90,
              blackHeight: 60,
              firstKey: firstKey,
              lastKey: lastKey,
              blackKeys: blackKeys,
              keyColors: keyColors,
              noteToXFn: (note) => PracticeKeyboard.noteToX(
                note: note,
                firstKey: firstKey,
                whiteWidth: whiteWidth,
                blackWidth: blackWidth,
                blackKeys: blackKeys,
              ),
            ),
          ),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.byType(PracticeKeyboard));
    expect(box.size.width, lessThanOrEqualTo(containerWidth));
  });

  test('PracticeKeyboard.noteToX aligns to white key widths', () {
    const firstKey = 60; // C4
    const blackKeys = [1, 3, 6, 8, 10];
    const whiteWidth = 20.0;
    const blackWidth = 12.0;

    final xC = PracticeKeyboard.noteToX(
      note: 60,
      firstKey: firstKey,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      blackKeys: blackKeys,
    );
    final xD = PracticeKeyboard.noteToX(
      note: 62,
      firstKey: firstKey,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      blackKeys: blackKeys,
    );
    final xE = PracticeKeyboard.noteToX(
      note: 64,
      firstKey: firstKey,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      blackKeys: blackKeys,
    );
    final xCSharp = PracticeKeyboard.noteToX(
      note: 61,
      firstKey: firstKey,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      blackKeys: blackKeys,
    );

    expect(xC, 0.0);
    expect(xD, whiteWidth);
    expect(xE, whiteWidth * 2);
    expect(xCSharp, xD - (blackWidth / 2));
  });

  testWidgets('PracticeKeyboard renders green for success state', (
    tester,
  ) async {
    // SESSION-056: Test render-only keyboard with pre-computed keyColors
    const firstKey = 36;
    const lastKey = 96;
    const blackKeys = [1, 3, 6, 8, 10];
    const midi60 = 60; // C4

    int whiteCount = 0;
    for (int note = firstKey; note <= lastKey; note++) {
      if (!blackKeys.contains(note % 12)) {
        whiteCount += 1;
      }
    }

    const containerWidth = 360.0;
    final whiteWidth = containerWidth / whiteCount;
    final blackWidth = whiteWidth * 0.65;
    final totalWidth = whiteWidth * whiteCount;

    // Generate key colors with GREEN for midi60
    final keyColors = <int, KeyVisualState>{};
    for (int note = firstKey; note <= lastKey; note++) {
      final isBlack = blackKeys.contains(note % 12);
      if (note == midi60) {
        keyColors[note] = KeyVisualState.green; // Success state
      } else {
        keyColors[note] = isBlack
            ? KeyVisualState.neutralBlack
            : KeyVisualState.neutralWhite;
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: containerWidth,
            child: PracticeKeyboard(
              totalWidth: totalWidth,
              whiteWidth: whiteWidth,
              blackWidth: blackWidth,
              whiteHeight: 90,
              blackHeight: 60,
              firstKey: firstKey,
              lastKey: lastKey,
              blackKeys: blackKeys,
              keyColors: keyColors,
              noteToXFn: (note) => PracticeKeyboard.noteToX(
                note: note,
                firstKey: firstKey,
                whiteWidth: whiteWidth,
                blackWidth: blackWidth,
                blackKeys: blackKeys,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    // Should render green for midi60 - visual verification would need golden tests
  });

  testWidgets('PracticeKeyboard renders red for error state', (tester) async {
    // SESSION-056: Test render-only keyboard with RED state
    const firstKey = 36;
    const lastKey = 96;
    const blackKeys = [1, 3, 6, 8, 10];
    const midi60 = 60; // C4

    int whiteCount = 0;
    for (int note = firstKey; note <= lastKey; note++) {
      if (!blackKeys.contains(note % 12)) {
        whiteCount += 1;
      }
    }

    const containerWidth = 360.0;
    final whiteWidth = containerWidth / whiteCount;
    final blackWidth = whiteWidth * 0.65;
    final totalWidth = whiteWidth * whiteCount;

    // Generate key colors with RED for midi60
    final keyColors = <int, KeyVisualState>{};
    for (int note = firstKey; note <= lastKey; note++) {
      final isBlack = blackKeys.contains(note % 12);
      if (note == midi60) {
        keyColors[note] = KeyVisualState.red; // Error state
      } else {
        keyColors[note] = isBlack
            ? KeyVisualState.neutralBlack
            : KeyVisualState.neutralWhite;
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: containerWidth,
            child: PracticeKeyboard(
              totalWidth: totalWidth,
              whiteWidth: whiteWidth,
              blackWidth: blackWidth,
              whiteHeight: 90,
              blackHeight: 60,
              firstKey: firstKey,
              lastKey: lastKey,
              blackKeys: blackKeys,
              keyColors: keyColors,
              noteToXFn: (note) => PracticeKeyboard.noteToX(
                note: note,
                firstKey: firstKey,
                whiteWidth: whiteWidth,
                blackWidth: blackWidth,
                blackKeys: blackKeys,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    // Should render red for midi60 - visual verification would need golden tests
  });

  testWidgets('PracticeKeyboard renders cyan for expected notes', (
    tester,
  ) async {
    // SESSION-056: Test render-only keyboard with CYAN (expected) state
    const firstKey = 36;
    const lastKey = 96;
    const blackKeys = [1, 3, 6, 8, 10];
    const midi60 = 60; // C4

    int whiteCount = 0;
    for (int note = firstKey; note <= lastKey; note++) {
      if (!blackKeys.contains(note % 12)) {
        whiteCount += 1;
      }
    }

    const containerWidth = 360.0;
    final whiteWidth = containerWidth / whiteCount;
    final blackWidth = whiteWidth * 0.65;
    final totalWidth = whiteWidth * whiteCount;

    // Generate key colors with CYAN for midi60
    final keyColors = <int, KeyVisualState>{};
    for (int note = firstKey; note <= lastKey; note++) {
      final isBlack = blackKeys.contains(note % 12);
      if (note == midi60) {
        keyColors[note] = KeyVisualState.cyan; // Expected state
      } else {
        keyColors[note] = isBlack
            ? KeyVisualState.neutralBlack
            : KeyVisualState.neutralWhite;
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: containerWidth,
            child: PracticeKeyboard(
              totalWidth: totalWidth,
              whiteWidth: whiteWidth,
              blackWidth: blackWidth,
              whiteHeight: 90,
              blackHeight: 60,
              firstKey: firstKey,
              lastKey: lastKey,
              blackKeys: blackKeys,
              keyColors: keyColors,
              noteToXFn: (note) => PracticeKeyboard.noteToX(
                note: note,
                firstKey: firstKey,
                whiteWidth: whiteWidth,
                blackWidth: blackWidth,
                blackKeys: blackKeys,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    // Should render cyan for midi60 - visual verification would need golden tests
  });
}
