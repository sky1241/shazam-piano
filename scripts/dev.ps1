
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

# PID timeout for logcat (seconds) - needs to be long enough for Flutter build+install
$pidTimeout = 120

function Get-AndroidPackageInfo {
  param([string]$RepoRoot)
  $result = @{
    ApplicationId = $null
    Namespace = $null
    Effective = $null
  }

  # Check build.gradle.kts first
  $gradleKts = Join-Path $RepoRoot "app\android\app\build.gradle.kts"
  if (Test-Path $gradleKts) {
    $content = Get-Content $gradleKts -Raw
    if ($content -match 'applicationId\s*=\s*"([^"]+)"') {
      $result.ApplicationId = $Matches[1]
    }
    if ($content -match 'namespace\s*=\s*"([^"]+)"') {
      $result.Namespace = $Matches[1]
    }
  }

  # Check build.gradle (groovy) if not found
  $gradle = Join-Path $RepoRoot "app\android\app\build.gradle"
  if (Test-Path $gradle) {
    $content = Get-Content $gradle -Raw
    if (-not $result.ApplicationId -and $content -match 'applicationId\s+[''"]([^''"]+)[''"]') {
      $result.ApplicationId = $Matches[1]
    }
    if (-not $result.Namespace -and $content -match 'namespace\s+[''"]([^''"]+)[''"]') {
      $result.Namespace = $Matches[1]
    }
  }

  # Effective = applicationId (priority) > namespace (fallback)
  if ($result.ApplicationId) {
    $result.Effective = $result.ApplicationId
  } elseif ($result.Namespace) {
    $result.Effective = $result.Namespace
  }

  return $result
}

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

  # ============================================================
  # INVARIANT 1: SINGLE DEVICE ENFORCEMENT (FAIL-CLOSED)
  # ============================================================
  $deviceSerial = $null
  if (Get-Command adb -ErrorAction SilentlyContinue) {
    $deviceLines = adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "(\S+)\s+device$" }
    $deviceCount = ($deviceLines | Measure-Object).Count
    if ($deviceCount -eq 0) {
      Write-Host ""
      Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
      Write-Host "  FAIL: NO DEVICE CONNECTED" -ForegroundColor Red
      Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
      Write-Host ""
      Write-Host "Run: adb devices" -ForegroundColor Yellow
      Write-Host "Connect a device or start an emulator." -ForegroundColor Yellow
      exit 1
    } elseif ($deviceCount -gt 1) {
      Write-Host ""
      Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
      Write-Host "  FAIL: MULTIPLE DEVICES DETECTED ($deviceCount)" -ForegroundColor Red
      Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
      Write-Host ""
      Write-Host "Devices:" -ForegroundColor Yellow
      adb devices
      Write-Host ""
      Write-Host "SOLUTION: Set env var before running:" -ForegroundColor Yellow
      Write-Host '  $env:ANDROID_SERIAL = "DEVICE_SERIAL_HERE"' -ForegroundColor Cyan
      Write-Host "Then re-run: .\scripts\dev.ps1 -Logcat" -ForegroundColor Cyan
      Write-Host ""
      exit 1
    } else {
      # Extract the single serial
      if ($deviceLines -match "(\S+)\s+device$") {
        $deviceSerial = $Matches[1]
      }
      Write-Host "DEVICE_SERIAL=$deviceSerial" -ForegroundColor Green
    }
  }

  # ============================================================
  # PACKAGE DETECTION (applicationId > namespace) - FAIL-CLOSED
  # ============================================================
  $pkgInfo = Get-AndroidPackageInfo -RepoRoot $repoRoot
  Write-Host "PACKAGE_APPLICATION_ID=$($pkgInfo.ApplicationId ?? 'NOT_FOUND')" -ForegroundColor $(if ($pkgInfo.ApplicationId) { 'Green' } else { 'Yellow' })
  Write-Host "PACKAGE_NAMESPACE=$($pkgInfo.Namespace ?? 'NOT_FOUND')" -ForegroundColor $(if ($pkgInfo.Namespace) { 'Gray' } else { 'Yellow' })

  if (-not $pkgInfo.Effective) {
    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "  FAIL: NO PACKAGE DETECTED" -ForegroundColor Red
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Check app/android/app/build.gradle.kts for applicationId" -ForegroundColor Yellow
    exit 1
  }
  $packageName = $pkgInfo.Effective
  Write-Host "PACKAGE_EFFECTIVE=$packageName" -ForegroundColor Green

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
  if ($deviceSerial) {
    $runAppArgs = " -DeviceSerial '$deviceSerial'"
  }
  if ($Fast) {
    $runAppArgs = "$runAppArgs -Fast"
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
      $logTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
      $logDir = Join-Path $repoRoot "logs"

      # Ensure logs directory exists
      if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
      }

      # BUILD_STAMP + serial + timestamp in filename
      $logSha = "nogit"
      try { $logSha = (git rev-parse --short HEAD 2>$null).Trim() } catch {}
      $logStamp = "$logSha-$logTimestamp"
      $serialSafe = $deviceSerial -replace '[:\\/<>|"?*]', '_'
      $logFile = Join-Path $logDir "logcat_${logStamp}_${serialSafe}.txt"

      # ADB serial argument
      $adbSerial = ""
      if ($deviceSerial) {
        $adbSerial = "-s $deviceSerial"
      }

      # ============================================================
      # INVARIANT 2: SIMPLE LOGCAT WITH FILE OUTPUT
      # ============================================================
      # Write header to log file
      $headerContent = @"
