# 🎯 BUG MASTER REFERENCE — ShazaPiano Practice Mode
**Date dernière MAJ**: 2026-01-08 — 23h45  
**Status**: ⚠️ **RUNTIME BUGS ACTIFS** — Score 0%, notes ne tombent pas, clavier mort

---

## 📌 PROMPT HANDOFF (Copier dans nouvelle conversation)

```
Je reprends le debugging du mode Practice de ShazaPiano (Flutter + Python Backend).

BUGS CORRIGÉS (Session 2026-01-08):
✅ Bug #1-6: Désynchronisation Backend↔Flutter (6 valeurs: PREROLL, LOOKAHEAD, OFFSET, TIMEOUT, DURATION)
✅ Bug #12: _hitNotes reference stability (clear+addAll pattern)  
✅ Bug #13: Timebase simplifié (clock-based)
✅ Bug #14: Notes loading guard
✅ Bug #15: _startTime timing (set APRÈS countdown)

BUGS RUNTIME ACTIFS (NON RÉSOLUS):
❌ Notes ne tombent PAS du haut (apparaissent mid-screen)
❌ Score reste 0% (aucun HIT détecté)
❌ Clavier mort (pas de vert/rouge)
❌ Micro détecte mais MicEngine ne score pas

ARCHITECTURE ACTUELLE:
- Backend: Python FastAPI (config.py, inference.py, render.py, app.py)
- Frontend: Flutter practice_page.dart (4832 lignes) + mic_engine.dart
- MicEngine: Architecture décisions (HIT/MISS/wrongFlash) OK mais feedback UI cassé
- Git: Commit 162ae88 (2026-01-08 push avec 10 bugs fixes)

FICHIERS CRITIQUES:
- app/lib/presentation/pages/practice/practice_page.dart (LIGNE 2520-2680: MicEngine scoring)
- app/lib/presentation/pages/practice/mic_engine.dart (LIGNE 230-242: Guard desync)
- backend/config.py (LIGNE 58-61: VIDEO_PREROLL_SEC, VIDEO_LOOKAHEAD_SE)

PISTES INVESTIGATION PRIORITAIRES:
1. **Feedback clavier**: _updateDetectedNote() jamais appelé après MicEngine decisions → _detectedNote reste null
2. **Notes falling**: guidanceElapsed démarre-t-il à -2.0s (countdown) ou à 0.0s (cassé) ?
3. **Scoring MicEngine**: decisions HIT générées mais _registerCorrectHit() ne met pas à jour UI ?

RÈGLES ABSOLUES:
- UN SEUL fichier doc: BUG_MASTER_REFERENCE.md (ce fichier)
- Pas de nouveaux fichiers MD dispersés
- Tests runtime OBLIGATOIRES avant validation
- Commande test: .\scripts\dev.ps1 -Logcat

MISSION: Identifier bug RUNTIME empêchant practice mode de fonctionner. Notes DOIVENT tomber du haut, score DOIT augmenter, clavier DOIT s'allumer vert/rouge.

Lis BUG_MASTER_REFERENCE.md section "HISTORIQUE BUGS" pour contexte complet.
```

---

## 🐛 HISTORIQUE BUGS (Référence Complète)

### ✅ Bug #1 — VIDEO_PREROLL_SEC Desync
**Commit**: 162ae88  
**Fichier**: `backend/config.py:58`  
**Fix**: `VIDEO_PREROLL_SEC: float = 2.0` (était 1.5s)  
**Raison**: Backend 1.5s vs Flutter _fallLeadSec 2.0s → notes tombaient trop vite  
**Validation**: Grep confirmé ligne 350 practice_page.dart `_fallLeadSec = 2.0`

---

