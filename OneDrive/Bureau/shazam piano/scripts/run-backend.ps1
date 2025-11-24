# Quick script to run backend on Windows

Write-Host "🚀 Starting ShazaPiano Backend..." -ForegroundColor Cyan

Set-Location backend

if (-Not (Test-Path ".venv")) {
    Write-Host "❌ Virtual environment not found. Run setup.ps1 first" -ForegroundColor Red
    exit 1
}

.\.venv\Scripts\Activate.ps1

Write-Host "Starting Uvicorn server on http://localhost:8000" -ForegroundColor Green
Write-Host "API Docs: http://localhost:8000/docs" -ForegroundColor Green
Write-Host ""

uvicorn app:app --reload --host 0.0.0.0 --port 8000

