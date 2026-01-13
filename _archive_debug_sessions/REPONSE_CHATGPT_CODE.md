# RÉPONSE CHATGPT — CODE DEMANDÉ (±80 lignes)

## ✅ CONFIRMATION: Oui, ton analyse ira très bien!

Les 3 bugs détectés sont **correctement identifiés** dans les logs. Voici le code exact pour que tu puisses fournir le patch.

---

## 📦 CODE SECTION 1 — `onPlayedNote()` (Traitement mic → matching)

**Fichier**: `app/lib/presentation/pages/practice/controller/practice_controller.dart`  
**Lignes**: 142-203

```dart
  /// Handle a played note event (mic or MIDI)
  ///
  /// This is the core matching + scoring logic:
  /// 1. Validate session
  /// 2. Add to buffer
  /// 3. Try to match with expected notes
  /// 4. If matched: resolve hit/miss, update score
  /// 5. If no match: mark as wrong (with caution)
  void onPlayedNote(PlayedNoteEvent event) {
    if (!state.isActive || _currentSessionId != state.currentSessionId) {
      // Stale event from previous session, ignore
      return;
    }

    // Add to buffer
    _playedBuffer.add(event);

    // Try to match with upcoming expected notes
    // We scan from _nextExpectedIndex up to a reasonable lookahead
    // (e.g., 10 notes ahead) to handle early hits
    final lookahead = 10;
    final scanEndIndex = (_nextExpectedIndex + lookahead).clamp(
      0,
      _expectedNotes.length,
    );

    for (var i = _nextExpectedIndex; i < scanEndIndex; i++) {
      final expected = _expectedNotes[i];

      // Check if this expected note is in range of the played event
      final dt = event.tPlayedMs - expected.tExpectedMs;
      if (dt < -_matcher.windowMs) {
        // Played note is too early for this expected note
        // (and all subsequent ones), stop scanning
        break;
      }

      // Try to match
      final candidate = _matcher.findBestMatch(
        expected,
        [event], // Only check this new event
        _consumedPlayedIds,
      );

      if (candidate != null) {
        // Match found!
        _resolveExpectedNote(
          expectedIndex: i,
          matchedEvent: event,
          dtMs: candidate.dtMs,
        );

        // Mark as consumed
        _consumedPlayedIds.add(event.id);
        return; // Done processing this event
      }
    }

    // No match found
    // CRITICAL: Only mark as WRONG if we're confident it's not a future hit
    // For now, we just buffer it. Wrong notes are detected in onTimeUpdate
    // when we move past the time window.
  }
```

---

## 📦 CODE SECTION 2 — `onTimeUpdate()` (Détection MISS + WRONG)

**Fichier**: `app/lib/presentation/pages/practice/controller/practice_controller.dart`  
**Lignes**: 205-267

```dart
  /// Update current time (called every frame or regularly)
  ///
  /// Checks for missed notes (time passed beyond window)
  void onTimeUpdate(double currentTimeMs) {
    if (!state.isActive) return;

    // Process all expected notes that are now "late" (missed)
    while (_nextExpectedIndex < _expectedNotes.length) {
      final expected = _expectedNotes[_nextExpectedIndex];

      // FIX BUG P0-A (SESSION4): Ne déclarer miss que si latence + window dépassés
      // Avant: currentTimeMs > expected.tExpectedMs + windowMs
      // Après: currentTimeMs > expected.tExpectedMs + windowMs + _micLatencyMs
      // Raison: event micro stable arrive ~300ms après note jouée
      if (currentTimeMs >
          expected.tExpectedMs + _matcher.windowMs + _micLatencyMs) {
        // Check if it was already matched
        final wasMatched = _consumedPlayedIds.any((id) {
          return _playedBuffer
              .where((e) => e.id == id)
              .any((e) => _isMatchForExpected(e, expected));
        });

        if (!wasMatched) {
          // Miss!
          _resolveExpectedNote(
            expectedIndex: _nextExpectedIndex,
            matchedEvent: null,
            dtMs: null,
          );
        }

        _nextExpectedIndex++;
      } else {
        // This note is still in range, stop scanning
        break;
      }
    }

    // Check for wrong notes (played events that never matched)
    // Only consider events that are now outside all possible windows
    final minExpectedTime = _nextExpectedIndex < _expectedNotes.length
        ? _expectedNotes[_nextExpectedIndex].tExpectedMs
        : double.infinity;

    final wrongCandidates = _playedBuffer.where((event) {
      // Already consumed? Not wrong
      if (_consumedPlayedIds.contains(event.id)) return false;

      // Too early to judge? (might match a future note)
      if (event.tPlayedMs + _matcher.windowMs >= minExpectedTime) {
        return false;
      }

      // This event is now definitively wrong
      return true;
    }).toList();

    // Handle each wrong note
    for (final event in wrongCandidates) {
      _handleWrongNote(event);
      _consumedPlayedIds.add(event.id); // Mark as handled
    }
  }
```

