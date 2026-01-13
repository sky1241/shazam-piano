# SESSION 4 CONTINUATION - HANDOFF POUR NOUVELLE SESSION AGENT

## 🎯 MISSION ACTUELLE

**Objectif**: Débugger le nouveau système de scoring Pitch/Timing/Sustain/Wrong implémenté en Session 4
**Statut**: Système implémenté et testé (50/50 tests pass), mais bugs visuels en runtime
**Prochaine étape**: Analyser la réponse de ChatGPT (analyse vidéo + logs) et corriger les bugs identifiés

---

## 📋 CONTEXTE COMPLET SESSION 4

### Travail accompli

**Création de 5 modules de scoring** (tous dans `app/lib/core/practice/`):

1. **`model/practice_models.dart`** (173 lignes)
   - `HitGrade` enum: perfect, good, ok, miss, wrong
   - `NoteSource` enum: microphone, midi
   - `ExpectedNote`: index, midi, tExpectedMs, durationMs
   - `PlayedNoteEvent`: id (UUID), midi, tPlayedMs, durationMs, source
   - `MatchCandidate`: expectedIndex, playedId, dtMs
   - `NoteResolution`: expectedIndex, grade, dtMs, pointsAdded, matchedPlayedId, sustainFactor
   - `PracticeScoringState`: totalScore, combo, maxCombo, counts (perfect/good/ok/miss/wrong), timingAbsDtSum, sustainFactorSum, timingP95AbsMs
   - Getters dérivés: accuracyPitch, timingAvgAbsMs, sustainAvgFactor

2. **`scoring/practice_scoring_engine.dart`** (206 lignes)
   - `ScoringConfig`: perfectMs=40, goodMs=100, okMs=200, perfectPts=100, goodPts=70, okPts=40
   - `PracticeScoringEngine.gradeFromDt()`: calcule grade selon timing
   - `computeMultiplier(combo)`: 1.0 + floor(combo/10)*0.1, cap 2.0x
   - `computeSustainFactor()`: ratio durée, clamp [0.7, 1.0]
   - `computeFinalPoints()`: grade * multiplier * sustainFactor
   - `applyResolution()`: mute PracticeScoringState
   - `applyWrongNotePenalty()`: wrongCount++, combo=0
   - `finalizeP95Timing()`: calcule p95 à la fin

3. **`matching/note_matcher.dart`** (167 lignes)
   - `NoteMatcher(windowMs, pitchEquals)`
   - `findBestMatch()`: cherche dans buffer ±windowMs, respecte exclusivité (alreadyUsedPlayedIds)
   - `micPitchMatch()`: pitch class + octave shifts (±12, ±24), tolerance ≤3
   - `midiPitchMatch()`: distance ≤1
   - `indexBufferByPitch()`: optimisation future (pas utilisé actuellement)

4. **`debug/practice_debug_logger.dart`** (262 lignes)
   - `DebugLogConfig`: enableLogs, maxBufferSize=1000
   - `PracticeDebugLogger.logResolveExpected()`: log résolutions notes
   - `logWrongPlayed()`: log wrong notes
   - `exportLogsAsJson()`: export complet
   - `getSessionSummary()`: stats session
   - Circular buffer avec rotation automatique

5. **`presentation/pages/practice/controller/practice_controller.dart`** (408 lignes)
   - `PracticeViewState`: isActive, scoringState, currentSessionId, currentNoteIndex, lastGrade
   - `PracticeController extends StateNotifier<PracticeViewState>`
   - `startPractice(sessionId, expectedNotes)`: init session
   - `onPlayedNote(event)`: lookahead 10 notes, matching + scoring
   - `onTimeUpdate(currentTimeMs)`: détection misses automatique
   - `stopPractice()`: finalise p95 timing
   - `currentScoringState` getter: accès public au state
   - `createPlayedEvent()` static: helper création événements

### Tests créés

