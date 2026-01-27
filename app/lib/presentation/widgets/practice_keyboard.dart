import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

class PracticeKeyboard extends StatelessWidget {
  final double totalWidth;
  final double whiteWidth;
  final double blackWidth;
  final double whiteHeight;
  final double blackHeight;
  final int firstKey;
  final int lastKey;
  final List<int> blackKeys;
  final Set<int> targetNotes;
  final int? detectedNote;
  final int? successFlashNote;
  final bool successFlashActive;
  final int? wrongFlashNote;
  final bool wrongFlashActive;
  // FIX BUG SESSION-005 #4: Miss flash for red keyboard feedback
  final int? missFlashNote;
  final bool missFlashActive;
  // SESSION-036: Anticipated flash for zero-lag feel (CYAN #00BCD4)
  final int? anticipatedFlashNote;
  final bool anticipatedFlashActive;
  // SESSION-036c: Detected note flash for "REAL-TIME FEEL" (BLUE #2196F3)
  final int? detectedFlashNote;
  final bool detectedFlashActive;
  final double Function(int) noteToXFn;
  final bool showDebugLabels;
  final bool showMidiNumbers;
  final Set<int> recentlyHitNotes; // FIX: Track recently validated HIT notes

  const PracticeKeyboard({
    super.key,
    required this.totalWidth,
    required this.whiteWidth,
    required this.blackWidth,
    required this.whiteHeight,
    required this.blackHeight,
    required this.firstKey,
    required this.lastKey,
    required this.blackKeys,
    required this.targetNotes,
    required this.detectedNote,
    this.successFlashNote,
    this.successFlashActive = false,
    this.wrongFlashNote,
    this.wrongFlashActive = false,
    this.missFlashNote, // FIX BUG SESSION-005 #4
    this.missFlashActive = false, // FIX BUG SESSION-005 #4
    this.anticipatedFlashNote, // SESSION-036: Anticipated flash (CYAN)
    this.anticipatedFlashActive = false, // SESSION-036
    this.detectedFlashNote, // SESSION-036c: Detected flash (BLUE)
    this.detectedFlashActive = false, // SESSION-036c
    required this.noteToXFn,
    this.showDebugLabels = false,
    this.showMidiNumbers = false,
    this.recentlyHitNotes = const {}, // FIX: Default to empty set
  });

  static double noteToX({
    required int note,
    required int firstKey,
    required double whiteWidth,
    required double blackWidth,
    required List<int> blackKeys,
    double offset = 0.0,
  }) {
    int whiteIndex = 0;
    for (int n = firstKey; n < note; n++) {
      if (!_isBlackKeyStatic(n, blackKeys)) {
        whiteIndex += 1;
      }
    }
    double x = whiteIndex * whiteWidth;
    if (_isBlackKeyStatic(note, blackKeys)) {
      x -= (blackWidth / 2);
    }
    return x + offset;
  }

