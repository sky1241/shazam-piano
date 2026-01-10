# ANALYSE VIDÉO SIMPLE - 4 BUGS PIANO

Tu vas regarder une vidéo d'un jeu de piano avec notes tombantes et décrire CE QUE TU VOIS. Pas besoin de mesures précises, juste des observations visuelles simples.

---

## 🎬 ÉTAPE 1 : Vue d'ensemble (regarde toute la vidéo)

**Donne-moi juste :**
- Durée totale : environ XX secondes
- User clique Play vers : ~X secondes
- Countdown "3-2-1" visible vers : ~X secondes  
- Practice démarre (musique) vers : ~X secondes
- Practice termine vers : ~X secondes

---

## 🐛 ÉTAPE 2 : Les 4 bugs - dis-moi ce que tu VOIS

### **BUG 1 - Flash de notes au début**
**Question** : Entre le moment où user clique Play et le moment où le countdown "3" apparaît, est-ce que tu vois des rectangles de notes apparaître brièvement ?

**Réponds juste :**
- ✅ OUI, je vois des notes pendant ~X secondes AVANT le countdown
- ❌ NON, aucune note avant le countdown, tout est propre

**Si OUI, décris simplement :**
- Elles apparaissent où ? (en haut / milieu / bas de l'écran)
- Elles restent combien de temps ? (moins d'1s / 1-2s / plus de 2s)
- Elles disparaissent comment ? (fondu / instantané)

---

### **BUG 2 - Notes qui sautent**
**Question** : Pendant la practice, est-ce que les notes font un "saut" bizarre vers le haut à un moment ?

**Réponds juste :**
- ✅ OUI, les notes sautent vers ~X secondes
- ❌ NON, les notes tombent tout le temps normalement

**Si OUI, décris simplement :**
- C'est juste après le countdown ou plus tard ?
- Le saut est petit (à peine visible) ou gros (très visible) ?
- Après le saut, les notes semblent plus courtes/longues qu'avant ? (OUI/NON)

---

### **BUG 3 - Notes pas illuminées**
**Question** : Quand les notes touchent le clavier (ligne du bas), elles DOIVENT changer de couleur si bien jouées. Est-ce que TOUTES les notes changent de couleur ou certaines restent grises ?

**Réponds juste :**
- ✅ TOUTES les notes bien jouées changent de couleur → PAS DE BUG
- ❌ CERTAINES notes bien jouées restent grises → BUG CONFIRMÉ
- ❓ PAS CLAIR, je ne vois pas bien les couleurs

**Si BUG, observe un pattern simple :**
- C'est les premières notes qui ne marchent pas ? (OUI/NON)
- C'est les dernières notes ? (OUI/NON)
- C'est 1 note sur 2 ? (OUI/NON)
- C'est aléatoire ? (OUI/NON)

---

### **BUG 4 - Replay automatique**
**Question** : Quand la practice se termine, est-ce qu'un tableau de scores s'affiche pendant au moins 1-2 secondes ?

**Réponds juste :**
- ✅ OUI, je vois le tableau de scores avec "Score: XXX, Précision: XX%"
- ❌ NON, ça repart direct en practice sans afficher les scores
- ❓ Le tableau apparaît mais disparaît trop vite (moins d'1 seconde)

**Si NON, décris :**
- Ça revient à l'écran d'accueil ou ça redémarre practice direct ?
- Le countdown "3-2-1" recommence immédiatement ? (OUI/NON)

---

## 📝 FORMAT DE RÉPONSE ATTENDU

```
=== VUE D'ENSEMBLE ===
Durée : ~XX secondes
Play cliqué : ~Xs
Countdown : ~Xs  
Practice démarre : ~Xs
Practice termine : ~Xs

=== BUG 1 (flash début) ===
Visible : OUI/NON
Si OUI : [description simple]

=== BUG 2 (saut notes) ===
Visible : OUI/NON
Si OUI : [description simple]

=== BUG 3 (illumination) ===
Toutes illuminées : OUI/NON
Pattern observé : [description simple]

=== BUG 4 (auto-replay) ===
Scores affichés : OUI/NON
Comportement : [description simple]
```

---

## 🎯 LOGS (optionnel - si tu veux confirmer)

Si tu veux confirmer ce que tu vois dans la vidéo, tu peux chercher dans les logs :

**Pour BUG 1 :** Cherche `COUNTDOWN_FINISH` - si notes visibles AVANT cette ligne = BUG

**Pour BUG 2 :** Cherche `elapsed` qui passe de négatif (-0.5s) à positif (0.1s) - regarde si transition est fluide ou brutale

**Pour BUG 3 :** Cherche `semitoneShift=` - s'il est != 0.00, c'est un problème de pitch detection

**Pour BUG 4 :** Cherche `video_end` ou `showSummary` - regarde si appelé et si scores s'affichent après

---

**C'EST TOUT !** Pas besoin de mesures pixel par pixel. Dis-moi juste ce que tu VOIS, en quelques phrases simples. 👀
