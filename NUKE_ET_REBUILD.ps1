#!/usr/bin/env pwsh
# NUKE COMPLET - Éliminer TOUT le cache Flutter

Write-Host "🔥 NUKE FLUTTER COMPLET..." -ForegroundColor Red

# 1. Tuer tous les processus Flutter/Gradle
Write-Host "1. Killing Flutter/Gradle processes..." -ForegroundColor Yellow
Get-Process | Where-Object {$_.Name -match "flutter|dart|gradle|java"} | Stop-Process -Force -ErrorAction SilentlyContinue

# 2. Désinstaller l'app du device
Write-Host "2. Uninstalling app from device..." -ForegroundColor Yellow
adb uninstall com.ludo.shazapiano

# 3. Clean Flutter
Write-Host "3. Flutter clean..." -ForegroundColor Yellow
Set-Location "app"
flutter clean

# 4. Supprimer TOUS les caches
Write-Host "4. Removing ALL caches..." -ForegroundColor Yellow
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android/.gradle -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android/app/build -ErrorAction SilentlyContinue
Remove-Item -Force pubspec.lock -ErrorAction SilentlyContinue
Remove-Item -Force android/local.properties -ErrorAction SilentlyContinue

# 5. Pub get
Write-Host "5. Flutter pub get..." -ForegroundColor Yellow
flutter pub get

# 6. Rebuild from scratch
Write-Host "6. Building fresh APK..." -ForegroundColor Green
Set-Location ..
.\scripts\dev.ps1 -Logcat

Write-Host "✅ DONE - Attends l'install et cherche 'Countdown C8' dans les logs" -ForegroundColor Green
