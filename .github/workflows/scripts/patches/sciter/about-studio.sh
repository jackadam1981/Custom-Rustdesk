_custom_patch_sciter_about_studio() {
    if [ -f "src/ui/index.tis" ]; then
        python3 - "src/ui/index.tis" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

studio_html = (
    "<p class='link custom-event studio-about' style='font-weight: bold' url='https://zzsn.work'>\" "
    "+ translate(\"custom_studio_attribution\") + \"</p> \\"
)
studio_plain = (
    "<span class='link custom-event studio-about' style='font-weight: bold' url='https://zzsn.work'>\" "
    "+ translate(\"custom_studio_attribution\") + \"</span> \\"
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

if "studio-about" not in text:
    injected = False
    legacy_slogan = "<p style='font-weight: bold'>\" + translate(\"Slogan_tip\") + \"</p>\\"
    if legacy_slogan in text:
        text = text.replace(legacy_slogan, legacy_slogan + "\n            " + studio_html, 1)
        injected = True
    else:
        plain_slogan = '" + translate("Slogan_tip") + " \\'
        if plain_slogan in text:
            text = text.replace(
                plain_slogan,
                plain_slogan + "\n            " + studio_plain,
                1,
            )
            injected = True
        else:
            raise SystemExit("source-patcher: Slogan_tip anchor not found in src/ui/index.tis")
    if not injected:
        raise SystemExit("source-patcher: failed to inject studio attribution in src/ui/index.tis")

if "custom_studio_attribution" not in text:
    raise SystemExit("source-patcher: studio attribution translate key missing in src/ui/index.tis")

text = re.sub(
    r"(function showAbout\(\)[\s\S]*?), 400, get_msgbox_width\(\)\);",
    r"\1, 480, get_msgbox_width()); // CUSTOM_RUSTDESK_ABOUT_HEIGHT",
    text,
    count=1,
)
text = re.sub(
    r"(function showAbout\(\)[\s\S]*?), 440, get_msgbox_width\(\)\); // CUSTOM_RUSTDESK_ABOUT_HEIGHT",
    r"\1, 480, get_msgbox_width()); // CUSTOM_RUSTDESK_ABOUT_HEIGHT",
    text,
    count=1,
)

path.write_text(text, encoding="utf-8")
PY
        if grep -q "studio-about" "src/ui/index.tis" &&
           grep -q "custom_studio_attribution" "src/ui/index.tis"; then
            echo "source-patcher: studio attribution aligned below Slogan_tip in src/ui/index.tis"
        else
            echo "source-patcher: failed to inject studio attribution in src/ui/index.tis" >&2
            return 1
        fi
    fi
}
