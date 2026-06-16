_custom_write_windows_sign_script() {
    local file=".github/workflows/scripts/onecloud-windows-sign.ps1"
    mkdir -p "$(dirname "$file")"
    cat > "$file" <<'EOF'
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:ONECLOUD_WINDOWS_PFX_BASE64)) {
    Write-Host 'OneCloud test signing skipped: ONECLOUD_WINDOWS_PFX_BASE64 is empty.'
    exit 0
}

$pfxPath = Join-Path $env:RUNNER_TEMP 'onecloud-windows-code-signing.pfx'
[IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($env:ONECLOUD_WINDOWS_PFX_BASE64))

$certs = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
$certs.Import($pfxPath, $env:ONECLOUD_WINDOWS_PFX_PASSWORD, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
$cert = $certs |
    Where-Object {
        $_.HasPrivateKey -and
        $_.Subject -ne $_.Issuer -and
        ($_.EnhancedKeyUsageList | Where-Object { $_.FriendlyName -eq 'Code Signing' -or $_.ObjectId -eq '1.3.6.1.5.5.7.3.3' })
    } |
    Select-Object -First 1

if (-not $cert) {
    throw 'No non-root code signing certificate with a private key was found in the PFX.'
}

$signtool = Get-ChildItem -LiteralPath "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\signtool\.exe$' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1

if (-not $signtool) {
    throw 'signtool.exe was not found in the Windows SDK.'
}

$signableExtensions = @('.dll', '.exe', '.sys', '.vxd', '.msix', '.msixbundle', '.appx', '.appxbundle', '.msi', '.msp')
$files = Get-ChildItem -LiteralPath $Path -Recurse -File |
    Where-Object { $signableExtensions -contains $_.Extension.ToLowerInvariant() }

foreach ($file in $files) {
    Write-Host "Signing $($file.FullName)"
    & $signtool.FullName sign /f $pfxPath /p "$env:ONECLOUD_WINDOWS_PFX_PASSWORD" /sha1 $cert.Thumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "$($file.FullName)"
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Timestamp signing failed for $($file.FullName), retrying without timestamp."
        & $signtool.FullName sign /f $pfxPath /p "$env:ONECLOUD_WINDOWS_PFX_PASSWORD" /sha1 $cert.Thumbprint /fd SHA256 "$($file.FullName)"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to sign $($file.FullName)"
        }
    }
}
EOF
}

_custom_patch_windows_test_signing() {
    local file=".github/workflows/flutter-build.yml"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping Windows test signing patch"
        return 0
    fi

    if grep -q "ONECLOUD_WINDOWS_PFX_BASE64" "$file"; then
        echo "source-patcher: Windows test signing already patched"
        _custom_write_windows_sign_script
        return 0
    fi

    _custom_write_windows_sign_script

    awk '
        {
            print
            if ($0 == "  SIGN_BASE_URL: \"${{ secrets.SIGN_BASE_URL }}-2\"") {
                print "  ONECLOUD_WINDOWS_SIGNING_ENABLED: \"${{ secrets.ONECLOUD_WINDOWS_PFX_BASE64 != '\'''\'' }}\""
            }
        }
    ' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"

    perl -0pi -e 's{(BASE_URL=\$\{\{ env\.SIGN_BASE_URL \}\} SECRET_KEY=\$\{\{ secrets\.SIGN_SECRET_KEY \}\} python3 res/job\.py sign_files \./rustdesk/\n)}{$1\n      - name: Sign rustdesk files with OneCloud test certificate\n        if: env.UPLOAD_ARTIFACT == '\''true'\'' && env.SIGN_BASE_URL == '\''-2'\'' && env.ONECLOUD_WINDOWS_SIGNING_ENABLED == '\''true'\''\n        shell: powershell\n        env:\n          ONECLOUD_WINDOWS_PFX_BASE64: \${{ secrets.ONECLOUD_WINDOWS_PFX_BASE64 }}\n          ONECLOUD_WINDOWS_PFX_PASSWORD: \${{ secrets.ONECLOUD_WINDOWS_PFX_PASSWORD }}\n        run: powershell -NoProfile -ExecutionPolicy Bypass -File .github/workflows/scripts/onecloud-windows-sign.ps1 -Path ./rustdesk\n}' "$file"

    perl -0pi -e 's{(BASE_URL=\$\{\{ env\.SIGN_BASE_URL \}\} SECRET_KEY=\$\{\{ secrets\.SIGN_SECRET_KEY \}\} python3 res/job\.py sign_files \./Release/\n)}{$1\n      - name: Sign sciter files with OneCloud test certificate\n        if: env.UPLOAD_ARTIFACT == '\''true'\'' && env.SIGN_BASE_URL == '\''-2'\'' && env.ONECLOUD_WINDOWS_SIGNING_ENABLED == '\''true'\''\n        shell: powershell\n        env:\n          ONECLOUD_WINDOWS_PFX_BASE64: \${{ secrets.ONECLOUD_WINDOWS_PFX_BASE64 }}\n          ONECLOUD_WINDOWS_PFX_PASSWORD: \${{ secrets.ONECLOUD_WINDOWS_PFX_PASSWORD }}\n        run: powershell -NoProfile -ExecutionPolicy Bypass -File .github/workflows/scripts/onecloud-windows-sign.ps1 -Path ./Release\n}' "$file"

    perl -0pi -e 's{(BASE_URL=\$\{\{ env\.SIGN_BASE_URL \}\} SECRET_KEY=\$\{\{ secrets\.SIGN_SECRET_KEY \}\} python3 res/job\.py sign_files \./SignOutput/?\n)}{$1\n      - name: Sign packaged Windows artifacts with OneCloud test certificate\n        if: env.UPLOAD_ARTIFACT == '\''true'\'' && env.SIGN_BASE_URL == '\''-2'\'' && env.ONECLOUD_WINDOWS_SIGNING_ENABLED == '\''true'\''\n        shell: powershell\n        env:\n          ONECLOUD_WINDOWS_PFX_BASE64: \${{ secrets.ONECLOUD_WINDOWS_PFX_BASE64 }}\n          ONECLOUD_WINDOWS_PFX_PASSWORD: \${{ secrets.ONECLOUD_WINDOWS_PFX_PASSWORD }}\n        run: powershell -NoProfile -ExecutionPolicy Bypass -File .github/workflows/scripts/onecloud-windows-sign.ps1 -Path ./SignOutput\n}g' "$file"
}
