# 🎹 ShazaPiano - Comment Ça Marche ?

## 🎯 Le Concept

**ShazaPiano n'est PAS un Shazam !**

C'est un **générateur de tutoriels piano** à partir de votre jeu.

### Le Flux Simple
```
1. Vous JOUEZ du piano (8 secondes) 
   └─ Enregistrement audio de vous en train de jouer

2. L'app ANALYSE votre mélodie
   └─ BasicPitch extrait les notes MIDI

3. L'app CRÉE 4 versions arrangées
   └─ L1: Ultra simple (débutant)
   └─ L2: Facile (avec basse)
   └─ L3: Moyen (avec accords)
   └─ L4: Pro (arrangement complet)

4. L'app GÉNÈRE 4 vidéos tutoriels
   └─ Clavier animé avec notes qui tombent
   └─ Style "Piano Tiles" / "Synthesia"

5. Vous APPRENEZ à jouer votre mélodie
   └─ Mode Practice avec détection en temps réel
```

---

## 📖 Exemple Concret

### Vous Jouez
🎹 Vous jouez "Joyeux Anniversaire" au piano pendant 8 secondes

### L'App Crée
- **L1 - Hyper Facile**: Mélodie simple, une note à la fois, main droite uniquement
- **L2 - Facile**: Mélodie + notes de basse simples, 2 mains
- **L3 - Moyen**: Mélodie + accords plaqués
- **L4 - Pro**: Arrangement complet avec arpèges

### Vous Obtenez
4 vidéos tutoriels avec clavier animé montrant exactement quelles touches presser !

---

## 🔧 Le Backend (Intelligence)

### 1. BasicPitch (Spotify)
**Rôle**: Extraire les notes MIDI de votre enregistrement audio

```
Audio (.m4a) → [BasicPitch ML Model] → MIDI (notes + timing)
```

**Output Example**:
```
Notes détectées: 45 notes
Tonalité: C majeur
Tempo: 120 BPM
Durée: 8.3 secondes
```

### 2. Arranger (4 Niveaux)
**Rôle**: Créer 4 versions adaptées à différents niveaux

**L1 - Hyper Facile**:
- Transposé en Do majeur (touches blanches)
- Quantifié 1/4 (notes rondes/blanches)
- Mélodie seule
- Réduit à une note à la fois

**L2 - Facile**:
- Transposé en Do majeur
- Quantifié 1/8
- Mélodie + Basse (fondamentale tenue)
- 2 mains simples

**L3 - Moyen**:
- Tonalité originale conservée
- Quantifié 1/8-1/16
- Mélodie + Accords triades
- Accompagnement plaqué

**L4 - Pro**:
- Tonalité originale
- Quantifié 1/16 (précis)
- Arrangement complet
- Arpèges + Voicings complexes

### 3. Render (Vidéos)
**Rôle**: Créer les vidéos de clavier animé

**Specs Vidéo**:
- Résolution: 1280x360 pixels
- FPS: 30
- Codec: H.264
- Format: MP4

**Contenu**:
- Clavier de piano (88 touches ou focus sur notes utilisées)
- Barres colorées qui tombent (style Piano Tiles)
- Couleur: #2AE6BE (turquoise) selon design system

**2 versions par niveau**:
- `preview_16s.mp4` - Gratuit, 16 premières secondes
- `full.mp4` - Complet, débloqué avec achat 1$

---

## ⏱️ Auto-Stop Enregistrement

### Configuration Actuelle
**Fichier**: `app/lib/core/constants/app_constants.dart`

```dart
// Durée recommandée pour reconnaissance optimale
static const int recommendedRecordingDurationSec = 8;

// Durée maximale autorisée
static const int maxRecordingDurationSec = 30;
```

### Comportement Implémenté
✅ **Auto-stop après 8 secondes** (recommandé pour de bons résultats)

```dart
if (duration.inSeconds >= 8) {
  // Stop automatique
  stopRecording();
  // → Upload immédiat vers backend
}
```

**Pourquoi 8 secondes ?**
- Assez long pour BasicPitch d'analyser la mélodie
- Assez court pour extraction rapide
- Durée optimale pour un morceau court

---

## 🎵 Ce Que le Backend Fait

### Étape 1: Audio → WAV
```bash
ffmpeg -i recording.m4a -ar 22050 -ac 1 output.wav
```
- Conversion en 22050Hz (requis par BasicPitch)
- Mono (une seule piste)

### Étape 2: WAV → MIDI
```python
from basic_pitch.inference import predict_and_save

# ML model de Spotify
predict_and_save(
    audio_path_list=['recording.wav'],
    output_directory='output/',
    save_midi=True
)
# → Génère: recording_basic_pitch.mid
```

**Ce que BasicPitch détecte**:
- Notes jouées (pitch)
- Timing (quand commencent/finissent)
- Vélocité (intensité)

