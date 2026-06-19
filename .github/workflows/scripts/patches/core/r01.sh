# R01 — 连接/服务器默认（1 个 rollout 针 = 1 个脚本）
# 改 2 个上游文件：src/common.rs + libs/hbb_common/src/config.rs
# 连接七项：ID / 中继 / API / Key / 超级密码 / 锁定网络 / 隐藏网络
# api_server 空则不写 api-server；super_password 空则不写 password；
# lock_network_settings=true → HARD_SETTINGS + disable-settings；
# hide_network_settings=true → hide-server/network-settings=Y。

_custom_patch_r01() {
    _r01_patch_common_rs
    _r01_patch_hbb_common_config_rs
}

_r01_patch_common_rs() {
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

    local app_name_json slogan_json customer_link_json customer_name_json rendezvous_json relay_json api_json key_json register_device_json hide_network_json super_password_json
    app_name_json=$(_custom_json_string "$CUSTOM_APP_NAME")
    slogan_json=$(_custom_json_string "$CUSTOM_SLOGAN")
    customer_link_json=$(_custom_json_string "$CUSTOM_CUSTOMER_LINK")
    customer_name_json=$(_custom_json_string "${CUSTOM_CUSTOMER:-定制客户}")
    rendezvous_json=$(_custom_json_string "$CUSTOM_RENDEZVOUS_SERVER")
    relay_json=$(_custom_json_string "$CUSTOM_RELAY_SERVER")
    api_json=$(_custom_json_string "$CUSTOM_API_SERVER")
    key_json=$(_custom_json_string "$CUSTOM_RS_PUB_KEY")
    super_password_json=$(_custom_json_string "${CUSTOM_SUPER_PASSWORD:-}")
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
    const CUSTOM_SUPER_PASSWORD: &str = $super_password_json;

    if !CUSTOM_APP_NAME.is_empty() {
        // UI-only: keep config::APP_NAME as RustDesk for MSI/install/registry paths.
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
    if !CUSTOM_SUPER_PASSWORD.is_empty() {
        let mut hard_settings = config::HARD_SETTINGS.write().unwrap();
        hard_settings.insert("password".to_owned(), CUSTOM_SUPER_PASSWORD.to_owned());
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
    perl -0pi -e 's/pub fn get_custom_rendezvous_server\(custom: String\) -> String \{\n/pub fn get_custom_rendezvous_server(custom: String) -> String {\n    apply_custom_build_defaults();\n    let custom = if custom.is_empty() {\n        config::Config::get_option("custom-rendezvous-server")\n    } else {\n        custom\n    };\n/' "$file"
    perl -0pi -e 's/pub fn get_api_server\(api: String, custom: String\) -> String \{\n/pub fn get_api_server(api: String, custom: String) -> String {\n    apply_custom_build_defaults();\n    if api.is_empty()\n        && config::Config::get_option("api-server").is_empty()\n        && config::Config::get_option("register-device") == "N"\n    {\n        return "".to_owned();\n    }\n/' "$file"

    _custom_trace_file_match "after" "$file" "custom patch marker" 'CUSTOM_RUSTDESK_PATCH_START|CUSTOM_RUSTDESK_PATCH_END'
    _custom_trace_file_match "after" "$file" "custom injected constants" 'const CUSTOM_'
    _custom_trace_file_match "after" "$file" "apply defaults calls" 'apply_custom_build_defaults\(\);'
    _custom_trace_file_match "after" "$file" "custom settings keys" '"custom-rendezvous-server"|"relay-server"|"api-server"|"key"'
}

_r01_patch_hbb_common_config_rs() {
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