**50 tests unitaires** (100% pass):
- `test/core/practice/scoring/practice_scoring_engine_test.dart`: 34 tests
  - Edge cases thresholds (39/40/41ms, 99/100/101ms, 199/200/201ms)
  - Combo multiplier (0→1.0x, 10→1.1x, 100→2.0x cap, 200→2.0x cap)
  - Sustain factor clamp [0.7, 1.0]
  - State mutations
  - Derived metrics (accuracy, avgTiming, avgSustain)

- `test/core/practice/matching/note_matcher_test.dart`: 16 tests
  - Closest dt wins
  - Exclusivity (1 event ne peut pas matcher 2 fois)
  - Window boundaries ±200ms
  - Pitch comparators (micPitchMatch, midiPitchMatch)

### Intégration dans practice_page.dart

**Fichier**: `app/lib/presentation/pages/practice/practice_page.dart` (5024 lignes après modifications)

**Changements clés**:

1. **Imports ajoutés** (lignes 28-36):
```dart
import '../../../core/practice/model/practice_models.dart';
import '../../../core/practice/scoring/practice_scoring_engine.dart';
import '../../../core/practice/matching/note_matcher.dart';
import '../../../core/practice/debug/practice_debug_logger.dart';
import 'controller/practice_controller.dart';
```

2. **Pitch comparators helpers** (lignes 40-66):
```dart
bool micPitchComparator(int detected, int expected) {
  final detectedPC = detected % 12;
  final expectedPC = expected % 12;
  if (detectedPC != expectedPC) return false;
  final shifts = [0, -12, 12, -24, 24];
  for (final shift in shifts) {
    if ((detected + shift - expected).abs() <= 3) return true;
  }
  return false;
}

bool midiPitchComparator(int detected, int expected) {
  return (detected - expected).abs() <= 1;
}
```

3. **Variables état** (lignes 328-332):
```dart
PracticeController? _newController; // New controller instance
final bool _useNewScoringSystem = true; // Flag to enable/disable new system
```

4. **Initialisation controller** (lignes 2261-2300):
```dart
if (_useNewScoringSystem) {
  final scoringConfig = ScoringConfig();
  final scoringEngine = PracticeScoringEngine(config: scoringConfig);
  final pitchComparator = _useMidi ? midiPitchComparator : micPitchComparator;
  final matcher = NoteMatcher(windowMs: 200, pitchEquals: pitchComparator);
  final debugConfig = DebugLogConfig(enableLogs: kDebugMode);
  final logger = PracticeDebugLogger(config: debugConfig);
  
  _newController = PracticeController(
    scoringEngine: scoringEngine,
    matcher: matcher,
    logger: logger,
  );
  
  // Convert _noteEvents to ExpectedNote format
  final expectedNotes = _noteEvents.asMap().entries.map((entry) {
    return ExpectedNote(
      index: entry.key,
      midi: entry.value.pitch,
      tExpectedMs: entry.value.start * 1000.0,
      durationMs: (entry.value.end - entry.value.start) * 1000.0,
    );
  }).toList();
  
  _newController!.startPractice(sessionId: '$sessionId', expectedNotes: expectedNotes);
}
```

5. **Hooks micro** (lignes 2660-2745):
```dart
// Pour chaque decision (hit/miss/wrongFlash) de mic_engine:
case mic.DecisionType.hit:
  if (_useNewScoringSystem && _newController != null && decision.detectedMidi != null) {
    // Capture state BEFORE
    final stateBefore = _newController!.currentScoringState;
    final correctCountBefore = stateBefore.perfectCount + stateBefore.goodCount + stateBefore.okCount;
    
    final playedEvent = PracticeController.createPlayedEvent(
      midi: decision.detectedMidi!,
      tPlayedMs: elapsed * 1000.0,
      source: NoteSource.microphone,
    );
    _newController!.onPlayedNote(playedEvent);
    
    // Check if NEW SYSTEM registered a correct hit
    final stateAfter = _newController!.currentScoringState;
    final correctCountAfter = stateAfter.perfectCount + stateAfter.goodCount + stateAfter.okCount;
    
    if (correctCountAfter > correctCountBefore) {
      // Flash green
      _registerCorrectHit(targetNote: decision.expectedMidi!, detectedNote: decision.detectedMidi!, now: now);
    }
  }
  // ... OLD SYSTEM fallback else { ... }

case mic.DecisionType.wrongFlash:
  if (_useNewScoringSystem && _newController != null && decision.detectedMidi != null) {
    // Similar logic for wrong notes
    // Check wrongCount before/after
    // Flash red if wrongCount increased
  }
```