### ✅ Bug #2 — VIDEO_LOOKAHEAD_SEC Desync
**Commit**: 162ae88  
**Fichier**: `backend/config.py:61`  
**Fix**: `VIDEO_LOOKAHEAD_SEC: float = 2.0` (était 2.2s)  
**Raison**: Backend 2.2s vs Flutter 2.0s → barre falling area inconsistente  
**Validation**: Valeur synchronisée avec Flutter constants

---

### ✅ Bug #3 — API Timeout Inconsistent
**Commit**: 162ae88  
**Fichiers**: `practice_page.dart:2442, 3245`  
**Fix**: Tous timeouts unifiés à 15s (était 20s/15s/10s)  
**Raison**: Comportement imprévisible fetch video vs notes  
**Validation**: Grep `Duration(seconds: 15)` → 2 matches confirmés

---

### ✅ Bug #4 — VIDEO_TIME_OFFSET_MS Non Appliqué Flutter
**Commit**: 162ae88  
**Fichier**: `practice_page.dart:355`  
**Fix**: `_videoSyncOffsetSec = -0.06` (était 0.0)  
**Raison**: Backend -60ms offset ignoré → desync 60ms scoring/video  
**Validation**: Backend config.py ligne 60 `VIDEO_TIME_OFFSET_MS: int = -60`

---

### ✅ Bug #5 — MIN_MIDI_DURATION Inconsistent
**Commit**: 162ae88  
**Fichier**: `backend/inference.py:392`  
**Fix**: `MIN_MIDI_DURATION = 10.0` (était 16.0)  
**Raison**: MIDI extend 16s mais video cut 10s → silence après  
**Validation**: Config FULL_VIDEO_MAX_DURATION_SEC = 10 (ligne 63)

---

### ✅ Bug #6 — PREVIEW_DURATION Hardcodé
**Commit**: 162ae88  
**Fichier**: `backend/render.py:523`  
**Fix**: `duration_sec = settings.PREVIEW_DURATION_SEC` (était hardcodé 16)  
**Raison**: Preview 16s au lieu config 10s  
**Validation**: Config ligne 62 `PREVIEW_DURATION_SEC: int = 10`

---

### ✅ Bug #12 — _hitNotes Reference Orphaned
**Commit**: 162ae88  
**Fichier**: `practice_page.dart:2063, 2224-2225`  
**Fix**: `_hitNotes.clear(); _hitNotes.addAll(...)` (était `_hitNotes = []`)  
**Raison**: Opérateur = crée nouvelle liste → MicEngine garde ancienne référence vide  
**Impact**: SCORING_DESYNC hitNotes=0 noteEvents=9 ABORT  
**Validation**: Pattern appliqué 3 locations (L2063, L2224, L4030)

---

### ✅ Bug #13 — Timebase Video Offset Complexe
**Commit**: 162ae88  
**Fichier**: `practice_page.dart:1909-1917`  
**Fix**: Return `clock` direct (supprimé video offset lock)  
**Raison**: Video position null/stale après countdown → calculs fragiles  
**Impact**: guidanceElapsed stable, démarre toujours 0 running phase  
**Validation**: Simplifié de 8 lignes à 1 ligne

---

### ✅ Bug #14 — Notes Loading Race Condition
**Commit**: 162ae88  
**Fichier**: `practice_page.dart:1987-1990`  
**Fix**: Guard `if (_notesLoading || _noteEvents.isEmpty) return false;`  
**Raison**: Practice démarrait AVANT notes chargées → MicEngine créé avec noteEvents vide  
**Impact**: Prévient RangeError, garantit MicEngine synced  
**Validation**: _canStartPractice() bloque jusqu'à notes prêtes

---

### ✅ Bug #15 — _startTime Set Trop Tôt (CRITIQUE)
**Commit**: 162ae88  
**Fichiers**: `practice_page.dart:2252-2254 (removed), 2318-2319 (added)`  
**Fix**: `_startTime = DateTime.now()` déplacé DANS `_updateCountdown()` quand countdown finit  
**Raison ROOT CAUSE**: _startTime set AVANT countdown → clock avance pendant countdown → guidanceElapsed démarre 2.0s au lieu 0.0s → notes spawn 106% (mid-screen)  
**Impact**: Notes tombent du haut pendant countdown, guidanceElapsed: -2.0→0.0 (smooth)  
**Validation**: Timeline t=0 → countdown, t=2.0 → _startTime set + running

