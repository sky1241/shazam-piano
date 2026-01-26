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
    _lastCorrectNote = targetNote;
    _lastCorrectNoteIndex = noteIndex; // FIX BUG SESSION-005 #1+2
    _lastCorrectHitAt = now;

    // FIX BUG P0 (FALSE RED): Track this note as recently hit
    _recentlyHitNotes[detectedNote] = now;

    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {});
    }
  }

  void _registerWrongHit({required int detectedNote, required DateTime now}) {
    // SESSION-025 FIX: Use _wrongFlashGateDuration (150ms) instead of _successFlashDuration (200ms)
    // PREUVE: logcat session-025 shows ~50% of MicEngine WRONG_FLASH being silently blocked
    //         because intervals (161ms, 186ms, 180ms, 151ms, 172ms) < 200ms
    // Gate is now aligned with MicEngine (wrongFlashCooldownSec=150ms, wrongFlashDedupMs=150ms)
    final tooSoon =
        _lastWrongHitAt != null &&
        now.difference(_lastWrongHitAt!) < _wrongFlashGateDuration;
    if (tooSoon && _lastWrongNote == detectedNote) {
      // SESSION-032 FIX: Log when gate blocks (for debugging)
      if (kDebugMode) {
        debugPrint(
          'WRONGFLASH_REGISTER_BLOCKED midi=$detectedNote '
          'reason=tooSoon_sameMidi lastWrongAt=${_lastWrongHitAt != null ? now.difference(_lastWrongHitAt!).inMilliseconds : "null"}ms '
          'gate=${_wrongFlashGateDuration.inMilliseconds}ms',
        );
      }
      return;
    }
    _lastWrongHitAt = now;
    _lastWrongNote = detectedNote;
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
}
