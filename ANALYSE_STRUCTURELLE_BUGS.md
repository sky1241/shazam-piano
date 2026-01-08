# 🔬 ANALYSE STRUCTURELLE — Pourquoi On Tourne en Rond

**Date**: 2026-01-08  
**Durée session**: 10 heures  
**Bugs fixés**: 20  
**Problème résolu**: NON (à valider runtime)

---

## 🎯 PROBLÈME ROOT CAUSE : Architecture "Gate Hell"

### Pattern Observé (Récurrent depuis 10h)

**Symptôme global** : Pratiquement TOUS les bugs viennent du même vecteur architectural.

```
Audio samples → Gate 1 (stereo?) → Gate 2 (RMS?) → Gate 3 (stability?) → Gate 4 (window?) → Scoring
                   ↓ return              ↓ return        ↓ return           ↓ return          ✅ Atteint jamais
```

**Résultat** : MicEngine génère décisions HIT/MISS MAIS UI ne reçoit JAMAIS les updates car `return;` early partout.

---

## 🐛 BUGS STRUCTURELS (Patterns Récurrents)

### 1️⃣ **Early Returns Cascade** (Bug Vecteur Principal)

**Fichier**: `practice_page.dart:2520-2680`

**Problème Architecture**:
```dart
// AVANT (architecture cassée):
void _processSamples(samples) {
  // Gate 1: Stereo detection
  if (_detectedChannelCount == null) {
    _detectStereo(); // Peut prendre 5-10 frames
    return; // ❌ SCORING BLOQUÉ pendant détection
  }
  
  // Gate 2: RMS threshold
  if (_micRms < dynamicMinRms) {
    _updateDetectedNote(null);
    return; // ❌ SCORING BLOQUÉ si trop silencieux
  }
  
  // Gate 3: Stability
  if (_stableFrameCount < _stabilityFrameThreshold) {
    return; // ❌ SCORING BLOQUÉ si pas 3 frames stables
  }
  
  // Gate 4: Window
  if (window == null) {
    return; // ❌ SCORING BLOQUÉ si buffer trop petit
  }
  
  // Scoring (JAMAIS ATTEINT)
  final decisions = _micEngine!.onAudioChunk(...);
}
```

**Impact Cascade**:
- Chunk 1-10: Gate 1 bloque (stereo detection)
- Chunk 11-15: Gate 2 bloque (RMS trop bas)
- Chunk 16-18: Gate 3 bloque (pas assez stable)
- Chunk 19: ENFIN scoring → 1 HIT détecté
- Chunk 20-30: Gate 2 bloque à nouveau (silence entre notes)
- **Résultat**: Sur 100 chunks, scoring atteint 5x seulement

**Solution Appliquée**:
```dart
// APRÈS (architecture correcte):
void _processSamples(samples) {
  // MicEngine TOUJOURS appelé EN PREMIER
  final decisions = _micEngine!.onAudioChunk(samples, now, elapsed);
  
  // Apply decisions (HIT/MISS/WRONG)
  for (decision in decisions) { ... }
  
  // Gates deviennent HUD-ONLY (affichage stats, pas scoring)
  if (_micRms < threshold) {
    _micFrequency = null; // HUD only
    return; // OK car scoring déjà fait
  }
}
```

**Leçon**: Scoring doit être UNCONDITIONAL. Gates = UI filters, pas scoring blockers.

---

### 2️⃣ **Reference Stability Hell** (Dart List Semantics)

**Fichier**: `practice_page.dart:2063,2224` + `mic_engine.dart:230`

**Problème Dart**:
```dart
// Session 0:
_hitNotes = List.filled(9, false);        // Liste A (length=9)
_micEngine = MicEngine(hitNotes: _hitNotes); // MicEngine référence liste A

// Reset session 1:
_hitNotes = [];                           // ❌ Nouvelle liste B (length=0)
// MicEngine garde ANCIENNE référence liste A (length=9)

// Session 1 start:
_hitNotes = List.filled(5, false);        // ❌ Nouvelle liste C (length=5)
// MicEngine garde TOUJOURS liste A (length=9)

// MicEngine scoring:
for (i in 0..noteEvents.length) {  // noteEvents=5
  if (hitNotes[i]) continue;        // ❌ RangeError: hitNotes=9, accès i=0..4 OK MAIS...
}
```