---

## 📦 CODE SECTION 3 — `_handleWrongNote()` (Décision WRONG)

**Fichier**: `app/lib/presentation/pages/practice/controller/practice_controller.dart`  
**Lignes**: 349-369

```dart
  /// Handle a wrong note (played but never matched)
  void _handleWrongNote(PlayedNoteEvent event) {
    _scoringEngine.applyWrongNotePenalty(_scoringState);

    _logger.logWrongPlayed(
      sessionId: _currentSessionId!,
      playedId: event.id,
      pitchKey: event.midi,
      tPlayedMs: event.tPlayedMs,
      reason: 'No matching expected note within window',
    );

    // Update UI
    state = state.copyWith(
      lastGrade: HitGrade.wrong,
      scoringState: _scoringState,
    );
  }
```

---

## 📦 CODE SECTION 4 — `_isMatchForExpected()` (Helper matching)

**Fichier**: `app/lib/presentation/pages/practice/controller/practice_controller.dart`  
**Lignes**: 371-379

```dart
  /// Helper: check if a played event corresponds to an expected note
  bool _isMatchForExpected(PlayedNoteEvent event, ExpectedNote expected) {
    final dt = (event.tPlayedMs - expected.tExpectedMs).abs();
    if (dt > _matcher.windowMs) return false;

    return _matcher.pitchEquals(event.midi, expected.midi);
  }
```

---

## 📦 CODE BONUS — Constantes importantes

**Fichier**: `app/lib/presentation/pages/practice/controller/practice_controller.dart`  
**Lignes**: 70-76

```dart
  // FIX BUG P0-A (SESSION4): Latence micro compensation
  // Problème: onTimeUpdate() résolvait miss trop tôt (avant arrivée event stable)
  // Solution: Ajouter latence micro (~300ms) avant de déclarer miss
  // ChatGPT analysis: dt observés = 0.259-0.485s (moyenne ~300ms)
  static const double _micLatencyMs = 300.0;

  // Session state
  String? _currentSessionId;
  List<ExpectedNote> _expectedNotes = [];
  List<PlayedNoteEvent> _playedBuffer = [];
  Set<String> _consumedPlayedIds = {};
  int _nextExpectedIndex = 0;
```

---

## 🔍 CONTEXTE IMPORTANT

### NoteMatcher (`_matcher.findBestMatch()`)
**Fichier**: `app/lib/core/practice/matching/note_matcher.dart`

Le matcher actuel:
- ✅ **Distance ≤3 demi-tons** autorisée (60→63 OK)
- ❌ **Distance >3** rejetée (60→72 NOK, **48→60 NOK**)
- ❌ **Octave shifts désactivés** (commit ec8d304)

**C'est ici le problème BUG #1**: `midi=48` vs `expected=60` → distance=12 → REJECT

---

## 🎯 ZONES CRITIQUES POUR TES PATCHES

### BUG #1 (Octave subharmonic) — Injection avant matching
**Où injecter ton helper `maybeFixDownOctave()`**:

**Ligne 184** dans `onPlayedNote()`, **AVANT** l'appel `_matcher.findBestMatch()`:

```dart
// Try to match
final candidate = _matcher.findBestMatch(
  expected,
  [event], // Only check this new event  ← INJECT ICI
  _consumedPlayedIds,
);
```

**Modification suggérée**:
```dart
// PATCH BUG #1: Corriger octave basse avant matching
final correctedEvent = maybeFixDownOctave(
  playedEvent: event,
  activeExpected: _expectedNotes.sublist(_nextExpectedIndex, scanEndIndex),
  maxSemitoneDistance: 3,
);

// Try to match avec event corrigé
final candidate = _matcher.findBestMatch(
  expected,
  [correctedEvent],
  _consumedPlayedIds,
);
```

