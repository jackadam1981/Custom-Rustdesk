#!/usr/bin/env python3
"""Split source-patcher.sh monolith into patches/ modules.

Usage (from repo root):
  python scripts/patch-lab/split-source-patcher.py           # HEAD monolith
  python scripts/patch-lab/split-source-patcher.py 5851659   # explicit commit
  python scripts/patch-lab/split-source-patcher.py 169039a   # patch-lab baseline
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCHES = ROOT / ".github/workflows/scripts"
ENTRY = PATCHES / "source-patcher.sh"
PATCH_DIR = PATCHES / "patches"


def load_monolith(ref: str) -> list[str]:
    path = ".github/workflows/scripts/source-patcher.sh"
    text = subprocess.check_output(
        ["git", "show", f"{ref}:{path}"],
        cwd=ROOT,
        text=True,
        encoding="utf-8",
    )
    return text.splitlines(keepends=True)


def slice_lines(lines: list[str], start: int, end: int) -> str:
    return "".join(lines[start - 1 : end])


def write_patch(rel: str, body: str) -> None:
    target = PATCH_DIR / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    if not body.endswith("\n"):
        body += "\n"
    target.write_text(body, encoding="utf-8")
    print(f"wrote {target.relative_to(ROOT)} ({len(body.splitlines())} lines)")


def find_function_range(lines: list[str], name: str) -> tuple[int, int]:
    start = None
    depth = 0
    for i, line in enumerate(lines, start=1):
        if start is None:
            if line.startswith(f"{name}()"):
                start = i
                if "{" in line and not line.rstrip().endswith("{"):
                    continue
                if "{" in line:
                    depth = line.count("{") - line.count("}")
                continue
        else:
            depth += line.count("{") - line.count("}")
            if depth <= 0 and (line.strip() == "}" or line.rstrip().endswith("}")):
                return start, i
    raise SystemExit(f"function not found: {name}")


def main() -> None:
    ref = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    lines = load_monolith(ref)
    print(f"split-source-patcher: ref={ref} lines={len(lines)}")

    write_patch("lib/common.sh", slice_lines(lines, 5, 101))
    write_patch("core/common-rs.sh", slice_lines(lines, 103, 257))
    write_patch("core/hbb-common.sh", slice_lines(lines, 259, 379))
    write_patch("brand/brand-files.sh", slice_lines(lines, 381, 403))
    write_patch("flutter/app-name.sh", slice_lines(lines, 405, 448))
    write_patch("brand/logo-assets.sh", slice_lines(lines, 450, 583))
    write_patch("lib/sciter-brand.sh", slice_lines(lines, 585, 620))
    write_patch("sciter/home-ui.sh", slice_lines(lines, 622, 793))

    # custom_ui_text sub-ranges (5851659 layout; 169039a lacks S13/about_layout — use 5851659)
    ref_line = len(lines)
    if ref_line >= 1600:
        cu_i18n_end = 821
        cu_about_start, cu_about_end = 823, 922
        cu_sciter_about_start, cu_sciter_about_end = 924, 978
        cu_home_start, cu_home_end = 980, 1078
        cu_powered_start, cu_powered_end = 1080, 1237
        about_layout_start, about_layout_end = 1491, 1533
        portable_start, portable_end = 1242, 1257
        windows_start, windows_end = 1259, 1350
        msi_start, msi_end = 1352, 1355
        rust_start, rust_end = 1357, 1387
        is_custom_start, is_custom_end = 1389, 1437
        sciter_css_start, sciter_css_end = 1439, 1489
    else:
        # 169039a baseline (no S13 / about_layout split)
        cu_i18n_end = 792
        cu_about_start, cu_about_end = 794, 893
        cu_sciter_about_start, cu_sciter_about_end = 895, 949
        cu_home_start, cu_home_end = 951, 1049
        cu_powered_start, cu_powered_end = 1051, 1127
        about_layout_start = about_layout_end = 0
        portable_start, portable_end = 1129, 1144
        windows_start, windows_end = 1206, 1237
        msi_start, msi_end = 1239, 1242
        rust_start, rust_end = 1244, 1274
        is_custom_start, is_custom_end = 1276, 1324
        sciter_css_start, sciter_css_end = 0, 0

    i18n_body = """_custom_patch_i18n_ui_strings() {
    local customer_name="${CUSTOM_CUSTOMER:-定制客户}"
    local studio_text="由郑州熵能科技工作室为${customer_name}倾情打造。"
    local powered_by_cn="由${customer_name}提供支持"
    local powered_by_en="Powered by ${customer_name}"
    local studio_text_json powered_by_cn_json powered_by_en_json

    studio_text_json=$(_custom_json_string "$studio_text")
    powered_by_cn_json=$(_custom_json_string "$powered_by_cn")
    powered_by_en_json=$(_custom_json_string "$powered_by_en")

    if [ -f "src/lang/cn.rs" ]; then
        perl -0pi -e "s/(\\(\\"powered_by_me\\", )\\"[^\\"]*\\"/\\1$powered_by_cn_json/" "src/lang/cn.rs"
        if ! grep -q 'custom_studio_attribution' "src/lang/cn.rs"; then
            perl -0pi -e "s{(\\(\\"powered_by_me\\", \\"[^\\"]*\\"\\),)}{\\1\\n        (\\"custom_studio_attribution\\", $studio_text_json),}" "src/lang/cn.rs"
        fi
    fi
    if [ -f "src/lang/en.rs" ]; then
        perl -0pi -e "s/(\\(\\"powered_by_me\\", )\\"[^\\"]*\\"/\\1$powered_by_en_json/" "src/lang/en.rs"
        if ! grep -q 'custom_studio_attribution' "src/lang/en.rs"; then
            perl -0pi -e "s{(\\(\\"powered_by_me\\", \\"[^\\"]*\\"\\),)}{\\1\\n        (\\"custom_studio_attribution\\", $studio_text_json),}" "src/lang/en.rs"
        fi
    fi
}
"""
    write_patch("i18n/ui-strings.sh", i18n_body)

    flutter_about = "_custom_patch_flutter_about_studio() {\n    local about_file=\"flutter/lib/desktop/pages/desktop_setting_page.dart\"\n\n"
    flutter_about += slice_lines(lines, cu_about_start, cu_about_end)
    if about_layout_start:
        about_layout = slice_lines(lines, about_layout_start, about_layout_end)
        about_layout = about_layout.replace(
            "_custom_patch_about_layout() {\n    local about_file=\"flutter/lib/desktop/pages/desktop_setting_page.dart\"\n\n",
            "",
        )
        flutter_about += "\n" + about_layout
    if not flutter_about.rstrip().endswith("}"):
        flutter_about += "}\n"
    write_patch("flutter/about-studio.sh", flutter_about)

    sciter_about = "_custom_patch_sciter_about_studio() {\n" + slice_lines(lines, cu_sciter_about_start, cu_sciter_about_end)
    if not sciter_about.rstrip().endswith("}"):
        sciter_about += "}\n"
    write_patch("sciter/about-studio.sh", sciter_about)

    home_body = "_custom_patch_flutter_home_header() {\n    local home_file=\"flutter/lib/desktop/pages/desktop_home_page.dart\"\n\n"
    home_body += slice_lines(lines, cu_home_start, cu_home_end)
    if not home_body.rstrip().endswith("}"):
        home_body += "}\n"
    write_patch("flutter/home-header.sh", home_body)

    powered_body = "_custom_patch_flutter_powered_by() {\n    local home_file=\"flutter/lib/desktop/pages/desktop_home_page.dart\"\n\n"
    powered_body += slice_lines(lines, cu_powered_start, cu_powered_end)
    if not powered_body.rstrip().endswith("}"):
        powered_body += "}\n"
    write_patch("flutter/powered-by.sh", powered_body)

    write_patch("platform/portable-workdir.sh", slice_lines(lines, portable_start, portable_end))
    write_patch("platform/windows-signing.sh", slice_lines(lines, windows_start, windows_end))
    write_patch("platform/msi-noop.sh", slice_lines(lines, msi_start, msi_end))
    write_patch("platform/rust-cache-nonfatal.sh", slice_lines(lines, rust_start, rust_end))
    write_patch("core/is-custom-client.sh", slice_lines(lines, is_custom_start, is_custom_end))
    if sciter_css_start:
        write_patch("sciter/config-menu-css.sh", slice_lines(lines, sciter_css_start, sciter_css_end))
    else:
        write_patch(
            "sciter/config-menu-css.sh",
            "_custom_patch_sciter_index_css() {\n    echo \"source-patcher: sciter config menu css patch not in this ref\"\n    return 0\n}\n",
        )

    write_patch(
        "manifest.sh",
        """# Patch ID registry — one ID = one module = one MR gate.
