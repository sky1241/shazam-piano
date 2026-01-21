part of '../practice_page.dart';

class _FallingNotesPainter extends CustomPainter {
  final List<_NoteEvent> noteEvents;
  final double elapsedSec;
  final double whiteWidth;
  final double blackWidth;
  final double fallAreaHeight;
  final double fallLead;
  final double fallTail;
  final double Function(int) noteToX;
  final int firstKey;
  final int lastKey;
  final Set<int> targetNotes;
  final int? successNote;
  final int?
  successNoteIndex; // FIX BUG SESSION-005 #1+2: Flash by index, not pitch
  final bool successFlashActive;
  final int? wrongNote;
  final bool wrongFlashActive;
  final bool forceLabels;
  final bool showGuides;
  final bool showMidiNumbers;

  static const List<int> _blackKeySteps = [1, 3, 6, 8, 10];
  static final Map<String, TextPainter> _labelFillCache = {};
  static final Map<String, TextPainter> _labelStrokeCache = {};
  static int _paintCallCount = 0;

  _FallingNotesPainter({
    required this.noteEvents,
    required this.elapsedSec,
    required this.whiteWidth,
    required this.blackWidth,
    required this.fallAreaHeight,
    required this.fallLead,
    required this.fallTail,
    required this.noteToX,
    required this.firstKey,
    required this.lastKey,
    required this.targetNotes,
    required this.successNote,
    this.successNoteIndex, // FIX BUG SESSION-005 #1+2
    required this.successFlashActive,
    required this.wrongNote,
    required this.wrongFlashActive,
    required this.forceLabels,
    required this.showGuides,
    required this.showMidiNumbers,
  });

  String _labelForSpace(
    int midi,
    double width,
    double barHeight, {
    required bool forceFull,
  }) {
    const names = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final base = names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    final fullLabel = '$base$octave ($midi)';
    final octaveLabel = '$base$octave';
    if (width < 16 || barHeight < 16) {
      return base;
    }
    return forceFull ? fullLabel : octaveLabel;
  }

  double _labelFontSize(double width, double barHeight, String label) {
    final widthFactor = label.length <= 2 ? 0.75 : 0.6;
    final raw = min(barHeight * 0.55, width * widthFactor);
    return raw.clamp(12.0, 18.0);
  }

  TextPainter _getLabelPainter(
    String label,
    double fontSize, {
    required bool stroke,
  }) {
    final key = '$label:${fontSize.toStringAsFixed(1)}:${stroke ? 's' : 'f'}';
    final cache = stroke ? _labelStrokeCache : _labelFillCache;
    final cached = cache[key];
    if (cached != null) {
      return cached;
    }
    final paint = Paint()
      ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = stroke ? 2.0 : 0.0
      ..color = stroke ? Colors.black : Colors.white;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          foreground: paint,
          shadows: stroke
              ? null
              : [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    cache[key] = painter;
    return painter;
  }

  /// CANONICAL MAPPING: time → screen y-coordinate
  /// Mathematically proven formula for falling notes.
  ///
  /// Coordinate system:
  /// - y=0 at TOP of falling area
  /// - y increases DOWNWARD
  /// - hitLineY = y position where note "hits" (typically fallAreaHeight)
  ///
  /// Given:
  /// - note.startSec: absolute time note should hit the target
  /// - fallLead: time (seconds) for note to travel from top to hit line
  /// - elapsedSec: current elapsed time
  /// - fallAreaHeight: vertical pixels from top to hit line
  ///
  /// Formula:
  /// progress = (elapsedSec - (note.startSec - fallLead)) / fallLead
  /// y = progress * fallAreaHeight
  ///
  /// Boundary conditions:
  /// - elapsed = note.start - fallLead => y = 0 (note spawns at top)
  /// - elapsed = note.start => y = fallAreaHeight (note hits line)
  /// - progress < 0 => note not yet visible (above screen)
  /// - progress > (1 + tailDuration/fallLead) => note has disappeared below
  double _computeNoteYPosition(
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

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // DEBUG: Log paint calls during countdown (limit to first 10)
    if (elapsedSec < 0 && _paintCallCount < 10) {
      _paintCallCount++;
      debugPrint(
        '[PAINTER] paint() call #$_paintCallCount: elapsed=$elapsedSec fallLead=$fallLead noteCount=${noteEvents.length} size=$size',
      );
    }

    if (showGuides) {
      final guidePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = 1;
      for (int note = firstKey; note <= lastKey; note++) {
        if (_blackKeySteps.contains(note % 12)) {
          continue;
        }
        final x = noteToX(note) + (whiteWidth / 2);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), guidePaint);
      }
    }

