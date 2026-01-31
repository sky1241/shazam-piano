
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

# PID timeout for logcat (seconds)
$pidTimeout = 30

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
      # INVARIANT 2: PID-BASED LOGCAT + FALLBACK + AUTO RE-SYNC
      # ============================================================
      $logcatScript = @"
`$host.UI.RawUI.WindowTitle = 'Logcat'
`$ErrorActionPreference = 'Continue'
`$pidTimeout = $pidTimeout
`$packageName = '$packageName'
`$deviceSerial = '$deviceSerial'
`$logFile = '$logFile'
`$adbSerial = '$adbSerial'
`$startTime = Get-Date

# ============================================================
# HEADER INFO
# ============================================================
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host '  LOGCAT - PID-FILTERED + AUTO RE-SYNC ON RESTART' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "PACKAGE_EFFECTIVE = `$packageName"
Write-Host "DEVICE_SERIAL     = `$deviceSerial"
Write-Host "LOG_FILE          = `$logFile"
Write-Host "PID_TIMEOUT       = `$pidTimeout seconds"
Write-Host ''

# Write PROOF_LOGCAT header to file
@"
============================================================
PROOF_LOGCAT HEADER
============================================================
PROOF_DEVICE_SERIAL   = `$deviceSerial
PROOF_PACKAGE         = `$packageName
PROOF_START_TIME      = `$(`$startTime.ToString('yyyy-MM-dd HH:mm:ss'))
PROOF_LOG_FILE        = `$logFile
============================================================

"@ | Out-File -Encoding utf8 -FilePath `$logFile

# Clear logcat buffer
Write-Host 'Clearing logcat buffer...' -ForegroundColor Yellow
adb `$adbSerial logcat -c 2>`$null

# Function to get PID with timeout
function Get-AppPid {
  param([int]`$Timeout)
  `$pid = `$null
  `$elapsed = 0
  while (-not `$pid -and `$elapsed -lt `$Timeout) {
    Start-Sleep -Seconds 1
    `$elapsed++
    `$pidResult = adb `$adbSerial shell pidof -s `$packageName 2>`$null
    if (`$pidResult -and `$pidResult -match '^\d+`$') {
      `$pid = `$pidResult.Trim()
    }
    Write-Host "`rWaiting for PID... (`$elapsed/`$Timeout)   " -NoNewline
  }
  Write-Host ''
  return `$pid
}

# Function to check if --pid is supported
function Test-PidSupport {
  `$testOutput = adb `$adbSerial logcat --pid=1 -d -t 1 2>&1
  return -not (`$testOutput -match 'unknown option|Invalid|error')
}

# Get initial PID
`$currentPid = Get-AppPid -Timeout `$pidTimeout

if (-not `$currentPid) {
  Write-Host ''
  Write-Host '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Red
  Write-Host "  FAIL: PID NOT FOUND AFTER `$pidTimeout SECONDS" -ForegroundColor Red
  Write-Host '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Red
  Write-Host ''
  Write-Host "Package: `$packageName" -ForegroundColor Yellow
  Write-Host 'Verify: package name / app installed / device serial' -ForegroundColor Yellow
  "PROOF_PID = FAIL_NOT_FOUND" | Out-File -Append -Encoding utf8 -FilePath `$logFile
  exit 1
}

# Test if --pid is supported
`$pidSupported = Test-PidSupport
`$captureMode = if (`$pidSupported) { 'PID_NATIVE' } else { 'FULL_CAPTURE_FALLBACK' }

"PROOF_PID             = `$currentPid
PROOF_CAPTURE_MODE    = `$captureMode
============================================================
" | Out-File -Append -Encoding utf8 -FilePath `$logFile

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host "  LOGCAT_PID=`$currentPid MODE=`$captureMode" -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ''

