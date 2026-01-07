# 🚀 Quick Dev Workflow — Itérer Vite sur ShazaPiano

Guide pour développer efficacement en 3 modes selon la complexité de la change.

---

## 📊 Temps par Mode

| Mode | Temps | Cas d'usage | Fréquence |
|------|-------|-----------|-----------|
| **⚡ Rapide** | 0–3s | UI, logique Dart, providers Riverpod | 90% |
| **⏱️ Normal** | 30–60s | Changement pubspec, nouvelles dépendances | 9% |
| **🔧 Lourd** | 5–15 min | Build Android, gradle/libs natives | 1% |

---

## ⚡ Mode Rapide (Hot Reload) — 90% du Temps

### Workflow Standard

```powershell
# 1. Terminal 1: Démarrer l'app (une seule fois)
cd app
flutter run -v

# 2. Terminal 2: Éditer et sauver (Ctrl+S)
# → Hot reload auto ou appuie sur 'r' dans le terminal flutter
# Voir la change en <1s sans recompiler Android

# 3. Itérer librement
# Changements supportés:
#  ✅ UI (widgets, layout, styles)
#  ✅ Logique Dart (providers, contrôleurs)
#  ✅ Riverpod (providers, état)
#  ✅ Assets non-binaires (images, strings)
#  ✅ Fonctions/méthodes (y compris build())

# 4. Relancer hot reload si besoin
#  'r'  = hot reload
#  'R'  = hot restart (redémarre Dart, garde Android)
```

### ✅ Avant de Commencer

```bash
# Vérif une seule fois par session
flutter doctor
flutter pub get
flutter clean  # SEULEMENT si vraiment buggé, sinon évite!
```

### 🎯 Changements Hot Reload-friendly

- **Riverpod StateNotifier**: Change logique → hot reload OK
- **UI**: Modifie widgets, layout, couleurs → hot reload OK
- **Strings/Assets**: Ajoute ressources → hot reload OK
- **Méthodes existantes**: Modifie corps → hot reload OK

### ⚠️ Hot Reload ne Supporte PAS

```dart
// ❌ Ces changements nécessitent hot restart ('R'):
- Ajouter/retirer classe, énumération, extension
- Ajouter/retirer static final
- Changer constructeur (signature)
- Changer type de variable au niveau classe
```

---

## ⏱️ Mode Normal (Pubspec/Dépendances) — 9% du Temps

### Quand: Ajouter/Supprimer Packages ou Changer Versions

```powershell
# 1. Éditer pubspec.yaml
# Exemple: ajouter package
flutter pub add http

# 2. Récupérer dépendances
flutter pub get

# 3. Si le package a du code généré
flutter pub run build_runner build --delete-conflicting-outputs

# 4. Hot restart ou redémarrer l'app
# 'R' dans terminal flutter, ou Ctrl+C puis 'flutter run'

# ⏱️ Temps total: 30–60s selon le package
```

### 🔍 Cas Courants

```yaml
# Retrofit + build_runner
dependencies:
  retrofit: ^4.0.0
  retrofit_generator: ^4.0.0
dev_dependencies:
  build_runner: ^2.4.0

# → flutter pub get + flutter pub run build_runner build
# Génère lib/data/datasources/remote/*.g.dart

# Riverpod + build_runner
dev_dependencies:
  riverpod_generator: ^2.0.0
  build_runner: ^2.4.0

# → flutter pub get + flutter pub run build_runner build
```

---

## 🔧 Mode Lourd (Android/Gradle) — 1% du Temps

### Quand: Build natif, JAR/AAR, NDK, dépendances natives

**Ces builds sont lents localement (5–15 min).** Solution: **GitHub Actions bâtit pendant que tu codes.**

### Workflow Lourd

```powershell
# 1. Éditer code/pubspec/gradle
# 2. Test local si petit changement (5 min)
flutter run --release

# 3. Push vers GitHub
git add .
git commit -m "feat: android native change"
git push

# 4. GitHub Actions bâtit en ~11 min en parallèle
# Vérifier: Actions tab → workflow "Build Android"

# 5. Pendant ce temps: Développe autre feature en mode rapide
# (autre branche ou fichier qui touche pas à Android)

# 6. Revenir au résultat build à la fin
# Si succès → merge et release
# Si erreur → fix locale et repush
```

### ⚙️ Trucs Gradle pour Accélérer

```gradle
// android/app/build.gradle.kts
android {
    // Cache Gradle
    buildCache {
        local { isEnabled = true }
    }
    
    // Compile options pour itération rapide
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    
    // Skip linker warnings
    packagingOptions {
        exclude 'META-INF/proguard/androidx-*.pro'
    }
}

// ~/.gradle/gradle.properties (ou local au projet)
org.gradle.parallel=true
org.gradle.workers.max=8  // Paralléliser sur 8 cores
org.gradle.caching=true   // Cache des builds
```

### 🚫 Éviter Absolument

