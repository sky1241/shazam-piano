# Firebase Setup Guide

## 🔥 Configuration Firebase pour ShazaPiano

### Étape 1: Créer un Projet Firebase

1. Aller sur [Firebase Console](https://console.firebase.google.com/)
2. Cliquer sur "Ajouter un projet"
3. Nom du projet: **shazapiano**
4. Activer Google Analytics (optionnel mais recommandé)
5. Créer le projet

---

### Étape 2: Ajouter l'Application Android

1. Dans Firebase Console → Paramètres du projet
2. Ajouter une application → Android
3. **Package name**: `com.ludo.shazapiano`
4. **App nickname**: ShazaPiano
5. Télécharger `google-services.json`
6. Placer dans `app/android/app/google-services.json`

---

### Étape 3: Configurer les Services

#### Authentication
1. Firebase Console → Authentication → Get Started
2. Activer **Anonymous** sign-in
3. (Optionnel) Activer Google Sign-In

#### Firestore Database
1. Firebase Console → Firestore Database → Create database
2. Mode: **Production** (on ajoutera les rules après)
3. Région: **europe-west1** (ou plus proche)

#### Firestore Rules
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // User documents - users can only read/write their own
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Generations - users can read/write their own generations
    match /generations/{generationId} {
      allow read, write: if request.auth != null 
        && resource.data.userId == request.auth.uid;
    }
  }
}
```

#### Analytics
1. Firebase Console → Analytics
2. Activé automatiquement si sélectionné à la création

#### Crashlytics
1. Firebase Console → Crashlytics → Get Started
2. Suivre les instructions d'installation
3. Déjà configuré dans le code

---

### Étape 4: Fichiers à Modifier

#### `android/app/build.gradle`
Ajouter en bas du fichier:
```gradle
apply plugin: 'com.google.gms.google-services'
```

#### `android/build.gradle`
Ajouter dans dependencies:
```gradle
classpath 'com.google.gms:google-services:4.4.0'
```

---

### Étape 5: Configuration IAP (Google Play)

#### Dans Google Play Console:
1. Créer produit In-App
2. **Product ID**: `piano_all_levels_1usd`
3. **Type**: Non-consumable (achat unique)
4. **Prix**: 1.00 USD
5. **Titre**: "Débloquer tous les niveaux"
6. **Description**: "Accès complet aux 4 niveaux de difficulté à vie"

#### Tester IAP:
1. Play Console → Setup → License testing
2. Ajouter comptes test Gmail
3. Installer version signée (pas debug)
4. Les comptes test peuvent acheter gratuitement

---

### Étape 6: Initialiser dans l'App

Le code est déjà prêt dans `main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await FirebaseService.initialize();
  
  runApp(const ShazaPianoApp());
}
```

---

## 📊 Structure Firestore

### Collection: `users`
```json
{
  "userId": {
    "created_at": Timestamp,
    "unlocked": false,
    "unlocked_at": Timestamp (optional),
    "total_generations": 0,
    "last_generation": Timestamp (optional)
  }
}
```

### Collection: `generations`
```json
{
  "generationId": {
    "userId": "string",
    "created_at": Timestamp,
    "job_id": "string",
    "key": "C",
    "tempo": 120,
    "duration": 8.5,
    "levels": [1, 2, 3, 4],
    "status": "success"
  }
}
```

---

## 🔐 Sécurité

### API Keys
- Les API keys Firebase sont **publiques** (ok pour mobile apps)
- La sécurité vient des **Firestore Rules**
- **NE PAS** mettre les keys dans git (déjà dans .gitignore)

### Backend API
Si tu veux ajouter une couche de sécurité:
1. Utiliser Firebase Admin SDK dans le backend
2. Vérifier les tokens Firebase côté serveur
3. Valider les entitlements IAP côté serveur

---

## 🧪 Testing

### Test Firebase localement:
```bash
flutter run --dart-define=BACKEND_BASE=http://10.0.2.2:8000
```

### Vérifier connexion Firebase:
1. Lancer l'app
2. Aller dans Firebase Console → Authentication
3. Tu devrais voir un utilisateur anonyme créé

### Test Analytics:
```bash
# Dans l'app, faire des actions
# Attendre 24h pour voir dans Analytics Dashboard
```

---

## 🚨 Troubleshooting

### Error: google-services.json not found
**Solution**: Télécharger depuis Firebase Console et placer dans `app/android/app/`

### Error: Default FirebaseApp not initialized
**Solution**: Vérifier que `google-services.json` est bien configuré

### IAP Error: Product not found
**Solution**: 
- Vérifier Product ID dans Play Console
- Attendre quelques heures après création produit
- Tester avec compte license testing

---

## ✅ Checklist Finale

- [ ] Projet Firebase créé
- [ ] google-services.json téléchargé et placé
- [ ] Authentication (Anonymous) activée
- [ ] Firestore Database créée
- [ ] Firestore Rules configurées
- [ ] Analytics activé
- [ ] Crashlytics configuré
- [ ] IAP produit créé dans Play Console
- [ ] Comptes test IAP ajoutés
- [ ] App teste et connexion Firebase OK

---

**🔥 Firebase est maintenant prêt pour ShazaPiano !**

