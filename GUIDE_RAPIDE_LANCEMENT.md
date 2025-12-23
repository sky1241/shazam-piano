# 🚀 Guide Rapide - Lancer ShazaPiano Complètement

## ⚡ TL;DR

```bash
# Terminal 1 - Backend
cd backend
pip install -r requirements.txt
python app.py

# Terminal 2 - Trouver votre IP
ipconfig  # Windows
# Chercher "IPv4 Address" (ex: 192.168.1.25)

# Dans l'app Flutter, modifier:
# app/lib/core/config/app_config.dart
# backendBaseUrl: 'http://192.168.1.25:8000'

# Relancer l'app
cd app
flutter run -d FMMFSOOBXO8T5D75
```

---

## 📋 Étape par Étape

### 1. Installer Python Dependencies (Une Seule Fois)

```bash
cd "C:\Users\ludov\OneDrive\Bureau\shazam piano\backend"

# Créer environnement virtuel
python -m venv venv

# Activer
venv\Scripts\activate

# Installer packages
pip install -r requirements.txt

# Cela installe:
# - FastAPI
# - BasicPitch (Spotify ML model)
# - PrettyMIDI
# - MoviePy + FFmpeg
# - Pillow
# - loguru
```

### 2. Trouver Votre IP Locale

```bash
ipconfig
```

Cherchez:
```
Carte réseau sans fil Wi-Fi:
   Adresse IPv4. . . . . . . . . . . . . .: 192.168.1.25
```

Notez ce numéro (ex: 192.168.1.25)

### 3. Configurer l'App

Ouvrez `app/lib/core/config/app_config.dart`:

```dart
/// Development configuration
factory AppConfig.dev() {
  return const AppConfig(
    backendBaseUrl: 'http://192.168.1.25:8000',  // ← CHANGEZ ICI
    debugMode: true,
    environment: 'dev',
  );
}
```

### 4. Lancer le Backend

```bash
cd "C:\Users\ludov\OneDrive\Bureau\shazam piano\backend"
python app.py
```

Vous devriez voir:
```
INFO:     Started server process
INFO:     Waiting for application startup.
🚀 ShazaPiano Backend starting...
📁 Media directory: C:\...\backend\media
🎵 Ready to process on http://0.0.0.0:8000
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
```

**⚠️ Laissez ce terminal ouvert !**

### 5. Tester le Backend

Dans un autre terminal:
```bash
curl http://localhost:8000/health
```

Devrait retourner:
```json
{
  "status": "healthy",
  "timestamp": "2025-11-27T...",
  "version": "1.0.0"
}
```

### 6. Relancer l'App Flutter

```bash
cd "C:\Users\ludov\OneDrive\Bureau\shazam piano\app"
flutter run -d FMMFSOOBXO8T5D75
```

Ou si déjà installée, **hot reload** (appuyez sur `R` dans le terminal Flutter)

### 7. Tester le Flux Complet

1. **Ouvrez l'app sur votre téléphone**
2. **Tap sur le bouton Record** (gros bouton turquoise)
3. **Jouez du piano pendant 8 secondes** (ou laissez auto-stop)
4. **Attendez 10-30 secondes** (backend traite)
5. **Voyez les 4 vidéos !** 🎉

---

## 🐛 Dépannage

### Erreur: Connection Timeout
**Cause**: Backend pas lancé ou mauvaise IP

**Solutions**:
1. Vérifier backend lancé: `curl http://localhost:8000/health`
2. Vérifier IP correcte dans `app_config.dart`
3. Vérifier firewall Windows ne bloque pas le port 8000
4. Essayer: `http://127.0.0.1:8000` au lieu de l'IP

### Erreur: No Melody Detected
**Cause**: Audio trop court, pas de notes détectées, bruit

**Solutions**:
1. Enregistrer au moins 8 secondes
2. Jouer des notes claires au piano
3. Éviter bruit de fond
4. Être proche du microphone

### Backend Crash
**Cause**: Dépendances manquantes, FFmpeg absent

**Solutions**:
```bash
# Vérifier FFmpeg installé
ffmpeg -version

# Si absent, installer:
# Windows: Télécharger depuis ffmpeg.org
# ou: choco install ffmpeg

# Vérifier BasicPitch
pip list | findstr basic-pitch
```

### App Freeze
**Cause**: Backend prend trop de temps

**Solutions**:
1. Vérifier logs backend
2. Augmenter timeouts dans `backend/config.py`
3. Essayer fichier audio plus court

---

## 📊 Ce Que Vous Verrez

### Logs Backend (Terminal)
```
INFO: Processing audio: recording_123456.m4a
INFO: Step 1: Extracting MIDI from audio...
INFO: Running BasicPitch MIDI extraction...
SUCCESS: Extracted 45 notes
SUCCESS: MIDI extracted: 45 notes, Key=C, Tempo=120
INFO: Step 2.1: Processing Level 1 - Hyper Facile
INFO: Arranging Level 1: Hyper Facile
INFO: Rendering video for Level 1...
SUCCESS: ✅ Level 1 completed!
... (repeat for L2, L3, L4)
🎉 Job completed! 4/4 levels successful
```

### Dans l'App
1. **Pendant enregistrement**: Bouton pulse, timer visible
2. **Après stop**: "Génération en cours..."
3. **Chips L1-L4**: Passent de "queued" → "processing" → "completed"
4. **Navigation auto**: Vers page Previews
5. **Grille 2×2**: 4 vidéos avec preview 16s

---

## ✅ Checklist Finale

- [ ] Backend installé (pip install -r requirements.txt)
- [ ] FFmpeg installé (ffmpeg -version)
- [ ] Backend lancé (python app.py)
- [ ] IP configurée dans app_config.dart
- [ ] App relancée (flutter run)
- [ ] Test: Enregistrer 8s de piano
- [ ] Voir les 4 vidéos générées !

---

**Tout est prêt ! Il suffit de lancer le backend.** 🎹🚀

