# 🎯 PROMPT CHATGPT — ANALYSE BUGS SESSION 4 (12 JAN 2026)

Copie-colle ce prompt à ChatGPT avec **la vidéo** + le fichier **`logcatdebug`** de ta session de test.

---

# 🎬 MISSION : Confirmer diagnostic + corrections ciblées

## 📖 CONTEXTE

**Session 4** : Nouveau système scoring Pitch/Timing/Sustain/Wrong implémenté.

**ANALYSE LOGS (12 jan 2026 06:25)** :
```
SESSION4_FINAL: perfect=0 good=0 ok=1 miss=5 wrong=2
```
**Attendu** : 9 ok/perfect, 0 miss, 0 wrong  
**Réel** : 1 ok, 5 miss, 2 wrong → ❌ **Échec total**

**CAUSE RACINE IDENTIFIÉE DANS LOGS** :
```
HIT_DECISION ... result=HIT reason=pitch_match_direct
SESSION4_GATING_HIT: Skip low-confidence hit midi=63 rms=0.002 conf=0.00
```
**Problème** : Notes **MATCHÉES** (result=HIT) MAIS **bloquées par GATING** car `conf < _minConfHit=0.12`

**Statistiques logs précises** :
- 3 HIT détectés par matcher
- 2 bloqués par gating : conf=0.00, conf=0.12 (limite exacte)
- 1 passé : conf=0.43 > 0.12 ✅
- 6 notes deviennent MISS (match=none, dt=null)
- 2 WRONG_NOTE (notes rejetées deviennent wrong après timeout)

**BUGS OBSERVÉS VIDÉO** :
1. 🔴 **P0 GATING TROP STRICT** : Notes piano conf=0.08-0.12 bloquées (seuil 0.12 trop haut)
2. 🔴 **P0 VERT → ROUGE** : Note verte valide devient rouge après (conflit OLD/NEW systems)
3. 🔴 **P0 FANTÔMES MICRO** : Touches rouges jamais jouées (gating wrong 0.45 insuffisant)
4. 🔴 **P0 COMPTAGE INVERSÉ** : Dialog affiche OLD system au lieu de NEW

**Objectif** : **CONFIRMER VISUELLEMENT** ces 4 bugs + **APPLIQUER CORRECTIONS CIBLÉES**.

---

## 🎥 ANALYSE VIDÉO — BUGS P0 CRITIQUES OBSERVÉS

### 🔴 BUG P0 #1 : GATING TROP STRICT (PRIORITÉ MAXIMALE)
**Symptôme logs confirmé** : 
```
HIT_DECISION ... result=HIT reason=pitch_match_direct
SESSION4_GATING_HIT: Skip low-confidence hit midi=63 rms=0.002 conf=0.00
SESSION4_GATING_HIT: Skip low-confidence hit midi=61 rms=0.006 conf=0.12
```
**Impact** : 2/3 notes matchées bloquées car conf < 0.12

**À CHERCHER DANS VIDÉO** :
- [ ] Combien de notes jouées PIANO ne flashent PAS vert ? X/9
- [ ] Notes bloquées : touches légères (faible RMS) OU toutes ?
- [ ] Pattern : début/milieu/fin session OU aléatoire ?
- [ ] Visuel : AUCUN flash (bloqué avant UI) OU flash très bref ?

**RÈGLE ATTENDUE** :
- ✅ Note piano conf=0.08-0.15 = **DOIT PASSER** (piano produit conf faible naturellement)
- ❌ Gating 0.12 bloque notes piano légitimes

**CAUSE CONFIRMÉE**VERT → ROUGE (CONFLIT DUAL SYSTEMS)
**Symptôme logs** : 2 WRONG_NOTE après notes matchées comme HIT
```
RESOLVE_NOTE session=1 idx=5 grade=ok dt=-153.0ms match=3fd54324
WRONG_NOTE session=1 playedId=c9ac3185 pitch=70 reason=No matching expected note
WRONG_NOTE session=1 playedId=246f5523 pitch=61 reason=No matching expected note
```

