# توسعه سریع CoinCeeper -- پرتابل / Debug
# Usage:
#   .\scripts\dev_run_portable.ps1            # اجراي EXE Debug موجود (سريع)
#   .\scripts\dev_run_portable.ps1 -HotReload  # flutter run -d windows (Hot Reload)
#   .\scripts\dev_run_portable.ps1 -Build      # بيلد Debug و سپس اجرا

param(
  [switch]$HotReload,
  [switch]$Build,
  [switch]$Portable
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $ROOT

$DEBUG_EXE    = "build\windows\x64\runner\Debug\CoinCeeper.exe"
$RELEASE_EXE  = "build\windows\x64\runner\Release\CoinCeeper.exe"
$PORTABLE_DIR = "build\portable"

# پيدا كردن Flutter SDK
function Find-Flutter {
  $candidates = @(
    "$env:USERPROFILE\flutter\bin\flutter.bat",
    "$env:FLUTTER_ROOT\bin\flutter.bat",
    "$env:LOCALAPPDATA\flutter\bin\flutter.bat",
    "C:\tools\flutter\bin\flutter.bat",
    "C:\flutter\bin\flutter.bat"
  )
  $which = Get-Command "flutter.bat" -ErrorAction SilentlyContinue
  if ($which) { return $which.Source }

  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }

  $resolved = Get-Command "flutter" -ErrorAction SilentlyContinue
  if ($resolved) { return $resolved.Source }

  return $null
}

$FLUTTER = Find-Flutter
if (-not $FLUTTER) {
  Write-Host "`n[خطا] Flutter SDK يافت نشد." -ForegroundColor Red
  Write-Host "   مسير flutter را در PATH تنظيم کنيد." -ForegroundColor Yellow
  exit 1
}
Write-Host "[OK] Flutter SDK: $FLUTTER" -ForegroundColor Green

# حالت Hot Reload
if ($HotReload) {
  Write-Host @"

==============================================
   [حالت Hot Reload]
   - برنامه در تسک بار نمايش داده مي شود
   - ترمينال باز مي ماند
   - براي اعمال تغييرات: دکمه r را بزنيد
   - براي خروج: دکمه q يا Ctrl+C
==============================================

"@ -ForegroundColor Cyan

  & $FLUTTER run -d windows
  exit $LASTEXITCODE
}

# حالت Portable (پرتابل)
if ($Portable -or (-not $HotReload -and -not $Build)) {
  Write-Host @"

==============================================
   [حالت پرتابل (Portable)]
   - برنامه مستقيما اجرا مي شود (بدون بيلد)
   - در تسک بار نمايش داده مي شود
   - تغييرات Dart: ابتدا با -Build اجرا کنيد
==============================================

"@ -ForegroundColor Cyan
}

# بيلد Debug (در صورت نياز)
if ($Build -or -not (Test-Path $DEBUG_EXE)) {
  if (-not $Build) {
    Write-Host "`n[INFO] EXE Debug يافت نشد -- در حال بيلد..." -ForegroundColor Yellow
  } else {
    Write-Host "`n[INFO] در حال بيلد Debug (سريع تر از Release)..." -ForegroundColor Yellow
  }

  & $FLUTTER pub get
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[خطا] flutter pub get ناموفق" -ForegroundColor Red
    exit 1
  }

  & $FLUTTER build windows --debug
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[خطا] بيلد ناموفق" -ForegroundColor Red
    exit 1
  }
  Write-Host "[OK] بيلد Debug با موفقيت انجام شد." -ForegroundColor Green
}

# اجراي مستقيم EXE Debug
if (Test-Path $DEBUG_EXE) {
  Write-Host "`n[در حال اجرا] CoinCeeper (Debug)..." -ForegroundColor Cyan
  Write-Host "   مسير: $DEBUG_EXE" -ForegroundColor Gray

  $exePath = Join-Path $ROOT $DEBUG_EXE
  $workDir = Split-Path $exePath -Parent

  Start-Process -FilePath $exePath -WorkingDirectory $workDir

  Write-Host @"

   [OK] برنامه در حال اجراست.
   - در Taskbar ويندوز قابل مشاهده است.
   - براي اعمال تغييرات جديد:
     1) برنامه را ببنديد
     2) اسکريپت را با -Build اجرا کنيد:
        .\scripts\dev_run_portable.ps1 -Build

   [نکته] گزينه Hot Reload (تغييرات لحظه اي):
        .\scripts\dev_run_portable.ps1 -HotReload
      سپس در ترمينال دکمه r را بزنيد.
"@ -ForegroundColor Green

} else {
  Write-Host "`n[خطا] فايل $DEBUG_EXE يافت نشد." -ForegroundColor Red
  exit 1
}