if (-not `$pidSupported) {
  Write-Host 'WARNING: --pid not supported, using full capture + PS filter' -ForegroundColor Yellow
}

Write-Host 'Streaming logs (auto re-sync on app restart)...' -ForegroundColor Cyan
Write-Host 'Press Ctrl+C to stop.' -ForegroundColor Gray
Write-Host ''

# Main loop with PID monitoring
while (`$true) {
  if (`$pidSupported) {
    # Native PID filtering
    `$proc = Start-Process -FilePath 'adb' -ArgumentList "`$adbSerial logcat --pid=`$currentPid -v time" -NoNewWindow -PassThru -RedirectStandardOutput "`$env:TEMP\logcat_pid_`$currentPid.tmp"

    # Monitor PID while streaming
    while (-not `$proc.HasExited) {
      # Check if PID still exists
      `$checkPid = adb `$adbSerial shell pidof -s `$packageName 2>`$null
      if (`$checkPid) { `$checkPid = `$checkPid.Trim() }

      if (-not `$checkPid) {
        Write-Host ''
        Write-Host '>>> APP STOPPED - waiting for restart...' -ForegroundColor Yellow
        Stop-Process -Id `$proc.Id -Force -ErrorAction SilentlyContinue

        `$newPid = Get-AppPid -Timeout `$pidTimeout
        if (`$newPid) {
          `$currentPid = `$newPid
          Write-Host ">>> APP RESTARTED - NEW PID=`$currentPid" -ForegroundColor Green
          ">>> PID_CHANGE: `$currentPid at `$(Get-Date -Format 'HH:mm:ss')" | Out-File -Append -Encoding utf8 -FilePath `$logFile
          break
        } else {
          Write-Host '>>> FAIL: App did not restart within timeout' -ForegroundColor Red
          ">>> FAIL: App did not restart" | Out-File -Append -Encoding utf8 -FilePath `$logFile
          exit 1
        }
      } elseif (`$checkPid -ne `$currentPid) {
        Write-Host ''
        Write-Host ">>> PID CHANGED: `$currentPid -> `$checkPid" -ForegroundColor Yellow
        Stop-Process -Id `$proc.Id -Force -ErrorAction SilentlyContinue
        `$currentPid = `$checkPid
        ">>> PID_CHANGE: `$currentPid at `$(Get-Date -Format 'HH:mm:ss')" | Out-File -Append -Encoding utf8 -FilePath `$logFile
        break
      }

      # Read and display temp file content, append to main log
      if (Test-Path "`$env:TEMP\logcat_pid_`$currentPid.tmp") {
        Get-Content "`$env:TEMP\logcat_pid_`$currentPid.tmp" -Wait -Tail 0 2>`$null | ForEach-Object {
          `$_ | Out-File -Append -Encoding utf8 -FilePath `$logFile
          Write-Host `$_
        }
      }
      Start-Sleep -Milliseconds 500
    }
  } else {
    # Fallback: full capture with PS filtering
    adb `$adbSerial logcat -v time 2>&1 | ForEach-Object {
      # Check PID periodically (every 100 lines approx)
      `$checkPid = adb `$adbSerial shell pidof -s `$packageName 2>`$null
      if (`$checkPid) { `$checkPid = `$checkPid.Trim() }

      if (`$checkPid -and `$checkPid -ne `$currentPid) {
        Write-Host ">>> PID CHANGED: `$currentPid -> `$checkPid" -ForegroundColor Yellow
        `$currentPid = `$checkPid
        ">>> PID_CHANGE: `$currentPid at `$(Get-Date -Format 'HH:mm:ss')" | Out-File -Append -Encoding utf8 -FilePath `$logFile
      }

      # Filter by PID in the log line (format: "MM-DD HH:MM:SS.mmm  PID  TID ...")
      if (`$_ -match "^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+`$currentPid\s+") {
        `$_ | Out-File -Append -Encoding utf8 -FilePath `$logFile
        Write-Host `$_
      }
    }
  }
}
"@
      Start-Process -FilePath $shell -ArgumentList "-NoExit", "-Command", $logcatScript | Out-Null
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
