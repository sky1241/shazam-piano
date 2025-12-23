# 🎹 ShazaPiano

[![GitHub](https://img.shields.io/badge/github-sky1241%2Fshazam--piano-blue?logo=github)](https://github.com/sky1241/shazam-piano)
[![Backend CI](https://github.com/sky1241/shazam-piano/workflows/Backend%20CI/badge.svg)](https://github.com/sky1241/shazam-piano/actions)
[![Flutter CI](https://github.com/sky1241/shazam-piano/workflows/Flutter%20CI/badge.svg)](https://github.com/sky1241/shazam-piano/actions)
[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/)
[![Flutter](https://img.shields.io/badge/flutter-3.16+-blue.svg)](https://flutter.dev/)

**Transformez vos enregistrements piano en vidéos pédagogiques animées**

Enregistrez ~8 secondes de piano → Obtenez instantanément 4 niveaux de difficulté avec clavier animé.

[Features](#-features) • [Architecture](#-architecture) • [Quick Start](#-quick-start) • [Documentation](#-documentation) • [Contributing](#-contributing)

---

## ✨ Features

- 🎤 **Enregistrement simple** : 8 secondes suffisent
- 🎹 **4 niveaux automatiques** : Hyper Facile → Facile → Moyen → Pro
- 📺 **Previews gratuits** : 16 secondes par niveau
- 💰 **Achat unique 1$** : Débloquez tout à vie
- 🎵 **Mode Pratique** : Détection des fausses notes en temps réel
- 🌙 **UI Shazam-like** : Dark theme moderne

---

## 🏗️ Architecture

### Monorepo Structure

```
shazapiano/
├── app/           # Flutter mobile app
│   ├── lib/
│   │   ├── core/         # Config, theme, constants
│   │   ├── data/         # Data sources, models, repos
│   │   ├── domain/       # Entities, use cases
│   │   └── presentation/ # UI, state, pages
│   └── pubspec.yaml
│
├── backend/       # FastAPI server
│   ├── app.py         # Routes & endpoints
│   ├── config.py      # Levels presets & config
│   ├── inference.py   # BasicPitch MIDI extraction
│   ├── arranger.py    # 4-level arrangements
│   ├── render.py      # Video generation
│   └── requirements.txt
│
├── infra/         # Docker, CI/CD
│   └── docker-compose.yml
│
└── docs/          # Documentation
    ├── ARCHITECTURE.md
    ├── UI_SPEC.md
    └── ROADMAP.md
```

### Repo layout updates
- Root now contains directly: `app/`, `backend/`, `packages/`, `scripts/`, `infra/`, `docs/`, `.github/`, `Makefile`.
- Archives et anciens docs: `docs/meta/legacy/` (index: `docs/meta/README.md`).
- Pièces jointes PDF: `docs/attachments/`.
- Fiches IA: `AGENTS.md`, `PROJECT_MAP.md`, `TASK_TEMPLATE.md` à la racine.

### Commandes utiles (Makefile)
- Flutter: `make install-flutter`, `make flutter-format`, `make flutter-analyze`, `make flutter-test`.
- Backend: `make install-backend`, `make backend-run`, `make backend-test`, `make backend-lint`.
- Nettoyage: `make clean`; CI combiné: `make ci-all`.

---

## 🚀 Quick Start

### Backend (FastAPI)

```bash
cd backend

# Setup
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt

# Run
uvicorn app:app --reload --host 0.0.0.0 --port 8000
```

API: http://localhost:8000
Docs: http://localhost:8000/docs

### Frontend (Flutter)

```bash
cd app

# Setup
flutter pub get

# Run (Android Emulator)
flutter run --flavor dev --dart-define=BACKEND_BASE=http://10.0.2.2:8000
```

### Docker

```bash
cd infra
docker-compose up --build
```

---

## 🎯 Stack Technique

### Frontend
- **Framework** : Flutter 3.9.2+
- **State** : Riverpod
- **Navigation** : go_router
- **HTTP** : Dio + Retrofit
- **Audio** : record package
- **Video** : video_player + chewie
- **IAP** : in_app_purchase
- **Firebase** : Auth + Firestore + Analytics + Crashlytics

### Backend
- **Framework** : FastAPI + Uvicorn
- **ML** : BasicPitch (Spotify) - MIDI extraction
- **Video** : MoviePy + FFmpeg
- **Audio** : Fluidsynth + SoundFont .sf2
- **MIDI** : PrettyMIDI

### Infrastructure
- **Container** : Docker
- **Hosting** : Fly.io / Railway / VPS
- **CI/CD** : GitHub Actions
- **DB** : Firebase Firestore

---

## 🎹 4 Niveaux de Difficulté

| Niveau | Description | Transposition | Accompagnement | Public |
|--------|-------------|---------------|----------------|--------|
| **L1 - Hyper Facile** | Mélodie simple | → C Majeur | Mélodie seule | Débutants complets |
| **L2 - Facile** | + Basse | → C Majeur | Fondamentale tenue | 3-6 mois de piano |
| **L3 - Moyen** | + Accords | Tonalité originale | Triades plaquées | 6-12 mois |
| **L4 - Pro** | Arrangement complet | Tonalité originale | Arpèges + voicings | 1+ an |

---

## 💰 Modèle Économique

- ✅ **Previews gratuits** : 16 secondes par niveau
- ✅ **Achat unique** : 1.00 USD (non-consommable)
- ✅ **Déblocage** : Accès complet aux 4 niveaux à vie
- ✅ **Mises à jour** : Gratuites

---

## 📱 Screens

### 1. Home (Shazam-like)
- Gros bouton circulaire central
- "Appuie pour créer tes 4 vidéos piano"
- 4 pastilles de progression (L1-L4)

### 2. Previews (Grille 2×2)
- 4 tuiles vidéo avec lecture auto
- Badge "16s preview"
- CTA "Débloquer pour 1$"

### 3. Player
- Lecteur vidéo complet
- Métadonnées : Level, Key, Tempo
- Actions : Télécharger, Partager, Pratiquer

### 4. Paywall
- Modal élégant
- Prix : 1.00 USD
- Avantages : 4 niveaux, accès illimité
- Bouton "Restaurer l'achat"

### 5. Practice Mode
- Clavier virtuel animé
- Détection pitch monophonique
- Feedback temps réel : ✅ Vert / ⚠️ Jaune / ❌ Rouge
- Score par mesure

---

## 🔥 API Endpoints

### `POST /process`
Génère les 4 vidéos à partir d'un audio

**Paramètres** :
- `audio` (file) : Fichier audio (m4a, wav, mp3)
- `with_audio` (bool) : Inclure audio synthétisé
- `levels` (string) : Niveaux à générer (default: "1,2,3,4")

**Réponse** :
```json
{
  "job_id": "20251124_030700_12345",
  "timestamp": "2025-11-24T03:07:00",
  "levels": [
    {
      "level": 1,
      "name": "Hyper Facile",
      "preview_url": "/media/out/job_L1_preview.mp4",
      "video_url": "/media/out/job_L1_full.mp4",
      "midi_url": "/media/out/job_L1.mid",
      "key_guess": "C",
      "tempo_guess": 120,
      "duration_sec": 8.0
    }
    // ... L2, L3, L4
  ]
}
```

### `GET /health`
Health check

### `DELETE /cleanup/{job_id}`
Nettoyer les fichiers d'un job

---

## 🧪 Tests

### Backend
```bash
cd backend
pytest
pytest --cov=. --cov-report=html
```

### Frontend
```bash
cd app
flutter test
flutter test --coverage
```

---

## 🚢 Déploiement

### Backend (Fly.io)
```bash
cd backend
fly launch
fly deploy
```

### Frontend (Play Store)
```bash
cd app
flutter build appbundle --release
# Upload AAB to Play Console
```

---

## 📝 Roadmap

- [x] **M1 - MVP** : Un seul niveau, vidéo muette
- [ ] **M2 - 4 Niveaux** : Génération parallèle L1-L4
- [ ] **M3 - Paywall** : IAP 1$ + previews 16s
- [ ] **M4 - Audio** : Synthèse piano .sf2
- [ ] **M5 - Release** : CI/CD + Alpha Testing

Voir [docs/ROADMAP.md](docs/ROADMAP.md) pour plus de détails.

---

## 📚 Documentation

- [📐 Architecture](docs/ARCHITECTURE.md) - Stack technique & structure
- [🎨 UI Spec](docs/UI_SPEC.md) - Design system & écrans
- [🗺️ Roadmap](docs/ROADMAP.md) - Jalons & planning

---

## 🤝 Contribution

Ce projet est actuellement privé. Contact : ludo@shazapiano.com

---

## 📄 Licence

Propriétaire - ShazaPiano © 2025

---

## 👨‍💻 Auteur

**Ludo** - Créateur de ShazaPiano

---

## 🙏 Remerciements

- **Spotify BasicPitch** - Extraction MIDI
- **MoviePy** - Génération vidéo
- **Flutter** - Framework mobile
- **FastAPI** - Backend moderne

---

**🎹 Transforme ton piano en vidéos pédagogiques en quelques secondes !**

## Codex usage
- Start every new Codex session by reading CODEX_SYSTEM.md
