_custom_patch_is_custom_client() {
    local file="src/common.rs"

    if [ ! -f "$file" ]; then
        return 0
    fi

    if grep -q "CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT" "$file"; then
        echo "source-patcher: is_custom_client already patched"
        return 0
    fi

    if ! grep -q 'get_app_name() != "RustDesk"' "$file"; then
        echo "source-patcher: is_custom_client anchor not found in $file, skipping"
        return 0
    fi

    python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
pattern = re.compile(
    r"pub fn is_custom_client\(\) -> bool \{\n    get_app_name\(\) != \"RustDesk\"\n\}"
)
replacement = """pub fn is_custom_client() -> bool {
    // CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT: app-name builtin marks UI custom build; APP_NAME stays RustDesk for MSI.
    if get_app_name() != "RustDesk" {
        return true;
    }
    if !get_builtin_option("app-name").is_empty() {
        return true;
    }
    !get_builtin_option("custom-customer-name").is_empty()
}"""
if not pattern.search(text):
    raise SystemExit("source-patcher: is_custom_client anchor not found in src/common.rs")
text = pattern.sub(replacement, text, count=1)
path.write_text(text, encoding="utf-8")
PY
    if grep -q "CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT" "$file"; then
        echo "source-patcher: is_custom_client uses app-name builtin in $file"
    else
        echo "source-patcher: failed to patch is_custom_client in $file" >&2
        return 1
    fi
}
