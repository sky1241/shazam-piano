# 🎯 PROMPT CHATGPT — VALIDATION POST-CORRECTIONS P0/P1 + NOUVEAUX BUGS

Copie-colle ce prompt à ChatGPT avec **la vidéo** + le fichier **`logcatdebug`** de ta nouvelle session de test.

---

# 🎬 MISSION : Validation corrections + détection bugs critiques observés vidéo

## 📖 CONTEXTE

**Session 4** : Nouveau système de scoring Pitch/Timing/Sustain/Wrong implémenté.

**Corrections dernière vague appliquées** :
- ✅ **P0** : windowMs 200ms → 300ms (matcher dt jusqu'à +300ms)
- ✅ **P1** : Gating séparé _minConfHit=0.12 vs _minConfWrong=0.35 (débloque piano conf 0.12-0.15)
- ✅ **P0-A** : Latence micro 300ms dans calcul miss (`onTimeUpdate`)
- ✅ **P0-B** : Head window 50ms → 300ms (`_targetWindowHeadSec`)
- ✅ **P1** : Anti-spam wrong 200ms → 350ms (vs hit 200ms)
- ✅ **setState()** : Ajouté après `onTimeUpdate` + hooks MIDI

**BUGS OBSERVÉS VIDÉO SESSION TEST (12 jan 2026)** :
1. 🔴 **P0 NOTE VERTE → ROUGE** : Note jouée parfaitement devient rouge après. **RÈGLE : Si bonne note jouée = VERT uniquement, jamais rouge**
2. 🔴 **P0 FANTÔMES MICRO** : Micro détecte notes jamais jouées → touches rouges fantômes. **Regarder détection micro (MicEngine) pourquoi faux positifs**
3. 🔴 **P0 HUD ALÉATOIRE** : Tableau score au-dessus piano se met à jour totalement aléatoirement (valeurs incohérentes)
4. 🔴 **P0 COMPTAGE INVERSÉ** : 9 notes jouées = 9 fautes comptées. **Erreur système comptage notes justes** (devrait être 9 justes / 0 fautes)

**Corrections P0 déjà appliquées (à vérifier si efficaces)** :
- ✅ Skip wrongFlash <500ms après hit (lignes 2820-2829)
- ✅ Gating wrong 0.35→0.45 (ligne 346)
- ✅ Anti-spam wrong 350→500ms (ligne 352)
- ✅ windowMs 200→300ms (ligne 2316)
- ✅ Gating séparé hit 0.12 vs wrong 0.45 (lignes 345-346)

**Objectif** : **TROUVER CAUSES RACINES** de ces 4 bugs P0 + **PROPOSER CORRECTIONS PRÉCISES** (lignes code + patch).

---

## 🎥 ANALYSE VIDÉO — BUGS P0 CRITIQUES OBSERVÉS

### 🔴 BUG P0 #1 : NOTE VERTE → ROUGE (PRIORITÉ MAXIMALE)
**Symptôme observé** : Note jouée parfaitement → flash VERT → devient ROUGE après

**À CHERCHER DANS VIDÉO** :
- [ ] Combien de notes vertes deviennent rouges ? X/9
- [ ] Délai vert→rouge : immédiat (<100ms) / court (100-500ms) / long (>500ms) ?
- [ ] Pattern : TOUTES les notes vertes deviennent rouges OU seulement certaines ?
- [ ] Timing : Rouge apparaît quand je **lâche** la touche OU **après délai fixe** ?

**RÈGLE ATTENDUE** :
- ✅ Note correcte (MIDI match + timing OK) = **VERT uniquement, JAMAIS rouge**
- ❌ Note manquée (jamais jouée) = **ROUGE uniquement**
- ❌ Note fausse (mauvais MIDI) = **ROUGE uniquement**

**CAUSE PROBABLE** : OLD system génère wrong APRÈS NEW system génère hit correct
**CORRECTION ATTENDUE** : Désactiver OLD system flashs si NEW system actif

---

### 🔴 BUG P0 #2 : FANTÔMES MICRO (PRIORITÉ MAXIMALE)
**Symptôme observé** : Touches ROUGES alors que **JAMAIS jouées** (micro détecte fantômes)

**À CHERCHER DANS VIDÉO** :
- [ ] Combien de touches rouges fantômes ? X
- [ ] Quels MIDI détectés fantômes : [liste]
- [ ] Pattern temporel : aléatoire / en rafale / après notes correctes ?
- [ ] Audio ambiant : bruit de fond / écho / résonance piano ?

**À CHERCHER DANS LOGS** :
```
SESSION4_DEBUG_WRONG: ... midi=XX rms=X.XXX conf=X.XX
Expected notes: [liste MIDI attendus]
→ Vérifier si XX dans liste attendus OU fantôme pur
```
- [ ] RMS fantômes : X.XXX (comparer à `_absMinRms=0.0020`)
- [ ] Conf fantômes : X.XX (comparer à `_minConfWrong=0.45`)
- [ ] Fréquence Hz fantômes : X Hz (vérifier si harmoniques parasites)

**CAUSE PROBABLE** : MicEngine détection trop sensible (gating 0.45 insuffisant OU harmoniques/écho)
**CORRECTION ATTENDUE** : Augmenter `_minConfWrong` 0.45→0.55 OU `_absMinRms` 0.0020→0.0030

---

### 🔴 BUG P0 #3 : HUD ALÉATOIRE (PRIORITÉ HAUTE)
**Symptôme observé** : Tableau score au-dessus piano → valeurs incohérentes / aléatoires

**À CHERCHER DANS VIDÉO** :
- [ ] Quels champs affectés : Précision / Notes Justes / Score / Combo ?
- [ ] Exemple incohérence : "9 notes jouées → Précision=X%, Notes Justes=X, Score=X"
- [ ] Champs figés (ne bougent pas) VS aléatoires (valeurs absurdes) ?

**À CHERCHER DANS LOGS** :
```
SESSION4_DEBUG_HIT: After ... correctCount=X score=Y combo=Z
SESSION4_CONTROLLER: Stopped. perfectCount=A goodCount=B okCount=C wrongCount=D missCount=E
Dialog final: Précision=X%, Score=Y, Notes Justes=Z/9
```
- [ ] `correctCount` progresse dans logs ? (devrait être 0→1→2→...→9)
- [ ] Valeurs finales cohérentes : `perfectCount+goodCount+okCount` = 9 ?
- [ ] Dialog final cohérent avec logs ?

**CAUSE PROBABLE** : OLD system met à jour HUD, NEW system met à jour logs → désynchronisation
**CORRECTION ATTENDUE** : Afficher SEULEMENT NEW system stats dans HUD (ignorer OLD `_correctNotes`)

---

### 🔴 BUG P0 #4 : COMPTAGE INVERSÉ (PRIORITÉ MAXIMALE)
**Symptôme observé** : 9 notes jouées → **9 FAUTES comptées** (devrait être 9 justes / 0 fautes)

**À CHERCHER DANS VIDÉO** :
- [ ] Dialog final : Précision=X%, Score=X, Notes Justes=X/9, Fautes=X
- [ ] Valeurs exactes notées

**À CHERCHER DANS LOGS** :
```
SESSION4_CONTROLLER: Stopped. Final score=X, perfectCount=A goodCount=B okCount=C wrongCount=D missCount=E
Dialog: wrongNotes=F
```
- [ ] `wrongCount` dans logs : devrait être 0, est X ?
- [ ] `missCount` dans logs : devrait être 0, est X ?
- [ ] `perfectCount+goodCount+okCount` : devrait être 9, est X ?
- [ ] Variable `_correctNotes` (OLD system) vs `correctCount` (NEW system) : incohérence ?

**CAUSE PROBABLE** : Dialog affiche OLD system `_correctNotes` au lieu de NEW system `correctCount` OU inversion wrong/correct
**CORRECTION ATTENDUE** : Dialog utiliser NEW system stats uniquement (lignes ~4620)

---

## 📊 ANALYSE LOGS — PATTERNS P0 CRITIQUES

### 🔴 PATTERN P0 #1 : NOTE VERTE → ROUGE
**Chercher conflit NEW/OLD systems** :
```
SESSION4_DEBUG_HIT: After ... midi=XX correctCount=1 (NEW system OK)
[...quelques lignes...]
SESSION4_DEBUG_WRONG: Before ... midi=XX (OLD system génère wrong sur MÊME MIDI)
OU
wrongFlash decision midi=XX (MicEngine génère wrong sur sustain)
```

**Questions CRITIQUES** :
- [ ] Pattern "HIT suivi WRONG même MIDI" existe ? **OUI / NON**
- [ ] Combien d'occurrences ? X/9
- [ ] Délai HIT→WRONG : X ms (si <500ms = BUG corrections P0 inefficaces)
- [ ] Log `SESSION4_SKIP_SUSTAIN_WRONG` apparaît ? **OUI / NON** (devrait skip wrong)
- [ ] Extraits 5-10 lignes montrant HIT→WRONG :

**DIAGNOSTIC** :
- Si `SESSION4_SKIP_SUSTAIN_WRONG` absent → correction P0 ligne 2820 ne fonctionne PAS
- Si présent mais wrong passe quand même → OLD system génère wrong via autre path (pas wrongFlash)

---

### 🔴 PATTERN P0 #2 : FANTÔMES MICRO
**Chercher détections micro fantômes** :
```
SESSION4_DEBUG_WRONG: ... midi=XX rms=X.XXX conf=X.XX
Expected notes list: [60, 62, 64, ...] (XX absent = fantôme pur)
```

**Questions CRITIQUES** :
- [ ] Combien de wrongs détectés total ? X
- [ ] Combien wrongs MIDI non attendus (fantômes purs) ? X
- [ ] Liste MIDI attendus : [...]
- [ ] Liste MIDI wrongs : [...]
- [ ] **RMS fantômes** : min=X.XXX max=X.XXX (comparer `_absMinRms=0.0020`)
- [ ] **Conf fantômes** : min=X.XX max=X.XX (comparer `_minConfWrong=0.45`)
- [ ] Gating bloque combien ? (logs `SESSION4_GATING`) X wrongs bloqués
- [ ] Anti-spam bloque combien ? (logs `SESSION4_ANTISPAM_WRONG`) X wrongs bloqués

**DIAGNOSTIC** :
- Si RMS > 0.0020 ET conf > 0.45 → gating 0.45 insuffisant, monter à 0.55
- Si RMS < 0.0020 → harmoniques/bruit passe sous radar, monter `_absMinRms` à 0.0030
- Si anti-spam bloque peu → fenêtre 500ms insuffisante, monter à 700ms

---

### 🔴 PATTERN P0 #3 : HUD ALÉATOIRE
**Chercher désynchronisation OLD/NEW** :
```
SESSION4_DEBUG_HIT: After ... correctCount=X (NEW)
[...fin session...]
SESSION4_CONTROLLER: Stopped. perfectCount=A goodCount=B okCount=C (NEW)
Dialog: Précision=Y%, Notes Justes=Z (affichées dans UI)
```

**Questions CRITIQUES** :
- [ ] `correctCount` progresse logs ? **OUI / NON** (0→1→2→...→9)
- [ ] Valeur finale `perfectCount+goodCount+okCount` : X (devrait être 9)
- [ ] Valeur dialog "Notes Justes" : X (devrait être 9)
- [ ] Incohérence dialog vs logs ? **OUI / NON**
- [ ] Variable OLD system `_correctNotes` mentionnée ? Valeur X

**DIAGNOSTIC** :
- Si `correctCount` OK logs mais dialog faux → Dialog affiche OLD `_correctNotes` (ligne ~4625)
- Si `correctCount` ne progresse pas logs → NEW system ne matche pas (gating trop strict ?)

---

### 🔴 PATTERN P0 #4 : COMPTAGE INVERSÉ (9 notes = 9 fautes)
**Chercher inversion comptage** :
```
SESSION4_CONTROLLER: Stopped. wrongCount=X missCount=Y (NEW)
Dialog final: "X fautes" affiché
```

**Questions CRITIQUES** :
- [ ] `wrongCount` logs : X (devrait être 0)
- [ ] `missCount` logs : X (devrait être 0)
- [ ] `perfectCount+goodCount+okCount` logs : X (devrait être 9)
- [ ] Dialog "Fautes" affiché : X (devrait être 0)
- [ ] Formule dialog fautes : `total - correctNotes` OU `wrongCount + missCount` ?

**DIAGNOSTIC** :
- Si wrongCount=9 logs → Toutes notes matchées comme wrong (gating hit trop strict `_minConfHit=0.12` ?)
- Si wrongCount=0 logs mais dialog=9 → Formule dialog fausse (ligne ~4625 utilise OLD system)

---

### ✅ STATISTIQUES REQUISES
**Compter dans TOUS les logs** :
- [ ] Total `SESSION4_DEBUG_HIT` : X (devrait être 9)
- [ ] Total `SESSION4_DEBUG_WRONG` : X (devrait être 0)
- [ ] Total `SESSION4_GATING_HIT` : X (devrait être 0)
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
✅ Pas de vert→rouge
✅ Pas de fantômes rouges
✅ HUD cohérent (9 justes, 0 fautes)
✅ Dialog: 100%, score ~900, 9/9 justes

VERDICT : CORRECTIONS P0 EFFICACES
```

---

### ❌ CORRECTIONS P0 ATTENDUES (4 bugs identifiés)

#### 🔴 P0 #1 : NOTE VERTE → ROUGE

**Si confirmé logs "HIT→WRONG même MIDI"** :

**BUG P0 #1 : CONFLIT DUAL SYSTEMS**  
**Priorité** : P0 (BLOQUANT)  
**Cause racine** : OLD system génère flashs APRÈS NEW system  
**Ligne suspecte** : `practice_page.dart:2779-2805` (OLD system hit/wrong hooks)  
**Correction** :
```dart
// LIGNE 2779 (dans case hit, branche else OLD SYSTEM)
} else {
  // OLD SYSTEM: Score based on timing precision
  // BUG P0 #1 FIX: Désactiver OLD flashs si NEW system actif
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

**BUG P0 #2 : GATING INSUFFISANT**  
**Priorité** : P0 (BLOQUANT)  
**Cause racine** : Seuil confidence 0.45 trop permissif pour fantômes  
**Ligne suspecte** : `practice_page.dart:346`  
**Correction** :
```dart
// AVANT
final double _minConfWrong = 0.45;

// APRÈS
final double _minConfWrong = 0.60; // P0 #2: Fantômes micro, conf 0.45 insuffisante
```

**Si RMS < 0.0020** (harmoniques/bruit bas niveau) :

**BUG P0 #2B : RMS GATE INSUFFISANT**  
**Ligne suspecte** : `practice_page.dart:344`  
**Correction** :
```dart
// AVANT
final double _absMinRms = 0.0020;

// APRÈS
final double _absMinRms = 0.0035; // P0 #2: Fantômes harmoniques bas RMS
```

---

#### 🔴 P0 #3 : HUD ALÉATOIRE

**Si dialog != logs NEW system** :

**BUG P0 #3 : HUD AFFICHE OLD SYSTEM**  
**Priorité** : P0 (BLOQUANT)  
**Cause racine** : HUD lit `_correctNotes` (OLD) au lieu de NEW system state  
**Ligne suspecte** : `practice_page.dart:~4625` (dialog score)  
**Correction** : Chercher dans `_showScoreDialog` + HUD widget :
```dart
// Remplacer références _correctNotes par _newController!.currentScoringState
final correctCount = _newController!.currentScoringState.perfectCount +
                     _newController!.currentScoringState.goodCount +
                     _newController!.currentScoringState.okCount;
```

---

#### 🔴 P0 #4 : COMPTAGE INVERSÉ (9 notes = 9 fautes)

**Si wrongCount=9 logs** :

**BUG P0 #4A : TOUTES NOTES = WRONG**  
**Priorité** : P0 (BLOQUANT)  
**Cause racine** : Gating hit trop strict `_minConfHit=0.12` bloque TOUTES notes  
**Ligne suspecte** : `practice_page.dart:345`  
**Correction** :
```dart
// AVANT
final double _minConfHit = 0.12;

// APRÈS
final double _minConfHit = 0.08; // P0 #4: Gating 0.12 trop strict, bloque notes réelles
```

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

---

### 📋 RÉPONSE OBLIGATOIRE FORMAT

Pour **CHAQUE BUG P0 confirmé**, fournis :

1. **Vidéo** : Symptôme observé + fréquence (X/9 notes)
2. **Logs** : Extrait 5-10 lignes montrant pattern
3. **Stats** : Compteurs NEW system (correctCount, wrongCount, etc.)
4. **Cause racine** : Quelle hypothèse confirmée
5. **Correction recommandée** : Quel patch appliquer (copie code ci-dessus)

**Format minimal réponse** :
```
BUG P0 #X CONFIRMÉ: [nom]
Vidéo: [symptôme + fréquence]
Logs: [extrait]
Stats: correctCount=X wrongCount=Y
Cause: [OLD/NEW conflit OU gating OU formule]
Correction: [patch #X ci-dessus]
```

---

**Merci ChatGPT ! Analyse P0 ciblée pour débloquer Session 4.** 🚀
