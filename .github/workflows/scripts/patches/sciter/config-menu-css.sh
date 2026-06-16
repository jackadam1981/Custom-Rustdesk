_custom_patch_sciter_index_css() {
    local css_file="src/ui/index.css"

    if [ ! -f "$css_file" ]; then
        return 0
    fi

    python3 - "$css_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
block = """/* CUSTOM_RUSTDESK_CONFIG_MENU_FLOW */
menu.context#config-options {
  flow: horizontal-flow;
  width: 520px;
  max-width: 90vw;
}
menu.context#config-options > li {
  width: 48%;
  min-width: 200px;
}
menu.context#config-options > div.separator {
  width: 100%;
}
"""
pattern = re.compile(
    r"/\* CUSTOM_RUSTDESK_CONFIG_MENU_FLOW \*/\s*"
    r"menu\.context#config-options\s*\{[^}]*\}\s*"
    r"(?:menu\.context#config-options > li\s*\{[^}]*\}\s*)?"
    r"(?:menu\.context#config-options > div\.separator\s*\{[^}]*\}\s*)?",
    re.DOTALL,
)
if pattern.search(text):
    text = pattern.sub(block + "\n", text, count=1)
elif "CUSTOM_RUSTDESK_CONFIG_MENU_FLOW" in text:
    raise SystemExit("source-patcher: config menu css marker found but block shape unexpected")
else:
    text = text.rstrip() + "\n\n" + block
path.write_text(text, encoding="utf-8")
PY
    if grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_FLOW" "$css_file" &&
       grep -q 'menu.context#config-options > li' "$css_file"; then
        echo "source-patcher: sciter config menu two-column flow patched in $css_file"
    else
        echo "source-patcher: failed to patch sciter config menu flow in $css_file" >&2
        return 1
    fi
}
