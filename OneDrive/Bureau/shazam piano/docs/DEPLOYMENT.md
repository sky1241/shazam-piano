# ShazaPiano - Deployment Guide

Guide complet pour déployer ShazaPiano en production.

---

## 📋 Pré-requis

### Comptes Nécessaires
- [ ] Compte GitHub
- [ ] Compte Firebase (gratuit)
- [ ] Compte Google Play Console (25$ one-time)
- [ ] Compte Fly.io / Railway (backend hosting)

### Outils Locaux
- [ ] Git
- [ ] Flutter SDK 3.16+
- [ ] Python 3.10+
- [ ] Docker (optionnel)
- [ ] Android Studio (pour signing)

---

## 🔥 Partie 1: Firebase Setup

### 1.1 Créer Projet Firebase

```bash
# 1. Aller sur https://console.firebase.google.com/
# 2. "Ajouter un projet"
# 3. Nom: shazapiano
# 4. Activer Google Analytics
# 5. Créer le projet
```

### 1.2 Ajouter App Android

```bash
# Dans Firebase Console:
# 1. Paramètres projet > Ajouter une application > Android
# 2. Package name: com.ludo.shazapiano
# 3. App nickname: ShazaPiano
# 4. Télécharger google-services.json
# 5. Placer dans: app/android/app/google-services.json
```

### 1.3 Activer Services

**Authentication**:
```
Firebase Console > Authentication > Get Started
> Sign-in method > Anonymous > Enable
```

**Firestore**:
```
Firebase Console > Firestore Database > Create database
> Mode: Production
> Location: europe-west1
```

**Firestore Rules**:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null 
        && request.auth.uid == userId;
    }
    match /generations/{genId} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }
  }
}
```

**Analytics & Crashlytics**:
- Déjà activés automatiquement
- Aucune config supplémentaire nécessaire

---

## 🚀 Partie 2: Backend Deployment

### Option A: Fly.io (Recommandé)

```bash
# Install Fly CLI
curl -L https://fly.io/install.sh | sh

# Login
flyctl auth login

# Deploy (première fois)
cd backend
flyctl launch --no-deploy
# Sélectionner région: Paris (cdg)
# Modifier fly.toml si nécessaire

# Create volume for media storage
flyctl volumes create shazapiano_media --size 10 --region cdg

# Set secrets
flyctl secrets set DEBUG=false

# Deploy!
flyctl deploy

# Check status
flyctl status
flyctl logs
```

**URL Backend**: https://shazapiano-backend.fly.dev

### Option B: Railway

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Deploy
cd backend
railway init
railway up

# Set environment variables
railway variables set DEBUG=false
railway variables set MAX_CONCURRENT_JOBS=4

# Get URL
railway domain
```

### Option C: Docker VPS

```bash
# Sur votre VPS (Ubuntu)
ssh user@your-server.com

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Clone repo
git clone https://github.com/sky1241/shazam-piano.git
cd shazam-piano/infra

# Configure .env
cp ../backend/.env.example ../backend/.env
nano ../backend/.env  # Éditer config

# Start with Docker Compose
docker-compose up -d

# Check logs
docker-compose logs -f

# Setup nginx reverse proxy
sudo apt install nginx
sudo cp nginx.conf /etc/nginx/nginx.conf
sudo systemctl restart nginx

# SSL with Let's Encrypt
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d shazapiano.com
```

---

## 📱 Partie 3: Flutter App Deployment

### 3.1 Google Play Console Setup

```bash
# 1. Créer compte Google Play Console (25$)
# 2. Créer nouvelle application
#    - Nom: ShazaPiano
#    - Langue par défaut: Français
#    - App ou jeu: App
#    - Gratuite ou payante: Gratuite (avec IAP)
```

### 3.2 Créer Produit IAP

```bash
# Dans Play Console:
# 1. Monétisation > Produits intégrés à l'application
# 2. Créer produit géré
#    - ID: piano_all_levels_1usd
#    - Nom: Débloquer tous les niveaux
#    - Description: Accès complet aux 4 niveaux de difficulté
#    - Prix: 1.00 USD (ou équivalent local)
#    - État: Actif
```

