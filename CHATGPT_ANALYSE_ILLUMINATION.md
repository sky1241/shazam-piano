# ANALYSE VIDÉO - BUGS ILLUMINATION NOTES (3 BUGS PRÉCIS)

Tu vas analyser une vidéo de jeu de piano avec notes tombantes. **FOCUS : Illumination des notes quand l'utilisateur joue.**

---

## 🎯 CE QUE TU DOIS OBSERVER

### **Contexte rapide**
- Des rectangles (notes) tombent du haut vers le clavier en bas
- Quand une note touche le clavier ET que user joue la bonne touche → elle DOIT s'illuminer
- Le clavier du bas affiche aussi les touches jouées (changent de couleur quand user appuie)

---

## 🐛 LES 3 BUGS À ANALYSER

### **BUG 5 - Note ne change PAS de couleur (juste halo)**

**Question** : Quand l'utilisateur joue une note correcte, est-ce que le RECTANGLE de la note change de couleur OU est-ce qu'il reste orange avec juste un effet lumineux/halo autour ?

**Attendu** :
- Rectangle note tombe (couleur : orange/gris)
- User joue la bonne touche au bon moment
- Rectangle devient **VERT** ou **JAUNE** (même couleur que la touche du clavier)

**Actuel (bug)** :
- Rectangle reste orange
- Juste un halo/glow apparaît autour

**Ce que tu dois noter** :
```
Pour les 5 premières notes jouées correctement :

Note 1 (timestamp ~Xs) :
- Couleur rectangle AVANT jeu : [orange/gris/autre]
- Couleur rectangle APRÈS jeu : [reste pareil/devient vert/devient jaune]
- Halo/effet visible : OUI/NON
- BUG ? [OUI si reste orange, NON si devient vert/jaune]

Note 2 (timestamp ~Xs) :
[même format...]

Note 3, 4, 5...
```

---

### **BUG 6 - Halo appliqué sur TOUTES les notes du même pitch**

**Question** : Quand user joue une note (ex: C4), est-ce que le halo/effet lumineux apparaît sur :
- ✅ SEULEMENT la note EN COURS (celle qui touche le clavier maintenant)
- ❌ TOUTES les notes C4 visibles à l'écran (passées + futures)

**Exemple problème** :
```
Timeline:
- T=5s : Note C4 #1 tombe, user joue → halo ✅ OK
- T=8s : Note C4 #2 tombe
- T=10s : Note C4 #3 tombe

Si BUG : #2 et #3 ont AUSSI le halo alors qu'elles ne sont pas encore jouées
Si OK : Seulement #1 a le halo
```

**Ce que tu dois noter** :
```
Trouve une note qui apparaît plusieurs fois (ex: C4, D4, E4...)

Pitch choisi : [Ex: C4]

Première fois jouée (~Xs) :
- Halo sur cette note : OUI/NON
- Halo sur les prochaines notes du même pitch visibles : OUI/NON

Si halo sur prochaines notes → BUG 6 CONFIRMÉ
```

---

### **BUG 7 - Certaines notes s'illuminent, d'autres non (aléatoire)**

**Question** : Sur les 10 premières notes jouées, est-ce que TOUTES s'illuminent correctement OU certaines sont ignorées ?

**Ce que tu dois noter** :
```
Tableau simple des 10 premières notes :

Note 1 (~Xs) : Touche jouée [C4/D4/etc] → Illumination OUI/NON
Note 2 (~Xs) : Touche jouée [C4/D4/etc] → Illumination OUI/NON
Note 3 (~Xs) : Touche jouée [C4/D4/etc] → Illumination OUI/NON
...
Note 10 (~Xs) : Touche jouée [...] → Illumination OUI/NON

Pattern détecté :
- Alternance (1 oui, 1 non) ? OUI/NON
- Premières notes OK, dernières KO ? OUI/NON
- Pitch spécifiques (ex: C4 OK mais D4 KO) ? OUI/NON
- Complètement aléatoire ? OUI/NON
```

---

## 📊 FORMAT DE RÉPONSE FINAL

```
=== BUG 5 (couleur rectangle) ===
Résumé : [Les rectangles changent de couleur OU restent orange avec juste halo]

Détails 5 premières notes :
[Tableau avec avant/après couleur]

Conclusion BUG 5 : PRÉSENT / ABSENT

---

=== BUG 6 (halo sur futures notes) ===
Résumé : [Halo seulement sur note jouée OU sur toutes les notes du même pitch]

Pitch testé : [Ex: C4]
Première occurrence (~Xs) : Halo OUI
Deuxième occurrence (~Xs) : Halo OUI/NON (si elle n'est pas encore jouée)

Conclusion BUG 6 : PRÉSENT / ABSENT

---

=== BUG 7 (illumination incohérente) ===
Résumé : [Toutes les notes s'illuminent OU certaines sont ignorées]

[Tableau 10 notes avec OUI/NON]

Pattern : [Description simple]

Conclusion BUG 7 : PRÉSENT / ABSENT
```

---

## 🎯 INDICES DANS LES LOGS (pour confirmer)

Si tu veux croiser vidéo + logs :

### **Pour BUG 5/6/7 (illumination) :**

Cherche ces patterns dans les logs :

```
HIT_DECISION sessionId=X noteIdx=Y result=HIT
```
→ Si tu vois `result=HIT` mais pas d'illumination vidéo = BUG

```
NoteAccuracy sessionId=X noteIdx=Y accuracy=perfect/good
```
→ Confirme que la note est détectée comme correcte

```
_lastCorrectNote=XX
```
→ Indique quelle note devrait avoir le halo

```
semitoneShift=1.95
```
→ Si présent, problème pitch detection (cause BUG 7)

---

## ⚡ INSTRUCTIONS IMPORTANTES

1. **Regarde 15-20 secondes de practice** (pas toute la vidéo)
2. **Focus sur 5-10 premières notes** jouées par user
3. **Note les timestamps approximatifs** (~5s, ~8s, etc.) - pas besoin de précision 0.001s
4. **Décris ce que tu VOIS**, pas ce que tu penses

---

**C'EST TOUT !** Donne-moi le format de réponse ci-dessus avec tes observations simples. 👀
