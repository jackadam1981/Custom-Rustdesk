#!/usr/bin/env bash
# core/network_lock.patch.sh – independent patch for network lock / hide settings

_custom_patch_network_lock() {
    local file="src/common.rs"
    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping network lock patch"
        return 0
    fi
    if grep -q "CUSTOM_RUSTDESK_NETWORK_LOCK_PATCH_START" "$file"; then
        echo "source-patcher: network lock patch already applied"
        return 0
    fi

    if grep -q "const CUSTOM_HIDE_NETWORK_SETTINGS" "$file"; then
        echo "source-patcher: network lock constants already provided by R01, skipping N01"
        return 0
    fi

    local hide_json=$(_custom_json_string "${CUSTOM_HIDE_NETWORK_SETTINGS:-false}")
    local lock_json=$(_custom_json_string "${CUSTOM_LOCK_SETTINGS:-false}")
    local patch_file=$(mktemp)
    cat > "$patch_file" <<EOF
// CUSTOM_RUSTDESK_NETWORK_LOCK_PATCH_START
    const CUSTOM_HIDE_NETWORK_SETTINGS: &str = $hide_json;
    const CUSTOM_LOCK_SETTINGS: &str = $lock_json;
// CUSTOM_RUSTDESK_NETWORK_LOCK_PATCH_END
EOF
    awk -v pfile="$patch_file" '/^pub fn apply_custom_build_defaults\(\)/{print;system("cat "pfile);next}1' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    rm -f "$patch_file"
    _custom_trace_file_match "after" "$file" "network lock patch" 'CUSTOM_RUSTDESK_NETWORK_LOCK_PATCH_START|CUSTOM_RUSTDESK_NETWORK_LOCK_PATCH_END'
}
