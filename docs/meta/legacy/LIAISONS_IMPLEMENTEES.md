# 🔗 Toutes les Liaisons Implémentées - ShazaPiano

## ✅ Liaisons Fonctionnelles

### 1. HOME PAGE → ENREGISTREMENT
**Fichier**: `app/lib/presentation/pages/home/home_page.dart`

```
Bouton RECORD (idle)
  │
  ├─ Tap → recordingProvider.startRecording()
  │         └─ Permission microphone
  │         └─ Démarrage AudioRecorder
  │         └─ État: RECORDING
  │
  └─ Tap (pendant recording) → recordingProvider.stopRecording()
            └─ Fichier .m4a sauvegardé
            └─ État: PROCESSING
```

### 2. UPLOAD & PROCESSING
**Fichier**: `app/lib/presentation/state/process_provider.dart`

```
Fichier Audio
  │
  ├─ processProvider.processAudio(audioFile, levels: [1,2,3,4])
  │   └─ Upload vers backend /process
  │   └─ Progression: L1 → L2 → L3 → L4
  │   └─ Feedback visuel (ModeChips)
  │
  └─ Résultat: ProcessResponse
        ├─ job_id
        ├─ key_guess (tonalité)
        ├─ tempo_guess
        └─ levels[4]
            ├─ preview_url (16s)
            ├─ video_url (full)
            └─ midi_url
```

### 3. PREVIEWS PAGE
**Fichier**: `app/lib/presentation/pages/previews/previews_page.dart`

```
Grille 2×2
  │
  ├─ VideoTile L1 (Hyper Facile)
  │   └─ Tap → PlayerPage(level1, isUnlocked)
  │
  ├─ VideoTile L2 (Facile)
  │   └─ Tap → PlayerPage(level2, isUnlocked)
  │
  ├─ VideoTile L3 (Moyen)
  │   └─ Tap → PlayerPage(level3, isUnlocked)
  │
  ├─ VideoTile L4 (Pro)
  │   └─ Tap → PlayerPage(level4, isUnlocked)
  │
  └─ Bouton "Débloquer pour 1$"
      └─ Tap → PaywallModal
```

### 4. PLAYER PAGE
**Fichier**: `app/lib/presentation/pages/player/player_page.dart`

```
Lecteur Vidéo (Chewie)
  │
  ├─ isUnlocked = true
  │   ├─ Affiche: video_url (full)
  │   ├─ Bouton Partager → _handleShare()
  │   ├─ Bouton Télécharger → _handleDownload()
  │   └─ Bouton "Mode Pratique 🎹"
  │       └─ Tap → PracticePage(level)
  │
  └─ isUnlocked = false
      ├─ Affiche: preview_url (16s)
      ├─ Badge "🔒 Preview 16s"
      └─ Bouton "Débloquer pour 1$"
          └─ Tap → PaywallModal
```

### 5. PRACTICE MODE
**Fichier**: `app/lib/presentation/pages/practice/practice_page.dart`

```
Mode Pratique
  │
  ├─ Clavier virtuel C2-C6 (49 touches)
  │   └─ Highlight notes attendues
  │
  ├─ Détection pitch temps réel (MPM)
  │   └─ Microphone → PitchDetector
  │       └─ Fréquence détectée
  │
  ├─ Feedback visuel
  │   ├─ ✅ VERT: Note correcte (±25 cents)
  │   ├─ ⚠️ JAUNE: Proche (±25-50 cents)
  │   └─ ❌ ROUGE: Fausse note (>50 cents)
  │
  └─ Score précision
      └─ % notes correctes
```

### 6. PAYWALL & IAP
**Fichiers**: `app/lib/presentation/widgets/paywall_modal.dart`, `app/lib/presentation/state/iap_provider.dart`

```
PaywallModal (Dialog)
  │
  ├─ Avantages listés (5 features)
  │
  ├─ Bouton "Acheter maintenant - 1,00 $"
  │   └─ Tap → iapProvider.purchase('piano_all_levels_1usd')
  │       └─ Google Play IAP
  │           ├─ Success → Firestore.update(unlocked: true)
  │           │         └─ Navigator.pop(true)
  │           └─ Error → SnackBar erreur
  │
  └─ Bouton "Restaurer l'achat"
      └─ Tap → iapProvider.restorePurchases()
          └─ Check Google Play
              ├─ Found → Firestore.update(unlocked: true)
              │        └─ SnackBar "Restauré !"
              └─ Not Found → SnackBar "Aucun achat"
```

