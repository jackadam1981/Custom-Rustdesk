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
