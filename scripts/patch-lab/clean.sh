#!/usr/bin/env bash
# Reset patch-lab workspace (upstream clone + output). Does not touch ~/custom-rustdesk repo by default.
set -euo pipefail

PATCH_LAB_ROOT="${PATCH_LAB_ROOT:-$HOME/patch-lab/custom-rustdesk}"
UPSTREAM_DIR="$PATCH_LAB_ROOT/upstream/rustdesk-source"
OUT_DIR="$PATCH_LAB_ROOT/out"
ARCHIVE_DIR="$PATCH_LAB_ROOT/archive"

purge_all=false
purge_repo=false

usage() {
    cat <<'EOF'
Usage: scripts/patch-lab/clean.sh [OPTIONS]

Options:
  --all          Remove entire PATCH_LAB_ROOT (upstream, out, archive)
  --purge-repo   DANGEROUS: also remove $CUSTOM_RUSTDESK_REPO if set under PATCH_LAB_ROOT parent
  -h, --help     Show this help

Environment:
  PATCH_LAB_ROOT   Default: ~/patch-lab/custom-rustdesk
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            purge_all=true
            shift
            ;;
        --purge-repo)
            purge_repo=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "patch-lab/clean: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

remove_path() {
    local path="$1"
    if [ -e "$path" ]; then
        echo "patch-lab/clean: removing $path"
        rm -rf "$path"
    fi
}

if [ "$purge_all" = true ]; then
    remove_path "$PATCH_LAB_ROOT"
else
    remove_path "$UPSTREAM_DIR"
    remove_path "$OUT_DIR"
fi

if [ "$purge_repo" = true ] && [ -n "${CUSTOM_RUSTDESK_REPO:-}" ]; then
    echo "patch-lab/clean: --purge-repo requested for CUSTOM_RUSTDESK_REPO=$CUSTOM_RUSTDESK_REPO" >&2
    remove_path "$CUSTOM_RUSTDESK_REPO"
fi

mkdir -p "$PATCH_LAB_ROOT/out"

echo "patch-lab/clean: checking dependencies..."
missing=0
for cmd in git bash jq python3 perl curl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  OK: $cmd"
    else
        echo "  MISSING: $cmd" >&2
        missing=1
    fi
done

if ! python3 -c "import PIL" >/dev/null 2>&1; then
    echo "  MISSING: python3 Pillow (pip3 install Pillow)" >&2
    missing=1
else
    echo "  OK: python3 Pillow"
fi

if [ "$missing" -ne 0 ]; then
    echo "patch-lab/clean: dependency check FAILED" >&2
    exit 1
fi

echo "patch-lab/clean: PASSED (PATCH_LAB_ROOT=$PATCH_LAB_ROOT)"
