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
    const keyboardPadding = 0.0;
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
              expectedNote: null,
              detectedNote: null,
              leftPadding: keyboardPadding,
            ),
          ),
        ),
      ),
    );

    final box = tester.renderObject<RenderBox>(find.byType(PracticeKeyboard));
    expect(box.size.width, lessThanOrEqualTo(containerWidth));
  });
}
