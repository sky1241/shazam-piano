# Bug Fixes Session 3 - Practice Mode Score=0% Fix

**Date**: 2026-01-08
**Symptômes originaux**: 
- Score reste à 0%
- Notes apparaissent mi-écran (ne tombent pas du haut)
- Pas de feedback clavier (vert/rouge)
- Logs: SCORING_DESYNC, guidanceElapsed=1.859s au lieu de -2.0s

---

## Bug #12 - CRITIQUE: _hitNotes reassignment orphans MicEngine reference

**Fichier**: `app/lib/presentation/pages/practice/practice_page.dart`

**Problème**:
```dart
// AVANT (3 locations):
_hitNotes = [];  // Ligne 2075
_hitNotes = List.filled(_noteEvents.length, false);  // Ligne 2233
_hitNotes = List.filled(_noteEvents.length, false);  // Ligne 4041
```

L'opérateur `=` crée une NOUVELLE liste, orphanant la référence de MicEngine:
- Session 0: MicEngine créé avec référence à liste A (9 éléments)
- Reset: `_hitNotes = []` crée liste B (vide)
- Session 1: `_hitNotes = List.filled(9, false)` crée liste C
- **MicEngine garde liste B (vide)** → SCORING_DESYNC hitNotes=0 noteEvents=9 ABORT

**Solution**:
```dart
// APRÈS:
_hitNotes.clear();  // Ligne 2063 - vide la liste mais garde référence
_hitNotes.clear();
_hitNotes.addAll(List.filled(_noteEvents.length, false));  // Ligne 2224-2225
_hitNotes.clear();
_hitNotes.addAll(List.filled(_noteEvents.length, false));  // Ligne 4030-4031
```

**Impact**: MicEngine garde toujours la même référence, voit les mises à jour → scoring fonctionne.

---

## Bug #13 - Timebase video offset simplifié

**Fichier**: `app/lib/presentation/pages/practice/practice_page.dart`

**Problème**:
Logique complexe de lock video→clock offset causait des problèmes:
- Video position peut être null/stale après countdown
- Offset calculations fragiles

**Solution** (Lignes 1909-1917):
```dart
// AVANT: Complexe avec video offset lock
if (v != null && _videoGuidanceOffsetSec != null) {
  return v + _videoGuidanceOffsetSec!;
}
return clock;

// APRÈS: Simple
return clock;  // Clock est fiable et démarre à 0 quand practice running commence
```

**Impact**: Plus simple, plus fiable, clock démarre toujours à 0 quand practice active.

---

## Bug #14 - Notes loading race condition

**Fichier**: `app/lib/presentation/pages/practice/practice_page.dart`

**Problème**:
`_canStartPractice()` ne vérifiait que video, pas notes:
```dart
// AVANT (Ligne 1995-2007):
bool _canStartPractice() {
  if (_videoLoading || _videoError != null) return false;
  if (controller == null || !controller.value.isInitialized) return false;
  if (effectiveDuration == null || effectiveDuration <= 0) return false;
  return true;  // ❌ Pas de check sur notes!
}
```

Conséquence: Practice pouvait démarrer AVANT notes chargées → MicEngine créé avec `_noteEvents` vide.

**Solution** (Lignes 1983-1991):
```dart
// APRÈS:
bool _canStartPractice() {
  // ... checks video ...
  
  // BUG FIX #14: Guard notes loaded before allowing practice start
  if (_notesLoading || _noteEvents.isEmpty) {
    return false;
  }
  return true;
}
```

**Bonus**: Message d'erreur précis (Lignes 1995-2011):
```dart
void _showVideoNotReadyHint() {
  String message;
  if (_notesLoading) {
    message = 'Notes en cours de chargement, reessaye dans un instant.';
  } else if (_noteEvents.isEmpty) {
    message = 'Notes indisponibles pour ce niveau.';
  } else if (_videoLoading) {
    message = 'Video en cours de chargement, reessaye dans un instant.';
  } else {
    message = 'Chargement en cours, reessaye dans un instant.';
  }
  // ...
}
```

**Impact**: Practice ne démarre jamais avant notes prêtes → MicEngine toujours synced.

