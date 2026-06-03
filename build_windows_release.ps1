# Windows release build: clean, flutter build (MSVC), MSIX.
# Run from this folder:  powershell -ExecutionPolicy Bypass -File .\build_windows_release.ps1
# If build\ is locked: run from a shell whose cwd is not under build\; close Explorer
# under Release; pause AV on this folder. Do not have flutter run or the app open.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

function Stop-HardProcessById {
  param(
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [string]$Reason = "",
    [int]$Depth = 0
  )
  if ($Depth -gt 8) { return }
  if ($ProcessId -le 4) { return }
  if ($ProcessId -eq $PID) { return }
  $alive = $null
  try { $alive = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue } catch { }
  if (-not $alive) { return }
  $tag = if ($Reason) { " ($Reason)" } else { "" }
  Write-Host "Force-stop PID $ProcessId$tag" -ForegroundColor Yellow
  $tkOut = cmd /c "taskkill /F /PID $ProcessId /T 2>&1"
  $tk = $LASTEXITCODE
  if ($tk -ne 0 -and $tkOut) {
    Write-Host "  taskkill: $tkOut" -ForegroundColor DarkYellow
  }
  Start-Sleep -Milliseconds 600
  try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch { }
  Start-Sleep -Milliseconds 400
  $chk = $null
  try { $chk = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue } catch { }
  if (-not $chk) { return }

  # Access denied on child: stop parent first when it is a normal host (not Explorer / session services)
  $noKillParent = @(
    "explorer.exe", "csrss.exe", "winlogon.exe", "services.exe", "lsass.exe", "svchost.exe",
    "Registry", "System", "Idle", "Secure System", "smss.exe", "fontdrvhost.exe", "dwm.exe",
    "Code.exe", "Cursor.exe", "devenv.exe", "ServiceHub.Host.exe", "ServiceHub.VSDetouredHost.exe"
  )
  try {
    $row = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($row) {
      $ppid = [int]$row.ParentProcessId
      if ($ppid -gt 4 -and $ppid -ne $PID) {
        $prow = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ppid" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($prow -and ($noKillParent -notcontains $prow.Name)) {
          Write-Host "  Retrying via parent PID $ppid ($($prow.Name))..." -ForegroundColor Yellow
          Stop-HardProcessById -ProcessId $ppid -Reason "parent of PID $ProcessId" -Depth ($Depth + 1)
          Start-Sleep -Milliseconds 500
          $tkOut2 = cmd /c "taskkill /F /PID $ProcessId /T 2>&1"
          if ($LASTEXITCODE -ne 0 -and $tkOut2) {
            Write-Host "  taskkill (retry): $tkOut2" -ForegroundColor DarkYellow
          }
          Start-Sleep -Milliseconds 500
          try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch { }
        }
        elseif ($prow -and ($noKillParent -contains $prow.Name)) {
          Write-Host "  Parent is $($prow.Name); end the app from Task Manager or run this script as Administrator." -ForegroundColor DarkYellow
        }
      }
    }
  } catch { }

  try {
    $chk2 = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($chk2) {
      Write-Host "  PID $ProcessId still running (taskkill exit $tk). Try Task Manager or run this shell as Administrator." -ForegroundColor Red
    }
  } catch { }
}

function Stop-BuildLockers {
  $release = Join-Path $root "build\windows\x64\runner\Release"
  $rootLower = $root.ToLowerInvariant()
  $rootWithSep = if ($rootLower.EndsWith("\")) { $rootLower } else { $rootLower + "\" }
  $relLower = if (Test-Path -LiteralPath $release) { $release.ToLowerInvariant() } else { "" }
  $relWithSep = if ([string]::IsNullOrEmpty($relLower)) { "" } elseif ($relLower.EndsWith("\")) { $relLower } else { $relLower + "\" }
  $releaseMarker = "build\windows\x64\runner\release"

  # 1) Windows app EXE(s) — CoinCeeper is current BINARY_NAME; my_flutter_app may remain from older builds
  foreach ($im in @("CoinCeeper.exe", "my_flutter_app.exe")) {
    cmd /c "taskkill /F /IM $im /T 1>nul 2>nul" | Out-Null
  }
  Start-Sleep -Milliseconds 400
  $flutterPids = New-Object "System.Collections.Generic.HashSet[int]"
  foreach ($procBase in @("CoinCeeper", "my_flutter_app")) {
    try {
      Get-Process -Name $procBase -ErrorAction SilentlyContinue | ForEach-Object { [void]$flutterPids.Add($_.Id) }
    } catch { }
  }
  foreach ($exeFilter in @("CoinCeeper.exe", "my_flutter_app.exe")) {
    try {
      Get-CimInstance -ClassName Win32_Process -Filter "Name = '$exeFilter'" -ErrorAction SilentlyContinue | ForEach-Object {
        [void]$flutterPids.Add([int]$_.ProcessId)
      }
    } catch { }
  }
  foreach ($fp in $flutterPids) {
    Stop-HardProcessById -ProcessId $fp -Reason "Windows app (clean build)"
  }

  # 2) EXE path or command line under this project Release (DLL locks); path\ boundaries
  if (-not [string]::IsNullOrEmpty($relWithSep)) {
    try {
      Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
        $procId = $_.ProcessId
        $e = $_.ExecutablePath
        $c = $_.CommandLine
        $eOk = $false
        if (-not [string]::IsNullOrEmpty($e)) {
          $el = $e.ToLowerInvariant()
          if ($el -eq $relLower -or $el.StartsWith($relWithSep)) { $eOk = $true }
        }
        $cOk = $false
        if (-not [string]::IsNullOrEmpty($c)) {
          $cl = $c.ToLowerInvariant()
          if ($cl.Contains($relWithSep) -or ($cl.Contains($rootWithSep) -and $cl.Contains($releaseMarker))) { $cOk = $true }
        }
        if ($eOk -or $cOk) {
          $detail = if ($e) { $e } else { $c.Substring(0, [Math]::Min(120, $c.Length)) }
          Stop-HardProcessById -ProcessId $procId -Reason "Release build: $detail"
        }
      }
    } catch { }
  }

  # 3) Stuck build/tooling for this repo (zombie MSBuild, dart, flutter, etc.)
  $buildToolNames = @("MSBuild.exe", "cl.exe", "link.exe", "lib.exe", "bscmake.exe", "dartaotruntime.exe", "dart.exe", "flutter.exe")
  try {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
      if ($buildToolNames -notcontains $_.Name) { }
      else {
        $c = $_.CommandLine
        if (-not [string]::IsNullOrEmpty($c) -and $c.ToLowerInvariant().Contains($rootWithSep)) {
          Stop-HardProcessById -ProcessId $_.ProcessId -Reason "$($_.Name) (project build)"
        }
      }
    }
  } catch { }

  # 4) .Path when PowerShell can read it
  if (-not [string]::IsNullOrEmpty($relWithSep)) {
    try {
      Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          $pp = $_.Path
          if (-not [string]::IsNullOrEmpty($pp) -and $pp.ToLowerInvariant().StartsWith($relWithSep)) {
            Stop-HardProcessById -ProcessId $_.Id -Reason "locks Release: $pp"
          }
        } catch { }
      }
    } catch { }
  }

  Start-Sleep -Seconds 2
}

