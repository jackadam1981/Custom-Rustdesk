#!/usr/bin/env bash
# Re-apply S10 on an existing patched tree (upgrade path smoke test).
set -euo pipefail
export PATH="/c/Users/jacka/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe:$PATH"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="${1:-$ROOT/downloads/LogoOnly-28211423477/patched-source}"

cd "$FIX"
export CUSTOM_RUSTDESK_REPO="$ROOT"
export SOURCE_PATCH_ONLY=S10
export SOURCE_PATCH_UP_TO=
# shellcheck disable=SC1091
source "$ROOT/scripts/patch-lab/profiles/logo-only.env"
# shellcheck disable=SC1091
source "$ROOT/.github/workflows/scripts/source-patcher.sh"
apply_custom_source_patches

python3 - <<'PY'
from pathlib import Path

t = Path("src/ui/index.tis").read_text(encoding="utf-8")
h = t.find("custom-rd-home-header")
c = t.find("<div .card-connect>")
p = t.find("#powered-by")
assert p != -1 and c != -1 and p < c, "powered must be above card-connect"
assert "#powered-by" not in t[h : h + 4000], "powered must not be in left brand"
assert "max-width:48px" in t, "logo must be 48px"
assert "custom-rd-home-powered" in t, "right pane powered marker missing"
print("OK sciter S10 upgrade path")
PY