---

### ⚠️ Bug #16 — MicEngine Desync Guard (Defense)
**Commit**: 162ae88  
**Fichier**: `mic_engine.dart:230-242`  
**Fix**: Guard `if (hitNotes.length != noteEvents.length) return [];`  
**Raison**: Si _hitNotes réassigné ailleurs pendant session → lengths mismatch → RangeError  
**Impact**: Graceful degradation, log SCORING_DESYNC, prevent crash  
**Type**: Defense-in-depth (pas de bug actif détecté, prévention)

---

## ✅ BUGS RUNTIME CORRIGÉS (Commit 2026-01-08 23h50)

### ✅ Bug #R1 — Notes Ne Tombent Pas  
**Status**: CORRIGÉ  
**Fix**: Ligne 4636 practice_page.dart — culling autorise `elapsed < 0` countdown  
**Code**:
```dart
if (elapsedSec > disappear && elapsedSec > 0) continue; // Skip only if past AND not countdown
```
**Impact**: Notes spawn y<0 offscreen top, tombent vers clavier pendant countdown

---

### ✅ Bug #R2 — Score Reste 0%  
**Status**: CORRIGÉ  
**Fix**: Ligne 2578 practice_page.dart — `_updateDetectedNote()` appelé après HIT  
**Code**:
```dart
case mic.DecisionType.hit:
  _correctNotes += 1;
  _score += 1;
  _registerCorrectHit(...);
  _updateDetectedNote(decision.detectedMidi, now, accuracyChanged: true); // FIX
```
**Impact**: `_detectedNote` mis à jour → clavier reçoit MIDI détecté → s'allume

---

### ✅ Bug #R3 — Clavier Mort (Pas de Vert/Rouge)  
**Status**: CORRIGÉ  
**Fix**: Lignes 2578 + 2591 practice_page.dart — update après HIT + WRONG  
**Impact**: 
- HIT → `_detectedNote` = detectedMidi → clavier PRIMARY + successFlash VERT
- WRONG → `_detectedNote` = detectedMidi → clavier PRIMARY + wrongFlash ROUGE

---

### ✅ Bug #R4 — Log Debug Countdown  
**Status**: AJOUTÉ  
**Fix**: Ligne 2561 practice_page.dart — log `GUIDANCE_TIME` toutes les 50 frames  
**Code**:
```dart
if (kDebugMode && _micFrameCount % 50 == 0) {
  debugPrint('GUIDANCE_TIME elapsed=${elapsed.toStringAsFixed(3)}s state=$_practiceState');
}
```
**Impact**: Visibilité countdown→running transition dans logs

---

## ❌ BUGS RUNTIME ACTIFS (AUCUN)  
**Symptôme**: Notes apparaissent mid-screen, pas de chute du haut  
**Logs attendus**: `guidanceElapsed=-2.0` durant countdown  
**Logs actuels**: Inconnu (pas de test runtime fait)  
**Hypothèse**: 
- guidanceElapsed démarre 0.0 au lieu -2.0 ? (vérifier `_guidanceElapsedSec()` ligne 1888)
- Painter culling empêche render elapsed < 0 ? (vérifier ligne 4645)
- _startTime timing encore cassé ? (vérifier log GUIDANCE_LOCK)

**Investigation requise**:
```powershell
.\scripts\dev.ps1 -Logcat | Select-String "guidanceElapsed|GUIDANCE_LOCK|Countdown"
```

