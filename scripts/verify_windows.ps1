$ErrorActionPreference = 'Stop'
Write-Host 'E-Campus local verification' -ForegroundColor Cyan
Write-Host 'Run this script from the project root. It does not deploy Firebase resources.'

flutter --version
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }

dart format --output=none --set-exit-if-changed lib test
if ($LASTEXITCODE -ne 0) { Write-Warning 'Dart formatting differs. Run: dart format lib test' }

flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze reported issues.' }

flutter test
if ($LASTEXITCODE -ne 0) { throw 'flutter test failed.' }

flutter build apk --debug
if ($LASTEXITCODE -ne 0) { throw 'Flutter APK build failed.' }

$apk = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path $apk)) {
  $apk = Join-Path $PSScriptRoot '..\android\app\build\outputs\flutter-apk\app-debug.apk'
}
if (Test-Path $apk) { Write-Host "APK created: $apk" -ForegroundColor Green }
else { Write-Warning 'Build command completed but APK path was not found; inspect Flutter build output.' }
