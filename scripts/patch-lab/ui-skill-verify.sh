#!/usr/bin/env bash
# Verify patched tree + patch modules per Flutter/Sciter UI skills.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UP="${PATCHED_TREE:-/tmp/ui-src-verify/upstream/rustdesk-source}"
PATCHES="$ROOT/.github/workflows/scripts/patches"

if [ ! -d "$UP/flutter" ]; then
    echo "ui-skill-verify: patched tree not found: $UP" >&2
    echo "Run: bash scripts/patch-lab/ui-source-review.sh first" >&2
    exit 1
fi

pass=0
fail=0
ok() { echo "OK: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

cd "$UP"

echo "========== Flutter skill (patched source) =========="
if ! grep -q 'isCustomClient()))' flutter/lib/desktop/pages/desktop_home_page.dart; then ok 'F13 no isCustomClient()))'; else bad 'F13 no isCustomClient()))'; fi
grep -q CUSTOM_RUSTDESK_HOME_ICON flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F10 HOME_ICON' || bad 'F10 HOME_ICON'
grep -q CUSTOM_RUSTDESK_HOME_HEADER flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F10 HOME_HEADER' || bad 'F10 HOME_HEADER'
grep -q CUSTOM_RUSTDESK_HOME_TITLE_ROW flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F10 HOME_TITLE_ROW' || bad 'F10 HOME_TITLE_ROW'
! grep -q CUSTOM_RUSTDESK_HOME_POWERED flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F10 no HOME_POWERED on home' || bad 'F10 no HOME_POWERED on home'
grep -Fq '), // CUSTOM_RUSTDESK_HOME_TITLE' flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F11 HOME_TITLE' || bad 'F11 HOME_TITLE'
grep -q CUSTOM_RUSTDESK_HOME_SLOGAN flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F12 HOME_SLOGAN' || bad 'F12 HOME_SLOGAN'
grep -q CUSTOM_RUSTDESK_HOME_POWERED flutter/lib/desktop/pages/connection_page.dart && ok 'F13 POWERED on connection' || bad 'F13 POWERED on connection'
grep -q CUSTOM_RUSTDESK_POWERED_STYLE flutter/lib/common.dart && ok 'F13 POWERED_STYLE' || bad 'F13 POWERED_STYLE'
grep -q CUSTOM_RUSTDESK_STUDIO_LINK flutter/lib/desktop/pages/desktop_setting_page.dart && ok 'F14 STUDIO_LINK' || bad 'F14 STUDIO_LINK'
grep -q CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION flutter/lib/desktop/pages/desktop_setting_page.dart && ok 'F14 about studio marker' || bad 'F14 about studio marker'
grep -q translate\('custom_studio_attribution'\) flutter/lib/desktop/pages/desktop_setting_page.dart && ok 'F14 about studio text' || bad 'F14 about studio text'
! grep -q CUSTOM_RUSTDESK_ABOUT_UNIFIED_RICH flutter/lib/desktop/pages/desktop_setting_page.dart && ok 'F14 keeps upstream Text rows' || bad 'F14 keeps upstream Text rows'
grep -q CUSTOM_RUSTDESK_UI_APP_NAME flutter/lib/common.dart && ok 'F02 UI_APP_NAME' || bad 'F02 UI_APP_NAME'

echo ""
echo "========== Sciter skill (patched source) =========="
grep -Fq 'custom-rd-home-title-row' src/ui/index.tis && ok 'S10 title-row' || bad 'S10 title-row'
grep -Fq 'custom-rd-home-logo' src/ui/index.tis && ok 'S10 logo' || bad 'S10 logo'
grep -Fq 'max-width:48px' src/ui/index.tis && ok 'S10 logo 48px' || bad 'S10 logo 48px'
grep -Fq 'CUSTOM_RUSTDESK_SCITER_HOME_TITLE' src/ui/index.tis && ok 'S11 title marker' || bad 'S11 title marker'
grep -Fq 'font-weight:bold;display:inline-block' src/ui/index.tis && ok 'S11 inline-block title' || bad 'S11 inline-block title'
grep -Fq 'custom-rd-home-slogan' src/ui/index.tis && ok 'S12 slogan row' || bad 'S12 slogan row'
grep -Fq 'custom-rd-home-powered' src/ui/index.tis && ok 'S13 powered on right pane' || bad 'S13 powered on right pane'
if python3 -c "from pathlib import Path;t=Path('src/ui/index.tis').read_text(encoding='utf-8');h=t.find('custom-rd-home-header');assert t.find('#powered-by')<t.find('<div .card-connect>') and '#powered-by' not in t[h:h+4000]"; then ok 'S13 powered above card, not in left brand'; else bad 'S13 powered placement'; fi
! grep -Fq 'menu.context#config-options > li' src/ui/index.css && ok 'S15 menu single-column' || bad 'S15 menu single-column'
grep -Fq 'max-height: 80vh' src/ui/index.css && ok 'S15 menu max-height css' || bad 'S15 menu max-height css'
grep -Fq 'overflow-y: scroll-indicator' src/ui/index.css && ok 'S15 menu scroll css' || bad 'S15 menu scroll css'
! grep -Fq 'CUSTOM_RUSTDESK_CONFIG_MENU_WIDTH' src/ui/index.tis && ok 'S15 menu no tis width hook' || bad 'S15 menu no tis width hook'
! grep -Fq 'CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT' src/ui/index.tis && ok 'S15 menu no overflow hook' || bad 'S15 menu no overflow hook'
grep -Fq 'studio-about' src/ui/index.tis && ok 'S14 studio-about' || bad 'S14 studio-about'
grep -Fq 'CUSTOM_RUSTDESK_ABOUT_HEIGHT' src/ui/index.tis && ok 'S14 about height' || bad 'S14 about height'

echo ""
echo "========== Patch module ↔ registry ID =========="
map_check() {
    local id="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$PATCHES/$file" 2>/dev/null; then
        ok "$id -> patches/$file"
    else
        bad "$id missing in patches/$file ($pattern)"
    fi
}
map_check R03 core/is-custom-client.sh 'CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT'
map_check F02 flutter/app-name.sh 'CUSTOM_RUSTDESK_UI_APP_NAME'
map_check B02 brand/logo-assets.sh 'flutter/assets/logo.png'
map_check F10 flutter/home-logo.sh 'CUSTOM_RUSTDESK_HOME_ICON'
map_check F11 flutter/home-title.sh '), // CUSTOM_RUSTDESK_HOME_TITLE'
map_check F12 flutter/home-slogan.sh 'CUSTOM_RUSTDESK_HOME_SLOGAN'
map_check F13 flutter/powered-by.sh 'CUSTOM_RUSTDESK_POWERED_STYLE'
map_check F14 flutter/about-studio.sh 'CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION'
map_check I01 i18n/ui-strings.sh 'custom_studio_attribution'
map_check S10 sciter/home-logo.sh 'custom-rd-home-logo'
map_check S11 sciter/home-title.sh 'CUSTOM_RUSTDESK_SCITER_HOME_TITLE'
map_check S12 sciter/home-slogan.sh 'custom-rd-home-slogan'
map_check S13 sciter/powered-by.sh 'custom-rd-home-powered'
map_check S14 sciter/about-studio.sh 'studio-about'
map_check S15 sciter/config-menu-css.sh 'CUSTOM_RUSTDESK_CONFIG_MENU_FLOW'

echo ""
echo "========== orchestrator apply order =========="
grep '_custom_run_patch' "$PATCHES/orchestrator.sh" | sed 's/^[[:space:]]*//'

echo ""
echo "--- ui-skill-verify: PASS=$pass FAIL=$fail ---"
echo "patched tree: $UP"
test "$fail" -eq 0
