# S13 — Sciter Powered-by（连接卡片上方，依赖 S10–S12 左栏不含 powered）
_custom_patch_sciter_powered_by() {
    local index_file="src/ui/index.tis"

    if [ ! -f "$index_file" ]; then
        return 0
    fi

    python3 - "$index_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
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
left_powered_in_brand = re.compile(
    r"\{is_custom_client && handler\.get_builtin_option\(\"hide-powered-by-me\"\) != \"Y\" "
    r"\? <div \.link(?: \.custom-rd-home-powered)? #powered-by(?: \.title)? style=\"[^\"]*\">"
    r"\{translate\('powered_by_me'\)\}</div> : \"\"\}"
)

text = text.replace(" <!-- CUSTOM_RUSTDESK_HOME_POWERED -->", "")

changed = False
if wrong_tip in text:
    text = text.replace(wrong_tip, plain_tip, 1)
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

header_pos = text.find("custom-rd-home-header")
if header_pos != -1:
    header_chunk = text[header_pos : header_pos + 4000]
    if left_powered_in_brand.search(header_chunk):
        raise SystemExit("source-patcher: S13 powered-by must not remain inside left brand header")

card = "<div .card-connect>"
if text.find("#powered-by") == -1 or text.find(card) == -1:
    raise SystemExit("source-patcher: S13 missing powered-by or card-connect anchor")
if text.find("#powered-by") > text.find(card):
    raise SystemExit("source-patcher: S13 powered-by must appear above card-connect")

if "custom-rd-home-powered" not in text and not changed:
    raise SystemExit("source-patcher: S13 powered-by patch made no changes")

path.write_text(text, encoding="utf-8")
PY

    if grep -q "custom-rd-home-powered" "$index_file" &&
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
PY
    then
        echo "source-patcher: S13 powered-by above card-connect in $index_file"
    else
        echo "source-patcher: failed to inject S13 powered-by in $index_file" >&2
        return 1
    fi
}
