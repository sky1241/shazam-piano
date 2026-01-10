# ANALYSE VIDÉO COMPLÈTE - PRACTICE MODE BUGS

Tu vas analyser une vidéo Flutter d'un jeu de piano avec notes tombantes. L'utilisateur rapporte **4 BUGS CRITIQUES**. Je te fournis : vidéo complète + logs Flutter + logs backend. 

**⚠️ INSTRUCTION CRITIQUE** : Tu DOIS analyser **L'INTÉGRALITÉ DE LA VIDÉO** du début à la fin, pas seulement quelques secondes. Tous les bugs apparaissent à différents moments.

---

## 📋 LES 4 BUGS À ANALYSER

### **BUG 1 - Image prévisualisation au démarrage**
**Symptôme** : Après avoir appuyé sur Play, pendant ~0-2 secondes, les notes apparaissent brièvement à l'écran (probablement en bas ou au milieu) avant de disparaître, puis le countdown "3-2-1" commence et les notes tombent normalement.

**Ce que tu dois faire** :
- Noter EXACTEMENT à quel moment cette "prévisualisation" apparaît (timestamp précis)
- Mesurer la position Y des notes pendant cette prévisualisation
- Noter combien de temps dure cette prévisualisation (en millisecondes)
- Vérifier si c'est AVANT ou APRÈS le countdown "3"

---

### **BUG 2 - Notes qui remontent + changement longueur**
**Symptôme** : À un moment donné pendant la practice (probablement vers 5s), les notes font un "saut" vers le haut (remontent), puis après ce saut, la LONGUEUR des rectangles de notes change visuellement.

**Ce que tu dois faire** :
- Noter EXACTEMENT le timestamp où les notes remontent (précision 0.001s)
- Mesurer l'amplitude du saut en pixels (Y avant - Y après)
- Mesurer la HAUTEUR des rectangles de notes AVANT le saut (en pixels)
- Mesurer la HAUTEUR des rectangles de notes APRÈS le saut (en pixels)
- Calculer le ratio de changement (ex: si notes passent de 40px à 60px = 1.5x)
- Vérifier si c'est lié au passage countdown→running ou au premier appui utilisateur

**Indices dans les logs** :
- Chercher `COUNTDOWN_FINISH` pour voir la transition countdown→running
- Chercher `[PAINTER] paint()` et noter si `fallLead` ou `size` changent brutalement
- Chercher `elapsed` et vérifier s'il y a une discontinuité (ex: -0.5s puis soudain 0.1s)

---

### **BUG 3 - Illumination incohérente des notes**
**Symptôme** : Quand une note tombe et touche le clavier (ligne du bas), elle est CENSÉE changer de couleur (devenir verte/jaune) si l'utilisateur joue la bonne note au bon moment. PROBLÈME : certaines notes s'illuminent correctement, d'autres NON alors qu'elles semblent correctement jouées.

**Ce que tu dois faire** :
- Analyser les **10 PREMIÈRES NOTES** jouées par l'utilisateur
- Pour CHAQUE note, noter :
  - **T** (timestamp en secondes quand note touche clavier)
  - **Couleur AVANT** : gris/bleu
  - **Couleur APRÈS** : vert/jaune (correcte) OU inchangée (BUG)
  - **S'illumine ?** : OUI / NON
- Détecter un PATTERN :
  - Notes impaires (1,3,5,7,9) OK mais paires (2,4,6,8,10) NON ?
  - Alternance aléatoire ?
  - Lié au timing (retard/avance) ?

**Indices dans les logs** :
- Chercher `NoteAccuracy` avec `perfect`, `good`, ou `miss`
- Chercher `_lastCorrectNote=` et vérifier s'il change ou reste bloqué
- Chercher `MIC_INPUT` et vérifier si `sampleRate=` est cohérent (doit être 32000-48000)
- Chercher `semitoneShift=` : s'il est NON NUL (ex: -5.13) → problème pitch detection !

---

### **BUG 4 - Auto-replay sans afficher scores**
**Symptôme** : Quand la vidéo se termine (toutes les notes jouées), au lieu d'afficher le tableau des scores, l'application REMET PLAY automatiquement et recommence immédiatement.

