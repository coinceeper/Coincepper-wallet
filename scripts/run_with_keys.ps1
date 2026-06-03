#!/usr/bin/env pwsh
# ============================================================
# run_with_keys.ps1 — Flutter run/build with ALL API keys
# ============================================================
# این اسکریپت secrets/vm_api_keys.env را می‌خواند و تمام
# کلیدها را به صورت --dart-define به flutter پاس می‌دهد
#
# نحوه استفاده:
#
# ── اجرا (run) ──
#   cd cc flutter
#   powershell -File scripts/run_with_keys.ps1
#   powershell -File scripts/run_with_keys.ps1 -BuildMode release
#
# ── خروجی گرفتن (build) ──
#   powershell -File scripts/run_with_keys.ps1 -Command build -Target apk
#   powershell -File scripts/run_with_keys.ps1 -Command build -Target appbundle
#   powershell -File scripts/run_with_keys.ps1 -Command build -Target ios
#   powershell -File scripts/run_with_keys.ps1 -Command build -Target apk -BuildMode release
#   powershell -File scripts/run_with_keys.ps1 -Command build -Target apk -BuildMode release -Clean
#
# ============================================================

param(
    [string]$BuildMode = "debug",
    [string]$Command = "run",
    [string]$Target = "",
    [switch]$Clean,
    [string]$DeviceId = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Resolve-Path "$ScriptDir/.."
$EnvFile = "$RootDir/secrets/vm_api_keys.env"

if (-not (Test-Path $EnvFile)) {
    Write-Host "❌ فایل $EnvFile یافت نشد!" -ForegroundColor Red
    Write-Host "   لطفاً ابتدا کلیدها را در secrets/vm_api_keys.env قرار دهید" -ForegroundColor Yellow
    exit 1
}

# ── خواندن کلیدها از فایل env ──
$dartDefines = @()
$allKeys = @(
    # Explorer
    "ETHERSCAN_API_KEY", "BSCSCAN_API_KEY", "POLYGONSCAN_API_KEY",
    "AVALANCHE_API_KEY", "ARBITRUMSCAN_API_KEY",
    # Tron (3 keys)
    "TRONGRID_API_KEY_1", "TRONGRID_API_KEY_2", "TRONGRID_API_KEY_3",
    # RPC Pool
    "DRPC_API_KEY", "ANKR_API_KEY",
    "CHAINSTACK_ETH_TOKEN", "CHAINSTACK_BTC_TOKEN",
    # Tenderly per-chain
    "TENDERLY_API_KEY",
    "TENDERLY_ETH_RPC_URL", "TENDERLY_ETH_WSS_URL",
    "TENDERLY_POLYGON_RPC_URL", "TENDERLY_POLYGON_WSS_URL",
    "TENDERLY_ARBITRUM_RPC_URL", "TENDERLY_ARBITRUM_WSS_URL",
    "TENDERLY_AVALANCHE_RPC_URL", "TENDERLY_AVALANCHE_WSS_URL",
    # Etox per-chain
    "ETOX_API_KEY",
    "ETOX_ETH_RPC_URL", "ETOX_ETH_WSS_URL",
    "ETOX_ARB_RPC_URL", "ETOX_ARB_WSS_URL",
    "ETOX_POLYGON_RPC_URL", "ETOX_POLYGON_WSS_URL",
    # BlockPI per-chain
    "BLOCKPI_ETH_RPC_URL", "BLOCKPI_ETH_WSS_URL",
    "BLOCKPI_POLYGON_RPC_URL", "BLOCKPI_POLYGON_WSS_URL",
    "BLOCKPI_ARBITRUM_RPC_URL", "BLOCKPI_ARBITRUM_WSS_URL",
    "BLOCKPI_BSC_RPC_URL", "BLOCKPI_BSC_WSS_URL",
    "BLOCKPI_AVALANCHE_RPC_URL", "BLOCKPI_AVALANCHE_WSS_URL",
    "BLOCKPI_BTC_RPC_URL",
    # Solana
    "SOLANA_RPC_URL", "HELIUS_API_KEY",
    # Polkadot (7 keys)
    "SUBSCAN_API_KEY_1", "SUBSCAN_API_KEY_2", "SUBSCAN_API_KEY_3",
    "SUBSCAN_API_KEY_4", "SUBSCAN_API_KEY_5", "SUBSCAN_API_KEY_6",
    "SUBSCAN_API_KEY_7",
    # Bitcoin (6 keys)
    "BLOCKCYPHER_API_KEY_1", "BLOCKCYPHER_API_KEY_2", "BLOCKCYPHER_API_KEY_3",
    "BLOCKCYPHER_API_KEY_4", "BLOCKCYPHER_API_KEY_5", "BLOCKCYPHER_API_KEY_6",
    # Price
    "COINGECKO_API_KEY",
    # Build-time secrets
    "CLIENT_HMAC_SECRET", "TLS_PIN_SHA256"
)

Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"').Trim("'")
        if ($key -in $allKeys -and $value -and -not $value.StartsWith("YOUR_")) {
            $dartDefines += "--dart-define=$key=$value"
        }
    }
}

if ($dartDefines.Count -eq 0) {
    Write-Host "❌ هیچ کلید معتبری در $EnvFile یافت نشد!" -ForegroundColor Red
    Write-Host "   لطفاً مقادیر 'YOUR_*' را با کلیدهای واقعی جایگزین کنید" -ForegroundColor Yellow
    exit 1
}

# ── ساخت دستور flutter ──
$flutterCmd = "flutter"
$flutterArgs = @()

if ($Command -eq "build") {
    # ── flutter build ──
    $flutterArgs += "build"
    if ($Target) {
        $flutterArgs += $Target
    } else {
        Write-Host "❌ برای build باید -Target مشخص کنید (apk, appbundle, ios, ...)" -ForegroundColor Red
        exit 1
    }
    if ($BuildMode -eq "release") {
        $flutterArgs += "--release"
    } elseif ($BuildMode -eq "profile") {
        $flutterArgs += "--profile"
    }
    if ($Clean) {
        $flutterArgs += "--clean"
    }
    $flutterArgs += $dartDefines

    Write-Host "`n📦 flutter build $Target با $($dartDefines.Count) کلید:" -ForegroundColor Green
} else {
    # ── flutter run ──
    if ($BuildMode -eq "release") {
        $flutterArgs += "run"
        $flutterArgs += "--release"
    } elseif ($BuildMode -eq "profile") {
        $flutterArgs += "run"
        $flutterArgs += "--profile"
    } else {
        $flutterArgs += "run"
    }
    if ($Clean) {
        $flutterArgs += "--clean"
    }
    if ($DeviceId) {
        $flutterArgs += "-d"
        $flutterArgs += $DeviceId
    }
    $flutterArgs += $dartDefines

    Write-Host "`n🚀 flutter run با $($dartDefines.Count) کلید:" -ForegroundColor Green
}

$dartDefines | ForEach-Object {
    $name = $_.Split("=")[0].Replace("--dart-define=", "")
    Write-Host "   ✅ $name" -ForegroundColor Cyan
}
Write-Host ""

$fullCmd = "$flutterCmd $($flutterArgs -join ' ')"
Write-Host "📌 دستور: $fullCmd" -ForegroundColor Gray
Write-Host ""

# اجرای دستور
Invoke-Expression $fullCmd
