#!/usr/bin/env pwsh
# Run dev.ps1 and capture Logcat to file

$ErrorActionPreference = "Stop"

Write-Host "🚀 Launching dev environment with log capture..." -ForegroundColor Cyan

# Clean previous log
$logFile = "logcat_output.txt"
if (Test-Path $logFile) {
    Remove-Item $logFile
}

# Run dev.ps1 in background
Start-Job -ScriptBlock {
    Set-Location $using:PWD
    .\scripts\dev.ps1 -Logcat
} | Out-Null

Write-Host "✅ Dev environment started. Waiting for app to launch..." -ForegroundColor Green
Start-Sleep -Seconds 15

Write-Host "📝 Capturing Logcat to $logFile..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop capture." -ForegroundColor Yellow

# Capture logcat to file
adb logcat -c
adb logcat | Tee-Object -FilePath $logFile

Write-Host "✅ Logs saved to $logFile" -ForegroundColor Green
