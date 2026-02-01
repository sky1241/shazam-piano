import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/practice/feedback/ui_feedback_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// Clavier de pratique RENDER-ONLY (SESSION-056)
///
/// Ce widget ne contient AUCUNE logique de décision.
/// Il reçoit une Map keyColors pré-calculée et peint.
///
/// La décision (priorité VERT, ROUGE, BLEU, CYAN, neutre)
/// est faite par UIFeedbackEngine.computeKeyColors()
class PracticeKeyboard extends StatelessWidget {
  final double totalWidth;
  final double whiteWidth;
  final double blackWidth;
  final double whiteHeight;
  final double blackHeight;
  final int firstKey;
  final int lastKey;
  final List<int> blackKeys;
  final double Function(int) noteToXFn;
  final bool showDebugLabels;
  final bool showMidiNumbers;

  /// État visuel pré-calculé pour chaque touche (RENDER-ONLY)
  /// Produit par UIFeedbackEngine.computeKeyColors()
  final Map<int, KeyVisualState> keyColors;

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
    required this.noteToXFn,
    required this.keyColors,
    this.showDebugLabels = false,
    this.showMidiNumbers = false,
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

  /// Construit une touche de piano RENDER-ONLY
  ///
  /// La couleur est lue directement depuis keyColors[note]
  /// AUCUNE logique de décision ici.
  Widget _buildPianoKey(
    BuildContext context,
    int note, {
    required bool isBlack,
    required double width,
    required double height,
  }) {
    // ═══════════════════════════════════════════════════════════════════════
    // RENDER-ONLY: Lire la couleur pré-calculée
    // ═══════════════════════════════════════════════════════════════════════
    final visualState =
        keyColors[note] ??
        (isBlack ? KeyVisualState.neutralBlack : KeyVisualState.neutralWhite);

    final keyColor = _stateToColor(visualState, isBlack);

    // Debug log pour flash states uniquement
    if (kDebugMode &&
        visualState != KeyVisualState.neutralBlack &&
        visualState != KeyVisualState.neutralWhite &&
        visualState != KeyVisualState.cyan) {
      final colorName = switch (visualState) {
        KeyVisualState.green => 'GREEN',
        KeyVisualState.red => 'RED',
        KeyVisualState.blue => 'BLUE',
        KeyVisualState.cyan => 'CYAN',
        _ => 'NEUTRAL',
      };
      debugPrint(
        'S56_KEY_RENDER midi=$note state=$visualState color=$colorName isBlack=$isBlack',
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

  /// Convertit KeyVisualState en Color (AUCUNE décision, juste mapping)
  Color _stateToColor(KeyVisualState state, bool isBlack) {
    return switch (state) {
      KeyVisualState.green =>
        isBlack ? AppColors.success : AppColors.success.withValues(alpha: 0.9),
      KeyVisualState.red =>
        isBlack ? AppColors.error : AppColors.error.withValues(alpha: 0.9),
      KeyVisualState.blue =>
        isBlack
            ? const Color(0xFF2196F3)
            : const Color(0xFF2196F3).withValues(alpha: 0.9),
      KeyVisualState.cyan =>
        isBlack
            ? const Color(0xFF00BCD4)
            : const Color(0xFF00BCD4).withValues(alpha: 0.9),
      KeyVisualState.neutralBlack => AppColors.blackKey,
      KeyVisualState.neutralWhite => AppColors.whiteKey,
    };
  }
}
