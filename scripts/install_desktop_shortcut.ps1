# نصب شورتکات CoinCeeper روي دسکتاپ
# ─────────────────────────────────
# اين اسکريپت يک شورتکات براي اجراي سريع برنامه
# روي دسکتاپ ويندوز ايجاد مي کند.

$ErrorActionPreference = "Stop"
$ROOT = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$BAT_PATH = Join-Path $ROOT "run_fast.bat"
$DESKTOP  = [Environment]::GetFolderPath("Desktop")
$SHORTCUT = Join-Path $DESKTOP "CoinCeeper (Portable).lnk"

if (-not (Test-Path $BAT_PATH)) {
  Write-Host "[خطا] فايل run_fast.bat يافت نشد." -ForegroundColor Red
  exit 1
}

$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($SHORTCUT)
$Shortcut.TargetPath = $BAT_PATH
$Shortcut.WorkingDirectory = $ROOT
$Shortcut.Description = "CoinCeeper - Portable Dev Mode"
$Shortcut.IconLocation = "$ROOT\windows\runner\resources\app_icon.ico, 0"
$Shortcut.Save()

Write-Host "[OK] شورتکات روي دسکتاپ ايجاد شد:" -ForegroundColor Green
Write-Host "    $SHORTCUT" -ForegroundColor Cyan
Write-Host ""
Write-Host "حالا مي توانيد از روي دسکتاپ برنامه را باز کنيد." -ForegroundColor Yellow
