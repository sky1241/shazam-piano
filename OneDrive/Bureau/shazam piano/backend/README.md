# ShazaPiano Backend

FastAPI backend pour générer 4 niveaux de vidéos piano à partir d'un enregistrement audio.

## 🚀 Quick Start

### Prérequis
- Python 3.10+
- FFmpeg installé et dans PATH
- pip ou uv

### Installation

```bash
# Créer environnement virtuel
python -m venv .venv

# Activer (Windows)
.venv\Scripts\activate

# Activer (Linux/Mac)
source .venv/bin/activate

# Installer dépendances
pip install -r requirements.txt
```

### Configuration

```bash
# Copier le fichier d'exemple
cp .env.example .env

# Éditer .env si nécessaire
```

### Lancer le serveur

```bash
# Mode développement (auto-reload)
uvicorn app:app --reload --host 0.0.0.0 --port 8000

# Ou directement
python app.py
```

API disponible sur: http://localhost:8000

Documentation interactive: http://localhost:8000/docs

## 📡 API Endpoints

### `POST /process`
Génère 4 vidéos de difficulté progressive.

**Paramètres:**
- `audio` (file): Fichier audio (m4a, wav, mp3)
- `with_audio` (bool): Inclure audio synthétisé (défaut: false)
- `levels` (string): Niveaux à générer, ex: "1,2,3,4" (défaut: tous)

**Réponse:**
```json
{
  "job_id": "20251124_030700_12345",
  "timestamp": "2025-11-24T03:07:00",
  "levels": [
    {
      "level": 1,
      "name": "Hyper Facile",
      "preview_url": "/media/out/jobid_L1_preview.mp4",
      "video_url": "/media/out/jobid_L1_full.mp4",
      "midi_url": "/media/out/jobid_L1.mid",
      "key_guess": "C",
      "tempo_guess": 120,
      "duration_sec": 8.0,
      "status": "success"
    },
    // ... L2, L3, L4
  ]
}
```

### `GET /health`
Health check

### `DELETE /cleanup/{job_id}`
Supprime tous les fichiers d'un job

## 🏗️ Architecture

```
backend/
├── app.py              # FastAPI routes
├── config.py           # Configuration & presets des 4 niveaux
├── inference.py        # BasicPitch extraction MIDI (TODO)
├── arranger.py         # Arrangements par niveau (TODO)
├── render.py           # Génération vidéo (TODO)
├── requirements.txt    # Dépendances Python
├── .env.example        # Variables d'environnement
└── media/
    ├── in/             # Uploads temporaires (purge 24h)
    └── out/            # Vidéos générées (purge 7j)
```

## 🎹 4 Niveaux de Difficulté

| Niveau | Description | Transposition | Accompagnement |
|--------|-------------|---------------|----------------|
| L1 | Hyper Facile | → C Maj | Mélodie seule |
| L2 | Facile | → C Maj | + Basse fondamentale |
| L3 | Moyen | Originale | + Triades plaquées |
| L4 | Pro | Originale | + Arpèges complets |

Voir `config.py` pour tous les paramètres.

## 🔧 Modules à Implémenter

### `inference.py`
```python
def extract_melody_from_audio(audio_path: Path) -> PrettyMIDI:
    """
    - FFmpeg: audio → WAV 22050Hz mono
    - BasicPitch: WAV → MIDI
    - Retourner objet PrettyMIDI
    """
    pass
```

### `arranger.py`
```python
def arrange_midi(midi: PrettyMIDI, level: int) -> PrettyMIDI:
    """
    - Appliquer config du niveau (transposition, quantization)
    - Ajouter accompagnement selon niveau
    - Retourner MIDI arrangé
    """
    pass
```

### `render.py`
```python
def render_video(midi: PrettyMIDI, level: int, with_audio: bool) -> tuple[Path, Path]:
    """
    - Générer frames du clavier animé
    - Optionnel: synthétiser audio avec Fluidsynth
    - Créer full.mp4 et preview_16s.mp4
    - Retourner (full_path, preview_path)
    """
    pass
```

## 🐳 Docker

```bash
# Build
docker build -t shazapiano-backend .

# Run
docker run -p 8000:8000 shazapiano-backend
```

## 📦 Déploiement

### Fly.io
```bash
fly launch
fly deploy
```

### Railway
```bash
railway init
railway up
```

## 🧪 Tests

```bash
# Installer dépendances de dev
pip install pytest pytest-asyncio httpx

# Lancer tests
pytest

# Avec coverage
pytest --cov=. --cov-report=html
```

## 📝 TODO

- [ ] Implémenter `inference.py` (BasicPitch)
- [ ] Implémenter `arranger.py` (4 niveaux)
- [ ] Implémenter `render.py` (MoviePy)
- [ ] Ajouter tests unitaires
- [ ] Ajouter rate limiting (slowapi)
- [ ] Implémenter purge automatique
- [ ] Optimiser warm-up du modèle
- [ ] Ajouter monitoring (Sentry)

## 📄 Licence

Propriétaire - ShazaPiano © 2025


