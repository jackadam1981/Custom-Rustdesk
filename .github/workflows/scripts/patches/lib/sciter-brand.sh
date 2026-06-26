_custom_sciter_logo_img_markup() {
    if [ ! -f "res/logo.png" ]; then
        return 0
    fi

    python3 - "res/logo.png" <<'PY'
import base64
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = base64.b64encode(path.read_bytes()).decode("ascii")
print(
    '<img.custom-rd-home-logo src="data:image/png;base64,' + data + '" '
    'style="max-width:48px;max-height:48px;width:48px;height:48px;vertical-align:middle" />'
)
PY
}

_custom_sciter_home_slogan_markup() {
    printf '%s' '{handler.get_builtin_option("custom-slogan") && handler.get_builtin_option("custom-slogan").length ? <div .custom-rd-home-slogan style="margin-top:0.2em;opacity:0.85">{handler.get_builtin_option("custom-slogan")}</div> : ""}'
}

_custom_sciter_custom_brand_block() {
    local logo_markup=""
    local slogan_markup=""

    slogan_markup=$(_custom_sciter_home_slogan_markup)

    if [ -f "res/logo.png" ]; then
        logo_markup=$(_custom_sciter_logo_img_markup)
    fi

    if [ -n "$logo_markup" ]; then
        printf '%s' "{is_custom_client ? <div #custom-brand.custom-rd-home-header style=\"text-align:center;margin-bottom:0.35em\"><div .custom-rd-home-title-row style=\"flow:horizontal;horizontal-align:center;vertical-align:middle\">${logo_markup}<div .title style=\"font-weight:bold;display:inline-block;vertical-align:middle;margin-left:0.35em\">{handler.get_builtin_option(\"app-name\") || handler.get_builtin_option(\"custom-customer-name\")}</div></div>${slogan_markup}</div> : \"\"}"
    else
        printf '%s' "{is_custom_client ? <div #custom-brand.custom-rd-home-header style=\"text-align:center;margin-bottom:0.35em\"><div .title style=\"font-weight:bold\">{handler.get_builtin_option(\"app-name\") || handler.get_builtin_option(\"custom-customer-name\")}</div>${slogan_markup}</div> : \"\"}"
    fi
}
