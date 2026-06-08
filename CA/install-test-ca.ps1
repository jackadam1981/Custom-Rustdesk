[CmdletBinding()]
param(
    [string]$RootCertificate,
    [string]$PublisherCertificate
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RootCertificate)) {
    $RootCertificate = Join-Path $scriptRoot "oneclouddesk-test-root-ca.cer"
}
if ([string]::IsNullOrWhiteSpace($PublisherCertificate)) {
    $PublisherCertificate = Join-Path $scriptRoot "oneclouddesk-test-code-signing.cer"
}

if (-not (Test-Path -LiteralPath $RootCertificate)) {
    throw "Root certificate not found: $RootCertificate"
}
if (-not (Test-Path -LiteralPath $PublisherCertificate)) {
    throw "Publisher certificate not found: $PublisherCertificate"
}

Import-Certificate -FilePath $RootCertificate -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
Import-Certificate -FilePath $PublisherCertificate -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher" | Out-Null

Write-Host "Installed test root CA into CurrentUser\\Root."
Write-Host "Installed test publisher certificate into CurrentUser\\TrustedPublisher."
