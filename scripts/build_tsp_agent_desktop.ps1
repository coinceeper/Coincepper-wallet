$ErrorActionPreference = "Stop"
# این اسکریپت در .../cc flutter/scripts است؛ ریشهٔ اپ = cc flutter، ریشهٔ مخزن = یک سطح بالاتر (Admin).
$FlutterRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$RepoRoot = Split-Path -Parent $FlutterRoot
$Ag = Join-Path $RepoRoot "agent\cmd\agent"
$OutDir = Join-Path $FlutterRoot "sidecar"
$null = New-Item -ItemType Directory -Force -Path $OutDir
# اگر در شل مقدار GOOS=linux مانده باشد، خروجی .exe اشتباهی لینوکسی می‌شود — همیشه ویندوز amd64.
$env:GOOS = "windows"
$env:GOARCH = "amd64"
$env:CGO_ENABLED = "0"
$Dest = Join-Path $OutDir "tsp_agent.exe"
Push-Location $Ag
try {
  & go build -ldflags "-s -w" -o $Dest .
  if ($LASTEXITCODE -ne 0) {
    throw "go build failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
}
if (-not (Test-Path -LiteralPath $Dest)) {
  throw "Output missing: $Dest"
}
Write-Host "OK: $Dest (copy next to CoinCeeper.exe; CMake install picks this path when present)"