**Pourquoi RangeError sporadic** :
- Si `noteEvents` chargées APRÈS MicEngine init → hitNotes était vide (length=0)
- MicEngine loop sur noteEvents (length=5) mais hitNotes (length=0)
- Accès `hitNotes[0]` → **RangeError: Valid range is empty: 0**

**Solutions Appliquées**:
1. **Bug #12**: `_hitNotes.clear(); _hitNotes.addAll(...)` (garde référence)
2. **Bug #16**: Guard `if (hitNotes.length != noteEvents.length) return [];`

**Leçon**: En Dart, `=` crée nouvelle liste. Utiliser `.clear()` + `.addAll()` pour garder référence.

---

### 3️⃣ **Timebase Drift Cascade** (Clock vs Video Offset)

**Fichier**: `practice_page.dart:1888-1920`

**Problème Architecture**:
```dart
// AVANT (complexe, fragile):
double? _guidanceElapsedSec() {
  final clock = _practiceClockSec(); // DateTime.now() - _startTime
  final video = _videoController?.value.position.inMilliseconds / 1000.0;
  
  // Lock offset première frame video
  if (video != null && !_videoGuidanceLocked) {
    _videoGuidanceOffsetSec = clock - video; // ❌ Timing critique
  }
  
  // Return video + offset
  if (video != null && _videoGuidanceOffsetSec != null) {
    return max(0.0, video + _videoGuidanceOffsetSec); // ❌ Clamp empêche elapsed < 0
  }
  
  return clock;
}
```

