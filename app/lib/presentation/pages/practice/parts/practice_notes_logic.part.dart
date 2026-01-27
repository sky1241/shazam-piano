part of '../practice_page.dart';

/// Mixin for note processing, scoring, and hit/miss detection.
/// Extracted from _PracticePageState to reduce file size.
mixin _PracticeNotesLogicMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  double? _guidanceElapsedSec();
  bool _isSessionActive(int sessionId);
  void _logMicDebug(DateTime now);

  void _processSamples(
    List<double> samples, {
    required DateTime now,
    bool injected = false,
    int? sessionId,
  }) {
    // C3: Session gate - skip if sessionId mismatch (stale callback)
    if (sessionId != null && !_isSessionActive(sessionId)) {
      return;
    }
    if (_startTime == null && !injected) return;
    // D1: Disable mic during countdown (anti-pollution: avoid capturing app's reference note)
    if (_practiceState == _PracticeState.countdown) {
      return;
    }

    // FIX CASCADE: Update timestamp APRÈS guards (consistent pattern)
    _lastMicFrameAt = now;

    // ═══════════════════════════════════════════════════════════════
    // CRITICAL: MicEngine scoring (all gating + buffering internal)
    // ═══════════════════════════════════════════════════════════════
    final elapsed = _guidanceElapsedSec();
    if (elapsed != null && _micEngine != null) {
      final prevAccuracy = _accuracy;
      final elapsedMs = elapsed * 1000.0;
      final decisions = _micEngine!.onAudioChunk(samples, now, elapsedMs);

      // FIX CASCADE CRITIQUE: Update mic state IMMEDIATELY après onAudioChunk
      // (decisions loop utilise _micRms/_micConfidence pour gating)
      _micFrequency = _micEngine!.lastFreqHz;
      _micNote = _micEngine!.lastMidi;
      _micConfidence = _micEngine!.lastConfidence ?? 0.0;
      _micRms = _micEngine!.lastRms ?? 0.0;

      // Phase B instrumentation: Accumulate RMS stats
      if (_micRms > 0) {
        _micRmsMin = (_micRmsMin == null) ? _micRms : min(_micRmsMin!, _micRms);
        _micRmsMax = (_micRmsMax == null) ? _micRms : max(_micRmsMax!, _micRms);
        _micRmsSum += _micRms;
        _micSampleCount++;
      }

      // ═══════════════════════════════════════════════════════════════
      // SESSION-036: Anticipated flash - onset-first zero-lag feedback
      // ═══════════════════════════════════════════════════════════════
      // 1) Check timeout first (before processing new onset)
      _checkAnticipatedTimeout(elapsedMs);

      // 2) Check if noteIdx changed (cancel stale anticipated flash)
      _checkAnticipatedNoteIdxChange(_micEngine!.onsetActiveNoteIdx);

      // 3) Process onset trigger for anticipated flash
      _processOnsetForAnticipatedFlash(elapsedMs);
      // ═══════════════════════════════════════════════════════════════

      // ═══════════════════════════════════════════════════════════════
      // SESSION-036c: Detected note flash (BLUE) - "REAL-TIME FEEL"
      // Update detected flash from MicEngine's last detected pitch
      // This shows what the mic heard, independent of scoring
      // ═══════════════════════════════════════════════════════════════
      _updateDetectedFlash(elapsedMs);
      // ═══════════════════════════════════════════════════════════════

      // Apply decisions (HIT/MISS/wrongFlash)
      for (final decision in decisions) {
        switch (decision.type) {
          case mic.DecisionType.hit:
            // ═══════════════════════════════════════════════════════════════
            // SESSION 4: Send played note event to NEW controller
            // ═══════════════════════════════════════════════════════════════
            if (_useNewScoringSystem &&
                _newController != null &&
                decision.detectedMidi != null) {
              // Anti-spam check (avoid duplicate hits)
              if (_lastHitMidi == decision.detectedMidi &&
                  _lastHitAt != null &&
                  now.difference(_lastHitAt!).inMilliseconds < _antiSpamHitMs) {
                break;
              }

              _lastHitMidi = decision.detectedMidi;
              _lastHitAt = now;

              final playedEvent = PracticeController.createPlayedEvent(
                midi: decision.detectedMidi!,
                tPlayedMs: elapsed * 1000.0, // Convert sec to ms
                source: NoteSource.microphone,
              );

              // BRIDGE: OLD system validated HIT, force match in NEW controller
              // Pass dtSec from MicEngine (calculated in its window context)
              _newController!.onPlayedNote(
                playedEvent,
                forceMatchExpectedIndex: decision.noteIndex,
                micEngineDtMs: decision.dtSec! * 1000.0, // Use MicEngine's dt
              );

              // SUSTAIN SCORING: Accumulate sustain ratio for precision calculation
              _cumulativeSustainRatio += decision.sustainRatio;

              // SESSION-036: Confirm anticipated flash as success (if active on this noteIdx)
              if (_anticipatedFlashNoteIdx == decision.noteIndex) {
                _confirmAnticipatedAsSuccess(
                  noteIdx: decision.noteIndex!,
                  midi: decision.detectedMidi!,
                  dtMs: (decision.dtSec ?? 0) * 1000.0,
                  nowMs: elapsedMs,
                );
              }

              // Flash green (forceMatch guarantees hit registered)
              // FIX BUG SESSION-005 #1+2: Pass noteIndex for unique flash targeting
              _registerCorrectHit(
                targetNote: decision.expectedMidi!,
                detectedNote: decision.detectedMidi!,
                now: now,
                noteIndex: decision.noteIndex,
              );
              setState(() {}); // Rebuild HUD
            }

            _accuracy = NoteAccuracy.correct;
            _updateDetectedNote(
              decision.detectedMidi,
              now,
              accuracyChanged: true,
            );
            // ═══════════════════════════════════════════════════════════════
            break;

          case mic.DecisionType.miss:
            if (_accuracy != NoteAccuracy.correct) {
              _accuracy = NoteAccuracy.wrong;
            }
            // FIX BUG SESSION-007 #2: REMOVED red keyboard flash for missed notes
            // Miss = note NOT played → keyboard should stay BLACK (no feedback)
            // Keyboard reflects only PLAYED notes, not expected unplayed notes
            // Previous behavior incorrectly showed red for notes user didn't play
            break;

          case mic.DecisionType.wrongFlash:
            // ═══════════════════════════════════════════════════════════════
            // SESSION 4: Send wrong note to NEW controller
            // ═══════════════════════════════════════════════════════════════
            // SESSION-032 FIX: Add UI-level log to trace wrongFlash decision processing
            // PREUVE session-032: WRONG_FLASH_EMIT logged in MicEngine but no UI log
            // to confirm decision was received → added WRONGFLASH_UI_RECEIVED
            if (kDebugMode) {
              debugPrint(
                'WRONGFLASH_UI_RECEIVED midi=${decision.detectedMidi} '
                'noteIdx=${decision.noteIndex} conf=${decision.confidence?.toStringAsFixed(2)} '
                'hasController=${_newController != null} useNew=$_useNewScoringSystem',
              );
            }

            // SESSION-032 FIX: Red flash trigger moved OUTSIDE scoring system guard
            // CAUSE: At session start, wrongFlash decisions were received but
            // _registerWrongHit was ONLY called inside the guard block.
            // PREUVE: logcat shows NO_EVENTS_FALLBACK_USED but no red flash visible
            // NOW: Red flash triggered for ANY wrongFlash decision with valid midi
            if (decision.detectedMidi != null) {
              // FIX BUG #1 SUSTAIN: Skip if same MIDI as recent hit (<500ms)
              // Cause: MicEngine génère wrongFlash sur sustain trop court
              if (_lastHitMidi == decision.detectedMidi &&
                  _lastHitAt != null &&
                  now.difference(_lastHitAt!).inMilliseconds < 500) {
                if (kDebugMode) {
                  debugPrint(
                    'SESSION4_SKIP_SUSTAIN_WRONG: Skip wrongFlash midi=${decision.detectedMidi} (same as recent hit, dt=${now.difference(_lastHitAt!).inMilliseconds}ms)',
                  );
                }
                // Skip red flash AND scoring, decision already handled
                break;
              }

              // Anti-spam check (avoid duplicate wrongs)
              if (_lastWrongMidi == decision.detectedMidi &&
                  _lastWrongAt != null &&
                  now.difference(_lastWrongAt!).inMilliseconds <
                      _antiSpamWrongMs) {
                if (kDebugMode) {
                  debugPrint(
                    'SESSION4_ANTISPAM_WRONG: Skip duplicate midi=${decision.detectedMidi} (< ${_antiSpamWrongMs}ms)',
                  );
                }
                break;
              }

              _lastWrongMidi = decision.detectedMidi;
              _lastWrongAt = now;

              // SESSION-036: Confirm anticipated flash as wrong (if active on this noteIdx)
              if (_anticipatedFlashNoteIdx == decision.noteIndex) {
                _confirmAnticipatedAsWrong(
                  noteIdx: decision.noteIndex!,
                  expectedMidi: decision.expectedMidi ?? 0,
                  detectedMidi: decision.detectedMidi!,
                  nowMs: elapsedMs,
                );
              }

              // Trigger red keyboard flash (independent of scoring system state)
              _registerWrongHit(detectedNote: decision.detectedMidi!, now: now);
              if (kDebugMode) {
                debugPrint(
                  'WRONGFLASH_UI_TRIGGERED midi=${decision.detectedMidi} '
                  'noteIdx=${decision.noteIndex} elapsed=${(elapsed * 1000).toStringAsFixed(0)}ms',
                );
              }

              // Send to NEW scoring controller (if enabled)
              if (_useNewScoringSystem && _newController != null) {
                final playedEvent = PracticeController.createPlayedEvent(
                  midi: decision.detectedMidi!,
                  tPlayedMs: elapsed * 1000.0,
                  source: NoteSource.microphone,
                );
                _newController!.onPlayedNote(playedEvent);
              }

              setState(() {});
            }

            _accuracy = NoteAccuracy.wrong;
            _updateDetectedNote(
              decision.detectedMidi,
              now,
              accuracyChanged: true,
            );
            // ═══════════════════════════════════════════════════════════════
            break;
        }
      }

      // ═══════════════════════════════════════════════════════════════════
      // SESSION 4: Update time for miss detection in NEW controller
      // ═══════════════════════════════════════════════════════════════════
      if (_useNewScoringSystem && _newController != null) {
        _newController!.onTimeUpdate(elapsed * 1000.0); // Convert sec to ms
      }
      // ═══════════════════════════════════════════════════════════════════

      // Update UI with MicEngine's held note (200ms hold)
      final uiMidi = _micEngine!.uiDetectedMidi;
      final accuracyChanged = prevAccuracy != _accuracy;
      _updateDetectedNote(uiMidi, now, accuracyChanged: accuracyChanged);
    }

    _logMicDebug(now);
  }

  void _updateDetectedNote(
    int? nextDetected,
    DateTime now, {
    bool accuracyChanged = false,
  }) {
    final prevDetected = _detectedNote;
    final tooSoon =
        _lastUiUpdateAt != null &&
        now.difference(_lastUiUpdateAt!) < const Duration(milliseconds: 120);
    final shouldUpdate =
        !tooSoon || prevDetected != nextDetected || accuracyChanged;

    if (shouldUpdate && mounted) {
      setState(() {
        _detectedNote = nextDetected;
      });
      _lastUiUpdateAt = now;
    } else {
      _detectedNote = nextDetected;
    }
  }

  void _registerCorrectHit({
    required int targetNote,
    required int detectedNote,
    required DateTime now,
    int? noteIndex, // FIX BUG SESSION-005 #1+2: Track specific note index
  }) {
    // SESSION-034 FIX: Use explicit expiry timestamp for guaranteed flash visibility
    // More robust than diff<=duration: even if build is delayed, flash stays visible
    // until the expiry time is reached (DateTime.now().isBefore(_successFlashUntil))
    final registerTime = DateTime.now();
    final expiryTime = registerTime.add(_successFlashDuration);

    _lastCorrectNote = targetNote;
    _lastCorrectNoteIndex = noteIndex; // FIX BUG SESSION-005 #1+2
    _lastCorrectHitAt = registerTime;
    _successFlashUntil = expiryTime; // SESSION-034: Set explicit expiry

    // SESSION-035 FIX: ALWAYS clear wrong flash on ANY correct hit
    // CAUSE: Rouge persistait après HIT si le WRONG était sur une note différente
    // PREUVE: t=7.257s HIT noteIdx=6 mais ROUGE visible (wrong flash non effacé)
    // BEFORE: Only cleared if _lastWrongNote == detectedNote || targetNote
    // AFTER: Always clear - any correct HIT should dismiss red feedback
    if (_wrongFlashUntil != null) {
      final clearedMidi = _lastWrongNote;
      _wrongFlashUntil = null;
      _lastWrongNote = null; // SESSION-035: Also clear the note to prevent stale state
      if (kDebugMode) {
        debugPrint(
          'WRONGFLASH_CLEARED_BY_HIT hitMidi=$detectedNote targetMidi=$targetNote '
          'clearedWrongMidi=$clearedMidi reason=any_correct_hit_clears_wrong',
        );
      }
    }

    // FIX BUG P0 (FALSE RED): Track this note as recently hit
    _recentlyHitNotes[detectedNote] = registerTime;

    // SESSION-035: Log for debugging flash timing with expiry
    if (kDebugMode) {
      debugPrint(
        'GOODFLASH_REGISTERED midi=$targetNote noteIdx=$noteIndex '
        'untilMs=${expiryTime.millisecondsSinceEpoch} '
        'deltaCbMs=${registerTime.difference(now).inMilliseconds}',
      );
    }

    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {});
    }
  }

  void _registerWrongHit({required int detectedNote, required DateTime now}) {
    // SESSION-034 FIX: Use explicit expiry timestamp for guaranteed flash visibility
    // More robust than diff<=duration: even if build is delayed, flash stays visible
    // until the expiry time is reached (DateTime.now().isBefore(_wrongFlashUntil))
    final registerTime = DateTime.now();

    // SESSION-025 FIX: Use _wrongFlashGateDuration (150ms) instead of _successFlashDuration (200ms)
    // PREUVE: logcat session-025 shows ~50% of MicEngine WRONG_FLASH being silently blocked
    //         because intervals (161ms, 186ms, 180ms, 151ms, 172ms) < 200ms
    // Gate is now aligned with MicEngine (wrongFlashCooldownSec=150ms, wrongFlashDedupMs=150ms)
    final tooSoon =
        _lastWrongHitAt != null &&
        registerTime.difference(_lastWrongHitAt!) < _wrongFlashGateDuration;
    if (tooSoon && _lastWrongNote == detectedNote) {
      // SESSION-032 FIX: Log when gate blocks (for debugging)
      if (kDebugMode) {
        debugPrint(
          'WRONGFLASH_REGISTER_BLOCKED midi=$detectedNote '
          'reason=tooSoon_sameMidi lastWrongAt=${_lastWrongHitAt != null ? registerTime.difference(_lastWrongHitAt!).inMilliseconds : "null"}ms '
          'gate=${_wrongFlashGateDuration.inMilliseconds}ms',
        );
      }
      return;
    }

    final expiryTime = registerTime.add(_successFlashDuration);
    _lastWrongHitAt = registerTime;
    _lastWrongNote = detectedNote;
    _wrongFlashUntil = expiryTime; // SESSION-034: Set explicit expiry

    // SESSION-035: Log for debugging flash timing with expiry
    if (kDebugMode) {
      debugPrint(
        'WRONGFLASH_REGISTERED midi=$detectedNote '
        'untilMs=${expiryTime.millisecondsSinceEpoch} '
        'deltaCbMs=${registerTime.difference(now).inMilliseconds}',
      );
    }

    HapticFeedback.selectionClick();
    if (mounted) {
      setState(() {});
    }
  }

  /// FIX BUG P0 (FALSE RED): Get set of notes that were recently validated as HIT
  /// Cleans up expired entries (older than _recentHitWindow)
  // ignore: unused_element (called from _PracticeUiStageMixin)
  Set<int> _getRecentlyHitNotes(DateTime now) {
    // Clean up expired entries
    _recentlyHitNotes.removeWhere((midi, timestamp) {
      return now.difference(timestamp) > _recentHitWindow;
    });
    return _recentlyHitNotes.keys.toSet();
  }

  List<double> _convertChunkToSamples(List<int> chunk) {
    if (chunk.isEmpty) return const [];
    final looksLikeBytes =
        chunk is Uint8List ||
        (chunk is! Int16List && chunk.every((v) => v >= 0 && v <= 255));

    final samples = <double>[];
    if (looksLikeBytes) {
      final evenLength = chunk.length - (chunk.length % 2);
      // D1: Convert bytes to int16 samples
      for (var i = 0; i < evenLength; i += 2) {
        final lo = chunk[i];
        final hi = chunk[i + 1];
        int value = (hi << 8) | lo;
        if (value >= 0x8000) {
          value -= 0x10000;
        }
        samples.add(value / 32768.0);
      }
      return samples;
    }

    // D1: If input is Int16List (could be stereo), treat as raw int16 values
    // and downmix to mono if needed (take every sample, assuming they're already interleaved properly)
    for (final value in chunk) {
      if (value < -32768 || value > 32767) {
        continue;
      }
      samples.add(value / 32768.0);
    }
    return samples;
  }

  // B) Merge overlapping same-pitch events (fix "two streams" problem)
  List<_NoteEvent> _mergeOverlappingEventsByPitch(
    List<_NoteEvent> events, {
    double? mergeTolerance,
    double? mergeGapTolerance,
  }) {
    mergeTolerance ??= _mergeEventOverlapToleranceSec;
    mergeGapTolerance ??= _mergeEventGapToleranceSec;
    if (events.isEmpty) {
      _notesMergedPairs = 0;
      _notesOverlapsDetected = 0;
      return events;
    }

    // Group events by pitch
    final byPitch = <int, List<_NoteEvent>>{};
    for (final event in events) {
      byPitch.putIfAbsent(event.pitch, () => []).add(event);
    }

    var mergedPairs = 0;
    var overlapsDetected = 0;
    final merged = <_NoteEvent>[];

    // Process each pitch group
    for (final pitchEvents in byPitch.values) {
      // Sort by start then end
      pitchEvents.sort((a, b) {
        final startCmp = a.start.compareTo(b.start);
        if (startCmp != 0) return startCmp;
        return a.end.compareTo(b.end);
      });

      final mergedGroup = <_NoteEvent>[];
      _NoteEvent? current = pitchEvents.isNotEmpty ? pitchEvents[0] : null;

      for (var i = 1; i < pitchEvents.length; i++) {
        final next = pitchEvents[i];
        if (current != null) {
          // Check for overlap: next.start <= current.end + tolerance
          final gap = next.start - current.end;
          if (gap <= mergeGapTolerance) {
            // Merge: extend current.end to max(current.end, next.end)
            overlapsDetected++;
            current = _NoteEvent(
              pitch: current.pitch,
              start: current.start,
              end: max(current.end, next.end),
            );
            mergedPairs++;
          } else {
            // No overlap, save current and move to next
            mergedGroup.add(current);
            current = next;
          }
        }
      }
      if (current != null) {
        mergedGroup.add(current);
      }

      merged.addAll(mergedGroup);
    }

    // Re-sort globally by start then pitch
    merged.sort((a, b) {
      final startCmp = a.start.compareTo(b.start);
      if (startCmp != 0) return startCmp;
      return a.pitch.compareTo(b.pitch);
    });

    _notesMergedPairs = mergedPairs;
    _notesOverlapsDetected = overlapsDetected;

    if (kDebugMode && overlapsDetected > 0) {
      debugPrint(
        'Practice notes merged: mergedPairs=$mergedPairs overlapsDetected=$overlapsDetected',
      );
    }

    return merged;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-036: Anticipated flash methods (zero-lag feel / onset-first)
  // ══════════════════════════════════════════════════════════════════════════

  /// Debounce constant for anticipated flash (120ms between emits)
  static const double _anticipatedFlashDebounceMs = 120.0;

  /// TTL for anticipated flash (450ms before auto-cancel)
  static const double _anticipatedFlashTtlMs = 450.0;

  /// SESSION-036b: Throttle for SUPPRESSED log (200ms between logs)
  static const double _suppressedLogThrottleMs = 200.0;
  double? _lastSuppressedLogMs;

  /// Emit a new anticipated flash (first onset for this noteIdx)
  void _emitAnticipatedFlash({
    required int noteIdx,
    required int expectedMidi,
    required double nowMs,
  }) {
    final debounceMs = _lastAnticipatedEmitMs != null
        ? nowMs - _lastAnticipatedEmitMs!
        : double.infinity;

    _anticipatedFlashMidi = expectedMidi;
    _anticipatedFlashNoteIdx = noteIdx;
    _anticipatedFlashUntilMs = nowMs + _anticipatedFlashTtlMs;
    _lastAnticipatedEmitMs = nowMs;

    if (kDebugMode) {
      debugPrint(
        'ANTICIPATED_FLASH_EMIT noteIdx=$noteIdx expectedMidi=$expectedMidi '
        'untilMs=${_anticipatedFlashUntilMs!.toStringAsFixed(0)} debounceMs=${debounceMs.toStringAsFixed(0)}',
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Refresh TTL of existing anticipated flash (same noteIdx, no setState)
  void _refreshAnticipatedFlash({
    required int noteIdx,
    required double nowMs,
  }) {
    _anticipatedFlashUntilMs = nowMs + _anticipatedFlashTtlMs;

    if (kDebugMode) {
      debugPrint(
        'ANTICIPATED_FLASH_REFRESH noteIdx=$noteIdx expectedMidi=$_anticipatedFlashMidi '
        'untilMs=${_anticipatedFlashUntilMs!.toStringAsFixed(0)}',
      );
    }
    // No setState - avoid unnecessary rebuild for TTL refresh only
  }

  /// Confirm anticipated flash as success (HIT) - clear and let green take over
  void _confirmAnticipatedAsSuccess({
    required int noteIdx,
    required int midi,
    required double dtMs,
    required double nowMs,
  }) {
    if (kDebugMode) {
      // SESSION-036b: Calculate msSinceOnset for timing correlation
      final onsetTriggerMs = _micEngine?.lastOnsetTriggerElapsedMs ?? -10000.0;
      final msSinceOnset = nowMs - onsetTriggerMs;
      debugPrint(
        'ANTICIPATED_FLASH_CONFIRM_SUCCESS noteIdx=$noteIdx midi=$midi dtMs=${dtMs.toStringAsFixed(0)} '
        'msSinceOnset=${msSinceOnset.toStringAsFixed(0)} nowMs=${nowMs.toStringAsFixed(0)}',
      );
    }

    _clearAnticipatedFlashState();
    // No setState here - _registerCorrectHit will handle it
  }

  /// Confirm anticipated flash as wrong - clear and let red take over
  void _confirmAnticipatedAsWrong({
    required int noteIdx,
    required int expectedMidi,
    required int detectedMidi,
    required double nowMs,
  }) {
    if (kDebugMode) {
      // SESSION-036b: Calculate msSinceOnset for timing correlation
      final onsetTriggerMs = _micEngine?.lastOnsetTriggerElapsedMs ?? -10000.0;
      final msSinceOnset = nowMs - onsetTriggerMs;
      debugPrint(
        'ANTICIPATED_FLASH_CONFIRM_WRONG noteIdx=$noteIdx expected=$expectedMidi detected=$detectedMidi '
        'msSinceOnset=${msSinceOnset.toStringAsFixed(0)} nowMs=${nowMs.toStringAsFixed(0)}',
      );
    }

    _clearAnticipatedFlashState();
    // No setState here - _registerWrongHit will handle it
  }

  /// Cancel anticipated flash (timeout, noteIdx change, or hit decision)
  void _cancelAnticipatedFlash({
    required String reason,
    int? oldIdx,
    int? newIdx,
  }) {
    if (kDebugMode) {
      final idxInfo = oldIdx != null && newIdx != null
          ? ' oldIdx=$oldIdx newIdx=$newIdx'
          : ' noteIdx=$_anticipatedFlashNoteIdx';
      debugPrint(
        'ANTICIPATED_FLASH_CANCEL reason=$reason$idxInfo',
      );
    }

    _clearAnticipatedFlashState();

    if (mounted) {
      setState(() {});
    }
  }

  /// Clear anticipated flash state (no setState)
  void _clearAnticipatedFlashState() {
    _anticipatedFlashMidi = null;
    _anticipatedFlashNoteIdx = null;
    _anticipatedFlashUntilMs = null;
    // Note: Don't clear _lastAnticipatedEmitMs - keep for debounce tracking
  }

  /// Check if anticipated flash has timed out
  void _checkAnticipatedTimeout(double nowMs) {
    if (_anticipatedFlashMidi == null || _anticipatedFlashUntilMs == null) {
      return;
    }

    if (nowMs > _anticipatedFlashUntilMs!) {
      _cancelAnticipatedFlash(reason: 'timeout');
    }
  }

  /// Check if noteIdx changed and cancel if stale
  void _checkAnticipatedNoteIdxChange(int? currentActiveNoteIdx) {
    if (_anticipatedFlashNoteIdx == null) return;

    if (currentActiveNoteIdx != _anticipatedFlashNoteIdx) {
      _cancelAnticipatedFlash(
        reason: 'noteidx_change',
        oldIdx: _anticipatedFlashNoteIdx,
        newIdx: currentActiveNoteIdx,
      );
    }
  }

  /// Check if anticipated flash is active (for UI rendering)
  // ignore: unused_element (called from _PracticeUiVideoMixin)
  bool _isAnticipatedFlashActive(double nowMs) {
    return _anticipatedFlashMidi != null &&
        _anticipatedFlashUntilMs != null &&
        nowMs <= _anticipatedFlashUntilMs!;
  }

  /// Process onset trigger for anticipated flash
  void _processOnsetForAnticipatedFlash(double nowMs) {
    if (_micEngine == null) return;

    final onsetState = _micEngine!.lastOnsetState;
    final inWindow = _micEngine!.onsetInActiveWindow;
    final noteIdx = _micEngine!.onsetActiveNoteIdx;
    final expectedMidi = _micEngine!.onsetExpectedMidi;
    final rmsRatio = _micEngine!.onsetRmsRatio;
    final dRms = _micEngine!.onsetDRms;

    // SESSION-036b: Helper to log SUPPRESSED with throttle
    void logSuppressed(String reason) {
      if (!kDebugMode) return;
      // Throttle: only log once per 200ms
      final throttleOk = _lastSuppressedLogMs == null ||
          (nowMs - _lastSuppressedLogMs!) >= _suppressedLogThrottleMs;
      if (!throttleOk) return;
      _lastSuppressedLogMs = nowMs;

      final debounceMs = _lastAnticipatedEmitMs != null
          ? nowMs - _lastAnticipatedEmitMs!
          : -1.0;
      debugPrint(
        'ANTICIPATED_FLASH_SUPPRESSED reason=$reason noteIdx=$noteIdx expectedMidi=$expectedMidi '
        'nowMs=${nowMs.toStringAsFixed(0)} onset=${onsetState.name} inWindow=$inWindow '
        'ratio=${rmsRatio.toStringAsFixed(2)} dRms=${dRms.toStringAsFixed(4)} '
        'debounceMs=${debounceMs.toStringAsFixed(0)}',
      );
    }

    // Only process trigger events
    if (onsetState != mic.OnsetState.trigger) {
      // Don't log for non-trigger states (too noisy)
      return;
    }

    // Check: not in active window
    if (!inWindow) {
      logSuppressed('not_in_window');
      return;
    }

    // Check: no active note
    if (noteIdx == null) {
      logSuppressed('no_active_note');
      return;
    }

    // Check: missing expected midi
    if (expectedMidi == null) {
      logSuppressed('missing_expected_midi');
      return;
    }

    // Check debounce (120ms)
    final debounceOk = _lastAnticipatedEmitMs == null ||
        (nowMs - _lastAnticipatedEmitMs!) >= _anticipatedFlashDebounceMs;

    if (!debounceOk) {
      logSuppressed('debounce');
      return;
    }

    // Check if anticipated already active on different noteIdx
    if (_anticipatedFlashNoteIdx != null && _anticipatedFlashNoteIdx != noteIdx) {
      logSuppressed('already_active_other_noteidx');
      // Note: We still emit for the new noteIdx, this is just informational
    }

    // Check if this is same noteIdx (refresh) or new (emit)
    if (_anticipatedFlashNoteIdx == noteIdx) {
      // Same note - refresh TTL
      _refreshAnticipatedFlash(noteIdx: noteIdx, nowMs: nowMs);
    } else {
      // New note - emit
      _emitAnticipatedFlash(
        noteIdx: noteIdx,
        expectedMidi: expectedMidi,
        nowMs: nowMs,
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-036c: Detected note flash (BLUE) - "REAL-TIME FEEL"
  // Shows what the mic actually hears, independent of scoring/matching
  // ══════════════════════════════════════════════════════════════════════════

  /// TTL for detected flash (150ms - short to avoid lingering)
  static const double _detectedFlashTtlMs = 150.0;

  /// SESSION-037: TTL window for considering raw detection "recent"
  static const double _rawDetectionWindowSec = 0.250; // 250ms

  /// SESSION-037: Release gating constants
  static const double _releaseMinRms = 0.008; // RMS below this = sound ended
  static const double _releaseGracePeriodMs = 60.0; // Grace period before clearing
  static const double _hardCapMs = 180.0; // Max duration without new pitch

  /// Update detected flash from MicEngine's last detected pitch
  /// SESSION-037: Now with release gating + hard cap to prevent stuck blue
  void _updateDetectedFlash(double nowMs) {
    if (_micEngine == null) return;

    final nowSec = nowMs / 1000.0;
    final rmsNow = _micEngine!.lastRms ?? 0.0;

    // ══════════════════════════════════════════════════════════════════════
    // SESSION-037 FIX: Release gating - clear BLUE when sound ends
    // ══════════════════════════════════════════════════════════════════════
    if (_detectedFlashMidi != null) {
      final soundEnded = rmsNow < _releaseMinRms;
      final pitchAgeMs = nowMs - _lastPitchUpdateMs;
      final flashAgeMs = _detectedFlashFirstEmitMs != null
          ? nowMs - _detectedFlashFirstEmitMs!
          : 0.0;

      // Clear conditions:
      // 1. TTL expired (original behavior)
      // 2. Sound ended (RMS below threshold) for grace period
      // 3. Hard cap: flash active too long without new pitch
      final ttlExpired = _detectedFlashUntilMs != null && nowMs > _detectedFlashUntilMs!;
      final releaseGated = soundEnded && pitchAgeMs > _releaseGracePeriodMs;
      final hardCapHit = flashAgeMs > _hardCapMs && pitchAgeMs > 80.0;

      if (ttlExpired || releaseGated || hardCapHit) {
        final reason = ttlExpired
            ? 'ttl_expired'
            : releaseGated
                ? 'release_gated'
                : 'hard_cap';
        if (kDebugMode) {
          debugPrint(
            'UI_DETECTED_CLEAR reason=$reason midi=$_detectedFlashMidi '
            'nowMs=${nowMs.toStringAsFixed(0)} rms=${rmsNow.toStringAsFixed(4)} '
            'pitchAgeMs=${pitchAgeMs.toStringAsFixed(0)} flashAgeMs=${flashAgeMs.toStringAsFixed(0)}',
          );
        }
        _detectedFlashMidi = null;
        _detectedFlashUntilMs = null;
        _detectedFlashFreq = null;
        _detectedFlashConf = null;
        _detectedFlashFirstEmitMs = null;
        if (mounted) setState(() {});
        return;
      }
    }

    // Get last detected from MicEngine (high-conf, post-filter)
    final detectedMidi = _micEngine!.lastDetectedMidi;
    final detectedElapsedMs = _micEngine!.lastDetectedElapsedMs;
    final detectedFreq = _micEngine!.lastDetectedFreq;
    final detectedConf = _micEngine!.lastDetectedConf;
    final detectedSource = _micEngine!.lastDetectedSource;

    // SESSION-037: Get raw detection (low-conf, pre-filter) for REAL-TIME FEEL
    final rawMidi = _micEngine!.lastRawMidi;
    final rawTSec = _micEngine!.lastRawTSec;
    final rawFreq = _micEngine!.lastRawFreq;
    final rawConf = _micEngine!.lastRawConf;
    final rawSource = _micEngine!.lastRawSource;

    // Determine which detection to use:
    // 1. Prefer high-conf detection if recent (within 200ms)
    // 2. Fall back to raw detection if recent (within 250ms) - SESSION-037 FIX
    int? useMidi;
    double? useFreq;
    double? useConf;
    String useSource = 'none';
    bool isNewPitch = false;

    final highConfRecent = detectedMidi != null && (nowMs - detectedElapsedMs) <= 200;
    final rawRecent = rawMidi != null && (nowSec - rawTSec) <= _rawDetectionWindowSec;

    if (highConfRecent) {
      // Use high-confidence detection
      useMidi = detectedMidi;
      useFreq = detectedFreq;
      useConf = detectedConf;
      useSource = detectedSource;
      // Check if this is a NEW pitch update (not stale)
      isNewPitch = detectedElapsedMs > _lastPitchUpdateMs;
      if (isNewPitch) _lastPitchUpdateMs = detectedElapsedMs;
    } else if (rawRecent) {
      // SESSION-037: Use raw detection for REAL-TIME FEEL
      useMidi = rawMidi;
      useFreq = rawFreq;
      useConf = rawConf;
      useSource = 'raw_$rawSource';
      // Raw uses seconds, convert for comparison
      final rawMs = rawTSec * 1000.0;
      isNewPitch = rawMs > _lastPitchUpdateMs;
      if (isNewPitch) _lastPitchUpdateMs = rawMs;
    }

    // No recent detection at all
    if (useMidi == null) {
      return;
    }

    // Check if midi changed or new detection
    final midiChanged = _detectedFlashMidi != useMidi;
    final isNew = _detectedFlashMidi == null;

    if (midiChanged || isNew) {
      // New or changed detected note - emit
      _detectedFlashMidi = useMidi;
      _detectedFlashUntilMs = nowMs + _detectedFlashTtlMs;
      _detectedFlashFreq = useFreq;
      _detectedFlashConf = useConf;
      _detectedFlashFirstEmitMs = nowMs; // Track start for hard cap

      if (kDebugMode) {
        debugPrint(
          'UI_DETECTED_SET midi=$useMidi source=$useSource '
          'conf=${useConf?.toStringAsFixed(2) ?? "?"} rms=${rmsNow.toStringAsFixed(4)} '
          'nowMs=${nowMs.toStringAsFixed(0)} holdMs=${_detectedFlashTtlMs.toStringAsFixed(0)}',
        );
      }

      if (mounted) {
        setState(() {});
      }
    } else if (isNewPitch) {
      // SESSION-037 FIX: Only refresh TTL if there's a NEW pitch update
      // This prevents infinite refresh from stale timestamps
      _detectedFlashUntilMs = nowMs + _detectedFlashTtlMs;
      if (kDebugMode) {
        final pitchAgeMs = nowMs - _lastPitchUpdateMs;
        debugPrint(
          'UI_DETECTED_REFRESH midi=$useMidi nowMs=${nowMs.toStringAsFixed(0)} '
          'pitchAgeMs=${pitchAgeMs.toStringAsFixed(0)} untilMs=${_detectedFlashUntilMs!.toStringAsFixed(0)}',
        );
      }
    }
    // If same midi but NOT a new pitch, don't refresh TTL - let it expire naturally
  }

  /// Check if detected flash is active (for UI rendering)
  bool _isDetectedFlashActive(double nowMs) {
    return _detectedFlashMidi != null &&
        _detectedFlashUntilMs != null &&
        nowMs <= _detectedFlashUntilMs!;
  }
}
