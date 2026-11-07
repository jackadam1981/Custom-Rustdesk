# F12 — Flutter 首页 slogan（依赖 F10/F11）
_custom_patch_flutter_home_slogan() {
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
slogan_marker = "CUSTOM_RUSTDESK_HOME_SLOGAN"
row_marker = "CUSTOM_RUSTDESK_HOME_TITLE_ROW"

slogan_widget = """if (bind.mainGetBuildinOption(key: "custom-slogan").isNotEmpty)
                Text(
                  bind.mainGetBuildinOption(key: "custom-slogan"),
                  style: Theme.of(context).textTheme.bodySmall,
                ).marginOnly(top: 2), // CUSTOM_RUSTDESK_HOME_SLOGAN"""

if slogan_marker in text:
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

if row_marker not in text:
    raise SystemExit("source-patcher: F12 requires F10 home logo scaffold first")

pat = re.compile(rf"(// {row_marker}\s*\n\s*)(\],)", re.MULTILINE)
if not pat.search(text):
    raise SystemExit("source-patcher: F12 slogan anchor not found in desktop_home_page.dart")

def _insert_slogan(match: re.Match) -> str:
    return match.group(1) + "              " + slogan_widget + "\n            " + match.group(2)

text = pat.sub(_insert_slogan, text, count=1)
if slogan_marker not in text:
    raise SystemExit("source-patcher: failed to inject F12 home slogan in desktop_home_page.dart")

path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_HOME_SLOGAN" "$home_file"; then
        echo "source-patcher: F12 home slogan injected in $home_file"
    else
        echo "source-patcher: failed to inject F12 home slogan in $home_file" >&2
        return 1
    fi
}