  static bool _isBlackKeyStatic(int note, List<int> blackKeys) {
    return blackKeys.contains(note % 12);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : totalWidth;
        final width = totalWidth.isFinite && totalWidth > 0
            ? min(totalWidth, maxWidth)
            : maxWidth;
        final height = whiteHeight + AppConstants.spacing12;
        final whiteNotes = <int>[];
        for (int note = firstKey; note <= lastKey; note++) {
          if (!_isBlackKey(note)) {
            whiteNotes.add(note);
          }
        }

        return SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (int i = 0; i < whiteNotes.length; i++)
                Positioned(
                  left: _resolveNoteToX(whiteNotes[i]),
                  child: _buildPianoKey(
                    context,
                    whiteNotes[i],
                    isBlack: false,
                    width: whiteWidth,
                    height: whiteHeight,
                  ),
                ),
              for (int note = firstKey; note <= lastKey; note++)
                if (_isBlackKey(note))
                  Positioned(
                    left: _resolveNoteToX(note),
                    child: _buildPianoKey(
                      context,
                      note,
                      isBlack: true,
                      width: blackWidth,
                      height: blackHeight,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  bool _isBlackKey(int note) {
    return blackKeys.contains(note % 12);
  }

  double _resolveNoteToX(int note) {
    return noteToXFn(note);
  }

  String _noteLabel(int midi, {bool withOctave = false}) {
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
    if (!withOctave) {
      return base;
    }
    final octave = (midi ~/ 12) - 1;
    return '$base$octave';
  }

  Widget _buildPianoKey(
    BuildContext context,
    int note, {
    required bool isBlack,
    required double width,
    required double height,
  }) {
    final isExpected = targetNotes.contains(note);
    final isDetected = note == detectedNote;
    // FIX BUG SESSION-004 #1: Check if note was recently validated as HIT
    // This prevents the "green switch" when uiDetectedMidi expires but note is still active
    final wasRecentlyHit = recentlyHitNotes.contains(note);

    Color keyColor;
    if (successFlashActive &&
        successFlashNote != null &&
        note == successFlashNote) {
      // SESSION-034 FIX: Use full opacity on black keys for visibility
      // CAUSE: alpha:0.9 blended with black base = nearly invisible green
      // PREUVE: FLASH_KEY_RENDER midi=61 finalColor=GREEN but video shows no flash
      // Black keys (C#, D#, F#, G#, A#) need full color to be visible
      keyColor = isBlack
          ? AppColors.success // Full opacity on black keys
          : AppColors.success.withValues(alpha: 0.9);
    } else if (wrongFlashActive &&
        wrongFlashNote != null &&
        note == wrongFlashNote) {
      // FIX BUG P0 (PHANTOM RED): Only show red via wrongFlash (scored as wrong)
      // Removed standalone isWrong condition - it caused phantom reds from mic noise
      // SESSION-034 FIX: Use full opacity on black keys for visibility
      keyColor = isBlack
          ? AppColors.error // Full opacity on black keys
          : AppColors.error.withValues(alpha: 0.9);
    } else if (anticipatedFlashActive &&
        anticipatedFlashNote != null &&
        note == anticipatedFlashNote) {
      // SESSION-036: Anticipated flash (CYAN #00BCD4) for zero-lag feel
      // Priority: success > wrong > anticipated > detected > neutral
      // CYAN provides instant visual feedback on onset detection before pitch confirmation
      const cyanColor = Color(0xFF00BCD4); // Material CYAN 500
      keyColor = isBlack
          ? cyanColor // Full opacity on black keys
          : cyanColor.withValues(alpha: 0.9);
    } else if (detectedFlashActive &&
        detectedFlashNote != null &&
        note == detectedFlashNote) {
      // SESSION-036c: Detected flash (BLUE #2196F3) for "REAL-TIME FEEL"
      // Priority: success > wrong > anticipated > detected > neutral
      // BLUE shows what the mic actually heard (independent of scoring)
      const blueColor = Color(0xFF2196F3); // Material BLUE 500
      keyColor = isBlack
          ? blueColor // Full opacity on black keys
          : blueColor.withValues(alpha: 0.9);
    }
    // FIX BUG SESSION-007 #2: REMOVED missFlash red for missed notes
    // Miss = note NOT played → keyboard stays BLACK (no feedback)
    // Keyboard reflects only PLAYED notes, not unplayed expected notes
    // Previously: missFlashActive && missFlashNote == note → red
    // Now: removed - keyboard only shows feedback for PLAYED notes
    else if (isDetected && isExpected) {
      // FIX BUG (GHOST GREEN): Only show green if note is CURRENTLY expected
      keyColor = AppColors.success;
    } else if (isExpected && wasRecentlyHit) {
      // FIX BUG SESSION-004 #1: Note was hit and is still expected = keep solid green
      // This prevents the visual "switch" between solid green and semi-transparent
      keyColor = AppColors.success;
    }
    // FIX BUG SESSION-008 #1+2: REMOVED green highlight for unplayed expected notes
    // Before: isExpected alone would light keyboard green even if note wasn't played
    // This caused:
    //   - BUG 1: Missed notes showing green keyboard (should stay black)
    //   - BUG 2: "Double green" illusion when miss + next note same pitch
    // Now: Keyboard only shows green if note is DETECTED or was RECENTLY HIT
    // Expected-but-unplayed notes stay at their natural color (black/white)
    else if (isBlack) {
      keyColor = AppColors.blackKey;
    } else {
      keyColor = AppColors.whiteKey;
    }

    // SESSION-035/036/036c: Enhanced log for flash debugging with ARGB values
    // Logs ONLY for flash-targeted notes to avoid spam
    // CRITICAL: Proves whether flash props reach keyboard and final color applied
    if (kDebugMode &&
        (note == successFlashNote || note == wrongFlashNote ||
         note == anticipatedFlashNote || note == detectedFlashNote)) {
      const cyanColor = Color(0xFF00BCD4);
      const blueColor = Color(0xFF2196F3);
      final colorName = keyColor == AppColors.success ||
              keyColor == AppColors.success.withValues(alpha: 0.9)
          ? 'GREEN'
          : keyColor == AppColors.error ||
                  keyColor == AppColors.error.withValues(alpha: 0.9)
              ? 'RED'
              : keyColor == cyanColor || keyColor == cyanColor.withValues(alpha: 0.9)
                  ? 'CYAN'
                  : keyColor == blueColor || keyColor == blueColor.withValues(alpha: 0.9)
                      ? 'BLUE'
                      : keyColor == AppColors.blackKey
                          ? 'BLACK'
                          : 'WHITE';
      // SESSION-035: Add ARGB hex for precise color verification
      final argbHex =
          '0x${keyColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
      debugPrint(
        'FLASH_KEY_RENDER midi=$note isBlack=$isBlack isDetected=$isDetected isExpected=$isExpected '
        'wasRecentlyHit=$wasRecentlyHit successActive=$successFlashActive successMidi=$successFlashNote '
        'wrongActive=$wrongFlashActive wrongMidi=$wrongFlashNote '
        'anticipatedActive=$anticipatedFlashActive anticipatedMidi=$anticipatedFlashNote '
        'detectedActive=$detectedFlashActive detectedMidi=$detectedFlashNote '
        'finalColor=$colorName argb=$argbHex',
      );
    }

    final showLabel = !isBlack || showDebugLabels;
    final baseLabel = _noteLabel(note, withOctave: true);
    final label = showLabel
        ? (showMidiNumbers ? '$baseLabel ($note)' : baseLabel)
        : '';
    final labelMaxWidth = max(0.0, width - 6);
    final labelFontSize = max(12.0, min(16.0, width * 0.75));
    final labelColor = isBlack
        ? Colors.white.withValues(alpha: 0.95)
        : Colors.black.withValues(alpha: 0.85);
    final labelShadow = Shadow(
      color: Colors.black.withValues(alpha: isBlack ? 0.55 : 0.25),
      blurRadius: 2,
    );
    final labelBackground = isBlack
        ? Colors.black.withValues(alpha: 0.45)
        : Colors.black.withValues(alpha: 0.18);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: width,
          height: height,
          margin: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: keyColor,
            border: Border.all(color: AppColors.divider, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        if (label.isNotEmpty)
          Positioned(
            bottom: 6,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: labelMaxWidth),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: labelBackground,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SizedBox(
                  width: labelMaxWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        color: labelColor,
                        shadows: [labelShadow],
                      ),
                      overflow: TextOverflow.clip,
                      softWrap: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