```powershell
# ❌ LENT: flutter clean + flutter run
# → recompile TOUT, 5–15 min

# ❌ LENT: flutter run --release sans raison
# → build optimisé, mais x3 plus lent

# ✅ RAPIDE: flutter run (debug, incrmental)
# ✅ RAPIDE: 'r' hot reload, 'R' hot restart
# ✅ RAPIDE: Laisser Gradle cacher entre runs
```

---

## 🐛 Pièges Courants et Solutions

### Piège 1: "Hot reload ne fait rien"

```bash
# Solution 1: Hot restart
# Dans terminal flutter: appuie sur 'R'

# Solution 2: Redémarrer l'app
Ctrl+C
flutter run

# Solution 3: Vérifier le changement est hot-reload-compatible
# (voir liste au-dessus)

# Solution 4 (dernière ressort): Clean (rare!)
flutter clean
flutter run
```

### Piège 2: "Gradle est bloqué / Build interminable"

```powershell
# Tuer gradle et processus Java
Get-Process -Name "gradle*","java*","flutter*" -ErrorAction SilentlyContinue | Stop-Process -Force

# Attendre 3s et relancer
Start-Sleep 3
flutter run
```

### Piège 3: "build_runner ne génère rien"

```bash
# Régenérer explicitement
flutter pub run build_runner build --delete-conflicting-outputs

# Vérifier les fichiers .g.dart existent
ls lib/data/datasources/remote/*.g.dart
```

### Piège 4: "Android linker errors / symbol not found"

```bash
# Solution: Clean gradle cache + rebuild
rm -r ~/.gradle/caches/  # ou sur Windows: Remove-Item C:\Users\<user>\.gradle\caches -Recurse

# Rebuild
flutter run --release
```

### Piège 5: "Changement pubspec, mais app crashe"

```bash
# Vérifier pubspec.yaml syntax
flutter pub get  # Écho les erreurs

# Relancer
flutter pub get
flutter run
```

---

## 🎯 Recette Typique: Ajouter une Feature Riverpod

### Scénario: Ajouter un provider pour "lecteur audio avec volume"

```powershell
# Terminal 1: flutter run (déjà lancé)

# Terminal 2:
cd app
# 1. Ajouter provider (3 sec de hot reload)
#    Crée: lib/presentation/providers/audio_volume_provider.dart
#    Édite: lib/presentation/providers/providers.dart (import)
# Appuie 'r' → hot reload → ✅ <1s

# 2. Modifier UI pour utiliser le provider (3 sec)
#    Édite: lib/presentation/screens/player_screen.dart
# Appuie 'r' → hot reload → ✅ <1s

# 3. Test sur app → fonctionnel en ~6 sec total

# 4. Si UI nécessite changement Riverpod complexe
#    Appuie 'R' → hot restart → ✅ 2–3s

# Total feature complète: 5–10 minutes
```

---

## 📱 Backend Changes (Python) — Parallèle à Flutter

```powershell
# Terminal 3 (séparé)
cd backend

# Éditer Python
# Code → test → push (5–10 min)

# Pendant ce temps: Flutter itère en mode rapide

# Workflow:
# 1. Push Python changes vers GitHub
# 2. API en CI/CD bâtit + teste (2–3 min)
# 3. Branche Flask/FastAPI redéploie sur Fly.io (1 min)
# 4. App Flutter consomme API mise à jour

# Total: Faire feature complète (Flutter + Backend) en 20–30 min
```

---

## ✅ Checklist Avant de Pushcer

```
☐ Hot reload/restart fonctionne (pas de erreurs console)
☐ Tests locaux passent
☐ Lint passe:   flutter analyze
☐ Format OK:    dart format .
☐ Pas de logs d'erreur
☐ Testable manually en <5 étapes
☐ Git status clean: git status
```

---

## 🚀 Stats Temps

**Avant workflow optimisé:**
- Feature simple (UI): 10–15 min (clean + build + test)
- Feature avec pubspec: 20–30 min (clean + pub + build)
- Bug Android: 30+ min

**Avec workflow optimisé:**
- Feature simple (UI): 3–5 min
- Feature avec pubspec: 5–10 min
- Bug Android: Développe autre feature en parallèle, test en CI

**Gain:** 2–6x plus rapide 🎯

---

## 🔗 Commandes Rapides

```powershell
# Starter
cd app && flutter run -v

# Hot reload (dans terminal flutter)
r

# Hot restart
R

# Analyse + format
flutter analyze
dart format .

# Pub commands
flutter pub get
flutter pub add <package>
flutter pub remove <package>
flutter pub run build_runner build

# Tuer les processus bloqués
Get-Process -Name "gradle*","java*","flutter*" -ErrorAction SilentlyContinue | Stop-Process -Force

# Release build
flutter run --release
```

---

**TL;DR: Hot reload (mode rapide) 90% du temps, pubspec normal 9%, gradle lourd 1% (via CI). Développe 5–10x plus vite.** 🎯

