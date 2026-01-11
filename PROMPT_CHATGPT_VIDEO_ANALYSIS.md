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

**BUGS OBSERVÉS VIDÉO (à confirmer dans logs)** :
1. ⚠️ **Sustain prématuré** : Note verte devient rouge si je lâche avant durée attendue
2. ⚠️ **Flash vert → rouge** : Note correcte flash vert PUIS rouge après
3. ⚠️ **HUD figé partiel** : Précision/Notes Justes ne montent pas, mais Score/Combo oui
4. ⚠️ **Sapin Noël micro** : Touches rouges alors que jamais jouées (fantômes wrongs)
5. ⚠️ **Note correcte rouge** : Bonne touche appuyée ressort rouge
6. ⚠️ **Timer dépassé autorisé** : Si bonne touche jouée hors timing, ça reste vert (devrait être rouge/miss)

**Objectif** : Confirmer/infirmer ces bugs dans logs + identifier causes racines + proposer corrections.

---

## 🎥 ANALYSE VIDÉO (6 notes attendues)

### 1. Flashs clavier - CRITÈRE STRICT
**Règle attendue** :
- ✅ **VERT** = Note correcte appuyée (MIDI match + timing OK)
- ❌ **ROUGE** = Note MANQUÉE (jamais jouée) OU mauvais MIDI joué
- ⚠️ **JAMAIS** : Vert puis Rouge sur même touche (= BUG)
- ⚠️ **JAMAIS** : Rouge sur touche jamais jouée (= BUG fantômes)

**À observer** :
- [ ] Combien de flashs VERTS ? (devrait être 6 si toutes notes jouées)
- [ ] Combien de flashs ROUGES ? (devrait être 0 si 6/6 parfait)
- [ ] **BUG #1 SUSTAIN** : Note VERTE devient ROUGE après (si lâché trop tôt) ? OUI / NON
- [ ] **BUG #2 DOUBLE-FLASH** : Même touche flash VERT puis ROUGE ? OUI / NON (timestamp)
- [ ] **BUG #3 FANTÔMES** : Touches rouges jamais jouées ? OUI / NON (quels MIDI ?)
- [ ] **BUG #4 TIMER** : Touche correcte hors timing reste VERTE ? OUI / NON (devrait être miss/rouge)

### 2. HUD en temps réel
**Champs à observer** :
- [ ] **Précision** : Se met à jour ? (devrait monter 0% → ~100%)
- [ ] **Notes Justes** : Se met à jour ? (devrait monter 0 → 6)
- [ ] **Score** : Se met à jour ? (devrait monter 0 → 600-700)
- [ ] **Combo** : Se met à jour ? (devrait monter 0 → 6)

**BUG #5 HUD PARTIEL** :
- [ ] Score/Combo montent MAIS Précision/Notes Justes figés ? OUI / NON
- [ ] Timestamps changements (noter XX:XX) :

### 3. Dialog final
- [ ] Précision : X% (devrait être ~100% si 6/6)
- [ ] Score : X (devrait être ~600-700)
- [ ] Notes justes : X/6 (devrait être 6/6)
- [ ] Cohérent avec HUD final ? OUI / NON

---

## 📊 ANALYSE LOGS `logcatdebug` — PATTERNS BUGS CRITIQUES

### 🔴 BUG #1 : SUSTAIN PRÉMATURÉ (Note verte → rouge si lâché trop tôt)
**Pattern suspecté** :
```
HIT_DECISION ... result=HIT midi=XX
[...quelques lignes...]
wrongFlash midi=XX (MÊME MIDI) ... (= sustain check fail)
```
**Questions** :
- [ ] Pattern "HIT puis wrongFlash MÊME MIDI" existe ? OUI / NON
- [ ] Combien d'occurrences ?
- [ ] Délai entre HIT et wrongFlash : X ms (devrait être >500ms pour sustain check légitime)
- [ ] **Si <200ms** : BUG sustain check trop rapide
- [ ] Extraits logs (timestamps + MIDI) :

**Cause probable** : `MicEngine` génère `wrongFlash` sur MÊME MIDI si durée sustain insuffisante → devrait être géré par NEW system, pas OLD system

---

### 🔴 BUG #2 : DOUBLE-FLASH (Vert puis Rouge même touche)
**Pattern suspecté** :
```
SESSION4_DEBUG_HIT: ... midi=XX correctCount=X→Y
[...quelques lignes...]
SESSION4_DEBUG_WRONG: ... midi=XX wrongCount=X→Y (MÊME MIDI)
```
**Questions** :
- [ ] Pattern "DEBUG_HIT puis DEBUG_WRONG MÊME MIDI" existe ? OUI / NON
- [ ] Combien d'occurrences ?
- [ ] Délai entre hit/wrong : X ms
- [ ] Extraits logs :

**Cause probable** : OLD system génère wrong APRÈS NEW system génère hit → conflit dual systems

---

