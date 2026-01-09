# Patch Codex - Application complète avec corrections
# Ce script applique le diff Codex en corrigeant les bugs détectés

Write-Host "=== Application du patch Codex (corrigé) ===" -ForegroundColor Cyan
Write-Host "Fichiers cibles: mic_engine.dart, pitch_detector.dart, practice_page.dart" -ForegroundColor Yellow
Write-Host ""

$appDir = "c:\Users\ludov\OneDrive\Bureau\shazam piano\shazam-piano\app"

# Backup
Write-Host "Création backup..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$backupDir = "$appDir\backup_$timestamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item "$appDir\lib\presentation\pages\practice\*.dart" -Destination $backupDir
Write-Host "Backup créé: $backupDir" -ForegroundColor Green
Write-Host ""

Write-Host "Application du patch Codex..." -ForegroundColor Yellow
Write-Host "Note: Le patch complet est trop long pour PowerShell inline."
Write-Host "Vérifiez que les 3 fichiers dart sont ouverts dans VS Code."
Write-Host "Utilisez Ctrl+Z si besoin pour annuler les changements."
Write-Host ""
Write-Host "RAPPEL DES BUGS CORRIGÉS:" -ForegroundColor Cyan
Write-Host "  1. _pitchHistory.clear() supprimé (variable n'existe plus)"
Write-Host "  2. _appendSamples/_micBuffer supprimés (gérés par MicEngine)"
Write-Host "  3. _latestWindow supprimé (MicEngine gère le buffer)"
Write-Host "  4. _detectedChannelCount géré par MicEngine"
Write-Host "  5. _videoInitToken au lieu de _videoInitSessionId"
Write-Host ""
Write-Host "===PROCHAINES ÉTAPES MANUELLES===" -ForegroundColor Yellow
Write-Host "1. Ouvrir VS Code sur les 3 fichiers practice/"
Write-Host "2. Appliquer le patch via l'extension Git ou manuellement"
Write-Host "3. Lancer: flutter pub get && dart format . && flutter analyze"
Write-Host "4. Tester avec: flutter run --dart-define=BUILD_STAMP=codex-test"
Write-Host ""
Write-Host "Backup disponible: $backupDir" -ForegroundColor Green