6. **Hooks MIDI** (lignes 3670-3730):
```dart
if (_useNewScoringSystem && _newController != null) {
  // Capture state before
  final stateBefore = _newController!.currentScoringState;
  final correctCountBefore = stateBefore.perfectCount + stateBefore.goodCount + stateBefore.okCount;
  final wrongCountBefore = stateBefore.wrongCount;
  
  final playedEvent = PracticeController.createPlayedEvent(midi: note, tPlayedMs: elapsed * 1000.0, source: NoteSource.midi);
  _newController!.onPlayedNote(playedEvent);
  _newController!.onTimeUpdate(elapsed * 1000.0);
  
  // Check what NEW SYSTEM decided
  final stateAfter = _newController!.currentScoringState;
  final correctCountAfter = stateAfter.perfectCount + stateAfter.goodCount + stateAfter.okCount;
  final wrongCountAfter = stateAfter.wrongCount;
  
  if (correctCountAfter > correctCountBefore) {
    // Flash green
    _registerCorrectHit(targetNote: note, detectedNote: note, now: now);
  } else if (wrongCountAfter > wrongCountBefore) {
    // Flash red
    _registerWrongHit(detectedNote: note, now: now);
  }
}
```

7. **HUD display** (lignes 699-727):
```dart
if (_useNewScoringSystem && _newController != null) {
  // SESSION 4: Display NEW scoring system stats
  final newState = _newController!.currentScoringState;
  final matched = newState.perfectCount + newState.goodCount + newState.okCount;
  final precisionValue = _totalNotes > 0 ? '${(matched / _totalNotes * 100).toStringAsFixed(1)}%' : '0%';
  statsText = 'Précision: $precisionValue   Notes justes: $matched/$_totalNotes   Score: ${newState.totalScore}   Combo: ${newState.combo}';
  
  // Debug: Compare old vs new
  if (kDebugMode) {
    final oldPrecision = _totalNotes > 0 ? (_correctNotes / _totalNotes * 100) : 0.0;
    final newPrecision = _totalNotes > 0 ? (matched / _totalNotes * 100) : 0.0;
    if ((oldPrecision - newPrecision).abs() > 5.0 || (_score - newState.totalScore).abs() > 10) {
      debugPrint('SESSION4_SCORING_DIFF: old=(prec=${oldPrecision.toStringAsFixed(1)}% score=$_score) new=(prec=${newPrecision.toStringAsFixed(1)}% score=${newState.totalScore})');
    }
  }
} else {
  // Original scoring system
  statsText = 'Précision: $precisionValue   Notes justes: $_correctNotes/$_totalNotes   Score: $_score';
}
```

8. **Stop controller** (lignes 2468-2476):
```dart
if (_useNewScoringSystem && _newController != null) {
  _newController!.stopPractice();
  if (kDebugMode) {
    final state = _newController!.currentScoringState;
    debugPrint('SESSION4_CONTROLLER: Stopped. Final score=${state.totalScore}, combo=${state.combo}, p95=${state.timingP95AbsMs.toStringAsFixed(1)}ms');
  }
}
```

### Documentation créée

1. **`REPERAGE_SESSION4.md`** (520 lignes):
   - Analyse complète système existant (ÉTAPE 0)
   - Findings pitch matching, session ID, scoring, performance

2. **`SESSION4_PROGRESS_REPORT.md`**:
   - Rapport exécutif complet
   - Modules créés, tests, intégration
   - Validations effectuées
   - Checklist tests manuels (ÉTAPE 8)

3. **`SESSION4_PROMPT_SCORING_REFACTOR.md`** (861 lignes):
   - Spécifications complètes du nouveau système
   - Méthodologie Session 3 appliquée