### 🔴 BUG #3 : FANTÔMES WRONGS (Touches rouges jamais jouées)
**Pattern suspecté** :
```
SESSION4_DEBUG_WRONG: ... midi=XX
[...vérifier...]
Expected notes list: [...] (XX absent de la liste)
```
**Questions** :
- [ ] Wrongs détectés pour MIDI non attendus ? OUI / NON
- [ ] Liste MIDI wrongs : [XX, YY, ...]
- [ ] Liste MIDI attendus : [AA, BB, ...]
- [ ] RMS/conf des wrongs fantômes : rms=X.XXX conf=X.XX (vérifier si <seuils)
- [ ] Anti-spam activé ? (SESSION4_ANTISPAM_WRONG logs présents ?)

**Cause probable** : Gating _minConfWrong=0.35 ou _absMinRms=0.0020 trop permissif → laisse passer bruit → OU anti-spam 350ms trop court

---

### 🔴 BUG #4 : TIMER DÉPASSÉ AUTORISÉ (Bonne touche hors timing reste verte)
**Pattern suspecté** :
```
PLAY_NOTE ... midi=XX t=T1
Expected note: midi=XX t=T2
dt = |T1 - T2| = >300ms (hors windowMs)
RESOLVE_NOTE ... grade=perfect/good/ok (devrait être miss)
```
**Questions** :
- [ ] Notes matchées avec dt > 300ms existent ? OUI / NON
- [ ] Extraits : midi=XX dt=Xms grade=X
- [ ] windowMs=300 respecté ? (vérifier ligne `NoteMatcher(windowMs: 300`)

**Cause probable** : windowMs=300 trop permissif OU calcul dt incorrect (pas abs()?)

---

### 🔴 BUG #5 : HUD PARTIEL (Score/Combo OK, Précision/Notes Justes figés)
**Pattern suspecté** :
```
SESSION4_DEBUG_HIT: After ... correctCount=X score=Y combo=Z
[...vérifier si correctCount monte...]
SESSION4_CONTROLLER: Stopped. perfectCount=A goodCount=B okCount=C
```
**Questions** :
- [ ] correctCount progresse dans logs ? (0→1→2→...) OUI / NON
- [ ] perfectCount + goodCount + okCount = combien ? (devrait être 6)
- [ ] `setState(() {})` appelé après hit ? (chercher ligne après SESSION4_DEBUG_HIT)

**Cause probable** : OLD system met à jour Précision/Notes Justes, NEW system met à jour Score/Combo → désynchronisation

---

### ✅ PATTERN 1 : `SESSION4_DEBUG_HIT` (vérification baseline)
```
SESSION4_DEBUG_HIT: Before ... midi=XX rms=X.XXX conf=X.XX correctCount=N
SESSION4_DEBUG_HIT: After ... correctCount=N+1 score=Y combo=Z
```
**Questions** :
- [ ] Combien de hits détectés ? (devrait être 6)
- [ ] correctCount progresse : 0→1→2→3→4→5→6 ? OUI / NON
- [ ] Score augmente : 0→100→... ? OUI / NON
- [ ] Hits bloqués par gating ? (SESSION4_GATING_HIT logs ?) Combien ?

---

### ✅ PATTERN 2 : `SESSION4_DEBUG_WRONG` (vérification baseline)
```
SESSION4_DEBUG_WRONG: ... midi=XX rms=X.XXX conf=X.XX
```
**Questions** :
- [ ] Combien de wrongs détectés ? (devrait être 0 si 6/6 parfait)
- [ ] MIDI wrongs vs MIDI attendus : cohérent ?
- [ ] Wrongs bloqués par gating ? (SESSION4_GATING logs ?) Combien ?

---

### ✅ PATTERN 3 : `RESOLVE_NOTE ... grade=miss` (vérification miss prématurés)
```
RESOLVE_NOTE ... grade=miss t=T1
[...vérifier si HIT existe après...]
HIT_DECISION ... t=T2 (T2 > T1 = BUG miss prématuré)
```
**Questions** :
- [ ] Combien de miss ? (devrait être 0 si 6/6 parfait)
- [ ] Miss avant hit même MIDI ? OUI / NON

---

### ✅ PATTERN 4 : `WRONG_NOTE ... No matching expected note` (vérification baseline)
```
HIT_DECISION ... result=HIT midi=XX
WRONG_NOTE ... No matching expected note ... midi=XX
```
**Questions** :
- [ ] Pattern "HIT puis No matching expected note" existe ? OUI / NON
- [ ] Combien d'occurrences ?

---

### ✅ PATTERN 5 : `SESSION4_CONTROLLER: Stopped` (vérification finale)
```
SESSION4_CONTROLLER: Stopped. Final score=X, combo=Y, p95=Zms
```
**Questions** :
- [ ] Log apparaît ? OUI / NON
- [ ] Score ≈ 600-700 ? OUI / NON
- [ ] Combo = 6 ? OUI / NON
- [ ] p95 timing < 100ms ? OUI / NON

---

### 📈 STATISTIQUES GLOBALES
Calcule :
- **dt moyens** : X.XXXs (devraient être <0.300s avec windowMs=300)
- **Ratio hits acceptés** : X/Y (devrait être 6/6)
- [ ] **Ratio wrongs** : X/Y (devrait être 0/0)
- **Ratio gating hits bloqués** : X (devrait être 0)
- **Ratio gating wrongs bloqués** : X (OK si >0)