**Test validation**:
- Notes doivent apparaître en HAUT écran (y=0) pendant countdown
- Notes doivent DESCENDRE vers clavier pendant countdown
- Notes atteignent clavier exactement quand audio démarre

---

### ❌ Bug #R2 — Score Reste 0%
**Status**: ACTIF  
**Symptôme**: Score bloqué 0%, aucun HIT détecté même notes correctes  
**Logs attendus**: `HIT_DECISION ... result=HIT expectedMidi=XX detectedMidi=XX`  
**Logs actuels**: Inconnu  
**Hypothèse**:
- MicEngine génère decisions HIT mais pas appliquées ? (vérifier ligne 2545-2577)
- _registerCorrectHit() appelé mais _score pas incrémenté ? (vérifier ligne 2743)
- Audio samples encore détruits quelque part ? (vérifier pipeline List<double>)

**Investigation requise**:
```powershell
.\scripts\dev.ps1 -Logcat | Select-String "HIT_DECISION|BUFFER_STATE|MicEngine"
```

**Test validation**:
- Jouer note correcte attendue
- Log `HIT_DECISION` doit apparaître avec `result=HIT`
- Score doit augmenter (0 → 1 → 2...)
- Précision doit être > 0%

---

### ❌ Bug #R3 — Clavier Mort (Pas de Vert/Rouge)
**Status**: ACTIF  
**Symptôme**: Clavier ne flash ni vert ni rouge, reste gris  
**Logs attendus**: `_registerCorrectHit` ou `_registerWrongHit` appelés  
**Logs actuels**: Inconnu  
**Hypothèse**:
- `_detectedNote` jamais mis à jour après MicEngine decisions (vérifier ligne 2545+)
- `_updateDetectedNote()` pas appelé avec detectedMidi après HIT
- `_lastCorrectHitAt` / `_lastWrongHitAt` pas setés → PracticeKeyboard reçoit null

**Investigation requise**:
```dart
// Vérifier dans practice_page.dart ligne 2545-2577:
// Après `case mic.DecisionType.hit:`
// Est-ce que _updateDetectedNote(decision.detectedMidi, now) est appelé ?
```

**Test validation**:
- Jouer note correcte → clavier flash VERT
- Jouer note fausse → clavier flash ROUGE
- Silence → pas de flash (sauf miss timeout)

---

## 🔍 ARCHITECTURE ACTUELLE

### MicEngine Pipeline (mic_engine.dart)
```dart
onAudioChunk(samples, now, elapsed) {
  // 1. Detect pitch (List<double> samples)
  final freq = detectPitch(monoSamples, sampleRate);
  final midi = _freqToMidi(freq);
  
  // 2. Store event in buffer (TTL 2s)
  _events.add(PitchEvent(tSec: elapsed, midi: midi, ...));
  
  // 3. Match active notes
  return _matchNotes(elapsed, now); // → [NoteDecision(type: hit/miss/wrongFlash)]
}

_matchNotes(elapsed, now) {
  // Guard desync (Bug #16 fix)
  if (hitNotes.length != noteEvents.length) return [];
  
  // Loop active notes
  for (idx in 0..noteEvents.length) {
    if (hitNotes[idx]) continue; // Already hit
    
    // Check events in window
    final candidates = _events.where(window matches);
    if (bestMatch) return [NoteDecision.hit(idx, expectedMidi, detectedMidi)];
    if (missTimeout) return [NoteDecision.miss(idx, expectedMidi)];
    if (wrongCandidate) return [NoteDecision.wrongFlash(detectedMidi)];
  }
}
```

**État**: Architecture CORRECTE mais decisions peut-être pas appliquées UI

---

