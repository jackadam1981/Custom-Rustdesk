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
! grep -q CUSTOM_RUSTDESK_HOME_POWERED flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F10 no HOME_POWERED on home' || bad 'F10 no HOME_POWERED on home'
grep -q CUSTOM_RUSTDESK_HOME_SLOGAN flutter/lib/desktop/pages/desktop_home_page.dart && ok 'F10 HOME_SLOGAN slot' || bad 'F10 HOME_SLOGAN slot'
grep -q CUSTOM_RUSTDESK_HOME_POWERED flutter/lib/desktop/pages/connection_page.dart && ok 'F11 POWERED on connection' || bad 'F11 POWERED on connection'
grep -q CUSTOM_RUSTDESK_POWERED_STYLE flutter/lib/common.dart && ok 'F11 POWERED_STYLE' || bad 'F11 POWERED_STYLE'
grep -q CUSTOM_RUSTDESK_STUDIO_LINK flutter/lib/desktop/pages/desktop_setting_page.dart && ok 'F12 STUDIO_LINK' || bad 'F12 STUDIO_LINK'
! grep -q CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN flutter/lib/desktop/pages/desktop_setting_page.dart && ok 'F12 about original spacing' || bad 'F12 about original spacing'
grep -q CUSTOM_RUSTDESK_UI_APP_NAME flutter/lib/common.dart && ok 'F02 UI_APP_NAME' || bad 'F02 UI_APP_NAME'

echo ""
echo "========== Sciter skill (patched source) =========="
grep -Fq 'custom-rd-home-title-row' src/ui/index.tis && ok 'S10 title-row' || bad 'S10 title-row'
grep -Fq 'flow:horizontal' src/ui/index.tis && ok 'S10 flow horizontal' || bad 'S10 flow horizontal'
grep -Fq 'font-weight:bold;display:inline-block' src/ui/index.tis && ok 'S10 inline-block title' || bad 'S10 inline-block title'
! grep -Fq 'display:block;margin:0 auto' src/ui/index.tis && ok 'S10 no display:block logo stack' || bad 'S10 no display:block logo stack'
grep -Fq 'custom-rd-home-slogan' src/ui/index.tis && ok 'S10 slogan row' || bad 'S10 slogan row'
grep -Fq 'custom-rd-home-powered' src/ui/index.tis && ok 'S10 powered on right pane' || bad 'S10 powered on right pane'
if python3 -c "from pathlib import Path;t=Path('src/ui/index.tis').read_text(encoding='utf-8');h=t.find('custom-rd-home-header');assert t.find('#powered-by')<t.find('<div .card-connect>') and '#powered-by' not in t[h:h+4000]"; then ok 'S10 powered above card, not in left brand'; else bad 'S10 powered placement'; fi
! grep -Fq 'flow: horizontal-flow' src/ui/index.css && ok 'S13 menu no horizontal-flow' || bad 'S13 menu no horizontal-flow'
! grep -Fq 'width: 48%' src/ui/index.css && ok 'S13 menu no li width hack' || bad 'S13 menu no li width hack'
grep -Fq 'max-height: 80vh' src/ui/index.css && ok 'S13 menu max-height css' || bad 'S13 menu max-height css'
grep -Fq 'overflow-y: scroll-indicator' src/ui/index.css && ok 'S13 menu scroll css' || bad 'S13 menu scroll css'
! grep -Fq 'CUSTOM_RUSTDESK_CONFIG_MENU_WIDTH' src/ui/index.tis && ok 'S13 menu no tis width hook' || bad 'S13 menu no tis width hook'
! grep -Fq 'CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT' src/ui/index.tis && ok 'S13 menu no overflow hook' || bad 'S13 menu no overflow hook'
grep -Fq 'studio-about' src/ui/index.tis && ok 'S12 studio-about' || bad 'S12 studio-about'
grep -Fq 'CUSTOM_RUSTDESK_ABOUT_HEIGHT' src/ui/index.tis && ok 'S12 about height' || bad 'S12 about height'

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
map_check F01 core/is-custom-client.sh 'CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT'
map_check F02 flutter/app-name.sh 'CUSTOM_RUSTDESK_UI_APP_NAME'
map_check F03 brand/logo-assets.sh 'flutter/assets/logo.png'
map_check F10 flutter/home-header.sh 'CUSTOM_RUSTDESK_HOME_HEADER'
map_check F11 flutter/powered-by.sh 'CUSTOM_RUSTDESK_POWERED_STYLE'
map_check F12 flutter/about-studio.sh 'CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION'
map_check S01 i18n/ui-strings.sh 'custom_studio_attribution'
map_check S10 sciter/home-ui.sh 'custom-rd-home-slogan'
map_check S10b lib/sciter-brand.sh 'custom-rd-home-title-row'
map_check S12 sciter/about-studio.sh 'studio-about'
map_check S13 sciter/config-menu-css.sh 'CUSTOM_RUSTDESK_CONFIG_MENU_FLOW'

echo ""
echo "========== orchestrator apply order =========="
grep '_custom_run_patch' "$PATCHES/orchestrator.sh" | sed 's/^[[:space:]]*//'

echo ""
echo "--- ui-skill-verify: PASS=$pass FAIL=$fail ---"
echo "patched tree: $UP"
test "$fail" -eq 0