**Ce que tu dois faire** :
- Noter le timestamp exact où la vidéo/practice se termine
- Noter ce qui se passe dans les 2 secondes suivantes :
  - Le tableau des scores apparaît-il ? (même brièvement ?)
  - Le countdown "3-2-1" redémarre immédiatement ?
  - Y a-t-il un flash/transition ou c'est instantané ?
- Vérifier s'il y a un message/popup de félicitations avant le replay

**Indices dans les logs** :
- Chercher `VIDEO_END` ou `practice ended`
- Chercher `showSummary` ou `_showResultsDialog`
- Chercher `_resetPracticeSession` ou `_startPractice` appelé juste après la fin

---

## 🎬 WORKFLOW D'ANALYSE OBLIGATOIRE

### ÉTAPE 1 : Vue d'ensemble de la vidéo

Avant d'analyser les bugs, donne-moi :

```
Durée totale vidéo       : XX:XX.XXX
Nombre de tests visibles : X (parfois user teste plusieurs fois dans même vidéo)
Timestamps clés :
  - T_play (premier Play)       : XX.XXXs
  - T_countdown_start ("3")     : XX.XXXs
  - T_countdown_end (music)     : XX.XXXs
  - T_first_note_hit            : XX.XXXs
  - T_video_end                 : XX.XXXs
  - T_replay (si auto-replay)   : XX.XXXs
```

**⚠️ SI PLUSIEURS TESTS** : Précise lequel analyser (généralement le DERNIER test = dernière partie logs).

---

### ÉTAPE 2 : Analyse BUG 1 (Prévisualisation)

Analyse frame-by-frame de **T_play à T_play+3s** :

**T=T_play (instant où user clique Play):**
```
Frame état :
  - Notes visibles ? OUI / NON
  - Si OUI :
    Y_top_note    = XXXpx (distance du haut écran à la note la plus haute)
    Y_bottom_note = XXXpx
    Y_keyboard    = XXXpx (ligne du clavier cible)
    Nombre notes  = X
    Durée visible = XXXms
  - Countdown "3" visible ? OUI / NON
```

**T=T_play+0.2s:**
```
(mêmes infos)
```

**T=T_play+0.5s:**
```
(mêmes infos)
```

**T=T_play+1.0s:**
```
(mêmes infos)
```

**T=T_play+2.0s:**
```
(mêmes infos)
```

**DIAGNOSTIC BUG 1:**
```
✓ Prévisualisation détectée ? OUI / NON
✓ Durée totale = XXXms
✓ Position Y moyenne = XXXpx (en bas/milieu/haut ?)
✓ Disparition à T = XX.XXXs
✓ Lien avec countdown ? (avant/après "3" apparaît)
```

**LOGS BUG 1:**
```
Colle ICI tous les logs entre T_play et T_play+3s qui contiennent :
- [PAINTER] paint()
- SPAWN note
- Countdown C8/C7/C6
- elapsed=
- size=
```

---

### ÉTAPE 3 : Analyse BUG 2 (Saut + changement longueur)

Analyse frame-by-frame autour du SAUT (généralement vers T_countdown_end) :

**Mesures AVANT le saut (T_saut - 0.5s):**
```
Position note référence (ex: 2ème note visible) :
  Y_ref           = XXXpx
  Hauteur rect    = XXpx (mesure verticale du rectangle bleu)
  Largeur rect    = XXpx
```

**Mesures AU MOMENT du saut (T_saut):**
```
Position note référence :
  Y_ref_avant     = XXXpx (dernière frame avant saut)
  Y_ref_après     = XXXpx (première frame après saut)
  ΔY              = XXXpx (négatif si remonte)
  
Dimensions rectangles :
  Hauteur_avant   = XXpx
  Hauteur_après   = XXpx
  Ratio_hauteur   = X.XX (après/avant)
```

**Mesures APRÈS le saut (T_saut + 0.5s):**
```
Position note référence :
  Y_ref           = XXXpx
  Hauteur rect    = XXpx (stable maintenant ?)
```

**DIAGNOSTIC BUG 2:**
```
✓ Saut détecté à T     = XX.XXXs
✓ Amplitude saut       = XXpx vers haut/bas
✓ Changement hauteur ? = OUI / NON
✓ Ratio changement     = X.XX
✓ Cause probable       = countdown→running / premier appui / autre ?
```