**À CHERCHER DANS VIDÉO** :
- [ ] Combien de notes VERTES deviennent ROUGES après ? X/9
- [ ] Délai vert→rouge : immédiat (<100ms) / court (100-500ms) / long (>500ms) ?
- [ ] Pattern : APRÈS note correcte OU sur note manquée transformée en wrong ?
- [ ] Timing : Rouge apparaît pendant sustain OU après release ?

**RÈGLE ATTENDUE** :
- ✅ Note matchée grade=ok = **VERT uniquement, jamais rouge**
- ❌ OLD system génère wrong sur même MIDI après NEW system déjà matché

**CAUSE PROBABLE** : OLD system `_registerWrongHit()` actif en parallèle NEW system
**CORRECTION** : Désactiver OLD system flashs si `_useNewScoringSystem=true`
- [ ] Conf fantômes : X.XX (comparer à `_minConfWrong=0.45`)
- [ ] Fréquence Hz fantômes : X Hz (vérifier si harmoniques parasites)

**CAUSE PROBABLE** : MicEngine détection trop sensible (gating 0.45 insuffisant OU harmoniques/écho)
**CORRECTION ATTENDUE** : Augmenter `_minConfWrong` 0.45→0.55 OU `_absMinRms` 0.0020→0.0030

---

### 🔴 BUG P0 #3 : HUD ALÉATOIRE (PRIORITÉ HAUTE)
**Symptôme observé*FANTÔMES MICRO (PRIORITÉ HAUTE)
**Symptôme attendu** : Touches ROUGES jamais jouées (micro détecte fantômes)

**À CHERCHER DANS VIDÉO** :
- [ ] Combien de touches rouges fantômes (MIDI jamais joués) ? X
- [ ] Quels MIDI fantômes : [liste]
- [ ] Pattern : aléatoire / après notes réelles / résonance piano ?
- [ ] Audio : bruit ambiant / harmoniques / écho ?

**À CHERCHER DANS LOGS** :
```
SESSION4_DEBUG_WRONG: ... midi=XX rms=X.XXX conf=X.XX
Expected notes: [60,61,63,70] (si XX absent = fantôme pur)
```
- [ ] RMS fantômes : min/max (comparer `_absMinRms=0.0020`)
- [ ] Conf fantômes : min/max (comparer `_minConfWrong=0.45`)
- [ ] Fréquence Hz : harmoniques parasites ?

