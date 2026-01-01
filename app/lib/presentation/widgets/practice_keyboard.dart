import 'dart:math';

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
  final int? targetNote;
  final int? detectedNote;
  final int? successFlashNote;
  final bool successFlashActive;
  final int? wrongFlashNote;
  final bool wrongFlashActive;
  final double leftPadding;

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
    required this.targetNote,
    required this.detectedNote,
    this.successFlashNote,
    this.successFlashActive = false,
    this.wrongFlashNote,
    this.wrongFlashActive = false,
    required this.leftPadding,
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
                  left: leftPadding + (i * whiteWidth),
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
                    left: leftPadding + _noteToX(note),
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

  double _noteToX(int note) {
    return noteToX(
      note: note,
      firstKey: firstKey,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      blackKeys: blackKeys,
    );
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
    final isExpected = note == targetNote;
    final isDetected = note == detectedNote;

    Color keyColor;
    if (successFlashActive &&
        successFlashNote != null &&
        note == successFlashNote) {
      keyColor = AppColors.success.withValues(alpha: 0.9);
    } else if (wrongFlashActive &&
        wrongFlashNote != null &&
        note == wrongFlashNote) {
      keyColor = AppColors.error.withValues(alpha: 0.9);
    } else if (isDetected && isExpected) {
      keyColor = AppColors.success;
    } else if (isExpected) {
      keyColor = AppColors.primary.withValues(alpha: 0.5);
    } else if (isBlack) {
      keyColor = AppColors.blackKey;
    } else {
      keyColor = AppColors.whiteKey;
    }

    final isC = note % 12 == 0;
    final label = isBlack
        ? ''
        : (isC ? _noteLabel(note, withOctave: true) : '');
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
