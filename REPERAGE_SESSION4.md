# REPÉRAGE SESSION 4 — Système existant ShazaPiano

**Date:** 2026-01-11  
**Objectif:** Comprendre le système de scoring/matching actuel avant refactor

---

## 📍 FINDINGS PRINCIPAUX

### 1. ARCHITECTURE ACTUELLE

**Fichiers clés identifiés:**
- `app/lib/presentation/pages/practice/practice_page.dart` (4765 lignes) — UI + logique métier mélangées
- `app/lib/presentation/pages/practice/mic_engine.dart` (555 lignes) — Moteur de scoring micro
- Pas de handler MIDI dédié — intégré dans practice_page.dart (ligne 3439+)

**Structure:**
- MicEngine existe déjà comme module séparé (✅ bon point)
- practice_page.dart contient TOUT le reste (❌ à refactoriser)

---

## 🎯 CRITÈRE PITCH EXISTANT (OBLIGATOIRE À RÉUTILISER)

### A) MIC MODE (via MicEngine)

**Fonction de comparaison:** `pitchClass` matching avec octave shift tolérant

**Localisation:** `mic_engine.dart` lignes 395-425

**Logique exacte:**
```dart
// 1. Pitch class match strict (midi % 12)
final detectedPitchClass = event.midi % 12;
final expectedPitchClass = note.pitch % 12;

// REJECT si pitchClass != expectedPitchClass
if (detectedPitchClass != expectedPitchClass) {
  continue; // reject
}

// 2. Si pitchClass OK, trouver meilleure octave (distance minimale)
final distDirect = (event.midi - note.pitch).abs();
// Test octave shifts: ±12, ±24 semitones
for (final shift in [-24, -12, 12, 24]) {
  final testMidi = event.midi + shift;
  final distOctave = (testMidi - note.pitch).abs();
  // Garder le meilleur
}

// 3. Accept si distance ≤ 3 semitones (tolérance piano réel)
if (bestDistance <= 3.0) {
  // HIT
}
```

**Résumé:**
- **Critère principal:** pitchClass exact (C == C, toutes octaves)
- **Octave ignorée:** comparaison avec shifts ±12, ±24 semitones
- **Tolérance finale:** ≤3 semitones (permet micro-décalages piano réel)

**PitchComparator à créer:**
```dart
typedef PitchComparator = bool Function(int pitch1, int pitch2);

// Wrapper exact de la logique existante
bool existingPitchMatch(int detected, int expected) {
  final detectedPC = detected % 12;
  final expectedPC = expected % 12;
  
  if (detectedPC != expectedPC) return false;
  
  // Test octave shifts
  final shifts = [0, -12, 12, -24, 24];
  for (final shift in shifts) {
    if ((detected + shift - expected).abs() <= 3) {
      return true;
    }
  }
  return false;
}
```

### B) MIDI MODE (via practice_page.dart)

**Localisation:** `practice_page.dart` lignes 3470-3478

**Logique exacte:**
```dart
// Matching MIDI beaucoup plus simple
if ((note - _noteEvents[idx].pitch).abs() <= 1) {
  matched = true;
  _hitNotes[idx] = true;
  _correctNotes += 1;
  _score += 1;
  // ...
}
```

**Résumé:**
- **Critère:** distance absolue ≤1 semitone (presque exact)
- **Pas d'octave shift:** MIDI note doit être dans [expected-1, expected+1]

**⚠️ ATTENTION:** Les deux modes (Mic vs MIDI) ont des critères différents !
- Mic: pitchClass + octave shift + distance ≤3
- MIDI: distance ≤1 (plus strict)

**Décision pour nouveau système:**
- Créer un `PitchComparator` configurable
- Par défaut (Mic): utiliser logique pitchClass existante
- MIDI mode: utiliser distance ≤1

---

## ⏱️ FENÊTRE DE MATCHING ACTUELLE

### MicEngine

**Paramètres:**
- `headWindowSec = 0.12` (120ms avant onset)
- `tailWindowSec = 0.45` (450ms après onset)
- **Fenêtre totale:** [t_expected - 0.12, t_expected + 0.45] = **570ms**

