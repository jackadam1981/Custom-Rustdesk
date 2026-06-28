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
  max-height: 80vh;
  max-width: 90vw;
  overflow-y: scroll-indicator;
  vertical-scrollbar: my-scrollbar;
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
while pattern.search(text):
    text = pattern.sub("", text, count=1)
text = re.sub(r"\n{3,}", "\n\n", text).rstrip() + "\n\n" + block
path.write_text(text, encoding="utf-8")
PY
    if grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_FLOW" "$css_file" &&
       grep -q 'max-height: 80vh' "$css_file" &&
       grep -q 'overflow-y: scroll-indicator' "$css_file" &&
       ! grep -q 'menu.context#config-options > li' "$css_file"; then
        echo "source-patcher: sciter config menu single-column scroll patched in $css_file"
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

upstream_popup = (
    "var menu = this.$(menu#config-options);\n"
    "                this.$(svg#menu).popup(menu);"
)

custom_popup = re.compile(
    r"(?P<indent>[ \t]*)var menu = this\.\$\(menu#config-options\);\n"
    r"(?:[ \t]*// CUSTOM_RUSTDESK_CONFIG_MENU_(?:MAX_HEIGHT|WIDTH)\n"
    r"(?:[ \t]*(?:var \(_, __, ___, viewH\) = view\.box\(#dimension, #border, #view\);\n"
    r"[ \t]*var maxMenuHDip = \(\(viewH / scaleFactor\) \* 72 / 100\)\.toInteger\(\);\n"
    r"[ \t]*if \(maxMenuHDip < 240\) maxMenuHDip = 240;\n"
    r")?)?"
    r"[ \t]*menu\.style\.set \{\n"
    r'(?:[ \t]*"max-height": maxMenuHDip \+ "dip",\n'
    r'[ \t]*"overflow-y": "scroll-indicator",\n'
    r'|[ \t]*width: "520dip",\n)'
    r"[ \t]*\};\n)?"
    r"(?P=indent)this\.\$\(svg#menu\)\.popup\(menu\);",
)

if custom_popup.search(text):
    text = custom_popup.sub(
        lambda m: f"{m.group('indent')}var menu = this.$(menu#config-options);\n"
        f"{m.group('indent')}this.$(svg#menu).popup(menu);",
        text,
        count=1,
    )
elif "CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT" in text or "CUSTOM_RUSTDESK_CONFIG_MENU_WIDTH" in text:
    raise SystemExit(
        "source-patcher: config menu marker found but showSettingMenu anchor unexpected"
    )
elif upstream_popup not in text.replace("\r\n", "\n"):
    raise SystemExit("source-patcher: showSettingMenu anchor not found in src/ui/index.tis")

if "CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT" in text or "CUSTOM_RUSTDESK_CONFIG_MENU_WIDTH" in text:
    raise SystemExit("source-patcher: failed to restore upstream config menu popup in index.tis")

path.write_text(text, encoding="utf-8")
PY
    if ! grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_MAX_HEIGHT" "src/ui/index.tis" &&
       ! grep -q "CUSTOM_RUSTDESK_CONFIG_MENU_WIDTH" "src/ui/index.tis" &&
       ! grep -q '"max-height"' "src/ui/index.tis" &&
       ! grep -q '"overflow-y"' "src/ui/index.tis" &&
       grep -q 'menu#config-options' "src/ui/index.tis" &&
       grep -q 'popup(menu)' "src/ui/index.tis"; then
        echo "source-patcher: sciter config menu uses upstream popup (scroll via CSS only)"
    else
        echo "source-patcher: failed to restore sciter config menu popup in src/ui/index.tis" >&2
        return 1
    fi
}
