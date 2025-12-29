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
flutter clean
flutter pub get

try {
  adb reverse tcp:8000 tcp:8000 | Out-Null
} catch {
}

flutter run --dart-define=ENV=dev --dart-define=BUILD_STAMP=$stamp