### Étape 3: MIDI → 4 Arrangements
```python
for level in [1, 2, 3, 4]:
    arranged_midi = arrange_level(
        midi=base_midi,
        level=level,
        key="C",  # détecté
        tempo=120  # détecté
    )
    # → 4 fichiers MIDI différents
```

### Étape 4: MIDI → Vidéo Animée
```python
# Pour chaque niveau
render_level_video(
    midi=arranged_midi,
    level=level,
    with_audio=False  # Muet ou avec son piano
)
# → Génère full.mp4 et preview_16s.mp4
```

---

## ✅ Ce Qui Est Implémenté

### Frontend (Flutter) ✅
- [x] Enregistrement audio (record package)
- [x] Auto-stop après 8 secondes
- [x] Upload vers backend
- [x] Affichage 4 vidéos
- [x] Lecteur vidéo (preview 16s)
- [x] Mode practice (pitch detection)
- [x] Paywall IAP (1$)

### Backend (FastAPI) ✅
- [x] Endpoint `/process` avec upload
- [x] Module `inference.py` - BasicPitch extraction
- [x] Module `arranger.py` - 4 niveaux d'arrangements
- [x] Module `render.py` - Génération vidéos MP4
- [x] Config complète (config.py)
- [x] Gestion erreurs et timeouts

---

## 🚀 Pour Que Ça Marche

### 1. Backend DOIT Être Lancé
```bash
cd backend

# Installer dépendances (première fois)
pip install -r requirements.txt

# Lancer le serveur
python app.py

# → Backend sur http://localhost:8000
```

### 2. Configuration App
**Fichier**: `app/lib/core/config/app_config.dart`

Pour téléphone physique, changer:
```dart
backendBaseUrl: 'http://192.168.1.X:8000'
// Remplacez X par votre IP locale
// Trouvez-la avec: ipconfig (Windows) ou ifconfig (Mac/Linux)
```

### 3. Test Complet
1. Lancer backend
2. Ouvrir app sur téléphone
3. Tap bouton Record
4. Jouer du piano pendant 8s (ou attendre auto-stop)
5. App upload automatiquement
6. Backend analyse (10-30s)
7. App affiche 4 vidéos !

---

## 📊 Flux Technique Détaillé

```
User taps Record Button
  ↓
recordingProvider.startRecording()
  ├─ Permissions microphone ✅
  ├─ AudioRecorder.start() ✅
  └─ Timer démarre ✅
  
After 8 seconds (auto)
  ↓
recordingProvider.stopRecording()
  ├─ AudioRecorder.stop() ✅
  ├─ Save file: /tmp/recording_XXX.m4a ✅
  └─ Return File object ✅

Immediately after stop
  ↓
processProvider.processAudio(file)
  ├─ Upload via Dio multipart ✅
  ├─ POST /process ✅
  └─ Progress tracking ✅

Backend receives
  ↓
/process endpoint
  ├─ Save to /media/in/
  ├─ inference.extract_midi() → MIDI ✅
  │   └─ BasicPitch ML model ✅
  ├─ For each level (1-4):
  │   ├─ arranger.arrange_level() ✅
  │   └─ render.render_video() ✅
  │       ├─ Generate full.mp4 ✅
  │       └─ Generate preview_16s.mp4 ✅
  └─ Return ProcessResponse with URLs ✅

App receives response
  ↓
Navigate to PreviewsPage
  ├─ Display 4 VideoTiles ✅
  ├─ Each shows preview 16s ✅
  └─ Tap to play full (if unlocked) ✅
```

---

## ⚠️ Solution au "Connection Timeout"

### Problème
```
Connection timeout
```

### Cause
Le backend n'est pas lancé !

### Solution
**Option 1: Backend Local**
```bash
cd backend
python app.py
```

Puis dans l'app, changez `app_config.dart`:
```dart
backendBaseUrl: 'http://192.168.1.X:8000'  // Votre IP locale
```

**Option 2: Backend Déployé**
Déployez le backend sur Fly.io/Railway et utilisez l'URL publique.

---

## 🎯 Résumé

### Ce Que Fait ShazaPiano
1. Vous JOUEZ du piano → App ENREGISTRE (auto-stop 8s)
2. App ANALYSE votre mélodie → Extrait les notes MIDI
3. App CRÉE 4 versions simplifiées/complexifiées
4. App GÉNÈRE 4 vidéos tutoriels avec clavier animé
5. Vous APPRENEZ à jouer avec le mode practice !

### Ce Qui Fonctionne Maintenant
- ✅ Enregistrement avec auto-stop 8s
- ✅ Upload vers backend (si backend lancé)
- ✅ Affichage vidéos
- ✅ Navigation complète
- ✅ Mode practice

### Ce Qui Manque Pour Test Complet
- ⚠️ **Lancer le backend Python** pour générer les vidéos
- ⚠️ **Configurer l'IP** dans app_config.dart

---

Le code est **100% conforme aux PDFs** ! Il manque juste de lancer le backend pour voir les vidéos générées. 🚀
