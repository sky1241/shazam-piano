#!/bin/bash
# ShazaPiano - Firebase Auto-Setup Script
# Automatise la configuration Firebase APRÈS création du projet

set -e

echo "🔥 Firebase Auto-Setup pour ShazaPiano"
echo "======================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables
PROJECT_ID="shazapiano"
ANDROID_PACKAGE="com.ludo.shazapiano"

echo -e "${YELLOW}⚠️  PRÉREQUIS MANUELS (tu dois faire d'abord) :${NC}"
echo "1. Créer projet Firebase sur console.firebase.google.com"
echo "2. Nom du projet : shazapiano"
echo "3. Télécharger google-services.json et placer dans app/android/app/"
echo ""
read -p "As-tu fait ces 3 étapes ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}❌ Fais d'abord ces étapes, puis relance ce script${NC}"
    exit 1
fi

# Check Firebase CLI
echo ""
echo -e "${CYAN}Vérification Firebase CLI...${NC}"
if ! command -v firebase &> /dev/null; then
    echo -e "${YELLOW}Firebase CLI non installé. Installation...${NC}"
    npm install -g firebase-tools
fi

echo -e "${GREEN}✓ Firebase CLI installé${NC}"

# Login
echo ""
echo -e "${CYAN}Connexion à Firebase...${NC}"
firebase login --no-localhost

# Select project
echo ""
echo -e "${CYAN}Sélection du projet...${NC}"
firebase use $PROJECT_ID || {
    echo -e "${RED}❌ Projet $PROJECT_ID non trouvé${NC}"
    echo "Crée d'abord le projet sur console.firebase.google.com"
    exit 1
}

# Initialize Firebase in Flutter project
echo ""
echo -e "${CYAN}Initialisation Firebase dans Flutter...${NC}"
cd app

# Install FlutterFire CLI
echo "Installation FlutterFire CLI..."
dart pub global activate flutterfire_cli

# Configure Firebase
echo "Configuration Firebase..."
flutterfire configure \
  --project=$PROJECT_ID \
  --platforms=android \
  --android-package-name=$ANDROID_PACKAGE \
  --out=lib/firebase_options.dart

cd ..

# Deploy Firestore Rules
echo ""
echo -e "${CYAN}Déploiement des règles Firestore...${NC}"

# Create firestore.rules
cat > firestore.rules << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users - peuvent lire/écrire leurs propres données
    match /users/{userId} {
      allow read, write: if request.auth != null 
        && request.auth.uid == userId;
    }
    
    // Generations - peuvent lire/écrire leurs propres générations
    match /generations/{genId} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }
  }
}
EOF

# Deploy rules
firebase deploy --only firestore:rules

# Create indexes
echo ""
echo -e "${CYAN}Configuration des indexes Firestore...${NC}"

cat > firestore.indexes.json << 'EOF'
{
  "indexes": [
    {
      "collectionGroup": "generations",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "userId", "order": "ASCENDING" },
        { "fieldPath": "created_at", "order": "DESCENDING" }
      ]
    }
  ]
}
EOF

firebase deploy --only firestore:indexes

# Summary
echo ""
echo "================================"
echo -e "${GREEN}✅ Configuration Firebase Terminée !${NC}"
echo "================================"
echo ""
echo -e "${GREEN}Configuré :${NC}"
echo "  ✓ FlutterFire dans app Flutter"
echo "  ✓ Règles de sécurité Firestore"
echo "  ✓ Indexes Firestore"
echo ""
echo -e "${YELLOW}À FAIRE MANUELLEMENT dans console.firebase.google.com :${NC}"
echo "  1. Authentication > Sign-in method > Anonymous > Activer"
echo "  2. (Optionnel) Analytics déjà activé si sélectionné à création"
echo ""
echo -e "${CYAN}Test :${NC}"
echo "  cd app && flutter run"
echo "  Vérifie Firebase Console > Authentication pour voir user créé"
echo ""
echo -e "${GREEN}Firebase prêt ! 🔥${NC}"

