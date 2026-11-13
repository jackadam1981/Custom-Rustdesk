_custom_sciter_logo_img_markup() {
    if [ ! -f "res/logo.png" ]; then
        return 0
    fi

    # 501 probe: reuse upstream get_icon() data URI (no CUSTOM_RUSTDESK_HOME_LOGO_SRC in ui.rs).
    printf '%s' \
        '<img.custom-rd-home-logo src={handler.get_icon()} style="max-width:48px;max-height:48px;width:48px;height:48px;vertical-align:middle" /> <!-- CUSTOM_RUSTDESK_SCITER_HOME_LOGO --> <!-- CUSTOM_RUSTDESK_501_ICON_PROBE -->'
}

_custom_sciter_home_title_markup() {
    printf '%s' '<div .title style="font-weight:bold;display:inline-block;vertical-align:middle;margin-left:0.35em">{handler.get_builtin_option("app-name") || handler.get_builtin_option("custom-customer-name")}</div> <!-- CUSTOM_RUSTDESK_SCITER_HOME_TITLE -->'
}

_custom_sciter_home_slogan_markup() {
    printf '%s' '{handler.get_builtin_option("custom-slogan") && handler.get_builtin_option("custom-slogan").length ? <div .custom-rd-home-slogan style="margin-top:0.2em;opacity:0.85">{handler.get_builtin_option("custom-slogan")}</div> : ""} <!-- CUSTOM_RUSTDESK_SCITER_HOME_SLOGAN -->'
}
