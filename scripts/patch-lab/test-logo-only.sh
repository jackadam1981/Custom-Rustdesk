#!/usr/bin/env bash

# logo-only 验收：仅 BUILD_LOGO_URL；icon 默认 RustDesk（branding/icon-rustdesk.png）

set -euo pipefail

export PATH="/c/Users/jacka/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe:$PATH"

ROOT="/d/My_Project/custom-rustdesk"

FIXTURE="$ROOT/downloads/R01-27751270327/patched-source"

WORK=$(mktemp -d)

trap 'rm -rf "$WORK"' EXIT



echo "logo-only test: copy fixture -> $WORK"

cp -a "$FIXTURE/." "$WORK/"



cd "$WORK"

rm -f flutter/assets/logo.png flutter/assets/banner.png flutter/assets/icon.png \

  flutter/assets/logo_light.png flutter/assets/logo_dark.png \

  res/logo.png res/banner.png res/icon.png res/tray-icon.ico 2>/dev/null || true



# shellcheck disable=SC1091

source "$ROOT/scripts/patch-lab/profiles/logo-only.env"

export CUSTOM_RUSTDESK_REPO="$ROOT"

export BUILD_TAG="logo-only-test"

export SOURCE_PATCH_UP_TO="S10"

export SOURCE_PATCH_ONLY=""

export CUSTOM_PATCH_APPLY_ALL=""



# shellcheck disable=SC1091

source "$ROOT/.github/workflows/scripts/source-patcher.sh"

apply_custom_source_patches



echo ""

echo "========== asset checks =========="

python3 - <<'PY'

import hashlib

from pathlib import Path

from PIL import Image



root = Path(".")

logo = root / "flutter/assets/logo.png"

icon = root / "flutter/assets/icon.png"

banner = root / "flutter/assets/banner.png"

default_icon = Path(__import__("os").environ.get("CUSTOM_RUSTDESK_REPO", ".")) / "branding/icon-rustdesk.png"



assert logo.is_file(), "logo.png missing"

im = Image.open(logo)

assert im.size == (72, 72), f"logo.png should be 72x72, got {im.size}"

print(f"OK logo.png {im.size}")



assert icon.is_file(), "icon.png missing (default RustDesk icon expected)"

im_icon = Image.open(icon)

assert im_icon.size == (256, 256), f"icon.png should be 256x256, got {im_icon.size}"

logo_hash = hashlib.sha256(logo.read_bytes()).hexdigest()

icon_hash = hashlib.sha256(icon.read_bytes()).hexdigest()

assert logo_hash != icon_hash, "logo.png and icon.png must differ (logo vs default RustDesk icon)"

if default_icon.is_file():

    def_hash = hashlib.sha256(default_icon.read_bytes()).hexdigest()

    assert icon_hash == def_hash, "icon.png should match branding/icon-rustdesk.png default"

print(f"OK icon.png default RustDesk {im_icon.size}")



if banner.exists():

    raise SystemExit(f"unexpected {banner} when only logo_url")



home = root / "flutter/lib/desktop/pages/desktop_home_page.dart"

text = home.read_text(encoding="utf-8")

for needle in (

    "CUSTOM_RUSTDESK_HOME_HEADER",

    "base64Decode",

    "Image.memory",

    "width: 48",

):

    assert needle in text, f"missing {needle} in home page"

assert "CUSTOM_RUSTDESK_HOME_POWERED" not in text, "powered-by must not be on home left pane"

print("OK F10 home header embeds logo.png as base64 Image.memory")



tis = (root / "src/ui/index.tis").read_text(encoding="utf-8")

assert "custom-rd-home-logo" in tis, "sciter home logo missing"

assert "custom-rd-home-header" in tis

print("OK S10 sciter home logo markup")



cfg = (root / "custom-build-config.json").read_text(encoding="utf-8")

assert '"logo_url"' in cfg

assert '"icon_url"' in cfg

print("OK custom-build-config.json has logo_url and default icon_url")

PY



echo ""

echo "logo-only test: PASSED"

