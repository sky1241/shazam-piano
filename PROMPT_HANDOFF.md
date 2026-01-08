# 🔥 PROMPT HANDOFF — Session Suivante

**Date** : 2026-01-08 00h30  
**Commit HEAD** : `f6a2b82`  
**Status** : 25 bugs fixés, TEST RUNTIME OBLIGATOIRE demain

---

## 🎯 CONTEXTE RAPIDE

**Projet** : ShazaPiano Practice Mode (Flutter + Python Backend)  
**Problème** : 10h debugging, practice mode cassé (notes mid-screen, score 0%, clavier mort)  
**Derniers Fixes** : 5 bugs effectiveLeadIn (1.5s → 2.0s) = ROOT CAUSE notes mid-screen

---

## 📋 CHECKLIST TEST (User DOIT faire demain)

```powershell
.\scripts\dev.ps1 -Logcat
```

**3 questions SEULEMENT** :
1. ✅ Notes tombent du HAUT ? (pas mid-screen)
2. ✅ Score augmente ?
3. ✅ Clavier flash vert/rouge ?

**SI NON** : Copier logs `EFFECTIVE_LEADIN`, `COUNTDOWN_FINISH`, `FIRST_FRAME_RUNNING`, `HIT_DECISION`

---

## 🔍 FICHIERS CRITIQUES

### 1. practice_page.dart (4853 lignes)
**Chemin** : `app/lib/presentation/pages/practice/practice_page.dart`

**Sections clés** :
- **L2265-2285** : `_computeEffectiveLeadIn()` — DOIT retourner 2.0s (pas 1.5s)
- **L2540-2610** : `_processSamples()` — MicEngine scoring + decisions HIT/MISS/WRONG
- **L1888-1920** : `_guidanceElapsedSec()` — Synthetic elapsed countdown [-2.0 → 0.0]
- **L4605-4680** : `_FallingNotesPainter.paint()` — Culling + Y position notes

**Variables critiques** :
```dart
static const double _fallLeadSec = 2.0;        // Notes tombent 2s
static const double _practiceLeadInSec = 1.5;  // Countdown BASE (écrasé par _effectiveLeadInSec)
late double _effectiveLeadInSec = 2.0;         // VRAI countdown (TOUJOURS 2.0s maintenant)
```

**Logs debug** :
- `EFFECTIVE_LEADIN computed=X.XXs` → DOIT être 2.000s
- `COUNTDOWN_FINISH countdownCompleteSec=X.X finalElapsed=X.XXX` → DOIT être 2.0 et 0.000
- `FIRST_FRAME_RUNNING elapsed=X.XXs clock=X.XXs` → DOIT être 0.000 et 0.000
- `GUIDANCE_TIME elapsed=X.XXs state=countdown/running` → countdown doit commencer -2.0
- `HIT_DECISION ... result=HIT` → Si notes correctes jouées

---

### 2. mic_engine.dart (485 lignes)
**Chemin** : `app/lib/presentation/pages/practice/mic_engine.dart`

**Fonction critique** :
- **L95-150** : `onAudioChunk()` — Détection pitch → event buffer → note matching → decisions

**Problème connu** : Si `hitNotes.length != noteEvents.length` → ABORT scoring (RangeError)

**Logs debug** :
- `SCORING_DESYNC` → Si desync hitNotes/noteEvents
- `HIT_DECISION expectedMidi=XX detectedMidi=XX distance=X` → Matching notes

---

### 3. BUG_MASTER_REFERENCE.md
**Contenu** : 25 bugs documentés (16 statiques + 9 runtime)

**Structure** :
- Bugs #1-6 : Backend/Flutter desync (timeouts, durations, offsets)
- Bugs #7-16 : Practice timing (countdown, clock, references)
- Bugs R1-R5 : Runtime (culling, score, clavier, logs, effectiveLeadIn)

**Section importante** : Bug #R5 (effectiveLeadIn 1.5s → 2.0s) = ROOT CAUSE notes mid-screen

