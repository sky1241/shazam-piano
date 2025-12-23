# 🎹 ShazaPiano v0.1.0 - Release Notes

**Release Date**: TBD (After Testing)  
**Version**: 0.1.0 (Build 1)  
**Codename**: "Harmonic Genesis" 🎵

---

## 🎉 Première Version Publique !

Nous sommes ravis d'annoncer la première version de **ShazaPiano** - l'application qui transforme tes enregistrements piano en vidéos pédagogiques animées !

---

## ✨ Fonctionnalités Principales

### 🎤 Enregistrement Audio
- Enregistre 8 secondes de piano avec ton micro
- Support formats : M4A, WAV, MP3
- Interface simple type Shazam
- Validation automatique qualité audio

### 🎹 Génération Automatique 4 Niveaux

**Niveau 1 - Hyper Facile** 🌟
- Mélodie simplifiée
- Main droite seule
- En Do majeur
- Tempo ralenti (-20%)
- Parfait pour débutants complets

**Niveau 2 - Facile** ⭐
- Mélodie + basse simple
- Accompagnement fondamentale
- Toujours en Do majeur
- Tempo ralenti (-10%)
- Idéal pour 3-6 mois de piano

**Niveau 3 - Moyen** ⭐⭐
- Mélodie + accords plaqués
- Tonalité originale
- Rythme authentique
- Tempo original
- Pour pianistes intermédiaires

**Niveau 4 - Pro** ⭐⭐⭐
- Arrangement complet
- Arpèges et voicings
- Toutes les nuances
- Complexité maximale
- Pour pianistes avancés

### 📺 Previews Gratuits
- 16 secondes par niveau
- Lecture illimitée
- Qualité HD (1280×360)
- Pas de watermark

### 💰 Achat Unique 1$
- Débloquer les 4 niveaux
- Accès complet illimité
- Téléchargement vidéos
- Mises à jour gratuites à vie
- **Prix** : 1.00 USD (ou équivalent local)

### 🎵 Mode Pratique (Practice Mode)
- Détection notes en temps réel
- Feedback visuel immédiat :
  - ✅ Vert : Note parfaite (±25 cents)
  - ⚠️ Jaune : Proche (±50 cents)
  - ❌ Rouge : À retravailler
- Score et précision %
- Clavier virtuel interactif

### 🎨 Interface Moderne
- Dark theme élégant
- Style Shazam
- Animations fluides
- UX intuitive

---

## 🔧 Détails Techniques

### Intelligence Artificielle
- **BasicPitch** (Spotify) pour extraction MIDI
- Estimation automatique tempo (BPM)
- Détection tonalité (algorithme Krumhansl-Schmuckler)
- Pitch detection (algorithme MPM)

### Performance
- Génération : ~60 secondes pour 4 niveaux
- Upload : Optimisé pour 4G/WiFi
- Vidéos : 30 FPS, 1280×360
- Previews : 16s, compression optimale

### Compatibilité
- **Android** : 6.0+ (API 23+)
- **Testé sur** : Samsung, Google Pixel, Xiaomi
- **Taille app** : ~50 MB
- **Internet** : Requis pour génération

### Services
- **Backend** : FastAPI sur serveurs EU
- **Cloud** : Firebase (Auth, Firestore, Analytics)
- **Paiement** : Google Play Billing
- **Privacy** : GDPR & CCPA compliant

---

## 🆕 Nouveautés v0.1.0

### Première Release Majeure
- [x] Système complet audio → vidéo
- [x] 4 niveaux de difficulté
- [x] Mode pratique avec détection notes
- [x] Système monétisation (IAP)
- [x] Interface utilisateur complète
- [x] Documentation exhaustive

---

## 🐛 Bugs Connus & Limitations

