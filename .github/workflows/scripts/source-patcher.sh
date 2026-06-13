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

    local app_name_json slogan_json customer_link_json customer_name_json rendezvous_json relay_json api_json key_json register_device_json hide_network_json
    app_name_json=$(_custom_json_string "$CUSTOM_APP_NAME")
    slogan_json=$(_custom_json_string "$CUSTOM_SLOGAN")
    customer_link_json=$(_custom_json_string "$CUSTOM_CUSTOMER_LINK")
    customer_name_json=$(_custom_json_string "${CUSTOM_CUSTOMER:-定制客户}")
    rendezvous_json=$(_custom_json_string "$CUSTOM_RENDEZVOUS_SERVER")
    relay_json=$(_custom_json_string "$CUSTOM_RELAY_SERVER")
    api_json=$(_custom_json_string "$CUSTOM_API_SERVER")
    key_json=$(_custom_json_string "$CUSTOM_RS_PUB_KEY")
    if [ "${CUSTOM_HIDE_NETWORK_SETTINGS:-false}" = "true" ]; then
        hide_network_json=$(_custom_json_string "Y")
    else
        hide_network_json=$(_custom_json_string "")
    fi
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
    const CUSTOM_CUSTOMER_NAME: &str = $customer_name_json;
    const CUSTOM_RENDEZVOUS_SERVER: &str = $rendezvous_json;
    const CUSTOM_RELAY_SERVER: &str = $relay_json;
    const CUSTOM_API_SERVER: &str = $api_json;
    const CUSTOM_RS_PUB_KEY: &str = $key_json;
    const CUSTOM_REGISTER_DEVICE: &str = $register_device_json;
    const CUSTOM_HIDE_NETWORK_SETTINGS: &str = $hide_network_json;

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
        ("custom-customer-name", CUSTOM_CUSTOMER_NAME),
        ("hide-server-settings", CUSTOM_HIDE_NETWORK_SETTINGS),
        ("hide-network-settings", CUSTOM_HIDE_NETWORK_SETTINGS),
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

    local rendezvous_json relay_json api_json key_json register_device_json app_name_json slogan_json customer_link_json customer_name_json hide_network_json
    rendezvous_json=$(_custom_json_string "$CUSTOM_RENDEZVOUS_SERVER")
    relay_json=$(_custom_json_string "$CUSTOM_RELAY_SERVER")
    api_json=$(_custom_json_string "$CUSTOM_API_SERVER")
    key_json=$(_custom_json_string "$CUSTOM_RS_PUB_KEY")
    app_name_json=$(_custom_json_string "$CUSTOM_APP_NAME")
    slogan_json=$(_custom_json_string "$CUSTOM_SLOGAN")
    customer_link_json=$(_custom_json_string "$CUSTOM_CUSTOMER_LINK")
    customer_name_json=$(_custom_json_string "${CUSTOM_CUSTOMER:-定制客户}")
    if [ "${CUSTOM_HIDE_NETWORK_SETTINGS:-false}" = "true" ]; then
        hide_network_json=$(_custom_json_string "Y")
    else
        hide_network_json=$(_custom_json_string "")
    fi
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
    const CUSTOM_CUSTOMER_NAME: &str = $customer_name_json;
    const CUSTOM_RENDEZVOUS_SERVER: &str = $rendezvous_json;
    const CUSTOM_RELAY_SERVER: &str = $relay_json;
    const CUSTOM_API_SERVER: &str = $api_json;
    const CUSTOM_RS_PUB_KEY: &str = $key_json;
    const CUSTOM_REGISTER_DEVICE: &str = $register_device_json;
    const CUSTOM_HIDE_NETWORK_SETTINGS: &str = $hide_network_json;

    let value = match k {
        "app-name" => CUSTOM_APP_NAME,
        "custom-rendezvous-server" | "rendezvous-servers" => CUSTOM_RENDEZVOUS_SERVER,
        "relay-server" => CUSTOM_RELAY_SERVER,
        "api-server" => CUSTOM_API_SERVER,
        "register-device" => CUSTOM_REGISTER_DEVICE,
        "key" => CUSTOM_RS_PUB_KEY,
        "custom-slogan" => CUSTOM_SLOGAN,
        "custom-customer-link" => CUSTOM_CUSTOMER_LINK,
        "custom-customer-name" => CUSTOM_CUSTOMER_NAME,
        "hide-server-settings" | "hide-network-settings" => CUSTOM_HIDE_NETWORK_SETTINGS,
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
        ("custom-customer-name", custom_build_default_option("custom-customer-name")),
        ("hide-server-settings", custom_build_default_option("hide-server-settings")),
        ("hide-network-settings", custom_build_default_option("hide-network-settings")),
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

def save_fit_png(path, max_width, max_height):
    path.parent.mkdir(parents=True, exist_ok=True)
    banner = image.copy()
    banner.thumbnail((max_width, max_height), Image.LANCZOS)
    banner.save(path)

for target in (
    Path("flutter/assets/logo.png"),
    Path("res/logo.png"),
):
    save_fit_png(target, 300, 60)

for target in (
    Path("flutter/assets/icon.png"),
    Path("res/icon.png"),
):
    save_png(target, 256)

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

_custom_sciter_logo_img_markup() {
    if [ ! -f "res/logo.png" ]; then
        return 0
    fi

    python3 - <<'PY'
import base64
from pathlib import Path

data = base64.b64encode(Path("res/logo.png").read_bytes()).decode("ascii")
print(
    '<img.custom-rd-home-logo src="data:image/png;base64,' + data + '" '
    'style="max-width:300px;max-height:60px;margin:0 auto 0.25em auto;display:block" />'
)
PY
}

_custom_sciter_custom_brand_block() {
    local logo_markup=""

    if [ -f "res/logo.png" ]; then
        logo_markup=$(_custom_sciter_logo_img_markup)
    fi

    if [ -n "$logo_markup" ]; then
        printf '%s' "{is_custom_client ? <div #custom-brand.custom-rd-home-header style=\"text-align:center;margin-bottom:0.35em\">${logo_markup}<div style=\"font-size:1.1em;font-weight:bold\">{handler.get_builtin_option(\"custom-customer-name\")}</div></div> : \"\"}"
    else
        printf '%s' '{is_custom_client ? <div #custom-brand.custom-rd-home-header style="text-align:center;margin-bottom:0.35em;font-size:1.1em;font-weight:bold">{handler.get_builtin_option("custom-customer-name")}</div> : ""}'
    fi
}

_custom_patch_sciter_home_ui() {
    local index_file="src/ui/index.tis"

    if [ ! -f "$index_file" ]; then
        return 0
    fi

    local brand_file=""
    brand_file=$(mktemp)
    _custom_sciter_custom_brand_block > "$brand_file"

    python3 - "$index_file" "$brand_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
brand = Path(sys.argv[2]).read_text(encoding="utf-8")
text = path.read_text(encoding="utf-8")

powered_block = (
    '{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" '
    '? <div .link .custom-rd-home-powered #powered-by style="color:#000;font-size:1.15em;'
    'text-decoration:underline;margin-bottom:0.4em">{translate(\'powered_by_me\')}</div> : ""}'
)
plain_tip = (
    "<div .lighter-text>{outgoing_only ? translate('outgoing_only_desk_tip') "
    ": translate('desk_tip')}</div>"
)
wrong_tip = plain_tip + (
    '{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" '
    '? <div .link #powered-by style="opacity:0.85;font-size:1em;text-decoration:underline;'
    'margin-top:0.4em">{translate(\'powered_by_me\')}</div> : ""} '
    '<!-- CUSTOM_RUSTDESK_HOME_POWERED -->'
)
old_header = (
    '{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" '
    '? <div .link #powered-by style="opacity:0.5;font-size:0.8em;text-decoration:underline">'
    "{translate('powered_by_me')}</div> : \"\"}"
)
old_click = 'event click $(#powered-by) {\n    handler.open_url("https://rustdesk.com");\n}'
new_click = (
    'event click $(#powered-by) { var link = handler.get_builtin_option("custom-customer-link"); '
    'handler.open_url(link && link.length ? link : "https://rustdesk.com"); }'
)
right_anchor = (
    "{!incoming_only && <div .right-pane>\n"
    "                    <div .right-content>\n"
    "                        <div .card-connect>"
)
right_with_powered = (
    "{!incoming_only && <div .right-pane>\n"
    "                    <div .right-content>\n"
    "                        " + powered_block + "\n"
    "                        <div .card-connect>"
)
text_only_brand = (
    '{is_custom_client ? <div #custom-brand style="text-align:center;margin-bottom:0.35em;'
    'font-size:1.1em;font-weight:bold">{handler.get_builtin_option("custom-customer-name")}'
    '</div> : ""}'
)
legacy_brand = re.compile(
    r"\{is_custom_client \? <div #custom-brand(?:\.custom-rd-home-header)?[^>]*>.*?"
    r"\{handler\.get_builtin_option\(\"custom-customer-name\"\)\}.*?</div> : \"\"\}",
    re.DOTALL,
)
legacy_powered = re.compile(
    r'\{is_custom_client && handler\.get_builtin_option\("hide-powered-by-me"\) != "Y" '
    r'\? <div \.link(?: \.custom-rd-home-powered)? #powered-by style="[^"]*">'
    r"\{translate\('powered_by_me'\)\}</div> : \"\"\}\s*"
    r'(?:<!-- CUSTOM_RUSTDESK_HOME_POWERED -->)?'
)

text = text.replace(" <!-- CUSTOM_RUSTDESK_HOME_POWERED -->", "")
text = text.replace(" <!-- CUSTOM_RUSTDESK_HOME_HEADER -->", "")
text = re.sub(r"\s*<!-- CUSTOM_RUSTDESK_HOME_LOGO -->", "", text)

changed = False

if old_header in text:
    text = text.replace(old_header, brand, 1)
    changed = True
elif text_only_brand in text and brand != text_only_brand:
    text = text.replace(text_only_brand, brand, 1)
    changed = True
elif "custom-rd-home-header" not in text and "#custom-brand" in text:
    match = legacy_brand.search(text)
    if match and match.group(0) != brand:
        text = legacy_brand.sub(brand, text, count=1)
        changed = True

if wrong_tip in text:
    text = text.replace(wrong_tip, plain_tip, 1)
    changed = True

if "custom-rd-home-powered" not in text:
    text = legacy_powered.sub("", text)
    if right_anchor not in text:
        raise SystemExit("source-patcher: missing sciter right-pane card-connect anchor")
    text = text.replace(right_anchor, right_with_powered, 1)
    changed = True
elif powered_block not in text:
    if right_anchor in text:
        text = legacy_powered.sub("", text)
        text = text.replace(right_anchor, right_with_powered, 1)
        changed = True

if old_click in text:
    text = text.replace(old_click, new_click, 1)
    changed = True

if not changed and "custom-rd-home-header" not in text and "custom-rd-home-powered" not in text:
    raise SystemExit("source-patcher: sciter home UI patch made no changes")

path.write_text(text, encoding="utf-8")
PY
    rm -f "$brand_file"

    if grep -q "custom-rd-home-header" "$index_file" &&
       grep -q "custom-rd-home-powered" "$index_file"; then
        if grep -q "card-connect" "$index_file" &&
           python3 - "$index_file" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "custom-rd-home-powered"
card = "<div .card-connect>"
idx_powered = text.find(marker)
idx_card = text.find(card)
if idx_powered == -1 or idx_card == -1 or idx_powered > idx_card:
    raise SystemExit(1)
PY
        then
            if grep -q "custom-rd-home-logo" "$index_file"; then
                echo "source-patcher: sciter home header with logo injected in $index_file"
            else
                echo "source-patcher: sciter home header injected in $index_file"
            fi
            echo "source-patcher: customer powered_by injected above Control Remote Desktop in $index_file"
        else
            echo "source-patcher: sciter powered_by marker is not above card-connect in $index_file" >&2
            return 1
        fi
    else
        echo "source-patcher: failed to inject sciter home UI in $index_file" >&2
        return 1
    fi
}

_custom_patch_custom_ui_text() {
    local customer_name="${CUSTOM_CUSTOMER:-定制客户}"
    local customer_link="${CUSTOM_CUSTOMER_LINK:-https://zzsn.work}"
    local studio_text="由郑州熵能科技工作室为${customer_name}倾情打造。"
    local powered_by_cn="由${customer_name}提供支持"
    local powered_by_en="Powered by ${customer_name}"
    local studio_text_json powered_by_cn_json powered_by_en_json customer_link_json
    local about_file="flutter/lib/desktop/pages/desktop_setting_page.dart"
    local home_file="flutter/lib/desktop/pages/desktop_home_page.dart"

    studio_text_json=$(_custom_json_string "$studio_text")
    powered_by_cn_json=$(_custom_json_string "$powered_by_cn")
    powered_by_en_json=$(_custom_json_string "$powered_by_en")
    customer_link_json=$(_custom_json_string "$customer_link")

    if [ -f "src/lang/cn.rs" ]; then
        perl -0pi -e "s/(\(\"powered_by_me\", )\"[^\"]*\"/\1$powered_by_cn_json/" "src/lang/cn.rs"
        if ! grep -q 'custom_studio_attribution' "src/lang/cn.rs"; then
            perl -0pi -e "s{(\(\"powered_by_me\", \"[^\"]*\"\),)}{\1\n        (\"custom_studio_attribution\", $studio_text_json),}" "src/lang/cn.rs"
        fi
    fi
    if [ -f "src/lang/en.rs" ]; then
        perl -0pi -e "s/(\(\"powered_by_me\", )\"[^\"]*\"/\1$powered_by_en_json/" "src/lang/en.rs"
        if ! grep -q 'custom_studio_attribution' "src/lang/en.rs"; then
            perl -0pi -e "s{(\(\"powered_by_me\", \"[^\"]*\"\),)}{\1\n        (\"custom_studio_attribution\", $studio_text_json),}" "src/lang/en.rs"
        fi
    fi

    if [ -f "$about_file" ] && ! grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file"; then
        perl -0pi -e "s{(translate\\('Slogan_tip'\\),\\n\\s*style: TextStyle\\(\\n\\s*fontWeight: FontWeight\\.w800,\\n\\s*color: Colors\\.white\\),\\n\\s*\\))}{\$1,\\n                          const SizedBox(height: 12),\\n                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION\\n                          InkWell(\\n                            onTap: () {\\n                              final link = bind.mainGetBuildinOption(key: \"custom-customer-link\");\\n                              if (link.isNotEmpty) launchUrlString(link);\\n                            },\\n                            child: Text(\\n                              translate('custom_studio_attribution'),\\n                              style: const TextStyle(\\n                                  fontWeight: FontWeight.w800,\\n                                  fontSize: 13,\\n                                  color: Colors.white,\\n                                  decoration: TextDecoration.underline),\\n                            ),\\n                          )}" "$about_file"
        if grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file"; then
            echo "source-patcher: studio attribution injected below Slogan_tip in $about_file"
        else
            echo "source-patcher: failed to inject studio attribution in $about_file" >&2
            return 1
        fi
    elif [ -f "$about_file" ] && grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file" &&
        ! grep -q "SizedBox(height: 12)" "$about_file"; then
        perl -0pi -e "s{(// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION)}{const SizedBox(height: 12),\\n                          \$1}" "$about_file"
        echo "source-patcher: studio attribution spacing added in $about_file"
    fi

    if [ -f "src/ui/index.tis" ] && ! grep -q "studio-about" "src/ui/index.tis"; then
        perl -0pi -e "s#(<p style='font-weight: bold'>\" \\+ translate\\(\"Slogan_tip\"\\) \\+ \"</p>\\\\)#\$1\\n            <br />\\\\\\n            <p class='link custom-event studio-about' style='font-weight: bold' url='\" + handler.get_builtin_option(\"custom-customer-link\") + \"'>\" + translate(\"custom_studio_attribution\") + \"</p>\\\\#g" "src/ui/index.tis"
        if grep -q "studio-about" "src/ui/index.tis"; then
            echo "source-patcher: studio attribution injected below Slogan_tip in src/ui/index.tis"
        else
            echo "source-patcher: failed to inject studio attribution in src/ui/index.tis" >&2
            return 1
        fi
    elif [ -f "src/ui/index.tis" ] && grep -q "studio-about" "src/ui/index.tis"; then
        if python3 - "src/ui/index.tis" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "studio-about" not in text:
    raise SystemExit(0)
pattern = (
    r"(<p style='font-weight: bold'>\" \+ translate\(\"Slogan_tip\"\) \+ \"</p>\\\\)\s*"
    r"(<p class='link custom-event studio-about')"
)
if re.search(
    r"Slogan_tip\"\) \+ \"</p>\\\\\s*\n\s*<br />\\\\\s*\n\s*<p class='link custom-event studio-about'",
    text,
):
    raise SystemExit(0)
new_text, count = re.subn(
    pattern,
    r"\1\n            <br />\\\n            \2",
    text,
)
if count == 0:
    raise SystemExit("source-patcher: failed to add studio attribution spacing in index.tis")
path.write_text(new_text, encoding="utf-8")
print("updated")
PY
        then
            echo "source-patcher: studio attribution spacing added in src/ui/index.tis"
        fi
    fi

    if [ -f "$home_file" ] && ! grep -q "CUSTOM_RUSTDESK_HOME_HEADER" "$home_file"; then
        perl -0pi -e 's/if \(bind\.isCustomClient\(\)\)\s*Align\(\s*alignment: Alignment\.center,\s*child: loadPowered\(context\),\s*\),\s*Align\(\s*alignment: Alignment\.center,\s*child: loadLogo\(\),\s*\),/if (bind.isCustomClient())\n        Align(\n          alignment: Alignment.center,\n          child: Column(\n            mainAxisSize: MainAxisSize.min,\n            children: [\n              loadLogo(),\n              Text(\n                bind.mainGetBuildinOption(key: "custom-customer-name"),\n                style: Theme.of(context).textTheme.titleMedium,\n              ).marginOnly(top: 4),\n            ],\n          ),\n        ) \/\/ CUSTOM_RUSTDESK_HOME_HEADER\n      else ...[\n        Align(\n          alignment: Alignment.center,\n          child: loadPowered(context),\n        ),\n        Align(\n          alignment: Alignment.center,\n          child: loadLogo(),\n        ),\n      ],/s' "$home_file"
        perl -0pi -e 's/if \(bind\.isCustomClient\(\)\)\s*Align\(\s*alignment: Alignment\.center,\s*child: bind\.isCustomClient\(\) \? SizedBox\.shrink\(\) : loadPowered\(context\),\s*\),\s*Align\(\s*alignment: Alignment\.center,\s*child: loadLogo\(\),\s*\),/if (bind.isCustomClient())\n        Align(\n          alignment: Alignment.center,\n          child: Column(\n            mainAxisSize: MainAxisSize.min,\n            children: [\n              loadLogo(),\n              Text(\n                bind.mainGetBuildinOption(key: "custom-customer-name"),\n                style: Theme.of(context).textTheme.titleMedium,\n              ).marginOnly(top: 4),\n            ],\n          ),\n        ) \/\/ CUSTOM_RUSTDESK_HOME_HEADER\n      else ...[\n        Align(\n          alignment: Alignment.center,\n          child: loadPowered(context),\n        ),\n        Align(\n          alignment: Alignment.center,\n          child: loadLogo(),\n        ),\n      ],/s' "$home_file"
        if grep -q "CUSTOM_RUSTDESK_HOME_HEADER" "$home_file"; then
            echo "source-patcher: custom home header injected in $home_file"
        else
            echo "source-patcher: failed to inject custom home header in $home_file" >&2
            return 1
        fi
    fi

    if [ -f "$home_file" ] && grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$home_file"; then
        perl -0pi -e 's/\n\s*if \(bind\.isCustomClient\(\) && bind\.mainGetBuildinOption\(key: "hide-powered-by-me"\) != '\''Y'\''\)\n\s*GestureDetector\([\s\S]*?\)\.marginOnly\(top: 4\), \/\/ CUSTOM_RUSTDESK_HOME_POWERED//g' "$home_file"
        echo "source-patcher: removed misplaced customer powered_by from $home_file"
    fi

    local connection_file="flutter/lib/desktop/pages/connection_page.dart"
    if [ -f "$connection_file" ] && ! grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$connection_file"; then
        perl -0pi -e 's/(child: Column\(\n          children: \[\n)/$1            if (bind.isCustomClient())\n              Align(\n                alignment: Alignment.centerLeft,\n                child: loadPowered(context),\n              ).paddingOnly(left: 12, top: 12), \/\/ CUSTOM_RUSTDESK_HOME_POWERED\n/s' "$connection_file"
        if grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$connection_file"; then
            echo "source-patcher: customer powered_by injected above Control Remote Desktop in $connection_file"
        else
            echo "source-patcher: failed to inject customer powered_by in $connection_file" >&2
            return 1
        fi
    fi

    local common_file="flutter/lib/common.dart"
    if [ -f "$common_file" ]; then
        python3 - "$common_file" <<'PY'
import re
import sys
from pathlib import Path

SIGNATURE = "Widget loadPowered(BuildContext context)"
OLD_CHILD = """      child: Opacity(
          opacity: 0.5,
          child: Text(
            translate("powered_by_me"),
            overflow: TextOverflow.clip,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 9, decoration: TextDecoration.underline),
          )),"""
NEW_CHILD = """      child: bind.isCustomClient()
          ? Text(
              translate("powered_by_me"),
              overflow: TextOverflow.clip,
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  decoration: TextDecoration.underline),
            )
          : Opacity(
              opacity: 0.5,
              child: Text(
                translate("powered_by_me"),
                overflow: TextOverflow.clip,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 9, decoration: TextDecoration.underline),
              )),"""
PARTIAL_CHILD = """      child: Opacity(
          opacity: 0.5,
          child: Text(
            translate("powered_by_me"),
            overflow: TextOverflow.clip,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: bind.isCustomClient() ? 12 : 9,
                    decoration: TextDecoration.underline),
          )),"""
LAUNCH_PATTERNS = (
    "launchUrl(Uri.parse('https://rustdesk.com'));",
    'launchUrl(Uri.parse("https://rustdesk.com"));',
    "launchUrlString('https://rustdesk.com');",
    'launchUrlString("https://rustdesk.com");',
)
NEW_LAUNCH = (
    "final poweredLink = bind.isCustomClient()\n"
    '              ? bind.mainGetBuildinOption(key: "custom-customer-link")\n'
    '              : "https://rustdesk.com";\n'
    "          if (poweredLink.isNotEmpty) launchUrl(Uri.parse(poweredLink)); // CUSTOM_RUSTDESK_POWERED_LINK"
)


def extract_function(text, signature):
    start = text.find(signature)
    if start == -1:
        return None
    brace = text.find("{", start + len(signature))
    if brace == -1:
        return None
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return start, index + 1
    return None


path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
span = extract_function(text, SIGNATURE)
if span is None:
    raise SystemExit("source-patcher: loadPowered function not found in common.dart")

start, end = span
function_text = text[start:end]
changed = False

if "CUSTOM_RUSTDESK_POWERED_LINK" not in function_text:
    old_launch = next((item for item in LAUNCH_PATTERNS if item in function_text), None)
    if old_launch is None:
        raise SystemExit("source-patcher: loadPowered launchUrl pattern not found in common.dart")
    function_text = function_text.replace(old_launch, NEW_LAUNCH, 1)
    changed = True

if NEW_CHILD not in function_text:
    if OLD_CHILD in function_text:
        function_text = function_text.replace(OLD_CHILD, NEW_CHILD, 1)
        changed = True
    elif PARTIAL_CHILD in function_text:
        function_text = function_text.replace(PARTIAL_CHILD, NEW_CHILD, 1)
        changed = True
    elif "fontSize: bind.isCustomClient() ? 14 : 9" in function_text:
        pass
    else:
        raise SystemExit("source-patcher: loadPowered style pattern not found in common.dart")

if changed:
    path.write_text(text[:start] + function_text + text[end:], encoding="utf-8")
PY
        if grep -q "CUSTOM_RUSTDESK_POWERED_LINK" "$common_file" &&
           grep -q "fontSize: 14" "$common_file" &&
           grep -q "Colors.black" "$common_file"; then
            echo "source-patcher: custom powered_by link and style wired in $common_file"
        else
            echo "source-patcher: failed to patch powered_by in $common_file" >&2
            return 1
        fi
    fi

    _custom_patch_sciter_home_ui
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

_custom_patch_msi_preprocess_app_name() {
    local file="res/msi/preprocess.py"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping MSI app-name source patch"
        return 0
    fi

    if grep -q "CUSTOM_RUSTDESK_MSI_APP_NAME" "$file"; then
        echo "source-patcher: MSI app-name source patch already applied in $file"
        return 0
    fi

    python3 - "$file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
helpers = '''
def _custom_rustdesk_repo_root():
    return Path(__file__).resolve().parents[2]


def _custom_rustdesk_build_app_name():
    config_path = _custom_rustdesk_repo_root() / "custom-build-config.json"
    if not config_path.exists():
        return ""
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    return (config.get("app_name") or "").strip()


def _custom_rustdesk_prepare_dist_exe(dist_dir, app_name):
    if not app_name or app_name == "RustDesk":
        return
    source_exe = dist_dir / "rustdesk.exe"
    target_exe = dist_dir / f"{app_name}.exe"
    if source_exe.exists() and source_exe != target_exe:
        shutil.copy2(source_exe, target_exe)
        source_exe.unlink()
'''
anchor = "def make_parser():"
main_old = """    app_name = args.app_name
    dist_dir = Path(sys.argv[0]).parent.joinpath(args.dist_dir).resolve()
"""
main_new = """    app_name = args.app_name
    # CUSTOM_RUSTDESK_MSI_APP_NAME
    if app_name == "RustDesk":
        custom_name = _custom_rustdesk_build_app_name()
        if custom_name:
            args.app_name = custom_name
            app_name = args.app_name
    dist_dir = Path(sys.argv[0]).parent.joinpath(args.dist_dir).resolve()
    _custom_rustdesk_prepare_dist_exe(dist_dir, app_name)
"""
if anchor not in text:
    raise SystemExit(f"source-patcher: make_parser anchor not found in {path}")
if main_old not in text:
    raise SystemExit(f"source-patcher: preprocess main block anchor not found in {path}")
text = text.replace(anchor, helpers + anchor, 1)
text = text.replace(main_old, main_new, 1)
path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_MSI_APP_NAME" "$file"; then
        echo "source-patcher: MSI app-name source patch applied in $file"
    else
        echo "source-patcher: failed to patch MSI app-name in $file" >&2
        return 1
    fi
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

    case "${BUILD_HIDE_NETWORK_SETTINGS:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON)
            CUSTOM_HIDE_NETWORK_SETTINGS="true"
            ;;
        false|FALSE|False|0|no|NO|n|N|off|OFF|"")
            CUSTOM_HIDE_NETWORK_SETTINGS="false"
            ;;
        *)
            echo "source-patcher: unsupported hide_network_settings '${BUILD_HIDE_NETWORK_SETTINGS}'" >&2
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
    _custom_trace_value "BUILD_HIDE_NETWORK_SETTINGS(raw)" "${BUILD_HIDE_NETWORK_SETTINGS:-}"
    _custom_trace_value "CUSTOM_HIDE_NETWORK_SETTINGS(normalized)" "$CUSTOM_HIDE_NETWORK_SETTINGS"
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
        --arg hide_network_settings "$CUSTOM_HIDE_NETWORK_SETTINGS" \
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
            hide_network_settings: ($hide_network_settings == "true"),
            source_patch_debug: ($source_patch_debug == "true")
        }' > custom-build-config.json

    _custom_patch_common_rs
    _custom_patch_hbb_common_config_rs
    _custom_patch_brand_files
    _custom_patch_logo_assets
    _custom_patch_custom_ui_text
    _custom_patch_portable_working_dir
    _custom_patch_windows_test_signing
    _custom_patch_msi_preprocess_app_name
    _custom_patch_rust_cache_nonfatal

    echo "source-patcher: custom source patches applied"
}
