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
brand = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
text = path.read_text(encoding="utf-8")

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
    "                        {is_custom_client && handler.get_builtin_option(\"hide-powered-by-me\") != \"Y\" "
    "? <div .link .custom-rd-home-powered #powered-by .title style=\"color:#000;"
    "text-decoration:underline;margin-bottom:0.4em\">{translate('powered_by_me')}</div> : \"\"}\n"
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
left_powered_in_brand = re.compile(
    r"\{is_custom_client && handler\.get_builtin_option\(\"hide-powered-by-me\"\) != \"Y\" "
    r"\? <div \.link(?: \.custom-rd-home-powered)? #powered-by(?: \.title)? style=\"[^\"]*\">"
    r"\{translate\('powered_by_me'\)\}</div> : \"\"\}"
)
logo_style_pat = re.compile(
    r"(<img\.custom-rd-home-logo[^>]*style=\")[^\"]*(\")"
)
logo_style_new = (
    r"\1max-width:48px;max-height:48px;width:48px;height:48px;vertical-align:middle\2"
)

text = text.replace(" <!-- CUSTOM_RUSTDESK_HOME_POWERED -->", "")
text = text.replace(" <!-- CUSTOM_RUSTDESK_HOME_HEADER -->", "")
text = re.sub(r"\s*<!-- CUSTOM_RUSTDESK_HOME_LOGO -->", "", text)

changed = False

if wrong_tip in text:
    text = text.replace(wrong_tip, plain_tip, 1)
    changed = True

match = legacy_brand.search(text)
if match:
    if match.group(0) != brand:
        text = legacy_brand.sub(brand, text, count=1)
        changed = True
elif old_header in text:
    text = text.replace(old_header, brand, 1)
    changed = True
elif text_only_brand in text and brand != text_only_brand:
    text = text.replace(text_only_brand, brand, 1)
    changed = True

stripped, n = left_powered_in_brand.subn("", text)
if n:
    text = stripped
    changed = True

if right_with_powered not in text and right_anchor in text:
    text = text.replace(right_anchor, right_with_powered, 1)
    changed = True

if old_click in text:
    text = text.replace(old_click, new_click, 1)
    changed = True

updated_logo_style, n = logo_style_pat.subn(logo_style_new, text)
if n:
    text = updated_logo_style
    changed = True

header_pos = text.find("custom-rd-home-header")
if header_pos != -1:
    header_chunk = text[header_pos : header_pos + 4000]
    if left_powered_in_brand.search(header_chunk):
        raise SystemExit("source-patcher: powered-by must not remain inside left brand header")

card = "<div .card-connect>"
if text.find("#powered-by") == -1 or text.find(card) == -1:
    raise SystemExit("source-patcher: missing powered-by or card-connect anchor")
if text.find("#powered-by") > text.find(card):
    raise SystemExit("source-patcher: powered-by must appear above card-connect")

if "custom-rd-home-header" not in text:
    raise SystemExit("source-patcher: sciter home brand header missing")
if "custom-rd-home-slogan" not in brand and "custom-rd-home-slogan" not in text:
    raise SystemExit("source-patcher: sciter home brand block missing slogan slot")

if not changed and "custom-rd-home-header" not in text:
    raise SystemExit("source-patcher: sciter home UI patch made no changes")

path.write_text(text, encoding="utf-8")
PY
    rm -f "$brand_file"

    if grep -q "custom-rd-home-header" "$index_file" &&
       grep -q "custom-rd-home-title-row" "$index_file" &&
       grep -q "custom-rd-home-slogan" "$index_file" &&
       grep -q "custom-rd-home-powered" "$index_file" &&
       python3 - "$index_file" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
header = text.find("custom-rd-home-header")
card = text.find("<div .card-connect>")
powered = text.find("#powered-by")
if header == -1 or card == -1 or powered == -1:
    raise SystemExit(1)
if powered > card:
    raise SystemExit(2)
if "#powered-by" in text[header : header + 4000]:
    raise SystemExit(3)
if "max-width:48px" not in text:
    raise SystemExit(4)
PY
    then
        if grep -q "custom-rd-home-logo" "$index_file"; then
            echo "source-patcher: sciter home header (48px logo+name+slogan) + powered above card in $index_file"
        else
            echo "source-patcher: sciter home header (name+slogan) + powered above card in $index_file"
        fi
    else
        echo "source-patcher: failed to inject sciter home UI in $index_file" >&2
        return 1
    fi
}
