# ShazaPiano - Troubleshooting Guide

Guide de résolution des problèmes courants.

---

## 📱 Problèmes App (Flutter)

### App ne démarre pas

**Symptômes** :
- Crash au lancement
- Écran blanc
- "App has stopped"

**Solutions** :
1. Réinstaller l'app
2. Vider le cache : Settings > Apps > ShazaPiano > Clear Cache
3. Vérifier version Android (min 6.0)
4. Vérifier espace disque disponible (min 100 MB)

### Permission micro refusée

**Solutions** :
1. Android Settings > Apps > ShazaPiano > Permissions
2. Activer "Microphone"
3. Redémarrer l'app

### Enregistrement ne fonctionne pas

**Diagnostic** :
```dart
// Check logs dans terminal :
flutter logs --device <device-id>
```

**Solutions** :
1. Vérifier permissions
2. Tester micro avec autre app (enregistreur vocal)
3. Redémarrer device
4. Vérifier que micro n'est pas utilisé par autre app

### Upload échoue

**Erreurs possibles** :
- `Connection timeout` → Problème réseau
- `File too large` → Fichier > 10 MB
- `Server error` → Backend down

**Solutions** :
1. Vérifier connexion internet (WiFi ou 4G)
2. Réduire durée enregistrement (max 15s)
3. Réessayer plus tard
4. Check backend status : https://shazapiano-backend.fly.dev/health

### Vidéos ne se chargent pas

**Solutions** :
1. Vérifier connexion internet
2. Attendre fin du loading
3. Force close et réouvrir app
4. Vider cache app

### IAP ne fonctionne pas

**Diagnostic** :
```
Play Console > Order Management > Vérifier transaction
```

**Solutions** :
1. Vérifier connexion Google Play
2. Bouton "Restaurer l'achat"
3. Attendre 5-10 minutes (propagation)
4. Vérifier compte Google Play actif
5. Réinstaller app + restore

---

## 🖥️ Problèmes Backend (Python)

### BasicPitch import error

**Erreur** :
```
ModuleNotFoundError: No module named 'basic_pitch'
```

**Solution** :
```bash
pip install basic-pitch tensorflow
```

### FFmpeg not found

**Erreur** :
```
FileNotFoundError: [Errno 2] No such file or directory: 'ffmpeg'
```

**Solution Windows** :
```powershell
# Option 1: Winget
winget install FFmpeg

# Option 2: Chocolatey
choco install ffmpeg

# Option 3: Manual
# Download from https://ffmpeg.org/download.html
# Add to PATH
```

**Solution Linux** :
```bash
sudo apt update
sudo apt install ffmpeg
```

**Solution Mac** :
```bash
brew install ffmpeg
```

### Tensorflow CPU warnings

**Warning** :
```
tensorflow not compiled with AVX2 support
```

**Solution** :
Ignore - doesn't affect functionality. Or install tensorflow-cpu optimized version.

### MoviePy "IMAGEIO FFMPEG_WRITER WARNING"

**Solution** :
```bash
pip install imageio-ffmpeg
```

### Port 8000 already in use

**Erreur** :
```
OSError: [Errno 48] Address already in use
```

**Solution** :
```bash
# Find process using port 8000
lsof -i :8000  # Mac/Linux
netstat -ano | findstr :8000  # Windows

# Kill process
kill <PID>  # Mac/Linux
taskkill /PID <PID> /F  # Windows

# Or use different port
uvicorn app:app --port 8001
```

### Out of memory (video rendering)

**Erreur** :
```
MemoryError: Unable to allocate array
```

**Solutions** :
1. Reduce video resolution in config.py
2. Increase Docker memory limit
3. Process fewer levels at once
4. Use smaller buffer sizes

---

## 🐳 Problèmes Docker

### Docker image won't build

**Solutions** :
```bash
# Clear cache
docker system prune -a

# Build with no cache
docker build --no-cache -t shazapiano-backend .

# Check logs
docker build -t shazapiano-backend . 2>&1 | tee build.log
```

### Container exits immediately

**Diagnostic** :
```bash
docker logs shazapiano-backend
docker inspect shazapiano-backend
```

**Solutions** :
1. Check environment variables
2. Verify CMD in Dockerfile
3. Test locally first without Docker

### Volume permissions

**Erreur** :
```
PermissionError: [Errno 13] Permission denied: '/app/media'
```

**Solution** :
```dockerfile
# In Dockerfile, add:
RUN chmod -R 777 /app/media
```

---

## 🔥 Problèmes Firebase

### google-services.json not found

**Erreur** :
```
Execution failed for task ':app:processDebugGoogleServices'
```

**Solution** :
1. Télécharger depuis Firebase Console
2. Placer dans `app/android/app/google-services.json`
3. Rebuild

### Firebase not initialized

**Erreur** :
```
[core/no-app] No Firebase App '[DEFAULT]' has been created
```

**Solution** :
```dart
// In main.dart, ensure:
await Firebase.initializeApp();
// before runApp()
```

