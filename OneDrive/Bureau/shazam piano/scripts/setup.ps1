# ShazaPiano - Setup Script for Windows PowerShell
# Sets up development environment on Windows

Write-Host "🎹 ShazaPiano Setup Script (Windows)" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# Check Python
Write-Host "📦 Checking Python..." -ForegroundColor Yellow
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonVersion = python --version
    Write-Host "✓ $pythonVersion" -ForegroundColor Green
} else {
    Write-Host "❌ Python not found. Install from https://www.python.org/" -ForegroundColor Red
    exit 1
}

# Check FFmpeg
Write-Host ""
Write-Host "🎥 Checking FFmpeg..." -ForegroundColor Yellow
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
    $ffmpegVersion = ffmpeg -version 2>&1 | Select-Object -First 1
    Write-Host "✓ FFmpeg found" -ForegroundColor Green
} else {
    Write-Host "⚠️  FFmpeg not found" -ForegroundColor Yellow
    Write-Host "   Download from: https://ffmpeg.org/download.html" -ForegroundColor Yellow
    Write-Host "   Or install with: winget install FFmpeg" -ForegroundColor Yellow
}

# Backend Setup
Write-Host ""
Write-Host "📦 Setting up Backend..." -ForegroundColor Cyan
Write-Host "------------------------" -ForegroundColor Cyan

Set-Location backend

if (-Not (Test-Path ".venv")) {
    Write-Host "Creating Python virtual environment..." -ForegroundColor Yellow
    python -m venv .venv
}

Write-Host "Activating virtual environment..." -ForegroundColor Yellow
.\.venv\Scripts\Activate.ps1

Write-Host "Installing Python dependencies..." -ForegroundColor Yellow
python -m pip install --upgrade pip
pip install -r requirements.txt

Write-Host "✅ Backend setup complete!" -ForegroundColor Green

Set-Location ..

# Flutter Setup
Write-Host ""
Write-Host "📱 Setting up Flutter App..." -ForegroundColor Cyan
Write-Host "----------------------------" -ForegroundColor Cyan

if (Get-Command flutter -ErrorAction SilentlyContinue) {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "✓ $flutterVersion" -ForegroundColor Green
} else {
    Write-Host "❌ Flutter not found. Install from https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Red
    exit 1
}

Set-Location app

Write-Host "Getting Flutter dependencies..." -ForegroundColor Yellow
flutter pub get

Write-Host "Running code generation..." -ForegroundColor Yellow
flutter pub run build_runner build --delete-conflicting-outputs

Write-Host "✅ Flutter setup complete!" -ForegroundColor Green

Set-Location ..

# Docker Check
Write-Host ""
Write-Host "🐳 Checking Docker..." -ForegroundColor Cyan
Write-Host "--------------------" -ForegroundColor Cyan

if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dockerVersion = docker --version
    Write-Host "✓ $dockerVersion" -ForegroundColor Green
} else {
    Write-Host "⚠️  Docker not found (optional)" -ForegroundColor Yellow
    Write-Host "   Install Docker Desktop for Windows" -ForegroundColor Yellow
}

# Summary
Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "🎉 Setup Complete!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Backend: cd backend && .\.venv\Scripts\Activate.ps1 && uvicorn app:app --reload" -ForegroundColor White
Write-Host "  2. Flutter: cd app && flutter run" -ForegroundColor White
Write-Host "  3. Docker:  cd infra && docker-compose up" -ForegroundColor White
Write-Host ""
Write-Host "Happy coding! 🎹" -ForegroundColor Cyan

