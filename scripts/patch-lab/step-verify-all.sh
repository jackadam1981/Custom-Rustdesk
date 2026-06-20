#!/usr/bin/env bash
# Apply patches incrementally (up to each ID) and run matching verify gate.
# Requires network for upstream clone (2.18 patch-lab host).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH_LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT="${PATCH_LAB_ROOT:-$HOME/patch-lab/custom-rustdesk}/step-verify-all-report.txt"

profile="baixin"
keep_on_fail=true
stop_on_fail=false

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
        --stop-on-fail)
            stop_on_fail=true
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/patch-lab/step-verify-all.sh [OPTIONS]

Runs patch-lab once per patch ID (SOURCE_PATCH_UP_TO=ID) with matching
PATCH_VERIFY_UP_TO=ID. Full sequence matches MR gate order.

Options:
  --profile NAME     Profile (default: baixin)
  --keep-on-fail     Keep upstream tree when a gate fails (default)
  --stop-on-fail     Exit immediately on first failure
  -h, --help         Show help

Report: $PATCH_LAB_ROOT/step-verify-all-report.txt
EOF
            exit 0
            ;;
        *)
            echo "step-verify-all: unknown option: $1" >&2
            exit 1
            ;;
    esac
done

ids=(R01 R03 B01 B02 I01 F02 F10 F11 F12 S10 S12 S13 P01 P02 P03 P04)

mkdir -p "$(dirname "$REPORT")"
{
    echo "step-verify-all report"
    echo "profile: $profile"
    echo "time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "---"
} >"$REPORT"

echo "step-verify-all: profile=$profile"
echo "step-verify-all: report=$REPORT"

pass=0
fail=0
declare -a failed_ids=()

for id in "${ids[@]}"; do
    echo ""
    echo "========== patch-lab gate: up-to $id =========="
    if bash "$PATCH_LAB_DIR/run.sh" \
        --profile "$profile" \
        --patch-up-to "$id" \
        --verify-up-to "$id" \
        $([ "$keep_on_fail" = true ] && echo --keep-on-fail); then
        pass=$((pass + 1))
        echo "PASS: $id" | tee -a "$REPORT"
    else
        fail=$((fail + 1))
        failed_ids+=("$id")
        echo "FAIL: $id" | tee -a "$REPORT"
        if [ "$stop_on_fail" = true ]; then
            break
        fi
    fi
done

{
    echo "---"
    echo "TOTAL: ${#ids[@]}  PASS: $pass  FAIL: $fail"
    if [ "${#failed_ids[@]}" -gt 0 ]; then
        echo "FAILED_IDS: ${failed_ids[*]}"
    fi
} | tee -a "$REPORT"

echo ""
if [ "$fail" -eq 0 ]; then
    echo "step-verify-all: all ${#ids[@]} gates PASSED"
    exit 0
fi

echo "step-verify-all: $fail gate(s) FAILED (${failed_ids[*]})" >&2
exit 1
