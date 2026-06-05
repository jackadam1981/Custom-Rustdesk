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

    local app_name_json slogan_json customer_link_json rendezvous_json api_json key_json
    app_name_json=$(_custom_json_string "$CUSTOM_APP_NAME")
    slogan_json=$(_custom_json_string "$CUSTOM_SLOGAN")
    customer_link_json=$(_custom_json_string "$CUSTOM_CUSTOMER_LINK")
    rendezvous_json=$(_custom_json_string "$CUSTOM_RENDEZVOUS_SERVER")
    api_json=$(_custom_json_string "$CUSTOM_API_SERVER")
    key_json=$(_custom_json_string "$CUSTOM_RS_PUB_KEY")

    local patch_file
    patch_file=$(mktemp)
    cat > "$patch_file" <<EOF

// CUSTOM_RUSTDESK_PATCH_START
pub fn apply_custom_build_defaults() {
    const CUSTOM_APP_NAME: &str = $app_name_json;
    const CUSTOM_SLOGAN: &str = $slogan_json;
    const CUSTOM_CUSTOMER_LINK: &str = $customer_link_json;
    const CUSTOM_RENDEZVOUS_SERVER: &str = $rendezvous_json;
    const CUSTOM_API_SERVER: &str = $api_json;
    const CUSTOM_RS_PUB_KEY: &str = $key_json;

    if !CUSTOM_APP_NAME.is_empty() {
        *config::APP_NAME.write().unwrap() = CUSTOM_APP_NAME.to_owned();
    }

    let custom_settings = [
        ("app-name", CUSTOM_APP_NAME),
        ("custom-rendezvous-server", CUSTOM_RENDEZVOUS_SERVER),
        ("api-server", CUSTOM_API_SERVER),
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
        let mut hard_settings = config::HARD_SETTINGS.write().unwrap();
        for (key, value) in custom_settings {
            if !value.is_empty() {
                hard_settings.insert(key.to_owned(), value.to_owned());
            }
        }
        hard_settings.insert("disable-settings".to_owned(), "Y".to_owned());
    }
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

apply_custom_source_patches() {
    CUSTOM_APP_NAME="${BUILD_CUSTOMER:-${BUILD_TAG:-CustomRustDesk}}"
    CUSTOM_CUSTOMER_LINK="${BUILD_CUSTOMER_LINK:-}"
    CUSTOM_SLOGAN="${BUILD_SLOGAN:-}"
    CUSTOM_RENDEZVOUS_SERVER="${BUILD_RENDEZVOUS_SERVER:-}"
    CUSTOM_RS_PUB_KEY="${BUILD_RS_PUB_KEY:-}"
    CUSTOM_API_SERVER="${BUILD_API_SERVER:-}"

    jq -n \
        --arg app_name "$CUSTOM_APP_NAME" \
        --arg customer_link "$CUSTOM_CUSTOMER_LINK" \
        --arg slogan "$CUSTOM_SLOGAN" \
        --arg rendezvous_server "$CUSTOM_RENDEZVOUS_SERVER" \
        --arg rs_pub_key "$CUSTOM_RS_PUB_KEY" \
        --arg api_server "$CUSTOM_API_SERVER" \
        '{
            app_name: $app_name,
            customer_link: $customer_link,
            slogan: $slogan,
            rendezvous_server: $rendezvous_server,
            rs_pub_key: $rs_pub_key,
            api_server: $api_server
        }' > custom-build-config.json

    _custom_patch_common_rs
    _custom_patch_brand_files
    _custom_patch_sciter_ui_text

    echo "source-patcher: custom source patches applied"
}
