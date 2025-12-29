[CmdletBinding()]
param(
  [switch]$Logcat,
  [switch]$Fast,
  [switch]$NoBuild,
  [switch]$UnlockAll
)

$ErrorActionPreference = "Stop"

function Show-Help {
  Write-Host "Usage:"
  Write-Host "  .\scripts\dev.ps1 [-Logcat]"
  Write-Host ""
  Write-Host "Options:"
  Write-Host "  -Logcat   Open an additional Logcat window (adb must be available)."
  Write-Host "  -Fast     Skip flutter clean/pub get for a quieter, faster launch."
  Write-Host "  -NoBuild  Skip Gradle build if APK already exists."
  Write-Host "  -UnlockAll  Force DEV unlock (debug only)."
}

function Stop-WindowByTitle {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Title
  )

  $targets = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -eq $Title }
  if ($targets) {
    $targets | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
  }
}

$logcatFilterArgs = "/c:flutter /c:ShazaPiano"

try {
  $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  $repoRoot = Resolve-Path (Join-Path $scriptRoot "..")

  $shell = "powershell"
  if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $shell = "pwsh"
  }

  foreach ($title in @("Backend", "Flutter", "Logcat")) {
    Stop-WindowByTitle -Title $title
  }

  $backendDir = Join-Path $repoRoot "backend"
  $runAppPath = Join-Path $repoRoot "scripts\run-app.ps1"

  $activateCmd = $null
  $venvActivate = Join-Path $backendDir "venv\Scripts\Activate.ps1"
  $dotVenvActivate = Join-Path $backendDir ".venv\Scripts\Activate.ps1"
  if (Test-Path $venvActivate) {
    $activateCmd = $venvActivate
  } elseif (Test-Path $dotVenvActivate) {
    $activateCmd = $dotVenvActivate
  }

  $backendCmd = $null
  if (Test-Path (Join-Path $backendDir "app.py")) {
    $backendCmd = "python app.py"
  } elseif (Get-Command uvicorn -ErrorAction SilentlyContinue) {
    $backendCmd = "uvicorn app:app --host 0.0.0.0 --port 8000"
  }

  $backendScriptLines = @(
    "`$host.UI.RawUI.WindowTitle = 'Backend'",
    "Write-Host 'Backend window'",
    "Set-Location '$backendDir'"
  )
  if ($activateCmd) {
    $backendScriptLines += ". '$activateCmd'"
  }
  if ($backendCmd) {
    $backendScriptLines += "Write-Host 'Backend command: $backendCmd'"
    if ($backendCmd -eq "python app.py") {
      $backendScriptLines += "python app.py"
      $backendScriptLines += "if (`$LASTEXITCODE -ne 0) { Write-Host 'Backend command failed. Try: uvicorn backend.app:app --host 0.0.0.0 --port 8000' }"
    } else {
      $backendScriptLines += $backendCmd
    }
  } else {
    $backendScriptLines += "Write-Host 'Backend command not found. Check backend/app.py or uvicorn.'"
  }
  $backendScript = $backendScriptLines -join "; "
  Start-Process -FilePath $shell -ArgumentList "-NoExit", "-Command", $backendScript | Out-Null

  $runAppArgs = ""
  if ($Fast) {
    $runAppArgs = " -Fast"
  }
  if ($NoBuild) {
    $runAppArgs = "$runAppArgs -NoBuild"
  }
  if ($UnlockAll) {
    $runAppArgs = "$runAppArgs -UnlockAll"
  }

  $flutterScript = @(
    "`$host.UI.RawUI.WindowTitle = 'Flutter'",
    "Write-Host 'Flutter window'",
    "Set-Location '$repoRoot'",
    "Write-Host 'Launching Flutter (BUILD_STAMP overlay is visible in debug)'",
    "& '$runAppPath'$runAppArgs"
  ) -join "; "
  Start-Process -FilePath $shell -ArgumentList "-NoExit", "-Command", $flutterScript | Out-Null

  if ($Logcat) {
    if (Get-Command adb -ErrorAction SilentlyContinue) {
      $logcatScript = @(
        "`$host.UI.RawUI.WindowTitle = 'Logcat'",
        "Write-Host 'Logcat window'",
        "adb logcat -c",
        "adb logcat | findstr /i $logcatFilterArgs"
      ) -join "; "
      Start-Process -FilePath $shell -ArgumentList "-NoExit", "-Command", $logcatScript | Out-Null
    } else {
      Write-Warning "adb not found; skipping logcat."
    }
  }

  Write-Host "Opened: Backend + Flutter (+ Logcat if requested)."
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Show-Help
  exit 1
}
