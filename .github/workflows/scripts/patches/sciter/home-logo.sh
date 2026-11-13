# 501 — Sciter 首页 logo（48px，依赖 202 res/logo.png）
# ui.rs 的 get_icon() 改读 res/icon.png（include_bytes!），sciter 才能真正显示定制图标。

_custom_patch_sciter_home_logo_strip_handler() {
    local ui_file="src/ui.rs"

    if [ ! -f "$ui_file" ]; then
        return 0
    fi

    if ! grep -q "CUSTOM_RUSTDESK_HOME_LOGO_SRC\|get_home_logo_src" "$ui_file"; then
        return 0
    fi

    python3 - "$ui_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = re.sub(
    r"\npub fn get_home_logo_src\(\) -> String \{[\s\S]*?// CUSTOM_RUSTDESK_HOME_LOGO_SRC[\s\S]*?\n\}\n",
    "\n",
    text,
    count=1,
)
text = text.replace(
    "    fn get_home_logo_src(&mut self) -> String {\n"
    "        get_home_logo_src()\n"
    "    }\n\n",
    "",
    1,
)
text = text.replace("        fn get_home_logo_src();\n", "", 1)

if "CUSTOM_RUSTDESK_HOME_LOGO_SRC" in text or "get_home_logo_src" in text:
    raise SystemExit("source-patcher: failed to strip 501 legacy get_home_logo_src from src/ui.rs")

path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_HOME_LOGO_SRC\|get_home_logo_src" "$ui_file"; then
        echo "source-patcher: failed to strip 501 legacy home logo handler from $ui_file" >&2
        return 1
    fi
    echo "source-patcher: 501 stripped legacy get_home_logo_src from $ui_file (icon probe)"
}

_custom_patch_sciter_home_logo_handler() {
    # 先清掉历史遗留的 get_home_logo_src，再把 get_icon() 改成读 res/icon.png
    _custom_patch_sciter_home_logo_strip_handler || return 1

    local ui_file="src/ui.rs"
    if [ ! -f "$ui_file" ]; then
        return 0
    fi
    if [ ! -f "res/icon.png" ]; then
        echo "source-patcher: res/icon.png missing — apply 202 icon_url before 501" >&2
        return 1
    fi
    if grep -q "CUSTOM_RUSTDESK_SCITER_ICON_SRC_START" "$ui_file"; then
        echo "source-patcher: sciter icon source already patched"
        return 0
    fi

    python3 - "$ui_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

new_fn = '''pub fn get_icon() -> String {
    // CUSTOM_RUSTDESK_SCITER_ICON_SRC_START
    let custom_icon: &[u8] = include_bytes!("../res/icon.png");
    let s = hbb_common::sodiumoxide::base64::encode(
        custom_icon.to_vec(),
        hbb_common::sodiumoxide::base64::Variant::Original,
    );
    format!("data:image/png;base64,{s}")
    // CUSTOM_RUSTDESK_SCITER_ICON_SRC_END
}'''

pattern = re.compile(r"pub fn get_icon\(\) -> String \{\n[\s\S]*?\n\}\n", re.MULTILINE)
if not pattern.search(text):
    raise SystemExit("source-patcher: get_icon() anchor not found in src/ui.rs")

text = pattern.sub(new_fn + "\n", text, count=1)
if "CUSTOM_RUSTDESK_SCITER_ICON_SRC_START" not in text:
    raise SystemExit("source-patcher: failed to inject sciter icon source in src/ui.rs")
path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_SCITER_ICON_SRC_START" "$ui_file" &&
       grep -q 'include_bytes!("../res/icon.png")' "$ui_file"; then
        echo "source-patcher: 501 sciter icon now reads res/icon.png from $ui_file"
    else
        echo "source-patcher: failed to point sciter icon at res/icon.png in $ui_file" >&2
        return 1
    fi
}