---

## 🎯 VERDICT & CORRECTIONS

### ✅ Si corrections P0/P1 ont marché ET 0 bugs critiques
Confirme :
```
✅ HUD se met à jour en temps réel (Précision/Score/Combo/Notes Justes)
✅ 6/6 flashs verts, 0 rouge
✅ Pas de vert→rouge (sustain OK)
✅ Pas de fantômes rouges
✅ Pas de notes hors timing acceptées
✅ Dialog final : 100%, score ~600-700
✅ Logs : correctCount 0→6, 0 wrong, 0 miss prématuré

VERDICT : CORRECTIONS P0/P1 EFFICACES — 0 bugs critiques restants
```

---

### ❌ Si bugs restent — FORMAT OBLIGATOIRE

Pour **CHAQUE BUG CONFIRMÉ**, fournis :

**BUG #X : [NOM DESCRIPTIF]**  
**Priorité** : P0 (bloquant) / P1 (critique) / P2 (mineur)  
**Symptôme vidéo** : [description précise timestamp si possible]  
**Symptôme logs** : [extrait 3-10 lignes clés avec timestamps]  
**Cause racine probable** : [analyse technique]  
**Ligne code suspecte** : `practice_page.dart:XXX` ou `practice_controller.dart:XXX` ou `mic_engine.dart:XXX`  
**Correction proposée** :
```dart
// AVANT (ligne XXX)
...code actuel...

// APRÈS (correction)
...code corrigé...

// JUSTIFICATION
[Pourquoi cette correction résout le bug]
```

---

### 🔍 BUGS SPÉCIFIQUES À CHERCHER

#### BUG #1 : SUSTAIN PRÉMATURÉ
**Si confirmé** : OLD system `MicEngine` génère `wrongFlash` sur note déjà matchée par NEW system  
**Correction probable** : Désactiver `wrongFlash` sur MIDI déjà consommé par NEW controller  
**Fichier** : `practice_page.dart` (hook wrongFlash, lignes ~2810-2850)

#### BUG #2 : DOUBLE-FLASH (Vert puis Rouge)
**Si confirmé** : NEW system matche hit, puis OLD system génère wrong sur même MIDI  
**Correction probable** : Consommer/marquer MIDI matchés pour empêcher OLD system traiter après  
**Fichier** : `practice_page.dart` (dual system interaction)

#### BUG #3 : FANTÔMES WRONGS
**Si confirmé** : Gating trop permissif OU anti-spam wrong trop court  
**Correction probable** : Augmenter `_minConfWrong` 0.35→0.40 OU augmenter `_antiSpamWrongMs` 350→500ms  
**Fichier** : `practice_page.dart` lignes 345-352

#### BUG #4 : TIMER DÉPASSÉ AUTORISÉ
**Si confirmé** : windowMs=300 trop permissif OU OLD system override NEW system  
**Correction probable** : Vérifier OLD system désactivé pour flashs OU réduire windowMs 300→250ms  
**Fichier** : `practice_page.dart` (ligne 2316) ou `practice_controller.dart` (ligne 396)

#### BUG #5 : HUD PARTIEL
**Si confirmé** : OLD system met à jour Précision/Notes Justes, NEW system met à jour Score/Combo  
**Correction probable** : Afficher SEULEMENT NEW system stats OU synchroniser OLD/NEW  
**Fichier** : `practice_page.dart` (HUD widget build, lignes ~3500-3800)

---

## 📋 CHECKLIST RÉPONSE OBLIGATOIRE

- [ ] Vidéo : BUG #1 Sustain (vert→rouge) confirmé ? OUI / NON
- [ ] Vidéo : BUG #2 Double-flash confirmé ? OUI / NON
- [ ] Vidéo : BUG #3 Fantômes wrongs confirmés ? OUI / NON (quels MIDI ?)
- [ ] Vidéo : BUG #4 Timer dépassé confirmé ? OUI / NON
- [ ] Vidéo : BUG #5 HUD partiel confirmé ? OUI / NON (quels champs figés ?)
- [ ] Logs : Pattern BUG #1 (HIT puis wrongFlash même MIDI) ? OUI / NON (extraits)
- [ ] Logs : Pattern BUG #2 (DEBUG_HIT puis DEBUG_WRONG même MIDI) ? OUI / NON (extraits)
- [ ] Logs : Pattern BUG #3 (wrongs MIDI non attendus) ? OUI / NON (liste MIDI)
- [ ] Logs : Pattern BUG #4 (dt > 300ms matchés) ? OUI / NON (extraits)
- [ ] Logs : Pattern BUG #5 (correctCount progresse mais HUD figé) ? OUI / NON
- [ ] Stats : dt moyens, ratios hits/wrongs
- [ ] **Verdict final : ✅ 0 bugs OU ❌ X bugs restants (détaille CHAQUE bug format ci-dessus)**

---

**Merci ChatGPT ! Analyse ciblée post-corrections P0/P1 + détection bugs critiques observés.** 🚀
