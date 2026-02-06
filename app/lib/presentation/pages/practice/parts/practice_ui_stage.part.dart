part of '../practice_page.dart';

/// Mixin for practice stage and keyboard UI widgets.
/// Extracted from _PracticePageState to reduce file size.
///
/// SESSION-056: Refactored to render-only pattern.
/// UIFeedbackEngine computes keyColors, keyboard just paints.
mixin _PracticeUiStageMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  Future<void> _loadNoteEvents({required int sessionId});
  double? _guidanceElapsedSec();
  Set<int> _uiTargetNotes({double? elapsedSec});
  void _handleRetryMicPermission();
  // From _PracticeUiVideoMixin
  Widget _buildVideoPlayer({
    required _KeyboardLayout layout,
    required Set<int> targetNotes,
    required double? elapsedSec,
  });

  Widget _buildPracticeContent({
    required _KeyboardLayout layout,
    required double horizontalPadding,
  }) {
    final elapsedSec = _guidanceElapsedSec();
    // FIX: Also check _practiceState to prevent painting during transition frames
    // This ensures notes are only painted during countdown or running, not during idle
    // FIX BUG 4: Wait for layout to stabilize before painting notes
    final shouldPaintNotes =
        (_practiceRunning || _practiceState == _PracticeState.countdown) &&
        _practiceState != _PracticeState.idle &&
        elapsedSec != null &&
        _noteEvents.isNotEmpty &&
        _isLayoutStable();
    final targetNotes = shouldPaintNotes
        ? _uiTargetNotes(elapsedSec: elapsedSec)
        : const <int>{};

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        children: [
          Expanded(
            child: _buildVideoPlayer(
              layout: layout,
              targetNotes: targetNotes,
              elapsedSec: elapsedSec,
            ),
          ),
          _buildPracticeStage(
            layout: layout,
            targetNotes: targetNotes,
            showMidiNumbers: _showMidiNumbers,
          ),
          // SESSION-036c: Mini debug overlay (kDebugMode only)
          if (kDebugMode && _practiceRunning) _buildMiniDebugOverlay(),
        ],
      ),
    );
  }

  // SESSION-056: Mini debug overlay showing S56 engine state
  // SESSION-059 ROUGE: redMidis est maintenant un Set<int> (multi-rouge)
  Widget _buildMiniDebugOverlay() {
    // Get values from UIFeedbackEngine (S56)
    final fbState = _uiFeedbackEngine?.state;
    final blueMidi = fbState?.blueMidi;
    final greenMidi = fbState?.greenMidi;
    final redMidis = fbState?.redMidis ?? {};
    final cyanMidis = fbState?.cyanMidis ?? {};
    final conf = fbState?.confidence ?? 0.0;
    final greenCount = _uiFeedbackEngine?.greenCount ?? 0;

    // Get raw detection info from MicEngine
    final rawMidi = _micEngine?.lastRawMidi;
    final rawConf = _micEngine?.lastRawConf;

    // Format display strings
    final blueStr = blueMidi != null ? '$blueMidi' : '--';
    final greenStr = greenMidi != null ? '$greenMidi' : '--';
    final redStr = redMidis.isNotEmpty ? '$redMidis' : '--';
    final cyanStr = cyanMidis.isNotEmpty ? '${cyanMidis.first}' : '--';
    final rawStr = rawMidi != null ? '$rawMidi' : '--';
    final confStr = conf.toStringAsFixed(2);
    final rawConfStr = rawConf != null ? rawConf.toStringAsFixed(2) : '--';

    // SESSION-075: DEBUG log pour comparer avec S56_KEYBOARD
    // Ce log doit TOUJOURS matcher S56_KEYBOARD car ils lisent le même état
    if (kDebugMode && (blueMidi != null || greenMidi != null || redMidis.isNotEmpty)) {
      debugPrint(
        'S56_OVERLAY blue=$blueMidi green=$greenMidi red=$redMidis '
        'cyan=$cyanMidis conf=${conf.toStringAsFixed(2)} '
        'raw=$rawMidi rawConf=${rawConf?.toStringAsFixed(2) ?? "--"}',
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'S56: blue:$blueStr green:$greenStr red:$redStr cyan:$cyanStr | raw:$rawStr conf:$confStr raw:$rawConfStr | greenCount:$greenCount',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildTopStatsLine() {
    // Hide stats when in idle state (before play or after stop)
    if (_practiceState == _PracticeState.idle) {
      return SizedBox.shrink();
    }

    String statsText = ''; // P0 fix: Initialize to avoid non-nullable error
    if (_useNewScoringSystem && _newController != null) {
      // SESSION 4: Display NEW scoring system stats
      final newState = _newController!.currentScoringState;
      final matched =
          newState.perfectCount + newState.goodCount + newState.okCount;
      // SUSTAIN SCORING: Precision based on cumulative sustain ratios
      // Each note contributes its sustainRatio (0.0-1.0) to total precision
      // Example: 5 notes, last one held 50% = 4*1.0 + 0.5 = 4.5/5 = 90%
      final precisionValue = _totalNotes > 0
          ? '${(_cumulativeSustainRatio / _totalNotes * 100).toStringAsFixed(1)}%'
          : '0%';
      statsText =
          'Précision: $precisionValue   Notes justes: $matched/$_totalNotes   Score: ${newState.totalScore}   Combo: ${newState.combo}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacing12,
        vertical: AppConstants.spacing8,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          statsText,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildMicPermissionFallback() {
    final status = _micPermissionStatus;
    final isPermanentlyDenied = status?.isPermanentlyDenied ?? false;
    final title = StringsFr.micAccessTitle;
    final body = isPermanentlyDenied
        ? StringsFr.micPermanentlyDeniedMessage
        : StringsFr.micDeniedMessage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacing16,
        AppConstants.spacing12,
        AppConstants.spacing16,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacing12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppConstants.radiusCard),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spacing8),
            Text(
              body,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppConstants.spacing12),
            Wrap(
              spacing: AppConstants.spacing8,
              children: [
                TextButton(
                  onPressed: _handleRetryMicPermission,
                  child: const Text(StringsFr.micRetry),
                ),
                TextButton(
                  onPressed: openAppSettings,
                  child: const Text(StringsFr.micOpenSettings),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPracticeStage({
    required _KeyboardLayout layout,
    required Set<int> targetNotes,
    required bool showMidiNumbers,
  }) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final whiteWidth = layout.whiteWidth;
    final blackWidth = layout.blackWidth;
    final displayWidth = layout.displayWidth;
    final outerWidth = layout.outerWidth;
    final shouldScroll = layout.shouldScroll;

    final whiteHeight = isPortrait ? 90.0 : 120.0;
    final blackHeight = isPortrait ? 60.0 : 80.0;
    final showNotesStatus =
        _notesLoading || _notesError != null || _noteEvents.isEmpty;

    final content = Container(
      width: outerWidth,
      padding: EdgeInsets.fromLTRB(
        layout.stagePadding,
        0,
        layout.stagePadding,
        layout.stagePadding,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showNotesStatus) _buildNotesStatus(displayWidth),
          if (showNotesStatus) const SizedBox(height: AppConstants.spacing8),
          _buildKeyboardWithSizes(
            totalWidth: displayWidth,
            whiteWidth: whiteWidth,
            blackWidth: blackWidth,
            whiteHeight: whiteHeight,
            blackHeight: blackHeight,
            targetNotes: targetNotes,
            noteToXFn: layout.noteToX,
            showDebugLabels: _showKeyboardDebugLabels,
            showMidiNumbers: showMidiNumbers,
          ),
        ],
      ),
    );

    if (shouldScroll) {
      return SingleChildScrollView(
        controller: _keyboardScrollController,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Align(alignment: Alignment.centerLeft, child: content),
      );
    }
    return Align(alignment: Alignment.center, child: content);
  }

  Widget _buildKeyboardWithSizes({
    required double totalWidth,
    required double whiteWidth,
    required double blackWidth,
    required double whiteHeight,
    required double blackHeight,
    required Set<int> targetNotes,
    required double Function(int) noteToXFn,
    required bool showDebugLabels,
    required bool showMidiNumbers,
  }) {
    // ═══════════════════════════════════════════════════════════════════════════
    // SESSION-056: RENDER-ONLY KEYBOARD
    // La décision (VERT > ROUGE > BLEU > CYAN > neutre) est faite par
    // UIFeedbackEngine.computeKeyColors() - le widget ne fait que peindre.
    // ═══════════════════════════════════════════════════════════════════════════

    Map<int, KeyVisualState> keyColors;

    if (_isS56ModeReady()) {
      // S56 READY: Utiliser le moteur de feedback perceptif
      keyColors = _uiFeedbackEngine!.computeKeyColors(
        firstKey: _displayFirstKey,
        lastKey: _displayLastKey,
        blackKeys: _blackKeys,
      );

      // Debug log (S56) - SESSION-058: Ajout resolved= pour montrer la couleur gagnante
      // SESSION-059 ROUGE: redMidis est maintenant un Set<int> (multi-rouge)
      if (kDebugMode) {
        final fbState = _uiFeedbackEngine!.state;
        if (fbState.blueMidi != null ||
            fbState.greenMidi != null ||
            fbState.redMidis.isNotEmpty) {
          // SESSION-058: Calculer la couleur résolue (gagnante) selon priorité
          final int? activeMidi =
              fbState.greenMidi ??
              (fbState.redMidis.isNotEmpty ? fbState.redMidis.first : null) ??
              fbState.blueMidi;
          final String resolved;
          if (fbState.greenMidi != null) {
            resolved = 'GREEN';
          } else if (fbState.redMidis.isNotEmpty) {
            resolved = 'RED';
          } else if (fbState.blueMidi != null) {
            resolved = 'BLUE';
          } else {
            resolved = 'NONE';
          }
          debugPrint(
            'S56_KEYBOARD blue=${fbState.blueMidi} green=${fbState.greenMidi} '
            'red=${fbState.redMidis} cyan=${fbState.cyanMidis} '
            'conf=${fbState.confidence.toStringAsFixed(2)} '
            'greenCount=${_uiFeedbackEngine!.greenCount} '
            'resolved=$resolved midi=$activeMidi',
          );
        }
      }
    } else {
      // S56 NOT READY: Clavier neutre (countdown, idle)
      keyColors = _computeNeutralKeyColors(targetNotes);
    }

    return PracticeKeyboard(
      key: const Key('practice_keyboard'),
      totalWidth: totalWidth,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      whiteHeight: whiteHeight,
      blackHeight: blackHeight,
      firstKey: _displayFirstKey,
      lastKey: _displayLastKey,
      blackKeys: _blackKeys,
      noteToXFn: noteToXFn,
      keyColors: keyColors,
      showDebugLabels: showDebugLabels,
      showMidiNumbers: showMidiNumbers,
    );
  }

  /// Génère une map de couleurs neutres pour le clavier (fallback)
  /// Utilisé pendant countdown, idle, ou quand S56 est désactivé
  Map<int, KeyVisualState> _computeNeutralKeyColors(Set<int> targetNotes) {
    final result = <int, KeyVisualState>{};
    for (int midi = _displayFirstKey; midi <= _displayLastKey; midi++) {
      final isBlack = _blackKeys.contains(midi % 12);
      if (targetNotes.contains(midi)) {
        result[midi] = KeyVisualState.cyan;
      } else {
        result[midi] = isBlack
            ? KeyVisualState.neutralBlack
            : KeyVisualState.neutralWhite;
      }
    }
    return result;
  }

  Widget _buildNotesStatus(double width) {
    if (_notesLoading) {
      return SizedBox(
        width: width,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_notesError != null) {
      return SizedBox(
        width: width,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _notesError!,
                style: AppTextStyles.caption.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacing8),
              TextButton(
                onPressed: () => _loadNoteEvents(sessionId: _practiceSessionId),
                child: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      );
    }
    if (_noteEvents.isEmpty) {
      return SizedBox(
        width: width,
        child: Center(
          child: Text('Aucune note disponible', style: AppTextStyles.caption),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
