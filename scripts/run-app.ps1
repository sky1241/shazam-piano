[CmdletBinding()]
param(
  [switch]$Fast,
  [switch]$NoBuild,
  [switch]$UnlockAll,
  [string]$DeviceSerial,
  [switch]$IUnderstandStaleRisk
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")

# Auto-detect package (applicationId > namespace) - FAIL-CLOSED
function Get-AndroidPackageInfo {
  param([string]$RepoRoot)
  $result = @{ ApplicationId = $null; Namespace = $null; Effective = $null }

  $gradleKts = Join-Path $RepoRoot "app\android\app\build.gradle.kts"
  if (Test-Path $gradleKts) {
    $content = Get-Content $gradleKts -Raw
    if ($content -match 'applicationId\s*=\s*"([^"]+)"') { $result.ApplicationId = $Matches[1] }
    if ($content -match 'namespace\s*=\s*"([^"]+)"') { $result.Namespace = $Matches[1] }
  }

  $gradle = Join-Path $RepoRoot "app\android\app\build.gradle"
  if (Test-Path $gradle) {
    $content = Get-Content $gradle -Raw
    if (-not $result.ApplicationId -and $content -match 'applicationId\s+[''"]([^''"]+)[''"]') { $result.ApplicationId = $Matches[1] }
    if (-not $result.Namespace -and $content -match 'namespace\s+[''"]([^''"]+)[''"]') { $result.Namespace = $Matches[1] }
  }

  $result.Effective = if ($result.ApplicationId) { $result.ApplicationId } elseif ($result.Namespace) { $result.Namespace } else { $null }
  return $result
}

$pkgInfo = Get-AndroidPackageInfo -RepoRoot $repoRoot
if (-not $pkgInfo.Effective) {
  Write-Host ""
  Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
  Write-Host "  FAIL: NO PACKAGE DETECTED" -ForegroundColor Red
  Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
  Write-Host "Check app/android/app/build.gradle.kts for applicationId" -ForegroundColor Yellow
  exit 1
}
$packageName = $pkgInfo.Effective
Set-Location $repoRoot

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$sha = "nogit"
if (Get-Command git -ErrorAction SilentlyContinue) {
  try {
    $sha = (git rev-parse --short HEAD).Trim()
  } catch {
    $sha = "nogit"
  }
}

$stamp = "$sha-$timestamp"
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  BUILD_STAMP = $stamp" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

$defaultGradleJvmArgs = "-Xmx2048m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=256m -Dfile.encoding=UTF-8"
if ($env:ORG_GRADLE_JVMARGS) {
  $gradleJvmArgs = $env:ORG_GRADLE_JVMARGS
} else {
  $gradleJvmArgs = $defaultGradleJvmArgs
  $env:ORG_GRADLE_JVMARGS = $gradleJvmArgs
}
$gradleOpts = "-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dorg.gradle.workers.max=1"
if ($env:GRADLE_OPTS) {
  $env:GRADLE_OPTS = "$env:GRADLE_OPTS $gradleOpts"
} else {
  $env:GRADLE_OPTS = $gradleOpts
}
Write-Host "GRADLE_JVMARGS=$gradleJvmArgs"
Write-Host "GRADLE_OPTS=$env:GRADLE_OPTS"

$defaultDartVmOptions = "--old_gen_heap_size=1024"
if ($env:DART_VM_OPTIONS) {
  $dartVmOptions = $env:DART_VM_OPTIONS
} else {
  $dartVmOptions = $defaultDartVmOptions
  $env:DART_VM_OPTIONS = $dartVmOptions
}
if ($env:DART_TOOL_VM_OPTIONS) {
  $dartToolVmOptions = $env:DART_TOOL_VM_OPTIONS
} else {
  $dartToolVmOptions = $dartVmOptions
  $env:DART_TOOL_VM_OPTIONS = $dartToolVmOptions
}
Write-Host "DART_VM_OPTIONS=$env:DART_VM_OPTIONS"
Write-Host "DART_TOOL_VM_OPTIONS=$env:DART_TOOL_VM_OPTIONS"

Set-Location (Join-Path $repoRoot "app")
if (-not $Fast) {
  # Uninstall APK first to avoid cache issues
  try {
    Write-Host "Uninstalling previous APK ($packageName)..."
    if ($DeviceSerial) {
      adb -s $DeviceSerial uninstall $packageName 2>$null | Out-Null
    } else {
      adb uninstall $packageName 2>$null | Out-Null
    }
  } catch {
    Write-Host "No previous APK found (or adb not available)"
  }
  flutter clean
  flutter pub get
}
# Note: -Fast warning is displayed later in the PROOF BLOCK section

# ============================================================
# DEVICE VALIDATION (FAIL-CLOSED IF AMBIGUOUS)
# ============================================================
$adbSerialArg = ""
if ($DeviceSerial) {
  $adbSerialArg = "-s $DeviceSerial"
  Write-Host "DEVICE_SERIAL=$DeviceSerial (from dev.ps1)" -ForegroundColor Green
} else {
  # Check for multiple devices if no serial provided
  $deviceLines = adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "(\S+)\s+device$" }
  $deviceCount = ($deviceLines | Measure-Object).Count
  if ($deviceCount -eq 0) {
    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "  FAIL: NO DEVICE CONNECTED" -ForegroundColor Red
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    exit 1
  } elseif ($deviceCount -gt 1) {
    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "  FAIL: MULTIPLE DEVICES ($deviceCount) - NO SERIAL PROVIDED" -ForegroundColor Red
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host ""
    adb devices
    Write-Host ""
    Write-Host "Use dev.ps1 or set: `$env:ANDROID_SERIAL" -ForegroundColor Yellow
    exit 1
  } else {
    # Single device, extract serial
    if ($deviceLines -match "(\S+)\s+device$") {
      $DeviceSerial = $Matches[1]
      $adbSerialArg = "-s $DeviceSerial"
    }
    Write-Host "DEVICE_SERIAL=$DeviceSerial (auto-detected)" -ForegroundColor Green
  }
}

