# ShazaPiano - Firebase Auto-Setup Script (Windows PowerShell)
# Automatise la configuration Firebase APRÈS création du projet

Write-Host "🔥 Firebase Auto-Setup pour ShazaPiano" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

$PROJECT_ID = "shazapiano"
$ANDROID_PACKAGE = "com.ludo.shazapiano"

Write-Host "⚠️  PRÉREQUIS MANUELS (tu dois faire d'abord) :" -ForegroundColor Yellow
Write-Host "1. Créer projet Firebase sur console.firebase.google.com"
Write-Host "2. Nom du projet : shazapiano"
Write-Host "3. Télécharger google-services.json et placer dans app/android/app/"
Write-Host ""
$response = Read-Host "As-tu fait ces 3 étapes ? (y/N)"
if ($response -ne 'y' -and $response -ne 'Y') {
    Write-Host "❌ Fais d'abord ces étapes, puis relance ce script" -ForegroundColor Red
    exit 1
}

# Check Node.js
Write-Host ""
Write-Host "Vérification Node.js..." -ForegroundColor Cyan
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Node.js non installé" -ForegroundColor Red
    Write-Host "Installe depuis : https://nodejs.org/" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Node.js installé" -ForegroundColor Green

# Check/Install Firebase CLI
Write-Host ""
Write-Host "Vérification Firebase CLI..." -ForegroundColor Cyan
if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Write-Host "Installation Firebase CLI..." -ForegroundColor Yellow
    npm install -g firebase-tools
}
Write-Host "✓ Firebase CLI installé" -ForegroundColor Green

# Login
Write-Host ""
Write-Host "Connexion à Firebase..." -ForegroundColor Cyan
firebase login

# Select project
Write-Host ""
Write-Host "Sélection du projet..." -ForegroundColor Cyan
firebase use $PROJECT_ID
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Projet $PROJECT_ID non trouvé" -ForegroundColor Red
    Write-Host "Crée d'abord le projet sur console.firebase.google.com" -ForegroundColor Yellow
    exit 1
}

# Initialize Firebase in Flutter
Write-Host ""
Write-Host "Initialisation Firebase dans Flutter..." -ForegroundColor Cyan
Set-Location app

# Install FlutterFire CLI
Write-Host "Installation FlutterFire CLI..." -ForegroundColor Yellow
dart pub global activate flutterfire_cli

# Configure
Write-Host "Configuration Firebase..." -ForegroundColor Yellow
flutterfire configure `
  --project=$PROJECT_ID `
  --platforms=android `
  --android-package-name=$ANDROID_PACKAGE `
  --out=lib/firebase_options.dart

Set-Location ..

# Create Firestore rules
Write-Host ""
Write-Host "Création des règles Firestore..." -ForegroundColor Cyan

@"
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users
    match /users/{userId} {
      allow read, write: if request.auth != null 
        && request.auth.uid == userId;
    }
    
    // Generations
    match /generations/{genId} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }
  }
}
"@ | Out-File -FilePath firestore.rules -Encoding UTF8

# Deploy rules
Write-Host "Déploiement des règles..." -ForegroundColor Yellow
firebase deploy --only firestore:rules

# Create indexes
Write-Host ""
Write-Host "Configuration des indexes..." -ForegroundColor Cyan

@"
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
"@ | Out-File -FilePath firestore.indexes.json -Encoding UTF8

firebase deploy --only firestore:indexes

# Summary
Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "✅ Configuration Firebase Terminée !" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "Configuré :" -ForegroundColor Green
Write-Host "  ✓ FlutterFire dans app Flutter"
Write-Host "  ✓ Règles de sécurité Firestore"
Write-Host "  ✓ Indexes Firestore"
Write-Host ""
Write-Host "À FAIRE MANUELLEMENT dans console.firebase.google.com :" -ForegroundColor Yellow
Write-Host "  1. Authentication > Sign-in method > Anonymous > Activer"
Write-Host ""
Write-Host "Test :" -ForegroundColor Cyan
Write-Host "  cd app && flutter run"
Write-Host "  Vérifie Firebase Console > Authentication pour voir user créé"
Write-Host ""
Write-Host "Firebase prêt ! 🔥" -ForegroundColor Green


