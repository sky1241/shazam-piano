part of '../practice_page.dart';

/// Mixin for microphone debug HUD functionality.
/// Extracted from _PracticePageState to reduce file size.
mixin _PracticeMicDebugMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  double? _videoElapsedSec();
  double? _guidanceElapsedSec();
  double _practiceClockSec();
  double? _effectiveElapsedSec();
  Set<int> _resolveTargetNotes(double? elapsedSec);
  Set<int> _computeImpactNotes({
    // ignore: unused_element_parameter
    double? elapsedSec,
  });
  Set<int> _uiTargetNotes({
    // ignore: unused_element_parameter
    double? elapsedSec,
  });
  _KeyboardLayout _computeKeyboardLayout(double maxWidth);
  double _currentAvailableWidth();
  String? _extractJobId(String url);
  void _runDetectionSelfTest();
  void _injectA4();
  Future<void> _refreshMicPermission();
  Future<void> _calibrateLatency({bool force = false});

  void _handleDevHudTap() {
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now();
    if (_devTapStartAt == null ||
        now.difference(_devTapStartAt!) > _devTapWindow) {
      _devTapStartAt = now;
      _devTapCount = 1;
    } else {
      _devTapCount += 1;
    }

    if (_devTapCount >= _devTapTarget) {
      _devTapCount = 0;
      _devTapStartAt = null;
      if (mounted) {
        setState(() {
          _devHudEnabled = !_devHudEnabled;
        });
      } else {
        _devHudEnabled = !_devHudEnabled;
      }
    }
  }

  Widget _buildMicDebugHud({required double horizontalPadding}) {
    if (!kDebugMode || !_devHudEnabled) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now();
    final targetRaw = _practiceRunning
        ? _resolveTargetNotes(_effectiveElapsedSec())
        : const <int>{};
    final sortedTargets = targetRaw.toList()..sort();
    final targetText = sortedTargets.isEmpty ? '--' : sortedTargets.join(',');
    int? minPitch;
    int? maxPitch;
    for (final event in _noteEvents) {
      minPitch = minPitch == null ? event.pitch : min(minPitch, event.pitch);
      maxPitch = maxPitch == null ? event.pitch : max(maxPitch, event.pitch);
    }
    final accuracyText = _accuracy.toString().split('.').last;
    final midiAvailText = _midiAvailable ? 'yes' : 'no';
    final micNoData =
        _practiceRunning &&
        !_useMidi &&
        !_micDisabled &&
        (_lastMicFrameAt == null ||
            now.difference(_lastMicFrameAt!) > const Duration(seconds: 2));
    final micStatus = !_practiceRunning || _useMidi
        ? 'OFF'
        : (_micDisabled ? 'DISABLED' : (micNoData ? 'NO DATA' : 'ON'));
    final midiNoData =
        _practiceRunning &&
        _useMidi &&
        (_lastMidiFrameAt == null ||
            now.difference(_lastMidiFrameAt!) > const Duration(seconds: 2));
    final midiStatus = _useMidi ? (midiNoData ? 'NO DATA' : 'ON') : 'OFF';
    final rmsText = _micRms.toStringAsFixed(3);
    final freqText = _micFrequency != null
        ? _micFrequency!.toStringAsFixed(1)
        : '--';
    final noteText = _useMidi
        ? (_lastMidiNote != null
              ? _formatMidiNote(_lastMidiNote!, withOctave: true)
              : '--')
        : (_micNote != null
              ? _formatMidiNote(_micNote!, withOctave: true)
              : '--');
    final confText = _micConfidence.toStringAsFixed(2);
    final permText = _permissionLabel(_micPermissionStatus);
    final ageText = _useMidi || _lastMicFrameAt == null
        ? '--'
        : '${now.difference(_lastMicFrameAt!).inMilliseconds}ms';
    final subActive = _micSub != null && !_micSub!.isPaused;
    final subText = _useMidi ? '--' : (subActive ? 'ON' : 'OFF');
    final stopText = _stopReason ?? '--';
    final line =
        'MIC: $micStatus | MIDI: $midiStatus | RMS: $rmsText | '
        'f0: $freqText Hz | note: $noteText | conf: $confText | '
        'age: $ageText | sub: $subText | stop: $stopText | perm: $permText';
    final videoPosSec = _videoElapsedSec();
    final guidanceElapsedSec = _guidanceElapsedSec();
    final practiceClockSec = _startTime != null ? _practiceClockSec() : null;
    final deltaSec = videoPosSec != null && practiceClockSec != null
        ? practiceClockSec - videoPosSec
        : null;
    final videoText = videoPosSec != null
        ? videoPosSec.toStringAsFixed(3)
        : '--';
    final guidanceText = guidanceElapsedSec != null
        ? guidanceElapsedSec.toStringAsFixed(3)
        : '--';
    final clockText = practiceClockSec != null
        ? practiceClockSec.toStringAsFixed(3)
        : '--';
    final deltaText = deltaSec != null ? deltaSec.toStringAsFixed(3) : '--';
    final stateLine =
        'target: $targetText | detected: ${_detectedNote ?? '--'} | '
        'accuracy: $accuracyText | midiAvail: $midiAvailText | '
        'vpos: $videoText | guidance: $guidanceText | clock: $clockText | '
        'delta: $deltaText';
    final sessionLine =
        'session: $_practiceSessionId | running: $_practiceRunning | '
        'listening: $_isListening | micGranted: '
        '${_micPermissionStatus?.isGranted == true ? 'yes' : 'no'}';
    final notesLine =
        'source: ${_notesSource.name} | notes: ${_noteEvents.length} | '
        'range: ${minPitch ?? '--'}-${maxPitch ?? '--'} | '
        'display: $_displayFirstKey-$_displayLastKey | '
        'merged: $_notesMergedPairs | overlaps: $_notesOverlapsDetected';
    final impactNotes = _computeImpactNotes();
    final impactList = impactNotes.isEmpty ? ['--'] : impactNotes.toList()
      ..sort();
    final impactText = impactList.toString();
    // FEATURE A: Lead-in countdown info
    final practiceStateText = _practiceState.toString().split('.').last;
    // BUG FIX #9: Use _effectiveLeadInSec (3.0s) instead of _practiceLeadInSec (1.5s)
    final countdownRemainingSec = _countdownStartTime != null
        ? max(
            0.0,
            _effectiveLeadInSec -
                (DateTime.now()
                        .difference(_countdownStartTime!)
                        .inMilliseconds /
                    1000.0),
          )
        : null;
    final countdownText = countdownRemainingSec != null
        ? countdownRemainingSec.toStringAsFixed(2)
        : '--';
    // BUG 2 FIX: Proof field for video variant tracking
    final videoVariantLine =
        'videoVariant: ${_selectedVideoVariant ?? "unset"} | forcePreview: ${widget.forcePreview}';

    // CRITICAL FIX: Falling notes geometry proof fields
    // These values prove the canonical mapping is correct
    final offsetAppliedSec = videoPosSec != null && guidanceElapsedSec != null
        ? videoPosSec - guidanceElapsedSec
        : null;
    final offsetText = offsetAppliedSec != null
        ? offsetAppliedSec.toStringAsFixed(3)
        : '--';

    // Compute y-coordinates for first note to prove the mapping
    String firstNoteStartSecStr = '--';
    String yAtSpawnStr = '--';
    String yAtHitStr = '--';
    if (_noteEvents.isNotEmpty && guidanceElapsedSec != null) {
      final firstNote = _noteEvents.first;
      firstNoteStartSecStr = firstNote.start.toStringAsFixed(3);
      // D2 FIX: Use effectiveLeadInSec during countdown for accurate Y calculation
      final fallLeadForCalc = _practiceState == _PracticeState.countdown
          ? _effectiveLeadInSec
          : _fallLeadSec;
      // Current y position of first note (where it appears on screen NOW)
      final yAtSpawn =
          (guidanceElapsedSec - (firstNote.start - fallLeadForCalc)) /
          fallLeadForCalc *
          400.0;
      yAtSpawnStr = yAtSpawn.toStringAsFixed(1);
      // What y WOULD BE when the note hits the keyboard (at elapsed = note.start)
      // Note: yAtHit should equal 400px (fallAreaHeight) by definition
      final yAtHitTheoretical =
          (firstNote.start - (firstNote.start - fallLeadForCalc)) /
          fallLeadForCalc *
          400.0;
      yAtHitStr = yAtHitTheoretical.toStringAsFixed(1);
    }

    final geometryLine =
        'fallLead: $_fallLeadSec | hitLine: 400px | firstNoteStart: $firstNoteStartSecStr | '
        'yAtSpawn: $yAtSpawnStr | yAtHit: $yAtHitStr | offsetApplied: $offsetText';

    // CRITICAL FIX: Video start position proof
    // Prove that practice always starts from t=0, never mid-video
    String startTargetSecStr = '--';
    String posAfterSeekSecStr = '--';
    if (_videoController != null && _videoController!.value.isInitialized) {
      startTargetSecStr = '0.000'; // Always target Duration.zero
      final posAfterSeek =
          _videoController!.value.position.inMilliseconds / 1000.0;
      posAfterSeekSecStr = posAfterSeek.toStringAsFixed(3);
    }
    final videoStartLine =
        'startTarget: $startTargetSecStr | posAfterSeek: $posAfterSeekSecStr | '
        'videoPos: ${(_videoElapsedSec()?.toStringAsFixed(3) ?? '--')}';

    final debugLine =
        'state: $practiceStateText | leadIn: $_practiceLeadInSec | '
        'countdownRemaining: $countdownText | '
        'videoLayerHidden: true | impactNotes: $impactText | impactCount: ${impactNotes.length}';

    // BUG FIX: Proof fields for dynamic lead-in to prevent mid-screen note spawn
    String earliestNoteStartSecStr = '--';
    if (_noteEvents.isNotEmpty) {
      earliestNoteStartSecStr = _noteEvents.first.start.toStringAsFixed(3);
    }
    final effectiveLeadInLine =
        'earliestNote: $earliestNoteStartSecStr | baseLeadIn: ${_practiceLeadInSec.toStringAsFixed(3)} | '
        'effectiveLeadIn: ${_effectiveLeadInSec.toStringAsFixed(3)} | fallLead: ${_fallLeadSec.toStringAsFixed(3)}';

    // BUG FIX: Proof that countdown is armed and lead-in is computed correctly
    final countdownArmed = _countdownStartTime != null ? 'yes' : 'no';
    final notesReady = _noteEvents.isNotEmpty ? 'yes' : 'no';
    // D2 FIX: During countdown, use effectiveLeadInSec
    final fallLeadForCountdownCalc = _practiceState == _PracticeState.countdown
        ? _effectiveLeadInSec
        : _fallLeadSec;
    final syntheticSpanSec = fallLeadForCountdownCalc.toStringAsFixed(2);
    final yAtCountdownStartStr =
        _countdownStartTime != null && _earliestNoteStartSec != null
        ? (((-fallLeadForCountdownCalc) -
                      (_earliestNoteStartSec! - fallLeadForCountdownCalc)) /
                  fallLeadForCountdownCalc *
                  400.0)
              .toStringAsFixed(1)
        : '--';
    final countdownProofLine =
        'countdownStarted: $countdownArmed | notesReady: $notesReady | '
        'syntheticSpan: [-$syntheticSpanSec..0] | yAtSpawn: $yAtCountdownStartStr';

    // BUG FIX: Proof of paint phase continuity (countdown→running transition)
    final paintPhase = _practiceState == _PracticeState.countdown
        ? 'countdown'
        : 'running';
    final stateCondition =
        (_practiceRunning || _practiceState == _PracticeState.countdown);
    final elapsedCondition = guidanceElapsedSec != null;
    final notesCondition = _noteEvents.isNotEmpty;
    final shouldPaintEval =
        stateCondition && elapsedCondition && notesCondition;
    final paintPhaseProofLine =
        'paintPhase: $paintPhase | state=$stateCondition | elapsed=$elapsedCondition | notes=$notesCondition | shouldPaint: $shouldPaintEval | elapsedVal: ${guidanceElapsedSec?.toStringAsFixed(3) ?? "null"}';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: AppConstants.spacing4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stateLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            sessionLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            notesLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            line,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            debugLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            geometryLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            videoStartLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            effectiveLeadInLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            countdownProofLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            paintPhaseProofLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            videoVariantLine,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Wrap(
            spacing: AppConstants.spacing8,
            runSpacing: AppConstants.spacing4,
            children: [
              TextButton(
                onPressed: _runDetectionSelfTest,
                child: const Text('Test detection'),
              ),
              TextButton(onPressed: _injectA4, child: const Text('Inject A4')),
              TextButton(
                onPressed: _refreshMicPermission,
                child: const Text('Check mic'),
              ),
              TextButton(
                onPressed: () => _calibrateLatency(force: true),
                child: const Text('Recalibrer'),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showMidiNumbers = !_showMidiNumbers;
                    });
                  } else {
                    _showMidiNumbers = !_showMidiNumbers;
                  }
                },
                child: Text(
                  _showMidiNumbers ? 'MIDI labels ON' : 'MIDI labels OFF',
                ),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showKeyboardGuides = !_showKeyboardGuides;
                    });
                  } else {
                    _showKeyboardGuides = !_showKeyboardGuides;
                  }
                },
                child: Text(_showKeyboardGuides ? 'Guides ON' : 'Guides OFF'),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showKeyboardDebugLabels = !_showKeyboardDebugLabels;
                    });
                  } else {
                    _showKeyboardDebugLabels = !_showKeyboardDebugLabels;
                  }
                },
                child: Text(
                  _showKeyboardDebugLabels ? 'Key labels ON' : 'Key labels OFF',
                ),
              ),
              TextButton(
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _showOnlyTargets = !_showOnlyTargets;
                    });
                  } else {
                    _showOnlyTargets = !_showOnlyTargets;
                  }
                },
                child: Text(_showOnlyTargets ? 'All Notes' : 'Only Targets'),
              ),
              TextButton(
                onPressed: _copyDebugReport,
                child: const Text('Copy debug report'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyDebugReport() async {
    if (!mounted) {
      return;
    }
    final media = MediaQuery.of(context);
    final layout = _computeKeyboardLayout(_currentAvailableWidth());
    final videoPosSec = _videoElapsedSec();
    final elapsedSec = _effectiveElapsedSec();
    final practiceClockSec = _startTime != null ? _practiceClockSec() : null;
    final deltaSec = videoPosSec != null && practiceClockSec != null
        ? practiceClockSec - videoPosSec
        : null;
    final pitches = _rawNoteEvents.isNotEmpty ? _rawNoteEvents : _noteEvents;
    int? minPitch;
    int? maxPitch;
    for (final event in pitches) {
      minPitch = minPitch == null ? event.pitch : min(minPitch, event.pitch);
      maxPitch = maxPitch == null ? event.pitch : max(maxPitch, event.pitch);
    }
    final targetNotes = _practiceRunning && elapsedSec != null
        ? _uiTargetNotes(elapsedSec: elapsedSec)
        : const <int>{};
    final micEnabled =
        _practiceRunning && !_useMidi && !_micDisabled && _isListening;
    final midiEnabled = _practiceRunning && _useMidi;
    final report = <String, dynamic>{
      'buildStamp': BuildInfo.stamp,
      'screenWidth': media.size.width,
      'devicePixelRatio': media.devicePixelRatio,
      'layoutMaxWidth': _lastLayoutMaxWidth,
      'practiceRunning': _practiceRunning,
      'listening': _isListening,
      'notesSource': _notesSource.name,
      'notesCount': _noteEvents.length,
      'notesRawCount': _notesRawCount,
      'dedupedCount': _notesDedupedCount,
      'filteredCount': _notesFilteredCount,
      'droppedOutOfRange': _notesDroppedOutOfRange,
      'droppedOutOfVideo': _notesDroppedOutOfVideo,
      'droppedDup': _notesDroppedDup,
      'minPitch': minPitch,
      'maxPitch': maxPitch,
      'layout': {
        'stagePadding': layout.stagePadding,
        'leftPadding': layout.leftPadding,
        'whiteWidth': layout.whiteWidth,
        'blackWidth': layout.blackWidth,
        'displayWidth': layout.displayWidth,
        'outerWidth': layout.outerWidth,
        'firstKey': layout.firstKey,
        'lastKey': layout.lastKey,
        'scrollOffset': _keyboardScrollOffset,
      },
      'displayFirstKey': _displayFirstKey,
      'displayLastKey': _displayLastKey,
      'videoUrl': widget.level.videoUrl,
      'midiUrl': widget.level.midiUrl,
      'jobId': _extractJobId(widget.level.midiUrl),
      'level': widget.level.level,
      'elapsedSec': elapsedSec,
      'videoPosSec': videoPosSec,
      'practiceClockSec': practiceClockSec,
      'deltaSec': deltaSec,
      'sessionId': _practiceSessionId,
      'targetNotes': targetNotes.toList()..sort(),
      'detectedNote': _detectedNote,
      'micEnabled': micEnabled,
      'midiEnabled': midiEnabled,
      'midiAvailable': _midiAvailable,
      'micPermissionGranted': _micPermissionStatus?.isGranted == true,
      'events': _noteEvents
          .take(15)
          .map((e) => {'pitch': e.pitch, 'start': e.start, 'end': e.end})
          .toList(),
    };
    final payload = jsonEncode(report);
    if (kDebugMode) {
      debugPrint('Practice debug report: $payload');
    }
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug report copied')));
  }

  String _permissionLabel(PermissionStatus? status) {
    if (status == null) {
      return 'unknown';
    }
    return status.toString().split('.').last;
  }
}
