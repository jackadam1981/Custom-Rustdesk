# S12 — Sciter 首页 slogan（依赖 S10/S11）
_custom_patch_sciter_home_slogan() {
    local index_file="src/ui/index.tis"

    if [ ! -f "$index_file" ]; then
        return 0
    fi

    local slogan_file=""
    slogan_file=$(mktemp)
    _custom_sciter_home_slogan_markup > "$slogan_file"

    python3 - "$index_file" "$slogan_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
slogan = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = path.read_text(encoding="utf-8")

if "CUSTOM_RUSTDESK_SCITER_HOME_SLOGAN" in text or "custom-rd-home-slogan" in text:
    if "CUSTOM_RUSTDESK_SCITER_HOME_SLOGAN" not in text and "custom-rd-home-slogan" in text:
        text = text.replace(
            slogan.replace(" <!-- CUSTOM_RUSTDESK_SCITER_HOME_SLOGAN -->", ""),
            slogan,
            1,
        )
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

if "custom-rd-home-header" not in text:
    raise SystemExit("source-patcher: S12 requires S10 home header first")

slogan_plain = slogan.replace(" <!-- CUSTOM_RUSTDESK_SCITER_HOME_SLOGAN -->", "")
header_end = re.compile(
    r"(<div #custom-brand\.custom-rd-home-header[^>]*>[\s\S]*?"
    r"<div \.custom-rd-home-title-row[\s\S]*?</div>)(\s*</div>\s*: \"\"\})",
    re.DOTALL,
)
if not header_end.search(text):
    raise SystemExit("source-patcher: S12 slogan anchor not found in src/ui/index.tis")

text = header_end.sub(lambda m: m.group(1) + slogan + m.group(2), text, count=1)
if "custom-rd-home-slogan" not in text:
    raise SystemExit("source-patcher: failed to inject S12 home slogan")

path.write_text(text, encoding="utf-8")
PY
    rm -f "$slogan_file"

    if grep -q "custom-rd-home-slogan" "$index_file"; then
        echo "source-patcher: S12 home slogan injected in $index_file"
    else
        echo "source-patcher: failed to inject S12 home slogan in $index_file" >&2
        return 1
    fi
}
