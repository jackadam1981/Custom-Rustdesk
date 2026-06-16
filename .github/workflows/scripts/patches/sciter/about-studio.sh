_custom_patch_sciter_about_studio() {
    if [ -f "src/ui/index.tis" ]; then
        python3 - "src/ui/index.tis" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
studio_p = (
    "<p class='link custom-event studio-about' style='font-weight: bold' url='https://zzsn.work'>\" "
    "+ translate(\"custom_studio_attribution\") + \"</p> \\"
)
text = re.sub(
    r"url='\" \+ handler\.get_builtin_option\(\"custom-customer-link\"\) \+ \"'",
    "url='https://zzsn.work'",
    text,
)
text = re.sub(
    r"\s*<br /><span class='link custom-event studio-about'[^>]*>.*?</span> \\\\",
    "",
    text,
    flags=re.DOTALL,
)
slogan_p = "<p style='font-weight: bold'>\" + translate(\"Slogan_tip\") + \"</p>\\"
if slogan_p in text and studio_p.strip() not in text:
    text = text.replace(slogan_p, slogan_p + "\n            " + studio_p, 1)
elif "studio-about" not in text:
    slogan_plain = '" + translate("Slogan_tip") + " \\'
    if slogan_plain in text:
        text = text.replace(
            slogan_plain,
            '" + translate("Slogan_tip") + " \\\n            ' + studio_p,
            1,
        )
    else:
        raise SystemExit("source-patcher: Slogan_tip anchor not found in src/ui/index.tis")

if "studio-about" not in text:
    raise SystemExit("source-patcher: failed to inject studio attribution in src/ui/index.tis")

text = re.sub(
    r"(function showAbout\(\)[\s\S]*?), 400, get_msgbox_width\(\)\);",
    r"\1, 440, get_msgbox_width()); // CUSTOM_RUSTDESK_ABOUT_HEIGHT",
    text,
    count=1,
)
path.write_text(text, encoding="utf-8")
PY
        if grep -q "studio-about" "src/ui/index.tis"; then
            echo "source-patcher: studio attribution aligned below Slogan_tip in src/ui/index.tis"
        else
            echo "source-patcher: failed to inject studio attribution in src/ui/index.tis" >&2
            return 1
        fi
    fi
}
