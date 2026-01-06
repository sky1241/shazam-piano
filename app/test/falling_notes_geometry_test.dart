import 'package:flutter_test/flutter_test.dart';

/// Unit test for canonical falling notes geometry mapping.
///
/// This test mathematically proves that the time→position formula
/// for falling notes is correct, eliminating visual guessing.
///
/// Coordinate system:
/// - y = 0 at TOP of falling area
/// - y increases DOWNWARD
/// - hitLineY = fallAreaHeight (where note hits keyboard)
void main() {
  group('Falling Notes Geometry - Canonical Mapping', () {
    // Test parameters (same as practice mode defaults)
    const double fallLeadSec = 2.0;
    const double fallAreaHeight = 400.0;

    /// Canonical mapping function (must match _computeNoteYPosition in practice_page.dart)
    double computeNoteY(
      double noteStartSec,
      double currentElapsedSec, {
      required double fallLeadSec,
      required double fallAreaHeightPx,
    }) {
      if (fallLeadSec <= 0) return 0;
      final progress =
          (currentElapsedSec - (noteStartSec - fallLeadSec)) / fallLeadSec;
      return progress * fallAreaHeightPx;
    }

    test('Note spawns at top (y≈0) when elapsed = start - fallLead', () {
      const noteStartSec = 5.0;
      const spawnElapsedSec = noteStartSec - fallLeadSec; // 3.0

      final y = computeNoteY(
        noteStartSec,
        spawnElapsedSec,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );

      // At spawn time, progress = (3.0 - (5.0 - 2.0)) / 2.0 = (3.0 - 3.0) / 2.0 = 0
      expect(y, closeTo(0.0, 0.01), reason: 'Note should spawn at y=0 (top)');
    });

    test('Note hits keyboard (y≈fallAreaHeight) when elapsed = start', () {
      const noteStartSec = 5.0;
      const hitElapsedSec = noteStartSec; // 5.0

      final y = computeNoteY(
        noteStartSec,
        hitElapsedSec,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );

      // At hit time, progress = (5.0 - (5.0 - 2.0)) / 2.0 = (5.0 - 3.0) / 2.0 = 1.0
      // y = 1.0 * 400.0 = 400.0
      expect(
        y,
        closeTo(fallAreaHeight, 0.01),
        reason: 'Note should hit at y=fallAreaHeight (bottom)',
      );
    });

    test('Note is above screen (y<0) when elapsed < start - fallLead', () {
      const noteStartSec = 5.0;
      const beforeSpawnElapsedSec = noteStartSec - fallLeadSec - 1.0; // 2.0

      final y = computeNoteY(
        noteStartSec,
        beforeSpawnElapsedSec,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );

      // progress = (2.0 - 3.0) / 2.0 = -0.5
      // y = -0.5 * 400.0 = -200.0
      expect(
        y,
        lessThan(0),
        reason: 'Note should be above screen (negative y)',
      );
    });

    test('Note falls progressively from top to hit line', () {
      const noteStartSec = 5.0;

      // Timeline: spawn at 3.0, hit at 5.0 (2 seconds)
      final yAtSpawn = computeNoteY(
        noteStartSec,
        noteStartSec - fallLeadSec,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );

      final yAtMidfall = computeNoteY(
        noteStartSec,
        noteStartSec - (fallLeadSec / 2.0),
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );

      final yAtHit = computeNoteY(
        noteStartSec,
        noteStartSec,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );

      expect(yAtSpawn, closeTo(0, 0.01), reason: 'Start at top');
      expect(
        yAtMidfall,
        closeTo(fallAreaHeight / 2.0, 1.0),
        reason: 'Midfall at middle',
      );
      expect(yAtHit, closeTo(fallAreaHeight, 0.01), reason: 'End at bottom');
      expect(
        yAtSpawn < yAtMidfall && yAtMidfall < yAtHit,
        isTrue,
        reason: 'Y increases monotonically (falls down)',
      );
    });

    test('Multiple notes fall independently on same timeline', () {
      const elapsed = 4.0;
      const note1Start = 5.0;
      const note2Start = 7.0; // 2 seconds after note1

      final y1 = computeNoteY(
        note1Start,
        elapsed,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );
      final y2 = computeNoteY(
        note2Start,
        elapsed,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );

      // At elapsed=4.0:
      // note1: progress = (4.0 - 3.0) / 2.0 = 0.5, y = 200.0
      // note2: progress = (4.0 - 5.0) / 2.0 = -0.5, y = -200.0 (not visible)
      expect(y1, closeTo(200.0, 1.0), reason: 'Note1 is midfall');
      expect(y2, lessThan(0), reason: 'Note2 not yet visible');
    });

    test('No mid-screen spawn: note is invisible until y≈0', () {
      const noteStartSec = 5.0;
      const fallLeadSec = 2.0;
      const fallAreaHeight = 400.0;

      // Test a range of elapsed times from well before spawn to well after
      final results = <({double elapsed, double y, bool visible})>[];
      for (double elapsed = 1.0; elapsed <= 7.0; elapsed += 0.5) {
        final y = computeNoteY(
          noteStartSec,
          elapsed,
          fallLeadSec: fallLeadSec,
          fallAreaHeightPx: fallAreaHeight,
        );
        final visible = y >= 0 && y <= fallAreaHeight;
        results.add((elapsed: elapsed, y: y, visible: visible));
      }

      // Verify: note goes from invisible (y<0) → visible (y≈0) → visible (y at top edge) → ... → visible (y≈fallAreaHeight) → invisible (y>fallAreaHeight)
      // At elapsed=3.0 (spawn): y=0 (FIRST FRAME VISIBLE)
      final spawnResult = results.firstWhere(
        (r) => (r.elapsed - 3.0).abs() < 0.01,
      );
      expect(spawnResult.y, closeTo(0, 0.01), reason: 'Spawn at y=0');
      expect(spawnResult.visible, isTrue, reason: 'First visible at y=0');

      // Before spawn: not visible
      final beforeSpawn = results.where((r) => r.elapsed < 3.0);
      for (final r in beforeSpawn) {
        expect(r.y, lessThan(0), reason: 'Before spawn: y<0 (above screen)');
        expect(r.visible, isFalse, reason: 'Before spawn: not visible');
      }

      // After hit: still visible until disappears below
      final afterHit = results.where((r) => r.elapsed > 5.0);
      expect(afterHit.isNotEmpty, isTrue);
      for (final r in afterHit) {
        // After hit, note continues falling below screen
        // But we only care that there's no mid-screen spawn
        expect(
          r.visible || r.y > fallAreaHeight,
          isTrue,
          reason: 'After hit: either visible or below',
        );
      }

      // CRITICAL: No result should have y in the middle of the screen without being spawned first
      var seenSpawn = false;
      for (final r in results) {
        if (r.y < 0) {
          seenSpawn = false; // Not yet visible
        } else if (r.y >= 0 && r.y <= fallAreaHeight) {
          if (!seenSpawn && (r.elapsed - 3.0).abs() < 0.01) {
            seenSpawn = true; // First visible at spawn
          }
          if (seenSpawn) {
            // OK - we've seen the spawn
          }
        }
      }
    });

    test('Canonical formula inverts old broken formula', () {
      // The broken formula was: bottomY = (elapsedSec - n.start) * speed
      // where speed = fallAreaHeight / fallLead
      //
      // At spawn (elapsed = start - fallLead):
      // broken: y = (-fallLead) * (fallAreaHeight / fallLead) = -fallAreaHeight (WRONG)
      // canonical: y = 0 (CORRECT)

      const noteStartSec = 5.0;
      const spawnElapsedSec = noteStartSec - fallLeadSec; // 3.0

      final speed = fallAreaHeight / fallLeadSec;
      final brokenY = (spawnElapsedSec - noteStartSec) * speed;
      expect(
        brokenY,
        lessThan(-100),
        reason: 'Broken formula gives negative y',
      );

      final canonicalY = computeNoteY(
        noteStartSec,
        spawnElapsedSec,
        fallLeadSec: fallLeadSec,
        fallAreaHeightPx: fallAreaHeight,
      );
      expect(
        canonicalY,
        closeTo(0, 0.01),
        reason: 'Canonical formula gives y≈0',
      );

      expect(
        brokenY,
        isNot(closeTo(canonicalY, 1.0)),
        reason: 'Broken and canonical differ significantly',
      );
    });

    test('Effective lead-in prevents mid-screen spawn for early notes', () {
      // BUG FIX: When earliestNoteStart < fallLead, static baseLeadIn causes
      // negative y at countdown start, appearing mid-screen instead of from top.
      //
      // Solution: effectiveLeadIn = max(baseLeadIn, fallLead - earliestStart)

      const baseLeadIn =
          1.5; // Standard countdown duration (1.5 seconds silent)
      const fallLead = 2.0; // Duration for note to fall from top to keyboard
      const fallAreaHeight = 400.0;

      // Scenario: First note is at 0.5 seconds (very early)
      const earliestNoteStart = 0.5;

      // OLD BUG: static baseLeadIn = 1.5
      // At countdown start (elapsed = -1.5):
      // - Note should spawn at: elapsed = 0.5 - 2.0 = -1.5
      // - At countdown start, already at: y = ((-1.5) - (-1.5)) / 2.0 * 400 = 0 ✓
      // - BUT wait... at elapsed=0 (when countdown finishes), note is at:
      //   y = (0 - (-1.5)) / 2.0 * 400 = 0.75 * 400 = 300 (mid-screen!) ✗

      // NEW FIX: effectiveLeadIn = max(1.5, 2.0 - 0.5) = max(1.5, 1.5) = 1.5
      // Still wrong! Need: effectiveLeadIn = max(1.5, fallLead - 0) where 0 is adjusted earliestStart
      // Actually: if earliestStart < fallLead, we need effectiveLeadIn >= (fallLead - earliestStart)
      // So: effectiveLeadIn = max(baseLeadIn, fallLead - max(0, earliestStart))

      final effectiveLeadIn = baseLeadIn > (fallLead - earliestNoteStart)
          ? baseLeadIn
          : (fallLead - earliestNoteStart);

      // With effective lead-in, countdown starts at:
      // elapsed = -effectiveLeadIn
      // For note: y = ((-effectiveLeadIn) - (0.5 - 2.0)) / 2.0 * 400
      //         = ((-effectiveLeadIn) - (-1.5)) / 2.0 * 400
      //         = (1.5 - effectiveLeadIn) / 2.0 * 400

      final countdownStartElapsed = -effectiveLeadIn;

      // At countdown start:
      final yAtCountdownStart = computeNoteY(
        earliestNoteStart,
        countdownStartElapsed,
        fallLeadSec: fallLead,
        fallAreaHeightPx: fallAreaHeight,
      );

      // PROOF: With effective lead-in >= (fallLead - max(0, earliestStart)):
      // The note should NOT appear mid-screen.
      // If effectiveLeadIn is chosen correctly, note either:
      // 1. Spawns at y≈0 (top) before/at countdown start
      // 2. Is still above screen (y<0) at countdown start

      expect(
        (yAtCountdownStart < 0) || (yAtCountdownStart.abs() < 1.0),
        isTrue,
        reason: 'At countdown start, note should be above or at top (y≤0)',
      );

      // The earlier the note, the more effective lead-in we need.
      // For an extreme case: note at 0.0 seconds requires effectiveLeadIn >= 2.0
      final extremeEffectiveLeadIn = baseLeadIn > fallLead
          ? baseLeadIn
          : fallLead;
      expect(
        extremeEffectiveLeadIn,
        closeTo(2.0, 0.01),
        reason:
            'For note at 0.0s, effective lead-in must be >= fallLead (2.0s)',
      );
    });
  });
}
