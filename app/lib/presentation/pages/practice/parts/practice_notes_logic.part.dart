part of '../practice_page.dart';

/// Mixin for note processing, scoring, and hit/miss detection.
/// Extracted from _PracticePageState to reduce file size.
mixin _PracticeNotesLogicMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  double? _guidanceElapsedSec();
  bool _isSessionActive(int sessionId);
  void _logMicDebug(DateTime now);
  Set<int> _computeImpactNotes({
    double? elapsedSec,
  }); // SESSION-056: For UI feedback

  // ════════════════════════════════════════════════════════════════════════════
  // LOI V3: JUGE DE FRAPPE - Fonctions helper
  // ════════════════════════════════════════════════════════════════════════════

  /// SESSION-075: Clamp MIDI to visible keyboard range by shifting octaves.
  /// YIN suffers from "period doubling" and often detects 1-2 octaves too low.
  /// This function shifts the detected MIDI to the closest octave within the keyboard.
  /// Ex: keyboard=48-84, YIN detects 37 (C#2) → shift to 61 (C#4)
  int _clampMidiToKeyboard(int midi) {
    // Already in keyboard range
    if (midi >= _displayFirstKey && midi <= _displayLastKey) {
      return midi;
    }

    // Shift up by octaves until in range
    int clamped = midi;
    while (clamped < _displayFirstKey) {
      clamped += 12;
    }

    // If now above range, shift down
    while (clamped > _displayLastKey) {
      clamped -= 12;
    }

    // Final check: if still out of range (keyboard < 1 octave), pick closest edge
    if (clamped < _displayFirstKey) {
      clamped = _displayFirstKey + (midi % 12);
      if (clamped > _displayLastKey) clamped -= 12;
    }

    return clamped;
  }

  /// Calcule la position Y d'une note - IDENTIQUE au painter (_FallingNotesPainter)
  /// [noteTimeSec] = note.start ou note.end selon ce qu'on calcule
  /// [elapsedSec] = temps écoulé actuel
  /// [fallLeadSec] = temps de chute (doit être _judgeFallLeadSec)
  /// [fallAreaHeightPx] = hauteur de la zone (doit être _judgeFallAreaHeight)
  double _judgeComputeNoteYPosition({
    required double noteTimeSec,
    required double elapsedSec,
    required double fallLeadSec,
    required double fallAreaHeightPx,
  }) {
    if (fallLeadSec <= 0) return 0;
    final progress = (elapsedSec - (noteTimeSec - fallLeadSec)) / fallLeadSec;
    return progress * fallAreaHeightPx;
  }

  /// Vérifie si la dernière note est hors écran et effectue la transition ACTIVE→ENDED
  /// Retourne true si l'état est maintenant ENDED (ou était déjà ENDED)
  bool _judgeCheckAndTransitionToEnded(double elapsedSec, double elapsedMs) {
    // Déjà ENDED ? Pas besoin de re-vérifier
    if (_judgeState == JudgeSessionState.ended) {
      return true;
    }

    // Paramètres du layout pas encore initialisés ? Ne pas transitionner
    if (_judgeFallAreaHeight <= 0 || _judgeFallLeadSec <= 0) {
      return false;
    }

    // Pas de notes ? Ne pas transitionner (ou transitionner immédiatement ?)
    if (_lastNoteEndSec <= 0) {
      return false;
    }

    // Calculer la position Y du HAUT de la dernière note (topY = note.end)
    final lastNoteTopY = _judgeComputeNoteYPosition(
      noteTimeSec: _lastNoteEndSec,
      elapsedSec: elapsedSec,
      fallLeadSec: _judgeFallLeadSec,
      fallAreaHeightPx: _judgeFallAreaHeight,
    );

    // Condition ENDED : le haut de la dernière note est >= hauteur visible
    // (identique au culling du painter: rectTop > fallAreaHeight)
    final isLastNoteOffscreen = lastNoteTopY >= _judgeFallAreaHeight;

    if (isLastNoteOffscreen) {
      // TRANSITION ACTIVE → ENDED (irréversible)
      _judgeState = JudgeSessionState.ended;

      if (kDebugMode) {
        debugPrint(
          'STATE_TRANSITION ts=${elapsedMs.round()} from=ACTIVE to=ENDED '
          'reason=last_note_offscreen lastNoteEndSec=${_lastNoteEndSec.toStringAsFixed(3)} '
          'lastNoteTopY=${lastNoteTopY.toStringAsFixed(1)} fallAreaHeight=${_judgeFallAreaHeight.toStringAsFixed(1)}',
        );
      }
      return true;
    }

    return false;
  }

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

    // ═══════════════════════════════════════════════════════════════════════════
    // D1: During countdown - calibrate noise floor but skip pitch detection
    // This uses the 2-3 second Play→Notes delay to measure ambient noise
    // ═══════════════════════════════════════════════════════════════════════════
    if (_practiceState == _PracticeState.countdown) {
      // Feed samples to MicEngine for noise floor calibration only
      _micEngine?.ingestCountdownSamples(samples);
      return;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOI V3: JUGE DE FRAPPE - Vérifier état ENDED (micro OFF conceptuel)
    // Si ENDED : aucun traitement, aucun flash, sortie immédiate
    // ═══════════════════════════════════════════════════════════════════════════
    if (_judgeState == JudgeSessionState.ended) {
      // Micro conceptuellement OFF - ignorer tous les samples
      return;
    }

    // FIX CASCADE: Update timestamp APRÈS guards (consistent pattern)
    _lastMicFrameAt = now;

    // ═══════════════════════════════════════════════════════════════
    // CRITICAL: MicEngine scoring (all gating + buffering internal)
    // MUST RUN FIRST to update lastRawMidi/lastRawConf for S56 engine
    // ═══════════════════════════════════════════════════════════════
    final elapsed = _guidanceElapsedSec();
    if (elapsed != null && _micEngine != null) {
      final prevAccuracy = _accuracy;
      final elapsedMs = elapsed * 1000.0;

      // ═══════════════════════════════════════════════════════════════════════
      // LOI V3: Vérifier transition ACTIVE → ENDED (dernière note hors écran)
      // ═══════════════════════════════════════════════════════════════════════
      if (_judgeCheckAndTransitionToEnded(elapsed, elapsedMs)) {
        // ENDED : micro OFF conceptuel, aucun traitement
        return;
      }

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

      // ═══════════════════════════════════════════════════════════════════════
      // LOI V3: JUGE DE FRAPPE - Arbitre central unique
      // ═══════════════════════════════════════════════════════════════════════
      // ENTRÉES:
      //   - rapport_detection: rawMidiForUi (0 ou 1 candidat après best-guess MicEngine)
      //   - notes_attendues_actives: expectedMidis
      //   - état: _judgeState (ACTIVE garanti ici car check plus haut)
      // SORTIES:
      //   - FLASH_VERT(touche) si verdict CORRECT
      //   - FLASH_ROUGE(touche) si verdict INCORRECT
      //   - NO_FLASH si rapport_detection vide
      // ═══════════════════════════════════════════════════════════════════════
      if (_uiFeedbackEngine != null) {
        // SESSION-075: Sync keyboard range to UIFeedbackEngine for ROUGE clamping
        _uiFeedbackEngine!.setKeyboardRange(_displayFirstKey, _displayLastKey);

        // Rapport de détection (déjà best-guess par MicEngine)
        var rawMidiForUi = _micEngine!.getRawMidiForUi(elapsed);
        final rawConfForUi = _micEngine!.getRawConfForUi(elapsed) ?? 0.0;

        // ═══════════════════════════════════════════════════════════════════
        // SESSION-075: CLAMP MIDI TO VISIBLE KEYBOARD
        // ═══════════════════════════════════════════════════════════════════
        // YIN souffre de "period doubling" et détecte souvent 1-2 octaves trop bas.
        // Solution: ramener le midi détecté à l'octave la plus proche dans le clavier.
        // Ex: clavier=48-84, YIN détecte 37 (C#2) → ramener à 61 (C#4)
        // ═══════════════════════════════════════════════════════════════════
        if (rawMidiForUi != null) {
          final originalMidi = rawMidiForUi;
          rawMidiForUi = _clampMidiToKeyboard(rawMidiForUi);
          if (kDebugMode && rawMidiForUi != originalMidi) {
            debugPrint(
              'MIDI_CLAMP_TO_KEYBOARD original=$originalMidi clamped=$rawMidiForUi '
              'keyboard=[$_displayFirstKey..$_displayLastKey]',
            );
          }
        }

        // Notes attendues actives (partition)
        final expectedMidis = _computeImpactNotes(elapsedSec: elapsed);

        // Format rapport_detection pour log
        final rapportDetection = rawMidiForUi != null
            ? '[$rawMidiForUi@${rawConfForUi.toStringAsFixed(2)}]'
            : '[]';

        // LOG JUDGE_IN
        if (kDebugMode && rawMidiForUi != null) {
          debugPrint(
            'JUDGE_IN ts=${elapsedMs.round()} rapport_detection=$rapportDetection '
            'attendues=$expectedMidis state=ACTIVE',
          );
        }

        // ═══════════════════════════════════════════════════════════════════
        // PHASE 1: Estimation de la note jouée
        // E1: Si ≥1 candidat → note_estimée = ce candidat (best-guess déjà fait)
        // E2: Si 0 candidat → note_estimée = INESTIMABLE → NO_FLASH
        // ═══════════════════════════════════════════════════════════════════
        if (rawMidiForUi == null) {
          // E2: Rapport vide → NO_FLASH (silence autorisé)
          // Pas de log JUDGE_OUT car pas de frappe détectée
          // Mais on doit quand même appeler update() pour gérer le clear
          _uiFeedbackEngine!.update(
            detectedMidi: null,
            confidence: rawConfForUi,
            expectedMidis: expectedMidis,
            nowMs: elapsedMs.round(),
          );
        } else {
          // E1: Note estimée disponible
          final noteEstimee = rawMidiForUi;

          // ═══════════════════════════════════════════════════════════════
          // SESSION-077: NO VERDICT IF NO EXPECTED NOTES
          // Si expectedMidis est vide, l'utilisateur joue entre les notes
          // ou avant/après - ce n'est PAS une erreur, juste pas de verdict.
          // On affiche en BLEU pour montrer la détection sans jugement.
          // ═══════════════════════════════════════════════════════════════
          if (expectedMidis.isEmpty) {
            // Pas de note attendue → afficher BLEU (détection sans verdict)
            _uiFeedbackEngine!.update(
              detectedMidi: noteEstimee,
              confidence: rawConfForUi,
              expectedMidis: expectedMidis,
              nowMs: elapsedMs.round(),
            );
            if (kDebugMode) {
              debugPrint(
                'JUDGE_NO_VERDICT ts=${elapsedMs.round()} midi=$noteEstimee '
                'reason=no_expected_notes (playing between/before notes)',
              );
            }
            // Continue to judgeUpdateCyan below (no verdict emitted)
          } else {
            // ═══════════════════════════════════════════════════════════════
            // PHASE 2: Association frappe-note (ONLY when expectedMidis non-empty)
            // A1/A2: Chercher si note_estimée ∈ expectedMidis
            // ═══════════════════════════════════════════════════════════════
            // SESSION-082: Compare PITCH CLASS instead of absolute MIDI
            // YIN often has octave errors (+1 to +2 octaves). If the detected
            // pitch class matches an expected pitch class, it's the correct note.
            // Example: expected=C5(60), detected=C6(72) → same pitch class (0) → MATCH
            final expectedPitchClasses = expectedMidis.map((m) => m % 12).toSet();
            final detectedPitchClass = noteEstimee % 12;
            final hasMatch = expectedPitchClasses.contains(detectedPitchClass);

            // ═══════════════════════════════════════════════════════════════
            // PHASE 3: Verdict et Flash
            // V1: Si match → CORRECT → FLASH_VERT
            // V2: Si no match → INCORRECT → FLASH_ROUGE
            // ═══════════════════════════════════════════════════════════════
            if (hasMatch) {
            // SESSION-084: Find the expected MIDI with matching pitch class
            // Display VERT on the EXPECTED key, not the detected octave
            // Bug: YIN detects A#6 (82) when expected is A#5 (70) - same pitch class
            // Fix: Show green on 70 (expected), not 82 (detected)
            final matchingExpectedMidi = expectedMidis.firstWhere(
              (m) => m % 12 == detectedPitchClass,
            );

            // V1: CORRECT → FLASH_VERT on expected MIDI
            _uiFeedbackEngine!.judgeFlashVert(
              midi: matchingExpectedMidi,
              nowMs: elapsedMs.round(),
            );

            // SESSION-066: Track green for protection window (use expected MIDI)
            _lastJudgeGreenMidi = matchingExpectedMidi;
            _lastJudgeGreenTimestampMs = elapsedMs.round();

            // SESSION-083: Track pitch class for extended sustain protection
            _recentlyValidatedPitchClasses[detectedPitchClass] = elapsedMs.round();

            if (kDebugMode) {
              debugPrint(
                'JUDGE_OUT ts=${elapsedMs.round()} note_estimee=$noteEstimee '
                'verdict=CORRECT flash=VERT touche=$matchingExpectedMidi '
                '(detected=$noteEstimee pc=$detectedPitchClass)',
              );
            }
          } else {
            // SESSION-066: GREEN PROTECTION WINDOW (Grace period for key release)
            // SESSION-078: Increased 300→500ms for more forgiving release timing
            // If this note was just VERT within _greenProtectionWindowMs, skip ROUGE
            // This prevents "held note becomes wrong" - user still holding after window ends
            final timeSinceGreen = elapsedMs.round() - _lastJudgeGreenTimestampMs;
            final isProtected = _lastJudgeGreenMidi == noteEstimee &&
                timeSinceGreen < _greenProtectionWindowMs;

            // SESSION-083: Extended sustain protection for ANY recently validated pitch class
            // Problem: D# validated at t=5532, sustain detected at t=8659 (3127ms later)
            //          Expected note is now C, so D# sustain causes false ROUGE
            // Solution: Check if pitch class was recently validated (within 3000ms)
            final lastValidatedTime = _recentlyValidatedPitchClasses[detectedPitchClass];
            final isSustainProtected = lastValidatedTime != null &&
                (elapsedMs.round() - lastValidatedTime) < _sustainProtectionWindowMs;

            if (isProtected) {
              // Skip ROUGE - note is in green immunity window
              if (kDebugMode) {
                debugPrint(
                  'JUDGE_SKIP_ROUGE ts=${elapsedMs.round()} midi=$noteEstimee '
                  'reason=green_protection timeSinceGreen=${timeSinceGreen}ms '
                  'window=${_greenProtectionWindowMs}ms',
                );
              }
            } else if (isSustainProtected) {
              // SESSION-083: Skip ROUGE - this is sustain of a previously correct note
              if (kDebugMode) {
                debugPrint(
                  'JUDGE_SKIP_ROUGE ts=${elapsedMs.round()} midi=$noteEstimee pc=$detectedPitchClass '
                  'reason=sustain_protection timeSinceValidated=${elapsedMs.round() - lastValidatedTime}ms '
                  'window=${_sustainProtectionWindowMs}ms',
                );
              }
            } else {
              // SESSION-079: LOW CONFIDENCE GATE FOR ROUGE
              // At low confidence (e.g., 0.24), YIN detects noise/harmonics as notes
              // Don't emit ROUGE if confidence is too low - treat as NO_VERDICT instead
              if (rawConfForUi < _minConfidenceForRouge) {
                // Confidence too low → skip ROUGE, show BLUE only
                _uiFeedbackEngine!.update(
                  detectedMidi: noteEstimee,
                  confidence: rawConfForUi,
                  expectedMidis: expectedMidis,
                  nowMs: elapsedMs.round(),
                );
                if (kDebugMode) {
                  debugPrint(
                    'JUDGE_SKIP_ROUGE ts=${elapsedMs.round()} midi=$noteEstimee '
                    'reason=low_confidence conf=${rawConfForUi.toStringAsFixed(2)} '
                    'threshold=$_minConfidenceForRouge',
                  );
                }
              } else {
                // V2: INCORRECT → FLASH_ROUGE
                // SESSION-076: Pass expectedMidis for octave clamping
                _uiFeedbackEngine!.judgeFlashRouge(
                  midi: noteEstimee,
                  nowMs: elapsedMs.round(),
                  expectedMidis: expectedMidis,
                );

                if (kDebugMode) {
                  debugPrint(
                    'JUDGE_OUT ts=${elapsedMs.round()} note_estimee=$noteEstimee '
                    'verdict=INCORRECT flash=ROUGE touche=$noteEstimee conf=${rawConfForUi.toStringAsFixed(2)}',
                  );
                }
              }
            }
          }
          } // End of else (expectedMidis non-empty)

          // Mettre à jour uniquement les cyan (notes attendues) sans écraser le verdict
          _uiFeedbackEngine!.judgeUpdateCyan(
            expectedMidis: expectedMidis,
            nowMs: elapsedMs.round(),
          );
        }
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
              // SESSION-039: Track onset of HIT to distinguish sustain vs re-attack
              _lastHitOnsetMs =
                  _micEngine?.lastOnsetTriggerElapsedMs ?? -10000.0;

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

              // SESSION-057: Notify UIFeedbackEngine of HIT_VALIDÉ for green flash
              _uiFeedbackEngine?.notifyHit(
                hitMidi: decision.expectedMidi!,
                nowMs: elapsedMs.round(),
              );

              // SESSION-084: Update sustain protection map from HIT decisions path
              // The JUDGE path might not have seen this detection (different timing/values)
              // so we must also protect the validated pitch class here
              final hitPitchClass = decision.expectedMidi! % 12;
              _recentlyValidatedPitchClasses[hitPitchClass] = elapsedMs.round();
              if (kDebugMode) {
                debugPrint(
                  'HIT_SUSTAIN_PROTECT ts=${elapsedMs.round()} midi=${decision.expectedMidi} '
                  'pc=$hitPitchClass window=${_sustainProtectionWindowMs}ms',
                );
              }

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

            // SESSION-056: S56 UIFeedbackEngine handles all visual feedback
            // This block only handles scoring - no flash logic needed
            if (decision.detectedMidi != null) {
              // ═══════════════════════════════════════════════════════════════
              // Sustain check ONLY if _lastHitAt exists
              // ═══════════════════════════════════════════════════════════════
              if (_lastHitAt != null) {
                // Skip if same MIDI as recent hit (<500ms) and not new onset
                final dtMs = now.difference(_lastHitAt!).inMilliseconds;
                final currentOnsetMs =
                    _micEngine?.lastOnsetTriggerElapsedMs ?? -10000.0;
                final isNewOnset =
                    (currentOnsetMs - _lastHitOnsetMs).abs() > 50.0;

                if (_lastHitMidi == decision.detectedMidi &&
                    dtMs < 500 &&
                    !isNewOnset) {
                  if (kDebugMode) {
                    debugPrint(
                      'SESSION4_SKIP_SUSTAIN_WRONG: Skip wrong midi=${decision.detectedMidi} '
                      '(same as recent hit, dt=${dtMs}ms, sameOnset=true)',
                    );
                  }
                  break; // Skip scoring
                }
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

              // Send to scoring controller (if enabled)
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