---

## 🔧 Providers & State Management

### recordingProvider
```dart
// Usage dans HomePage
final recordingNotifier = ref.read(recordingProvider.notifier);

// Démarrer
await recordingNotifier.startRecording();

// Arrêter
await recordingNotifier.stopRecording();

// État
final recordingState = ref.watch(recordingProvider);
// recordingState.isRecording
// recordingState.recordedFile
// recordingState.error
```

### processProvider
```dart
// Usage dans HomePage
final processNotifier = ref.read(processProvider.notifier);

// Traiter
await processNotifier.processAudio(
  audioFile: file,
  withAudio: false,
  levels: [1,2,3,4],
);

// État
final processState = ref.watch(processProvider);
// processState.result (ProcessResponse)
// processState.uploadProgress
// processState.error
```

### iapProvider
```dart
// Usage dans PaywallModal
final iapNotifier = ref.read(iapProvider.notifier);

// Acheter
await iapNotifier.purchase('piano_all_levels_1usd');

// Restaurer
await iapNotifier.restorePurchases();

// État
final iapState = ref.watch(iapProvider);
// iapState.isUnlocked
// iapState.isPurchasing
// iapState.error
```

---

## 🎨 Widgets Réutilisables

### BigRecordButton
```dart
BigRecordButton(
  state: RecordButtonState.idle, // ou recording, processing
  onTap: () => _handleRecordButtonTap(),
)
```

### ModeChip (L1-L4)
```dart
ModeChip(
  level: 1,
  status: ModeChipStatus.queued, // ou processing, completed, error
)
```

### VideoTile
```dart
VideoTile(
  level: 1,
  levelName: "Hyper Facile",
  previewUrl: "https://...",
  isUnlocked: false,
  isLoading: false,
  videoKey: "C",
  tempo: 120,
  onTap: () => navigateToPlayer(),
)
```

### AppLogo
```dart
AppLogo(
  width: 120,
  height: 40,
)
```

---

## 🧪 Points de Test

### Test 1: Enregistrement
- [x] Microphone permission
- [x] Démarrage recording
- [x] Arrêt recording
- [x] Fichier sauvegardé

### Test 2: Upload
- [x] Connexion backend
- [x] Upload fichier
- [ ] Progression visuelle (TODO: backend doit être lancé)

### Test 3: Previews
- [x] Affichage 4 vidéos
- [x] Navigation vers Player
- [ ] Lecture preview 16s (TODO: backend doit générer vidéos)

### Test 4: IAP
- [ ] Configuration Google Play (TODO: produit IAP à créer)
- [ ] Achat test
- [ ] Restauration

### Test 5: Practice Mode
- [x] Détection pitch
- [x] Feedback visuel
- [x] Score précision

---

## ⚙️ Configuration Requise

### Backend
```bash
# Lancer le backend localement
cd backend
python -m venv venv
source venv/bin/activate  # ou venv\Scripts\activate sur Windows
pip install -r requirements.txt
python app.py

# Backend accessible sur http://localhost:8000
```

### App Config
```dart
// app/lib/core/config/app_config.dart

// Pour téléphone physique, utiliser l'IP locale:
backendBaseUrl: 'http://192.168.1.X:8000'  // Remplacer X par votre IP

// Ou déployer backend et utiliser:
backendBaseUrl: 'https://votre-backend.fly.dev'
```

### Google Play Console
1. Créer produit IAP
2. Product ID: `piano_all_levels_1usd`
3. Type: Non-consumable
4. Prix: 1,00 USD
5. Ajouter comptes test

---

## 📊 Résumé

### Implémenté ✅
- Enregistrement audio réel
- Upload vers backend
- Affichage résultats (4 vidéos)
- Navigation complète
- Lecteur vidéo
- Paywall & IAP
- Practice mode avec pitch detection
- Firebase (auth, firestore, crashlytics)

### En Attente du Backend ⏳
- Génération des 4 vidéos MP4
- MIDI extraction (BasicPitch)
- Arrangements (L1-L4)
- Render piano animé

### Non-Critique (Futures Features) 🔮
- Menu & Settings
- Historique
- Partage social
- Téléchargement offline
- Tutoriel

---

**Status**: 🎯 Flux principal complet, prêt pour test avec backend

