# F11 — Flutter 首页 app 名（标题行，依赖 F10）
_custom_patch_flutter_home_title() {
    local home_file="flutter/lib/desktop/pages/desktop_home_page.dart"

    if [ ! -f "$home_file" ]; then
        return 0
    fi

    python3 - "$home_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
title_marker = "CUSTOM_RUSTDESK_HOME_TITLE"
icon_marker = "CUSTOM_RUSTDESK_HOME_ICON"
row_marker = "CUSTOM_RUSTDESK_HOME_TITLE_ROW"

title_widget = """Flexible(
                    child: Text(
                      bind.mainGetBuildinOption(key: "app-name"),
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ), // CUSTOM_RUSTDESK_HOME_TITLE"""

def _has_home_title_marker(text: str) -> bool:
    return bool(re.search(r"// CUSTOM_RUSTDESK_HOME_TITLE(?!_ROW)", text))

if _has_home_title_marker(text):
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

if icon_marker not in text or row_marker not in text:
    raise SystemExit("source-patcher: F11 requires F10 home logo (HOME_ICON + TITLE_ROW) first")

icon_pos = text.find(f"// {icon_marker}")
row_pos = text.find(f"// {row_marker}")
if icon_pos == -1 or row_pos == -1 or row_pos <= icon_pos:
    raise SystemExit("source-patcher: F11 home logo/title-row markers out of order")

header_chunk = text[icon_pos:row_pos]
if "bind.mainGetBuildinOption(key: \"app-name\")" in header_chunk:
    if not _has_home_title_marker(text):
        raise SystemExit("source-patcher: F11 app-name row present but HOME_TITLE marker missing")
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

pat = re.compile(rf"(// {icon_marker}\s*\n\s*)(\],)", re.MULTILINE)
if not pat.search(text):
    raise SystemExit("source-patcher: F11 title-row anchor not found in desktop_home_page.dart")

def _insert_title(match: re.Match) -> str:
    return match.group(1) + "                  " + title_widget + "\n                " + match.group(2)

text = pat.sub(_insert_title, text, count=1)
if not _has_home_title_marker(text):
    raise SystemExit("source-patcher: failed to inject F11 home title in desktop_home_page.dart")

path.write_text(text, encoding="utf-8")
PY

    if grep -Fq '), // CUSTOM_RUSTDESK_HOME_TITLE' "$home_file" &&
       grep -q 'bind.mainGetBuildinOption(key: "app-name")' "$home_file"; then
        echo "source-patcher: F11 home title injected in $home_file"
    else
        echo "source-patcher: failed to inject F11 home title in $home_file" >&2
        return 1
    fi
}