**CAUSE PROBABLE** : Gating wrong 0.45 trop permissif pour harmoniques/bruit
**CORRECTION** : `_minConfWrong` 0.45 → **0.55** (bloquer fantômes conf<0.55
---

### 🔴 BUG P0 #4 : HUD/DIALOG DÉSYNCHRONISÉS (PRIORITÉ HAUTE)
**Symptôme logs confirmé** :
```
SESSION4_SCORING_DIFF: old=(prec=0.0% score=0.0) new=(prec=16.7% score=40)
```
Répété 518x → OLD system affiche prec=0.0%, NEW system prec=16.7%

**À CHERCHER DANS VIDÉO** :
- [ ] HUD (tableau au-dessus piano) : Précision affichée X%, Score X, Notes justes X/9
- [ ] Dialog final : Précision X%, Score X, Notes justes X/9, Fautes X
- [ ] Cohérence HUD vs Dialog ? **OUI / NON**
- [ ] Valeurs figées (ne bougent pas) OU aléatoires ?

**À CHERCHER DANS LOGS** :
```
SESSION4_CONTROLLER: Stopped. perfectCount=0 goodCount=0 okCount=1
Dialog: correctNotes=X (devrait être 1)
```
- [ ] Valeur finale NEW system : perfectCount+goodCount+okCount = **1** ✅
- [ ] Dialog/HUD affichent 1 OU 0 ?

**CAUSE CONFIRMÉE** : HUD/Dialog lisent OLD `_correctNotes=0` au lieu de NEW `okCount=1`
**CORRECTION** : HUD/Dialog déjà corrigés (commit bd9d81f), vérifier visuel cohérent

---GATING TROP STRICT
**Chercher notes bloquées par gating** :
```
HIT_DECISION ... result=HIT reason=pitch_match_direct
SESSION4_GATING_HIT: Skip low-confidence hit midi=XX rms=X.XXX conf=X.XX
```

**Questions CRITIQUES** :
- [ ] Combien logs `SESSION4_GATING_HIT` ? X (logs actuels : 2)
- [ ] Conf bloquées : min/max (logs actuels : conf=0.00, conf=0.12)
- [ ] Pattern : toutes notes piano OU seulement légères ?
- [ ] RMS bloquées : <0.010 (très faible) OU >0.010 (normale) ?
- [ ] Extraits 5 lignes montrant GATING_HIT :

**DIAGNOSTIC LOGS ACTUELS** :
```
midi=63 rms=0.002 conf=0.00 → BLOQUÉ (conf << 0.12)
midi=61 rms=0.006 conf=0.12 → BLOQUÉ (conf = limite exacte)
midi=61 rms=0.021 conf=0.43 → PASSÉ ✅
```
**Preuve** : Notes conf=0.08-0.12 bloquées, seulement conf>0.12 passent

**DIAGNOSTIC** :
- Si `SESSION4_SKIP_SUSVERT → ROUGE (DUAL SYSTEMS)
**Chercher conflit NEW/OLD systems** :
```
RESOLVE_NOTE session=1 idx=X grade=ok match=XXXXX (NEW system OK)
[...quelques lignes...]
WRONG_NOTE session=1 playedId=XXXXX pitch=XX reason=No matching expected note
```

**Questions CRITIQUES** :
- [ ] Combien logs `WRONG_NOTE` ? X (logs actuels : 2)
- [ ] WRONG après note déjà matchée (grade=ok) ? **OUI / NON**
- [ ] MIDI wrongs : [70, 61] (logs actuels)
- [ ] Pattern : wrongs sur notes déjà résolues OU nouvelles détections ?
- [ ] Extraits montrant WRONG après grade=ok :

**DIAGNOSTIC LOGS ACTUELS** :
```
RESOLVE_NOTE idx=5 grade=ok midi=61 ← NEW system matche
[délai]
WRONG_NOTE playedId=c9ac3185 pitch=70 ← OLD system génère wrong
WRONG_NOTE playedId=246f5523 pitch=61 ← OLD system génère wrong
```
**Preuve** : 2 wrongs générés APRÈS résolution ok → conflit dual systewrongs bloqués

**DIAGNOSTIC** :
- Si RMS > 0.0020 ET conf > 0.45 → gating 0.45 insuffisant, monter à 0.55
- Si RMS < 0.0020 → harmoniques/bruit passe sous radar, monter `_absMinRms` à 0.0030
- Si anti-spam bloque peu → fenêtre 500ms insuffisante, monter à 700ms
FANTÔMES MICRO
**Chercher détections fantômes** :
```
SESSION4_DEBUG_WRONG: ... midi=XX rms=X.XXX conf=X.XX
Expected notes: [60,61,63,70] (si XX absent = fantôme)
```

**Questions CRITIQUES** :
- [ ] Combien logs `SESSION4_DEBUG_WRONG` ? X
- [ ] MIDI wrongs vs attendus : fantômes purs OU harmoniques notes réelles ?
- [ ] RMS wrongs : min/max (comparer `_absMinRms=0.0020`)
- [ ] Conf wrongs : min/max (comparer `_minConfWrong=0.45`)
- [ ] Logs `SESSION4_GATING` (wrongs bloqués) ? Combien ?

**DIAGNOSTIC ATTENDU** :
- Si wrongs conf=0.45-0.55 → gating 0.45 insuffisant, monter à 0.55
- Si wrongs harmoniques (e.g. MIDI=82 pour note=70) → pitch matcher trop permissif
- Si RMS < 0.0020 → bruit bas niveau, monter `_absMinRms` à 0.0030
**DIAGNOSTIC** :
- Si `correctCount` OK logs mais dialog faux → Dialog affiche OLD `_correctNotes` (ligne ~4625)
- Si `correctCount` ne progresse pas logs → NEW system ne matche pas (gating trop strict ?)

---
HUD/DIALOG DÉSYNCHRONISÉS
**Chercher désynchronisation OLD/NEW** :
```
SESSION4_SCORING_DIFF: old=(prec=0.0% score=0.0) new=(prec=16.7% score=40)
SESSION4_CONTROLLER: Stopped. perfectCount=0 goodCount=0 okCount=1
```

**Questions CRITIQUES** :
- [ ] Combien logs `SESSION4_SCORING_DIFF` ? X (logs actuels : 518x)
- [ ] OLD prec vs NEW prec : désynchronisation combien % ?
- [ ] Valeur finale NEW : `perfectCount+goodCount+okCount` = **1** (logs actuels)
- [ ] Dialog affiche combien notes justes ? X (devrait être 1)
- [ ] HUD affiche combien notes justes ? X (devrait être 1)

**DIAGNOSTIC LOGS ACTUELS** :
```
old=(prec=0.0% score=0.0) ← OLD system figé à 0
new=(prec=16.7% score=40) ← NEW system progresse correctement
```
**Preuve** : OLD system ne met PAS à jour `_correctNotes`, reste 0 pendant session
**Note** : CorrectiLOGS ACTUELS (12 JAN 06:25)
**Comptage confirmé** :
- ✅ Total `SESSION4_DEBUG_HIT` : **3** (devrait être 9) → ❌ 6 manquantes
- ✅ Total `SESSION4_GATING_HIT` : **2** (notes bloquées conf<0.12)
- ✅ Total `RESOLVE_NOTE grade=ok` : **1** (seule note passée)
- ✅ Total `RESOLVE_NOTE grade=miss` : **5** (notes jamais matchées)
- ✅ Total `WRONG_NOTE` : **2** (après résolution notes)
- ✅ Final NEW system : `perfectCount=0 goodCount=0 okCount=1 missCount=5 wrongCount=2`
- ✅ Total `SESSION4_SCORING_DIFF` : **518x** (OLD=0.0% vs NEW=16.7%)

**VERDICT LOGS** :
1. ❌ **BUG P0 #1 CONFIRMÉ** : 2 notes bloquées gating (conf=0.00, conf=0.12)
2. ❌ **BUG P0 #2 CONFIRMÉ** : 2 WRONG_NOTE générés après grade=ok
3. ⚠️ **BUG P0 #3 À VÉRIFIER VIDÉO** : Fantômes micro (pas de SESSION4_DEBUG_WRONG dans logs)
4. ❌ **BUG P0 #4 CONFIRMÉ** : OLD system figé prec=0.0%, NEW prec=16.7%0)
- [ ] Total `SESSION4_GATING` (wrongs bloqués) : X (OK si >0)
- [ ] Total `SESSION4_SKIP_SUSTAIN_WRONG` : X (corrections P0, devrait être >0 si bug #1)
- [ ] Final `correctCount` (NEW) : X (devrait être 9)
- [ ] Final `wrongCount` (NEW) : X (devrait être 0)
- [ ] Final `_correctNotes` (OLD) : X (si mentionné)

---

## 🎯 VERDICT & CORRECTIONS P0 OBLIGATOIRES

### ✅ Si 0 bugs observés (IMPROBABLE vu symptômes)
```
✅ 9/9 flashs verts, 0 rouge
✅ Pas de vert→rougeCIBLÉES (LOGS CONFIRMÉS)

#### 🔴 P0 #1 : GATING TROP STRICT

**CONFIRMÉ LOGS** : 2 notes bloquées conf=0.00, conf=0.12 < seuil 0.12

**BUG P0 #1 : SEUIL CONFIDENCE HIT TROP HAUT**  
**Priorité** : P0 (BLOQUANT CRITIQUE)  
**Cause racine** : `_minConfHit=0.12` bloque notes piano conf=0.08-0.12  
**Ligne** : `practice_page.dart:345`  
**Correction** :
```dart
// AVANT
final double _minConfHit = 0.12;

// APRÈS
final double _minConfHit = 0.08; // P0 #1: Piano produit conf=0.08-0.15, ne pas bloquer
```
**Impact attendu** :
- 2 notes bloquées → passent (conf=0.00 ?, conf=0.12 ✅)
- **Note** : conf=0.00 suspect (RMS=0.002 très faible), peut-être bruit
- Si conf=0.00 passe → ajouter `rms > 0.005` comme garde-fou

**Justification** : Piano acoustique produit naturellement conf=0.08-0.15 sur touches légères
// LIGNE 2895 (dans case wrongFlash, branche else OLD SYSTEM)
} else {
  // OLD SYSTEM: Flash wrong note
  // BUG P0 #1 FIX: Désactiver OLD flashs si NEW system actif
  if (!_useNewScoringSystem) {
    _registerWrongHit(detectedNote: decision.detectedMidi!, now: now);
  }
}
```
**Justification** : OLD system _registerCorrectHit + _registerWrongHit set `_lastCorrectNote`/`_lastWrongNote` utilisés pour flashs clavier → conflit avec NEW system

---

#### 🔴 P0 #2 : FANTÔMES MICRO

**Si RMS > 0.0020 ET conf > 0.45** :
VERT → ROUGE (DUAL SYSTEMS)

**CONFIRMÉ LOGS** : 2 WRONG_NOTE générés après notes déjà matchées grade=ok

**BUG P0 #2 : CONFLIT OLD/NEW SYSTEMS FLASHS**  
**Priorité** : P0 (BLOQUANT VISUEL)  
**Cause racine** : OLD system `_registerWrongHit()` actif en parallèle NEW system  
**Lignes** : `practice_page.dart:2779-2805` (OLD hit) + `2895` (OLD wrong)  
**Correction** :
```dart
// LIGNE 2779 (dans case hit, branche else OLD SYSTEM)
} else {
  // OLD SYSTEM: Score based on timing precision
  // P0 #2 FIX: Désactiver OLD flashs si NEW system actif
  if (!_useNewScoringSystem) {
    final timingErrorMs = (decision.dtSec?.abs() ?? 0.0) * 1000.0;
    final timingScore = _calculateTimingScore(timingErrorMs);
    _correctNotes += 1;
    _score += timingScore;
    _registerCorrectHit(...);
  }
}

