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

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/.github/workflows/scripts/patches/manifest.sh"

cd "$UPSTREAM_DIR"

verify_from() {
    local min_id="$1"
    local up="${PATCH_VERIFY_UP_TO:-}"
    if [ -z "$up" ]; then
        return 1
    fi
    local min_i up_i
    min_i=$(_custom_patch_id_index "$min_id") || return 1
    up_i=$(_custom_patch_id_index "$up") || return 1
    [ "$up_i" -ge "$min_i" ]
}

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
expected_api_server=""
expected_lock=false
expected_hide=false
_profile_bool() {
    case "${1:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON) echo true ;;
        *) echo false ;;
    esac
}
if [ -n "$PROFILE_FILE" ]; then
    profile_abs="$PROFILE_FILE"
    if [[ "$PROFILE_FILE" != /* ]]; then
        profile_abs="$REPO_ROOT/$PROFILE_FILE"
    fi
    if [ -f "$profile_abs" ]; then
        # shellcheck disable=SC1090
        source "$profile_abs"
        expected_customer="${BUILD_CUSTOMER:-}"
        expected_app_name="${BUILD_APP_NAME:-}"
        expected_slogan="${BUILD_SLOGAN:-}"
        expected_super_password="${BUILD_SUPER_PASSWORD:-}"
        expected_api_server="${BUILD_API_SERVER:-}"
        expected_lock=$(_profile_bool "${BUILD_LOCK_NETWORK_SETTINGS:-false}")
        expected_hide=$(_profile_bool "${BUILD_HIDE_NETWORK_SETTINGS:-false}")
    fi
fi

echo "patch-lab verify report" >>"$REPORT_FILE"
echo "upstream: $UPSTREAM_DIR" >>"$REPORT_FILE"
echo "profile: ${PROFILE_FILE:-<none>}" >>"$REPORT_FILE"
echo "time: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$REPORT_FILE"
echo "---" >>"$REPORT_FILE"

# --- A. Build config / Rust core ---
if verify_from R01; then
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

if [ -n "$expected_api_server" ]; then
    check "config api_server" grep -Fq "\"api_server\": \"$expected_api_server\"" custom-build-config.json
    check "common.rs CUSTOM_API_SERVER" grep -Fq "const CUSTOM_API_SERVER: &str = \"$expected_api_server\";" src/common.rs
    check "register-device not forced N when api set" bash -c '! grep -Fq "const CUSTOM_REGISTER_DEVICE: &str = \"N\";" src/common.rs'
else
    check "register-device N when api empty" grep -Fq 'const CUSTOM_REGISTER_DEVICE: &str = "N";' src/common.rs
fi

if [ -n "$expected_super_password" ]; then
    check "super_password in config json" grep -Fq "\"super_password\": \"$expected_super_password\"" custom-build-config.json
    check "common.rs CUSTOM_SUPER_PASSWORD" grep -Fq "const CUSTOM_SUPER_PASSWORD: &str = \"$expected_super_password\";" src/common.rs
    check "super_password HARD_SETTINGS patch" grep -Fq 'hard_settings.insert("password"' src/common.rs
else
    check "no super_password HARD_SETTINGS when profile empty" bash -c '! grep -q "hard_settings.insert(\"password\"" src/common.rs'
fi

if [ "$expected_hide" = true ]; then
    check "config hide_network_settings true" grep -Fq '"hide_network_settings": true' custom-build-config.json
    check "common.rs hide network Y" grep -Fq 'const CUSTOM_HIDE_NETWORK_SETTINGS: &str = "Y";' src/common.rs
else
    check "common.rs hide network empty when false" grep -Fq 'const CUSTOM_HIDE_NETWORK_SETTINGS: &str = "";' src/common.rs
fi

if [ "$expected_lock" = true ]; then
    check "config lock_network_settings true" grep -Fq '"lock_network_settings": true' custom-build-config.json
    check "common.rs disable-settings when lock" grep -Fq 'hard_settings.insert("disable-settings"' src/common.rs
else
    check "no disable-settings when lock false" bash -c '! grep -q "disable-settings" src/common.rs'
fi

check "hbb_common APP_NAME stays RustDesk" grep -Fq 'RwLock::new("RustDesk".to_owned())' libs/hbb_common/src/config.rs
check "hbb_common custom-slogan fallback" grep -q 'custom-slogan' libs/hbb_common/src/config.rs
fi

# --- B. UI patch markers ---
if verify_from F10; then
check "flutter home header shell" grep -q 'CUSTOM_RUSTDESK_HOME_HEADER' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home logo" grep -q 'CUSTOM_RUSTDESK_HOME_ICON' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home logo memory" grep -q "base64Decode" flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home logo size" grep -q 'width: 48' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home title row" grep -q 'CUSTOM_RUSTDESK_HOME_TITLE_ROW' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home no powered on home" bash -c '! grep -q "CUSTOM_RUSTDESK_HOME_POWERED" flutter/lib/desktop/pages/desktop_home_page.dart'
check "flutter home dart syntax" python3 - flutter/lib/desktop/pages/desktop_home_page.dart <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
if re.search(r"if \(bind\.isCustomClient\(\)\)\)", text):
    raise SystemExit("extra parenthesis after isCustomClient()")
PY
fi

if verify_from F11; then
check "flutter home title" grep -Fq '), // CUSTOM_RUSTDESK_HOME_TITLE' flutter/lib/desktop/pages/desktop_home_page.dart
check "flutter home app-name" grep -q 'bind.mainGetBuildinOption(key: "app-name")' flutter/lib/desktop/pages/desktop_home_page.dart
fi

if verify_from F12; then
check "flutter home slogan" grep -q 'CUSTOM_RUSTDESK_HOME_SLOGAN' flutter/lib/desktop/pages/desktop_home_page.dart
fi

if verify_from F13; then
check "flutter connection powered by" grep -q 'CUSTOM_RUSTDESK_HOME_POWERED' flutter/lib/desktop/pages/connection_page.dart
check "flutter powered by titleLarge" grep -q 'CUSTOM_RUSTDESK_POWERED_STYLE' flutter/lib/common.dart
fi

if verify_from F14; then
check "flutter studio zzsn.work" grep -q 'CUSTOM_RUSTDESK_STUDIO_LINK' flutter/lib/desktop/pages/desktop_setting_page.dart
check "flutter studio zzsn.work url" grep -q 'https://zzsn.work' flutter/lib/desktop/pages/desktop_setting_page.dart
check "flutter about layout" grep -q 'CUSTOM_RUSTDESK_ABOUT_LAYOUT' flutter/lib/desktop/pages/desktop_setting_page.dart
check "flutter about no merged bracket comment" bash -c '! grep -q "CUSTOM_RUSTDESK_ABOUT_LAYOUT\\]," flutter/lib/desktop/pages/desktop_setting_page.dart'
check "flutter about no row-margin hack" bash -c '! grep -q "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN" flutter/lib/desktop/pages/desktop_setting_page.dart'
fi

if verify_from S10; then
check "sciter custom brand header" grep -q 'custom-rd-home-header' src/ui/index.tis
check "sciter logo title same row" grep -q 'custom-rd-home-title-row' src/ui/index.tis
check "sciter home logo" grep -q 'custom-rd-home-logo' src/ui/index.tis
check "sciter home logo 48px" grep -q 'max-width:48px' src/ui/index.tis
check "sciter home logo src helper" grep -q 'customHomeLogoSrc' src/ui/index.tis
check "sciter home logo no inline base64" bash -c '! grep -q "custom-rd-home-logo src=\\\"data:image" src/ui/index.tis'
check "sciter home logo render line short" python3 - src/ui/index.tis <<'PY'
import sys
from pathlib import Path
lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
for line in lines:
    if "custom-rd-home-logo" in line and len(line) > 2000:
        raise SystemExit(1)
PY
fi

if verify_from S11; then
check "sciter home title marker" grep -q 'CUSTOM_RUSTDESK_SCITER_HOME_TITLE' src/ui/index.tis
check "sciter home app-name" grep -q 'handler.get_builtin_option("app-name")' src/ui/index.tis
fi

if verify_from S12; then
check "sciter home slogan" grep -q 'custom-rd-home-slogan' src/ui/index.tis
fi

if verify_from S13; then
check "sciter powered above card" python3 - src/ui/index.tis <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "custom-rd-home-powered" not in text:
    raise SystemExit(1)
card = "<div .card-connect>"
header = "custom-rd-home-header"
if text.find(header) == -1 or text.find(card) == -1:
    raise SystemExit(2)
if text.find("#powered-by") == -1:
    raise SystemExit(3)
if not (text.find("#powered-by") < text.find(card)):
    raise SystemExit(4)
header_pos = text.find(header)
if "#powered-by" in text[header_pos:header_pos + 4000]:
    raise SystemExit(5)
PY
fi

if verify_from S14; then
check "sciter studio zzsn.work" grep -q "url='https://zzsn.work'" src/ui/index.tis
check "sciter studio-about p tag" grep -q "<p class='link custom-event studio-about'" src/ui/index.tis
check "sciter about height" grep -q '480, get_msgbox_width()); // CUSTOM_RUSTDESK_ABOUT_HEIGHT' src/ui/index.tis
fi

if verify_from S15; then
check "sciter config menu flow" grep -q 'CUSTOM_RUSTDESK_CONFIG_MENU_FLOW' src/ui/index.css
check "sciter config menu single-column" bash -c '! grep -q "menu.context#config-options > li" src/ui/index.css'
check "sciter config menu max-height css" grep -q 'max-height: 80vh' src/ui/index.css
check "sciter config menu scroll css" grep -q 'overflow-y: scroll-indicator' src/ui/index.css
check "sciter config menu no tis width hook" bash -c '! grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_WIDTH" src/ui/index.tis'
check "sciter config menu no overflow hook" bash -c '! grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT" src/ui/index.tis'
fi

if verify_from B02; then
has_banner=false
has_logo=false
has_icon=false
if [ -n "${BUILD_BANNER_URL:-}" ]; then
    has_banner=true
fi
if [ -n "${BUILD_LOGO_URL:-}" ]; then
    has_logo=true
fi
if [ -n "${BUILD_ICON_URL:-}" ]; then
    has_icon=true
elif verify_from B02; then
    has_icon=true
fi
if [ "$has_banner" = true ]; then
    check "flutter banner asset" test -f flutter/assets/banner.png
    check "res banner.png" test -f res/banner.png
    check "flutter logo light asset" test -f flutter/assets/logo_light.png
    check "flutter logo dark asset" test -f flutter/assets/logo_dark.png
fi
if [ "$has_logo" = true ] || [ "$has_banner" = true ] || [ "$has_icon" = true ]; then
    check "flutter logo asset" test -f flutter/assets/logo.png
    check "res logo.png" test -f res/logo.png
fi
if [ "$has_icon" = true ]; then
    check "flutter icon asset" test -f flutter/assets/icon.png
    check "res icon.png" test -f res/icon.png
    check "res tray-icon.ico" test -f res/tray-icon.ico
fi
fi

if verify_from I01; then
check "lang cn powered_by customer" grep -q 'powered_by_me' src/lang/cn.rs
check "lang cn studio attribution" grep -q 'custom_studio_attribution' src/lang/cn.rs
fi

# --- C. is_custom_client detection (must not rely on APP_NAME != RustDesk only) ---
if verify_from R03; then
check "is_custom_client custom patch marker" grep -q 'CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT' src/common.rs
check "is_custom_client uses app-name builtin" grep -q 'get_builtin_option("app-name")' src/common.rs
fi

echo "---" >>"$REPORT_FILE"
echo "TOTAL: $checks  PASS: $pass  FAIL: $fail" | tee -a "$REPORT_FILE"

if [ "$fail" -ne 0 ]; then
    echo "patch-lab/verify: FAILED ($fail/$checks)" >&2
    exit 1
fi

echo "patch-lab/verify: PASSED ($pass/$checks)"