---

### BUG #2 (WRONG trop agressif) — Modifier `_handleWrongNote()`

**Ligne 349-369**, ajouter vérification pitch-class avant déclencher WRONG:

```dart
void _handleWrongNote(PlayedNoteEvent event) {
  // PATCH BUG #2: Vérifier si pitch-class proche notes actives
  final activeExpected = _expectedNotes
      .where((e) => (e.tExpectedMs - event.tPlayedMs).abs() < _matcher.windowMs * 2)
      .toList();
  
  final activePitchClasses = activeExpected.map((e) => e.midi % 12).toSet();
  final playedPitchClass = event.midi % 12;
  
  if (activePitchClasses.contains(playedPitchClass)) {
    // Même pitch-class qu'une note attendue → "near miss" (pas WRONG)
    // Log comme MISS soft au lieu de WRONG
    _logger.logNearMiss( // ← Créer cette méthode ou log différent
      sessionId: _currentSessionId!,
      playedId: event.id,
      pitchKey: event.midi,
      tPlayedMs: event.tPlayedMs,
      reason: 'Pitch-class match but distance/timing rejected (likely technical issue)',
    );
    return; // Ne pas appliquer penalty WRONG
  }
  
  // Sinon: vrai WRONG (note complètement hors contexte)
  _scoringEngine.applyWrongNotePenalty(_scoringState);
  
  _logger.logWrongPlayed(
    sessionId: _currentSessionId!,
    playedId: event.id,
    pitchKey: event.midi,
    tPlayedMs: event.tPlayedMs,
    reason: 'No matching expected note within window',
  );
  
  state = state.copyWith(
    lastGrade: HitGrade.wrong,
    scoringState: _scoringState,
  );
}
```

---

### BUG #3 (Logs trompeurs) — Logs additionnels

**Ajouter dans `onPlayedNote()` ligne 184** (avant `_matcher.findBestMatch()`):

```dart
// DEBUG BUG #3: Log buffer state avant matching
debugPrint('SESSION4_BUFFER_STATE: '
    'eventsInBuffer=${_playedBuffer.length} '
    'unconsumed=${_playedBuffer.where((e) => !_consumedPlayedIds.contains(e.id)).length} '
    'expectedIndex=$i expectedMidi=${expected.midi}');

final candidate = _matcher.findBestMatch(...);

// DEBUG: Log résultat matching avec détails filtrage
if (candidate == null) {
  debugPrint('SESSION4_MATCH_FAIL: '
      'playedMidi=${event.midi} '
      'expectedMidi=${expected.midi} '
      'reason=no_match_after_filters '
      'distance=${(event.midi - expected.midi).abs()}');
}
```

---

## ✅ QUESTIONS CLARIFICATION (Tu as demandé)

### Q1: Le morceau est-il majoritairement C4→C5 (midi ~60–72)?
**Réponse basée sur logs**: OUI
- Logs montrent `expectedMidi=60` (C4) comme référence
- Range notes attendues semble être autour 60-72

### Q2: Le micro capte-t-il octave basse (C3) systématiquement?
**Réponse basée sur logs**: OUI, au moins dans ce cas
- `bestEvent=midi=48 freq=130.8` (C3) alors que `expectedMidi=60` (C4)
- Pattern typique subharmonic detection (détecteur FFT voit octave basse plus fort)

---

## 🚀 PROCHAINES ÉTAPES

1. **Tu génères les patches** pour BUG #1 (helper octave) + BUG #2 (WRONG soft)
2. **Je les applique** avec workflow AGENTS.md (≤6 fichiers)
3. **Tests validation**:
   ```bash
   flutter test app/test/core/practice/matching/note_matcher_test.dart
   flutter test app/test/core/practice/scoring/practice_scoring_engine_test.dart
   flutter analyze
   ```
4. **Test manuel** avec logs:
   ```bash
   .\scripts\dev.ps1 -Logcat
   grep "SESSION4_OCTAVE_FIX" logcatdebug  # Doit apparaître
   grep "WRONG_NOTE" logcatdebug           # Doit diminuer drastiquement
   ```

---

**MERCI CHATGPT! Génère tes patches et je suis prêt à les appliquer! 🔥**
