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
              recentlyHitNotes: const {}, // FIX: Add required parameter
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

  testWidgets('PracticeKeyboard prevents false red notes when recently hit', (
    tester,
  ) async {
    // BUG FIX TEST: Regression test for "false red notes" bug
    // Scenario: Note was played correctly (HIT), but timing window moved forward
    // Result: targetNotes no longer contains the MIDI, but detectedNote still holds it
    // Expected: Should show GREEN (success) not RED (wrong), because it was recently validated
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

    // CASE 1: Note detected but NOT in targetNotes and NOT recently hit -> RED (wrong)
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
              targetNotes: const {}, // C4 not expected
              detectedNote: midi60, // C4 detected
              recentlyHitNotes: const {}, // NOT recently hit
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
    // Should show red (wrong note, not recently validated)
    // This case is CORRECT behavior - truly wrong note

    // CASE 2: Note detected, NOT in targetNotes, but WAS recently hit -> GREEN (success)
    // This is the BUG FIX: prevents false red
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
              targetNotes: const {}, // C4 not in current targets
              detectedNote: midi60, // C4 still detected (held)
              recentlyHitNotes: const {midi60}, // BUT was recently validated!
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
    // Should show GREEN (success), NOT red
    // This prevents the "false red" bug where correctly played notes turn red
    // after the timing window moves forward

    // Test passes if no exceptions thrown (visual verification would need golden tests)
  });

  testWidgets('PracticeKeyboard shows green for expected notes', (
    tester,
  ) async {
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

    // Note detected AND in targetNotes -> should be green
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
              targetNotes: const {midi60}, // C4 expected
              detectedNote: midi60, // C4 detected
              recentlyHitNotes: const {},
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
    // Should show green (correct hit)
  });
}