try {
  Invoke-Expression "adb $adbSerialArg reverse tcp:8000 tcp:8000" | Out-Null
} catch {
}

# APK path for proof
$apkPath = Join-Path (Get-Location) "build\app\outputs\flutter-apk\app-debug.apk"

$flutterArgs = @("--dart-define=ENV=dev", "--dart-define=BUILD_STAMP=$stamp")
if ($UnlockAll) {
  $flutterArgs += "--dart-define=DEV_UNLOCK_ALL=true"
}

# -Fast warning (non-blocking)
if ($Fast) {
  Write-Host ""
  Write-Host "=============================================" -ForegroundColor Yellow
  Write-Host "  WARNING: -Fast MODE (caches may be stale)" -ForegroundColor Yellow
  Write-Host "=============================================" -ForegroundColor Yellow
  Write-Host "  Skipping flutter clean/pub get." -ForegroundColor Yellow
  Write-Host "  Native code changes may not be recompiled." -ForegroundColor Yellow
  Write-Host ""
}

# -NoBuild FAIL-CLOSED
if ($NoBuild) {
  if (Test-Path $apkPath) {
    $apkInfo = Get-Item $apkPath
    $apkAge = (Get-Date) - $apkInfo.LastWriteTime
    Write-Host ""
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "  FAIL: -NoBuild MODE = STALE BUILD GUARANTEED" -ForegroundColor Red
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host ""
    Write-Host "  APK Path     : $apkPath" -ForegroundColor Yellow
    Write-Host "  APK Modified : $($apkInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Yellow
    Write-Host "  APK Age      : $([math]::Round($apkAge.TotalMinutes, 1)) minutes ago" -ForegroundColor Yellow
    Write-Host "  APK Size     : $([math]::Round($apkInfo.Length / 1MB, 2)) MB" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  THIS BUILD_STAMP : $stamp" -ForegroundColor Cyan
    Write-Host "  APK BUILD_STAMP  : DIFFERENT (embedded at build time)" -ForegroundColor Magenta
    Write-Host ""
    if (-not $IUnderstandStaleRisk) {
      Write-Host "  To proceed anyway, add: -IUnderstandStaleRisk" -ForegroundColor Yellow
      Write-Host ""
      exit 1
    } else {
      Write-Host "  -IUnderstandStaleRisk acknowledged. Proceeding..." -ForegroundColor Magenta
      $flutterArgs += "--no-build"
    }
  } else {
    Write-Host "NO_BUILD requested but no APK found; running full build."
  }
}

# Add device to flutter args
if ($DeviceSerial) {
  $flutterArgs += "-d"
  $flutterArgs += $DeviceSerial
}

# ============================================================
# PROOF BLOCK - SCREENSHOT THIS TO PROVE BUILD
# ============================================================
$apkTimestamp = "N/A (will be built)"
$apkSize = "N/A"
if (Test-Path $apkPath) {
  $apkInfo = Get-Item $apkPath
  $apkTimestamp = $apkInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
  $apkSize = "$([math]::Round($apkInfo.Length / 1MB, 2)) MB"
}

Write-Host ""
Write-Host "############################################################" -ForegroundColor Cyan
Write-Host "#                      PROOF BLOCK                         #" -ForegroundColor Cyan
Write-Host "############################################################" -ForegroundColor Cyan
Write-Host "  PROOF_BUILD_STAMP   = $stamp" -ForegroundColor White
Write-Host "  PROOF_GIT_SHA       = $sha" -ForegroundColor White
Write-Host "  PROOF_DEVICE_SERIAL = $DeviceSerial" -ForegroundColor White
Write-Host "  PROOF_APK_PATH      = $apkPath" -ForegroundColor White
Write-Host "  PROOF_APK_TIMESTAMP = $apkTimestamp" -ForegroundColor White
Write-Host "  PROOF_APK_SIZE      = $apkSize" -ForegroundColor White
Write-Host "  PROOF_FLUTTER_MODE  = debug" -ForegroundColor White
Write-Host "  PROOF_PACKAGE_APPID = $($pkgInfo.ApplicationId ?? 'N/A')" -ForegroundColor White
Write-Host "  PROOF_PACKAGE_NS    = $($pkgInfo.Namespace ?? 'N/A')" -ForegroundColor White
Write-Host "  PROOF_PACKAGE_EFF   = $packageName" -ForegroundColor White
Write-Host "############################################################" -ForegroundColor Cyan
Write-Host ""

flutter run @flutterArgs
