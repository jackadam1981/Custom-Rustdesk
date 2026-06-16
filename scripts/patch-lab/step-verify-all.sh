#!/usr/bin/env bash
# Apply patches incrementally (up to each ID) and run matching verify gate.
# Requires network for upstream clone (2.18 patch-lab host).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH_LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

profile="baixin"
keep_on_fail=true

while [ $# -gt 0 ]; do
    case "$1" in
        --profile)
            profile="$2"
            shift 2
            ;;
        --keep-on-fail)
            keep_on_fail=true
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/patch-lab/step-verify-all.sh [--profile baixin]

Runs patch-lab once per patch ID (SOURCE_PATCH_UP_TO=ID) with matching
PATCH_VERIFY_UP_TO=ID. Full sequence matches MR gate order.
EOF
            exit 0
            ;;
        *)
            echo "step-verify-all: unknown option: $1" >&2
            exit 1
            ;;
    esac
done

ids=(R01 R02 R03 B01 B02 I01 F02 F10 F11 F12 S10 S12 S13 P01 P02 P03 P04)

echo "step-verify-all: profile=$profile"
for id in "${ids[@]}"; do
    echo ""
    echo "========== patch-lab gate: up-to $id =========="
    if ! bash "$PATCH_LAB_DIR/run.sh" \
        --profile "$profile" \
        --patch-up-to "$id" \
        --verify-up-to "$id" \
        $([ "$keep_on_fail" = true ] && echo --keep-on-fail); then
        echo "step-verify-all: FAILED at $id" >&2
        exit 1
    fi
done

echo ""
echo "step-verify-all: all ${#ids[@]} gates PASSED"
