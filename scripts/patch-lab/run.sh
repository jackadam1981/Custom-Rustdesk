#!/usr/bin/env bash
# Fresh upstream clone -> optional source-patcher -> verify tree (aligns with CI rollout).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH_LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PATCH_LAB_ROOT="${PATCH_LAB_ROOT:-$HOME/patch-lab/custom-rustdesk}"
UPSTREAM_DIR="$PATCH_LAB_ROOT/upstream/rustdesk-source"
OUT_DIR="$PATCH_LAB_ROOT/out"
RUSTDESK_REPO="${RUSTDESK_REPO:-rustdesk/rustdesk}"
RUSTDESK_BRANCH="${RUSTDESK_BRANCH:-master}"

profile="baixin"
env_file=""
keep_on_fail=false
skip_clean=false
patch_only=""
patch_up_to=""
verify_up_to=""
apply_all=false

usage() {
    cat <<'EOF'
Usage: scripts/patch-lab/run.sh [OPTIONS]

Options:
  --profile NAME       Load scripts/patch-lab/profiles/NAME.env (default: baixin)
  --env-file PATH      Load build params from custom env file
  --patch-only ID      Apply single patch module (e.g. F10)
  --patch-up-to ID     Apply patches through ID inclusive (e.g. F10)
  --apply-all          Apply all 16 patches (local debug only)
  --verify-up-to ID    Run only verify checks for patches through ID
  --keep-on-fail       Do not delete upstream tree when patch/verify fails
  --skip-clean         Skip clean.sh (not recommended)
  -h, --help           Show help

Patch IDs (order): R01 R03 B01 B02 I01 F02 F10 F11 F12 S10 S12 S13 P01 P02 P03 P04

Environment:
  PATCH_LAB_ROOT       Workspace root (default: ~/patch-lab/custom-rustdesk)
  RUSTDESK_REPO        Upstream repo (default: rustdesk/rustdesk)
  RUSTDESK_BRANCH      Upstream branch (default: master)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --profile)
            profile="$2"
            shift 2
            ;;
        --env-file)
            env_file="$2"
            shift 2
            ;;
        --keep-on-fail)
            keep_on_fail=true
            shift
            ;;
        --skip-clean)
            skip_clean=true
            shift
            ;;
        --patch-only)
            patch_only="$2"
            shift 2
            ;;
        --patch-up-to)
            patch_up_to="$2"
            shift 2
            ;;
        --verify-up-to)
            verify_up_to="$2"
            shift 2
            ;;
        --apply-all)
            apply_all=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "patch-lab/run: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -n "$env_file" ]; then
    profile_file="$env_file"
elif [ -f "$PATCH_LAB_DIR/profiles/${profile}.env" ]; then
    profile_file="$PATCH_LAB_DIR/profiles/${profile}.env"
else
    echo "patch-lab/run: profile not found: $profile" >&2
    exit 1
fi

echo "patch-lab/run: CUSTOM_RUSTDESK repo=$ROOT"
echo "patch-lab/run: PATCH_LAB_ROOT=$PATCH_LAB_ROOT"
echo "patch-lab/run: profile=$profile_file"
if [ -n "$patch_only" ]; then
    echo "patch-lab/run: SOURCE_PATCH_ONLY=$patch_only"
elif [ -n "$patch_up_to" ]; then
    echo "patch-lab/run: SOURCE_PATCH_UP_TO=$patch_up_to"
elif [ "$apply_all" = true ]; then
    echo "patch-lab/run: CUSTOM_PATCH_APPLY_ALL=true"
else
    echo "patch-lab/run: vanilla upstream (no patches; use --patch-up-to or --apply-all)"
fi
if [ -n "$verify_up_to" ]; then
    echo "patch-lab/run: PATCH_VERIFY_UP_TO=$verify_up_to"
fi

if [ "$skip_clean" != true ]; then
    bash "$PATCH_LAB_DIR/clean.sh"
fi

mkdir -p "$PATCH_LAB_ROOT/upstream" "$OUT_DIR"

clone_url="https://github.com/${RUSTDESK_REPO}.git"
echo "patch-lab/run: cloning $clone_url @ $RUSTDESK_BRANCH ..."
git clone --depth 1 --branch "$RUSTDESK_BRANCH" --recurse-submodules --shallow-submodules \
    "$clone_url" "$UPSTREAM_DIR"

# shellcheck disable=SC1090
source "$profile_file"

