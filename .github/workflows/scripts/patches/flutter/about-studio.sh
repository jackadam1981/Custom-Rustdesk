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
row_margin = ".marginSymmetric(vertical: 4.0)"
row_marker = "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN"

studio_block = """
                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION
                          InkWell(
                            onTap: () {
                              launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK
                            },
                            child: Text(
                              translate('custom_studio_attribution'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  decoration: TextDecoration.underline),
                            ),
                          )%s, // CUSTOM_RUSTDESK_ABOUT_LAYOUT""" % row_margin

text = re.sub(
    r"final link = bind\.mainGetBuildinOption\(key: \"custom-customer-link\"\);\s*"
    r"if \(link\.isNotEmpty\) launchUrlString\(link\);",
    "launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK",
    text,
)

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
                if row_margin not in chunk:
                    chunk = chunk.rstrip(",") + row_margin + ", // " + row_marker
                return chunk + block

            text = anchor.sub(_inject_studio, text, count=1)
            matched = True
            break
    if not matched:
        raise SystemExit("source-patcher: Slogan_tip anchor not found in desktop_setting_page.dart")

# Normalize blue about-box row spacing to match version/build rows above.
text = text.replace(
    "style: const TextStyle(color: Colors.white, height: 2.0), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
    "style: const TextStyle(color: Colors.white)",
)
text = re.sub(
    r"height: 2\.0\), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
    ")",
    text,
)

copyright_pat = re.compile(
    r"(Text\(\s*"
    r"'Copyright © \$\{DateTime\.now\(\)\.toString\(\)\.substring\(0, 4\)\} Purslane Ltd\.\\n\$license',\s*"
    r"style: const TextStyle\(color: Colors\.white\),\s*"
    r"\))"
    r"(?!\.marginSymmetric\(vertical: 4\.0\))",
)
text = copyright_pat.sub(r"\1" + row_margin + ", // " + row_marker, text, count=1)

slogan_pat = re.compile(
    r"(Text\(\s*"
    r"translate\('Slogan_tip'\),\s*"
    r"style: TextStyle\(\s*"
    r"fontWeight: FontWeight\.w800,\s*"
    r"color: Colors\.white\),\s*"
    r"\))"
    r"(?!\.marginSymmetric\(vertical: 4\.0\))",
)
text = slogan_pat.sub(r"\1" + row_margin + ", // " + row_marker, text, count=1)

# Legacy studio row: comment on inner Text instead of InkWell margin.
text = re.sub(
    r"InkWell\(\s*"
    r"onTap: \(\) \{\s*"
    r"launchUrlString\('https://zzsn\.work'\); // CUSTOM_RUSTDESK_STUDIO_LINK\s*"
    r"\},\s*"
    r"child: Text\(\s*"
    r"translate\('custom_studio_attribution'\),\s*"
    r"style: const TextStyle\(\s*"
    r"fontWeight: FontWeight\.w800,\s*"
    r"color: Colors\.white,\s*"
    r"decoration: TextDecoration\.underline\),\s*"
    r"\), // CUSTOM_RUSTDESK_ABOUT_LAYOUT\s*"
    r"\),\s*\]",
    """InkWell(
                            onTap: () {
                              launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK
                            },
                            child: Text(
                              translate('custom_studio_attribution'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  decoration: TextDecoration.underline),
                            ),
                          )""" + row_margin + ", // CUSTOM_RUSTDESK_ABOUT_LAYOUT\n                          ],",
    text,
    count=1,
)

text = text.replace(
    "// CUSTOM_RUSTDESK_ABOUT_LAYOUT],",
    "// CUSTOM_RUSTDESK_ABOUT_LAYOUT\n                          ],",
)

studio_pat = re.compile(
    r"(InkWell\(\s*"
    r"onTap: \(\) \{\s*"
    r"launchUrlString\('https://zzsn\.work'\); // CUSTOM_RUSTDESK_STUDIO_LINK\s*"
    r"\},\s*"
    r"child: Text\(\s*"
    r"translate\('custom_studio_attribution'\),\s*"
    r"style: const TextStyle\(\s*"
    r"fontWeight: FontWeight\.w800,\s*"
    r"color: Colors\.white,\s*"
    r"decoration: TextDecoration\.underline\),\s*"
    r"\),\s*"
    r"\))"
    r"(?!\.marginSymmetric\(vertical: 4\.0\))",
)
text = studio_pat.sub(r"\1" + row_margin + ", // CUSTOM_RUSTDESK_ABOUT_LAYOUT", text, count=1)

if marker not in text:
    raise SystemExit("source-patcher: failed to inject studio attribution in desktop_setting_page.dart")
if row_marker not in text:
    raise SystemExit("source-patcher: failed to apply about row spacing in desktop_setting_page.dart")

path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file" &&
       grep -q "CUSTOM_RUSTDESK_ABOUT_ROW_MARGIN" "$about_file"; then
        echo "source-patcher: studio attribution and about row spacing applied in $about_file"
    else
        echo "source-patcher: failed to patch about page layout in $about_file" >&2
        return 1
    fi
}