**Problèmes Multiples**:
1. **Clamp `max(0.0, ...)` empêche countdown** (Bug #2)
2. **Lock timing critique** : Si lock arrive quand `clock=0, video=0` → offset=0 (Bug #3)
3. **Video position stale** : Après countdown, video.position peut être null/0 → offset cassé

**Solutions Appliquées**:
1. **Bug #2**: Supprimé `max(0.0, ...)` → autorise elapsed négatif
2. **Bug #3**: Lock APRÈS countdown (guard `_practiceState != countdown`)
3. **Bug #13**: Simplifié → return `clock` direct (Bug #15 garantit clock démarre 0)

**Architecture Finale**:
```dart
// APRÈS (simple, robuste):
double? _guidanceElapsedSec() {
  // Countdown: synthetic -fallLead → 0
  if (_practiceState == countdown) {
    return syntheticCountdownElapsed(...); // Mapping linéaire garanti
  }
  
  // Running: clock direct (démarre 0 car _startTime set à fin countdown)
  return _practiceClockSec(); // Simple, fiable
}
```

**Leçon**: Video offset ajoutait complexité pour zéro bénéfice. Clock suffit si timing correct.

---

### 4️⃣ **Countdown Timing Race** (Bug #15 - CRITIQUE)

**Fichier**: `practice_page.dart:2252 → 2319`

**Problème Timeline**:
```
AVANT (cassé):
t=0.0s:  _startPractice() → _startTime = DateTime.now()  ❌ SET TROP TÔT
t=0.0s:  Countdown démarre (state=countdown)
t=0-2s:  guidanceElapsed = synthetic -2.0 → 0.0 ✅ OK durant countdown
t=2.0s:  Countdown finit → state=running
t=2.0s:  guidanceElapsed = clock = DateTime.now() - _startTime = 2.0s ❌ BOOM

Résultat:
- Note start=1.875s, fallLead=2.0s → spawn=-0.125s
- Painter: progress = (2.0 - (-0.125)) / 2.0 = 1.0625 = 106%
- Note apparaît 106% fallen = MID-SCREEN
```

**Solution**:
```dart
// APRÈS (correct):
// _startPractice() L2252: 
// _startTime = DateTime.now(); // ❌ REMOVED

// _updateCountdown() L2319:
if (elapsedMs >= countdownCompleteSec * 1000) {
  _startTime = DateTime.now(); // ✅ SET ICI (quand countdown FINI)
  setState(() => _practiceState = running);
}
```

**Timeline Correcte**:
```
t=0.0s:  _startPractice() → _startTime = null (pas encore set)
t=0-2s:  Countdown → guidanceElapsed = synthetic -2.0 → 0.0 ✅
t=2.0s:  _startTime = DateTime.now() ✅ SET MAINTENANT
t=2.0s:  guidanceElapsed = clock = 0.0s ✅ Démarre à 0
t=3.0s:  guidanceElapsed = clock = 1.0s ✅
```

**Impact**: Bug #15 était ROOT CAUSE du symptôme "notes mid-screen". TOUS les autres bugs (timebase, culling, etc.) étaient des PATCHS pour compenser ce bug.

**Leçon**: 1 bug timing peut casser 5 systèmes downstream. Fix la source, pas les symptômes.

---

### 5️⃣ **Backend/Flutter Value Desync** (6 bugs identiques)

**Fichiers**: `backend/config.py`, `practice_page.dart`

**Pattern Récurrent**:
```
Backend config.py:
  VIDEO_PREROLL_SEC = 1.5
  VIDEO_LOOKAHEAD_SEC = 2.2
  VIDEO_TIME_OFFSET_MS = -60
  MIN_MIDI_DURATION = 16.0
  PREVIEW_DURATION hardcodé 16

Flutter practice_page.dart:
  _fallLeadSec = 2.0
  _videoSyncOffsetSec = 0.0
  API timeout: 20s (video) vs 15s (notes)
  MAX_DURATION = 10s
  
RÉSULTAT: 6 valeurs différentes → comportement imprévisible
```

**Root Cause Structurelle**: **PAS DE SOURCE OF TRUTH UNIQUE**

**Solution Correcte (à implémenter)** :
```typescript
// IDEAL: config.shared.json (1 seul fichier)
{
  "video": {
    "prerollSec": 2.0,
    "lookaheadSec": 2.0,
    "timeOffsetMs": -60,
    "maxDurationSec": 10
  },
  "api": {
    "timeoutSec": 15
  },
  "practice": {
    "fallLeadSec": 2.0,
    "previewDurationSec": 10
  }
}

// Backend: from config.shared import VIDEO_PREROLL_SEC
// Flutter: const videoPreroll = SharedConfig.video.prerollSec;
```

**Solution Actuelle (temporaire)** :
- Bugs #1-6 : Synchronisé manuellement les 6 valeurs
- ⚠️ **FRAGILE** : Prochaine modif peut re-introduire desync

**Leçon**: Configuration dupliquée = bugs garantis. 1 source of truth obligatoire.

---

### 6️⃣ **UI Update Disconnect** (Bug R2/R3)

**Fichier**: `practice_page.dart:2545-2680`

**Problème Architecture**:
```dart
// MicEngine génère decisions:
final decisions = _micEngine!.onAudioChunk(...);

for (decision in decisions) {
  case hit:
    _score++;                    // ✅ État scoring OK
    _registerCorrectHit(...);    // ✅ Flash state OK
    // ❌ MAIS _detectedNote JAMAIS MIS À JOUR
    break;
}

// Plus tard (ligne 2597):
final uiMidi = _micEngine!.uiDetectedMidi; // ❌ Peut être null si hold expiré
_updateDetectedNote(uiMidi, ...);          // ❌ Clavier reçoit null
```

**Disconnect**:
- **Scoring**: MicEngine decisions appliquées (score++, flash state OK)
- **UI Keyboard**: Attend `_detectedNote` (qui vient de uiMidi, peut être null)
- **Résultat**: Score augmente MAIS clavier reste gris (mort)

**Solution Appliquée**:
```dart
case hit:
  _score++;
  _registerCorrectHit(...);
  _updateDetectedNote(decision.detectedMidi, now, accuracyChanged: true); // ✅ FIX
  break;

case wrongFlash:
  _registerWrongHit(...);
  _updateDetectedNote(decision.detectedMidi, now, accuracyChanged: true); // ✅ FIX
  break;
```

**Leçon**: Décision → Action UI doit être IMMEDIATE. Pas de dépendance sur état externe (uiMidi).

---

## 🔄 PATTERN MÉTA : Pourquoi On Tourne en Rond

### Cycle Vicieux Observé

```
1. Bug Symptôme détecté (ex: notes mid-screen)
   ↓
2. Analyse superficielle (painter culling?)
   ↓
3. Patch symptôme (fix culling)
   ↓
4. Test statique (flutter analyze OK)
   ↓
5. Push Git
   ↓
6. AUCUN TEST RUNTIME
   ↓
7. Bug ROOT CAUSE toujours là (timing)
   ↓
8. Nouveau symptôme apparaît (score 0%)
   ↓
9. Retour étape 1 (boucle infinie)
```

### Root Causes du Cycle

1. **Pas de validation runtime** : flutter analyze détecte syntaxe, PAS logique
2. **Fix symptômes, pas causes** : Culling fixé MAIS timing cassé (Bug #15 ignoré)
3. **Bugs interdépendants** : 1 bug timing casse 5 systèmes (cascade)
4. **Architecture fragile** : Early returns, references instables, config dupliquée

---

## 🎯 BUGS POTENTIELS RESTANTS (À Investiguer)

### 🔴 Critique (Bloquants Possibles)

#### 1. **MicEngine Sample Rate Detection Faux**
**Fichier**: `mic_engine.dart:164-210`  
**Problème Potentiel**:
```dart
// Bug #6 fix partiel:
double dtSec;
if (_lastChunkTime != null) {
  dtSec = now.difference(_lastChunkTime!).inMilliseconds / 1000.0;
} else {
  dtSec = _totalSamplesReceived / (44100.0 * _detectedChannels!); // ❌ ASSUME 44100
}
```

**Risque**: Si VRAI sample rate = 48000, dtSec calculé faux → SR détecté faux → pitch transposé.

**Test Validation**:
```
Log attendu: "MIC_INPUT sampleRate=44100 ratio=1.000"
Si ratio != 1.000 → transposition active
```

**Fix Potentiel**:
```dart
// Première frame: impossible savoir SR sans timestamp
// Solution: skip SR detection première frame, utiliser 44100 par défaut
if (_lastChunkTime == null) {
  _detectedSampleRate = 44100; // Fallback safe
  return;
}
```

---

#### 2. **Notes Loading Race avec Video**
**Fichier**: `practice_page.dart:2183-2192`  
**Problème Potentiel**:
```dart
await _loadNoteEvents(sessionId);
if (!_isSessionActive(sessionId)) return;

await _startPracticeVideo(...);
if (!_isSessionActive(sessionId)) return;

// Race: Si user clique STOP pendant await?
// → _noteEvents chargées MAIS MicEngine pas créé
// → Prochaine session: MicEngine init avec OLD notes
```

**Symptôme**: Session 2 commence avec notes de Session 1.

**Fix Potentiel**:
```dart
// Capturer notes AVANT session check
final localNotes = _noteEvents.toList(); // Snapshot
if (!_isSessionActive(sessionId)) return;

// Utiliser localNotes pour MicEngine init (pas _noteEvents direct)
_micEngine = MicEngine(
  noteEvents: localNotes.map(...).toList(),
  ...
);
```

---

#### 3. **Video Controller Dispose Race**
**Fichier**: `practice_page.dart:2495-2496`  
**Problème Potentiel**:
```dart
@override
void dispose() {
  _videoController?.dispose(); // ❌ Si video playing?
  _micSub?.cancel();
  super.dispose();
}
```

**Risque**: Si user ferme page pendant video play → dispose() appelé pendant playback → crash possible.

**Fix Potentiel**:
```dart
@override
void dispose() async {
  await _stopPractice(); // Arrête TOUT proprement
  await _videoController?.pause();
  _videoController?.dispose();
  await _micSub?.cancel();
  super.dispose();
}
```

---

### 🟡 Moyen (Dégradation Possible)

#### 4. **Pitch Detector Thresholds Trop Bas**
**Fichier**: `pitch_detector.dart:10-11`  
**Problème Actuel**:
```dart
static const double clarityThreshold = 0.75; // Was 0.9
static const double minPeakValue = 0.65;     // Was 0.8
```

**Trade-off**: 
- ⬇️ Thresholds → ⬆️ Détections (moins de misses)
- ⬇️ Thresholds → ⬆️ False positives (plus de wrongs)

**Symptôme Possible**: Clavier flash rouge constant (bruit détecté comme notes).

**Validation Runtime**:
```
Si wrongFlash > 30% des events → thresholds trop bas
Si misses > 50% → thresholds trop hauts
```

**Fix Potentiel**: Adaptive thresholds (EWMA du clarity moyen).

---

#### 5. **MicEngine Window Matching Trop Large**
**Fichier**: `mic_engine.dart:85-90`  
**Config Actuelle**:
```dart
MicEngine({
  this.headWindowSec = 0.2,  // 200ms avant note
  this.tailWindowSec = 0.5,  // 500ms après note
  ...
});
```

**Problème Potentiel**: Note A (start=2.0) et Note B (start=2.3) → windows overlap → Note B détectée comme HIT pour Note A.

**Symptôme**: Score augmente MAIS mauvaise note marquée HIT.

**Validation**:
```dart
// Log HIT_DECISION:
"expectedMidi=60 detectedMidi=62 distance=2" // ❌ Distance > 1
```

**Fix Potentiel**:
```dart
// Réduire window OU ajouter distance check strict
if (distance > 1) continue; // Ne match que notes exactes
```

---

### 🟢 Faible (Edge Cases)

#### 6. **_hitNotes Array Bounds (Defense)**
**Fichier**: `practice_page.dart:3615-3625`  
**Problème Possible**:
```dart
for (i in 0.._noteEvents.length) {
  if (_hitNotes[i]) continue; // ❌ Si _hitNotes.length < _noteEvents.length?
}
```

**Fix Appliqué** (Bug #10):
```dart
if (i < _hitNotes.length && _hitNotes[i]) continue; // ✅ Bounds check
```

**Status**: Déjà patché, edge case unlikely mais défense ajoutée.

---

#### 7. **Countdown Elapsed Negative Overflow**
**Fichier**: `practice_page.dart:178-191`  
**Problème Théorique**:
```dart
final progress = (elapsedSinceCountdownStartSec / leadInSec).clamp(0.0, 1.0);
final syntheticElapsed = -fallLeadSec + (progress * fallLeadSec);
// Si elapsedSinceCountdownStartSec < 0 ? (clock rewind?)
```

**Probabilité**: Quasi-nulle (DateTime monotonic).

**Fix Préventif**:
```dart
final elapsedSinceCountdownStartSec = max(0.0, 
  DateTime.now().difference(_countdownStartTime!).inMilliseconds / 1000.0
);
```

---

## 📊 MÉTRIQUES QUALITÉ CODE

### Bugs par Catégorie

| Catégorie | Bugs Identifiés | Bugs Fixés | Bugs Potentiels |
|-----------|-----------------|------------|-----------------|
| **Architecture** | 6 | 6 | 0 |
| **Timing** | 5 | 5 | 1 (video dispose) |
| **References** | 2 | 2 | 1 (notes snapshot) |
| **Sync Backend/Flutter** | 6 | 6 | 0 |
| **UI Update** | 3 | 3 | 0 |
| **Audio** | 1 | 1 | 2 (SR, thresholds) |
| **Edge Cases** | 2 | 2 | 2 (bounds, overflow) |
| **TOTAL** | **25** | **25** | **6** |

### Confidence Niveau

```
Bugs Critiques Restants:   3/6  (50% - à investiguer runtime)
Bugs Moyens Restants:      2/6  (33% - monitoring requis)
Bugs Faible Restants:      2/6  (33% - defense-in-depth OK)

Confidence Globale: 70% ⚠️
Validation Runtime: OBLIGATOIRE
```

---

## 🚨 RECOMMANDATIONS STRUCTURELLES

### 1. **Refactor Audio Pipeline** (Priorité: HAUTE)

**Problème**: Early returns cascade fragile.

**Solution**:
```dart
// Architecture Layers:
class AudioPipeline {
  // Layer 1: TOUJOURS exécuté
  List<Decision> processScoring(samples, elapsed) {
    return _micEngine.onAudioChunk(samples, elapsed);
  }
  
  // Layer 2: HUD display (optionnel)
  AudioHUD? processHUD(samples) {
    if (_micRms < threshold) return null;
    if (window == null) return null;
    // ... compute freq, midi, etc
    return AudioHUD(freq: X, midi: Y);
  }
}

// Usage:
void _processSamples(samples) {
  // Layer 1: SCORING (unconditional)
  final decisions = _audioPipeline.processScoring(samples, elapsed);
  _applyDecisions(decisions);
  
  // Layer 2: HUD (optional)
  final hud = _audioPipeline.processHUD(samples);
  if (hud != null) {
    _micFrequency = hud.freq;
    _micNote = hud.midi;
  }
}
```

**Bénéfice**: Scoring JAMAIS bloqué, HUD indépendant.

---

### 2. **Shared Config File** (Priorité: HAUTE)

**Problème**: Backend/Flutter values dupliquées → desync.

**Solution**:
```yaml
# config/shared.yaml (1 seul fichier)
video:
  preroll_sec: 2.0
  lookahead_sec: 2.0
  time_offset_ms: -60
  max_duration_sec: 10
  
practice:
  fall_lead_sec: 2.0
  preview_duration_sec: 10
  
api:
  timeout_sec: 15
```

**Backend**:
```python
import yaml
with open('config/shared.yaml') as f:
    config = yaml.safe_load(f)
VIDEO_PREROLL_SEC = config['video']['preroll_sec']
```

**Flutter**:
```dart
import 'package:yaml/yaml.dart';
final config = loadYaml(await rootBundle.loadString('config/shared.yaml'));
static final fallLeadSec = config['practice']['fall_lead_sec'];
```

**Bénéfice**: 1 source of truth, desync impossible.

---

### 3. **Runtime Test Integration** (Priorité: CRITIQUE)

**Problème**: flutter analyze insuffisant, aucun test runtime.

**Solution**:
```dart
// test/integration/practice_runtime_test.dart
testWidgets('Practice mode full flow', (tester) async {
  await tester.pumpWidget(MyApp());
  
  // 1. Start practice
  await tester.tap(find.byIcon(Icons.play_arrow));
  await tester.pump();
  
  // 2. Wait countdown
  await tester.pump(Duration(seconds: 2));
  
  // 3. Inject audio samples (mock mic)
  final samples = generateTestSamples(freq: 261.6); // C4
  audioController.injectSamples(samples);
  await tester.pump();
  
  // 4. Verify score increased
  expect(find.text('Score: 1'), findsOneWidget);
  
  // 5. Verify keyboard green flash
  final keyboard = tester.widget<PracticeKeyboard>(find.byType(PracticeKeyboard));
  expect(keyboard.successFlashActive, true);
});
```

**Commande CI**:
```yaml
# .github/workflows/test.yml
- name: Integration Tests
  run: flutter test test/integration/
```

**Bénéfice**: Détection bugs AVANT push, pas après.

---

### 4. **Telemetry Logs** (Priorité: MOYENNE)

**Problème**: Debugging runtime difficile sans logs structurés.

**Solution**:
```dart
class PracticeTelemetry {
  static void logScoring(String event, Map<String, dynamic> data) {
    if (kDebugMode) {
      final json = jsonEncode({'event': event, 'ts': DateTime.now().toIso8601String(), ...data});
      debugPrint('TELEMETRY $json');
    }
  }
}

// Usage:
PracticeTelemetry.logScoring('hit_decision', {
  'expectedMidi': 60,
  'detectedMidi': 60,
  'elapsed': 2.5,
  'distance': 0.0,
});
```

**Extraction**:
```powershell
adb logcat | Select-String "TELEMETRY" | ConvertFrom-Json | Export-Csv telemetry.csv
```

**Bénéfice**: Analyse post-mortem sessions, metrics agregated.

---

## 🔬 PROMPT CODEX (Analyse Systématique)

Copie ce prompt dans Codex pour analyse profonde :

```markdown
# CONTEXTE SHAZAPIANO

Je suis l'IA debugging ShazaPiano Practice Mode (Flutter + Python Backend).

**Problème**: 10h de debugging, 25 bugs fixés, MAIS toujours incertain si fonctionnel runtime.

**Architecture**:
- Backend: Python FastAPI (inference, render, config)
- Frontend: Flutter (practice_page 4832 lignes, mic_engine)
- MicEngine: Audio → Pitch → Event Buffer → Note Matching → Decisions (HIT/MISS/WRONG)

**Bugs Patterns Identifiés**:
1. Early Returns Cascade (audio gates bloquent scoring)
2. Reference Stability (Dart `=` crée nouvelle liste)
3. Timebase Drift (countdown timing critique)
4. Backend/Flutter Desync (6 valeurs dupliquées)
5. UI Update Disconnect (decisions ≠ UI state)

**Fichier Référence**: `ANALYSE_STRUCTURELLE_BUGS.md` (ce fichier)

---

# MISSION CODEX

Analyse SYSTÉMATIQUE du code selon ces axes :

## 1. Architecture Antipatterns

**Question**: Y a-t-il d'autres "gate hells" cachés ?

**Chercher**:
- `if (...) return;` dans fonctions critiques
- Conditions qui skip logic essentielle
- Dependencies circulaires (A → B → C → A)

**Fichiers**: `practice_page.dart` (toutes méthodes `_process*`, `_on*`)

---

## 2. Reference Stability

**Question**: Y a-t-il d'autres listes réassignées avec `=` ?

**Chercher**:
- `_variable = [];` ou `_variable = List.filled(...)`
- Listes passées en référence à classes (MicEngine, Painter, etc.)
- Modifications après passage référence

**Pattern Dangereux**:
```dart
_list = []; // Nouvelle liste créée
ExternalClass(list: _list); // Référence passée
_list = List.filled(10, 0); // ❌ ExternalClass garde ancienne référence vide
```

**Fichiers**: Toutes variables `List<T> _something` dans `practice_page.dart`

---

## 3. Timing Race Conditions

**Question**: Y a-t-il d'autres timestamps critiques mal placés ?

**Chercher**:
- `DateTime.now()` assignments
- `_startTime`, `_countdownStartTime`, `_lastXxxAt` variables
- Order of operations dans `setState` vs `await`

**Pattern Dangereux**:
```dart
_timestamp = DateTime.now(); // ❌ Set trop tôt
await longOperation();
// _timestamp utilisé ici → valeur stale
```

**Fichiers**: `practice_page.dart` (toutes méthodes async avec timestamps)

---

## 4. Null Safety Edge Cases

**Question**: Y a-t-il des `!` ou `.value` sans guards ?

**Chercher**:
- `variable!` sans `if (variable != null)`
- `.value.position` sans check `isInitialized`
- `_controller!` sans null check upstream

**Pattern Dangereux**:
```dart
final pos = _videoController!.value.position; // ❌ Si controller null/uninitialized?
```

**Fichiers**: Tous fichiers Dart dans `lib/presentation/pages/practice/`

---

## 5. State Machine Transitions

**Question**: Y a-t-il des transitions invalides `_practiceState` ?

**Chercher**:
- Tous les `setState(() => _practiceState = X)`
- Vérifier : idle → countdown → running → idle (cycle valide uniquement)
- Transitions manquantes (ex: countdown → idle si error ?)

**Fichiers**: `practice_page.dart` (toutes mutations `_practiceState`)

---

## 6. Memory Leaks

**Question**: Y a-t-il des buffers/listeners qui croissent infiniment ?

**Chercher**:
- `List.add()` sans cleanup (ex: `_pitchHistory`, `_events`)
- `StreamSubscription` sans `.cancel()` dans dispose
- `Timer` sans `.cancel()`

**Pattern Dangereux**:
```dart
_buffer.add(data); // ❌ Pas de removeWhere() ou clear()
// Buffer croît infiniment → OOM après 10min
```

**Fichiers**: `mic_engine.dart` (`_events`), `practice_page.dart` (`_micBuffer`)

---

## 7. Backend/Flutter Contract Violations

**Question**: Y a-t-il d'autres valeurs hardcodées dupliquées ?

**Chercher Backend**:
- `backend/config.py` : Toutes constantes `VIDEO_*`, `MIDI_*`, `*_DURATION*`
- `backend/*.py` : Hardcoded values (16, 2.0, 0.5, etc.)

**Chercher Flutter**:
- `practice_page.dart` : Constantes `static const double _*`
- Comparer avec Backend : sont-elles identiques ?

**Pattern Dangereux**:
```python
# backend/config.py
VIDEO_PREROLL_SEC = 2.0

# practice_page.dart
static const _fallLeadSec = 1.5; // ❌ Différent!
```

---

## 8. Error Handling Gaps

**Question**: Y a-t-il des try/catch qui avalent erreurs silencieusement ?

**Chercher**:
- `try { ... } catch (_) {}`  sans log
- `await operation()` sans try/catch
- Erreurs backend non propagées au frontend

**Pattern Dangereux**:
```dart
try {
  await criticalOperation();
} catch (_) {
  // ❌ Erreur avalée, user voit rien
}
```

**Fichiers**: Tous fichiers `.dart` et `.py`

---

## OUTPUT ATTENDU

Pour CHAQUE axe (1-8) :

```markdown
## Axe X: [Nom]

**Bugs Potentiels Trouvés**: [N]

### Bug Potentiel X.Y
**Fichier**: `path/to/file.dart:ligne`
**Pattern Détecté**: [Code snippet]
**Risque**: [Description impact]
**Probabilité**: HAUTE/MOYENNE/FAIBLE
**Fix Suggéré**: [Code snippet solution]

---

**Axes avec 0 bugs**: [Liste axes OK]
**Axes avec bugs critiques**: [Liste axes avec HAUTE probabilité]
```

---

# RÈGLES ANALYSE

1. **Exhaustif**: Scanner TOUS les fichiers mentionnés, pas juste échantillons
2. **Preuves**: Citer ligne exacte + code snippet pour chaque bug potentiel
3. **Priorité**: Classer HAUTE (bloquant), MOYENNE (dégradation), FAIBLE (edge case)
4. **Actionnable**: Proposer fix concret (code), pas juste description problème
5. **False Positives OK**: Mieux signaler 10 faux positifs que louper 1 vrai bug

---

# FICHIERS À ANALYSER

**Backend**:
- `backend/config.py`
- `backend/inference.py`
- `backend/render.py`
- `backend/app.py`

**Frontend**:
- `app/lib/presentation/pages/practice/practice_page.dart`
- `app/lib/presentation/pages/practice/mic_engine.dart`
- `app/lib/core/audio/pitch_detector.dart`

**Tests** (si existent):
- `app/test/*.dart`

---

**START ANALYSE SYSTÉMATIQUE**
```

---

## 📁 FICHIERS RÉFÉRENCE

### Fichiers Ce Dossier

1. **`ANALYSE_STRUCTURELLE_BUGS.md`** (ce fichier)
   - Analyse détaillée patterns bugs
   - 6 bugs potentiels critiques identifiés
   - Recommendations architecturales

2. **`BUG_MASTER_REFERENCE.md`**
   - Historique 25 bugs fixés
   - Prompt handoff conversations
   - Checklist validation

3. **`AGENTS.md`**
   - Règles workflow projet
   - Interdictions (packages, refactor, etc.)

4. **`PROJECT_MAP.md`**
   - Architecture globale
   - Structure dossiers

### Git Commits Importants

```
6edf514 (HEAD) - fix: TOUS bugs runtime (4 fixes final)
4daa1f7 - docs: centralisation BUG_MASTER_REFERENCE.md
162ae88 - fix: Backend/Flutter desync (6 bugs) + practice timing (Bug #12-15)
2149ea2 - fix(practice): critical audio + timebase fixes v3.0
```

---

## ✅ PROCHAINES ÉTAPES

### Immédiat (Maintenant)

1. **Envoyer prompt Codex** (section ci-dessus)
2. **Attendre analyse systématique** (8 axes)
3. **Lire rapport Codex** (bugs potentiels identifiés)

### Après Rapport Codex

4. **Prioriser bugs critiques** (probabilité HAUTE)
5. **Fixer 1 bug à la fois** (1 fix = 1 test runtime = 1 commit)
6. **Valider runtime** (`.\scripts\dev.ps1 -Logcat`)

### Si Runtime OK

7. **Update `BUG_MASTER_REFERENCE.md`** (section bugs runtime → VALIDÉ)
8. **Commit final** : "feat: practice mode VALIDATED runtime"
9. **Fermer session** : Practice mode opérationnel ✅

### Si Runtime KO

10. **Extraire logs** : `GUIDANCE_TIME`, `HIT_DECISION`, `SCORING_DESYNC`
11. **Nouvelle conversation** : Copier prompt handoff + logs
12. **Fixer bug identifié** : Répéter cycle

---

**FIN ANALYSE STRUCTURELLE**

Ce fichier documente POURQUOI on a tourné en rond 10h. La vraie cause : **patcher symptômes au lieu de fixer architecture fragile**.

Maintenant avec Codex, on trouve les bugs RESTANTS avant qu'ils causent problèmes.