**LOGS BUG 2:**
```
Colle ICI tous les logs dans fenêtre [T_saut-1s, T_saut+1s] qui contiennent :
- COUNTDOWN_FINISH
- [PAINTER] paint()
- elapsed=
- fallLead=
- size=
- latency=
```

---

### ÉTAPE 4 : Analyse BUG 3 (Illumination)

Pour les **10 PREMIÈRES NOTES** que l'utilisateur joue, remplis ce tableau :

```
╔═══════╦═══════════╦═══════════════╦═══════════════╦═══════════╗
║ Note# ║ Timestamp ║ Couleur AVANT ║ Couleur APRÈS ║ Illumine? ║
╠═══════╬═══════════╬═══════════════╬═══════════════╬═══════════╣
║   1   ║  XX.XXXs  ║  bleu/gris    ║  vert/jaune   ║    OUI    ║
╠═══════╬═══════════╬═══════════════╬═══════════════╬═══════════╣
║   2   ║  XX.XXXs  ║  bleu/gris    ║  inchangé     ║    NON    ║
╠═══════╬═══════════╬═══════════════╬═══════════════╬═══════════╣
║   3   ║           ║               ║               ║           ║
╠═══════╬═══════════╬═══════════════╬═══════════════╬═══════════╣
║  ...  ║           ║               ║               ║           ║
╚═══════╩═══════════╩═══════════════╩═══════════════╩═══════════╝
```

**PATTERN détecté:**
```
- Notes 1,3,5,7,9 illuminent ? ___
- Notes 2,4,6,8,10 illuminent ? ___
- Pattern alternance ? ___
- Timing impact ? (retard/avance)
```

**DIAGNOSTIC BUG 3:**
```
✓ Taux succès illumination = X/10 (60% par exemple)
✓ Pattern identifié         = OUI / NON
✓ Toujours même note bloquée ? = OUI / NON
✓ Lié au pitch detection ?   = voir logs MIC_INPUT
```

**LOGS BUG 3:**
```
Colle ICI pour CHAQUE note du tableau ci-dessus :

Note 1 (T=XX.XXXs):
  MIC_INPUT: ...
  NoteAccuracy: perfect/good/miss
  _lastCorrectNote=XX
  
Note 2 (T=XX.XXXs):
  MIC_INPUT: ...
  NoteAccuracy: ...
  _lastCorrectNote=XX
  
(etc pour les 10 notes)

Aussi chercher et copier :
- MIC_INPUT sessionId=... sampleRate=XXXXX semitoneShift=X.XX
- Si semitoneShift != 0.00 → PROBLÈME PITCH !
```

---

### ÉTAPE 5 : Analyse BUG 4 (Auto-replay)

Analyse des **dernières 5 secondes** de la vidéo :

**T=T_video_end (quand dernière note jouée/passée):**
```
Frame état :
  - Score affiché ?           OUI / NON
  - Tableau résultats ?       OUI / NON
  - Popup félicitations ?     OUI / NON
  - Countdown "3" redémarre ? OUI / NON / IMMÉDIAT ?
```

**T=T_video_end+0.5s:**
```
(mêmes infos)
```

**T=T_video_end+1.0s:**
```
(mêmes infos)
```

**T=T_video_end+2.0s:**
```
(mêmes infos - practice a redémarré ?)
```

**DIAGNOSTIC BUG 4:**
```
✓ Scores affichés ?       = OUI (XXXms) / NON
✓ Replay immédiat ?       = OUI / NON
✓ Temps avant replay      = XXXms
✓ User a cliqué quelque chose ? = OUI / NON
```

**LOGS BUG 4:**
```
Colle ICI tous les logs dans fenêtre [T_video_end-2s, T_video_end+3s] qui contiennent :
- VIDEO_END
- practice ended
- showSummary
- _showResultsDialog
- _resetPracticeSession
- _startPractice
- User interaction
```

---

## 📊 ÉTAPE FINALE : Synthèse et hypothèses

Après avoir analysé les 4 bugs, donne-moi :