# Order matches apply_custom_source_patches.

CUSTOM_PATCH_IDS=(
    R01 R02 R03
    B01 B02
    I01
    F02 F10 F11 F12
    S10 S12 S13
    P01 P02 P03 P04
)

_custom_patch_id_index() {
    local want="$1"
    local i=0
    for id in "${CUSTOM_PATCH_IDS[@]}"; do
        if [ "$id" = "$want" ]; then
            echo "$i"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

_custom_should_run_patch() {
    local id="$1"
    local only="${SOURCE_PATCH_ONLY:-}"
    local up_to="${SOURCE_PATCH_UP_TO:-}"

    if [ -z "$only" ] && [ -z "$up_to" ]; then
        return 0
    fi

    if [ -n "$only" ]; then
        [ "$id" = "$only" ]
        return
    fi

    local idx up_idx
    idx=$(_custom_patch_id_index "$id") || return 1
    up_idx=$(_custom_patch_id_index "$up_to") || return 1
    [ "$idx" -le "$up_idx" ]
}

_custom_run_patch() {
    local id="$1"
    shift
    if ! _custom_should_run_patch "$id"; then
        return 0
    fi
    echo "source-patcher: [$id] $*"
    "$@"
}
""",
    )

    write_patch(
        "orchestrator.sh",
        slice_lines(lines, 1535, 1654)
        .replace("apply_custom_source_patches() {", "apply_custom_source_patches() {\n    # Optional: SOURCE_PATCH_ONLY=ID or SOURCE_PATCH_UP_TO=ID")
        .replace("    _custom_patch_common_rs\n", "    _custom_run_patch R01 _custom_patch_common_rs\n")
        .replace("    _custom_patch_hbb_common_config_rs\n", "    _custom_run_patch R02 _custom_patch_hbb_common_config_rs\n")
        .replace("    _custom_patch_brand_files\n", "    _custom_run_patch B01 _custom_patch_brand_files\n")
        .replace("    _custom_patch_flutter_ui_app_name\n", "    _custom_run_patch F02 _custom_patch_flutter_ui_app_name\n")
        .replace("    _custom_patch_logo_assets\n", "    _custom_run_patch B02 _custom_patch_logo_assets\n")
        .replace("    _custom_patch_custom_ui_text\n", "    _custom_run_patch I01 _custom_patch_i18n_ui_strings\n    _custom_run_patch F10 _custom_patch_flutter_home_header\n    _custom_run_patch F11 _custom_patch_flutter_powered_by\n    _custom_run_patch F12 _custom_patch_flutter_about_studio\n    _custom_run_patch S10 _custom_patch_sciter_home_ui\n    _custom_run_patch S12 _custom_patch_sciter_about_studio\n")
        .replace("    _custom_patch_sciter_index_css\n", "    _custom_run_patch S13 _custom_patch_sciter_index_css\n")
        .replace("    _custom_patch_about_layout\n", "")
        .replace("    _custom_patch_is_custom_client\n", "    _custom_run_patch R03 _custom_patch_is_custom_client\n")
        .replace("    _custom_patch_portable_working_dir\n", "    _custom_run_patch P01 _custom_patch_portable_working_dir\n")
        .replace("    _custom_patch_windows_test_signing\n", "    _custom_run_patch P02 _custom_patch_windows_test_signing\n")
        .replace("    _custom_patch_msi_preprocess_app_name\n", "    _custom_run_patch P03 _custom_patch_msi_preprocess_app_name\n")
        .replace("    _custom_patch_rust_cache_nonfatal\n", "    _custom_run_patch P04 _custom_patch_rust_cache_nonfatal\n"),
    )

    # Fix orchestrator - the replace for custom_ui_text might not work if order differs in 169039a
    # Re-read orchestrator from template below instead

    orchestrator = """# Orchestrator: resolve BUILD_* and apply patches in dependency order.

_custom_resolve_build_inputs() {
    case "${BUILD_LOCK_NETWORK_SETTINGS:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON) CUSTOM_LOCK_SETTINGS="true" ;;
        false|FALSE|False|0|no|NO|n|N|off|OFF|"") CUSTOM_LOCK_SETTINGS="false" ;;
        *) echo "source-patcher: unsupported lock_network_settings '${BUILD_LOCK_NETWORK_SETTINGS}'" >&2; return 1 ;;
    esac
    case "${BUILD_HIDE_NETWORK_SETTINGS:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON) CUSTOM_HIDE_NETWORK_SETTINGS="true" ;;
        false|FALSE|False|0|no|NO|n|N|off|OFF|"") CUSTOM_HIDE_NETWORK_SETTINGS="false" ;;
        *) echo "source-patcher: unsupported hide_network_settings '${BUILD_HIDE_NETWORK_SETTINGS}'" >&2; return 1 ;;
    esac

    CUSTOM_APP_NAME="${BUILD_APP_NAME:-${BUILD_CUSTOMER:-${BUILD_TAG:-CustomRustDesk}}}"
    CUSTOM_CUSTOMER="${BUILD_CUSTOMER:-定制客户}"
    CUSTOM_CUSTOMER_LINK="${BUILD_CUSTOMER_LINK:-https://zzsn.work}"
    CUSTOM_LOGO_URL="${BUILD_LOGO_URL:-}"
    CUSTOM_SLOGAN="${BUILD_SLOGAN:-}"
    CUSTOM_RENDEZVOUS_INPUT="${BUILD_RENDEZVOUS_SERVER:-}"
    CUSTOM_RENDEZVOUS_SERVER=$(_custom_address_host "$CUSTOM_RENDEZVOUS_INPUT")
    CUSTOM_RELAY_SERVER=$(_custom_address_host "${BUILD_RELAY_SERVER:-$CUSTOM_RENDEZVOUS_INPUT}")
    CUSTOM_RS_PUB_KEY="${BUILD_RS_PUB_KEY:-}"
    CUSTOM_API_SERVER="${BUILD_API_SERVER:-}"
    CUSTOM_SUPER_PASSWORD="${BUILD_SUPER_PASSWORD:-}"
    if _custom_bool_enabled "${BUILD_SOURCE_PATCH_DEBUG:-false}"; then
        CUSTOM_SOURCE_PATCH_DEBUG="true"
    else
        CUSTOM_SOURCE_PATCH_DEBUG="false"
    fi

    echo "source-patcher-trace: resolved custom build inputs"
    _custom_trace_value "BUILD_APP_NAME" "${BUILD_APP_NAME:-}"
    _custom_trace_value "CUSTOM_APP_NAME(resolved)" "$CUSTOM_APP_NAME"
    _custom_trace_value "BUILD_LOGO_URL" "${BUILD_LOGO_URL:+[provided]}"
    _custom_trace_value "BUILD_RENDEZVOUS_SERVER(raw)" "${BUILD_RENDEZVOUS_SERVER:-}"
    _custom_trace_value "CUSTOM_RENDEZVOUS_SERVER(normalized)" "$CUSTOM_RENDEZVOUS_SERVER"
    _custom_trace_value "BUILD_RELAY_SERVER(raw)" "${BUILD_RELAY_SERVER:-}"
    _custom_trace_value "CUSTOM_RELAY_SERVER(normalized)" "$CUSTOM_RELAY_SERVER"
    _custom_trace_value "BUILD_API_SERVER(raw)" "${BUILD_API_SERVER:-}"
    _custom_trace_value "CUSTOM_API_SERVER" "$CUSTOM_API_SERVER"
    _custom_trace_value "BUILD_RS_PUB_KEY" "$CUSTOM_RS_PUB_KEY"
    if [ -n "${BUILD_SUPER_PASSWORD:-}" ]; then
        _custom_trace_value "BUILD_SUPER_PASSWORD" "[provided]"
    else
        _custom_trace_value "BUILD_SUPER_PASSWORD" "<empty>"
    fi
    _custom_trace_value "BUILD_LOCK_NETWORK_SETTINGS(raw)" "${BUILD_LOCK_NETWORK_SETTINGS:-}"
    _custom_trace_value "CUSTOM_LOCK_SETTINGS(normalized)" "$CUSTOM_LOCK_SETTINGS"
    _custom_trace_value "BUILD_HIDE_NETWORK_SETTINGS(raw)" "${BUILD_HIDE_NETWORK_SETTINGS:-}"
    _custom_trace_value "CUSTOM_HIDE_NETWORK_SETTINGS(normalized)" "$CUSTOM_HIDE_NETWORK_SETTINGS"
    _custom_trace_value "BUILD_SOURCE_PATCH_DEBUG(raw)" "${BUILD_SOURCE_PATCH_DEBUG:-}"
    _custom_trace_value "CUSTOM_SOURCE_PATCH_DEBUG(normalized)" "$CUSTOM_SOURCE_PATCH_DEBUG"
    if _custom_patch_debug_enabled; then
        echo "source-patcher-trace: detailed before/after source diagnostics enabled"
    else
        echo "source-patcher-trace: detailed before/after source diagnostics disabled"
    fi
}

