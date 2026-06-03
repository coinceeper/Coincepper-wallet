# Creates a self-signed code-signing PFX for local MSIX builds.
# Subject MUST match msix_config.publisher in pubspec.yaml (CoinCeeper).
#
# Usage (PowerShell, from repo root = cc flutter):
#   .\scripts\msix\New-CoinCeeperMsixCert.ps1
#
# Then:
#   flutter build windows --release
#   dart run msix:create --certificate-password "<same password>"
#
# When msix asks to install the certificate, choose Y once (needs Administrator)
# so Trusted Root trusts your dev certificate on this PC.
#
# For end users / other PCs: distribute windows/msix_signing.cer and have them
# install it to "Trusted Root Certification Authorities" (local machine), or
# buy a standard code signing certificate from a public CA.

$ErrorActionPreference = 'Stop'

$subject = 'CN=CoinCeeper ADL, O=CoinCeeper, C=US'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$winDir = Join-Path $repoRoot 'windows'
if (-not (Test-Path $winDir)) {
  New-Item -ItemType Directory -Path $winDir | Out-Null
}
$pfxPath = Join-Path $winDir 'msix_signing.pfx'
$cerPath = Join-Path $winDir 'msix_signing.cer'
if (Test-Path $pfxPath) { Remove-Item $pfxPath -Force }
if (Test-Path $cerPath) { Remove-Item $cerPath -Force }

$p1 = Read-Host 'PFX password (min 6 chars)' -AsSecureString
$p2 = Read-Host 'Confirm PFX password' -AsSecureString
$b1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p1))
$b2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($p2))
if ($b1 -ne $b2) { throw 'Passwords do not match.' }
if ($b1.Length -lt 6) { throw 'Password too short.' }

$cert = New-SelfSignedCertificate `
  -Subject $subject `
  -Type CodeSigningCert `
  -KeyUsage DigitalSignature `
  -KeyAlgorithm RSA `
  -KeyLength 2048 `
  -HashAlgorithm SHA256 `
  -CertStoreLocation 'Cert:\CurrentUser\My' `
  -NotAfter (Get-Date).AddYears(5)

try {
  $secure = ConvertTo-SecureString -String $b1 -AsPlainText -Force
  Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secure | Out-Null
  Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT | Out-Null
}
finally {
  $b1 = $null
  $b2 = $null
  Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
}

Write-Host ""
Write-Host "Created:" -ForegroundColor Green
Write-Host "  $pfxPath"
Write-Host "  $cerPath"
Write-Host ""
Write-Host 'Next: dart run msix:create --certificate-password "<your password>"' -ForegroundColor Cyan
