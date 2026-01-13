# Script de rebuild COMPLET pour forcer recompilation
# Utilise ce script quand hot reload ne suffit pas

Write-Host "=== REBUILD COMPLET ===" -ForegroundColor Cyan

# 1. Kill l'app sur le device
Write-Host "`n1. Arrêt de l'app sur le device..." -ForegroundColor Yellow
cd app
flutter run --pid-file="flutter.pid" 2>&1 | Out-Null
if (Test-Path "flutter.pid") {
    $pid = Get-Content "flutter.pid"
    adb shell am force-stop com.ludo.shazapiano
    Remove-Item "flutter.pid" -ErrorAction SilentlyContinue
}

# 2. Clean complet
Write-Host "2. Nettoyage complet (flutter clean)..." -ForegroundColor Yellow
flutter clean | Out-Null

# 3. Pub get
Write-Host "3. Téléchargement packages (flutter pub get)..." -ForegroundColor Yellow
flutter pub get | Out-Null

# 4. Rebuild + run avec logcat
Write-Host "4. Compilation complète et lancement..." -ForegroundColor Yellow
Write-Host "   (Les logs seront dans debuglogcat à la racine)" -ForegroundColor Gray
cd ..

# Clear logcat avant de lancer
adb logcat -c

# Lance l'app en mode release pour éviter les timeouts debug
cd app
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PWD'; flutter run --release" -WindowStyle Minimized

# Capture logcat en arrière-plan
Start-Sleep -Seconds 5
Write-Host "`n5. Capture des logs démarrée..." -ForegroundColor Green
adb logcat -v time | Tee-Object -FilePath "..\debuglogcat"