```
═══════════════════════════════════════════════════════
SYNTHÈSE ANALYSE COMPLÈTE
═══════════════════════════════════════════════════════

[BUG 1] PRÉVISUALISATION NOTES
───────────────────────────────────────────────────────
Confirmé         : OUI / NON
Durée            : XXXms
Position Y       : XXXpx (en bas/milieu/haut)
Hypothèse cause  : [Layout instable / shouldPaintNotes trop tôt / autre]
Recommandation   : [Augmenter guard de 200ms → 300ms / autre]

[BUG 2] SAUT + CHANGEMENT LONGUEUR
───────────────────────────────────────────────────────
Confirmé         : OUI / NON
Timestamp        : XX.XXXs
Amplitude saut   : XXpx
Changement taille: X.XX ratio
Hypothèse cause  : [Discontinuité elapsed / recalcul fallLead / latency issue]
Recommandation   : [Fixer transition countdown→running / autre]

[BUG 3] ILLUMINATION INCOHÉRENTE
───────────────────────────────────────────────────────
Confirmé         : OUI / NON
Taux succès      : X/10
Pattern          : [Alternance / Aléatoire / Toujours mêmes notes]
Pitch detection  : [OK / sampleRate=XXXXX semitoneShift=X.XX PROBLÈME]
Hypothèse cause  : [RMS trop bas / wrong pitch / MicEngine logic]
Recommandation   : [Ajuster threshold / fixer sampleRate / autre]

[BUG 4] AUTO-REPLAY SANS SCORES
───────────────────────────────────────────────────────
Confirmé         : OUI / NON
Scores affichés  : OUI (XXXms) / NON
Replay timing    : XXXms après fin
Hypothèse cause  : [Callback vidéo trop rapide / showSummary skipped / autre]
Recommandation   : [Ajouter delay avant replay / forcer dialog / autre]

[ANOMALIES GLOBALES]
───────────────────────────────────────────────────────
- Logs manquants ?
- Crashes/erreurs ?
- Timing global ok ?
- Autres bugs détectés ?
```

---

## 🔧 INFOS TECHNIQUES POUR TOI

**Coordonnées écran:**
- Y=0px : Top écran (spawn notes hors-écran)
- Y≈400px : Clavier (ligne cible où notes doivent être jouées)
- Y≈1500px : Bottom écran

**Formule position notes:**
```dart
Y = (elapsed - (noteStart - fallLead)) / fallLead × overlayHeight
```
- Si Y < 0 → note hors-écran top (pas encore tombée)
- Si Y ≈ 400 → note au niveau clavier (moment de jouer)
- Si Y > 1500 → note hors-écran bottom (ratée)

**Illumination logique:**
```
Note s'illumine SI :
  1. detectedPitch == expectedPitch (±1 semitone)
  2. timing == good/perfect (±120ms head window)
  3. note pas déjà hit (_hitNotes[i] == false)
```

**Variables clés dans logs:**
- `elapsed` : temps écoulé depuis début practice (secondes)
- `fallLead` : durée de chute des notes (secondes, ex: 2.5s)
- `size` : dimensions canvas (width, height)
- `sampleRate` : fréquence audio micro (devrait être 32000-48000)
- `semitoneShift` : décalage pitch (devrait être 0.00, sinon PROBLÈME)
- `_lastCorrectNote` : MIDI dernière note correcte (devrait changer à chaque hit)

---

## ⚠️ INSTRUCTIONS ULTRA IMPORTANTES

1. **ANALYSE COMPLÈTE** : Tu DOIS regarder la vidéo DU DÉBUT À LA FIN, pas juste quelques secondes
2. **PRÉCISION** : Tous les timestamps en format XX.XXXs (3 décimales)
3. **MESURES** : Toutes les positions Y en pixels EXACTS (utilise règle/outil si besoin)
4. **LOGS** : COPIE-COLLE les logs pertinents, ne paraphrase PAS
5. **HYPOTHÈSES** : Propose des causes probables basées sur vidéo + logs
6. **RECOMMANDATIONS** : Propose des fixes précis (avec valeurs numériques)

Si un bug n'apparaît PAS dans la vidéo, dis-le clairement : "BUG X non reproduit dans cette vidéo".

**C'EST PARTI ! Analyse maintenant la vidéo et les logs.**
