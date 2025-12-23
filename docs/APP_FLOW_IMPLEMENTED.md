# ShazaPiano - Flux d'Application Implémenté

## 🔄 Flux Complet

### 1. Home Page → Enregistrement
**Fichiers**: `lib/presentation/pages/home/home_page.dart`

**Liaisons implémentées**:
- ✅ Bouton Record (BigRecordButton) → `_handleRecordButtonTap()`
- ✅ État idle → Démarre l'enregistrement audio via `recordingProvider.startRecording()`
- ✅ État recording → Arrête l'enregistrement via `recordingProvider.stopRecording()`
- ✅ Gestion des permissions microphone
- ✅ Feedback visuel avec les 4 pastilles L1-L4

### 2. Upload → Backend API
**Fichiers**: `lib/presentation/state/process_provider.dart`

**Liaisons implémentées**:
- ✅ Upload du fichier audio vers `/process`
- ✅ Progression visuelle des 4 niveaux
- ✅ Paramètres: `audioFile`, `withAudio`, `levels`
- ✅ Gestion d'erreur avec retry logic
- ✅ Timeouts configurés

### 3. Processing → Previews Page
**Fichiers**: `lib/presentation/pages/previews/previews_page.dart`

**Liaisons implémentées**:
- ✅ Navigation automatique vers PreviewsPage après traitement
- ✅ Affichage grille 2×2 des 4 niveaux
- ✅ Chaque VideoTile affiche: preview 16s, niveau, tonalité, tempo
- ✅ Badge "16s preview" sur chaque carte
- ✅ Bouton "Débloquer pour 1$" en bas

### 4. Video Tile → Player Page
**Fichiers**: `lib/presentation/pages/player/player_page.dart`

**Liaisons implémentées**:
- ✅ Tap sur VideoTile → Navigation vers PlayerPage
- ✅ Lecteur vidéo (Chewie + VideoPlayer)
- ✅ Affichage métadonnées: niveau, tonalité, tempo, durée
- ✅ Boutons: Partager, Télécharger (si débloqué)
- ✅ Bouton "Mode Pratique" (si débloqué)
- ✅ Bouton "Débloquer pour 1$" (si verrouillé)

### 5. Player → Practice Mode
**Fichiers**: `lib/presentation/pages/practice/practice_page.dart`

**Liaisons implémentées**:
- ✅ Bouton "Mode Pratique" → Navigation vers PracticePage
- ✅ Détection pitch en temps réel (MPM algorithm)
- ✅ Clavier virtuel C2-C6
- ✅ Feedback visuel:
  - ✅ Vert: Note correcte (±25 cents)
  - ⚠️ Jaune: Proche (±50 cents)
  - ❌ Rouge: Fausse note (>50 cents)
- ✅ Score de précision en temps réel

### 6. Paywall → In-App Purchase
**Fichiers**: `lib/presentation/widgets/paywall_modal.dart`, `lib/presentation/state/iap_provider.dart`

**Liaisons implémentées**:
- ✅ Modal PaywallModal (Dialog)
- ✅ Liste des avantages: 4 niveaux, vidéos complètes, mode pratique, téléchargements, mises à jour
- ✅ Bouton "Acheter maintenant - 1,00 $" → `iapProvider.purchase()`
- ✅ Bouton "Restaurer l'achat" → `iapProvider.restorePurchases()`
- ✅ Gestion d'erreur et feedback utilisateur
- ✅ Product ID: `piano_all_levels_1usd`

### 7. Home → Menu & Historique
**Fichiers**: `lib/presentation/pages/home/home_page.dart`

**TODO (non critique)**:
- ⏳ Bouton Menu → Navigation vers SettingsPage
- ⏳ Bouton Historique → Navigation vers HistoryPage

---

## 📊 État des Providers

### RecordingProvider
**Fichier**: `lib/presentation/state/recording_provider.dart`

**Fonctionnalités**:
- ✅ `startRecording()` - Démarre l'enregistrement
- ✅ `stopRecording()` - Arrête et sauvegarde
- ✅ `cancelRecording()` - Annule et supprime
- ✅ Timer de durée (max 30s)
- ✅ Gestion permissions

