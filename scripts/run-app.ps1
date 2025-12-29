[CmdletBinding()]
param(
  [switch]$Fast,
  [switch]$NoBuild,
  [switch]$UnlockAll
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")
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
Write-Host "BUILD_STAMP=$stamp"

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
  flutter clean
  flutter pub get
} else {
  Write-Host "FAST_MODE=1 (skipping flutter clean/pub get)"
}

try {
  adb reverse tcp:8000 tcp:8000 | Out-Null
} catch {
}

$flutterArgs = @("--dart-define=ENV=dev", "--dart-define=BUILD_STAMP=$stamp")
if ($UnlockAll) {
  $flutterArgs += "--dart-define=DEV_UNLOCK_ALL=true"
}
if ($NoBuild) {
  $apkPath = Join-Path (Get-Location) "build\app\outputs\flutter-apk\app-debug.apk"
  if (Test-Path $apkPath) {
    $flutterArgs += "--no-build"
    Write-Host "NO_BUILD=1 (using existing APK)"
  } else {
    Write-Host "NO_BUILD requested but no APK found; running full build."
  }
}

flutter run @flutterArgs
