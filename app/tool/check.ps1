[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$appRoot = Resolve-Path (Join-Path $scriptRoot "..")
Set-Location $appRoot

$formatPaths = @("lib", "test")
if (Test-Path "integration_test") {
  $formatPaths += "integration_test"
}
if (Test-Path "tool") {
  $formatPaths += "tool"
}

flutter pub get
dart format @formatPaths
flutter analyze
flutter test
