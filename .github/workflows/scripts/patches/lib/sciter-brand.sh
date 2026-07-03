_custom_sciter_logo_src_function() {
    if [ ! -f "res/logo.png" ]; then
        return 0
    fi

    python3 - "res/logo.png" <<'PY'
import base64
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = base64.b64encode(path.read_bytes()).decode("ascii")
chunk_size = 120
chunks = [data[i : i + chunk_size] for i in range(0, len(data), chunk_size)]
joined = "\n        + ".join(f'"{chunk}"' for chunk in chunks)
print(
    "function customHomeLogoSrc() {\n"
    '    return "data:image/png;base64," + '
    f"{joined};\n"
    "} <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO_SRC -->"
)
PY
}

_custom_sciter_logo_img_markup() {
    if [ ! -f "res/logo.png" ]; then
        return 0
    fi

    printf '%s' \
        '<img.custom-rd-home-logo src={customHomeLogoSrc()} style="max-width:48px;max-height:48px;width:48px;height:48px;vertical-align:middle" /> <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO -->'
}

_custom_sciter_home_title_markup() {
    printf '%s' '<div .title style="font-weight:bold;display:inline-block;vertical-align:middle;margin-left:0.35em">{handler.get_builtin_option("app-name") || handler.get_builtin_option("custom-customer-name")}</div> <!-- CUSTOM_RUSTDESK_SCITER_HOME_TITLE -->'
}

_custom_sciter_home_slogan_markup() {
    printf '%s' '{handler.get_builtin_option("custom-slogan") && handler.get_builtin_option("custom-slogan").length ? <div .custom-rd-home-slogan style="margin-top:0.2em;opacity:0.85">{handler.get_builtin_option("custom-slogan")}</div> : ""} <!-- CUSTOM_RUSTDESK_SCITER_HOME_SLOGAN -->'
}
