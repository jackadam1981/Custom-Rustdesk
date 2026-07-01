# F10 — Flutter 首页 logo（48px base64）
_custom_patch_flutter_home_logo() {
    local home_file="flutter/lib/desktop/pages/desktop_home_page.dart"
    local logo_file="flutter/assets/logo.png"

    if [ ! -f "$logo_file" ]; then
        echo "source-patcher: $logo_file missing — apply B02 logo_url before F10" >&2
        return 1
    fi

    if [ ! -f "$home_file" ]; then
        return 0
    fi

    python3 - "$home_file" "$logo_file" <<'PY'
import base64
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
logo_file = Path(sys.argv[2])
text = path.read_text(encoding="utf-8")
header_marker = "CUSTOM_RUSTDESK_HOME_HEADER"
row_marker = "CUSTOM_RUSTDESK_HOME_TITLE_ROW"
icon_marker = "CUSTOM_RUSTDESK_HOME_ICON"

if not logo_file.is_file():
    raise SystemExit(f"source-patcher: logo asset missing for F10: {logo_file}")

logo_b64 = base64.b64encode(logo_file.read_bytes()).decode("ascii")
logo_widget = f"""Image.memory(
                    base64Decode('{logo_b64}'),
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, error, stackTrace) => loadIcon(48),
                  ), // {icon_marker}"""

if "import 'dart:convert';" not in text:
    if "import 'dart:async';" in text:
        text = text.replace(
            "import 'dart:async';",
            "import 'dart:async';\nimport 'dart:convert';",
            1,
        )
    else:
        raise SystemExit("source-patcher: cannot inject dart:convert import in desktop_home_page.dart")

text = re.sub(
    r"if \(bind\.isCustomClient\(\)\)\)\s*\n",
    "if (bind.isCustomClient())\n",
    text,
)

logo_scaffold = f"""if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  {logo_widget}
                ],
              ), // {row_marker}
            ],
          ),
        ), // {header_marker}
      if (!bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadLogo(),
        ),"""

legacy_icon = re.compile(
    r"(?:Image\.memory\([\s\S]*?|Image\.asset\([\s\S]*?|Container\(\s*"
    r"constraints: const BoxConstraints\(maxWidth: 300, maxHeight: 72\),\s*"
    r"child: Image\.asset\([\s\S]*?)"
    rf"// {icon_marker}",
    re.MULTILINE,
)

if icon_marker in text and header_marker in text:
    if not legacy_icon.search(text):
        raise SystemExit("source-patcher: F10 home icon marker found but block shape unexpected")
    text = legacy_icon.sub(logo_widget, text, count=1)
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

legacy_block = re.compile(
    rf"if \(bind\.isCustomClient\(\)\)\)?\s*"
    rf"Align\([\s\S]*?// {header_marker}\s*"
    rf"(?:if \(!bind\.isCustomClient\(\)\)\s*"
    rf"Align\([\s\S]*?loadLogo\(\),\s*\),\s*)?",
    re.MULTILINE,
)
legacy_block_else = re.compile(
    rf"if \(bind\.isCustomClient\(\)\)\s*Align\([\s\S]*?// {header_marker}\s*"
    rf"else \.\.\.\[[\s\S]*?loadLogo\(\),\s*\),\s*\],",
    re.MULTILINE,
)
upstream_block = re.compile(
    r"if \(bind\.isCustomClient\(\)\)\s*"
    r"Align\(\s*alignment: Alignment\.center,\s*"
    r"child: loadPowered\(context\),\s*\),\s*"
    r"Align\(\s*alignment: Alignment\.center,\s*"
    r"child: loadLogo\(\),\s*\),",
    re.MULTILINE,
)

if header_marker in text or legacy_block.search(text) or legacy_block_else.search(text):
    if legacy_block_else.search(text):
        text = legacy_block_else.sub(logo_scaffold, text, count=1)
    else:
        text = legacy_block.sub(logo_scaffold, text, count=1)
elif upstream_block.search(text):
    text = upstream_block.sub(logo_scaffold, text, count=1)
else:
    raise SystemExit("source-patcher: home logo anchor not found in desktop_home_page.dart")

for item in (header_marker, row_marker, icon_marker, "base64Decode(", "Image.memory(", "loadIcon(48)"):
    if item not in text:
        raise SystemExit(f"source-patcher: F10 missing {item} in desktop_home_page.dart")
if "CUSTOM_RUSTDESK_HOME_POWERED" in text or "loadPowered(context)" in text.split(header_marker)[0]:
    raise SystemExit("source-patcher: F10 home logo must not include powered-by")

path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_HOME_ICON" "$home_file" &&
       grep -q "CUSTOM_RUSTDESK_HOME_HEADER" "$home_file" &&
       grep -q "CUSTOM_RUSTDESK_HOME_TITLE_ROW" "$home_file" &&
       grep -q "base64Decode" "$home_file" &&
       grep -q "Image.memory" "$home_file"; then
        echo "source-patcher: F10 home logo injected in $home_file"
    else
        echo "source-patcher: failed to inject F10 home logo in $home_file" >&2
        return 1
    fi
}
