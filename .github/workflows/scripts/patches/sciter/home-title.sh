# S11 — Sciter 首页 app 名（依赖 S10）
_custom_patch_sciter_home_title() {
    local index_file="src/ui/index.tis"

    if [ ! -f "$index_file" ]; then
        return 0
    fi

    local title_file=""
    title_file=$(mktemp)
    _custom_sciter_home_title_markup > "$title_file"

    python3 - "$index_file" "$title_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
title = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = path.read_text(encoding="utf-8")

if "CUSTOM_RUSTDESK_SCITER_HOME_TITLE" in text:
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

if "custom-rd-home-title-row" not in text:
    raise SystemExit("source-patcher: S11 requires S10 home logo shell first")

title_plain = title.replace(" <!-- CUSTOM_RUSTDESK_SCITER_HOME_TITLE -->", "")
if title_plain in text:
    if "CUSTOM_RUSTDESK_SCITER_HOME_TITLE" not in text:
        text = text.replace(title_plain, title, 1)
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

logo_close = re.compile(
    r"(<img\.custom-rd-home-logo[^>]*/>\s*(?:<!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->)?)(\s*</div>)",
    re.DOTALL,
)
if not logo_close.search(text):
    raise SystemExit("source-patcher: S11 title anchor (logo in title-row) not found")

text = logo_close.sub(lambda m: m.group(1) + title + m.group(2), text, count=1)
if "CUSTOM_RUSTDESK_SCITER_HOME_TITLE" not in text:
    raise SystemExit("source-patcher: failed to inject S11 home title")

path.write_text(text, encoding="utf-8")
PY
    rm -f "$title_file"

    if grep -q "CUSTOM_RUSTDESK_SCITER_HOME_TITLE" "$index_file" &&
       grep -q 'handler.get_builtin_option("app-name")' "$index_file"; then
        echo "source-patcher: S11 home title injected in $index_file"
    else
        echo "source-patcher: failed to inject S11 home title in $index_file" >&2
        return 1
    fi
}