### 3.3 Générer Keystore de Signature

```bash
cd app/android

# Générer keystore
keytool -genkey -v -keystore shazapiano-release.keystore \
  -alias shazapiano -keyalg RSA -keysize 2048 -validity 10000

# IMPORTANT: Sauvegarder le mot de passe !

# Créer key.properties
cat > app/key.properties << EOF
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=shazapiano
storeFile=../shazapiano-release.keystore
EOF

# IMPORTANT: Ne JAMAIS commit key.properties (déjà dans .gitignore)
```

### 3.4 Configuration Backend URL

```bash
cd app

# Modifier lib/core/config/app_config.dart
# Remplacer l'URL backend prod par votre URL réelle:
# backendBaseUrl: 'https://shazapiano-backend.fly.dev'
```

### 3.5 Build Release

```bash
cd app

# Get dependencies
flutter pub get

# Generate code
flutter pub run build_runner build --delete-conflicting-outputs

# Build App Bundle (pour Play Store)
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

### 3.6 Upload sur Play Console

```bash
# 1. Play Console > Votre app > Version > Production
# 2. Créer nouvelle version
# 3. Upload app-release.aab
# 4. Compléter:
#    - Titre de version: "Version initiale 1.0.0"
#    - Notes de version (FR):
#      "🎹 Première version de ShazaPiano !
#       - Enregistrement piano
#       - 4 niveaux de difficulté
#       - Previews gratuits 16s
#       - Achat 1$ pour tout débloquer"
# 5. Enregistrer > Vérifier > Publier en test interne
```

### 3.7 Test Interne

```bash
# 1. Play Console > Test interne > Créer nouvelle version
# 2. Ajouter testeurs (emails)
# 3. Les testeurs reçoivent lien pour installer
# 4. Tester toutes les fonctionnalités
# 5. Tester IAP en sandbox
```

---

## 🧪 Partie 4: Testing Production

### Backend Health Check

```bash
# Test endpoint health
curl https://shazapiano-backend.fly.dev/health

# Should return:
# {"status":"healthy","timestamp":"...","version":"1.0.0"}
```

### Test Upload

```bash
# Test avec un fichier audio
curl -X POST https://shazapiano-backend.fly.dev/process \
  -F "audio=@test.m4a" \
  -F "with_audio=false" \
  -F "levels=1,2,3,4"

# Devrait retourner job_id et URLs des vidéos
```

### Flutter App Testing

**Test Interne (5-10 testeurs)**:
- [ ] Recording audio fonctionne
- [ ] Upload vers backend réussi
- [ ] 4 vidéos générées correctement
- [ ] Previews 16s playent
- [ ] IAP flow complet (achat test)
- [ ] Restore purchases fonctionne
- [ ] Practice mode détecte les notes
- [ ] Pas de crash

**Test Fermé (50-100 testeurs)**:
- [ ] Sur plusieurs devices (Samsung, Pixel, etc.)
- [ ] Différentes versions Android (23-34)
- [ ] Différents réseaux (WiFi, 4G, 5G)
- [ ] Feedback utilisateurs collecté
- [ ] Bugs critiques fixés

---

## 🔒 Partie 5: Sécurité Production

### Backend

```bash
# Dans backend/.env (production):
DEBUG=false
MAX_UPLOAD_SIZE_MB=10
FFMPEG_TIMEOUT=15
BASICPITCH_TIMEOUT=10
RENDER_TIMEOUT=20

# Ajouter rate limiting
pip install slowapi
# Voir backend/app.py pour implementation
```

### Flutter

```bash
# Build avec obfuscation
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/app/outputs/symbols
```

### Firestore Security

- ✅ Rules configurées (users own data only)
- ✅ Indexes créés si nécessaire
- ✅ Backup activé

### Monitoring

```bash
# Backend: Ajouter Sentry
pip install sentry-sdk[fastapi]

