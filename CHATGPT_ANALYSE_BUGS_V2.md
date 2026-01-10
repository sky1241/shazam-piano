# PROMPT ANALYSE VIDÉO - BUGS PRACTICE MODE

Tu vas analyser une vidéo d'une application Flutter de piano avec des notes tombantes. L'utilisateur rapporte 3 bugs. Je te fournis : vidéo + logs Flutter + logs backend. Fais une analyse frame-by-frame ULTRA PRÉCISE.

## 📋 LES 3 BUGS

**BUG 4 - Notes en bas au démarrage:**
Quand l'utilisateur appuie sur Play, pendant ~1 seconde les notes apparaissent directement en bas de l'écran (près du clavier) au lieu d'être en haut. Après cette "pré-image", les notes tombent normalement depuis le haut.

**BUG 5 - Saut visuel au premier appui:**
Au moment où l'utilisateur appuie sur la première note, les notes font un petit "saut" visuel et remontent légèrement, puis continuent à tomber normalement.

**BUG 6 - Certaines notes ne s'illuminent pas:**
Quand l'utilisateur appuie correctement sur une note au bon moment, certaines s'illuminent en vert/jaune (correct) mais d'autres ne changent PAS de couleur alors qu'elles semblent correctement jouées.

---

**⚠️ NOTE IMPORTANTE**: J'ai fait 3 tests dans la même session. Dans les logs Flutter et backend, **seule la DERNIÈRE partie t'intéresse** (le 3ème test). Ignore les 2 premiers tests.

---

## 🎬 TON TRAVAIL

### ÉTAPE 1 : Timestamps clés

Regarde la vidéo et note (en secondes avec 3 décimales, ex: 2.754s) :

- **T_play** : Quand l'utilisateur clique Play
- **T_countdown** : Quand le countdown "3" apparaît
- **T_running** : Quand le countdown finit
- **T_first_press** : Premier appui utilisateur
- **Durée totale** vidéo

### ÉTAPE 2 : Analyse BUG 4 (Notes en bas)

Mesure les positions Y en pixels à ces moments :

**T=T_play:**
- Y_note_top = ? (haut de 1ère note visible, depuis top écran)
- Y_note_bottom = ? (bas de cette note)
- Y_keyboard = ? (ligne du clavier)
- Combien de notes visibles ?

**T=T_play + 0.3s:**
- Mêmes mesures

**T=T_play + 0.6s:**
- Mêmes mesures

**T=T_play + 1.0s:**
- Mêmes mesures

**T=T_countdown:**
- Mêmes mesures

**Diagnostic:**
- Notes vraiment en bas (Y > 1000px) ou au milieu (Y ≈ 400-800px) ?
- À quel moment sautent-elles vers le haut ?

### ÉTAPE 3 : Analyse BUG 5 (Saut visuel)

Autour du premier appui, analyse serrée :

