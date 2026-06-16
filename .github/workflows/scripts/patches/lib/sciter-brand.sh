_custom_sciter_logo_img_markup() {
    if [ ! -f "res/icon.png" ]; then
        return 0
    fi

    python3 - <<'PY'
import base64
from pathlib import Path

data = base64.b64encode(Path("res/icon.png").read_bytes()).decode("ascii")
print(
    '<img.custom-rd-home-logo src="data:image/png;base64,' + data + '" '
    'style="width:1.4em;height:1.4em;vertical-align:middle" />'
)
PY
}

_custom_sciter_slogan_markup() {
    printf '%s' '{handler.get_builtin_option("custom-slogan") && handler.get_builtin_option("custom-slogan").length ? <div style="font-size:0.85em;margin-top:0.15em">{handler.get_builtin_option("custom-slogan")}</div> : ""}'
}

_custom_sciter_custom_brand_block() {
    local logo_markup=""
    local slogan_markup
    slogan_markup=$(_custom_sciter_slogan_markup)

    if [ -f "res/icon.png" ]; then
        logo_markup=$(_custom_sciter_logo_img_markup)
    fi

    if [ -n "$logo_markup" ]; then
        printf '%s' "{is_custom_client ? <div #custom-brand.custom-rd-home-header style=\"text-align:center;margin-bottom:0.35em\"><div .custom-rd-home-title-row style=\"flow:horizontal;horizontal-align:center;vertical-align:middle\">${logo_markup}<div .title style=\"font-weight:bold;display:inline-block;vertical-align:middle;margin-left:0.35em\">{handler.get_builtin_option(\"app-name\") || handler.get_builtin_option(\"custom-customer-name\")}</div></div>${slogan_markup}</div> : \"\"}"
    else
        printf '%s' "{is_custom_client ? <div #custom-brand.custom-rd-home-header style=\"text-align:center;margin-bottom:0.35em\"><div .title style=\"font-weight:bold\">{handler.get_builtin_option(\"app-name\") || handler.get_builtin_option(\"custom-customer-name\")}</div>${slogan_markup}</div> : \"\"}"
    fi
}