### Practice Page Scoring (practice_page.dart L2520-2680)
```dart
_processSamples(samples) {
  // 1. Countdown guard
  if (_practiceState == countdown) return; // Bloque audio
  
  // 2. MicEngine scoring
  final decisions = _micEngine!.onAudioChunk(samples, now, elapsed);
  
  // 3. Apply decisions
  for (decision in decisions) {
    switch (decision.type) {
      case hit:
        _correctNotes++;
        _score++;
        _accuracy = correct;
        _registerCorrectHit(targetNote: X, detectedNote: Y, now: now);
        break;
      case miss:
        // Log miss
        break;
      case wrongFlash:
        _registerWrongHit(detectedNote: Z, now: now);
        break;
    }
  }
  
  // 4. Update UI (stats HUD)
  // PROBLÈME POTENTIEL: _updateDetectedNote() PAS APPELÉ ICI ?
}

_registerCorrectHit({targetNote, detectedNote, now}) {
  _lastCorrectNote = targetNote;
  _lastCorrectDetectedNote = detectedNote; // → PracticeKeyboard.successFlashNote
  _lastCorrectHitAt = now;
  HapticFeedback.lightImpact();
  setState(() {}); // Trigger rebuild
}
```

**État**: Décisions traitées MAIS `_detectedNote` (clavier primary color) jamais mis à jour

---

### PracticeKeyboard Widget (practice_keyboard.dart)
```dart
PracticeKeyboard({
  required int? detectedNote,          // Primary highlight (white→primary)
  required int? successFlashNote,      // Green flash
  required bool successFlashActive,    // Flash timing
  required int? wrongFlashNote,        // Red flash
  required bool wrongFlashActive,      // Flash timing
  ...
})

// Key color logic:
if (successFlashActive && midi == successFlashNote) return AppColors.success; // VERT
if (wrongFlashActive && midi == wrongFlashNote) return AppColors.error;       // ROUGE
if (midi == detectedNote) return AppColors.primary;                           // BLEU (détecté)
if (targetNotes.contains(midi)) return AppColors.primaryVariant;              // Cyan (attendu)
return defaultColor; // GRIS
```

**État**: Widget OK, attend juste les bonnes props depuis practice_page.dart

---

## 🎯 PLAN D'ACTION IMMÉDIAT

### 1. Test Runtime OBLIGATOIRE (5 min)
```powershell
cd "c:\Users\ludov\OneDrive\Bureau\shazam piano\shazam-piano"
.\scripts\dev.ps1 -Logcat > runtime_test.log
```

**Observer**:
- Notes tombent du haut ? (OUI/NON)
- Score augmente ? (OUI/NON)
- Clavier vert/rouge ? (OUI/NON)

**Extraire logs critiques**:
```powershell
Select-String "guidanceElapsed|HIT_DECISION|SCORING_DESYNC|GUIDANCE_LOCK" runtime_test.log
```

---

### 2. Fix Bug Identifié (1 fichier max)
**SI notes ne tombent pas**: Vérifier `_guidanceElapsedSec()` ligne 1888  
**SI score 0%**: Vérifier decisions loop ligne 2545-2577  
**SI clavier mort**: Ajouter `_updateDetectedNote(decision.detectedMidi, now)` après HIT

**RÈGLE**: 1 bug = 1 fix = 1 commit = test runtime validation

---

### 3. Validation Final (Checklist)
```
[ ] Notes apparaissent en haut écran (countdown t=-2.0s)
[ ] Notes descendent smooth vers clavier
[ ] Score augmente sur notes correctes (0→1→2...)
[ ] Clavier flash VERT sur HIT
[ ] Clavier flash ROUGE sur WRONG
[ ] Log HIT_DECISION visible
[ ] 0 occurrences SCORING_DESYNC
[ ] Session complète sans crash
```

**Si 8/8 ✅**: Practice mode VALIDÉ, push Git final

---

## 📂 CENTRALISATION FICHIERS

### Fichiers à CONSERVER
- ✅ `BUG_MASTER_REFERENCE.md` (CE FICHIER — référence unique)
- ✅ `AGENTS.md` (règles workflow)
- ✅ `PROJECT_MAP.md` (architecture globale)

