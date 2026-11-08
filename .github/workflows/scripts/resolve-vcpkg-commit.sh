#!/bin/bash
# Resolve VCPKG_COMMIT_ID from the vcpkg baseline declared by the cloned upstream vcpkg.json.
#
# Upstream keeps the vcpkg checkout commit in sync with the baseline recorded in vcpkg.json:
#   - `vcpkg-configuration.default-registry.baseline` (current upstream layout, kind=builtin), or
#   - top-level `builtin-baseline`.
# When this repository vendors the upstream workflows, a hardcoded VCPKG_COMMIT_ID goes stale
# as soon as the cloned upstream source moves to a newer baseline, which makes vcpkg fail with:
#   error: no version database entry for <port> at <version>.
#
# This script derives the commit from the source tree that is actually being built and
# exports it to later steps via $GITHUB_ENV. It never falls back to a hardcoded value:
# a missing/unreadable baseline is a hard error.

set -euo pipefail

if [ ! -f vcpkg.json ]; then
    echo "::error::vcpkg.json not found in $(pwd); cannot resolve VCPKG_COMMIT_ID from its vcpkg baseline"
    exit 1
fi

if ! command -v node >/dev/null 2>&1; then
    echo "::error::node is required to parse vcpkg.json but was not found in PATH"
    exit 1
fi

baseline="$(node -e "
const fs = require('fs');
const v = JSON.parse(fs.readFileSync('vcpkg.json', 'utf8'));
const cfg = v['vcpkg-configuration'];
const def = (cfg && cfg['default-registry']) || {};
let baseline = '';
if (v['builtin-baseline']) {
  baseline = String(v['builtin-baseline']);
} else if (def['baseline']) {
  if (def['kind'] && def['kind'] !== 'builtin') {
    console.error('::error::vcpkg.json default-registry kind is ' + def['kind'] + ', expected builtin');
    process.exit(2);
  }
  baseline = String(def['baseline']);
}
process.stdout.write(baseline);
")"

if [ -z "$baseline" ]; then
    echo "::error::vcpkg.json declares no vcpkg baseline (neither builtin-baseline nor vcpkg-configuration.default-registry.baseline); refusing to fall back to a hardcoded vcpkg commit"
    exit 1
fi

case "$baseline" in
    *[!0-9a-f]*)
        echo "::error::vcpkg baseline is not a lowercase hex commit sha: $baseline"
        exit 1
        ;;
esac

if [ "${#baseline}" -ne 40 ]; then
    echo "::error::vcpkg baseline is not a 40-character commit sha: $baseline"
    exit 1
fi

echo "VCPKG_COMMIT_ID=$baseline" >> "$GITHUB_ENV"
echo "✅ VCPKG_COMMIT_ID resolved from vcpkg.json baseline: $baseline"
