#!/usr/bin/env bash
# core/super_password.patch.sh – independent patch for super password

_custom_patch_super_password() {
    local file="src/common.rs"
    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping super password patch"
        return 0
    fi
    if grep -q "CUSTOM_RUSTDESK_SUPER_PASSWORD_PATCH_START" "$file"; then
        echo "source-patcher: super password patch already applied"
        return 0
    fi

    if grep -q "const CUSTOM_SUPER_PASSWORD" "$file"; then
        echo "source-patcher: super password constant already provided by R01, skipping P05"
        return 0
    fi

    local password_json=$(_custom_json_string "${CUSTOM_SUPER_PASSWORD:-}")
    local patch_file=$(mktemp)
    cat > "$patch_file" <<EOF
// CUSTOM_RUSTDESK_SUPER_PASSWORD_PATCH_START
    const CUSTOM_SUPER_PASSWORD: &str = $password_json;
// CUSTOM_RUSTDESK_SUPER_PASSWORD_PATCH_END
EOF
    awk -v pfile="$patch_file" '/^pub fn apply_custom_build_defaults\(\)/{print;system("cat "pfile);next}1' "$file" > "${file}.tmp"
    mv "${file}.tmp" "$file"
    rm -f "$patch_file"
    _custom_trace_file_match "after" "$file" "super password patch" 'CUSTOM_RUSTDESK_SUPER_PASSWORD_PATCH_START|CUSTOM_RUSTDESK_SUPER_PASSWORD_PATCH_END'
}
