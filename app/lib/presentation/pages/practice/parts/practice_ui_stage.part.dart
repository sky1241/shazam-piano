part of '../practice_page.dart';

/// Mixin for practice stage and keyboard UI widgets.
/// Extracted from _PracticePageState to reduce file size.
mixin _PracticeUiStageMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  Future<void> _loadNoteEvents({required int sessionId});
  double? _guidanceElapsedSec();
  Set<int> _uiTargetNotes({double? elapsedSec});
  bool _isSuccessFlashActive(DateTime now);
  bool _isWrongFlashActive(DateTime now);
  bool _isMissFlashActive(DateTime now);
  bool _isAnticipatedFlashActiveForUi(); // SESSION-036
  bool _isDetectedFlashActiveForUi(); // SESSION-036c
  Set<int> _getRecentlyHitNotes(DateTime now);
  int? _uiDetectedNote();
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

  // SESSION-036c/037: Mini debug overlay showing real-time detection info
  Widget _buildMiniDebugOverlay() {
    // Get values from MicEngine (if available)
    final expectedMidi = _micEngine?.onsetExpectedMidi;
    final detectedMidi = _detectedFlashMidi;
    final noteIdx = _micEngine?.onsetActiveNoteIdx;
    final inWindow = _micEngine?.onsetInActiveWindow ?? false;
    final conf = _detectedFlashConf;

    // SESSION-037: Get raw detection info
    final rawMidi = _micEngine?.lastRawMidi;
    final rawConf = _micEngine?.lastRawConf;
    final anticipated = _anticipatedFlashMidi;

    // Format display strings
    final expectedStr = expectedMidi != null ? '$expectedMidi' : '--';
    final detectedStr = detectedMidi != null ? '$detectedMidi' : '--';
    final rawStr = rawMidi != null ? '$rawMidi' : '--';
    final noteIdxStr = noteIdx != null ? '$noteIdx' : '--';
    final inWindowStr = inWindow ? 'Y' : 'N';
    final confStr = conf != null ? conf.toStringAsFixed(2) : '--';
    final rawConfStr = rawConf != null ? rawConf.toStringAsFixed(2) : '--';
    final antStr = anticipated != null ? '$anticipated' : '--';

    // SESSION-038: Add wrongFlash counters to debug overlay
    final emitStr = '$_wrongFlashEmitCount';
    final skipStr = '$_wrongFlashSkipGatedCount';
    final dupStr = '$_wrongFlashDuplicateAttackCount';
    final mismatchStr = '$_wrongFlashUiMismatchCount';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'exp:$expectedStr det:$detectedStr raw:$rawStr ant:$antStr | idx:$noteIdxStr win:$inWindowStr | conf:$confStr raw:$rawConfStr',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
          Text(
            'wf: emit:$emitStr skip:$skipStr dup:$dupStr mis:$mismatchStr',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 8,
              fontFamily: 'monospace',
            ),
          ),
        ],
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
    final now = DateTime.now();

    // ═══════════════════════════════════════════════════════════════════════════
    // SESSION-056: USE NEW PERCEPTIVE FEEDBACK ENGINE (if enabled)
    // Simple rules: BLEU=detection, CYAN=partition, VERT=success, ROUGE=error
    // ═══════════════════════════════════════════════════════════════════════════
    if (_useNewFeedbackEngine &&
        _uiFeedbackEngine != null &&
        _practiceRunning) {
      final fbState = _uiFeedbackEngine!.state;

      // BLEU = what mic detects (immediate)
      final blueMidi = fbState.blueMidi;
      final blueActive = blueMidi != null;

      // CYAN = what partition expects (always visible for active notes)
      // Already passed via targetNotes parameter

      // VERT = BLEU ∩ CYAN (pitch class match = success)
      final greenMidi = fbState.greenMidi;
      final greenActive = greenMidi != null;

      // ROUGE = BLEU without CYAN nearby (clear error)
      final redMidi = fbState.redMidi;
      final redActive = redMidi != null;

      // Log for debug (SESSION-056)
      if (kDebugMode && (blueActive || greenActive || redActive)) {
        debugPrint(
          'S56_KEYBOARD blue=$blueMidi green=$greenMidi red=$redMidi '
          'cyan=${fbState.cyanMidis} conf=${fbState.confidence.toStringAsFixed(2)} '
          'greenCount=${_uiFeedbackEngine!.greenCount}',
        );
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
        targetNotes: targetNotes,
        detectedNote: blueMidi, // BLEU = detected note
        // VERT = success (pitch class match)
        successFlashNote: greenMidi,
        successFlashActive: greenActive,
        // ROUGE = error (BLEU without CYAN)
        wrongFlashNote: redMidi,
        wrongFlashActive: redActive,
        // Disable old miss flash (not needed in S56)
        missFlashNote: null,
        missFlashActive: false,
        // CYAN = anticipated (partition) - use first cyan if multiple
        anticipatedFlashNote: fbState.cyanMidis.isNotEmpty
            ? fbState.cyanMidis.first
            : null,
        anticipatedFlashActive: fbState.cyanMidis.isNotEmpty,
        // BLEU = detected (already shown via detectedNote, but also flash)
        detectedFlashNote: blueMidi,
        detectedFlashActive: blueActive && !greenActive, // Hide blue if green
        noteToXFn: noteToXFn,
        showDebugLabels: showDebugLabels,
        showMidiNumbers: showMidiNumbers,
        recentlyHitNotes: const {}, // Not needed in S56
      );
    }
    // ═══════════════════════════════════════════════════════════════════════════
    // FALLBACK: Old complex logic (when S56 engine not active)
    // ═══════════════════════════════════════════════════════════════════════════

    final successFlashActive = _isSuccessFlashActive(now);
    final wrongFlashActive = _isWrongFlashActive(now);
    final missFlashActive = _isMissFlashActive(now); // FIX BUG SESSION-005 #4
    final anticipatedFlashActive =
        _isAnticipatedFlashActiveForUi(); // SESSION-036
    final detectedFlashActive = _isDetectedFlashActiveForUi(); // SESSION-036c
    final recentlyHitNotes = _getRecentlyHitNotes(
      now,
    ); // FIX: Get recently validated notes

    // ═══════════════════════════════════════════════════════════════════════════
    // SESSION-038: Unified keyboard state - prevent blue+red on different keys
    // If wrong flash is active on key A, and detected flash is on key B (A != B),
    // this is a UI mismatch that should not happen. Log and suppress blue.
    // ═══════════════════════════════════════════════════════════════════════════
    final bool hasMismatch =
        wrongFlashActive &&
        detectedFlashActive &&
        _lastWrongNote != null &&
        _detectedFlashMidi != null &&
        _lastWrongNote != _detectedFlashMidi;

    // If mismatch detected, suppress blue flash to only show red
    final effectiveDetectedFlashActive = hasMismatch
        ? false
        : detectedFlashActive;
    final effectiveDetectedFlashMidi = hasMismatch ? null : _detectedFlashMidi;

    // SESSION-038: Log mismatch and increment counter (should be rare/zero after fix)
    if (kDebugMode && hasMismatch) {
      _wrongFlashUiMismatchCount++;
      debugPrint(
        'WRONGFLASH_UI_MISMATCH blue=$_detectedFlashMidi red=$_lastWrongNote '
        'suppressing_blue=true reason=unified_state count=$_wrongFlashUiMismatchCount',
      );
    }

    // SESSION-033/036/036c/038: Log keyboard flash props for debugging
    if (kDebugMode &&
        (successFlashActive ||
            wrongFlashActive ||
            anticipatedFlashActive ||
            effectiveDetectedFlashActive)) {
      debugPrint(
        'KEYBOARD_UI_APPLY activeMidi=${wrongFlashActive ? _lastWrongNote : (effectiveDetectedFlashActive ? effectiveDetectedFlashMidi : _lastCorrectNote)} '
        'color=${wrongFlashActive ? "red" : (successFlashActive ? "green" : (effectiveDetectedFlashActive ? "blue" : "cyan"))} '
        'source=${wrongFlashActive ? "wrong" : (successFlashActive ? "hit" : (effectiveDetectedFlashActive ? "detected" : "anticipated"))} '
        'greenMidi=$_lastCorrectNote redMidi=$_lastWrongNote blueMidi=$effectiveDetectedFlashMidi '
        'keyRange=$_displayFirstKey-$_displayLastKey',
      );
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
      targetNotes: targetNotes,
      detectedNote: _uiDetectedNote(),
      // Flash the expected/target note (more consistent with falling overlay feedback).
      successFlashNote: _lastCorrectNote,
      successFlashActive: successFlashActive,
      wrongFlashNote: _lastWrongNote,
      wrongFlashActive: wrongFlashActive,
      missFlashNote: _lastMissNote, // FIX BUG SESSION-005 #4
      missFlashActive: missFlashActive, // FIX BUG SESSION-005 #4
      anticipatedFlashNote: _anticipatedFlashMidi, // SESSION-036: Zero-lag CYAN
      anticipatedFlashActive: anticipatedFlashActive, // SESSION-036
      // SESSION-038: Use effective values to prevent blue+red mismatch
      detectedFlashNote:
          effectiveDetectedFlashMidi, // SESSION-036c/038: Real-time BLUE (unified)
      detectedFlashActive: effectiveDetectedFlashActive, // SESSION-036c/038
      noteToXFn: noteToXFn,
      showDebugLabels: showDebugLabels,
      showMidiNumbers: showMidiNumbers,
      recentlyHitNotes:
          recentlyHitNotes, // FIX: Pass recently hit notes to prevent false reds
    );
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