# Dans app.py:
import sentry_sdk
sentry_sdk.init(dsn="YOUR_SENTRY_DSN")
```

---

## 📊 Partie 6: Monitoring & Analytics

### Firebase Analytics

```dart
// Track key events
FirebaseService.logEvent('video_generated', {
  'level': level,
  'duration': duration,
});

FirebaseService.logEvent('purchase_completed', {
  'product_id': AppConstants.iapProductId,
  'price': 1.00,
});
```

### Backend Logs

```bash
# Fly.io logs
flyctl logs -a shazapiano-backend

# Railway logs
railway logs

# Docker logs
docker-compose logs -f backend
```

### Crashlytics

```dart
// Crashes auto-tracked
// Manually log errors:
FirebaseCrashlytics.instance.recordError(error, stackTrace);
```

---

## 🔄 Partie 7: CI/CD Automation

### GitHub Secrets

```bash
# Dans GitHub repo > Settings > Secrets

# Android Signing
ANDROID_KEYSTORE_BASE64  # Base64 du keystore
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD

# Deployment
FLY_API_TOKEN  # Pour auto-deploy Fly.io
RAILWAY_TOKEN  # Pour auto-deploy Railway
```

### Auto-Deploy Workflow

```yaml
# .github/workflows/deploy.yml (déjà créé)
# Se déclenche sur push vers main
# - Run tests
# - Build Docker
# - Deploy to Fly.io
# - Build Flutter AAB
# - Upload artifact
```

---

## 📈 Partie 8: Scaling & Optimizations

### Backend

**Optimisations**:
```python
# Warm-up BasicPitch au démarrage
@app.on_event("startup")
async def warmup():
    from basic_pitch import ICASSP_2022_MODEL_PATH
    # Load model in memory
```

**Scaling**:
```bash
# Fly.io: Scale machines
flyctl scale count 2 --region cdg

# Fly.io: Upgrade resources
flyctl scale vm shared-cpu-2x --memory 2048
```

**Caching**:
- Redis pour cache résultats
- CloudFlare pour CDN media files

### Database

**Firestore Indexes**:
```javascript
// Index pour queries rapides
users: [userId]
generations: [userId, created_at DESC]
```

---

## 📱 Partie 9: Play Store Release

### Pre-launch Checklist

- [ ] Tests internes passés (10+ testeurs)
- [ ] Tests fermés passés (50+ testeurs)
- [ ] Tous les bugs critiques fixés
- [ ] Screenshots professionnels (8 required)
- [ ] Vidéo demo (optionnel mais recommandé)
- [ ] Description captivante
- [ ] Privacy policy published
- [ ] Content rating completed
- [ ] Pricing & distribution set
- [ ] IAP produit actif

### Store Listing

**Titre court**: ShazaPiano  
**Description courte**:
```
Transforme ton piano en 4 vidéos pédagogiques animées !
Enregistre 8s → Obtiens 4 niveaux de difficulté instantanément.
```

**Description complète**:
```
🎹 ShazaPiano - Ton Prof de Piano IA

Enregistre quelques secondes de piano et obtiens instantanément 
4 vidéos de clavier animé adaptées à ton niveau !

✨ FONCTIONNALITÉS
• Enregistrement facile (8 secondes suffisent)
• 4 niveaux générés automatiquement
• Previews gratuits de 16 secondes
• Mode pratique avec détection des notes
• Interface élégante et intuitive

🎯 4 NIVEAUX DE DIFFICULTÉ
1. Hyper Facile - Mélodie simple pour débutants
2. Facile - Avec accompagnement basse
3. Moyen - Accords et harmonisation
4. Pro - Arrangement complet

💰 PRIX
Previews gratuits pour tous les niveaux !
Débloquez tout pour seulement 1$ (achat unique, à vie)

🎵 MODE PRATIQUE
Détection intelligente de tes notes en temps réel
Feedback visuel immédiat (vert/orange/rouge)
Progresse à ton rythme !

