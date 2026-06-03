# ايجاد کپي پرتابل از CoinCeeper
# ──────────────────────────────────
# اين اسکريپت يک کپي کامل از EXE و DLL هاي مورد نياز را
# در پوشه build\portable\CoinCeeper\ مي سازد.
# مي توانيد اين پوشه را به هر جايي کپی کنيد و اجرا کنيد.

param(
  [string]$OutputDir = "",      # مسير مقصد (اختياري)
  [switch]$UseRelease,          # از EXE Release استفاده کن (پيش فرض: Debug)
  [switch]$BuildFirst           # اول بيلد کن، بعد کپي کن
)

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $ROOT

$FLUTTER = "$env:USERPROFILE\flutter\bin\flutter.bat"
if (-not (Test-Path $FLUTTER)) {
  $FLUTTER = (Get-Command "flutter" -ErrorAction SilentlyContinue).Source
}

if ($BuildFirst) {
  if ($UseRelease) {
    Write-Host "[بيلد] Release..." -ForegroundColor Yellow
    & $FLUTTER build windows --release
  } else {
    Write-Host "[بيلد] Debug..." -ForegroundColor Yellow
    & $FLUTTER build windows --debug
  }
  if ($LASTEXITCODE -ne 0) { exit 1 }
}

$MODE = if ($UseRelease) { "Release" } else { "Debug" }
$SRC  = "build\windows\x64\runner\$MODE"
$DST  = if ($OutputDir) { $OutputDir } else { "build\portable\CoinCeeper" }

if (-not (Test-Path $SRC)) {
  Write-Host "[خطا] پوشه $SRC يافت نشد. ابتدا با -BuildFirst بيلد کنيد." -ForegroundColor Red
  exit 1
}

# ايجاد پوشه مقصد
if (Test-Path $DST) { Remove-Item "$DST\*" -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $DST -Force | Out-Null

# کپي کردن همه فايل ها به جز پوشه هاي CMake و فايل هاي موقت
Write-Host "[کپي] در حال کپي کردن فايل ها..." -ForegroundColor Cyan
Copy-Item "$SRC\*" $DST -Recurse -Force -Exclude @("*.exp", "*.ilk", "*.lib", "*.pdb", "*.recipe", "*.tlog", "obj")

# حذف پوشه obj اگر کپی شده باشد
if (Test-Path "$DST\obj") { Remove-Item "$DST\obj" -Recurse -Force }

$fileCount = (Get-ChildItem $DST -Recurse -File).Count
$totalSize = (Get-ChildItem $DST -Recurse -File | Measure-Object -Property Length -Sum).Sum
$sizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Host @"

══════════════════════════════════════════════
   [موفق] کپي پرتابل ايجاد شد!
══════════════════════════════════════════════

   مسير: $DST
   حالت: $MODE
   تعداد فايل: $fileCount
   حجم کل: $sizeMB MB

   فايل اصلي: $DST\CoinCeeper.exe

   نکته: اين پوشه کاملا پرتابل است.
   مي توانيد آن را به هر جايي (حتی USB) کپی کنيد.

   براي اجراي سريع:
        $DST\CoinCeeper.exe

   براي به روز رساني (بعد از تغيير کد):
        .\scripts\create_portable_copy.ps1 -BuildFirst

"@ -ForegroundColor Green