4. **`practice_page_backup_session4.dart`**:
   - Backup complet avant modifications Session 4

### Commits récents

```
be17e71 - fix: Format Dart (practice_page.dart)
be265a9 - feat: Réactiver flashs visuels clavier basés sur nouveau système
e71694a - fix: Désactiver flashs visuels clavier quand nouveau système actif
686b655 - fix: Ajouter accolades manquantes (curly_braces_in_flow_control_structures)
f577e6f - fix: Format Dart files pour CI/CD
32c55ea - Session 4: Nouveau système de scoring Pitch/Timing/Sustain/Wrong + Tests
```

---

## 🐛 BUGS IDENTIFIÉS (À CORRIGER)

### Bug 1: HUD ne se met pas à jour
**Symptôme**: "Précision: 0% Notes justes: 0/X Score: 0 Combo: 0" reste figé
**Localisation**: Lignes 699-727 de practice_page.dart (méthode `_buildTopStatsLine()`)
**Hypothèses**:
- `_newController!.currentScoringState` ne se met pas à jour ?
- `setState()` pas appelé après changements ?
- Controller pas correctement initialisé ?

### Bug 2: Notes rouges fantômes (environnement silencieux)
**Symptôme**: Touches rouges alors qu'aucun son n'est joué
**Localisation**: 
- Lignes 2720-2745 (wrongFlash micro)
- Détection audio mic_engine.dart (mais INCHANGÉ donc suspect)
**Hypothèses**:
- Seuil `absMinRms` trop bas (0.0020) ?
- `wrongCount` augmente sans raison (bug dans matcher ?) ?
- Ancien système interfère avec nouveau ?

### Bug 3: Sapin de Noël après appui long
**Symptôme**: Après quelques secondes d'appui, toutes les touches clignotent rouge
**Localisation**: Lignes 2667-2745 (comparaison counts avant/après)
**Hypothèses**:
- Événement `onPlayedNote()` appelé en boucle pour même note ?
- `wrongCount` incrémenté à répétition ?
- Buffer de notes détectées non vidé ?

### Bug 4: Résultats finaux à 0%
**Symptôme**: Dialog de fin affiche Précision: 0%, Score: 0, Combo: 0
**Localisation**: 
- Lignes 4385-4395 (dialog score)
- Lignes 2460-2470 (_sendPracticeSession)
**Hypothèses**:
- Dialog utilise encore `_correctNotes` et `_score` (ancien système) ?
- Devrait utiliser `_newController!.currentScoringState` ?

### Bug 5: Comportement OK (note positive)
**Observation**: Quand touche reste appuyée, elle reste rouge → correct
**Pas un bug**: Confirme que `_registerWrongHit()` fonctionne correctement

---

## 📥 RÉPONSE CHATGPT ATTENDUE

ChatGPT aura analysé:
1. **Vidéo**: Comportement visuel des bugs
2. **Fichier `logcatdebug`**: Logs Flutter + debug prints

**Format de réponse attendu** (voir `PROMPT_CHATGPT_VIDEO_ANALYSIS.md`):

### Partie 1: Résumé visuel
- HUD se met à jour: OUI / NON / PARTIELLEMENT
- Flashs rouges fantômes: OUI / NON - Fréquence: X/sec
- Sapin de Noël après: X secondes d'appui
- Dialog final affiche: Valeurs correctes / Valeurs à 0 / Erreur

### Partie 2: Analyse logs critique
- 20 lignes les plus pertinentes du log
- Patterns détectés:
  - Nombre de "wrongFlash": X
  - Nombre de "onPlayedNote": X
  - Score final controller: X
  - RMS moyen détections: X

### Partie 3: Diagnostic bugs
Pour chaque bug (1-5):
- Cause racine probable
- Ligne(s) de code suspecte(s)
- Preuve dans logs (extrait)
- Preuve dans vidéo (timestamp + description)

### Partie 4: Recommandations correctifs
Classés par priorité (P0/P1/P2):
1. **[P0/P1/P2]** Bug X: Action à prendre
2. **[P0/P1/P2]** Bug Y: Action à prendre

