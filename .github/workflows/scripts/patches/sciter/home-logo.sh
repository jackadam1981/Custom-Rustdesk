# S10 — Sciter 首页 logo（48px，依赖 B02 res/logo.png）
_custom_patch_sciter_home_logo() {
    local index_file="src/ui/index.tis"

    if [ ! -f "$index_file" ]; then
        return 0
    fi

    local logo_file_tmp=""
    local logo_src_file_tmp=""
    logo_markup=$(_custom_sciter_logo_img_markup)
    logo_src_fn=$(_custom_sciter_logo_src_function)
    if [ -z "$logo_markup" ] || [ -z "$logo_src_fn" ]; then
        echo "source-patcher: res/logo.png missing — apply B02 before S10" >&2
        return 1
    fi

    logo_file_tmp=$(mktemp)
    logo_src_file_tmp=$(mktemp)
    printf '%s' "$logo_markup" > "$logo_file_tmp"
    printf '%s' "$logo_src_fn" > "$logo_src_file_tmp"

    python3 - "$index_file" "$logo_file_tmp" "$logo_src_file_tmp" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
logo = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
logo_src = Path(sys.argv[3]).read_text(encoding="utf-8").strip()
text = path.read_text(encoding="utf-8")

app_anchor = "class App: Reactor.Component"
src_marker = "CUSTOM_RUSTDESK_SCITER_HOME_LOGO_SRC"
src_fn_name = "function customHomeLogoSrc()"

if src_marker in text:
    text = re.sub(
        r"function customHomeLogoSrc\(\) \{[\s\S]*?\} <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO_SRC -->",
        logo_src,
        text,
        count=1,
    )
elif src_fn_name in text:
    raise SystemExit("source-patcher: S10 customHomeLogoSrc present without marker")
elif app_anchor not in text:
    raise SystemExit("source-patcher: S10 App class anchor not found in src/ui/index.tis")
else:
    text = text.replace(app_anchor, logo_src + "\n\n" + app_anchor, 1)

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
    text = logo_pat.sub(logo.replace(" <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->", ""), text, count=1)
    if "CUSTOM_RUSTDESK_SCITER_HOME_LOGO" not in text:
        text = text.replace(
            logo.replace(" <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->", ""),
            logo,
            1,
        )
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

if src_marker not in text or src_fn_name not in text:
    raise SystemExit("source-patcher: S10 customHomeLogoSrc helper missing")

if 'custom-rd-home-logo src="data:image/png;base64,' in text:
    raise SystemExit("source-patcher: S10 still uses inline base64 logo src")

path.write_text(text, encoding="utf-8")
PY
    rm -f "$logo_file_tmp" "$logo_src_file_tmp"

    if grep -q "custom-rd-home-header" "$index_file" &&
       grep -q "custom-rd-home-title-row" "$index_file" &&
       grep -q "custom-rd-home-logo" "$index_file" &&
       grep -q "customHomeLogoSrc" "$index_file" &&
       grep -q "CUSTOM_RUSTDESK_SCITER_HOME_LOGO" "$index_file" &&
       grep -q "CUSTOM_RUSTDESK_SCITER_HOME_LOGO_SRC" "$index_file"; then
        echo "source-patcher: S10 home logo injected in $index_file"
    else
        echo "source-patcher: failed to inject S10 home logo in $index_file" >&2
        return 1
    fi
}
