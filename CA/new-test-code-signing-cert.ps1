[CmdletBinding()]
param(
    [string]$Name = "OneCloudDesk Test Code Signing",
    [string]$Password,
    [string]$OutDir,
    [switch]$PrintSecrets
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

if ([string]::IsNullOrWhiteSpace($Password)) {
    $Password = [Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Minimum 0 -Maximum 256 }))
}

$privateDir = Join-Path $OutDir "private"
New-Item -ItemType Directory -Force -Path $privateDir | Out-Null

$rootSubject = "CN=$Name Root CA"
$leafSubject = "CN=$Name Publisher"

$root = New-SelfSignedCertificate `
    -Type Custom `
    -Subject $rootSubject `
    -KeyAlgorithm RSA `
    -KeyLength 4096 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy Exportable `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyUsage CertSign, CRLSign, DigitalSignature `
    -TextExtension @("2.5.29.19={critical}{text}ca=TRUE&pathlength=0") `
    -NotAfter (Get-Date).AddYears(10)

$leaf = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $leafSubject `
    -Signer $root `
    -KeyAlgorithm RSA `
    -KeyLength 3072 `
    -HashAlgorithm SHA256 `
    -KeyExportPolicy Exportable `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter (Get-Date).AddYears(3)

$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$rootCer = Join-Path $OutDir "oneclouddesk-test-root-ca.cer"
$leafCer = Join-Path $OutDir "oneclouddesk-test-code-signing.cer"
$pfx = Join-Path $privateDir "oneclouddesk-test-code-signing.pfx"
$secretFile = Join-Path $privateDir "github-secrets.txt"

Export-Certificate -Cert $root -FilePath $rootCer | Out-Null
Export-Certificate -Cert $leaf -FilePath $leafCer | Out-Null
Export-PfxCertificate -Cert $leaf -FilePath $pfx -Password $securePassword | Out-Null

$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pfx))
@"
ONECLOUD_WINDOWS_PFX_PASSWORD=$Password
ONECLOUD_WINDOWS_PFX_BASE64=$base64
"@ | Set-Content -LiteralPath $secretFile -Encoding ASCII

Write-Host "Generated:"
Write-Host "  Root CA: $rootCer"
Write-Host "  Publisher cert: $leafCer"
Write-Host "  PFX: $pfx"
Write-Host "  GitHub secret values: $secretFile"

if ($PrintSecrets) {
    Write-Host ""
    Write-Host "GitHub Secrets:"
    Write-Host "  ONECLOUD_WINDOWS_PFX_PASSWORD=$Password"
    Write-Host "  ONECLOUD_WINDOWS_PFX_BASE64=$base64"
}