function Remove-FolderRobust {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$MaxAttempts = 8
  )
  if (-not (Test-Path -LiteralPath $Path)) { return $true }
  Write-Host ">>> Remove (with retries): $Path" -ForegroundColor Cyan
  for ($i = 0; $i -lt $MaxAttempts; $i++) {
    Stop-BuildLockers
    # Use cmd rmdir (stderr 2>nul) — avoids per-file "Access is denied" spam from Remove-Item
    $rdline = "rd /s /q " + '"' + $Path + '"' + " 2>nul & exit /b 0"
    $null = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $rdline -Wait -PassThru -NoNewWindow
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    $null = [System.GC]::Collect()
    Start-Sleep -Seconds 2
  }
  return $false
}

Write-Host ">>> Stopping processes that may lock build output..." -ForegroundColor Cyan
Stop-BuildLockers
Start-Sleep -Seconds 2

$buildPath = Join-Path $root "build"
$ephemPath = Join-Path $root "windows\flutter\ephemeral"

if (-not (Remove-FolderRobust -Path $buildPath)) {
  Write-Host ""
  Write-Host "ERROR: cannot delete folder:" -ForegroundColor Red
  Write-Host "  $buildPath"
  Write-Host "Close any app running from Release\ (or Explorer preview on that folder), then run again." -ForegroundColor Red
  Write-Host "If a PID keeps showing as still running, end it in Task Manager or re-run this script from an elevated PowerShell." -ForegroundColor Red
  exit 1
}

if (Test-Path -LiteralPath $ephemPath) {
  Write-Host ">>> Remove: $ephemPath" -ForegroundColor Cyan
  if (-not (Remove-FolderRobust -Path $ephemPath -MaxAttempts 4)) {
    Write-Host "WARN: could not remove ephemeral; continuing anyway." -ForegroundColor Yellow
  }
}

Write-Host ">>> flutter pub get" -ForegroundColor Cyan
& flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$vcX86 = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
$vcComm = "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
$vcPro = "$env:ProgramFiles\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
$vcvars = $null
if (Test-Path -LiteralPath $vcX86) { $vcvars = $vcX86 }
elseif (Test-Path -LiteralPath $vcComm) { $vcvars = $vcComm }
elseif (Test-Path -LiteralPath $vcPro) { $vcvars = $vcPro }
if (-not $vcvars) {
  Write-Host "ERROR: vcvars64.bat not found. Install VS 2022 Build Tools (C++)." -ForegroundColor Red
  exit 1
}

# Pass one string to cmd.exe - avoids && parse issues in older PowerShell
$cmdline = "call " + '"' + $vcvars + '"' + " && cd /d " + '"' + $root + '"' + " && flutter build windows --release"
Write-Host ">>> $cmdline" -ForegroundColor Cyan
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmdline -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -ne 0) {
  Write-Host ""
  Write-Host "Release build failed. If the log mentioned MSB3073, cmake_install, or Permission denied on runner\Release:" -ForegroundColor Yellow
  Write-Host "  Fully close CoinCeeper.exe / my_flutter_app.exe that were started from build\...\Release\, then run this script again." -ForegroundColor Yellow
  Write-Host "  Or use Task Manager (elevated if the app was Run as administrator)." -ForegroundColor Yellow
  Write-Host "To build into a separate folder while Release is locked:  flutter build windows --debug" -ForegroundColor Yellow
  Write-Host "  then run:  build\windows\x64\runner\Debug\CoinCeeper.exe" -ForegroundColor Yellow
  exit $proc.ExitCode
}

Write-Host ">>> dart run msix:create" -ForegroundColor Cyan
Set-Location $root
& dart run msix:create
if ($LASTEXITCODE -ne 0) {
  Write-Host "If signing failed, set in pubspec msix_config: sign_msix: false" -ForegroundColor Yellow
  exit $LASTEXITCODE
}

$msix = Join-Path $root "build\windows\installer\CoinCeeper_Installer.msix"
if (Test-Path -LiteralPath $msix) {
  Write-Host "OK. MSIX: $msix" -ForegroundColor Green
} else {
  Write-Host "Check build\windows\installer\ for the .msix" -ForegroundColor Yellow
}
exit 0