export BUILD_CUSTOMER BUILD_APP_NAME BUILD_CUSTOMER_LINK BUILD_BANNER_URL BUILD_ICON_URL BUILD_LOGO_URL BUILD_SLOGAN
export BUILD_RENDEZVOUS_SERVER BUILD_RELAY_SERVER BUILD_RS_PUB_KEY BUILD_API_SERVER
export BUILD_SUPER_PASSWORD BUILD_HIDE_NETWORK_SETTINGS BUILD_LOCK_NETWORK_SETTINGS
export BUILD_SOURCE_PATCH_DEBUG BUILD_TAG="${BUILD_TAG:-patch-lab}"

cd "$UPSTREAM_DIR"
# shellcheck disable=SC1091
source "$ROOT/.github/workflows/scripts/source-patcher.sh"

export SOURCE_PATCH_ONLY="${patch_only:-}"
export SOURCE_PATCH_UP_TO="${patch_up_to:-}"
if [ "$apply_all" = true ]; then
    export CUSTOM_PATCH_APPLY_ALL=true
fi

if [ -z "$patch_only" ] && [ -z "$patch_up_to" ] && [ "$apply_all" != true ]; then
    echo "patch-lab/run: skipping apply_custom_source_patches (vanilla)"
else
if ! apply_custom_source_patches; then
    echo "patch-lab/run: apply_custom_source_patches FAILED" >&2
    if [ "$keep_on_fail" = true ]; then
        echo "patch-lab/run: upstream tree kept at $UPSTREAM_DIR"
    else
        rm -rf "$UPSTREAM_DIR"
    fi
    exit 1
fi
fi

report="$OUT_DIR/verify-report.txt"
mkdir -p "$OUT_DIR"

if [ -z "$patch_only" ] && [ -z "$patch_up_to" ] && [ "$apply_all" != true ]; then
    echo "patch-lab/run: Q0 vanilla verify..."
    {
        echo "patch-lab Q0 vanilla verify"
        echo "time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "---"
    } >"$report"
    q0_fail=0
    if grep -rq 'CUSTOM_RUSTDESK_PATCH_START' src/ libs/ flutter/ 2>/dev/null; then
        echo "FAIL: unexpected patch markers in upstream tree" | tee -a "$report"
        q0_fail=1
    else
        echo "PASS: no CUSTOM_RUSTDESK patch markers" | tee -a "$report"
    fi
    if [ -f src/common.rs ] && grep -q 'pub fn load_custom_client' src/common.rs; then
        echo "PASS: vanilla common.rs present" | tee -a "$report"
    else
        echo "FAIL: vanilla common.rs missing" | tee -a "$report"
        q0_fail=1
    fi
    if [ "$q0_fail" -ne 0 ]; then
        echo "patch-lab/run: Q0 verify FAILED (see $report)" >&2
        exit 1
    fi
    echo "patch-lab/run: Q0 vanilla verify PASSED"
else
    if [ -z "$verify_up_to" ]; then
        if [ "$apply_all" = true ]; then
            verify_up_to="P04"
        elif [ -n "$patch_up_to" ]; then
            verify_up_to="$patch_up_to"
        elif [ -n "$patch_only" ]; then
            verify_up_to="$patch_only"
        fi
    fi

    export PATCH_VERIFY_UP_TO="${verify_up_to:-}"
    if ! bash "$PATCH_LAB_DIR/verify.sh" "$UPSTREAM_DIR" "$report" "$profile_file"; then
        echo "patch-lab/run: verify FAILED (see $report)" >&2
        cp -f custom-build-config.json "$OUT_DIR/custom-build-config.json" 2>/dev/null || true
        if [ "$keep_on_fail" = true ]; then
            echo "patch-lab/run: upstream tree kept at $UPSTREAM_DIR"
        else
            rm -rf "$UPSTREAM_DIR"
        fi
        exit 1
    fi
fi

if [ -f custom-build-config.json ]; then
cp -f custom-build-config.json "$OUT_DIR/custom-build-config.json"
fi
for f in \
    src/common.rs \
    flutter/lib/desktop/pages/desktop_home_page.dart \
    flutter/lib/desktop/pages/connection_page.dart \
    flutter/lib/desktop/pages/desktop_setting_page.dart \
    src/ui/index.tis; do
    if [ -f "$f" ]; then
        mkdir -p "$OUT_DIR/$(dirname "$f")"
        cp -f "$f" "$OUT_DIR/$f"
    fi
done

echo "patch-lab/run: PASSED"
echo "patch-lab/run: report=$report"
echo "patch-lab/run: artifacts=$OUT_DIR"

# Success: remove upstream to save disk; patched snippets kept in out/
rm -rf "$UPSTREAM_DIR"
