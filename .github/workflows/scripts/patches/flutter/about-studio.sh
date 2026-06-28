_custom_patch_flutter_about_studio() {
    local about_file="flutter/lib/desktop/pages/desktop_setting_page.dart"

    if [ ! -f "$about_file" ]; then
        return 0
    fi

    python3 - "$about_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION"

def normalize_about_layout_close(text: str) -> str:
    text = re.sub(
        r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT\],",
        "), // CUSTOM_RUSTDESK_ABOUT_LAYOUT\n                          ],",
        text,
    )
    text = re.sub(
        r"// CUSTOM_RUSTDESK_ABOUT_LAYOUT\],",
        "// CUSTOM_RUSTDESK_ABOUT_LAYOUT\n                          ],",
        text,
    )
    return text

# One Text.rich block: Slogan_tip + newline + studio link share the same line
# spacing as Copyright's internal "\n" breaks (original about blue-box rhythm).
studio_rich_block = (
    "\n                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION\n"
    "                          Text.rich(\n"
    "                            TextSpan(\n"
    "                              children: [\n"
    "                                TextSpan(\n"
    "                                  text: translate('Slogan_tip'),\n"
    "                                  style: TextStyle(\n"
    "                                      fontWeight: FontWeight.w800,\n"
    "                                      color: Colors.white),\n"
    "                                ),\n"
    "                                const TextSpan(text: '\\n'),\n"
    "                                TextSpan(\n"
    "                                  text: translate('custom_studio_attribution'),\n"
    "                                  style: TextStyle(\n"
    "                                      fontWeight: FontWeight.w800,\n"
    "                                      color: Colors.white,\n"
    "                                      decoration: TextDecoration.underline),\n"
    "                                  recognizer: TapGestureRecognizer()\n"
    "                                    ..onTap = () => launchUrlString('https://zzsn.work'), // CUSTOM_RUSTDESK_STUDIO_LINK\n"
    "                                ),\n"
    "                              ],\n"
    "                            ),\n"
    "                          ), // CUSTOM_RUSTDESK_ABOUT_LAYOUT"
)

def fix_dart_newline_escape(text: str) -> str:
    broken = "const TextSpan(text: '" + chr(10) + "'),"
    fixed = "const TextSpan(text: '" + chr(92) + "n'),"
    return text.replace(broken, fixed)

text = re.sub(
    r"final link = bind\.mainGetBuildinOption\(key: \"custom-customer-link\"\);\s*"
    r"if \(link\.isNotEmpty\) launchUrlString\(link\);",
    "launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK",
    text,
)

# Remove legacy spacing hacks from older F12 attempts.
text = text.replace(
    "style: const TextStyle(color: Colors.white, height: 2.0), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
    "style: const TextStyle(color: Colors.white)",
)
text = re.sub(
    r"height: 2\.0\), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
    ")",
    text,
)
text = re.sub(
    r"\)\.marginSymmetric\(vertical: 4\.0\), // CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN,?",
    ")",
    text,
)
text = re.sub(
    r"\)\.marginSymmetric\(vertical: 4\.0\), // CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN",
    ")",
    text,
)
text = re.sub(
    r"\)\.marginSymmetric\(vertical: 4\.0\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
    "), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
    text,
)
text = re.sub(
    r"\)\.marginSymmetric\(vertical: 4\.0\)\s*\)\.marginSymmetric\(vertical: 4\.0\)",
    ")",
    text,
)

legacy_combined = re.compile(
    r"Text\(\s*translate\('Slogan_tip'\),\s*"
    r"style: TextStyle\([\s\S]*?"
    r"color: Colors\.white\),\s*"
    r"\)\s*,?\s*"
    r"// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION[\s\S]*?"
    r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
)
if legacy_combined.search(text):
    text = legacy_combined.sub(studio_rich_block.strip(), text, count=1)
elif marker in text:
    studio_pat = re.compile(
        r"// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION[\s\S]*?"
        r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
    )
    text = studio_pat.sub(studio_rich_block.strip(), text, count=1)
else:
    slogan_only = re.compile(
        r"Text\(\s*translate\('Slogan_tip'\),\s*"
        r"style: TextStyle\([\s\S]*?"
        r"color: Colors\.white\),\s*"
        r"\)\s*,?"
    )
    if not slogan_only.search(text):
        raise SystemExit("source-patcher: Slogan_tip anchor not found in desktop_setting_page.dart")
    text = slogan_only.sub(studio_rich_block.strip(), text, count=1)

if marker not in text:
    raise SystemExit("source-patcher: failed to inject studio attribution in desktop_setting_page.dart")

if "package:flutter/gestures.dart" not in text:
    text = text.replace(
        "import 'package:flutter/material.dart';",
        "import 'package:flutter/gestures.dart';\nimport 'package:flutter/material.dart';",
        1,
    )

text = normalize_about_layout_close(text)
text = fix_dart_newline_escape(text)
path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file" &&
       grep -q "https://zzsn.work" "$about_file" &&
       grep -q "CUSTOM_RUSTDESK_ABOUT_LAYOUT" "$about_file" &&
       grep -q "Text.rich" "$about_file" &&
       grep -q "TapGestureRecognizer" "$about_file" &&
       ! grep -q 'CUSTOM_RUSTDESK_ABOUT_LAYOUT\],' "$about_file" &&
       ! grep -q "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN" "$about_file" &&
       ! grep -q "height: 2.0" "$about_file"; then
        echo "source-patcher: studio attribution aligned below Slogan_tip in $about_file"
    else
        echo "source-patcher: failed to patch about page layout in $about_file" >&2
        return 1
    fi
}
