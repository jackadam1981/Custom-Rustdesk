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

def fix_dart_newline_escape(text: str) -> str:
    broken = "const TextSpan(text: '" + chr(10) + "'),"
    fixed = "const TextSpan(text: '" + chr(92) + "n'),"
    text = text.replace(broken, fixed)
    # Heredoc can turn Copyright \\n into a literal line break inside the string.
    bad = (
        "'Copyright © ${DateTime.now().toString().substring(0, 4)} "
    )
    idx = 0
    while True:
        start = text.find(bad, idx)
        if start < 0:
            break
        end = text.find("$license'", start)
        if end < 0:
            break
        chunk = text[start : end + len("$license'")]
        if chr(10) in chunk and chr(92) + "n" not in chunk:
            fixed_chunk = chunk.replace(chr(10), chr(92) + "n")
            text = text[:start] + fixed_chunk + text[end + len("$license'") :]
        idx = end + 1
    return text

def build_unified_blue_box() -> str:
    dart_nl = chr(92) + "n"
    copyright_text = (
        "'Copyright © ${DateTime.now().toString().substring(0, 4)} Purslane Ltd."
        + dart_nl
        + "$license'"
    )
    return (
        "\n                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION\n"
        "                          // CUSTOM_RUSTDESK_ABOUT_UNIFIED_RICH\n"
        "                          Text.rich(\n"
        "                            TextSpan(\n"
        "                              style: const TextStyle(color: Colors.white),\n"
        "                              children: [\n"
        "                                TextSpan(\n"
        "                                  text: "
        + copyright_text
        + ",\n"
        "                                ),\n"
        "                                const TextSpan(text: '"
        + dart_nl
        + "'),\n"
        "                                TextSpan(\n"
        "                                  text: translate('Slogan_tip'),\n"
        "                                  style: const TextStyle(\n"
        "                                      fontWeight: FontWeight.w800),\n"
        "                                ),\n"
        "                                const TextSpan(text: '"
        + dart_nl
        + "'),\n"
        "                                TextSpan(\n"
        "                                  text: translate('custom_studio_attribution'),\n"
        "                                  style: const TextStyle(\n"
        "                                      fontWeight: FontWeight.w800,\n"
        "                                      decoration: TextDecoration.underline),\n"
        "                                  recognizer: TapGestureRecognizer()\n"
        "                                    ..onTap = () => launchUrlString('https://zzsn.work'), // CUSTOM_RUSTDESK_STUDIO_LINK\n"
        "                                ),\n"
        "                              ],\n"
        "                            ),\n"
        "                          ), // CUSTOM_RUSTDESK_ABOUT_LAYOUT"
    )

def preserve_company_name(block: str, text: str) -> str:
    m = re.search(
        r"'Copyright © \$\{DateTime\.now\(\)\.toString\(\)\.substring\(0, 4\)\} ([^'\\]+)\\n\$license'",
        text,
    )
    if not m:
        return block
    company = m.group(1)
    return block.replace("Purslane Ltd.", company, 1)

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

unified = preserve_company_name(build_unified_blue_box(), text).strip()

# Re-apply: replace prior partial Text.rich (Copyright still separate) or full upstream pair.
patterns = [
    re.compile(
        r"Text\(\s*'Copyright © \$\{DateTime\.now\(\)\.toString\(\)\.substring\(0, 4\)\} [^']+\\n\$license',\s*"
        r"style: const TextStyle\(color: Colors\.white\),\s*"
        r"\),\s*"
        r"// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION[\s\S]*?"
        r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
    ),
    re.compile(
        r"Text\(\s*'Copyright © \$\{DateTime\.now\(\)\.toString\(\)\.substring\(0, 4\)\} [^']+\\n\$license',\s*"
        r"style: const TextStyle\(color: Colors\.white\),\s*"
        r"\),\s*"
        r"Text\(\s*translate\('Slogan_tip'\),\s*"
        r"style: TextStyle\([\s\S]*?"
        r"color: Colors\.white\),\s*"
        r"\)\s*,?",
    ),
    re.compile(
        r"// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION[\s\S]*?"
        r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
    ),
]

replaced = False
for pat in patterns:
    if pat.search(text):
        text = pat.sub(unified, text, count=1)
        replaced = True
        break

if not replaced and marker not in text:
    raise SystemExit("source-patcher: about blue-box anchor not found in desktop_setting_page.dart")

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
       grep -q "CUSTOM_RUSTDESK_ABOUT_UNIFIED_RICH" "$about_file" &&
       grep -q "custom_studio_attribution" "$about_file" &&
       ! grep -q 'CUSTOM_RUSTDESK_ABOUT_LAYOUT\],' "$about_file" &&
       ! grep -q "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN" "$about_file" &&
       ! grep -q "height: 2.0" "$about_file"; then
        echo "source-patcher: studio attribution aligned below Slogan_tip in $about_file"
    else
        echo "source-patcher: failed to patch about page layout in $about_file" >&2
        return 1
    fi
}
