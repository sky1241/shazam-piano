part of '../practice_page.dart';

/// Mixin for practice lifecycle management.
/// Handles initState, dispose, app lifecycle, and practice start/stop flow.
mixin _PracticeLifecycleMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  String? _extractJobId(String url);
  Future<void> _refreshMicPermission();
  Future<void> _initVideo();
  Future<void> _loadNoteEvents({required int sessionId});
  Future<void> _loadSavedLatency();
  bool _canStartPractice();
  void _showVideoNotReadyHint();
  Future<bool> _tryStartMidi();
  bool _isSessionActive(int sessionId);
  Future<bool> _ensureMicPermission();
  void _setStopReason(String reason);
  void _setMicDisabled(bool disabled);
  // ignore: unused_element_parameter (force used in _PracticeMicDebugMixin)
  Future<void> _calibrateLatency({bool force = false});
  Future<void> _startPracticeVideo({Duration? startPosition});
  Future<void> _startMicStream();
  double? _guidanceElapsedSec();
  Future<void> _showScoreDialog({
    required double score,
    required double accuracy,
  });
  void _seedTestData();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final jobId = _extractJobId(widget.level.midiUrl);
    if (jobId != null) {
      DebugJobGuard.setCurrentJobId(jobId);
    }
    if (!_isTestEnv) {
      unawaited(_refreshMicPermission());
    }
    _ticker = createTicker((_) {
      final isPlaying = _videoController?.value.isPlaying ?? false;
      if (mounted && (_practiceRunning || isPlaying)) {
        setState(() {});
      }
    })..start();
    _keyboardScrollController.addListener(() {
      final next = _keyboardScrollController.offset;
      if (next == _keyboardScrollOffset) {
        return;
      }
      _keyboardScrollOffset = next;
      if (mounted) {
        setState(() {});
      }
    });
    if (_isTestEnv) {
      _seedTestData();
    } else {
      _initVideo();
      _loadNoteEvents(sessionId: _practiceSessionId);
      _loadSavedLatency();
      _maybeShowPracticeInterstitial();
    }
  }

  void _maybeShowPracticeInterstitial() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isTestEnv) {
        return;
      }
      AdmobInterstitialOnce.maybeShowPractice();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _practiceRunning) {
      _stopPractice(showSummary: false, reason: 'lifecycle_pause');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _keyboardScrollController.dispose();
    // FIX PASS2: Cancel subscription BEFORE stop to prevent AudioRecord -38
    _micSub?.cancel();
    _midiSub?.cancel();
    try {
      _recorder.stop();
    } catch (_) {}
    // End FIX PASS2
    // FIX BUG CRITIQUE #2: Cancel calibration beep before disposing player
    if (_isCalibrating) {
      try {
        _beepPlayer.stop();
      } catch (_) {}
      _isCalibrating = false;
    }
    _beepPlayer.dispose(); // FIX: Dispose AudioPlayer to prevent memory leak
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _togglePractice() async {
    final next = !_practiceRunning;
    if (next && !_canStartPractice()) {
      _showVideoNotReadyHint();
      return;
    }

    if (next) {
      // Reset state from any previous run
      await _resetPracticeSession();
      ++_practiceSessionId; // New session: invalidate old callbacks

      if (mounted) {
        setState(() {
          _practiceRunning = true;
          _practiceStarting = true; // Flag that startup is in progress
        });
      } else {
        _practiceRunning = true;
        _practiceStarting = true;
      }
      if (_videoController != null) {
        await _videoController!.pause();
      }
      // RACE FIX: Don't set countdown state here. Wait for notes/video to load in _startPractice()
      // _togglePractice just signals start-in-progress; actual countdown state set after await
      await _startPractice();
    } else {
      await _stopPractice(showSummary: true, reason: 'user_stop');
    }
  }

  /// Reset practice session completely for replay or stop
  Future<void> _resetPracticeSession() async {
    _practiceState = _PracticeState.idle;
    _practiceRunning = false;
    _practiceStarting = false;
    _countdownStartTime = null;
    _videoEndFired = false;
    _totalNotes = 0;
    _cumulativeSustainRatio = 0.0; // SUSTAIN SCORING: Reset for new session
    // BUG FIX #12: Use clear() instead of reassignment to maintain MicEngine reference
    _hitNotes.clear();
    _micEngine = null; // Recreate per-session after notes + hitNotes are ready
    _notesSourceLocked = false; // C2: Reset source lock for next session
    _notesLoadingSessionId = null; // C4: Reset load guard for next session
    _notesLoadedSessionId = null; // C4: Reset loaded flag for next session
    _stableVideoDurationSec =
        null; // C6: Reset stable duration for next session
    _lastSanitizedDurationSec = null; // C7: Reset sanitize epsilon guard
    _lastCorrectNote = null;
    _lastCorrectNoteIndex = null; // FIX BUG SESSION-005 #1+2
    _lastWrongNote = null;
    _lastMissNote = null; // FIX BUG SESSION-005 #4
    _lastMissHitAt = null; // FIX BUG SESSION-005 #4
    // SESSION-037: Reset detected flash state
    _detectedFlashMidi = null;
    _detectedFlashUntilMs = null;
    _detectedFlashFirstEmitMs = null;
    _lastPitchUpdateMs = -10000.0;
    _recentlyHitNotes
        .clear(); // FIX BUG P0: Clear recently hit notes for new session
    // Phase B instrumentation: Reset RMS stats for new session
    _micRmsMin = null;
    _micRmsMax = null;
    _micRmsSum = 0.0;
    _micSampleCount = 0;
    // SESSION-038: Reset wrongFlash health counters for new session
    _wrongFlashEmitCount = 0;
    _wrongFlashSkipGatedCount = 0;
    _wrongFlashDuplicateAttackCount = 0;
    _wrongFlashUiMismatchCount = 0;
    _wrongFlashHealthLastLogMs = -10000.0;
    _wrongFlashSessionStartMs = 0.0;
    if (_videoController != null && _videoController!.value.isInitialized) {
      await _videoController!.pause();
      await _videoController!.seekTo(Duration.zero);
    }
  }

  Future<void> _startPractice({Duration? startPosition}) async {
    // FIX BUG 4: Prevent instant replay after video end - require 2s delay
    if (_lastVideoEndAt != null) {
      final timeSinceEnd = DateTime.now()
          .difference(_lastVideoEndAt!)
          .inMilliseconds;
      if (timeSinceEnd < 2000) {
        return; // Ignore replay attempts within 2s of video end
      }
      _lastVideoEndAt = null; // Clear guard after delay passed
    }

    if (!_canStartPractice()) {
      _showVideoNotReadyHint();
      if (mounted) {
        setState(() {
          _practiceRunning = false;
          _isListening = false;
        });
      } else {
        _practiceRunning = false;
        _isListening = false;
      }
      return;
    }
    if (!_practiceRunning) {
      if (mounted) {
        setState(() {
          _practiceRunning = true;
        });
      } else {
        _practiceRunning = true;
      }
    }
    final sessionId = _practiceSessionId;
    _lastMicFrameAt = null;
    _micRms = 0.0;
    _micFrequency = null;
    _micNote = null;
    _micConfidence = 0.0;
    _lastMicLogAt = null;
    _lastMidiFrameAt = null;
    _lastMidiNote = null;
    _stopReason = null;
    _micRestartAttempts = 0;
    _micRestarting = false;
    _lastMicRestartAt = null;
    _lastUiUpdateAt = null;
    _videoEndFired = false;

    // NOTE: MicEngine will be initialized AFTER _loadNoteEvents to avoid race condition
    // (hitNotes must be synced with noteEvents length)
    _setMicDisabled(false);
    if (mounted) {
      setState(() {
        _isListening = false;
      });
    } else {
      _isListening = false;
    }

    // Try MIDI first
    _useMidi = await _tryStartMidi();
    if (!_isSessionActive(sessionId)) {
      return;
    }
    if (_useMidi) {
      if (mounted) {
        setState(() {
          _isListening = true;
        });
      } else {
        _isListening = true;
      }
    }

    if (!_useMidi) {
      final micGranted = await _ensureMicPermission();
      if (!_isSessionActive(sessionId)) {
        return;
      }
      if (!micGranted) {
        final status = _micPermissionStatus;
        final reason = status?.isPermanentlyDenied == true
            ? 'permission_permanently_denied'
            : 'permission_denied';
        _setStopReason(reason);
        _setMicDisabled(true);
      } else {
        _setMicDisabled(false);
        if (mounted) {
          setState(() {
            _isListening = true;
          });
        } else {
          _isListening = true;
        }
        // Auto calibrate silently (latency)
        if (_latencyMs == 0) {
          await _calibrateLatency();
        }
        if (_latencyMs == 0) {
          _latencyMs = _fallbackLatencyMs; // fallback if calibration failed
        }
        if (!_isSessionActive(sessionId)) {
          return;
        }
      }
    }

    // Fetch expected notes from backend
    await _loadNoteEvents(sessionId: sessionId);
    if (!_isSessionActive(sessionId)) {
      return;
    }
    // Compute effective lead-in based on loaded notes
    _computeEffectiveLeadIn();
    await _startPracticeVideo(startPosition: startPosition);
    if (!_isSessionActive(sessionId)) {
      return;
    }
    // RACE FIX: Arm countdown NOW that BOTH notes AND video are ready
    // Set state + timestamp TOGETHER to guarantee elapsedOk && notesOk both true for painter
    if (_practiceStarting && _countdownStartTime == null) {
      _spawnLogCount = 0; // D2: Reset log counter for new session
      if (mounted) {
        setState(() {
          _practiceState = _PracticeState.countdown;
          _countdownStartTime = DateTime.now();
          _practiceStarting = false; // Cleanup flag
        });
      } else {
        _practiceState = _PracticeState.countdown;
        _countdownStartTime = DateTime.now();
        _practiceStarting = false;
      }
      // C8: Log countdown timing to verify no chute compression
      // D2 FIX: During countdown, notes use effectiveLeadInSec for fall calculation
      // so ratio should be 1.00 (leadIn / leadIn) not (leadIn / fallLead)
      if (kDebugMode) {
        final leadIn = _effectiveLeadInSec;
        final effectiveFallDuringCountdown =
            _effectiveLeadInSec; // Notes actually use this
        final firstStart = _earliestNoteStartSec ?? 0;
        debugPrint(
          'Countdown C8: leadInSec=$leadIn fallLeadUsedInPainter=$effectiveFallDuringCountdown '
          'ratio=${(leadIn / effectiveFallDuringCountdown).toStringAsFixed(2)} '
          'earliestNoteStart=$firstStart synthAt_t0=-$effectiveFallDuringCountdown synthAt_tEnd=0',
        );
      }
    }
    _totalNotes = _noteEvents.length;
    // BUG FIX #12: Rebuild list in-place to maintain MicEngine reference
    _hitNotes.clear();
    _hitNotes.addAll(List<bool>.filled(_noteEvents.length, false));

    // FIX BUG #3 (CASCADE): Reset anti-spam au démarrage (defense in depth)
    _lastHitMidi = null;
    _lastHitAt = null;
    _lastHitOnsetMs = -10000.0; // SESSION-039: Reset onset tracker
    _lastWrongMidi = null;
    _lastWrongAt = null;

    // Initialize MicEngine NOW (after notes loaded, hitNotes synced)
    // Previously MicEngine was created before _hitNotes was populated, causing
    // SCORING_DESYNC ABORT and no hits / no key highlights.
    _micEngine = mic.MicEngine(
      noteEvents: _noteEvents
          .map((n) => mic.NoteEvent(start: n.start, end: n.end, pitch: n.pitch))
          .toList(),
      hitNotes: _hitNotes,
      detectPitch: (samples, sr) {
        // samples are already List<double>, no conversion needed
        final float32Samples = Float32List.fromList(samples);
        // FIX BUG 6: Use actual detected sample rate from MicEngine, not hardcoded constant
        // MicEngine calculates sr based on audio chunk timing (e.g., 32784 Hz on some devices)
        // Using wrong sr causes semitoneShift (e.g., 32784→44100 = -5.13 semitones = all notes wrong)
        final result = _pitchDetector.detectPitch(
          float32Samples,
          sampleRate: sr.round(),
        );
        return result ?? 0.0;
      },
      headWindowSec: _targetWindowHeadSec,
      tailWindowSec: _targetWindowTailSec,
      // FIX BUG #10 (CASCADE): Use _absMinRms variable instead of hardcoded 0.0020
      // Ensures single source of truth for RMS threshold (declared line 343)
      absMinRms: _absMinRms,
    );
    _micEngine!.reset('$sessionId');

    // ══════════════════════════════════════════════════════════════════════
    // SESSION 4: Initialize NEW scoring controller (parallel with old system)
    // ══════════════════════════════════════════════════════════════════════
    if (_useNewScoringSystem) {
      // Create controller with proper configuration
      final scoringConfig = ScoringConfig();
      final scoringEngine = PracticeScoringEngine(config: scoringConfig);

      // Use mic or MIDI pitch comparator
      final pitchComparator = _useMidi
          ? midiPitchComparator
          : micPitchComparator;
      final matcher = NoteMatcher(
        // CRITICAL: Must be >= ScoringEngine.okThresholdMs (450ms)
        // Previous: 300ms caused events at 300-450ms to be rejected
        windowMs: 450, // Matches MicEngine tailWindowSec
        pitchEquals: pitchComparator,
      );

      final debugConfig = DebugLogConfig(enableLogs: kDebugMode);
      final logger = PracticeDebugLogger(config: debugConfig);

      _newController = PracticeController(
        scoringEngine: scoringEngine,
        matcher: matcher,
        logger: logger,
      );

      // Convert _noteEvents to ExpectedNote format
      final expectedNotes = _noteEvents.asMap().entries.map((entry) {
        final duration = (entry.value.end - entry.value.start) * 1000.0;
        return ExpectedNote(
          index: entry.key,
          midi: entry.value.pitch,
          tExpectedMs: entry.value.start * 1000.0, // Convert sec to ms
          durationMs: duration > 0 ? duration : null, // Null if invalid
        );
      }).toList();

      // Start new scoring session
      _newController!.startPractice(
        sessionId: '$sessionId',
        expectedNotes: expectedNotes,
      );

      if (kDebugMode) {
        debugPrint(
          'SESSION4_CONTROLLER: Started with ${expectedNotes.length} notes, sessionId=$sessionId',
        );
      }
    }
    // ══════════════════════════════════════════════════════════════════════

    _lastCorrectHitAt = null;
    _lastCorrectNote = null;
    _lastCorrectNoteIndex = null; // FIX BUG SESSION-005 #1+2
    _successFlashUntil = null; // SESSION-034: Reset explicit expiry
    _lastWrongHitAt = null;
    _lastWrongNote = null;
    _wrongFlashUntil = null; // SESSION-034: Reset explicit expiry
    _lastMissHitAt = null; // FIX BUG SESSION-005 #4
    _lastMissNote = null; // FIX BUG SESSION-005 #4
    // SESSION-037: Reset detected flash state
    _detectedFlashMidi = null;
    _detectedFlashUntilMs = null;
    _detectedFlashFirstEmitMs = null;
    _lastPitchUpdateMs = -10000.0;
    // BUG FIX #15: Do NOT set _startTime here - it will be set when countdown finishes
    // If set here, clock advances during countdown and guidanceElapsed starts at 2s instead of 0
    // _startTime = DateTime.now(); // REMOVED

    if (_useMidi) {
      // Already listening via MIDI subscription
    } else if (!_micDisabled) {
      await _startMicStream();
    }
  }

  /// Compute effective lead-in to guarantee first note spawns at y≈0 when countdown starts.
  /// D1 FIX: Ensure countdown ratio = 1.0 (no velocity compression).
  /// Formula: effectiveLeadInSec = max(baseLeadIn, fallLead) to prevent chute compression.
  void _computeEffectiveLeadIn() {
    if (_noteEvents.isEmpty) {
      // FIX: ALWAYS use max(), not practiceLeadIn (would cause 1.5s countdown instead of 2.0s)
      _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
      _earliestNoteStartSec = null;
    } else {
      final minStart = _noteEvents.fold<double>(
        double.infinity,
        (min, note) => min < note.start ? min : note.start,
      );
      // Clamp to >= 0
      _earliestNoteStartSec = max(0.0, minStart);
      // D1: Ensure countdown ratio = 1.0 (no velocity > 1.0 compression)
      _effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec) + 1.0;
      if (kDebugMode) {
        debugPrint(
          'EFFECTIVE_LEADIN computed=${_effectiveLeadInSec.toStringAsFixed(3)}s (practiceLeadIn=$_practiceLeadInSec fallLead=$_fallLeadSec)',
        );
      }
    }
  }

  // FEATURE A: Monitor countdown and transition to running when time expires
  void _updateCountdown() {
    if (_practiceState != _PracticeState.countdown) {
      return;
    }
    if (_countdownStartTime == null) {
      return;
    }
    final elapsedMs = DateTime.now()
        .difference(_countdownStartTime!)
        .inMilliseconds;
    // BUG FIX: Use effectiveLeadInSec to prevent mid-screen note spawn
    final countdownCompleteSec = _effectiveLeadInSec;
    if (elapsedMs >= countdownCompleteSec * 1000) {
      // Countdown finished: start video + mic + enter running state
      // FIX BUG 5 REVISED: Set _startTime to NOW, _practiceClockSec handles latency subtraction
      // This ensures smooth transition: synthetic countdown ends at 0.0s, running starts at 0.0s
      // The latency compensation in _practiceClockSec() will naturally delay elapsed by ~100ms
      _startTime = DateTime.now();
      // Finalize noise baseline before transitioning to running
      // This uses the RMS samples collected during countdown to set dynamic thresholds
      _micEngine?.finalizeCountdownBaseline();

      if (kDebugMode) {
        final finalElapsed = _guidanceElapsedSec();
        final noiseFloor = _micEngine?.noiseFloorRms ?? 0.0;
        final dynamicThreshold = _micEngine?.dynamicOnsetMinRms ?? 0.0;
        debugPrint(
          'COUNTDOWN_FINISH elapsedMs=$elapsedMs countdownCompleteSec=$countdownCompleteSec '
          'finalElapsed=${finalElapsed?.toStringAsFixed(3)} latency=${_latencyMs.toStringAsFixed(1)}ms '
          'noiseFloor=${noiseFloor.toStringAsFixed(5)} dynamicThreshold=${dynamicThreshold.toStringAsFixed(5)} -> RUNNING',
        );
      }
      if (mounted) {
        setState(() {
          _practiceState = _PracticeState.running;
        });
      } else {
        _practiceState = _PracticeState.running;
      }
      _startPlayback();
    }
  }

  Future<void> _startPlayback() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.play();
    } catch (_) {}
    // Mic listening should already be set up in _startPractice()
  }

  Future<void> _stopPractice({
    bool showSummary = false,
    String reason = 'user_stop',
  }) async {
    _setStopReason(reason);

    // CASCADE FIX #B: Set _isListening false IMMEDIATELY to prevent delayed callbacks
    _isListening = false;
    _micDisabled = false;

    // BUG 2 FIX: Don't set _practiceRunning = false yet (causes Play flash)
    // Will be set AFTER score dialog closes

    // FIX PASS2: Cancel subscription BEFORE stop to prevent AudioRecord -38
    _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    // End FIX PASS2
    _midiSub?.cancel();
    _midiSub = null;
    await _videoController?.pause();
    _useMidi = false;
    _midiAvailable = false;
    final startedAtIso = _startTime?.toIso8601String();
    _startTime = null;
    final finishedAt = DateTime.now().toIso8601String();

    // FIX BUG 4 (DIALOG): Brancher sur nouveau système si actif
    // CASCADE FIX: Remove fallback total=1 to keep consistency with HUD (line 734)
    final int total = _totalNotes;

    // SESSION 4: Always use NEW scoring system (_useNewScoringSystem=true hard-coded)
    _newController!.stopPractice();
    final newState = _newController!.currentScoringState;
    final matched =
        newState.perfectCount + newState.goodCount + newState.okCount;
    final score = newState.totalScore.toDouble();
    // SUSTAIN SCORING: Use cumulative sustain ratio for precision
    // Each note contributes its sustainRatio (0.0-1.0) based on held duration
    final accuracy = total > 0
        ? (_cumulativeSustainRatio / total * 100.0)
        : 0.0;

    if (kDebugMode) {
      debugPrint(
        'SESSION4_CONTROLLER: Stopped. Final score=${newState.totalScore}, combo=${newState.combo}, p95=${newState.timingP95AbsMs.toStringAsFixed(1)}ms',
      );
      debugPrint(
        'SESSION4_FINAL: perfect=${newState.perfectCount} good=${newState.goodCount} ok=${newState.okCount} miss=${newState.missCount} wrong=${newState.wrongCount}',
      );
      // SESSION-038: Log wrongFlash UI summary at end of session
      // Use monotonic _wrongFlashHealthLastLogMs as duration proxy (safer than DateTime.parse)
      final sessionDurationMs = _wrongFlashHealthLastLogMs > 0
          ? _wrongFlashHealthLastLogMs.toInt()
          : 0;
      debugPrint(
        'WRONGFLASH_SUMMARY session=$_practiceSessionId '
        'emits=$_wrongFlashEmitCount '
        'skipGated=$_wrongFlashSkipGatedCount '
        'dup=$_wrongFlashDuplicateAttackCount '
        'mismatch=$_wrongFlashUiMismatchCount '
        'durationMs=$sessionDurationMs',
      );
      // SESSION-038: Also log MicEngine counters for comparison
      _micEngine?.logEngineSummary();
    }

    await _sendPracticeSession(
      score: score,
      accuracy: accuracy,
      notesTotal: total,
      notesCorrect:
          matched, // P0 fix: Send NEW system matched count (not OLD _correctNotes=0)
      startedAt: startedAtIso ?? finishedAt,
      endedAt: finishedAt,
    );

    // FIX CASCADE CRITIQUE: Set flags AVANT setState pour bloquer callbacks
    _practiceRunning = false;
    _isListening = false;

    setState(() {
      _detectedNote = null;
      _lastMicFrameAt = null;
      _micRms = 0.0;
      _micFrequency = null;
      _micNote = null;
      _micConfidence = 0.0;
      _micScoringOffsetSec = 0.0; // D1: Reset offset for new session
      _lastMidiFrameAt = null;
      _lastMidiNote = null;
      _lastCorrectHitAt = null;
      _lastCorrectNote = null;
      _lastCorrectNoteIndex = null; // FIX BUG SESSION-005 #1+2
      _successFlashUntil = null; // SESSION-034: Reset explicit expiry
      _lastWrongHitAt = null;
      _lastWrongNote = null;
      _wrongFlashUntil = null; // SESSION-034: Reset explicit expiry
      _lastMissHitAt = null; // FIX BUG SESSION-005 #4
      _lastMissNote = null; // FIX BUG SESSION-005 #4
      // SESSION-037: Reset detected flash state
      _detectedFlashMidi = null;
      _detectedFlashUntilMs = null;
      _detectedFlashConf = null;
      _detectedFlashFirstEmitMs = null;
      _lastPitchUpdateMs = -10000.0;
      // D1, D3: Reset mic config logging and latency comp for new session
      _micConfigLogged = false;
      _micLatencyCompSec = 0.0;
      // FIX BUG #3 (CASCADE): Reset anti-spam entre sessions
      _lastHitMidi = null;
      _lastHitAt = null;
      _lastHitOnsetMs = -10000.0; // SESSION-039: Reset onset tracker
      _lastWrongMidi = null;
      _lastWrongAt = null;
    });

    // FIX BUG 2: Await score dialog to prevent screen returning to Play immediately
    // Before: async call continued, UI returned to idle while dialog was opening
    // After: Wait for dialog close before marking video end
    // FIX BUG #7 (CASCADE): Duplication stopPractice supprimée (déjà appelé dans branchement dialog ci-dessus)

    // CASCADE FIX #2: Wrap in try-finally to prevent state lock if dialog crashes
    try {
      if (showSummary && mounted) {
        await _showScoreDialog(score: score, accuracy: accuracy);
      }
    } catch (e) {
      debugPrint('Score dialog error: $e');
    } finally {
      // BUG 2 FIX: NOW set _practiceRunning = false AFTER dialog closed (or if error)
      if (mounted) {
        setState(() {
          _practiceRunning = false;
          _isListening = false;
          _micDisabled = false;
          // Clear all overlay/highlight state on stop
          _detectedNote = null;
          _accuracy = NoteAccuracy.miss;
          _practiceState = _PracticeState.idle;
          _countdownStartTime = null;
        });
      } else {
        _practiceRunning = false;
        _isListening = false;
        _micDisabled = false;
        _detectedNote = null;
        _accuracy = NoteAccuracy.miss;
        _practiceState = _PracticeState.idle;
        _countdownStartTime = null;
      }
    }

    // FIX BUG 4: Mark video end time to prevent instant replay
    _lastVideoEndAt = DateTime.now();
  }

  Future<void> _sendPracticeSession({
    required double score,
    required double accuracy,
    required int notesTotal,
    required int notesCorrect,
    String? startedAt,
    String? endedAt,
  }) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final jobId = _extractJobId(widget.level.midiUrl);

      final dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.backendBaseUrl,
          connectTimeout: const Duration(
            seconds: 15,
          ), // SYNC: uniform API timeout
        ),
      );
      DebugJobGuard.attachToDio(dio);
      dio.options.headers['Authorization'] = 'Bearer $token';

      await dio.post(
        '/practice/session',
        data: {
          'job_id': jobId ?? widget.level.videoUrl,
          'level': widget.level.level,
          'score': score,
          'accuracy': accuracy,
          'notes_total': notesTotal,
          'notes_correct': notesCorrect,
          'notes_missed': notesTotal - notesCorrect,
          'started_at': startedAt,
          'ended_at': endedAt,
          'app_version': 'mobile',
        },
      );
    } catch (_) {
      // ignore errors for now in UI; backend will log if it receives request
    }
  }
}
