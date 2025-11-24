# ShazaPiano - FAQ (Foire Aux Questions)

## 🎹 Questions Générales

### Qu'est-ce que ShazaPiano ?

ShazaPiano est une application mobile qui transforme tes enregistrements de piano en vidéos pédagogiques animées. Enregistre 8 secondes de piano et obtiens instantanément 4 versions de difficulté différente avec un clavier visuel animé.

### Comment ça fonctionne ?

1. **Enregistre** ~8 secondes de piano avec le micro de ton téléphone
2. **L'IA analyse** et extrait la mélodie (BasicPitch de Spotify)
3. **Génération automatique** de 4 arrangements (Facile → Pro)
4. **Reçois** 4 vidéos avec clavier animé

### C'est gratuit ?

- ✅ **Previews gratuits** : 16 secondes par niveau
- 💰 **Déblocage complet** : 1.00 USD (achat unique à vie)

### Quels instruments sont supportés ?

Actuellement : **Piano uniquement**  
Futures versions : Guitare, violon, autres instruments

---

## 🎵 Questions Techniques

### Quelle qualité d'enregistrement est nécessaire ?

- Micro smartphone standard suffit
- Environnement calme recommandé
- 8 secondes minimum, 15 secondes maximum
- Format : M4A, WAV, ou MP3

### Les 4 niveaux, c'est quoi exactement ?

1. **Niveau 1 - Hyper Facile** :
   - Mélodie simple, main droite seule
   - Transposé en Do majeur
   - Notes rondes/blanches
   - Tempo ralenti 20%

2. **Niveau 2 - Facile** :
   - Mélodie + basse simple
   - Toujours en Do majeur
   - Notes blanches et noires
   - Tempo ralenti 10%

3. **Niveau 3 - Moyen** :
   - Mélodie + accords plaqués
   - Tonalité originale
   - Rythme original
   - Tempo normal

4. **Niveau 4 - Pro** :
   - Arrangement complet
   - Arpèges et voicings
   - Toutes les nuances
   - Tempo original

### Combien de temps prend la génération ?

- Upload : ~5 secondes
- Génération : ~30-60 secondes pour les 4 niveaux
- Total : ~1 minute

### Puis-je télécharger les vidéos ?

- ✅ **Preview (gratuit)** : Lecture uniquement
- ✅ **Débloqué (1$)** : Téléchargement illimité

---

## 💰 Questions Monétisation

### Le paiement est unique ?

Oui ! **1.00 USD une seule fois**, accès à vie aux 4 niveaux pour toutes tes générations futures.

### Je peux restaurer mon achat ?

Oui, le bouton "Restaurer l'achat" est disponible si tu changes de téléphone ou réinstalles l'app.

### Les previews gratuits sont limités ?

Les previews de 16 secondes sont **illimités et gratuits** pour toujours. Seul l'accès complet (téléchargement + lecture > 16s) nécessite l'achat.

### Remboursement possible ?

Selon la politique Google Play (généralement 48h après achat).

---

## 🎓 Questions Practice Mode

### Comment fonctionne la détection des notes ?

- Micro capte ton piano
- Algorithme MPM détecte la fréquence (pitch)
- Comparaison avec les notes attendues
- Feedback visuel en temps réel (vert/orange/rouge)

### Quelle précision est requise ?

- **Vert (correct)** : ±25 cents (excellent)
- **Orange (proche)** : ±50 cents (bon)
- **Rouge (faux)** : >50 cents (à retravailler)

### Fonctionne avec un piano numérique ?

Oui ! Tant que le micro capte le son clairement.

### Fonctionne avec un vrai piano ?

Oui ! Environnement calme recommandé.

---

## 🔧 Questions Techniques Développeurs

### Quelle est la stack technique ?

**Backend** :
- FastAPI (Python)
- BasicPitch (Spotify) pour extraction MIDI
- MoviePy pour génération vidéo
- FFmpeg pour conversion audio/vidéo

**Frontend** :
- Flutter
- Riverpod (state management)
- Firebase (Auth, Firestore, Analytics)
- in_app_purchase (IAP)

### Puis-je contribuer au code ?

Le projet est actuellement privé. Contact : ludo@shazapiano.com

### L'app fonctionne sur iOS ?

Actuellement : **Android uniquement**  
Futures versions : iOS support prévu (M6)

### Puis-je self-host le backend ?

Oui ! Le code backend est disponible avec Docker. Voir `docs/DEPLOYMENT.md`.

---

## 🐛 Troubleshooting

### L'enregistrement ne fonctionne pas

**Solutions** :
1. Vérifier permissions micro dans paramètres Android
2. Redémarrer l'app
3. Vérifier que le micro n'est pas utilisé par une autre app

### La génération échoue

**Causes possibles** :
1. Enregistrement trop bruité → Essayer environnement calme
2. Aucune mélodie détectable → Jouer plus fort
3. Serveur saturé → Réessayer plus tard

**Solutions** :
- Enregistrer dans un endroit calme
- Jouer clairement et distinctement
- Vérifier connexion internet

### Les vidéos ne se chargent pas

**Solutions** :
1. Vérifier connexion internet
2. Attendre la fin du téléchargement
3. Réessayer plus tard
4. Redémarrer l'app

### L'achat ne fonctionne pas

**Solutions** :
1. Vérifier connexion Google Play
2. Utiliser le bouton "Restaurer l'achat"
3. Attendre quelques minutes (synchronisation)
4. Contacter support : ludo@shazapiano.com

### Le Practice Mode ne détecte pas mes notes

**Solutions** :
1. Environnement plus silencieux
2. Jouer plus fort et distinct
3. Vérifier permissions micro
4. Redémarrer le mode pratique

---

## 📱 Questions Compatibilité

### Android version minimale ?

Android 6.0 (API 23) et supérieur

### Fonctionne sur tablette ?

Oui ! L'interface s'adapte.

### Fonctionne hors-ligne ?

- ❌ Génération : Nécessite connexion internet
- ✅ Lecture vidéos déjà générées : Fonctionne hors-ligne
- ✅ Practice Mode : Fonctionne hors-ligne

### Quelle taille fait l'app ?

- APK : ~50 MB
- Avec vidéos sauvegardées : +10-20 MB par génération

---

## 🔐 Questions Confidentialité

### Que faites-vous de mes enregistrements ?

- Enregistrements traités puis **supprimés après 24h**
- Vidéos générées gardées 7 jours puis supprimées
- Aucun stockage permanent côté serveur
- Option de sauvegarde locale uniquement

### Mes données sont-elles partagées ?

Non. Aucune donnée n'est partagée avec des tiers.

### Puis-je supprimer mes données ?

Oui, via paramètres app ou contact : privacy@shazapiano.com

---

## 📧 Contact

### Support Technique

Email : support@shazapiano.com  
Réponse sous 48h

### Questions Générales

Email : ludo@shazapiano.com

### Rapporter un Bug

GitHub : https://github.com/sky1241/shazam-piano/issues  
Ou : bugs@shazapiano.com

### Business / Partenariats

Email : business@shazapiano.com

---

## 🔮 Futures Fonctionnalités

Voir notre [Roadmap](ROADMAP.md) pour :
- Support iOS
- Multi-instruments
- Bibliothèque de morceaux
- Partage social
- Export PDF partition
- Mode collaboration

---

**🎹 Encore des questions ? Contact : ludo@shazapiano.com**

