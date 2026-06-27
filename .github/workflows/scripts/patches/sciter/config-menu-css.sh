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
    r"(?:menu\.context#config-options > div\.separator\s*\{[^}]*\}\s*)?"
    r"(?:@media \(height < 720px\) \{\s*menu\.context#config-options\s*\{[^}]*\}\s*\}\s*)?",
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
       grep -q 'flow: horizontal-flow' "$css_file" &&
       grep -q 'menu.context#config-options > li' "$css_file" &&
       grep -q 'width: 48%' "$css_file" &&
       ! grep -q 'overflow-y: scroll-indicator' "$css_file" &&
       ! grep -q 'max-height: 72vh' "$css_file"; then
        echo "source-patcher: sciter config menu two-column flow patched in $css_file"
    else
        echo "source-patcher: failed to patch sciter config menu flow in $css_file" >&2
        return 1
    fi

    if [ ! -f "src/ui/index.tis" ]; then
        return 0
    fi

    python3 - "src/ui/index.tis" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

tis_pattern = re.compile(
    r"(?P<indent>[ \t]*)var menu = this\.\$\(menu#config-options\);\n"
    r"(?:[ \t]*// CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT\n"
    r"[ \t]*var \(_, __, ___, viewH\) = view\.box\(#dimension, #border, #view\);\n"
    r"[ \t]*var maxMenuHDip = \(\(viewH / scaleFactor\) \* 72 / 100\)\.toInteger\(\);\n"
    r"[ \t]*if \(maxMenuHDip < 240\) maxMenuHDip = 240;\n"
    r"[ \t]*menu\.style\.set \{\n"
    r'[ \t]*"max-height": maxMenuHDip \+ "dip",\n'
    r'[ \t]*"overflow-y": "scroll-indicator",\n'
    r"[ \t]*\};\n)?"
    r"(?P=indent)this\.\$\(svg#menu\)\.popup\(menu\);",
)

def build_replacement(match: re.Match[str]) -> str:
    indent = match.group("indent")
    return f"{indent}var menu = this.$(menu#config-options);\n{indent}this.$(svg#menu).popup(menu);"

if tis_pattern.search(text):
    text = tis_pattern.sub(build_replacement, text, count=1)
elif "CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT" in text:
    raise SystemExit(
        "source-patcher: config menu max-height marker found but showSettingMenu anchor unexpected"
    )

path.write_text(text, encoding="utf-8")
PY
    if grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT" "src/ui/index.tis"; then
        echo "source-patcher: failed to remove sciter config menu max-height hook in src/ui/index.tis" >&2
        return 1
    fi
    if ! grep -q 'var menu = this\.\$(menu#config-options);' "src/ui/index.tis" ||
       ! grep -q 'this\.\$(svg#menu)\.popup(menu);' "src/ui/index.tis"; then
        echo "source-patcher: showSettingMenu anchor missing after config menu patch in src/ui/index.tis" >&2
        return 1
    fi
    echo "source-patcher: sciter config menu uses upstream showSettingMenu popup (no runtime style hook)"
}