### Firestore permission denied

**Erreur** :
```
PERMISSION_DENIED: Missing or insufficient permissions
```

**Solution** :
1. Check Firestore Rules in Firebase Console
2. Ensure user is authenticated
3. Verify rules match document structure

---

## 🧪 Problèmes Tests

### Flutter tests fail

**Solutions** :
```bash
# Clear cache
flutter clean
flutter pub get

# Run with verbose
flutter test --verbose

# Update golden files if UI tests
flutter test --update-goldens
```

### Backend tests fail

**Solutions** :
```bash
# Install test dependencies
pip install pytest pytest-asyncio httpx

# Run with verbose
pytest -v -s

# Run specific test
pytest test_api.py::test_health_endpoint -v
```

---

## 🚀 Problèmes Déploiement

### Fly.io deploy fails

**Diagnostic** :
```bash
flyctl logs
flyctl status
```

**Solutions** :
1. Check Dockerfile syntax
2. Verify fly.toml configuration
3. Ensure region has capacity
4. Check resource limits

### Play Store upload rejected

**Raisons courantes** :
- Missing privacy policy
- Inappropriate content rating
- Missing store listing info
- APK not signed correctly

**Solutions** :
1. Complete all required fields
2. Add privacy policy URL
3. Re-sign APK with correct keystore
4. Check Play Console error messages

### AAB signature verification failed

**Solution** :
```bash
# Verify keystore
keytool -list -v -keystore shazapiano-release.keystore

# Rebuild with correct signing
flutter build appbundle --release
```

---

## 🔍 Debugging Tips

### Enable Verbose Logging

**Backend** :
```python
# In config.py
DEBUG = True

# In app.py
import logging
logging.basicConfig(level=logging.DEBUG)
```

**Flutter** :
```dart
// Enable debug prints
debugPrint('My debug message');

// Check provider states
ref.listen(recordingProvider, (prev, next) {
  print('Recording state changed: $next');
});
```

### Check Network Requests

**Flutter** :
```dart
// In Dio interceptor (already configured)
dio.interceptors.add(LogInterceptor(
  requestBody: true,
  responseBody: true,
));
```

### Monitor Firebase

```bash
# Firebase Console > Crashlytics
# See all crashes with stack traces

# Firebase Console > Analytics
# Real-time events
```

---

## 📊 Performance Issues

### Backend slow response

**Diagnostic** :
```bash
# Check server resources
flyctl status
flyctl metrics

# Check logs for slow operations
flyctl logs | grep "slow"
```

**Solutions** :
1. Warm-up BasicPitch model at startup
2. Increase server resources (RAM, CPU)
3. Optimize video rendering settings
4. Add caching layer (Redis)

### Flutter app laggy

**Solutions** :
```bash
# Build in release mode
flutter run --release

# Profile performance
flutter run --profile
# Use DevTools performance tab

# Check for memory leaks
# Use Flutter Inspector
```

---

## 🔒 Security Issues

### Suspicious activity detected

**Report immediately** : security@shazapiano.com

**Include** :
- What happened
- When it happened
- Screenshots if possible
- Device/app version

### Data breach concerns

**Response** :
1. We'll investigate within 24h
2. Notify affected users within 72h
3. Implement fixes
4. Post-mortem report

---

## 📞 Getting Help

### Self-Help Resources

1. Check this Troubleshooting guide
2. Read [FAQ](FAQ.md)
3. Check [Documentation](../README.md)
4. Search [GitHub Issues](https://github.com/sky1241/shazam-piano/issues)

### Contact Support

**Email** : support@shazapiano.com

**Include in your message** :
- Device model
- Android version
- App version (from Settings)
- Clear description of problem
- Steps to reproduce
- Screenshots if applicable

**Response time** : Within 48 hours

### Emergency Contact

For critical bugs or security issues:
- **Priority Email** : urgent@shazapiano.com
- **Response** : Within 4 hours

---

## 🐛 Known Issues

### Current Version (0.1.0)

1. **Audio synthesis** : FluidSynth not always available
   - Workaround : Use `with_audio=false`
   
2. **Large files** : Files > 8MB may timeout
   - Workaround : Keep recordings under 10 seconds
   
3. **Noisy recordings** : May fail MIDI extraction
   - Workaround : Record in quiet environment

---

## 🔄 Reporting Bugs

### Bug Report Template

```
**Description**:
Clear description of the bug

**Steps to Reproduce**:
1. Step 1
2. Step 2
3. ...

**Expected Behavior**:
What should happen

**Actual Behavior**:
What actually happens

**Environment**:
- Device: Samsung Galaxy S21
- Android: 13
- App Version: 1.0.0

**Screenshots**:
[Attach if applicable]

**Logs**:
[Relevant error messages]
```

### Where to Report

- **GitHub** : https://github.com/sky1241/shazam-piano/issues
- **Email** : bugs@shazapiano.com

---

**🎹 Happy troubleshooting! Most issues have simple fixes.**

**Still stuck?** Contact support@shazapiano.com