---

### 4. ANALYSE_STRUCTURELLE_BUGS.md
**Contenu** : 6 patterns bugs + prompt Codex

**Patterns récurrents** :
1. Early Returns Cascade (audio gates bloquent scoring)
2. Reference Stability (Dart `=` crée nouvelle liste)
3. Timebase Drift (countdown timing critique)
4. Backend/Flutter Desync (6 valeurs dupliquées)
5. UI Update Disconnect (decisions ≠ UI state)

**NE PAS relire sauf si boucle infinie recommence**.

---

## 🐛 BUGS FIXÉS (Dernière Session)

### Bug R5 : effectiveLeadIn 1.5s → 2.0s ✅
**Commit** : `f6a2b82`  
**Root Cause** : 5 endroits assignaient `_effectiveLeadInSec = 1.5s` au lieu de `max(1.5, 2.0) = 2.0s`  
**Impact** : Countdown durait 1.5s MAIS notes besoin 2s → velocity 1.33x → notes spawn 33% trop bas

**Lignes fixées** :
- L2271 : `_computeEffectiveLeadIn()` notes vides
- L3233 : `_loadNoteEvents()` reset cleared
- L3244 : `_loadNoteEvents()` jobId null
- L3384 : `_loadNoteEvents()` DioException
- L3400 : `_loadNoteEvents()` catch general

**TOUS utilisent maintenant** : `_effectiveLeadInSec = max(_practiceLeadInSec, _fallLeadSec);`

---

## 🚨 SI PROBLÈME PERSISTE

### Symptôme : Notes TOUJOURS mid-screen

**Vérifier dans l'ORDRE** :

1. **Log `EFFECTIVE_LEADIN` absent ou != 2.000s**  
   → `_computeEffectiveLeadIn()` pas appelé OU écrasé après  
   → Chercher TOUS `_effectiveLeadInSec =` dans practice_page.dart  
   → `grep_search` query=`_effectiveLeadInSec =` isRegexp=false

2. **Log `COUNTDOWN_FINISH` countdownCompleteSec != 2.0**  
   → `_updateCountdown()` L2315 utilise mauvaise valeur  
   → Vérifier `final countdownCompleteSec = _effectiveLeadInSec;`

3. **Painter reçoit mauvais fallLead**  
   → Ligne 4244 `_FallingNotesPainter(fallLead: _fallLeadSec)`  
   → DOIT être 2.0 (static const)

4. **`syntheticCountdownElapsedForTest()` map faux**  
   → L178-192 formule : `-fallLeadSec + (progress * fallLeadSec)`  
   → Tester avec t=0 (doit = -2.0), t=2.0 (doit = 0.0)

5. **Culling empêche render**  
   → L4646 `if (elapsedSec > disappear && elapsedSec > 0) continue;`  
   → Supprimer `&& elapsedSec > 0` si notes toujours pas visibles

---

### Symptôme : Score 0%

**Vérifier** :

1. **Log `HIT_DECISION` absent**  
   → MicEngine pas appelé OU early return avant scoring  
   → L2555-2570 : MicEngine DOIT être appelé AVANT tout `if/return`

2. **Log `HIT_DECISION result=HIT` présent MAIS score pas augmenté**  
   → L2578 `case mic.DecisionType.hit:` vérifier `_score += 1;`  
   → Vérifier si `_updateDetectedNote()` appelé APRÈS score++

3. **Log `SCORING_DESYNC`**  
   → `hitNotes.length != noteEvents.length`  
   → L2063 vérifier `_hitNotes.clear(); _hitNotes.addAll(...)`  
   → NE JAMAIS faire `_hitNotes = [];` (crée nouvelle liste)

---

### Symptôme : Clavier mort (pas vert/rouge)

**Vérifier** :