    // CULLING: only draw notes within active window
    int drawnCount = 0;
    // FIX BUG SESSION-005 #1+2: Use indexed loop to match flash by noteIndex
    for (int noteIdx = 0; noteIdx < noteEvents.length; noteIdx++) {
      final n = noteEvents[noteIdx];
      if (n.pitch < firstKey || n.pitch > lastKey) {
        continue;
      }
      // CRITICAL FIX: Allow negative elapsed (countdown) - notes must spawn offscreen top
      // Only cull notes that are completely past (not future - countdown has elapsed < 0)
      final disappear = n.end + fallTail;
      if (elapsedSec > disappear && elapsedSec > 0) {
        continue; // Skip only if past AND not countdown
      }

      // Use CANONICAL mapping for vertical position
      final bottomY = _computeNoteYPosition(
        n.start,
        elapsedSec,
        fallLeadSec: fallLead,
        fallAreaHeightPx: fallAreaHeight,
      );
      final topY = _computeNoteYPosition(
        n.end,
        elapsedSec,
        fallLeadSec: fallLead,
        fallAreaHeightPx: fallAreaHeight,
      );

      // DEBUG: Log Y positions for first few notes during countdown
      if (elapsedSec < 0 && _paintCallCount <= 3 && drawnCount < 3) {
        debugPrint(
          '[PAINTER] Note midi=${n.pitch} start=${n.start} end=${n.end}: topY=$topY bottomY=$bottomY (elapsed=$elapsedSec fallLead=$fallLead height=$fallAreaHeight)',
        );
      }

      // FIX FINAL V4: Check if note rectangle CROSSES keyboard line (visual intersection)
      // BUG WAS: targetNotes contains all pitches → colored ALL notes with same pitch
      // SOLUTION: Check if rectangle [topY, bottomY] intersects keyboard zone
      final hitZonePixels = 50.0;
      final keyboardY = fallAreaHeight;
      final rectTop = min(topY, bottomY);
      final rectBot = max(topY, bottomY);
      final rectBottom = bottomY; // Keep for legacy compatibility

      // Cull notes completely outside visible area (allows spawnY < 0 offscreen)
      if (rectBottom < 0 || rectTop > fallAreaHeight) {
        continue;
      }
      final barHeight = max(1.0, rectBottom - rectTop);

      final x = noteToX(n.pitch);
      // C5: Skip if noteToX returns null (safety) - should never happen
      if (x.isNaN || x.isInfinite || x < -1000 || x > size.width + 1000) {
        continue;
      }
      final isBlack = _blackKeySteps.contains(n.pitch % 12);
      final width = isBlack ? blackWidth : whiteWidth;
      if (x + width < 0 || x > size.width) {
        continue;
      }
      final isCrossingKeyboard =
          (rectTop <= keyboardY + hitZonePixels) &&
          (rectBot >= keyboardY - hitZonePixels);
      final isTarget = isCrossingKeyboard && targetNotes.contains(n.pitch);
      // FIX BUG SESSION-005 #1+2: Use noteIndex for flash matching (not pitch)
      // This prevents ALL notes with same pitch from flashing when ONE is hit
      final isSuccessFlash =
          successFlashActive &&
          successNoteIndex != null &&
          noteIdx == successNoteIndex;
      // SESSION-020 FIX BUG #2: wrongFlash coupling REMOVED from falling notes
      // Wrong flash must ONLY affect the keyboard (bottom), NOT the falling notes.
      // Previously: wrongFlashActive && wrongNote != null && n.pitch == wrongNote
      // Now: wrongFlash is handled ONLY by PracticeKeyboard widget.

      // FIX BUG 5+7: Change rectangle color when note hit, not just halo
      // Before: Rectangle stayed orange with blue halo overlay (inconsistent)
      // After: Rectangle becomes green/cyan like keyboard key (consistent visual feedback)
      if (isTarget) {
        final glowPaint = Paint()
          ..color = AppColors.success.withValues(alpha: 0.40)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        final glowRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - 2,
            rectBottom - barHeight - 2,
            width + 4,
            barHeight + 4,
          ),
          const Radius.circular(5),
        );
        canvas.drawRRect(glowRect, glowPaint);
      }

      // Priority: successFlash > isTarget (note hit) > default (orange)
      // SESSION-020 FIX BUG #2: wrongFlash removed from falling notes color logic
      // Wrong flash feedback is now ONLY on the keyboard (bottom), not falling notes.
      paint.color = isSuccessFlash
          ? AppColors.success.withValues(alpha: 0.95)
          : isTarget
          ? AppColors.success.withValues(alpha: 0.85)
          : AppColors.warning.withValues(alpha: 0.85);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, rectBottom - barHeight, width, barHeight),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, paint);

      final label = _labelForSpace(
        n.pitch,
        width,
        barHeight,
        forceFull: showMidiNumbers || isTarget,
      );
      final fontSize = _labelFontSize(width, barHeight, label);
      final textPainter = _getLabelPainter(label, fontSize, stroke: false);
      final labelY = max(
        rectBottom - textPainter.height - 4,
        rectBottom - barHeight + 2,
      );
      final maxLabelY = max(0.0, fallAreaHeight - textPainter.height);
      final clampedLabelY = labelY.clamp(0.0, maxLabelY);
      final textOffset = Offset(
        x + (width - textPainter.width) / 2,
        clampedLabelY,
      );
      final canDrawLabel =
          width > 4 &&
          (barHeight > textPainter.height + 4 || forceLabels || isTarget);
      if (canDrawLabel) {
        final background = Paint()..color = Colors.black.withValues(alpha: 0.4);
        final padX = 3.0;
        final padY = 2.0;
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            textOffset.dx - padX,
            textOffset.dy - padY,
            textPainter.width + (padX * 2),
            textPainter.height + (padY * 2),
          ),
          const Radius.circular(4),
        );
        canvas.drawRRect(bgRect, background);
        final strokePainter = _getLabelPainter(label, fontSize, stroke: true);
        strokePainter.paint(canvas, textOffset);
        textPainter.paint(canvas, textOffset);
      }

      drawnCount++;
    }

    // DEBUG: Log drawn notes during countdown (limit)
    if (elapsedSec < 0 && _paintCallCount <= 10) {
      debugPrint('[PAINTER] Drawn $drawnCount notes during countdown');
    }
  }

  @override
  bool shouldRepaint(covariant _FallingNotesPainter oldDelegate) {
    return oldDelegate.elapsedSec != elapsedSec ||
        oldDelegate.noteEvents != noteEvents ||
        oldDelegate.whiteWidth != whiteWidth ||
        oldDelegate.blackWidth != blackWidth ||
        oldDelegate.fallAreaHeight != fallAreaHeight ||
        oldDelegate.fallLead != fallLead ||
        oldDelegate.fallTail != fallTail ||
        oldDelegate.noteToX != noteToX ||
        !setEquals(oldDelegate.targetNotes, targetNotes) ||
        oldDelegate.firstKey != firstKey ||
        oldDelegate.lastKey != lastKey ||
        oldDelegate.successNote != successNote ||
        oldDelegate.successNoteIndex !=
            successNoteIndex || // FIX BUG SESSION-005 #1+2
        oldDelegate.successFlashActive != successFlashActive ||
        oldDelegate.wrongNote != wrongNote ||
        oldDelegate.wrongFlashActive != wrongFlashActive ||
        oldDelegate.forceLabels != forceLabels ||
        oldDelegate.showGuides != showGuides ||
        oldDelegate.showMidiNumbers != showMidiNumbers;
  }
}