### ProcessProvider
**Fichier**: `lib/presentation/state/process_provider.dart`

**Fonctionnalités**:
- ✅ `processAudio()` - Upload et traitement
- ✅ Progression upload (0-100%)
- ✅ Gestion d'erreur DioException
- ✅ Timeout handling

### IAPProvider
**Fichier**: `lib/presentation/state/iap_provider.dart`

**Fonctionnalités**:
- ✅ `initialize()` - Init In-App Purchase
- ✅ `purchase(productId)` - Achat 1$
- ✅ `restorePurchases()` - Restaurer
- ✅ Sync avec Firestore (userId, unlocked, unlocked_at)

---

## 🎯 Flux Utilisateur Complet

```
[Home]
  ↓ Tap Record Button
[Recording...] (8-30s)
  ↓ Tap Stop
[Uploading...] (progress bar)
  ↓ Backend processing
[Processing L1...L2...L3...L4] (visual feedback)
  ↓ Success
[Previews Page] (grille 2×2)
  ↓ Tap Video Tile
[Player Page] (preview 16s ou full si débloqué)
  ↓ Si verrouillé: Tap "Débloquer 1$"
[Paywall Modal]
  ↓ Tap "Acheter maintenant"
[Google Play IAP Flow]
  ↓ Success
[Previews Page] (refreshed, unlocked)
  ↓ Tap Video Tile
[Player Page] (full video)
  ↓ Tap "Mode Pratique"
[Practice Mode] (pitch detection en temps réel)
```

---

## 🐛 Points d'Attention

### Backend Requis
⚠️ Pour que le traitement fonctionne, le backend FastAPI doit être lancé :
```bash
cd backend
python app.py
```

URL backend dans `lib/core/config/app_config.dart`:
- Dev: `http://10.0.2.2:8000` (pour émulateur Android)
- Prod: `https://api.shazapiano.com` (à configurer)

### IAP Configuration
⚠️ Pour tester les achats, configurer dans Google Play Console :
1. Créer produit IAP: `piano_all_levels_1usd` (1,00 USD)
2. Ajouter comptes test dans License testing
3. Build AAB signé (pas debug APK)

### Firebase
✅ Firebase est configuré et initialisé :
- Anonymous auth
- Firestore pour user data
- Crashlytics pour erreurs
- Analytics pour events

---

## 📝 Ce Qui Manque (Non-Bloquant)

### Menu & Settings
- ⏳ Page de paramètres
- ⏳ Choix de langue
- ⏳ Tutoriel premier lancement

### Historique
- ⏳ Liste des générations précédentes
- ⏳ Sauvegarde locale (SharedPreferences)
- ⏳ Sync avec Firestore

### Partage & Téléchargement
- ⏳ Partager vidéo vers réseaux sociaux
- ⏳ Télécharger MP4 sur l'appareil
- ⏳ Télécharger MIDI

### Optimisations
- ⏳ Cache vidéos en local
- ⏳ Offline mode pour vidéos téléchargées
- ⏳ Compression vidéo pour preview

---

## ✅ Ce Qui Fonctionne

1. **Enregistrement audio** ✅
2. **Upload vers backend** ✅
3. **Affichage previews** ✅
4. **Navigation vers Player** ✅
5. **Lecteur vidéo** ✅
6. **Paywall modal** ✅
7. **Practice mode** ✅
8. **Firebase integration** ✅
9. **Crashlytics** ✅
10. **Analytics** ✅

---

## 🚀 Pour Tester

1. Lancer le backend:
```bash
cd backend
python app.py
```

2. Lancer l'app:
```bash
cd app
flutter run
```

3. Workflow:
- Tap bouton record
- Enregistrer 8s de piano
- Attendre traitement
- Voir les 4 vidéos
- Tap sur une vidéo pour lecture
- Tester mode pratique (si débloqué)

---

Date: 27 Nov 2025
Status: ✅ Flux principal complet