Parfait pour :
• Débutants voulant apprendre
• Pianistes cherchant nouvelles idées
• Profs créant du contenu pédagogique

Télécharge maintenant et transforme ton piano ! 🎹
```

**Screenshots**:
1. Home screen (bouton record)
2. Grille 4 vidéos
3. Video player
4. Practice mode
5. Paywall modal
6. About screen
7. Settings
8. Success state

### Release Notes Template

```
Version 1.0.0 (Build 1)
🎹 Première version publique !

✨ Nouveautés:
• Enregistrement audio piano
• Génération automatique 4 niveaux
• Previews gratuits 16 secondes
• Achat 1$ pour débloquer tout
• Mode pratique avec détection notes

🐛 Corrections:
• Stabilité améliorée
• Performance optimisée

Merci de nous aider à améliorer ShazaPiano ! 
Feedback: ludo@shazapiano.com
```

---

## 🌍 Partie 10: DNS & Custom Domain

### Setup DNS (Optionnel)

```bash
# Acheter domaine: shazapiano.com (Namecheap, etc.)

# DNS Records:
A     @           <FLY_IO_IP>
A     www         <FLY_IO_IP>
CNAME api         shazapiano-backend.fly.dev

# Fly.io custom domain
flyctl certs create shazapiano.com
flyctl certs create www.shazapiano.com
```

---

## 🔍 Partie 11: Monitoring Post-Launch

### Métriques à Surveiller

**Backend**:
- Requests per minute
- Average response time
- Error rate
- CPU/Memory usage
- Storage usage

**App**:
- Crash-free users %
- Daily Active Users (DAU)
- Conversion rate (preview → purchase)
- Average session duration
- Feature adoption (Practice mode)

### Alertes

```bash
# Fly.io metrics
flyctl dashboard

# Firebase Analytics
# Console > Analytics > Dashboard

# Crashlytics
# Console > Crashlytics > Issues
```

---

## 📦 Partie 12: Updates & Maintenance

### Update Backend

```bash
# 1. Update code
git pull origin main

# 2. Run tests
cd backend && pytest

# 3. Deploy
flyctl deploy

# 4. Monitor
flyctl logs
```

### Update Flutter

```bash
# 1. Update code
git pull origin main

# 2. Increment version
# Edit app/pubspec.yaml: version: 1.0.1+2

# 3. Build
cd app
flutter build appbundle --release

# 4. Upload to Play Console
# Play Console > Production > Create new release

# 5. Rollout
# Staged rollout: 10% → 50% → 100%
```

---

## ✅ Post-Deployment Checklist

### Immediately After Deploy

- [ ] Backend health check passes
- [ ] Test upload fonctionnel
- [ ] Test génération 4 vidéos
- [ ] Test download vidéos
- [ ] App store listing correct
- [ ] IAP produit visible
- [ ] Test achat en sandbox
- [ ] Firebase connected
- [ ] Analytics tracking
- [ ] Crashlytics reporting

### First Week

- [ ] Monitor crash rate (< 1%)
- [ ] Check error logs daily
- [ ] Respond to user feedback
- [ ] Fix critical bugs quickly
- [ ] Analyze user behavior
- [ ] Optimize based on data

### First Month

- [ ] Collect user reviews
- [ ] Analyze conversion funnel
- [ ] A/B test paywall messaging
- [ ] Optimize video generation time
- [ ] Add most-requested features
- [ ] Plan v1.1 release

---

## 🚨 Rollback Plan

### Backend Rollback

```bash
# Fly.io
flyctl releases
flyctl releases rollback <VERSION>

# Railway
railway rollback
```

### Flutter Rollback

```bash
# Play Console:
# 1. Halt current rollout
# 2. Publish previous version
# 3. Notify users
```

---

## 📞 Support

Problèmes de déploiement ?

1. Check logs first
2. Consult documentation
3. Search GitHub issues
4. Contact: ludo@shazapiano.com

---

**🎹 Bon déploiement ! 🚀**