**Code:** `mic_engine.dart` ligne 324
```dart
final windowStart = note.start - headWindowSec;
final windowEnd = note.end + tailWindowSec;
```

**⚠️ SPEC VS ACTUEL:**
- Spec SESSION4: ±200ms (400ms total)
- Actuel: -120ms à +450ms (570ms total)

**Décision:** Garder 200ms comme spec (plus strict), mais documenter l'ancien comportement.

---

## 🆔 SESSION ID (ANTI-REPLAY)

### Mécanisme existant

**Variable:** `_practiceSessionId` (int, practice_page.dart ligne 249)

**Utilisation:**
1. Incrémenté à chaque démarrage practice
2. Capturé au début de callbacks async
3. Vérifié avant chaque traitement

**Code exemple:** `practice_page.dart` ligne 2471-2477
```dart
Future<void> _processAudioChunk(List<int> chunk) async {
  if (_startTime == null) return;
  // C3: Session gate - capture sessionId to prevent obsolete callbacks
  final localSessionId = _practiceSessionId;
  if (!_isSessionActive(localSessionId)) {
    return;
  }
  // ... process
}

bool _isSessionActive(int? id) => id != null && id == _practiceSessionId;
```

**MicEngine:** Propre sessionId String (ligne 39, 86)
```dart
String? _sessionId;
void reset(String sessionId) {
  _sessionId = sessionId;
  // ...
}
```

**✅ RESPECTER STRICTEMENT:** Le nouveau système DOIT propager sessionId partout.

---

## 📊 SCORING ACTUEL

### Variables

**practice_page.dart:**
```dart
double _score = 0.0;         // ligne 279 (TYPE FIX: était int, devenu double en BUG 5)
int _totalNotes = 0;         // ligne 280
int _correctNotes = 0;       // ligne 280
```

### Calcul score (BUG 5 FIX récent)

**Avant:** +1 point par note correcte (binaire)

**Après (actuel):** Timing-weighted scoring

**Code:** `practice_page.dart` ligne 2514-2518
```dart
// BUG 5 FIX: Score based on timing precision, not just binary hit
final timingErrorMs = (decision.dtSec?.abs() ?? 0.0) * 1000.0;
final timingScore = _calculateTimingScore(timingErrorMs);

_correctNotes += 1;
_score += timingScore; // BUG 5 FIX: Add weighted score instead of +1
```

**Fonction:** `practice_page.dart` ligne 2596-2610
```dart
double _calculateTimingScore(double timingErrorMs) {
  if (timingErrorMs <= 10) {
    return 1.0; // Perfect (±10ms)
  } else if (timingErrorMs <= 50) {
    return 0.8; // Great (±50ms)
  } else if (timingErrorMs <= 100) {
    return 0.6; // Good (±100ms)
  } else if (timingErrorMs <= 200) {
    return 0.4; // OK (±200ms)
  } else {
    return 0.0; // Too late (>200ms)
  }
}
```

**⚠️ SPEC SESSION4 VS ACTUEL:**

| Spec SESSION4 | Actuel |
|---------------|--------|
| Perfect ≤40ms → 100pts | Perfect ≤10ms → 1.0 |
| Good ≤100ms → 70pts | Great ≤50ms → 0.8 |
| OK ≤200ms → 40pts | Good ≤100ms → 0.6 |
| Miss >200ms → 0pts | OK ≤200ms → 0.4 |

**Décision:** Remplacer par spec SESSION4 (seuils plus tolérants, points absolus).

---

## 🔄 MATCHING ALGORITHM ACTUEL (MicEngine)

### Buffer management

**Structure:** `List<PitchEvent> _events` (ligne 43)

**PitchEvent:**
```dart
class PitchEvent {
  final double tSec;
  final int midi;
  final double freq;
  final double conf;
  final double rms;
  final int stabilityFrames;
}
```

### Matching logic (ligne 369-425)

