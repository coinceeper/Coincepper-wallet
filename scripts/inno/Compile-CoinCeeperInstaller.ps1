# Compile CoinCeeper Inno Setup installer (requires Inno Setup 6).
$ErrorActionPreference = 'Stop'

function Find-InnoISCC {
  $paths = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 5\ISCC.exe",
    "$env:LocalAppData\Programs\Inno Setup 6\ISCC.exe"
  )
  foreach ($p in $paths) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }

  $cmd = Get-Command iscc.exe -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }

  $roots = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($root in $roots) {
    $apps = Get-ItemProperty $root -ErrorAction SilentlyContinue |
      Where-Object { $_.DisplayName -match 'Inno Setup' -and $_.InstallLocation }
    foreach ($a in $apps) {
      $exe = Join-Path $a.InstallLocation.TrimEnd('\') 'ISCC.exe'
      if (Test-Path -LiteralPath $exe) { return $exe }
    }
  }

  # Direct folders named like "Inno Setup 6" under Program Files
  foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if (-not $pf) { continue }
    foreach ($dir in Get-ChildItem -Path $pf -Directory -Filter '*Inno*' -ErrorAction SilentlyContinue) {
      $exe = Join-Path $dir.FullName 'ISCC.exe'
      if (Test-Path -LiteralPath $exe) { return $exe }
    }
  }

  return $null
}

function Find-WingetExe {
  foreach ($p in @(
      "$env:LocalAppData\Microsoft\WindowsApps\winget.exe",
      "$env:ProgramFiles\Microsoft\AppInstaller\winget.exe",
      "${env:ProgramFiles(x86)}\Microsoft\AppInstaller\winget.exe"
    )) {
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  return $null
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$iss = Join-Path $PSScriptRoot 'Coinceeper_Setup.iss'

if (-not (Test-Path (Join-Path $releaseDir 'CoinCeeper.exe'))) {
  Write-Host "Release build not found. Run first:" -ForegroundColor Yellow
  Write-Host "  cd `"$repoRoot`"" -ForegroundColor Cyan
  Write-Host "  flutter build windows --release" -ForegroundColor Cyan
  exit 1
}

$iscc = Find-InnoISCC
if (-not $iscc) {
  Write-Host "ISCC.exe not found - Inno Setup 6 is not installed (or not in a standard folder)." -ForegroundColor Red
  Write-Host ""

  $wg = Find-WingetExe
  if ($wg) {
    Write-Host "On your PC, winget exists but is not in PATH. Install Inno with:" -ForegroundColor Yellow
    Write-Host ('  & "' + $wg + '" install --id JRSoftware.InnoSetup -e --accept-package-agreements --accept-source-agreements') -ForegroundColor Cyan
    Write-Host ""
  }
  else {
    Write-Host "'winget' is missing or not installed. Easiest fix - manual installer:" -ForegroundColor Yellow
    Write-Host "  1) Open https://jrsoftware.org/isdl.php" -ForegroundColor Cyan
    Write-Host "  2) Download Inno Setup 6 (exe), Next → Next → Install (default folder)." -ForegroundColor White
    Write-Host "  3) Close this terminal, open a NEW PowerShell, run this script again." -ForegroundColor White
    Write-Host ""
    Write-Host "Optional - install App Installer / winget from Microsoft Store (Windows 10/11), then:" -ForegroundColor DarkGray
    Write-Host "  winget install --id JRSoftware.InnoSetup -e --accept-package-agreements --accept-source-agreements" -ForegroundColor DarkGray
    Write-Host ""
  }

  if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
    Write-Host "Chocolatey detected - alternative:" -ForegroundColor Yellow
    Write-Host "  choco install innosetup -y" -ForegroundColor Cyan
    Write-Host ""
  }

  Write-Host "Manual compile after install:" -ForegroundColor Yellow
  Write-Host "  Inno Setup Compiler > File > Open >" -ForegroundColor White
  Write-Host "    $((Join-Path $PSScriptRoot 'Coinceeper_Setup.iss'))" -ForegroundColor Cyan
  Write-Host "  Build > Compile" -ForegroundColor White
  exit 1
}

Write-Host "Using: $iscc" -ForegroundColor DarkGray
Push-Location $repoRoot
try {
  & $iscc $iss
} finally {
  Pop-Location
}
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}
$outDir = Join-Path $repoRoot 'build\windows\installer_inno'
Write-Host ""
Write-Host "Done. Output folder:" -ForegroundColor Green
Write-Host "  $outDir" -ForegroundColor Cyan