---

## Bug #15 - CRITIQUE: _startTime set trop tôt

**Fichier**: `app/lib/presentation/pages/practice/practice_page.dart`

**Problème ROOT CAUSE du bug principal**:

`_startTime = DateTime.now()` était set dans `_startPractice()` ligne 2252, **AVANT le countdown**:

**Timeline problématique**:
```
t=0.0s:  _startPractice() → _startTime = DateTime.now()
t=0.0s:  Countdown démarre (state=countdown, 2 secondes)
t=0-2s:  _guidanceElapsedSec() retourne synthetic (-2.0 → 0.0) ✅
t=2.0s:  Countdown finit → state=running
t=2.0s:  _guidanceElapsedSec() retourne clock = DateTime.now() - _startTime = 2.0s ❌
```

**Conséquence**: 
- guidanceElapsed démarre à 2.0s au lieu de 0.0s
- Note avec start=1.875s et fallLead=2.0s spawn à -0.125s
- Painter calcule: progress = (2.0 - (-0.125)) / 2.0 = 1.06 = **106% = mi-écran!**

**Solution**:

**Partie 1** - Retirer l'ancien set (Lignes 2252-2254):
```dart
// BUG FIX #15: Do NOT set _startTime here - it will be set when countdown finishes
// If set here, clock advances during countdown and guidanceElapsed starts at 2s instead of 0
// _startTime = DateTime.now(); // REMOVED
```

**Partie 2** - Set au bon moment (Lignes 2318-2319 dans `_updateCountdown()`):
```dart
if (elapsedMs >= countdownCompleteSec * 1000) {
  // Countdown finished: start video + mic + enter running state
  // BUG FIX #15: Set _startTime NOW so clock starts at 0 for running state
  _startTime = DateTime.now();  // ✅ Clock démarre à 0 maintenant
  if (mounted) {
    setState(() {
      _practiceState = _PracticeState.running;
    });
  }
  // ...
}
```

**Impact**: 
- Clock démarre à 0 quand practice running commence
- guidanceElapsed: -2.0 → 0.0 (countdown) puis 0.0 → ... (running)
- Notes tombent du haut pendant countdown
- Score fonctionne dès première note

---

## Vérifications Complètes

### Timing Variables
✅ `_startTime`: null pendant countdown, set quand running démarre
✅ `_countdownStartTime`: set quand countdown démarre, reset à stop
✅ `_practiceClockSec()`: retourne 0.0 si _startTime==null, safe
✅ `_guidanceElapsedSec()`: synthetic pendant countdown, clock pendant running

### State Machine
✅ `_practiceState`: idle → countdown → running → idle
✅ Transitions atomiques dans setState
✅ Guards empêchent audio processing pendant countdown

### MicEngine Lifecycle
✅ Créé dans `_startPractice()` après notes chargées
✅ Référence `_hitNotes` stable via clear()+addAll()
✅ Référence `noteEvents` copie via .toList()
✅ Session guards empêchent callbacks stale

### Painter
✅ Reçoit `_guidanceElapsedSec()` correct
✅ Formula Y position: `(elapsed - (noteStart - fallLead)) / fallLead`
✅ Peut gérer elapsed négatif (notes offscreen haut)

### UI State
✅ `_detectedNote`, `_accuracy` reset à stop
✅ Flash timing correct
✅ Keyboard highlight synced

---

## Tests Attendus

**Avant fix**:
```
❌ guidanceElapsed=1.859s au démarrage
❌ Notes apparaissent mi-écran
❌ SCORING_DESYNC hitNotes=0 noteEvents=9 ABORT
❌ Score reste 0%
❌ Pas de feedback clavier
```

**Après fix**:
```
✅ guidanceElapsed=-2.0s au début countdown
✅ guidanceElapsed=0.0s à fin countdown
✅ Notes tombent du haut
✅ Score augmente sur hits
✅ Feedback clavier actif (vert/rouge)
✅ 0 SCORING_DESYNC dans logs
```

---

## Compilation
```
flutter analyze --no-fatal-infos
Result: No issues found! (0 errors, 3 deprecation warnings non-bloquants)
```
