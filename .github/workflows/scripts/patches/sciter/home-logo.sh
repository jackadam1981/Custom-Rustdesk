# S10 — Sciter 首页 logo（48px，依赖 B02 res/logo.png）
_custom_patch_sciter_home_logo_handler() {
    local ui_file="src/ui.rs"

    if [ ! -f "$ui_file" ] || [ ! -f "res/logo.png" ]; then
        return 0
    fi

    python3 - "$ui_file" "res/logo.png" <<'PY'
import base64
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
logo_path = Path(sys.argv[2])
text = path.read_text(encoding="utf-8")
data = base64.b64encode(logo_path.read_bytes()).decode("ascii")

rust_fn = (
    "\npub fn get_home_logo_src() -> String {\n"
    "    // CUSTOM_RUSTDESK_HOME_LOGO_SRC\n"
    f'    "data:image/png;base64,{data}".into()\n'
    "}\n"
)

if "CUSTOM_RUSTDESK_HOME_LOGO_SRC" in text:
    text = re.sub(
        r"\npub fn get_home_logo_src\(\) -> String \{[\s\S]*?// CUSTOM_RUSTDESK_HOME_LOGO_SRC[\s\S]*?\n\}\n",
        rust_fn,
        text,
        count=1,
    )
elif "pub fn get_home_logo_src()" not in text:
    anchor = "\npub fn get_icon() -> String {"
    if anchor not in text:
        raise SystemExit("source-patcher: S10 get_icon anchor not found in src/ui.rs")
    text = text.replace(anchor, rust_fn + anchor, 1)

impl_anchor = "    fn get_icon(&mut self) -> String {\n        get_icon()\n    }"
impl_block = (
    "    fn get_home_logo_src(&mut self) -> String {\n"
    "        get_home_logo_src()\n"
    "    }\n\n"
    + impl_anchor
)
if "fn get_home_logo_src(&mut self)" in text:
  pass
elif impl_anchor in text:
    text = text.replace(impl_anchor, impl_block, 1)
else:
    raise SystemExit("source-patcher: S10 UI::get_icon impl anchor not found in src/ui.rs")

macro_anchor = "        fn get_icon();"
macro_block = "        fn get_home_logo_src();\n" + macro_anchor
if "fn get_home_logo_src();" not in text:
    if macro_anchor not in text:
        raise SystemExit("source-patcher: S10 get_icon macro anchor not found in src/ui.rs")
    text = text.replace(macro_anchor, macro_block, 1)

if "CUSTOM_RUSTDESK_HOME_LOGO_SRC" not in text or "get_home_logo_src" not in text:
    raise SystemExit("source-patcher: failed to inject S10 home logo handler in src/ui.rs")

path.write_text(text, encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_HOME_LOGO_SRC" "$ui_file" &&
       grep -q "get_home_logo_src" "$ui_file"; then
        echo "source-patcher: S10 home logo handler injected in $ui_file"
    else
        echo "source-patcher: failed to inject S10 home logo handler in $ui_file" >&2
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
        echo "source-patcher: res/logo.png missing — apply B02 before S10" >&2
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

legacy_src_fn = re.compile(
    r"function customHomeLogoSrc\(\) \{[\s\S]*?\} <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO_SRC -->\n*"
)
if legacy_src_fn.search(text):
    text = legacy_src_fn.sub("", text, count=1)

logo = logo.replace("customHomeLogoSrc()", "handler.get_home_logo_src()")
logo_plain = logo.replace(" <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->", "")

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
    r"<img\.custom-rd-home-logo[^>]*/>\s*(?:<!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->)?"
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
    raise SystemExit("source-patcher: S10 home logo anchor not found in src/ui/index.tis")

if not changed and "custom-rd-home-logo" not in text:
    raise SystemExit("source-patcher: S10 home logo patch made no changes")

if "custom-rd-home-header" not in text or "custom-rd-home-title-row" not in text:
    raise SystemExit("source-patcher: S10 home logo header shell missing")

if "handler.get_home_logo_src()" not in text:
    raise SystemExit("source-patcher: S10 home logo must use handler.get_home_logo_src()")

if "customHomeLogoSrc" in text:
    raise SystemExit("source-patcher: S10 legacy customHomeLogoSrc still present in index.tis")

if 'custom-rd-home-logo src="data:image/png;base64,' in text:
    raise SystemExit("source-patcher: S10 still uses inline base64 logo src in index.tis")

path.write_text(text, encoding="utf-8")
PY
    rm -f "$logo_file_tmp"

    if grep -q "custom-rd-home-header" "$index_file" &&
       grep -q "custom-rd-home-title-row" "$index_file" &&
       grep -q "custom-rd-home-logo" "$index_file" &&
       grep -q "handler.get_home_logo_src()" "$index_file" &&
       grep -q "CUSTOM_RUSTDESK_SCITER_HOME_LOGO" "$index_file" &&
       grep -q "CUSTOM_RUSTDESK_HOME_LOGO_SRC" "src/ui.rs"; then
        echo "source-patcher: S10 home logo injected in $index_file"
    else
        echo "source-patcher: failed to inject S10 home logo in $index_file" >&2
        return 1
    fi
}
