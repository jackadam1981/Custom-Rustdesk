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

_custom_trace_value() {
    local name="$1"
    local value="${2:-}"

    if [ -z "$value" ]; then
        echo "source-patcher-trace: $name=<empty>"
    else
        echo "source-patcher-trace: $name=$value"
    fi
}

_custom_bool_enabled() {
    case "${1:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_custom_patch_debug_enabled() {
    _custom_bool_enabled "${CUSTOM_SOURCE_PATCH_DEBUG:-${BUILD_SOURCE_PATCH_DEBUG:-false}}"
}

_custom_trace_file_match() {
    local phase="$1"
    local file="$2"
    local label="$3"
    local pattern="$4"

    if ! _custom_patch_debug_enabled; then
        return 0
    fi

    echo "source-patcher-trace: [$phase] $file :: $label"
    if [ ! -f "$file" ]; then
        echo "source-patcher-trace: [$phase] $file missing"
        return 0
    fi

    if ! grep -nE "$pattern" "$file" | head -20; then
        echo "source-patcher-trace: [$phase] no match for $label"
    fi
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

    _custom_trace_file_match "before" "$file" "load_custom_client entry" 'pub fn load_custom_client\(\)'
    _custom_trace_file_match "before" "$file" "get_custom_rendezvous_server entry" 'pub fn get_custom_rendezvous_server\('
    _custom_trace_file_match "before" "$file" "get_api_server entry" 'pub fn get_api_server\('
    _custom_trace_file_match "before" "$file" "existing custom/default settings references" 'BUILTIN_SETTINGS|DEFAULT_SETTINGS|OVERWRITE_SETTINGS|RENDEZVOUS|RS_PUB_KEY'

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

    _custom_trace_file_match "after" "$file" "custom patch marker" 'CUSTOM_RUSTDESK_PATCH_START|CUSTOM_RUSTDESK_PATCH_END'
    _custom_trace_file_match "after" "$file" "custom injected constants" 'const CUSTOM_'
    _custom_trace_file_match "after" "$file" "apply defaults calls" 'apply_custom_build_defaults\(\);'
    _custom_trace_file_match "after" "$file" "custom settings keys" '"custom-rendezvous-server"|"relay-server"|"api-server"|"key"'
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

    _custom_trace_file_match "before" "$file" "Config::get_rendezvous_servers fallback" 'custom-rendezvous-server|get_rendezvous_servers'
    _custom_trace_file_match "before" "$file" "Config::get_options entry" 'pub fn get_options\(\)'
    _custom_trace_file_match "before" "$file" "Config::get_option entry" 'pub fn get_option\('
    _custom_trace_file_match "before" "$file" "upstream/default option sources" 'RENDEZVOUS_SERVERS|RS_PUB_KEY|DEFAULT_SETTINGS|OVERWRITE_SETTINGS'

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

fn custom_build_default_options() -> HashMap<String, String> {
    let mut options = HashMap::new();
    for (key, value) in [
        ("app-name", custom_build_default_option("app-name")),
        ("custom-rendezvous-server", custom_build_default_option("custom-rendezvous-server")),
        ("rendezvous-servers", custom_build_default_option("rendezvous-servers")),
        ("relay-server", custom_build_default_option("relay-server")),
        ("api-server", custom_build_default_option("api-server")),
        ("register-device", custom_build_default_option("register-device")),
        ("key", custom_build_default_option("key")),
        ("custom-slogan", custom_build_default_option("custom-slogan")),
        ("custom-customer-link", custom_build_default_option("custom-customer-link")),
    ] {
        if let Some(value) = value {
            options.insert(key.to_owned(), value.to_owned());
        }
    }
    options
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
    perl -0pi -e 's/(\s*pub fn get_options\(\) -> HashMap<String, String> \{\n\s*let mut res = DEFAULT_SETTINGS\.read\(\)\.unwrap\(\)\.clone\(\);\n)/$1        res.extend(custom_build_default_options());\n/' "$file"
    perl -0pi -e 's/get_or\(\n\s*&OVERWRITE_SETTINGS,\n\s*&CONFIG2\.read\(\)\.unwrap\(\)\.options,\n\s*&DEFAULT_SETTINGS,\n\s*k,\n\s*\)\n\s*\.unwrap_or_default\(\)/get_or(\n            \&OVERWRITE_SETTINGS,\n            \&CONFIG2.read().unwrap().options,\n            \&DEFAULT_SETTINGS,\n            k,\n        )\n        .or_else(|| custom_build_default_option(k).map(|v| v.to_owned()))\n        .unwrap_or_default()/' "$file"

    _custom_trace_file_match "after" "$file" "hbb_common patch marker" 'CUSTOM_RUSTDESK_HBB_COMMON_PATCH_START|CUSTOM_RUSTDESK_HBB_COMMON_PATCH_END'
    _custom_trace_file_match "after" "$file" "custom injected constants" 'const CUSTOM_'
    _custom_trace_file_match "after" "$file" "custom default option function" 'custom_build_default_option|custom_build_default_options'
    _custom_trace_file_match "after" "$file" "patched get_options/get_option fallback" 'res\.extend\(custom_build_default_options\(\)\)|or_else\(\|\| custom_build_default_option'
    _custom_trace_file_match "after" "$file" "patched rendezvous fallback" 'return vec!\[s\.to_owned\(\)\]'
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

_custom_patch_logo_assets() {
    local logo_source="${CUSTOM_LOGO_URL:-}"

    if [ -z "$logo_source" ]; then
        echo "source-patcher: no custom logo configured, skipping icon assets"
        return 0
    fi

    local work_dir
    work_dir=$(mktemp -d)
    local input_image="$work_dir/custom-logo"

    echo "source-patcher: custom logo configured"
    if [[ "$logo_source" =~ ^https?:// ]]; then
        if ! curl -fsSL "$logo_source" -o "$input_image"; then
            echo "source-patcher: failed to download logo_url" >&2
            rm -rf "$work_dir"
            return 1
        fi
    elif [ -f "$logo_source" ]; then
        cp "$logo_source" "$input_image"
    elif [ -f "../$logo_source" ]; then
        cp "../$logo_source" "$input_image"
    else
        echo "source-patcher: logo_url is neither a downloadable URL nor an existing file: $logo_source" >&2
        rm -rf "$work_dir"
        return 1
    fi

    if ! python3 - <<'PY' >/dev/null 2>&1
import PIL
PY
    then
        echo "source-patcher: installing Pillow for logo asset generation"
        python3 -m pip install --user pillow
    fi

    python3 - "$input_image" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

from PIL import Image

source = Path(sys.argv[1])
try:
    image = Image.open(source).convert("RGBA")
except Exception as exc:
    raise SystemExit(f"source-patcher: logo image cannot be opened by Pillow: {exc}")

def square_canvas(img, size):
    img.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(img, ((size - img.width) // 2, (size - img.height) // 2))
    return canvas

def save_png(path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    square_canvas(image.copy(), size).save(path)

windows_icon = Path("flutter/windows/runner/resources/app_icon.ico")
if windows_icon.exists():
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    square_canvas(image.copy(), 256).save(windows_icon, sizes=sizes)

android_sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for folder, size in android_sizes.items():
    base = Path("flutter/android/app/src/main/res") / folder
    for name in ("ic_launcher.png", "ic_launcher_round.png", "ic_launcher_foreground.png"):
        target = base / name
        if target.exists():
            save_png(target, size)
    stat_logo = base / "ic_stat_logo.png"
    if stat_logo.exists():
        save_png(stat_logo, max(24, size // 2))

appicon_dir = Path("flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset")
contents = appicon_dir / "Contents.json"
if contents.exists():
    data = json.loads(contents.read_text(encoding="utf-8"))
    for entry in data.get("images", []):
        filename = entry.get("filename")
        size_text = entry.get("size", "")
        scale_text = entry.get("scale", "1x")
        if not filename or "x" not in size_text:
            continue
        points = float(size_text.split("x", 1)[0])
        scale = int(re.sub(r"\D", "", scale_text) or "1")
        save_png(appicon_dir / filename, int(round(points * scale)))

print("source-patcher: custom logo assets generated")
PY

    rm -rf "$work_dir"
}

_custom_patch_sciter_ui_text() {
    local studio_text="由郑州熵能科技工作室为${CUSTOM_CUSTOMER:-定制客户}倾情打造。"
    local customer_link="${CUSTOM_CUSTOMER_LINK:-https://zzsn.work}"
    local about_file="flutter/lib/desktop/pages/desktop_setting_page.dart"

    if [ -f "$about_file" ] && ! grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file"; then
        export CUSTOM_STUDIO_TEXT="$studio_text"
        export CUSTOM_STUDIO_LINK="$customer_link"
        perl -0pi -e '
            s{
                Text\(\n
                \s*translate\('\''Slogan_tip'\''\),\n
                \s*style: TextStyle\(\n
                \s*fontWeight: FontWeight\.w800,\n
                \s*color: Colors\.white\),\n
                \s*\)\n
                \s*\],
            }{
                          Text(
                            translate('\''Slogan_tip'\''),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION
                          InkWell(
                            onTap: () {
                              launchUrlString('\''$ENV{CUSTOM_STUDIO_LINK}'\'');
                            },
                            child: Text(
                              '\''$ENV{CUSTOM_STUDIO_TEXT}'\'',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
            }msx' "$about_file"
        echo "source-patcher: studio attribution injected below Slogan_tip in $about_file"
    fi

    if [ -f "src/ui/index.tis" ] && ! grep -q "studio-about" "src/ui/index.tis"; then
        export CUSTOM_STUDIO_TEXT="$studio_text"
        export CUSTOM_STUDIO_LINK="$customer_link"
        perl -0pi -e '
            s#<p style='\''font-weight: bold'\''>" \+ translate\("Slogan_tip"\) \+ "</p>\\#<p style='\''font-weight: bold'\''>" + translate("Slogan_tip") + "</p>\\
            <p class='\''link custom-event studio-about'\'' style='\''font-weight: bold'\'' url='\''$ENV{CUSTOM_STUDIO_LINK}'\''>$ENV{CUSTOM_STUDIO_TEXT}</p>\\#g' "src/ui/index.tis"
        echo "source-patcher: studio attribution injected below Slogan_tip in src/ui/index.tis"
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

_custom_patch_rust_cache_nonfatal() {
    local file=".github/workflows/flutter-build.yml"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping rust-cache nonfatal patch"
        return 0
    fi

    if ! grep -q 'Swatinem/rust-cache' "$file"; then
        echo "source-patcher: no Swatinem/rust-cache step found, skipping rust-cache nonfatal patch"
        return 0
    fi

    local cache_steps patched_steps
    cache_steps="$(grep -c 'Swatinem/rust-cache' "$file" || true)"
    patched_steps="$(awk '
        /Swatinem\/rust-cache/ { saw_cache=1; next }
        saw_cache && /continue-on-error: true/ { count++; saw_cache=0; next }
        saw_cache { saw_cache=0 }
        END { print count+0 }
    ' "$file")"

    if [ "$cache_steps" -eq "$patched_steps" ]; then
        echo "source-patcher: rust-cache nonfatal patch already applied"
        return 0
    fi

    perl -0pi -e 's/^(\s*- uses: Swatinem\/rust-cache@[^\n]*\n)(?!\s+continue-on-error:)/$1        continue-on-error: true\n/gm' "$file"

    echo "source-patcher: marked Swatinem/rust-cache steps as continue-on-error"
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

    CUSTOM_APP_NAME="${BUILD_APP_NAME:-${BUILD_CUSTOMER:-${BUILD_TAG:-CustomRustDesk}}}"
    CUSTOM_CUSTOMER="${BUILD_CUSTOMER:-定制客户}"
    CUSTOM_CUSTOMER_LINK="${BUILD_CUSTOMER_LINK:-https://zzsn.work}"
    CUSTOM_LOGO_URL="${BUILD_LOGO_URL:-}"
    CUSTOM_SLOGAN="${BUILD_SLOGAN:-}"
    CUSTOM_RENDEZVOUS_INPUT="${BUILD_RENDEZVOUS_SERVER:-}"
    CUSTOM_RENDEZVOUS_SERVER=$(_custom_address_host "$CUSTOM_RENDEZVOUS_INPUT")
    CUSTOM_RELAY_SERVER=$(_custom_address_host "${BUILD_RELAY_SERVER:-$CUSTOM_RENDEZVOUS_INPUT}")
    CUSTOM_RS_PUB_KEY="${BUILD_RS_PUB_KEY:-}"
    CUSTOM_API_SERVER="${BUILD_API_SERVER:-}"
    if _custom_bool_enabled "${BUILD_SOURCE_PATCH_DEBUG:-false}"; then
        CUSTOM_SOURCE_PATCH_DEBUG="true"
    else
        CUSTOM_SOURCE_PATCH_DEBUG="false"
    fi

    echo "source-patcher-trace: resolved custom build inputs"
    _custom_trace_value "BUILD_APP_NAME" "${BUILD_APP_NAME:-}"
    _custom_trace_value "CUSTOM_APP_NAME(resolved)" "$CUSTOM_APP_NAME"
    _custom_trace_value "BUILD_LOGO_URL" "${BUILD_LOGO_URL:+[provided]}"
    _custom_trace_value "BUILD_RENDEZVOUS_SERVER(raw)" "${BUILD_RENDEZVOUS_SERVER:-}"
    _custom_trace_value "CUSTOM_RENDEZVOUS_SERVER(normalized)" "$CUSTOM_RENDEZVOUS_SERVER"
    _custom_trace_value "BUILD_RELAY_SERVER(raw)" "${BUILD_RELAY_SERVER:-}"
    _custom_trace_value "CUSTOM_RELAY_SERVER(normalized)" "$CUSTOM_RELAY_SERVER"
    _custom_trace_value "BUILD_API_SERVER(raw)" "${BUILD_API_SERVER:-}"
    _custom_trace_value "CUSTOM_API_SERVER" "$CUSTOM_API_SERVER"
    _custom_trace_value "BUILD_RS_PUB_KEY" "$CUSTOM_RS_PUB_KEY"
    _custom_trace_value "BUILD_LOCK_NETWORK_SETTINGS(raw)" "${BUILD_LOCK_NETWORK_SETTINGS:-}"
    _custom_trace_value "CUSTOM_LOCK_SETTINGS(normalized)" "$CUSTOM_LOCK_SETTINGS"
    _custom_trace_value "BUILD_SOURCE_PATCH_DEBUG(raw)" "${BUILD_SOURCE_PATCH_DEBUG:-}"
    _custom_trace_value "CUSTOM_SOURCE_PATCH_DEBUG(normalized)" "$CUSTOM_SOURCE_PATCH_DEBUG"
    if _custom_patch_debug_enabled; then
        echo "source-patcher-trace: detailed before/after source diagnostics enabled"
    else
        echo "source-patcher-trace: detailed before/after source diagnostics disabled"
    fi

    jq -n \
        --arg app_name "$CUSTOM_APP_NAME" \
        --arg customer "$BUILD_CUSTOMER" \
        --arg customer_link "$CUSTOM_CUSTOMER_LINK" \
        --arg logo_url "$CUSTOM_LOGO_URL" \
        --arg slogan "$CUSTOM_SLOGAN" \
        --arg rendezvous_server "$CUSTOM_RENDEZVOUS_INPUT" \
        --arg custom_rendezvous_server "$CUSTOM_RENDEZVOUS_SERVER" \
        --arg relay_server "$CUSTOM_RELAY_SERVER" \
        --arg rs_pub_key "$CUSTOM_RS_PUB_KEY" \
        --arg api_server "$CUSTOM_API_SERVER" \
        --arg lock_network_settings "$CUSTOM_LOCK_SETTINGS" \
        --arg source_patch_debug "$CUSTOM_SOURCE_PATCH_DEBUG" \
        '{
            app_name: $app_name,
            customer: $customer,
            customer_link: $customer_link,
            logo_url: $logo_url,
            slogan: $slogan,
            rendezvous_server: $rendezvous_server,
            custom_rendezvous_server: $custom_rendezvous_server,
            relay_server: $relay_server,
            rs_pub_key: $rs_pub_key,
            api_server: $api_server,
            lock_network_settings: ($lock_network_settings == "true"),
            source_patch_debug: ($source_patch_debug == "true")
        }' > custom-build-config.json

    _custom_patch_common_rs
    _custom_patch_hbb_common_config_rs
    _custom_patch_brand_files
    _custom_patch_logo_assets
    _custom_patch_sciter_ui_text
    _custom_patch_portable_working_dir
    _custom_patch_windows_test_signing
    _custom_patch_rust_cache_nonfatal

    echo "source-patcher: custom source patches applied"
}
