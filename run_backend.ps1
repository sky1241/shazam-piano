#!/usr/bin/env pwsh
# Run the backend from the repository root.

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDir = Join-Path $projectRoot "backend"

Write-Host ">> Changing to backend directory: $backendDir" -ForegroundColor Cyan
Set-Location $backendDir

Write-Host "OK Current directory: $(Get-Location)" -ForegroundColor Green
Write-Host ">> Starting uvicorn server..." -ForegroundColor Cyan

python -m uvicorn app:app --host 0.0.0.0 --port 8000 --log-level info
