_custom_sciter_logo_img_markup() {
    local logo_file=""
    if [ -f "res/logo.png" ]; then
        logo_file="res/logo.png"
    elif [ -f "res/icon.png" ]; then
        logo_file="res/icon.png"
    else
        return 0
    fi

    if [ "$logo_file" = "res/logo.png" ]; then
        python3 - "$logo_file" <<'PY'
import base64
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = base64.b64encode(path.read_bytes()).decode("ascii")
print(
    '<img.custom-rd-home-logo src="data:image/png;base64,' + data + '" '
    'style="max-width:300px;max-height:60px;vertical-align:middle" />'
)
PY
    else
        python3 - "$logo_file" <<'PY'
import base64
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = base64.b64encode(path.read_bytes()).decode("ascii")
print(
    '<img.custom-rd-home-logo src="data:image/png;base64,' + data + '" '
    'style="width:1.4em;height:1.4em;vertical-align:middle" />'
)
PY
    fi
}

_custom_sciter_custom_brand_block() {
    local logo_markup=""

    if [ -f "res/logo.png" ] || [ -f "res/icon.png" ]; then
        logo_markup=$(_custom_sciter_logo_img_markup)
    fi

    if [ -n "$logo_markup" ]; then
        printf '%s' "{is_custom_client ? <div #custom-brand.custom-rd-home-header style=\"text-align:center;margin-bottom:0.35em\"><div .custom-rd-home-title-row style=\"flow:horizontal;horizontal-align:center;vertical-align:middle\">${logo_markup}<div .title style=\"font-weight:bold;display:inline-block;vertical-align:middle;margin-left:0.35em\">{handler.get_builtin_option(\"app-name\") || handler.get_builtin_option(\"custom-customer-name\")}</div></div></div> : \"\"}"
    else
        printf '%s' "{is_custom_client ? <div #custom-brand.custom-rd-home-header style=\"text-align:center;margin-bottom:0.35em\"><div .title style=\"font-weight:bold\">{handler.get_builtin_option(\"app-name\") || handler.get_builtin_option(\"custom-customer-name\")}</div></div> : \"\"}"
    fi
}
