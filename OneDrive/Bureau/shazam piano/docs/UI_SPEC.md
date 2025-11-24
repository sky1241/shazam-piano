# ShazaPiano - UI & Design System

## 🎨 Design System (Dark Theme)

### Palette de Couleurs
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
divider: #1E2A2E

// Status
success: #47E1A8
warning: #F6C35D
error: #FF6B6B
```

### Typography
- **Display**: 24px - Titres principaux
- **Title**: 18px - Sous-titres
- **Body**: 14px - Corps de texte
- **Caption**: 12px - Légendes

**Font**: SF Pro (iOS) / Roboto (Android)

### Spacing
4 / 8 / 12 / 16 / 24 / 32 px

### Border Radius
- Buttons: 24px
- Cards: 16px

### Shadows
Soft blur: 30px

### Gradients
```dart
// Background radial (center 0,-0.2)
radialGradient: [#2AE6BE @12%, transparent]

// Button linear
buttonGradient: [#2AE6BE → #21C7A3]
```

---

## 📱 Écrans

### 1. Home (Shazam-like)
- Grand bouton circulaire central (220px)
- Icon: microphone / stop
- Text: "Appuie pour créer tes 4 vidéos piano"
- 4 pastilles de progression: L1 / L2 / L3 / L4
- États: en file, en cours, terminé, erreur

**Flux**: Tap → Record 8s → Upload → Processing → Previews

### 2. Previews (Grille 2×2)
- 4 tuiles vidéo avec lecture auto
- Badge "16s preview" sur chaque carte
- Infos: Niveau, tonalité, tempo
- CTA: "Débloquer les 4 pour 1$" ou "Ouvrir"

### 3. Player (Full Video)
- Lecteur vidéo en boucle
- Métadonnées: Level, Key, Tempo, Duration
- Actions:
  - 📥 Télécharger
  - 📤 Partager
  - 🎹 Mode Pratique

### 4. Paywall
- Card sombre centrée
- Titre: "Tout débloquer pour 1$"
- Liste avantages:
  - ✓ 4 niveaux de difficulté
  - ✓ Accès complet illimité
  - ✓ Mises à jour gratuites
- CTA: "Acheter maintenant (1$)"
- Lien: "Restaurer l'achat"

### 5. Practice Mode
- Clavier virtuel simplifié
- Timeline avec barres de mesure
- Détection pitch monophonique (YIN/MPM)
- Feedback temps réel:
  - ✅ Vert: Note correcte
  - ⚠️ Jaune: Proche (±25-50 cents)
  - ❌ Rouge: Fausse note (>50 cents)
- Score par mesure
- Tolérance: ±50 cents, min 80ms

---

## 🧩 Composants UI

### BigRecordButton
```dart
- Diameter: 220px
- Icon: mic / stop (animated)
- Gradient: primary → primaryVariant
- Shadow: soft blur
- States: idle, recording, processing
```

### ModeChip
```dart
- Labels: L1, L2, L3, L4
- States: queued, processing, done, error
- Colors: divider, warning, success, error
```

### VideoTile
```dart
- Thumbnail: video frame
- Badge: "16s preview" / "Unlocked"
- Title: Level name
- Subtitle: Key, Tempo
- Loading overlay
```

### PaywallModal
```dart
- Card: rounded 16px
- Price: $1.00 highlighted
- CTA button: gradient primary
- Restore link: textSecondary
```

### PracticeHUD
```dart
- Virtual keyboard: C2-C6
- Progress bar: measure timeline
- Indicators: correct/wrong/close
- Score counter: realtime %
```

---

## 🎯 Interactions

### Bouton Record
- **Tap**: Start recording (pulse animation)
- **Recording**: Waveform animation
- **Release/Stop**: Upload + navigate to Previews

### Video Tiles
- **Tap**: Open Player (if unlocked) or Paywall
- **Long press**: Options menu (share, download)

### Practice Mode
- **Mic input**: Real-time pitch detection
- **Visual feedback**: Halo on expected key
- **Score**: Live update per measure

---

## 📐 Layout Responsive

### Portrait (default)
- Home: Button centered
- Previews: 2×2 grid
- Player: Full width video

### Landscape
- Optimized for video playback
- Controls overlay bottom

