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
row_marker = "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN"

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

studio_block = """
                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION
                          InkWell(
                            onTap: () {
                              launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK
                            },
                            child: Text(
                              translate('custom_studio_attribution'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  decoration: TextDecoration.underline),
                            ),
                          ), // CUSTOM_RUSTDESK_ABOUT_LAYOUT"""

text = re.sub(
    r"final link = bind\.mainGetBuildinOption\(key: \"custom-customer-link\"\);\s*"
    r"if \(link\.isNotEmpty\) launchUrlString\(link\);",
    "launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK",
    text,
)

# Remove legacy line-height hack and row-margin injections inside the blue about box.
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
text = normalize_about_layout_close(text)

if marker not in text:
    anchors = [
        re.compile(
            r"(Text\(\s*"
            r"translate\('Slogan_tip'\),\s*"
            r"style: TextStyle\([\s\S]*?"
            r"color: Colors\.white\),\s*"
            r"\)\s*)"
        ),
        re.compile(
            r"(translate\('Slogan_tip'\),\s*"
            r"style: TextStyle\([\s\S]*?"
            r"color: Colors\.white\),\s*"
            r"\),)"
        ),
    ]
    matched = False
    for anchor in anchors:
        if anchor.search(text):
            def _inject_studio(match, block=studio_block):
                chunk = match.group(1).rstrip()
                if not chunk.endswith(","):
                    chunk += ","
                return chunk + block

            text = anchor.sub(_inject_studio, text, count=1)
            matched = True
            break
    if not matched:
        raise SystemExit("source-patcher: Slogan_tip anchor not found in desktop_setting_page.dart")
else:
    studio_pat = re.compile(
        r"InkWell\(\s*"
        r"onTap: \(\) \{\s*"
        r"launchUrlString\('https://zzsn\.work'\); // CUSTOM_RUSTDESK_STUDIO_LINK\s*"
        r"\},\s*"
        r"child: Text\(\s*"
        r"translate\('custom_studio_attribution'\),\s*"
        r"style: (?:const )?TextStyle\([\s\S]*?"
        r"decoration: TextDecoration\.underline\),\s*"
        r"\),\s*"
        r"\)(?:\.marginSymmetric\(vertical: 4\.0\))?, // CUSTOM_RUSTDESK_ABOUT_LAYOUT(?:\],)?",
    )
    text = studio_pat.sub(studio_block.strip(), text, count=1)

if marker not in text:
    raise SystemExit("source-patcher: failed to inject studio attribution in desktop_setting_page.dart")

text = normalize_about_layout_close(text)

path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file" &&
       grep -q "https://zzsn.work" "$about_file" &&
       grep -q "CUSTOM_RUSTDESK_ABOUT_LAYOUT" "$about_file" &&
       ! grep -q 'CUSTOM_RUSTDESK_ABOUT_LAYOUT\],' "$about_file" &&
       ! grep -q "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN" "$about_file" &&
       ! grep -q "height: 2.0" "$about_file"; then
        echo "source-patcher: studio attribution aligned below Slogan_tip in $about_file"
    else
        echo "source-patcher: failed to patch about page layout in $about_file" >&2
        return 1
    fi
}