_custom_patch_sciter_home_logo() {
    local index_file="src/ui/index.tis"

    if [ ! -f "$index_file" ]; then
        return 0
    fi

    _custom_patch_sciter_home_logo_handler || return 1

    local logo_file_tmp=""
    logo_markup=$(_custom_sciter_logo_img_markup)
    if [ -z "$logo_markup" ]; then
        echo "source-patcher: res/logo.png missing — apply 202 before 501" >&2
        return 1
    fi

    logo_file_tmp=$(mktemp)
    printf '%s' "$logo_markup" > "$logo_file_tmp"

    python3 - "$index_file" "$logo_file_tmp" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
logo = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = path.read_text(encoding="utf-8")
logo_handler = "handler.get_icon()"

legacy_src_fn = re.compile(
    r"function customHomeLogoSrc\(\) \{[\s\S]*?\} <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO_SRC -->\n*"
)
if legacy_src_fn.search(text):
    text = legacy_src_fn.sub("", text, count=1)

logo = logo.replace("customHomeLogoSrc()", logo_handler)
logo = logo.replace("handler.get_home_logo_src()", logo_handler)
logo_plain = logo.replace(" <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->", "")
logo_plain = logo_plain.replace(" <!-- CUSTOM_RUSTDESK_501_ICON_PROBE -->", "")
if "CUSTOM_RUSTDESK_501_ICON_PROBE" not in logo:
    logo = logo.replace(
        " <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->",
        " <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO --> <!-- CUSTOM_RUSTDESK_501_ICON_PROBE -->",
        1,
    )

logo_shell = (
    '{is_custom_client ? <div #custom-brand.custom-rd-home-header style="text-align:center;margin-bottom:0.35em">'
    f'<div .custom-rd-home-title-row style="flow:horizontal;horizontal-align:center;vertical-align:middle">{logo}</div>'
    "</div> : \"\"} <!-- CUSTOM_RUSTDESK_SCITER_HOME_HEADER -->"
)

legacy_brand = re.compile(
    r"\{is_custom_client \? <div #custom-brand(?:\.custom-rd-home-header)?[^>]*>.*?"
    r"\{handler\.get_builtin_option\([^)]+\)(?: \|\| handler\.get_builtin_option\([^)]+\))?.*?</div> : \"\"\}",
    re.DOTALL,
)
old_header = (
    '{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" '
    '? <div .link #powered-by style="opacity:0.5;font-size:0.8em;text-decoration:underline">'
    "{translate('powered_by_me')}</div> : \"\"}"
)
text_only_brand = (
    '{is_custom_client ? <div #custom-brand style="text-align:center;margin-bottom:0.35em;'
    'font-size:1.1em;font-weight:bold">{handler.get_builtin_option("app-name") || handler.get_builtin_option("custom-customer-name")}'
    '</div> : ""}'
)
logo_pat = re.compile(
    r"<img\.custom-rd-home-logo[^>]*/>\s*(?:<!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->)?\s*(?:<!-- CUSTOM_RUSTDESK_501_ICON_PROBE -->)?"
)

changed = False
if "CUSTOM_RUSTDESK_SCITER_HOME_HEADER" in text and logo_pat.search(text):
    text = logo_pat.sub(logo_plain, text, count=1)
    if "CUSTOM_RUSTDESK_SCITER_HOME_LOGO" not in text:
        text = text.replace(logo_plain, logo, 1)
    changed = True
elif legacy_brand.search(text):
    text = legacy_brand.sub(logo_shell, text, count=1)
    changed = True
elif old_header in text:
    text = text.replace(old_header, logo_shell, 1)
    changed = True
elif text_only_brand in text:
    text = text.replace(text_only_brand, logo_shell, 1)
    changed = True
elif "custom-rd-home-header" not in text:
    raise SystemExit("source-patcher: 501 home logo anchor not found in src/ui/index.tis")

if not changed and "custom-rd-home-logo" not in text:
    raise SystemExit("source-patcher: 501 home logo patch made no changes")

if "custom-rd-home-header" not in text or "custom-rd-home-title-row" not in text:
    raise SystemExit("source-patcher: 501 home logo header shell missing")

if logo_handler not in text:
    raise SystemExit("source-patcher: 501 icon probe must use handler.get_icon() in index.tis")

if "CUSTOM_RUSTDESK_501_ICON_PROBE" not in text:
    raise SystemExit("source-patcher: 501 icon probe marker missing in index.tis")

if "handler.get_home_logo_src()" in text:
    raise SystemExit("source-patcher: 501 icon probe must not use handler.get_home_logo_src()")

if "customHomeLogoSrc" in text:
    raise SystemExit("source-patcher: 501 legacy customHomeLogoSrc still present in index.tis")

if 'custom-rd-home-logo src="data:image/png;base64,' in text:
    raise SystemExit("source-patcher: 501 still uses inline base64 logo src in index.tis")

path.write_text(text, encoding="utf-8")
PY
    rm -f "$logo_file_tmp"

    if grep -q "custom-rd-home-header" "$index_file" &&
       grep -q "custom-rd-home-title-row" "$index_file" &&
       grep -q "custom-rd-home-logo" "$index_file" &&
       grep -q "handler.get_icon()" "$index_file" &&
       grep -q "CUSTOM_RUSTDESK_501_ICON_PROBE" "$index_file" &&
       grep -q "CUSTOM_RUSTDESK_SCITER_HOME_LOGO" "$index_file" &&
       ! grep -q "handler.get_home_logo_src()" "$index_file" &&
       ! grep -q "CUSTOM_RUSTDESK_HOME_LOGO_SRC\|get_home_logo_src" "src/ui.rs" 2>/dev/null; then
        echo "source-patcher: 501 home logo (icon probe) injected in $index_file"
    else
        echo "source-patcher: failed to inject 501 home logo in $index_file" >&2
        return 1
    fi
}