1. **`_updateDetectedNote()` pas appelé après HIT/WRONG**  
   → L2578 après `case hit:` DOIT avoir `_updateDetectedNote(decision.detectedMidi, now, accuracyChanged: true);`  
   → L2591 après `case wrongFlash:` IDEM

2. **PracticeKeyboard reçoit null**  
   → `_lastCorrectNote` ou `_lastWrongDetectedNote` pas setés  
   → Vérifier `_registerCorrectHit()` et `_registerWrongHit()`

---

## 🛠️ COMMANDES UTILES

**Lire fichier critique** :
```
read_file practice_page.dart L2540-2610  (scoring)
read_file practice_page.dart L1888-1920  (guidanceElapsed)
read_file practice_page.dart L4605-4680  (painter)
```

**Chercher variable** :
```
grep_search query="_effectiveLeadInSec =" isRegexp=false includePattern="practice_page.dart"
grep_search query="GUIDANCE_TIME" isRegexp=false includePattern="practice_page.dart"
```

**Vérifier compilation** :
```
run_in_terminal: flutter analyze --no-fatal-infos
```

**Git commit** :
```
git add -A
git commit -m "fix: [description courte]"
git push
```

---

## 🚫 RÈGLES ABSOLUES

### NE JAMAIS FAIRE

1. ❌ Créer nouveau document analyse SAUF si user demande explicitement
2. ❌ Refactor global sans accord (>6 fichiers modifiés)
3. ❌ Ajouter packages (pubspec/requirements) sans accord
4. ❌ Dire "c'est fixé" SANS test runtime device
5. ❌ Patcher symptômes (culling, painter) AVANT root cause (timing, effectiveLeadIn)
6. ❌ Faire `_hitNotes = []` (perd référence) → utiliser `.clear() + .addAll()`

### TOUJOURS FAIRE

1. ✅ Lire code AVANT fixer (3-5 lectures parallèles OK)
2. ✅ Fixer 1 bug à la fois (1 fix = 1 commit)
3. ✅ Ajouter logs debug si timing suspect
4. ✅ Vérifier compilation (`flutter analyze`) AVANT commit
5. ✅ Demander test runtime APRÈS commit
6. ✅ Documenter fix dans BUG_MASTER_REFERENCE.md

---

## 📊 MÉTRIQUES SESSION

**Bugs fixés** : 25 (16 statiques + 9 runtime)  
**Fichiers modifiés** : 2 (practice_page.dart, mic_engine.dart)  
**Commits** : 4 (162ae88, 4daa1f7, 6edf514, c261f01, f6a2b82)  
**Durée** : 10h+ (user fatigué)  
**Status** : Code compile ✅, test runtime PENDING

---

## 🎬 PROMPT POUR NOUVELLE SESSION

**Copie-colle ce texte quand user revient** :

```
Bonjour. Je reprends session ShazaPiano practice mode.

CONTEXTE:
- 25 bugs fixés hier (commit f6a2b82)
- Bug R5 (effectiveLeadIn 1.5s→2.0s) ROOT CAUSE notes mid-screen
- Code compile OK, test runtime PAS ENCORE FAIT

J'AI TESTÉ? [OUI/NON]

SI OUI:
1. Notes tombent du HAUT? [OUI/NON]
2. Score augmente? [OUI/NON]  
3. Clavier vert/rouge? [OUI/NON]

SI NON sur 1+ points:
→ Copie logs contenant: EFFECTIVE_LEADIN, COUNTDOWN_FINISH, FIRST_FRAME_RUNNING, HIT_DECISION

SI PAS ENCORE TESTÉ:
→ Lance: .\scripts\dev.ps1 -Logcat
→ Réponds 3 questions ci-dessus

FICHIER RÉFÉRENCE: PROMPT_HANDOFF.md (ce fichier)
BUGS HISTORIQUE: BUG_MASTER_REFERENCE.md
```

---

**FIN PROMPT_HANDOFF.md**

User : lis ce fichier AVANT toute action. Gagnes 1h de contexte.