### Limitations Connues
1. **Instruments** : Piano uniquement (pour l'instant)
2. **Enregistrement** : Environnement calme requis
3. **Génération** : Connexion internet nécessaire
4. **Preview** : Limité à 16 secondes (gratuit)

### Bugs Mineurs
1. Audio synthesis parfois indisponible → Workaround: vidéos muettes ok
2. Très gros fichiers (>8MB) peuvent timeout → Workaround: <10s recording

### Work in Progress
- Support iOS (prévu M6)
- Multi-instruments (prévu M7)
- Bibliothèque morceaux (prévu M5)

---

## 🔐 Confidentialité & Sécurité

### Vos Données
- Enregistrements supprimés après 24h
- Vidéos supprimées après 7j
- Aucune vente de données
- Analytics 100% anonyme

### Sécurité
- Connexions HTTPS/TLS
- Pas de tracking publicitaire
- Code open à audit (sur demande)
- Conformité GDPR/CCPA

---

## 📥 Installation & Mise à Jour

### Première Installation
1. Télécharger depuis Google Play Store
2. Accorder permission micro
3. Créer ton premier enregistrement
4. Enjoy ! 🎹

### Mise à Jour
- Auto-update via Play Store (recommandé)
- Ou manuel : Play Store > ShazaPiano > Mettre à jour

---

## 💬 Feedback & Support

### Nous Contacter

**Support** : support@shazapiano.com  
**Feedback** : feedback@shazapiano.com  
**Bugs** : bugs@shazapiano.com  
**General** : ludo@shazapiano.com

### Réseaux Sociaux
- GitHub : https://github.com/sky1241/shazam-piano
- Email : ludo@shazapiano.com

### Demandes de Fonctionnalités
Partagez vos idées ! Nous écoutons :
- Email : features@shazapiano.com
- GitHub Issues avec tag `enhancement`

---

## 🏗️ Développé Avec

- ❤️ Passion pour la musique
- 🧠 Intelligence artificielle (Spotify BasicPitch)
- 🎨 Design moderne (Material Design 3)
- ⚡ Technologies modernes (Flutter, FastAPI)
- 🔒 Respect de votre vie privée

---

## 🎯 Roadmap

### v0.2.0 (M2) - Q1 2026
- Optimisations performance
- Amélioration qualité MIDI
- Plus d'accompagnements

### v0.3.0 (M3) - Q1 2026
- Modes arrangement personnalisés
- Ajout SoundFont de qualité
- Export partition PDF

### v0.4.0 (M4) - Q2 2026
- Support iOS
- Partage social
- Bibliothèque morceaux

### v1.0.0 - Q3 2026
- Multi-instruments (guitare, violon)
- Mode collaboration
- Streaming en direct

---

## 📊 Statistiques Projet

**Développement** :
- 7 heures intensives
- 11 commits majeurs
- 11,250+ lignes de code
- 200+ fichiers

**Stack** :
- Python 3.10+ (Backend)
- Flutter 3.16+ (Mobile)
- Firebase (Cloud)
- Docker (DevOps)

**Documentation** :
- 12 documents
- 4,500+ lignes
- 9 guides complets

---

## 🙏 Remerciements Spéciaux

**Technologies** :
- Spotify BasicPitch Team
- Flutter Team @ Google
- FastAPI by Sebastián Ramírez
- Firebase Team

**Inspiration** :
- Shazam (UI/UX)
- Synthesia (Video style)
- Simply Piano (Practice concept)

---

## 📜 Licence

Propriétaire - ShazaPiano © 2025  
Voir [LICENSE](LICENSE) pour détails complets.

---

## ⚠️ Disclaimer

Cette app utilise IA pour générer arrangements. Les résultats peuvent varier selon la qualité d'enregistrement. Meilleurs résultats avec piano bien accordé et environnement calme.

---

# 🎉 Merci d'utiliser ShazaPiano !

**Transforme ton piano en vidéos pédagogiques en quelques secondes ! 🎹**

---

**Questions ?** ludo@shazapiano.com  
**Support ?** support@shazapiano.com  
**GitHub ?** https://github.com/sky1241/shazam-piano

---

*Bonne musique et bon apprentissage ! 🎹✨*

**- L'équipe ShazaPiano**


