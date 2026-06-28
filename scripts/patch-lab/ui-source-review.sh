#!/usr/bin/env bash
# Deep UI source review on a freshly patched upstream tree (baixin profile).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH_ROOT="${PATCH_ROOT:-/tmp/ui-src-verify}"
UP="${PATCH_ROOT}/upstream/rustdesk-source"

rm -rf "$PATCH_ROOT"
mkdir -p "$PATCH_ROOT/upstream"
git clone --depth 1 --branch master --recurse-submodules --shallow-submodules \
    https://github.com/rustdesk/rustdesk.git "$UP"

# shellcheck disable=SC1091
source "$ROOT/scripts/patch-lab/profiles/baixin.env"
cd "$UP"
# shellcheck disable=SC1091
source "$ROOT/.github/workflows/scripts/source-patcher.sh"
apply_custom_source_patches

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

hf=flutter/lib/desktop/pages/desktop_home_page.dart
cf=flutter/lib/desktop/pages/connection_page.dart
cm=flutter/lib/common.dart
af=flutter/lib/desktop/pages/desktop_setting_page.dart
tis=src/ui/index.tis

# F1 Flutter home brand (logo + app_name + slogan; no powered-by on left pane)
if grep -q "CUSTOM_RUSTDESK_HOME_ICON" "$hf" &&
   grep -q "base64Decode" "$hf" &&
   grep -q "Image.memory" "$hf" &&
   grep -q "width: 48" "$hf" &&
   grep -q "textTheme.titleLarge" "$hf" &&
   grep -q "CUSTOM_RUSTDESK_HOME_SLOGAN" "$hf" &&
   ! grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$hf"; then
    ok "F1 home: logo/app_name row + slogan slot, no powered on left"
else
    bad "F1 home brand"
fi

# F2 Flutter connection powered
if grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$cf" &&
   grep -q "loadPowered(context)" "$cf" &&
   python3 - "$cf" "$cm" <<'PY'
import sys
from pathlib import Path

conn = Path(sys.argv[1]).read_text(encoding="utf-8")
common = Path(sys.argv[2]).read_text(encoding="utf-8")
fn = conn.split("Widget _buildRemoteIDTextField", 1)[-1]
if "CUSTOM_RUSTDESK_HOME_POWERED" not in fn:
    raise SystemExit(1)
if fn.find("CUSTOM_RUSTDESK_HOME_POWERED") > fn.find("          w,"):
    raise SystemExit(2)
chunk = common.split("Widget loadPowered(BuildContext context)", 1)[1][:1200]
if "titleLarge" not in chunk or "CUSTOM_RUSTDESK_POWERED_STYLE" not in chunk:
    raise SystemExit(3)
if "custom-customer-link" not in common:
    raise SystemExit(4)
PY
then
    ok "F2 connection: powered above card, titleLarge style, customer_link"
else
    bad "F2 flutter powered"
fi

# F3 Flutter about
if grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$af" &&
   grep -q "https://zzsn.work" "$af" &&
   grep -q "CUSTOM_RUSTDESK_ABOUT_LAYOUT" "$af" &&
   ! grep -q "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN" "$af" &&
   ! grep -q "CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT" "$af" &&
   ! grep -q "height: 2.0" "$af"; then
    ok "F3 about: studio below Slogan_tip, zzsn.work, original row spacing"
else
    bad "F3 flutter about"
fi

# F4 super password
if grep -Fq '"super_password": "Jack@1993"' custom-build-config.json &&
   grep -q 'hard_settings.insert("password"' src/common.rs; then
    ok "F4 super_password in config + HARD_SETTINGS"
else
    bad "F4 super_password"
fi

# F5 MSI identity
if grep -Fq 'RwLock::new("RustDesk".to_owned())' libs/hbb_common/src/config.rs; then
    ok "F5 APP_NAME stays RustDesk for MSI"
else
    bad "F5 MSI identity"
fi

