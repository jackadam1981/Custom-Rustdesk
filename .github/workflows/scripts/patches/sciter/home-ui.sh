_custom_patch_sciter_home_ui() {
    local index_file="src/ui/index.tis"

    if [ ! -f "$index_file" ]; then
        return 0
    fi

    local brand_file=""
    brand_file=$(mktemp)
    _custom_sciter_custom_brand_block > "$brand_file"

    python3 - "$index_file" "$brand_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
brand = Path(sys.argv[2]).read_text(encoding="utf-8")
text = path.read_text(encoding="utf-8")

powered_block = (
    '{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" '
    '? <div .link .custom-rd-home-powered #powered-by .title style="color:#000;'
    'text-decoration:underline;margin-bottom:0.4em">{translate(\'powered_by_me\')}</div> : ""}'
)
plain_tip = (
    "<div .lighter-text>{outgoing_only ? translate('outgoing_only_desk_tip') "
    ": translate('desk_tip')}</div>"
)
wrong_tip = plain_tip + (
    '{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" '
    '? <div .link #powered-by style="opacity:0.85;font-size:1em;text-decoration:underline;'
    'margin-top:0.4em">{translate(\'powered_by_me\')}</div> : ""} '
    '<!-- CUSTOM_RUSTDESK_HOME_POWERED -->'
)
old_header = (
    '{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" '
    '? <div .link #powered-by style="opacity:0.5;font-size:0.8em;text-decoration:underline">'
    "{translate('powered_by_me')}</div> : \"\"}"
)
old_click = 'event click $(#powered-by) {\n    handler.open_url("https://rustdesk.com");\n}'
new_click = (
    'event click $(#powered-by) { var link = handler.get_builtin_option("custom-customer-link"); '
    'handler.open_url(link && link.length ? link : "https://rustdesk.com"); }'
)
right_anchor = (
    "{!incoming_only && <div .right-pane>\n"
    "                    <div .right-content>\n"
    "                        <div .card-connect>"
)
right_with_powered = (
    "{!incoming_only && <div .right-pane>\n"
    "                    <div .right-content>\n"
    "                        " + powered_block + "\n"
    "                        <div .card-connect>"
)
text_only_brand = (
    '{is_custom_client ? <div #custom-brand style="text-align:center;margin-bottom:0.35em;'
    'font-size:1.1em;font-weight:bold">{handler.get_builtin_option("app-name") || handler.get_builtin_option("custom-customer-name")}'
    '</div> : ""}'
)
legacy_brand = re.compile(
    r"\{is_custom_client \? <div #custom-brand(?:\.custom-rd-home-header)?[^>]*>.*?"
    r"\{handler\.get_builtin_option\([^)]+\)(?: \|\| handler\.get_builtin_option\([^)]+\))?.*?</div> : \"\"\}",
    re.DOTALL,
)
legacy_powered = re.compile(
    r'\{is_custom_client && handler\.get_builtin_option\("hide-powered-by-me"\) != "Y" '
    r'\? <div \.link(?: \.custom-rd-home-powered)? #powered-by style="[^"]*">'
    r"\{translate\('powered_by_me'\)\}</div> : \"\"\}\s*"
    r'(?:<!-- CUSTOM_RUSTDESK_HOME_POWERED -->)?'
)

text = text.replace(" <!-- CUSTOM_RUSTDESK_HOME_POWERED -->", "")
text = text.replace(" <!-- CUSTOM_RUSTDESK_HOME_HEADER -->", "")
text = re.sub(r"\s*<!-- CUSTOM_RUSTDESK_HOME_LOGO -->", "", text)

changed = False

if old_header in text:
    text = text.replace(old_header, brand, 1)
    changed = True
elif text_only_brand in text and brand != text_only_brand:
    text = text.replace(text_only_brand, brand, 1)
    changed = True
elif "custom-rd-home-header" not in text and "#custom-brand" in text:
    match = legacy_brand.search(text)
    if match and match.group(0) != brand:
        text = legacy_brand.sub(brand, text, count=1)
        changed = True

if wrong_tip in text:
    text = text.replace(wrong_tip, plain_tip, 1)
    changed = True

if "custom-rd-home-powered" not in text:
    text = legacy_powered.sub("", text)
    if right_anchor not in text:
        raise SystemExit("source-patcher: missing sciter right-pane card-connect anchor")
    text = text.replace(right_anchor, right_with_powered, 1)
    changed = True
elif powered_block not in text:
    upgraded = re.sub(
        r"\{is_custom_client && handler\.get_builtin_option\(\"hide-powered-by-me\"\) != \"Y\" "
        r"\? <div \.link \.custom-rd-home-powered #powered-by(?: \.title)? style=\"[^\"]*\">"
        r"\{translate\('powered_by_me'\)\}</div> : \"\"\}",
        powered_block,
        text,
        count=1,
    )
    if upgraded != text:
        text = upgraded
        changed = True
    elif right_anchor in text:
        text = legacy_powered.sub("", text)
        text = text.replace(right_anchor, right_with_powered, 1)
        changed = True

if brand not in text:
    match = legacy_brand.search(text)
    if match and match.group(0) != brand:
        text = legacy_brand.sub(brand, text, count=1)
        changed = True

if old_click in text:
    text = text.replace(old_click, new_click, 1)
    changed = True

if not changed and "custom-rd-home-header" not in text and "custom-rd-home-powered" not in text:
    raise SystemExit("source-patcher: sciter home UI patch made no changes")

if Path("res/icon.png").exists() and "custom-rd-home-logo" not in text:
    match = legacy_brand.search(text)
    if match and match.group(0) != brand:
        text = legacy_brand.sub(brand, text, count=1)
        changed = True

path.write_text(text, encoding="utf-8")
PY
    rm -f "$brand_file"

    if grep -q "custom-rd-home-header" "$index_file" &&
       grep -q "custom-rd-home-powered" "$index_file"; then
        if grep -q "card-connect" "$index_file" &&
           python3 - "$index_file" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "custom-rd-home-powered"
card = "<div .card-connect>"
idx_powered = text.find(marker)
idx_card = text.find(card)
if idx_powered == -1 or idx_card == -1 or idx_powered > idx_card:
    raise SystemExit(1)
PY
        then
            if grep -q "custom-rd-home-logo" "$index_file"; then
                echo "source-patcher: sciter home header with logo injected in $index_file"
            else
                echo "source-patcher: sciter home header injected in $index_file"
            fi
            echo "source-patcher: customer powered_by injected above Control Remote Desktop in $index_file"
        else
            echo "source-patcher: sciter powered_by marker is not above card-connect in $index_file" >&2
            return 1
        fi
    else
        echo "source-patcher: failed to inject sciter home UI in $index_file" >&2
        return 1
    fi
}
