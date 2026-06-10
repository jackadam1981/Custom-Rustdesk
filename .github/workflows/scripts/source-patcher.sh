#!/bin/bash

# Applies custom RustDesk source patches inside the cloned rustdesk source tree.

_custom_json_string() {
    jq -Rn --arg v "${1:-}" '$v'
}

_custom_xml_escape() {
    printf '%s' "${1:-}" |
        sed -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g' \
            -e 's/"/\&quot;/g' \
            -e "s/'/\&apos;/g"
}

_custom_replace_file() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"

    if [ -f "$file" ]; then
        perl -0pi -e "s{$pattern}{$replacement}g" "$file"
    fi
}

_custom_replace_file_once() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"

    if [ -f "$file" ]; then
        perl -0pi -e "s{$pattern}{$replacement}" "$file"
    fi
}

_custom_address_host() {
    local address="${1:-}"
    address="${address#*://}"
    address="${address%%/*}"

    if [[ "$address" =~ ^\[([^]]+)\](:[0-9]+)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "$address" =~ ^([^:]+):[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    echo "$address"
}

_custom_patch_common_rs() {
    local file="src/common.rs"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping Rust core defaults"
        return 0
    fi

    if grep -q "CUSTOM_RUSTDESK_PATCH_START" "$file"; then
        echo "source-patcher: Rust core defaults already patched"
        return 0
    fi

    local app_name_json slogan_json customer_link_json rendezvous_json relay_json api_json key_json register_device_json
    app_name_json=$(_custom_json_string "$CUSTOM_APP_NAME")
    slogan_json=$(_custom_json_string "$CUSTOM_SLOGAN")
    customer_link_json=$(_custom_json_string "$CUSTOM_CUSTOMER_LINK")
    rendezvous_json=$(_custom_json_string "$CUSTOM_RENDEZVOUS_SERVER")
    relay_json=$(_custom_json_string "$CUSTOM_RELAY_SERVER")
    api_json=$(_custom_json_string "$CUSTOM_API_SERVER")
    key_json=$(_custom_json_string "$CUSTOM_RS_PUB_KEY")
    if [ -z "$CUSTOM_API_SERVER" ]; then
        register_device_json=$(_custom_json_string "N")
    else
        register_device_json=$(_custom_json_string "")
    fi

    local hard_settings_patch=""
    if [ "${CUSTOM_LOCK_SETTINGS:-false}" = "true" ]; then
        hard_settings_patch='
    {
        let mut hard_settings = config::HARD_SETTINGS.write().unwrap();
        for (key, value) in custom_settings {
            if !value.is_empty() {
                hard_settings.insert(key.to_owned(), value.to_owned());
            }
        }
        hard_settings.insert("disable-settings".to_owned(), "Y".to_owned());
    }'
    fi

    local patch_file
    patch_file=$(mktemp)
    cat > "$patch_file" <<EOF

// CUSTOM_RUSTDESK_PATCH_START
pub fn apply_custom_build_defaults() {
    const CUSTOM_APP_NAME: &str = $app_name_json;
    const CUSTOM_SLOGAN: &str = $slogan_json;
    const CUSTOM_CUSTOMER_LINK: &str = $customer_link_json;
    const CUSTOM_RENDEZVOUS_SERVER: &str = $rendezvous_json;
    const CUSTOM_RELAY_SERVER: &str = $relay_json;
    const CUSTOM_API_SERVER: &str = $api_json;
    const CUSTOM_RS_PUB_KEY: &str = $key_json;
    const CUSTOM_REGISTER_DEVICE: &str = $register_device_json;

    if !CUSTOM_APP_NAME.is_empty() {
        *config::APP_NAME.write().unwrap() = CUSTOM_APP_NAME.to_owned();
    }

    let custom_settings = [
        ("app-name", CUSTOM_APP_NAME),
        ("custom-rendezvous-server", CUSTOM_RENDEZVOUS_SERVER),
        ("rendezvous-servers", CUSTOM_RENDEZVOUS_SERVER),
        ("relay-server", CUSTOM_RELAY_SERVER),
        ("api-server", CUSTOM_API_SERVER),
        ("register-device", CUSTOM_REGISTER_DEVICE),
        ("key", CUSTOM_RS_PUB_KEY),
        ("custom-slogan", CUSTOM_SLOGAN),
        ("custom-customer-link", CUSTOM_CUSTOMER_LINK),
    ];

    {
        let mut builtin_settings = config::BUILTIN_SETTINGS.write().unwrap();
        for (key, value) in custom_settings {
            if !value.is_empty() {
                builtin_settings.insert(key.to_owned(), value.to_owned());
            }
        }
    }
    {
        let mut default_settings = config::DEFAULT_SETTINGS.write().unwrap();
        for (key, value) in custom_settings {
            if !value.is_empty() {
                default_settings.insert(key.to_owned(), value.to_owned());
            }
        }
    }
    {
        let mut overwrite_settings = config::OVERWRITE_SETTINGS.write().unwrap();
        for (key, value) in custom_settings {
            if !value.is_empty() {
                overwrite_settings.insert(key.to_owned(), value.to_owned());
            }
        }
    }
    {
        let mut runtime_settings = std::collections::HashMap::new();
        for (key, value) in custom_settings {
            if !value.is_empty() {
                runtime_settings.insert(key.to_owned(), value.to_owned());
            }
        }
        if !runtime_settings.is_empty() {
            config::Config::set_options(runtime_settings);
        }
    }
$hard_settings_patch
}
// CUSTOM_RUSTDESK_PATCH_END
EOF

    awk -v patch_file="$patch_file" '
        /^fn read_custom_client_advanced_settings\(/ && !inserted {
            while ((getline line < patch_file) > 0) print line;
            close(patch_file);
            inserted=1;
        }
        { print }
    ' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    rm -f "$patch_file"

    perl -0pi -e 's/pub fn load_custom_client\(\) \{\n/pub fn load_custom_client() {\n    apply_custom_build_defaults();\n/' "$file"
    perl -0pi -e 's/pub fn get_custom_rendezvous_server\(custom: String\) -> String \{\n/pub fn get_custom_rendezvous_server(custom: String) -> String {\n    apply_custom_build_defaults();\n    let custom = if custom.is_empty() {\n        config::Config::get_option("custom-rendezvous-server")\n    } else {\n        custom\n    };\n/' "$file"
    perl -0pi -e 's/pub fn get_api_server\(api: String, custom: String\) -> String \{\n/pub fn get_api_server(api: String, custom: String) -> String {\n    apply_custom_build_defaults();\n    if api.is_empty()\n        && config::Config::get_option("api-server").is_empty()\n        && config::Config::get_option("register-device") == "N"\n    {\n        return "".to_owned();\n    }\n/' "$file"
}

_custom_patch_hbb_common_config_rs() {
    local file="libs/hbb_common/src/config.rs"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping hbb_common defaults"
        return 0
    fi

    if grep -q "CUSTOM_RUSTDESK_HBB_COMMON_PATCH_START" "$file"; then
        echo "source-patcher: hbb_common defaults already patched"
        return 0
    fi

    local rendezvous_json relay_json api_json key_json register_device_json app_name_json slogan_json customer_link_json
    rendezvous_json=$(_custom_json_string "$CUSTOM_RENDEZVOUS_SERVER")
    relay_json=$(_custom_json_string "$CUSTOM_RELAY_SERVER")
    api_json=$(_custom_json_string "$CUSTOM_API_SERVER")
    key_json=$(_custom_json_string "$CUSTOM_RS_PUB_KEY")
    app_name_json=$(_custom_json_string "$CUSTOM_APP_NAME")
    slogan_json=$(_custom_json_string "$CUSTOM_SLOGAN")
    customer_link_json=$(_custom_json_string "$CUSTOM_CUSTOMER_LINK")
    if [ -z "$CUSTOM_API_SERVER" ]; then
        register_device_json=$(_custom_json_string "N")
    else
        register_device_json=$(_custom_json_string "")
    fi

    local patch_file
    patch_file=$(mktemp)
    cat > "$patch_file" <<EOF

// CUSTOM_RUSTDESK_HBB_COMMON_PATCH_START
fn custom_build_default_option(k: &str) -> Option<&'static str> {
    const CUSTOM_APP_NAME: &str = $app_name_json;
    const CUSTOM_SLOGAN: &str = $slogan_json;
    const CUSTOM_CUSTOMER_LINK: &str = $customer_link_json;
    const CUSTOM_RENDEZVOUS_SERVER: &str = $rendezvous_json;
    const CUSTOM_RELAY_SERVER: &str = $relay_json;
    const CUSTOM_API_SERVER: &str = $api_json;
    const CUSTOM_RS_PUB_KEY: &str = $key_json;
    const CUSTOM_REGISTER_DEVICE: &str = $register_device_json;

    let value = match k {
        "app-name" => CUSTOM_APP_NAME,
        "custom-rendezvous-server" | "rendezvous-servers" => CUSTOM_RENDEZVOUS_SERVER,
        "relay-server" => CUSTOM_RELAY_SERVER,
        "api-server" => CUSTOM_API_SERVER,
        "register-device" => CUSTOM_REGISTER_DEVICE,
        "key" => CUSTOM_RS_PUB_KEY,
        "custom-slogan" => CUSTOM_SLOGAN,
        "custom-customer-link" => CUSTOM_CUSTOMER_LINK,
        _ => "",
    };
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}
// CUSTOM_RUSTDESK_HBB_COMMON_PATCH_END
EOF

    awk -v patch_file="$patch_file" '
        /^impl Config \{/ && !inserted {
            while ((getline line < patch_file) > 0) print line;
            close(patch_file);
            inserted=1;
        }
        { print }
    ' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    rm -f "$patch_file"

    perl -0pi -e 's/(\s*let s = Self::get_option\("custom-rendezvous-server"\);\n\s*if !s\.is_empty\(\) \{\n\s*return vec!\[s\];\n\s*\})/$1\n        if let Some(s) = custom_build_default_option("custom-rendezvous-server") {\n            return vec![s.to_owned()];\n        }/' "$file"
    perl -0pi -e 's/get_or\(\n\s*&OVERWRITE_SETTINGS,\n\s*&CONFIG2\.read\(\)\.unwrap\(\)\.options,\n\s*&DEFAULT_SETTINGS,\n\s*k,\n\s*\)\n\s*\.unwrap_or_default\(\)/get_or(\n            \&OVERWRITE_SETTINGS,\n            \&CONFIG2.read().unwrap().options,\n            \&DEFAULT_SETTINGS,\n            k,\n        )\n        .or_else(|| custom_build_default_option(k).map(|v| v.to_owned()))\n        .unwrap_or_default()/' "$file"
}

_custom_patch_brand_files() {
    local app_name_xml
    app_name_xml=$(_custom_xml_escape "$CUSTOM_APP_NAME")

    _custom_replace_file "flutter/android/app/src/main/res/values/strings.xml" \
        '<string name="app_name">[^<]*</string>' \
        "<string name=\"app_name\">$app_name_xml</string>"

    _custom_replace_file "flutter/android/app/src/main/AndroidManifest.xml" \
        'android:label="RustDesk"' \
        "android:label=\"$app_name_xml\""

    _custom_replace_file "flutter/ios/Runner/Info.plist" \
        '(<key>CFBundleDisplayName</key>[[:space:]]*<string>)[^<]*(</string>)' \
        "\${1}$app_name_xml\${2}"
    _custom_replace_file "flutter/ios/Runner/Info.plist" \
        '(<key>CFBundleName</key>[[:space:]]*<string>)[^<]*(</string>)' \
        "\${1}$app_name_xml\${2}"

    _custom_replace_file_once "res/rustdesk.desktop" '(?m)^Name=.*$' "Name=$CUSTOM_APP_NAME"
    _custom_replace_file_once "res/rustdesk-link.desktop" '(?m)^Name=.*$' "Name=$CUSTOM_APP_NAME"

    _custom_replace_file "flutter/windows/runner/Runner.rc" \
        'VALUE "ProductName", "RustDesk"' \
        "VALUE \"ProductName\", \"$CUSTOM_APP_NAME\""
    _custom_replace_file "flutter/windows/runner/Runner.rc" \
        'VALUE "FileDescription", "RustDesk Remote Desktop"' \
        "VALUE \"FileDescription\", \"$CUSTOM_APP_NAME Remote Desktop\""

    _custom_replace_file "Cargo.toml" \
        'description = "RustDesk Remote Desktop"' \
        "description = \"$CUSTOM_APP_NAME Remote Desktop\""
    _custom_replace_file "Cargo.toml" \
        'ProductName = "RustDesk"' \
        "ProductName = \"$CUSTOM_APP_NAME\""
    _custom_replace_file "Cargo.toml" \
        'FileDescription = "RustDesk Remote Desktop"' \
        "FileDescription = \"$CUSTOM_APP_NAME Remote Desktop\""

    _custom_replace_file "libs/portable/Cargo.toml" \
        'description = "RustDesk Remote Desktop"' \
        "description = \"$CUSTOM_APP_NAME Remote Desktop\""
    _custom_replace_file "libs/portable/Cargo.toml" \
        'ProductName = "RustDesk"' \
        "ProductName = \"$CUSTOM_APP_NAME\""
    _custom_replace_file "libs/portable/Cargo.toml" \
        'FileDescription = "RustDesk Remote Desktop"' \
        "FileDescription = \"$CUSTOM_APP_NAME Remote Desktop\""
}

_custom_patch_sciter_ui_text() {
    if [ ! -d "src/lang" ]; then
        return 0
    fi

    if [ -f "src/lang/cn.rs" ]; then
        _custom_replace_file "src/lang/cn.rs" \
            '\("powered_by_me",[[:space:]]*"[^"]*"\)' \
            "(\"powered_by_me\", \"由 $CUSTOM_APP_NAME 提供支持\")"
    fi

    if [ -f "src/lang/en.rs" ]; then
        _custom_replace_file "src/lang/en.rs" \
            '\("powered_by_me",[[:space:]]*"[^"]*"\)' \
            "(\"powered_by_me\", \"Powered by $CUSTOM_APP_NAME\")"
    fi
}

_custom_patch_portable_working_dir() {
    local file="libs/portable/src/main.rs"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping portable working directory patch"
        return 0
    fi

    if grep -q "CUSTOM_RUSTDESK_PORTABLE_WORKDIR_PATCH" "$file"; then
        echo "source-patcher: portable working directory already patched"
        return 0
    fi

    perl -0pi -e 's{let mut cmd = Command::new\(path\);\n}{// CUSTOM_RUSTDESK_PORTABLE_WORKDIR_PATCH\n    let current_dir = path.parent().map(|dir| dir.to_path_buf());\n    let mut cmd = Command::new(path);\n}' "$file"
    perl -0pi -e 's{cmd\.args\(args\);\n}{cmd.args(args);\n    if let Some(dir) = current_dir {\n        cmd.current_dir(dir);\n    }\n}' "$file"
}

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

apply_custom_source_patches() {
    case "${BUILD_LOCK_NETWORK_SETTINGS:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON)
            CUSTOM_LOCK_SETTINGS="true"
            ;;
        false|FALSE|False|0|no|NO|n|N|off|OFF|"")
            CUSTOM_LOCK_SETTINGS="false"
            ;;
        *)
            echo "source-patcher: unsupported lock_network_settings '${BUILD_LOCK_NETWORK_SETTINGS}'" >&2
            return 1
            ;;
    esac

    CUSTOM_APP_NAME="${BUILD_CUSTOMER:-${BUILD_TAG:-CustomRustDesk}}"
    CUSTOM_CUSTOMER_LINK="${BUILD_CUSTOMER_LINK:-}"
    CUSTOM_SLOGAN="${BUILD_SLOGAN:-}"
    CUSTOM_RENDEZVOUS_INPUT="${BUILD_RENDEZVOUS_SERVER:-}"
    CUSTOM_RENDEZVOUS_SERVER=$(_custom_address_host "$CUSTOM_RENDEZVOUS_INPUT")
    CUSTOM_RELAY_SERVER=$(_custom_address_host "${BUILD_RELAY_SERVER:-$CUSTOM_RENDEZVOUS_INPUT}")
    CUSTOM_RS_PUB_KEY="${BUILD_RS_PUB_KEY:-}"
    CUSTOM_API_SERVER="${BUILD_API_SERVER:-}"

    jq -n \
        --arg app_name "$CUSTOM_APP_NAME" \
        --arg customer_link "$CUSTOM_CUSTOMER_LINK" \
        --arg slogan "$CUSTOM_SLOGAN" \
        --arg rendezvous_server "$CUSTOM_RENDEZVOUS_INPUT" \
        --arg custom_rendezvous_server "$CUSTOM_RENDEZVOUS_SERVER" \
        --arg relay_server "$CUSTOM_RELAY_SERVER" \
        --arg rs_pub_key "$CUSTOM_RS_PUB_KEY" \
        --arg api_server "$CUSTOM_API_SERVER" \
        --arg lock_network_settings "$CUSTOM_LOCK_SETTINGS" \
        '{
            app_name: $app_name,
            customer_link: $customer_link,
            slogan: $slogan,
            rendezvous_server: $rendezvous_server,
            custom_rendezvous_server: $custom_rendezvous_server,
            relay_server: $relay_server,
            rs_pub_key: $rs_pub_key,
            api_server: $api_server,
            lock_network_settings: ($lock_network_settings == "true")
        }' > custom-build-config.json

    _custom_patch_common_rs
    _custom_patch_hbb_common_config_rs
    _custom_patch_brand_files
    _custom_patch_sciter_ui_text
    _custom_patch_portable_working_dir
    _custom_patch_windows_test_signing

    echo "source-patcher: custom source patches applied"
}