// LIGNE 2895 (dans case wrongFlash, branche else OLD SYSTEM)
} else {
  // OLD SYSTEM: Flash wrong note
  // P0 #2 FIX: Désactiver OLD flashs si NEW system actif
  if (!_useNewScoringSystem) {
    _registerWrongHit(detectedNote: decision.detectedMidi!, now: now);
  }
}
```FANTÔMES MICRO

**À VÉRIFIER VIDÉO** : Aucun log `SESSION4_DEBUG_WRONG` dans fichier actuel

**BUG P0 #3 : GATING WRONG INSUFFISANT (SI FANTÔMES CONFIRMÉS)**  
**Priorité** : P0 (si vidéo montre fantômes)  
**Cause probable** : `_minConfWrong=0.45` trop permissif harmoniques/bruit  
**Ligne** : `practice_page.dart:346`  
**Correction** :
```dart
// AVANT
final double _minConfWrong = 0.45;

// APRÈS
final double _minConfWrong = 0.55; // P0 #3: Bloquer fantômes conf<0.55
```

**OU SI BRUIT BAS RMS** :
```dartHUD/DIALOG DÉSYNCHRONISÉS

**CONFIRMÉ LOGS** : OLD prec=0.0%, NEW prec=16.7% (518 occurrences)

**BUG P0 #4 : DÉJÀ CORRIGÉ (COMMIT bd9d81f)**  
**Priorité** : P0 (correction appliquée, vérifier vidéo)  
**Correction déjà appliquée** :
```dart
// practice_page.dart ligne 4618-4632
if (_useNewScoringSystem && _newController != null) {
  final state = _newController!.currentScoringState;
  correctNotes = state.perfectCount + state.goodCount + state.okCount;
  wrongNotes = state.wrongCount + state.missCount;
} else {
  correctNotes = _correctNotes;
  wrongNotes = total - _correctNotes;
}
```