**Algorithme:**
1. Pour chaque note attendue
2. Filtrer events buffer:
   - Dans fenêtre temporelle [start-head, end+tail]
   - Pitch class match (midi % 12)
   - Stabilité ≥1 frame (toujours true pour piano)
3. Pour chaque event filtré:
   - Tester direct + octave shifts (±12, ±24)
   - Garder distance minimale
4. Accept si distance ≤3 semitones

**Exclusivité:** ❌ AUCUNE gestion d'exclusivité !
- Un event peut matcher plusieurs notes
- PAS de tracking "consumed events"

**Performance:** ⚠️ O(notes × events) potentiellement
- Pas d'indexation par pitch
- Scan linéaire du buffer complet

**✅ AMÉLIORATION OBLIGATOIRE:** Ajouter exclusivité + indexation pitch.

---

## 🎹 MIDI MATCHING ACTUEL

**Localisation:** `practice_page.dart` ligne 3460-3490

**Algorithm:**
1. Trouver notes actives (elapsed dans [start, end+tail])
2. Pour chaque note active:
   - Si distance ≤1 semitone → HIT
   - Break (première note matchée seulement)
3. Si aucune note active matchée → WRONG flash (si notes actives existent)

**Exclusivité:** ✅ Implicite via `_hitNotes[idx]` + break

**SessionId:** ❌ PAS vérifié dans MIDI handler (bug potentiel ?)

---

## 📦 MODÈLES EXISTANTS

### NoteEvent (mic_engine.dart ligne 504)

```dart
class NoteEvent {
  const NoteEvent({
    required this.start,
    required this.end,
    required this.pitch,
  });
  final double start;
  final double end;
  final int pitch;
}
```

**✅ RÉUTILISABLE:** Proche de `ExpectedNote` spec SESSION4.

### PitchEvent (mic_engine.dart ligne 517)

```dart
class PitchEvent {
  const PitchEvent({
    required this.tSec,
    required this.midi,
    required this.freq,
    required this.conf,
    required this.rms,
    required this.stabilityFrames,
  });
  // ...
}
```

**✅ RÉUTILISABLE:** Proche de `PlayedNoteEvent` spec SESSION4.

### _NoteEvent (practice_page.dart, privé)

**⚠️ ATTENTION:** Doublon de NoteEvent, mais privé à practice_page.

**Recherche nécessaire:** Vérifier s'il y a une différence.

---

## 🚫 WRONG NOTES ACTUELS

### MicEngine (ligne 480-500)

**Logique:**
1. Si bestEvent non null MAIS aucun HIT
2. ET confidence ≥ minConfForWrong (0.35)
3. ET cooldown passé (150ms)
4. → Trigger wrongFlash

**Code:**
```dart
if (bestEventAcrossAll != null &&
    decisions.every((d) => d.type != DecisionType.hit) &&
    bestEventAcrossAll.conf >= minConfForWrong) {
  final now = DateTime.now();
  final cooldownPassed =
      _lastWrongFlashAt == null ||
      now.difference(_lastWrongFlashAt!).inMilliseconds >=
          (wrongFlashCooldownSec * 1000).round();
  if (cooldownPassed) {
    decisions.add(
      NoteDecision(
        type: DecisionType.wrongFlash,
        detectedMidi: bestMidiAcrossAll,
        confidence: bestEventAcrossAll.conf,
      ),
    );
    _lastWrongFlashAt = now;
  }
}
```

**✅ SAFE:** Throttled + confidence gate → peu de faux positifs.

### MIDI Mode (practice_page.dart ligne 3490-3501)

**Logique:**
1. Si aucune note active matchée
2. ET il existe au moins une note active (impactNotes non vide)
3. → Wrong flash

**Code:**
```dart
if (!matched && activeIndices.isNotEmpty) {
  // PATCH: Only trigger wrongFlash if there's an active note to play
  final impactNotes = _computeImpactNotes(elapsedSec: elapsed);
  if (impactNotes.isNotEmpty) {
    _accuracy = NoteAccuracy.wrong;
    _registerWrongHit(detectedNote: note, now: now);
  }
}
```