# → Attends 11-15 min pour GitHub Actions (pas blocking)
```

**CI/CD = source de vérité.** Build GitHub Actions réussit = code bon. Ignore local warnings si GitHub Actions passe.

---

## 🧭 Structure Projet — Où Éditer Quoi

| Besoin | Fichier | Temps Recompile |
|--------|---------|-----------------|
| UI Layout | `lib/presentation/` | 0s (hot reload) |
| State Riverpod | `lib/core/providers/` | 0s (hot reload) |
| API Call | `lib/data/api/` + `backend/app.py` | 0s (hot reload) |
| Audio Logic | `lib/core/services/audio_service.dart` | 0-2s (hot reload) |
| Permission/Native | `android/app/build.gradle.kts` | 5-10 min |
| Backend Model | `backend/arranger.py`, `backend/inference.py` | 0s (Flask auto-reload) |

**Règle d'or:** Si c'est Dart/Flutter code = hot reload rapide. Si c'est Android/Kotlin = build long.

---

## 🔧 Gradle Tricks pour Build Rapide

**File:** `app/android/gradle.properties`

```properties
# Déjà configuré — heap optimisé
org.gradle.jvmargs=-Xmx4096m
org.gradle.daemon=true           # Gradle daemon reste actif (3x+ rapide)
org.gradle.parallel=true         # Build parallel (optionnel, peut causer issues)

# Pour développement ultra agressif (risqué):
org.gradle.caching=true          # Cache build tasks globalement
```

**Ne change PAS settings.gradle.kts — tu casses le build.** (Sauf ajout repository, très rare).

---

## 💥 Troubleshoot Rapide

### "Build hanging" ou "Gradle process killed"
```powershell
# Kill tous les processus
Get-Process gradle*,java*,flutter* -ErrorAction SilentlyContinue | Stop-Process -Force

# Attendre 5s, recommencer
Start-Sleep 5
flutter run
```

### Changement pubspec.yaml ne veut pas appliquer
```powershell
flutter pub get
# Si toujours bloqué:
Remove-Item .dart_tool -Recurse -Force
flutter pub get
```

### "Erreur Android mais pas clear pourquoi"
```powershell
# Full log verbose
flutter run -v 2>&1 | Tee-Object build_log.txt
# Cherche "error:" ou "FAILED" dans build_log.txt
```

### Gradle repository error
⚠️ **NE PAS ÉDITER** `settings.gradle.kts` sauf si new repo ajoutée.
→ Si besoin: ajoute repo seulement dans `repositories {}` block (déjà fait: Flutter SDK repo là).

---

## 📊 Temps Réaliste par Opération

| Opération | Local Dev | CI/CD (GitHub) |
|-----------|-----------|---|
| Hot reload (UI change) | 2-3s | N/A |
| `flutter pub get` | 15-30s | 2-3 min |
| Incremental APK build | 30-60s | N/A |
| Full APK build (clean) | 5-7 min | 11-15 min |
| Backend Flask restart | 1s | N/A |
| Backend inference (first run) | 10-30s | 10-30s |

**Tip:** Développe sur **device physique via WiFi** si possible (hot reload plus stable).

---

## 🎯 Workflow Type: Ajouter Feature Audio

**Temps total: ~5 min**

```powershell
# 1. Edit service
# lib/core/services/audio_service.dart → hot reload auto (0s)

# 2. Edit UI
# lib/presentation/screens/audio_screen.dart → hot reload (0s)

# 3. Edit provider
# lib/core/providers/audio_provider.dart → hot reload (0s)

# 4. Test local
flutter run  # Déjà lancé, juste regarde app

# 5. Commit
git add .
git commit -m "feat(audio): add new feature"
git push

# 6. GitHub Actions builds auto (11 min, tu continues)
```

**Total dev time: ~3-5 min. GitHub Actions: 11 min (parallel, tu fais autre chose).**

---

## 🚫 À NE PAS FAIRE

- ❌ `flutter clean` chaque fois
- ❌ Éditer Gradle config pendant dev (crash)
- ❌ Oublier `flutter pub get` après pubspec change
- ❌ Pousser code sans test local rapide
- ❌ Attendre GitHub Actions pour savoir si ça marche (test local d'abord)

---

## 📌 Cas Spécial: Tests Inference/Arranger

Backend tests sans recompile app:

```powershell
# Terminal séparé
cd backend
.\venv\Scripts\activate
python test_inference.py
python test_arranger.py
```

**App Dart continue de tourner** = zero impact sur dev.

---

## 🎓 Résumé: 3 Modes de Dev

| Mode | Cas | Temps | Commande |
|------|-----|-------|----------|
| **Mode Rapide** (90%) | UI/Dart logic/provider | 0-3s | `flutter run` (auto reload) |
| **Mode Normal** (9%) | Pubspec change/package add | 30-60s | `flutter pub get && flutter run` |
| **Mode Lourd** (1%) | Android/Gradle/native | 5-15 min | `flutter build apk --debug` ou GitHub Actions |

**Philosophie:** Maximise mode rapide. Batch mode lourd pour fin de jour.

---

**TL;DR:** Utilise hot reload, teste local d'abord, pousse à GitHub Actions. Done. 🚀
