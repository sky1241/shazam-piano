# 🚀 ShazaPiano - Quick Start Guide

**Objectif** : Lancer ShazaPiano en 15 minutes chrono ! ⏱️

---

## ⚡ Option 1 : Windows (Rapide)

### 1. Prérequis (5 min)

```powershell
# Vérifier Python
python --version  # Doit être 3.10+

# Vérifier Flutter
flutter --version  # Doit être 3.16+

# Installer FFmpeg
winget install FFmpeg
```

### 2. Setup (5 min)

```powershell
# Clone repo (déjà fait ✅)
cd <repo-root>

# Run setup automatique
.\scripts\setup.ps1
```

### 3. Lancer Backend (2 min)

```powershell
# Terminal 1
.\scripts\run-backend.ps1

# Devrait afficher:
# 🚀 Starting ShazaPiano Backend...
# Uvicorn running on http://0.0.0.0:8000
```

**Test** : Ouvrir http://localhost:8000/docs

### 4. Lancer Flutter (3 min)

```powershell
# Terminal 2 (nouveau)
cd app
flutter run

# Choisir device (emulator ou phone USB)
```

**Done! 🎉** L'app devrait se lancer avec le bouton central !

---

## ⚡ Option 2 : Linux/Mac (Rapide)

### 1. Installation Auto (10 min)

```bash
# Tout en une commande
chmod +x scripts/setup.sh
./scripts/setup.sh
```

### 2. Lancer (2 min)

```bash
# Terminal 1 : Backend
make backend-run
# Ou: cd backend && source .venv/bin/activate && uvicorn app:app --reload

# Terminal 2 : Flutter
make flutter-run
# Ou: cd app && flutter run
```

---

## ⚡ Option 3 : Docker (Ultra Rapide)

```bash
# 1 commande pour tout lancer
cd infra
docker-compose up --build

# Backend accessible sur: http://localhost:8000
```

---

## 🧪 Tester l'API

### Via Browser
```
http://localhost:8000/docs
```

### Via curl
```bash
curl http://localhost:8000/health

# Should return:
# {"status":"healthy","timestamp":"...","version":"1.0.0"}
```

---

## 📱 Tester Flutter App

### 1. Avec Emulator Android

```bash
# Créer émulateur (Android Studio)
# Device Manager > Create Virtual Device > Pixel 5 > Android 13

# Lancer émulateur
emulator -avd Pixel_5_API_33

# Dans nouveau terminal
cd app
flutter run
```

### 2. Avec Device Réel (USB)

```bash
# Activer USB Debugging sur phone
# Settings > About > Tap "Build number" 7x
# Developer options > USB debugging

# Connecter USB
# Autoriser debugging

cd app
flutter run
```

### 3. Avec Simulateur iOS (Mac uniquement)

```bash
open -a Simulator

cd app
flutter run
```

---

## 🎯 Test Rapide du Flow Complet

### 1. Record Audio (Simulé)

Dans l'app :
1. Tap gros bouton central
2. Attendre animation (ou tap stop)
3. → Navigation vers Previews (simulé)

### 2. Upload Réel (Avec Backend)

Créer fichier audio test :
```bash
# Enregistrer 5s de piano avec micro
# Ou télécharger sample : https://sampleswap.org/
```

Upload manuel:
```bash
curl -X POST http://localhost:8000/process \
  -F "audio=@test.m4a" \
  -F "levels=1"

# Devrait retourner job_id et URLs
```

### 3. Vérifier Résultat

```bash
# Ouvrir vidéo générée dans browser
http://localhost:8000/media/out/<job_id>_L1_preview.mp4
```

---

## 🔥 Setup Firebase (Optionnel - 10 min)

Si tu veux tester Firebase features :

### 1. Créer Projet
```
1. https://console.firebase.google.com/
2. "Add project" → shazapiano
3. Enable Analytics
4. Create project
```

### 2. Add Android App
```
1. Add app → Android
2. Package: com.ludo.shazapiano
3. Download google-services.json
4. Place in: app/android/app/google-services.json
```

### 3. Enable Services
```
1. Authentication → Anonymous → Enable
2. Firestore → Create database → Production mode
3. Done!
```

### 4. Test
```bash
cd app
flutter run

# App devrait auto-sign-in anonymous
# Check Firebase Console > Authentication
# Tu devrais voir 1 user créé
```

---

## 🐛 Troubleshooting Rapide

### Backend ne démarre pas

```bash
# Vérifier Python
python --version

# Réinstaller deps
cd backend
pip install -r requirements.txt

# Vérifier FFmpeg
ffmpeg -version
```

### Flutter ne compile pas

```bash
# Clean
flutter clean
flutter pub get

# Rebuild
flutter run
```

### Permission errors (Linux/Mac)

```bash
# Rendre scripts exécutables
chmod +x scripts/*.sh
```

---

## 📚 Documentation Complète

Besoin de plus de détails ? Consulte :

- **Architecture** : `docs/ARCHITECTURE.md`
- **Setup Firebase** : `docs/SETUP_FIREBASE.md`
- **Deployment** : `docs/DEPLOYMENT.md`
- **API** : `docs/API_REFERENCE.md`
- **FAQ** : `docs/FAQ.md`
- **Troubleshooting** : `docs/TROUBLESHOOTING.md`

---

## 🎯 Commandes Utiles

```bash
# Avec Makefile (Linux/Mac)
make help          # Liste toutes les commandes
make setup         # Setup auto
make backend-run   # Run backend
make flutter-run   # Run Flutter
make test          # Run tous les tests
make clean         # Clean builds

# Sans Makefile (Windows)
.\scripts\setup.ps1       # Setup
.\scripts\run-backend.ps1 # Run backend
cd app && flutter run     # Run Flutter
```

---

## ⏱️ Timeline

```
00:00 - Clone repo (déjà fait ✅)
00:05 - Run setup script
00:10 - Start backend
00:12 - Start Flutter
00:15 - App running! 🎉
```

---

## 🎊 C'est Tout !

**Backend** → http://localhost:8000  
**App** → Running on emulator/device  
**Docs** → http://localhost:8000/docs

**Tu es prêt à développer ! 🎹**

---

## 🆘 Besoin d'Aide ?

**Quick help** : `docs/TROUBLESHOOTING.md`  
**Email** : support@shazapiano.com

---

**Happy coding! 🎹✨**

