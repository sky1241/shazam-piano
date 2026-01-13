# FIX: Conflit Buffer OLD/NEW System

## Problème Root Cause

Les corrections de ChatGPT (octave fix + near-miss) **fonctionnaient correctement** mais ne réglaient PAS le bug visuel (notes rouges aléatoires) car:

### Deux Systèmes Parallèles en Conflit

```
OLD SYSTEM (practice_page.dart)
  ↓ MicEngine détecte pitch
  ↓ NoteMatcher match contre _expectedMidi buffer
  ↓ HIT_DECISION log: "result=HIT" ✅
  ↓
  → Appelle NEW controller.onPlayedNote()
      ↓ NEW controller essaie de re-matcher
      ↓ Mais NEW controller a son propre buffer _expectedNotes
      ↓ Buffer désynchronisé → SESSION4_MATCH_FAIL ❌
      ↓ Result: MISS → note rouge
```

**Résultat**: OLD system dit HIT, NEW controller dit MISS → note affichée rouge.

### Preuve dans debuglogcat (ligne 3570)

```
HIT_DECISION ... expectedMidi=66 detectedMidi=66 distance=0.0 result=HIT  ← OLD ✅
SESSION4_BUFFER_STATE: buffer=1 unconsumed=1 nextExpected=0            ← NEW
SESSION4_MATCH_FAIL: rawMidi=66 usedMidi=66 dist=0                     ← NEW ❌
RESOLVE_NOTE session=1 idx=0 grade=miss                                ← Final
```

Note parfaite (dist=0) → OLD dit HIT → NEW dit MISS → Grade final: MISS.

## Solution Appliquée

### 1. Bridge Parameter `forceMatchExpectedIndex`

Ajout param optionnel dans `practice_controller.dart`:

```dart
void onPlayedNote(
  PlayedNoteEvent event, {
  int? forceMatchExpectedIndex, // ← Nouveau
}) {
  // Si OLD system a déjà validé le match
  if (forceMatchExpectedIndex != null) {
    // Skip le re-matching, resolve directement
    _resolveExpectedNote(
      expectedIndex: forceMatchExpectedIndex,
      matchedEvent: playedEvent,
      dtMs: dtMs,
    );
    return; // Done
  }
  
  // Sinon flow normal (MIDI, tests, wrong notes)
  // ...
}
```

### 2. Pass Index depuis OLD System

Dans `practice_page.dart` lors HIT decision:

```dart
final playedEvent = PracticeController.createPlayedEvent(
  midi: decision.detectedMidi!,
  tPlayedMs: elapsed * 1000.0,
  source: NoteSource.microphone,
);

// AVANT: _newController!.onPlayedNote(playedEvent);
// APRÈS:
_newController!.onPlayedNote(
  playedEvent,
  forceMatchExpectedIndex: decision.noteIndex, // ← Bridge
);
```

`decision.noteIndex` vient du `MicEngine.NoteDecision` qui track l'index dans `noteEvents[]`.

### 3. Cas Spéciaux

- **HIT mic**: utilise `forceMatchExpectedIndex` ✅ (fix appliqué)
- **WRONG mic**: PAS de `forceMatchExpectedIndex` → NEW controller traite normalement
- **MIDI input**: PAS de `forceMatchExpectedIndex` → NEW controller match librement

## Résultat Attendu

Après fix:
- OLD system détecte HIT → passe index au NEW controller
- NEW controller accepte directement sans re-matcher
- `correctCountAfter > correctCountBefore` → `_registerCorrectHit()` ✅
- Note devient verte → **bug résolu**

## Test Manuel

```powershell
.\scripts\dev.ps1 -Logcat
```

Vérifier:
1. Notes correctes deviennent **vertes** (plus de rouge aléatoire)
2. `SESSION4_MATCH_FAIL` avec dist=0 disparaît des logs
3. Final summary: plus de MISS sur notes correctes

## Fichiers Modifiés

- `practice_controller.dart` (+50 lignes): Param `forceMatchExpectedIndex`, skip matching si présent
- `practice_page.dart` (+3 lignes): Pass `decision.noteIndex` au controller

## Migration Future

Ce fix est un **bridge temporaire** entre OLD et NEW systems. Objectif long terme:

**Option A**: Migrer entièrement vers NEW controller (supprimer OLD MicEngine/NoteMatcher)  
**Option B**: Sync explicite des buffers OLD/NEW à chaque frame

Pour l'instant, bridge permet:
- Fix immédiat du bug visuel ✅
- Garder octave fix + near-miss corrections de ChatGPT ✅
- Pas de refactor massif ✅