============================================================
PROOF_LOGCAT HEADER
============================================================
PROOF_DEVICE_SERIAL   = $deviceSerial
PROOF_PACKAGE         = $packageName
PROOF_START_TIME      = $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
PROOF_LOG_FILE        = $logFile
============================================================

"@
      $headerContent | Out-File -Encoding utf8 -FilePath $logFile

      # Simple logcat script - stream all logs from app
      # Note: Use $appPid instead of $pid (reserved variable in PowerShell)
      $logcatScript = @'
param($pkg, $serial, $logPath, $timeout)
$host.UI.RawUI.WindowTitle = 'Logcat'
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  LOGCAT - STREAMING APP LOGS' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "PACKAGE = $pkg"
Write-Host "DEVICE  = $serial"
Write-Host "LOG     = $logPath"
Write-Host ''

$adbArgs = if ($serial) { "-s $serial" } else { "" }

# Clear buffer
Invoke-Expression "adb $adbArgs logcat -c" 2>$null

# Wait for PID
Write-Host 'Waiting for app PID...' -ForegroundColor Yellow
$appPid = $null
for ($i = 0; $i -lt $timeout -and -not $appPid; $i++) {
    Start-Sleep -Seconds 1
    $appPid = Invoke-Expression "adb $adbArgs shell pidof -s $pkg" 2>$null
    if ($appPid) { $appPid = $appPid.Trim() }
    Write-Host "." -NoNewline
}
Write-Host ''

if (-not $appPid) {
    Write-Host "FAIL: PID not found after $timeout seconds" -ForegroundColor Red
    "PROOF_PID = FAIL_NOT_FOUND" | Out-File -Append -Encoding utf8 -FilePath $logPath
    exit 1
}

Write-Host "PID = $appPid" -ForegroundColor Green
"PROOF_PID = $appPid" | Out-File -Append -Encoding utf8 -FilePath $logPath
Write-Host ''
Write-Host 'Streaming logs (Ctrl+C to stop)...' -ForegroundColor Cyan

# Stream with --pid if supported, else full stream
$testResult = Invoke-Expression "adb $adbArgs logcat --pid=1 -d -t 1 2>&1"
if ($testResult -notmatch 'unknown|error|Invalid') {
    Write-Host "MODE = PID_NATIVE" -ForegroundColor Green
    "PROOF_MODE = PID_NATIVE" | Out-File -Append -Encoding utf8 -FilePath $logPath
    Invoke-Expression "adb $adbArgs logcat --pid=$appPid -v time" 2>&1 | ForEach-Object {
        $_ | Out-File -Append -Encoding utf8 -FilePath $logPath
        Write-Host $_
    }
} else {
    Write-Host "MODE = FULL_CAPTURE (filtering by PID $appPid)" -ForegroundColor Yellow
    "PROOF_MODE = FULL_CAPTURE" | Out-File -Append -Encoding utf8 -FilePath $logPath
    Invoke-Expression "adb $adbArgs logcat -v time" 2>&1 | ForEach-Object {
        if ($_ -match "\s+$appPid\s+") {
            $_ | Out-File -Append -Encoding utf8 -FilePath $logPath
            Write-Host $_
        }
    }
}
'@
      # Write script to temp file and execute
      $tempScript = Join-Path $env:TEMP "logcat_script_$logTimestamp.ps1"
      $logcatScript | Out-File -Encoding utf8 -FilePath $tempScript
      # Use quoted paths for spaces
      Start-Process -FilePath $shell -ArgumentList "-NoExit", "-File", "`"$tempScript`"", "-pkg", "`"$packageName`"", "-serial", "`"$deviceSerial`"", "-logPath", "`"$logFile`"", "-timeout", $pidTimeout | Out-Null
      Write-Host "LOGCAT_FILE=$logFile (PID-filtered, all tags)" -ForegroundColor Green
    } else {
      Write-Host ""
      Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
      Write-Host "  FAIL: ADB NOT FOUND" -ForegroundColor Red
      Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
      exit 1
    }
  }

  Write-Host "Opened: Backend + Flutter (+ Logcat if requested)."
} catch {
  Write-Host "ERROR: $($_.Exception.Message)"
  Show-Help
  exit 1
}