---

## 🔧 ACTIONS À PRENDRE (APRÈS RÉCEPTION RÉPONSE CHATGPT)

### Étape 1: Analyser la réponse ChatGPT
- Lire attentivement chaque diagnostic
- Identifier les causes racines confirmées
- Noter les lignes de code problématiques
- Prioriser les bugs (P0 d'abord)

### Étape 2: Ajouter debug logs si nécessaire
Si ChatGPT n'a pas trouvé assez de logs, ajouter:

```dart
// Dans practice_page.dart, lignes 2667-2690 (hooks micro hit):
debugPrint('SESSION4_DEBUG: Before onPlayedNote - correctCount=$correctCountBefore, wrongCount=$wrongCountBefore');
_newController!.onPlayedNote(playedEvent);
debugPrint('SESSION4_DEBUG: After onPlayedNote - correctCount=$correctCountAfter, wrongCount=$wrongCountAfter');

// Dans practice_page.dart, lignes 2720-2740 (hooks micro wrongFlash):
debugPrint('SESSION4_DEBUG: Before onPlayedNote(wrong) - wrongCount=$wrongCountBefore');
_newController!.onPlayedNote(playedEvent);
debugPrint('SESSION4_DEBUG: After onPlayedNote(wrong) - wrongCount=$wrongCountAfter');

// Dans practice_page.dart, lignes 699-727 (HUD):
debugPrint('SESSION4_DEBUG: HUD update - matched=$matched, totalNotes=$_totalNotes, score=${newState.totalScore}, combo=${newState.combo}');
```

### Étape 3: Corriger bugs par priorité

**Bug P0 typique: HUD ne se met pas à jour**
Vérifier:
1. `_newController` est-il null ?
2. `currentScoringState` retourne-t-il les bonnes valeurs ?
3. `setState()` est-il appelé après modifications ?
4. Widget `_buildTopStatsLine()` est-il rebuild ?

Solution probable:
```dart
// Dans _buildTopStatsLine(), forcer setState après lecture state:
if (_useNewScoringSystem && _newController != null) {
  final newState = _newController!.currentScoringState;
  // ... construire statsText ...
  
  // Déclencher rebuild si valeurs ont changé
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() {});
  });
}
```

**Bug P0 typique: Dialog final à 0%**
Le dialog utilise probablement encore ancien système:
```dart
// Ligne 2460-2470 dans _stopPractice():
if (_useNewScoringSystem && _newController != null) {
  final newState = _newController!.currentScoringState;
  final matched = newState.perfectCount + newState.goodCount + newState.okCount;
  score = newState.totalScore.toDouble();
  accuracy = _totalNotes > 0 ? (matched / _totalNotes * 100.0) : 0.0;
} else {
  score = _score;
  accuracy = total > 0 ? (_score / total) * 100.0 : 0.0;
}
```

**Bug P1 typique: Notes rouges fantômes**
Vérifier seuil RMS:
```dart
// Ligne 2256 dans _startPractice():
absMinRms: 0.0020, // Augmenter à 0.0050 ou 0.0100 ?
```

Ou ajouter filtre temporel:
```dart
// Dans hooks micro, éviter flashs trop fréquents:
final now = DateTime.now();
if (_lastWrongFlashAt != null && now.difference(_lastWrongFlashAt!) < Duration(milliseconds: 500)) {
  return; // Ignore si dernier flash < 500ms
}
_lastWrongFlashAt = now;
```

**Bug P1 typique: Sapin de Noël**
Problème probable: même note génère plusieurs événements
```dart
// Dans hooks micro, ligne 2667-2690:
// Ajouter cache dernière note traitée
int? _lastProcessedMidi;
DateTime? _lastProcessedAt;

if (_useNewScoringSystem && _newController != null && decision.detectedMidi != null) {
  // Éviter traiter même note < 200ms
  if (_lastProcessedMidi == decision.detectedMidi && 
      _lastProcessedAt != null && 
      now.difference(_lastProcessedAt!) < Duration(milliseconds: 200)) {
    break; // Skip duplicate
  }
  
  _lastProcessedMidi = decision.detectedMidi;
  _lastProcessedAt = now;
  
  // ... reste du code ...
}
```

### Étape 4: Tester après chaque correction
```powershell
flutter analyze --no-fatal-infos
flutter test --no-pub
flutter run
```

### Étape 5: Commit + push après validation
```powershell
git add -A
git commit -m "fix(session4): [Description précise du bug corrigé]"
git push
```

---

## 📁 FICHIERS CRITIQUES À CONNAÎTRE

### Scoring system (core)
- `app/lib/core/practice/model/practice_models.dart`
- `app/lib/core/practice/scoring/practice_scoring_engine.dart`
- `app/lib/core/practice/matching/note_matcher.dart`
- `app/lib/core/practice/debug/practice_debug_logger.dart`
- `app/lib/presentation/pages/practice/controller/practice_controller.dart`

### Integration (UI)
- `app/lib/presentation/pages/practice/practice_page.dart` (5024 lignes)
- `app/lib/presentation/pages/practice/mic_engine.dart` (555 lignes, INCHANGÉ)

### Tests
- `app/test/core/practice/scoring/practice_scoring_engine_test.dart` (34 tests)
- `app/test/core/practice/matching/note_matcher_test.dart` (16 tests)

### Documentation
- `REPERAGE_SESSION4.md` (findings système existant)
- `SESSION4_PROGRESS_REPORT.md` (rapport complet)
- `SESSION4_PROMPT_SCORING_REFACTOR.md` (specs)
- `PROMPT_CHATGPT_VIDEO_ANALYSIS.md` (prompt pour ChatGPT)
- `HANDOFF_SESSION4_CONTINUATION.md` (ce fichier, pour toi)

---

## ⚠️ RÈGLES STRICTES (AGENTS.md)

**Interdits sans accord explicite**:
- Nouveaux packages (pubspec/requirements)
- Refactor global
- Renommages/déplacements massifs
- >6 fichiers modifiés par tâche

**Flux de réponse obligatoire**:
PLAN (≤6 lignes) → CHANGEMENTS (diff/fichiers) → VÉRIFICATION (commandes) → TEST MANUEL (≤5 étapes)

**Flutter (`app/`)**:
- Respecter Riverpod et structure lib/core|data|domain|presentation
- Null-safety stricte, éviter `dynamic`/`!` sans justification
- Audio/streaming: gérer permissions, stop/cancel, timeout

**Backend (`backend/`)**:
- Pas de refonte lourde
- Gérer erreurs/logs proprement

**Git**:
- Utiliser `git mv` pour déplacements (conserver historique)
- Pas de nouveaux packages sans feu vert

---

## 🎯 RÉSUMÉ POUR DÉMARRAGE RAPIDE

**Tu es en Session 4 - Phase correction bugs**

**Déjà fait**:
- ✅ 5 modules scoring créés (1216 lignes)
- ✅ 50 tests unitaires (100% pass)
- ✅ Intégration complète dans practice_page.dart
- ✅ Système tourne en parallèle avec ancien (dual system)
- ✅ Build CI/CD passé (flutter analyze + test)

**Bugs runtime**:
- 🐛 HUD ne se met pas à jour (reste à 0)
- 🐛 Notes rouges fantômes (environnement silencieux)
- 🐛 Sapin de Noël après appui long
- 🐛 Dialog final à 0%

**Prochaine action**:
1. L'utilisateur a envoyé vidéo + logs à ChatGPT via `PROMPT_CHATGPT_VIDEO_ANALYSIS.md`
2. ChatGPT va analyser et répondre aux questions (diagnostics précis)
3. **TOI**: Tu vas recevoir la réponse de ChatGPT
4. **TOI**: Tu vas corriger les bugs selon diagnostics ChatGPT
5. **TOI**: Tester, commit, push

**Flag important**: `_useNewScoringSystem = true` (ligne 330 de practice_page.dart)

**Workspace**: `c:\Users\ludov\OneDrive\Bureau\shazam piano\shazam-piano`

Bon courage ! 🚀
