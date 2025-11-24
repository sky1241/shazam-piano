# ShazaPiano - Flutter App

Application mobile Flutter pour transformer un enregistrement piano en 4 vidéos pédagogiques animées.

## 🎨 Features

- 🎤 Enregistrement audio (~8s)
- 🎹 Génération de 4 niveaux de difficulté (L1-L4)
- 📺 Previews 16s gratuits
- 💰 Achat unique 1$ pour débloquer tout
- 🎵 Mode pratique avec détection fausses notes
- 🌙 Dark theme type Shazam

## 🏗️ Architecture

Clean Architecture avec 4 couches :

```
lib/
├── core/               # Configuration, theme, utils
│   ├── config/        # App config & environments
│   ├── constants/     # Constants globales
│   └── theme/         # Design system (colors, text, theme)
│
├── data/              # Data layer
│   ├── datasources/   # API clients, local DB
│   ├── models/        # DTOs & JSON serialization
│   └── repositories/  # Repository implementations
│
├── domain/            # Business logic
│   ├── entities/      # Business objects
│   ├── repositories/  # Repository interfaces
│   └── usecases/      # Use cases
│
└── presentation/      # UI layer
    ├── state/         # Riverpod providers
    ├── pages/         # Screens
    └── widgets/       # Reusable widgets
```

## 🚀 Quick Start

### Prérequis
- Flutter 3.9.2+
- Android Studio / Xcode
- Firebase project configuré

### Installation

```bash
# Installer dépendances
flutter pub get

# Générer code (Riverpod, Retrofit, JSON)
flutter pub run build_runner build --delete-conflicting-outputs

# Lancer en dev
flutter run --flavor dev --dart-define=BACKEND_BASE=http://10.0.2.2:8000

# Lancer en prod
flutter run --flavor prod --release
```

## 📦 Packages Principaux

### State & Navigation
- `flutter_riverpod` - State management
- `go_router` - Navigation déclarative

### Network
- `dio` - HTTP client
- `retrofit` - Type-safe API client

### Audio/Video
- `record` - Audio recording
- `video_player` + `chewie` - Video playback
- `permission_handler` - Permissions

### Firebase
- `firebase_core`, `firebase_auth`, `cloud_firestore`
- `firebase_analytics`, `firebase_crashlytics`

### IAP
- `in_app_purchase` - In-App Purchase

### Storage
- `shared_preferences` - Local key-value
- `path_provider` - File paths

## 🎨 Design System

### Colors
```dart
// Background
bg: #0B0F10
surface: #12171A
card: #0F1417

// Primary
primary: #2AE6BE
primaryVariant: #21C7A3
accent: #7EF2DA

// Text
textPrimary: #E9F5F1
textSecondary: #A9C3BC

// Status
success: #47E1A8
warning: #F6C35D
error: #FF6B6B
```

### Typography
- Display: 24px - Titres principaux
- Title: 18px - Sous-titres
- Body: 14px - Corps
- Caption: 12px - Légendes

### Spacing
4 / 8 / 12 / 16 / 24 / 32 px

### Border Radius
- Buttons: 24px
- Cards: 16px

## 🔥 Firebase Setup

1. Créer projet Firebase
2. Ajouter Android app : `com.ludo.shazapiano`
3. Télécharger `google-services.json` → `android/app/`
4. (iOS) Télécharger `GoogleService-Info.plist` → `ios/Runner/`
5. Activer :
   - Authentication (Anonymous)
   - Cloud Firestore
   - Analytics
   - Crashlytics

### Firestore Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## 💳 In-App Purchase Setup

### Google Play Console
1. Créer produit non-consommable
2. ID: `piano_all_levels_1usd`
3. Prix: 1.00 USD
4. Titre: "Débloquer tous les niveaux"
5. Description: "Accès complet aux 4 niveaux à vie"

### Testing
- Créer license testers dans Play Console
- Utiliser comptes test pour sandbox

## 🧪 Tests

```bash
# Unit tests
flutter test

# Widget tests
flutter test test/widgets/

# Integration tests
flutter test integration_test/
```

## 🏗️ Build

### Android

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Release AAB (Play Store)
flutter build appbundle --release
```

### iOS

```bash
# Debug
flutter build ios --debug

# Release
flutter build ios --release
```

## 📱 Flavors

### Dev
```bash
flutter run --flavor dev --dart-define=BACKEND_BASE=http://10.0.2.2:8000
```

### Prod
```bash
flutter run --flavor prod --dart-define=BACKEND_BASE=https://api.shazapiano.com
```

## 📝 TODO - Structure à Créer

### Data Layer
- [ ] `data/datasources/api_client.dart` (Retrofit)
- [ ] `data/datasources/local_storage.dart`
- [ ] `data/models/level_result.dart`
- [ ] `data/repositories/video_repository_impl.dart`

### Domain Layer
- [ ] `domain/entities/level.dart`
- [ ] `domain/entities/video_result.dart`
- [ ] `domain/repositories/video_repository.dart`
- [ ] `domain/usecases/process_audio.dart`
- [ ] `domain/usecases/purchase_all_levels.dart`

### Presentation Layer
- [ ] `presentation/pages/home/home_page.dart`
- [ ] `presentation/pages/previews/previews_page.dart`
- [ ] `presentation/pages/player/player_page.dart`
- [ ] `presentation/pages/practice/practice_page.dart`
- [ ] `presentation/widgets/big_record_button.dart`
- [ ] `presentation/widgets/mode_chip.dart`
- [ ] `presentation/widgets/video_tile.dart`
- [ ] `presentation/widgets/paywall_modal.dart`
- [ ] `presentation/state/recording_provider.dart`
- [ ] `presentation/state/iap_provider.dart`

## 📄 Licence

Propriétaire - ShazaPiano © 2025