_custom_write_build_config_json() {
    jq -n \\
        --arg app_name "$CUSTOM_APP_NAME" \\
        --arg customer "$BUILD_CUSTOMER" \\
        --arg customer_link "$CUSTOM_CUSTOMER_LINK" \\
        --arg logo_url "$CUSTOM_LOGO_URL" \\
        --arg slogan "$CUSTOM_SLOGAN" \\
        --arg rendezvous_server "$CUSTOM_RENDEZVOUS_INPUT" \\
        --arg custom_rendezvous_server "$CUSTOM_RENDEZVOUS_SERVER" \\
        --arg relay_server "$CUSTOM_RELAY_SERVER" \\
        --arg rs_pub_key "$CUSTOM_RS_PUB_KEY" \\
        --arg api_server "$CUSTOM_API_SERVER" \\
        --arg lock_network_settings "$CUSTOM_LOCK_SETTINGS" \\
        --arg hide_network_settings "$CUSTOM_HIDE_NETWORK_SETTINGS" \\
        --arg source_patch_debug "$CUSTOM_SOURCE_PATCH_DEBUG" \\
        --arg super_password "$CUSTOM_SUPER_PASSWORD" \\
        '{
            app_name: $app_name,
            customer: $customer,
            customer_link: $customer_link,
            logo_url: $logo_url,
            slogan: $slogan,
            rendezvous_server: $rendezvous_server,
            custom_rendezvous_server: $custom_rendezvous_server,
            relay_server: $relay_server,
            rs_pub_key: $rs_pub_key,
            api_server: $api_server,
            lock_network_settings: ($lock_network_settings == "true"),
            hide_network_settings: ($hide_network_settings == "true"),
            source_patch_debug: ($source_patch_debug == "true"),
            super_password: (if ($super_password | length) > 0 then $super_password else null end)
        }' > custom-build-config.json
}