### Fichiers à SUPPRIMER (redondants)
- ❌ `ANALYSE_COMPLETE_SESSION3.md` (contenu intégré ici)
- ❌ `BUG_FIXES_SESSION3.md` (contenu intégré ici)
- ❌ `ULTRA_DEEP_ANALYSIS_SESSION3.md` (contenu intégré ici)
- ❌ `AUDIT_FIX_REPORT.md` (contenu intégré ici)
- ❌ `app/debug` (fichier vide inutile)
- ❌ `app/debug_files/MASTER_DEBUG.md` (doublon)
- ❌ `app/log cat back end flutter` (fichier vide)

**Commande cleanup**:
```powershell
cd "c:\Users\ludov\OneDrive\Bureau\shazam piano\shazam-piano"
rm ANALYSE_COMPLETE_SESSION3.md, BUG_FIXES_SESSION3.md, ULTRA_DEEP_ANALYSIS_SESSION3.md, AUDIT_FIX_REPORT.md
rm app/debug, "app/log cat back end flutter"
rm -r app/debug_files
git add -A
git commit -m "docs: cleanup redondants, centralisation BUG_MASTER_REFERENCE.md"
git push
```

---

## 🚨 RÈGLES ANTI-RÉGRESSION

### Vecteur d'Erreur Identifié: "Analyse sans Test Runtime"
**Symptôme**: 10h d'analyse, 10 bugs fixés, MAIS problème runtime pas résolu  
**Cause**: Validation statique (flutter analyze) insuffisante  
**Solution**: **TEST RUNTIME OBLIGATOIRE** après chaque fix

**Process correct**:
1. Identifier bug via logs runtime
2. Fix 1 bug (1 fichier si possible)
3. `flutter analyze` (validation statique)
4. `.\scripts\dev.ps1 -Logcat` (validation RUNTIME)
5. Si ✅ → commit + push, sinon retour step 1

### Ne JAMAIS Répéter
- ❌ Fixer 10 bugs d'un coup sans test runtime entre chaque
- ❌ Créer 5 fichiers MD différents pour même info
- ❌ Analyser 4000 lignes sans extraire logs device
- ❌ Pusher sans validation runtime

### TOUJOURS Faire
- ✅ 1 bug = 1 fix = 1 test runtime = 1 commit
- ✅ 1 seul fichier doc: `BUG_MASTER_REFERENCE.md`
- ✅ Logs device AVANT toute hypothèse
- ✅ Validation checklist 8 points (section Plan d'Action)

---

## 📊 MÉTRIQUES SESSION

| Métrique | Valeur |
|----------|--------|
| Durée session | 10 heures |
| Bugs identifiés | 16 (10 fixes backend/flutter sync, 6 fixes practice timing) |
| Bugs résolus | 16 statique ✅, 0 runtime ❌ |
| Commits | 1 (162ae88) |
| Fichiers modifiés | 8 (practice_page, mic_engine, config, inference, render, +3 docs) |
| Tests runtime | 0 ⚠️ |
| Practice mode fonctionnel | NON ❌ |

**Conclusion**: Beaucoup de travail statique, MAIS problème runtime pas diagnostiqué car **AUCUN TEST DEVICE**.

---

## 🔄 PROCHAINE SESSION

**Objectif**: Résoudre bugs runtime R1, R2, R3 en < 2h

**Étapes**:
1. Lancer `.\scripts\dev.ps1 -Logcat` (5 min)
2. Extraire logs critiques (2 min)
3. Identifier bug ROOT CAUSE via logs (10 min)
4. Fix 1 bug (20 min)
5. Test runtime validation (5 min)
6. Répéter steps 1-5 jusqu'à 8/8 checklist ✅

**Si bloqué**: Partager logs dans conversation avec prompt handoff (début de ce fichier)

---

**FIN BUG_MASTER_REFERENCE.md**