**Action requise VIDÉO** :
- [ ] HUD affiche : "Notes justes: 1/9" (NEW system okCount=1) OU "0/9" (OLD figé) ?
- [ ] Dialog affiche : "Notes justes: 1/9, Fautes: 8" (NEW) OU "0/9, Fautes: 9" (OLD) ?

**Si vidéo montre ENCORE 0/9** → Correction bd9d81f non appliquée, rebuild nécessaire

**Si wrongCount=0 logs mais dialog=9 fautes** :

**BUG P0 #4B : FORMULE DIALOG FAUSSE**  
**Priorité** : P0 (BLOQUANT)  
**Cause racine** : Dialog calcule `total - _correctNotes` (OLD) au lieu de `wrongCount + missCount` (NEW)  
**Ligne suspecte** : `practice_page.dart:~4625`  
**Correction** :
```dart
// AVANT
final wrongNotes = total - _correctNotes;

// APRÈS
final wrongNotes = _newController!.currentScoringState.wrongCount +
                   _newController!.currentScoringState.missCount;
```

---**, fournis :

1. **Vidéo** : Symptôme visuel (X/9 notes affectées)
2. **Logs** : Pattern confirmé (extrait 5 lignes)
3. **Verdict** : CONFIRMÉ OU NON OBSERVÉ
4. **Correction** : Quel patch appliquer (numéro P0 #X ci-dessus)

**Format minimal réponse** :
```
BUG P0 #1 GATING:
Vidéo: X/9 notes piano ne flashent PAS vert (bloquées)
Logs: SESSION4_GATING_HIT ... conf=0.12 (2 occurrences)
Verdict: CONFIRMÉ
Correction: _minConfHit 0.12→0.08

BUG P0 #2 VERT→ROUGE:
Vidéo: X notes vertes deviennent rouges après Xms
Logs: WRONG_NOTE après RESOLVE_NOTE grade=ok (2 occurrences)
Verdict: CONFIRMÉ
Correction: Désactiver OLD flashs (lignes 2779, 2895)

BUG P0 #3 FANTÔMES:
Vidéo: X touches rouges jamais jouées
Logs: Aucun SESSION4_DEBUG_WRONG
Verdict: NON OBSERVÉ (ou SESSION4_DEBUG_WRONG manquant)
Correction: Si confirmé vidéo → _minConfWrong 0.45→0.55

BUG P0 #4 HUD:
Vidéo: HUD affiche 0/9 notes justes (devrait être 1/9)
Logs: SESSION4_SCORING_DIFF old=0.0% new=16.7% (518x)
Verdict: CONFIRMÉ (correction bd9d81f appliquée, vérifier rebuild)
Correction: Déjà appliquée (HUD/Dialog NEW state)
```

---

**Merci ChatGPT ! Confirme visuellement ces 4 bugs pour valider corrections ciblées

---

**Merci ChatGPT ! Analyse P0 ciblée pour débloquer Session 4.** 🚀