**T=T_first_press - 0.3s:**
- Y_note_cible = ? (note que l'user va appuyer)
- Y_note_2 = ? (note suivante)

**T=T_first_press - 0.1s:**
- Y_note_cible = ?
- Y_note_2 = ?

**T=T_first_press:**
- Y_note_cible = ?
- Change de couleur immédiatement ?

**T=T_first_press + 0.1s:**
- Y_note_cible = ? (encore visible ?)
- Y_note_2 = ?
- **CALCULE ΔY** = (Y_note_2 à T+0.1s) - (Y_note_2 à T-0.1s)
- Si ΔY < 0 → SAUT vers haut !

**T=T_first_press + 0.3s:**
- Y_note_2 = ?

**Diagnostic:**
- Saut confirmé ? Amplitude en pixels ?
- Toutes les notes affectées ?

### ÉTAPE 4 : Analyse BUG 6 (Illumination)

Pour les 5 premières notes jouées :

**Note 1 (T=?):**
- Couleur AVANT : ?
- Couleur APRÈS : ?
- S'illumine ? OUI/NON

**Note 2 (T=?):**
- Mêmes infos

**Note 3, 4, 5:**
- Mêmes infos

**Diagnostic:**
- Pattern détecté ? (ex: notes 1,3,5 OK mais 2,4 NON)
- Notes non-illuminées jouées en retard/avance ?

---

## 📊 ÉTAPE 5 : Corrélation avec logs

Je te donne les logs. Cherche et COPIE-COLLE :

### Pour BUG 4:
Autour de T_play et T_countdown :
- Logs `[PAINTER] paint()` avec `elapsed=` et `size=`
- Logs `SPAWN note midi=` avec `yTop=` et `yBottom=`
- Log `Countdown C8`

### Pour BUG 5:
Autour de T_first_press (fenêtre -1s à +1s) :
- Logs `[PAINTER]` → note si `elapsed`, `fallLead` ou `size` changent brutalement
- Logs détection note (mic/MIDI)

### Pour BUG 6:
Pour chaque note jouée :
- Logs `NoteAccuracy` (perfect/good/miss)
- Logs `_lastCorrectNote=`
- Logs timing error (ms)

---

## 📝 FORMAT RÉPONSE

```
═══════════════════════════════════════════════════════
ANALYSE VIDÉO - BUGS PRACTICE MODE
═══════════════════════════════════════════════════════

[ÉTAPE 1] TIMESTAMPS
───────────────────────────────────────────────────────
Durée totale     : XX:XX.XXX
T_play           : XX.XXXs
T_countdown      : XX.XXXs
T_running        : XX.XXXs
T_first_press    : XX.XXXs

[ÉTAPE 2] BUG 4 - NOTES EN BAS
───────────────────────────────────────────────────────
T=XX.XXXs (T_play)
  Y_note_top    = XXXpx
  Y_note_bottom = XXXpx
  Y_keyboard    = XXXpx
  Notes visibles = X

T=XX.XXXs (T_play+0.3s)
  Y_note_top    = XXXpx
  ...

[Répéter tous frames]

DIAGNOSTIC BUG 4:
✓ Notes en bas confirmé (Y > 1000px)
✓ Saut vers haut à T=XX.XXXs

LOGS BUG 4:
[Coller logs [PAINTER] et SPAWN]
elapsed = [-2.954, -2.921, ...]
yTop = [2.7px, 45.3px, ...]
size = [(400, 1500), ...]

[ÉTAPE 3] BUG 5 - SAUT VISUEL
───────────────────────────────────────────────────────
T=XX.XXXs (T_first_press-0.3s)
  Y_note_cible = XXXpx
  Y_note_2     = XXXpx

T=XX.XXXs (T_first_press+0.1s)
  Y_note_cible = disparue
  Y_note_2     = XXXpx
  ΔY = -XXpx ← SAUT DÉTECTÉ

DIAGNOSTIC BUG 5:
✓ Saut confirmé à T=XX.XXXs
✓ Amplitude = XXpx vers haut

LOGS BUG 5:
[Coller logs]
elapsed avant = [0.123, 0.156, ...]
elapsed après = [0.189, 0.222, ...]
Changement brutal ? OUI/NON

[ÉTAPE 4] BUG 6 - ILLUMINATION
───────────────────────────────────────────────────────
Note 1 (T=XX.XXXs)
  Couleur avant : bleu
  Couleur après : vert
  S'illumine ? OUI

Note 2 (T=XX.XXXs)
  Couleur avant : bleu
  Couleur après : bleu (inchangé)
  S'illumine ? NON ← PROBLÈME

[Répéter notes 3,4,5]

DIAGNOSTIC BUG 6:
Pattern: Notes 1,3,5 OK / Notes 2,4 NON
✓ Notes NON illuminées jouées en retard

LOGS BUG 6:
Note 1: accuracy=perfect, _lastCorrectNote=60
Note 2: accuracy=miss, _lastCorrectNote=60 (inchangé)
...

[ÉTAPE 5] HYPOTHÈSES ROOT CAUSE
───────────────────────────────────────────────────────
BUG 4: [Ta meilleure hypothèse]
BUG 5: [Ta meilleure hypothèse]
BUG 6: [Ta meilleure hypothèse]
```

---

## 🔧 INFOS TECHNIQUES

**Coordonnées:**
- Y=0 : Top écran (spawn notes)
- Y≈400 : Clavier (cible)
- Y≈1500 : Bottom écran

**Formule position:**
```
Y = (elapsed - (noteStart - fallLead)) / fallLead × overlayHeight
```

**Illumination:**
- Note correcte + timing good/perfect → VERT/JAUNE
- Note incorrecte ou timing miss → PAS d'illumination
- Variable: `_lastCorrectNote` (MIDI dernière note correcte)

**Logs clés:**
- `[PAINTER] paint()` : Rendering frame
- `SPAWN note midi=` : Note visible
- `Countdown C8` : Timing countdown
- `NoteAccuracy` : perfect/good/miss

---

## ⚠️ IMPORTANT

1. **Précision**: Timestamps 3 décimales (2.754s)
2. **Mesures**: Pixels exacts
3. **Discontinuités**: Cherche SAUTS trajectoires
4. **Anomalies**: Si logs ≠ vidéo → DIS-LE ! C'est la clé du bug.