**✅ SAFE:** Gate par impactNotes (évite wrong pendant silences).

---

## 📈 MÉTRIQUES ACTUELLES

### Variables disponibles

```dart
double _score = 0.0;           // Score total (weighted)
int _totalNotes = 0;           // Notes attendues
int _correctNotes = 0;         // Notes matchées
```

**Calculs dérivés:**
- Accuracy: `_correctNotes / _totalNotes * 100` (ligne 656)
- Wrong notes: `_totalNotes - _correctNotes` (ligne 4162)

**❌ MANQUANT (à ajouter):**
- Combo
- Max combo
- Distribution grades (Perfect/Good/OK/Miss/Wrong)
- Timing moyen
- Sustain (pas utilisé actuellement)

---

## 🔍 ZONES D'IMPACT IDENTIFIÉES (CASCADE)

### Pour nouvelle architecture

**Fichiers à LIRE avant modification:**
1. ✅ `practice_page.dart` (lu lignes clés)
2. ✅ `mic_engine.dart` (lu complet)
3. `pitch_detector.dart` (grep référence trouvée ligne 156-161)
4. `practice_keyboard.dart` (widget UI, probablement safe)

**Variables à surveiller:**
- `_score` (type changé int→double récemment, grep 10 occurrences)
- `_correctNotes` (grep 10 occurrences)
- `_hitNotes` (List<bool>, bounds checks critiques)
- `_practiceSessionId` (anti-replay, grep 20+ occurrences)

**Fonctions critiques:**
- `_processSamples` (ligne 2479+) — callback micro
- `_processMidiPacket` (ligne 3439+) — callback MIDI
- `_calculateTimingScore` (ligne 2596+) — à remplacer
- `_registerCorrectHit` (ligne 2580+) — haptics + UI
- `_registerWrongHit` (ligne 2591+) — haptics + UI

---

## ✅ CONCLUSIONS & RECOMMANDATIONS

### 1. PITCH COMPARATOR

**Réutiliser logique pitchClass:**
```dart
bool micPitchMatch(int detected, int expected) {
  final detectedPC = detected % 12;
  final expectedPC = expected % 12;
  if (detectedPC != expectedPC) return false;
  
  // Octave shifts ±12, ±24
  for (final shift in [0, -12, 12, -24, 24]) {
    if ((detected + shift - expected).abs() <= 3) return true;
  }
  return false;
}

bool midiPitchMatch(int detected, int expected) {
  return (detected - expected).abs() <= 1;
}
```

### 2. FENÊTRE MATCHING

**Spec SESSION4:** ±200ms (plus strict)  
**Actuel:** -120ms à +450ms (plus tolérant)

**Recommandation:** Utiliser 200ms comme spec, mais rendre configurable.

### 3. SCORING THRESHOLDS

**Remplacer:**
```
≤10ms → 1.0
≤50ms → 0.8
≤100ms → 0.6
≤200ms → 0.4
```

**Par spec SESSION4:**
```
≤40ms → Perfect (100pts)
≤100ms → Good (70pts)
≤200ms → OK (40pts)
>200ms → Miss (0pts)
```

### 4. EXCLUSIVITÉ

**CRITIQUE:** Ajouter tracking events consommés (Set<String> playedIds).

### 5. PERFORMANCE

**CRITIQUE:** Indexer buffer par pitchClass → Map<int, List<PlayedEvent>>

### 6. SESSION ID

**CRITIQUE:** Propager sessionId dans toute la nouvelle architecture.

---

## 🎯 PROCHAINES ÉTAPES

1. ✅ Repérage terminé
2. ⏭️ ÉTAPE 1 — Créer modèles (practice_models.dart)
3. ⏭️ ÉTAPE 2 — Scoring engine + tests
4. ⏭️ ÉTAPE 3 — Note matcher + tests
5. ⏭️ ÉTAPE 4 — Debug logger
6. ⏭️ ÉTAPE 5 — Controller
7. ⏭️ ÉTAPE 6 — Branchement progressif

---

**FIN REPÉRAGE — PRÊT POUR IMPLÉMENTATION**
