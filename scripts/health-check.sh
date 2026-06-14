#!/bin/bash
# Quick repo health check for dev machines. Does not call gh or run fixtures.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0

echo "==> Shell syntax (bash -n)"
for f in .github/workflows/scripts/*.sh; do
    if ! bash -n "$f"; then
        echo "FAIL: $f"
        fail=1
    else
        echo "OK: $f"
    fi
done

echo "==> Workflow structure"
WORKFLOW=".github/workflows/CustomBuildRustdesk.yml"
for job in trigger review join-queue wait-build-lock build upstream-build finish; do
    if grep -q "^  ${job}:" "$WORKFLOW"; then
        echo "OK: job $job"
    else
        echo "FAIL: missing job $job in $WORKFLOW"
        fail=1
    fi
done

if grep -q 'apply_custom_source_patches' .github/workflows/scripts/source-patcher.sh; then
    echo "OK: source-patcher entrypoint"
else
    echo "FAIL: apply_custom_source_patches not found"
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "health-check: FAILED"
    exit 1
fi

echo "health-check: PASSED"
