_custom_patch_flutter_about_studio() {
    local about_file="flutter/lib/desktop/pages/desktop_setting_page.dart"

    if [ -f "$about_file" ]; then
        python3 - "$about_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION"
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
                            ), // CUSTOM_RUSTDESK_ABOUT_LAYOUT
                          ),"""

text = re.sub(
    r"final link = bind\.mainGetBuildinOption\(key: \"custom-customer-link\"\);\s*"
    r"if \(link\.isNotEmpty\) launchUrlString\(link\);",
    "launchUrlString('https://zzsn.work'); // CUSTOM_RUSTDESK_STUDIO_LINK",
    text,
)

if marker in text:
    text = re.sub(
        r"\s*const SizedBox\(height: 12\),\s*// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION",
        "\n                          // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION",
        text,
        count=1,
    )
    text = re.sub(
        r"fontWeight: FontWeight\.w800,\s*fontSize: 13,\s*color: Colors\.white,",
        "fontWeight: FontWeight.w800,\n                                  color: Colors.white,",
        text,
        count=1,
    )
    text = re.sub(
        r"height: 2\.0,\s*\n\s*decoration: TextDecoration\.underline\),\s*\n\s*\),\s*// CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION",
        "decoration: TextDecoration.underline),\n                            ), // CUSTOM_RUSTDESK_ABOUT_LAYOUT\n                          ), // CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION",
        text,
        count=1,
    )
    text = text.replace(
        "style: const TextStyle(color: Colors.white, height: 2.0), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
        "style: const TextStyle(color: Colors.white)",
    )
    text = re.sub(
        r"height: 2\.0\), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
        ")",
        text,
        count=1,
    )
else:
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

path.write_text(text, encoding="utf-8")
PY
        if grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file"; then
            echo "source-patcher: studio attribution aligned below Slogan_tip in $about_file"
        else
            echo "source-patcher: failed to inject studio attribution in $about_file" >&2
            return 1
        fi
    fi

    if [ -f "$about_file" ] && grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file" &&
       grep -q "CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT" "$about_file"; then
        python3 - "$about_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "style: const TextStyle(color: Colors.white, height: 2.0), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
    "style: const TextStyle(color: Colors.white)",
)
text = re.sub(
    r"height: 2\.0\), // CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT",
    ")",
    text,
)
if "CUSTOM_RUSTDESK_ABOUT_LAYOUT" not in text and "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" in text:
    text = text.replace(
        "decoration: TextDecoration.underline),\n                            ),",
        "decoration: TextDecoration.underline),\n                            ), // CUSTOM_RUSTDESK_ABOUT_LAYOUT",
        1,
    )
path.write_text(text, encoding="utf-8")
PY
        echo "source-patcher: removed legacy about line-height hack in $about_file"
    fi

    if [ -f "$about_file" ] && grep -q "CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION" "$about_file" &&
       ! grep -q "CUSTOM_RUSTDESK_ABOUT_LAYOUT" "$about_file"; then
        perl -0pi -e 's/decoration: TextDecoration\.underline\),\s*\n\s*\),(\s*\/\/ CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION)/decoration: TextDecoration.underline),\n                            ), \/\/ CUSTOM_RUSTDESK_ABOUT_LAYOUT$1/' "$about_file"
        if grep -q "CUSTOM_RUSTDESK_ABOUT_LAYOUT" "$about_file"; then
            echo "source-patcher: about layout marker added in $about_file"
        else
            echo "source-patcher: failed to mark about layout in $about_file" >&2
            return 1
        fi
    fi
}