# F6 logo / ico assets
if test -f flutter/assets/logo.png &&
   test -f flutter/assets/logo_light.png &&
   test -f flutter/assets/logo_dark.png &&
   test -f flutter/assets/icon.png &&
   test -f res/icon.png; then
    ok "logo assets: logo trio + icon png"
else
    bad "logo assets"
fi

if python3 - <<'PY'
from pathlib import Path
from PIL import Image

ico = Path("flutter/windows/runner/resources/app_icon.ico")
if not ico.exists():
    raise SystemExit("missing ico")
img = Image.open(ico)
sizes = sorted({s[0] for s in img.info.get("sizes", set())})
expected = [16, 20, 24, 32, 40, 48, 64, 128, 256]
if sizes != expected:
    raise SystemExit(f"got {sizes}, want {expected}")
PY
then
    ok "taskbar: app_icon.ico 9 sizes"
else
    bad "taskbar ico sizes"
fi

# S1 Sciter home (Pro layout)
if python3 - "$tis" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
need = [
    "custom-rd-home-logo",
    "custom-rd-home-title-row",
    "custom-rd-home-slogan",
    "flow:horizontal",
    "max-width:48px;max-height:48px;width:48px;height:48px",
    "font-weight:bold;display:inline-block",
]
missing = [n for n in need if n not in text]
if missing:
    raise SystemExit("missing: " + ", ".join(missing))
if "custom-rd-home-powered" not in text:
    raise SystemExit("missing custom-rd-home-powered on right pane")
brand = text.find("custom-rd-home-header")
powered = text.find("#powered-by")
card = text.find("<div .card-connect>")
if brand == -1 or powered == -1 or card == -1:
    raise SystemExit("missing brand, powered, or card anchor")
if not (powered < card):
    raise SystemExit("powered must be above card-connect, not in left brand block")
header_block = text[brand:brand + 4000]
if "#powered-by" in header_block:
    raise SystemExit("powered must not appear inside left brand header")
PY
then
    ok "S1 sciter home: logo+app_name+slogan; powered above card-connect"
else
    bad "S1 sciter home"
fi

# S2 Sciter powered click + no duplicate on card
if grep -q 'custom-customer-link' "$tis" &&
   grep -q 'custom-rd-home-powered' "$tis"; then
    ok "S2 sciter powered: customer link, above card-connect"
else
    bad "S2 sciter powered"
fi

# S3 Sciter about + menu
if grep -q "<p class='link custom-event studio-about'" "$tis" &&
   grep -q "CUSTOM_RUSTDESK_ABOUT_HEIGHT" "$tis" &&
   grep -q '<p style='"'"'font-weight: bold'"'"'>\" + translate(\"Slogan_tip\")' "$tis" &&
   grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_FLOW" src/ui/index.css &&
   ! grep -q 'menu.context#config-options > li' src/ui/index.css &&
   ! grep -q 'width: 48%' src/ui/index.css &&
   ! grep -q 'flow: horizontal-flow' src/ui/index.css &&
   grep -q 'max-height: 80vh' src/ui/index.css &&
   grep -q 'overflow-y: scroll-indicator' src/ui/index.css &&
   ! grep -q 'CUSTOM_RUSTDESK_CONFIG_MENU_WIDTH' "$tis" &&
   ! grep -q 'CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT' "$tis"; then
    ok "S3 sciter about p-tag + taller dialog + menu single-column scroll css"
else
    bad "S3 sciter about/menu"
fi

# i18n
if grep -Fq "由郑州百信科技有限公司提供支持" src/lang/cn.rs &&
   grep -Fq "郑州熵能科技工作室为郑州百信科技有限公司倾情打造" src/lang/cn.rs; then
    ok "i18n: powered_by + studio attribution (cn)"
else
    bad "i18n cn"
fi

# isCustomClient
if grep -q 'get_builtin_option("app-name")' src/common.rs; then
    ok "is_custom_client via app-name builtin"
else
    bad "is_custom_client"
fi

echo "---"
echo "UI source review: PASS=$pass FAIL=$fail"
echo "patched tree: $UP"
test "$fail" -eq 0
