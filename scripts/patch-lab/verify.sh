#!/usr/bin/env bash
# Static verification of patched upstream RustDesk tree (post source-patcher).
set -euo pipefail

UPSTREAM_DIR="${1:-}"
REPORT_FILE="${2:-}"
PROFILE_FILE="${3:-}"

if [ -z "$UPSTREAM_DIR" ] || [ ! -d "$UPSTREAM_DIR" ]; then
    echo "patch-lab/verify: upstream directory required" >&2
    exit 1
fi

if [ -z "$REPORT_FILE" ]; then
    echo "patch-lab/verify: report file path required" >&2
    exit 1
fi

mkdir -p "$(dirname "$REPORT_FILE")"
: >"$REPORT_FILE"

cd "$UPSTREAM_DIR"

checks=0
pass=0
fail=0

log_pass() {
    pass=$((pass + 1))
    echo "PASS: $1" | tee -a "$REPORT_FILE"
}

log_fail() {
    fail=$((fail + 1))
    echo "FAIL: $1" | tee -a "$REPORT_FILE"
}

check() {
    local name="$1"
    shift
    checks=$((checks + 1))
    if "$@"; then
        log_pass "$name"
    else
        log_fail "$name"
    fi
}

# Load expected values from profile when available
expected_customer=""
expected_app_name=""
expected_slogan=""
expected_super_password=""
if [ -n "$PROFILE_FILE" ] && [ -f "$PROFILE_FILE" ]; then
    # shellcheck disable=SC1090
    source "$PROFILE_FILE"
    expected_customer="${BUILD_CUSTOMER:-}"
    expected_app_name="${BUILD_APP_NAME:-}"
    expected_slogan="${BUILD_SLOGAN:-}"
    expected_super_password="${BUILD_SUPER_PASSWORD:-}"
fi

echo "patch-lab verify report" >>"$REPORT_FILE"
echo "upstream: $UPSTREAM_DIR" >>"$REPORT_FILE"
echo "profile: ${PROFILE_FILE:-<none>}" >>"$REPORT_FILE"
echo "time: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$REPORT_FILE"
echo "---" >>"$REPORT_FILE"

# --- A. Build config / Rust core ---
check "custom-build-config.json exists" test -f custom-build-config.json

if [ -n "$expected_app_name" ]; then
    check "config app_name" grep -Fq "\"app_name\": \"$expected_app_name\"" custom-build-config.json
fi
if [ -n "$expected_customer" ]; then
    check "config customer" grep -Fq "\"customer\": \"$expected_customer\"" custom-build-config.json
fi
if [ -n "$expected_slogan" ]; then
    check "config slogan" grep -Fq "\"slogan\": \"$expected_slogan\"" custom-build-config.json
fi

check "common.rs patch marker" grep -q 'CUSTOM_RUSTDESK_PATCH_START' src/common.rs

if [ -n "$expected_app_name" ]; then
    check "common.rs CUSTOM_APP_NAME" grep -Fq "const CUSTOM_APP_NAME: &str = \"$expected_app_name\";" src/common.rs
fi
if [ -n "$expected_slogan" ]; then
    check "common.rs CUSTOM_SLOGAN" grep -Fq "const CUSTOM_SLOGAN: &str = \"$expected_slogan\";" src/common.rs
fi

check "hbb_common APP_NAME stays RustDesk" grep -Fq 'RwLock::new("RustDesk".to_owned())' libs/hbb_common/src/config.rs
check "hbb_common custom-slogan fallback" grep -q 'custom-slogan' libs/hbb_common/src/config.rs

if [ -n "$expected_super_password" ]; then
    check "super_password in config json" grep -Fq "\"super_password\": \"$expected_super_password\"" custom-build-config.json
    check "super_password HARD_SETTINGS patch" grep -Fq "hard_settings.insert(\"password\"" src/common.rs
else
    check "no super_password HARD_SETTINGS when profile empty" bash -c '! grep -q "hard_settings.insert(\"password\"" src/common.rs'
fi

# --- B. UI patch markers ---
check "flutter home header" grep -q 'CUSTOM_RUSTDESK_HOME_HEADER' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home icon" grep -q 'CUSTOM_RUSTDESK_HOME_ICON' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home slogan" grep -q 'CUSTOM_RUSTDESK_HOME_SLOGAN' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter connection powered by" grep -q 'CUSTOM_RUSTDESK_HOME_POWERED' flutter/lib/desktop/pages/connection_page.dart
check "flutter powered by titleLarge" grep -q 'CUSTOM_RUSTDESK_POWERED_STYLE' flutter/lib/common.dart
check "flutter studio zzsn.work" grep -q 'CUSTOM_RUSTDESK_STUDIO_LINK' flutter/lib/desktop/pages/desktop_setting_page.dart
check "flutter studio zzsn.work url" grep -q 'https://zzsn.work' flutter/lib/desktop/pages/desktop_setting_page.dart
check "flutter about layout" grep -q 'CUSTOM_RUSTDESK_ABOUT_LAYOUT' flutter/lib/desktop/pages/desktop_setting_page.dart

check "sciter custom brand header" grep -q 'custom-rd-home-header' src/ui/index.tis
check "sciter custom slogan markup" grep -q 'custom-slogan' src/ui/index.tis
check "sciter studio zzsn.work" grep -q "url='https://zzsn.work'" src/ui/index.tis
check "sciter studio-about p tag" grep -q "<p class='link custom-event studio-about'" src/ui/index.tis
check "sciter powered title class" grep -q 'custom-rd-home-powered #powered-by .title' src/ui/index.tis
check "sciter config menu flow" grep -q 'CUSTOM_RUSTDESK_CONFIG_MENU_FLOW' src/ui/index.css
check "sciter about dialog height" grep -q 'CUSTOM_RUSTDESK_ABOUT_HEIGHT' src/ui/index.tis
check "sciter powered above card-connect" python3 - src/ui/index.tis <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "custom-rd-home-powered"
card = "<div .card-connect>"
if text.find(marker) == -1 or text.find(card) == -1 or text.find(marker) > text.find(card):
    raise SystemExit(1)
PY

if [ -n "${BUILD_LOGO_URL:-}" ]; then
    check "flutter logo asset" test -f flutter/assets/logo.png
    check "flutter logo light asset" test -f flutter/assets/logo_light.png
    check "flutter logo dark asset" test -f flutter/assets/logo_dark.png
    check "res logo.png" test -f res/logo.png
    check "res icon.png" test -f res/icon.png
fi

check "lang cn powered_by customer" grep -q 'powered_by_me' src/lang/cn.rs
check "lang cn studio attribution" grep -q 'custom_studio_attribution' src/lang/cn.rs

# --- C. is_custom_client detection (must not rely on APP_NAME != RustDesk only) ---
check "is_custom_client custom patch marker" grep -q 'CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT' src/common.rs
check "is_custom_client uses app-name builtin" grep -q 'get_builtin_option("app-name")' src/common.rs

echo "---" >>"$REPORT_FILE"
echo "TOTAL: $checks  PASS: $pass  FAIL: $fail" | tee -a "$REPORT_FILE"

if [ "$fail" -ne 0 ]; then
    echo "patch-lab/verify: FAILED ($fail/$checks)" >&2
    exit 1
fi

echo "patch-lab/verify: PASSED ($pass/$checks)"