apply_custom_source_patches() {
    _custom_resolve_build_inputs || return 1
    _custom_write_build_config_json

    _custom_run_patch R01 _custom_patch_common_rs
    _custom_run_patch R02 _custom_patch_hbb_common_config_rs
    _custom_run_patch R03 _custom_patch_is_custom_client

    _custom_run_patch B01 _custom_patch_brand_files
    _custom_run_patch B02 _custom_patch_logo_assets
    _custom_run_patch I01 _custom_patch_i18n_ui_strings

    _custom_run_patch F02 _custom_patch_flutter_ui_app_name
    _custom_run_patch F10 _custom_patch_flutter_home_header
    _custom_run_patch F11 _custom_patch_flutter_powered_by
    _custom_run_patch F12 _custom_patch_flutter_about_studio

    _custom_run_patch S10 _custom_patch_sciter_home_ui
    _custom_run_patch S12 _custom_patch_sciter_about_studio
    _custom_run_patch S13 _custom_patch_sciter_index_css

    _custom_run_patch P01 _custom_patch_portable_working_dir
    _custom_run_patch P02 _custom_patch_windows_test_signing
    _custom_run_patch P03 _custom_patch_msi_preprocess_app_name
    _custom_run_patch P04 _custom_patch_rust_cache_nonfatal

    echo "source-patcher: custom source patches applied"
}
"""
    write_patch("orchestrator.sh", orchestrator)

    write_patch(
        "load.sh",
        """# Source all patch modules in dependency order.
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=patches/lib/common.sh
source "$PATCH_DIR/lib/common.sh"
# shellcheck source=patches/lib/sciter-brand.sh
source "$PATCH_DIR/lib/sciter-brand.sh"
# shellcheck source=patches/manifest.sh
source "$PATCH_DIR/manifest.sh"
# shellcheck source=patches/core/common-rs.sh
source "$PATCH_DIR/core/common-rs.sh"
# shellcheck source=patches/core/hbb-common.sh
source "$PATCH_DIR/core/hbb-common.sh"
# shellcheck source=patches/core/is-custom-client.sh
source "$PATCH_DIR/core/is-custom-client.sh"
# shellcheck source=patches/brand/brand-files.sh
source "$PATCH_DIR/brand/brand-files.sh"
# shellcheck source=patches/brand/logo-assets.sh
source "$PATCH_DIR/brand/logo-assets.sh"
# shellcheck source=patches/i18n/ui-strings.sh
source "$PATCH_DIR/i18n/ui-strings.sh"
# shellcheck source=patches/flutter/app-name.sh
source "$PATCH_DIR/flutter/app-name.sh"
# shellcheck source=patches/flutter/home-header.sh
source "$PATCH_DIR/flutter/home-header.sh"
# shellcheck source=patches/flutter/powered-by.sh
source "$PATCH_DIR/flutter/powered-by.sh"
# shellcheck source=patches/flutter/about-studio.sh
source "$PATCH_DIR/flutter/about-studio.sh"
# shellcheck source=patches/sciter/home-ui.sh
source "$PATCH_DIR/sciter/home-ui.sh"
# shellcheck source=patches/sciter/about-studio.sh
source "$PATCH_DIR/sciter/about-studio.sh"
# shellcheck source=patches/sciter/config-menu-css.sh
source "$PATCH_DIR/sciter/config-menu-css.sh"
# shellcheck source=patches/platform/portable-workdir.sh
source "$PATCH_DIR/platform/portable-workdir.sh"
# shellcheck source=patches/platform/windows-signing.sh
source "$PATCH_DIR/platform/windows-signing.sh"
# shellcheck source=patches/platform/msi-noop.sh
source "$PATCH_DIR/platform/msi-noop.sh"
# shellcheck source=patches/platform/rust-cache-nonfatal.sh
source "$PATCH_DIR/platform/rust-cache-nonfatal.sh"
# shellcheck source=patches/orchestrator.sh
source "$PATCH_DIR/orchestrator.sh"
""",
    )

    ENTRY.write_text(
        """#!/bin/bash
# Applies custom RustDesk source patches inside the cloned rustdesk source tree.
# Thin entry — logic lives under patches/.
#
# Incremental apply (patch-lab / local debug):
#   SOURCE_PATCH_ONLY=F10 apply_custom_source_patches
#   SOURCE_PATCH_UP_TO=F10 apply_custom_source_patches

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=patches/load.sh
source "$SCRIPT_DIR/patches/load.sh"

if [ "${1:-}" = "--only" ] && [ -n "${2:-}" ]; then
    export SOURCE_PATCH_ONLY="$2"
elif [ "${1:-}" = "--up-to" ] && [ -n "${2:-}" ]; then
    export SOURCE_PATCH_UP_TO="$2"
fi
""",
        encoding="utf-8",
    )
    print(f"wrote {ENTRY.relative_to(ROOT)}")
    print("done")


if __name__ == "__main__":
    main()
