import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
              targetNotes: const {},
              detectedNote: null,
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
}
