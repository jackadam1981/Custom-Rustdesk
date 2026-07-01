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

def company_from_text(text: str) -> str:
    m = re.search(
        r"'Copyright © \$\{DateTime\.now\(\)\.toString\(\)\.substring\(0, 4\)\} ([^'\\]+)\\n\$license'",
        text,
    )
    return m.group(1) if m else "Purslane Ltd."

def build_upstream_copyright_slogan(company: str) -> str:
    return (
        "                          Text(\n"
        f"                            'Copyright © ${{DateTime.now().toString().substring(0, 4)}} {company}\\n$license',\n"
        "                            style: const TextStyle(color: Colors.white),\n"
        "                          ),\n"
        "                          Text(\n"
        "                            translate('Slogan_tip'),\n"
        "                            style: TextStyle(\n"
        "                                fontWeight: FontWeight.w800,\n"
        "                                color: Colors.white),\n"
        "                          )"
    )

def build_studio_insert() -> str:
    return (
        "\n                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION\n"
        "                          // CUSTOM_RUSTDESK_STUDIO_LINK https://zzsn.work\n"
        "                          const Text('\\n'),\n"
        "                          Text(\n"
        "                            translate('custom_studio_attribution'),\n"
        "                            style: const TextStyle(\n"
        "                                fontWeight: FontWeight.w800,\n"
        "                                color: Colors.white,\n"
        "                                decoration: TextDecoration.underline),\n"
        "                          ), // CUSTOM_RUSTDESK_ABOUT_LAYOUT"
    )

text = re.sub(
    r"final link = bind\.mainGetBuildinOption\(key: \"custom-customer-link\"\);\s*"
    r"if \(link\.isNotEmpty\) launchUrlString\(link\);",
    "launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK",
    text,
)

# Strip legacy F12 spacing / unified-rich attempts; upstream rows stay plain Text.
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

company = company_from_text(text)
upstream_pair = build_upstream_copyright_slogan(company)
studio = build_studio_insert()

unified_rich_pat = re.compile(
    r"Text\(\s*'Copyright © \$\{DateTime\.now\(\)\.toString\(\)\.substring\(0, 4\)\} [^']+\\n\$license',\s*"
    r"style: const TextStyle\(color: Colors\.white\),\s*"
    r"\),\s*"
    r"// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION[\s\S]*?"
    r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
)
unified_only_pat = re.compile(
    r"// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION\n"
    r"\s*// CUSTOM_RUSTDESK_ABOUT_UNIFIED_RICH\n"
    r"\s*Text\.rich\([\s\S]*?"
    r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
)
studio_block_pat = re.compile(
    r"\n?\s*// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION[\s\S]*?"
    r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
)
slogan_pat = re.compile(
    r"Text\(\s*translate\('Slogan_tip'\),\s*"
    r"style: TextStyle\([\s\S]*?"
    r"color: Colors\.white\),\s*"
    r"\)\s*,?",
)

replaced = False
if unified_rich_pat.search(text):
    text = unified_rich_pat.sub(upstream_pair + studio, text, count=1)
    replaced = True
elif unified_only_pat.search(text):
    text = unified_only_pat.sub(upstream_pair + studio, text, count=1)
    replaced = True
elif studio_block_pat.search(text):
    text = studio_block_pat.sub(studio, text, count=1)
    replaced = True
elif slogan_pat.search(text):
    def slogan_repl(m: re.Match) -> str:
        body = m.group(0).rstrip()
        if body.endswith(","):
            body = body[:-1].rstrip()
        return body + "," + studio

    text = slogan_pat.sub(slogan_repl, text, count=1)
    replaced = True

if not replaced and marker not in text:
    raise SystemExit("source-patcher: about blue-box anchor not found in desktop_setting_page.dart")

if marker not in text:
    raise SystemExit("source-patcher: failed to inject studio attribution in desktop_setting_page.dart")

text = normalize_about_layout_close(text)
path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file" &&
       grep -q "https://zzsn.work" "$about_file" &&
       grep -q "CUSTOM_RUSTDESK_ABOUT_LAYOUT" "$about_file" &&
       grep -q "translate('Slogan_tip')" "$about_file" &&
       grep -q "translate('custom_studio_attribution')" "$about_file" &&
       grep -q "const Text('\\\\n')" "$about_file" &&
       ! grep -q "CUSTOM_RUSTDESK_ABOUT_UNIFIED_RICH" "$about_file" &&
       ! grep -q 'CUSTOM_RUSTDESK_ABOUT_LAYOUT\],' "$about_file" &&
       ! grep -q "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN" "$about_file" &&
       ! grep -q "height: 2.0" "$about_file"; then
        echo "source-patcher: studio attribution aligned below Slogan_tip in $about_file"
    else
        echo "source-patcher: failed to patch about page layout in $about_file" >&2
        return 1
    fi
}
