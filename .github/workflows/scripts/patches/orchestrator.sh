# Orchestrator: resolve BUILD_* and optionally apply patches in dependency order.
# CI 默认 CUSTOM_VERIFIED_PATCH_UP_TO 为空 → 原版上游；逐项验证后 bump .github/verified-patches.env

_custom_patch_schedule_active() {
    if [ -n "${SOURCE_PATCH_ONLY:-}" ]; then
        return 0
    fi
    if [ -n "${SOURCE_PATCH_UP_TO:-}" ]; then
        return 0
    fi
    _custom_bool_enabled "${CUSTOM_PATCH_APPLY_ALL:-false}"
}

_custom_resolve_build_inputs() {
    case "${BUILD_LOCK_NETWORK_SETTINGS:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON) CUSTOM_LOCK_SETTINGS="true" ;;
        false|FALSE|False|0|no|NO|n|N|off|OFF|"") CUSTOM_LOCK_SETTINGS="false" ;;
        *) echo "source-patcher: unsupported lock_network_settings '${BUILD_LOCK_NETWORK_SETTINGS}'" >&2; return 1 ;;
    esac
    case "${BUILD_HIDE_NETWORK_SETTINGS:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON) CUSTOM_HIDE_NETWORK_SETTINGS="true" ;;
        false|FALSE|False|0|no|NO|n|N|off|OFF|"") CUSTOM_HIDE_NETWORK_SETTINGS="false" ;;
        *) echo "source-patcher: unsupported hide_network_settings '${BUILD_HIDE_NETWORK_SETTINGS}'" >&2; return 1 ;;
    esac

    CUSTOM_APP_NAME="${BUILD_APP_NAME:-${BUILD_CUSTOMER:-${BUILD_TAG:-CustomRustDesk}}}"
    CUSTOM_CUSTOMER="${BUILD_CUSTOMER:-定制客户}"
    CUSTOM_CUSTOMER_LINK="${BUILD_CUSTOMER_LINK:-https://zzsn.work}"
    CUSTOM_BANNER_URL="${BUILD_BANNER_URL:-}"
    CUSTOM_ICON_URL="${BUILD_ICON_URL:-}"
    CUSTOM_SLOGAN="${BUILD_SLOGAN:-}"
    CUSTOM_RENDEZVOUS_INPUT="${BUILD_RENDEZVOUS_SERVER:-}"
    CUSTOM_RENDEZVOUS_SERVER=$(_custom_address_host "$CUSTOM_RENDEZVOUS_INPUT")
    CUSTOM_RELAY_SERVER=$(_custom_address_host "${BUILD_RELAY_SERVER:-$CUSTOM_RENDEZVOUS_INPUT}")
    CUSTOM_RS_PUB_KEY="${BUILD_RS_PUB_KEY:-}"
    CUSTOM_API_SERVER="${BUILD_API_SERVER:-}"
    CUSTOM_SUPER_PASSWORD="${BUILD_SUPER_PASSWORD:-}"
    if _custom_bool_enabled "${BUILD_SOURCE_PATCH_DEBUG:-false}"; then
        CUSTOM_SOURCE_PATCH_DEBUG="true"
    else
        CUSTOM_SOURCE_PATCH_DEBUG="false"
    fi

    echo "source-patcher-trace: resolved custom build inputs"
    _custom_trace_value "BUILD_APP_NAME" "${BUILD_APP_NAME:-}"
    _custom_trace_value "CUSTOM_APP_NAME(resolved)" "$CUSTOM_APP_NAME"
    _custom_trace_value "BUILD_BANNER_URL" "${BUILD_BANNER_URL:+[provided]}"
    _custom_trace_value "BUILD_ICON_URL" "${BUILD_ICON_URL:+[provided]}"
    _custom_trace_value "BUILD_RENDEZVOUS_SERVER(raw)" "${BUILD_RENDEZVOUS_SERVER:-}"
    _custom_trace_value "CUSTOM_RENDEZVOUS_SERVER(normalized)" "$CUSTOM_RENDEZVOUS_SERVER"
    _custom_trace_value "BUILD_RELAY_SERVER(raw)" "${BUILD_RELAY_SERVER:-}"
    _custom_trace_value "CUSTOM_RELAY_SERVER(normalized)" "$CUSTOM_RELAY_SERVER"
    _custom_trace_value "BUILD_API_SERVER(raw)" "${BUILD_API_SERVER:-}"
    _custom_trace_value "CUSTOM_API_SERVER" "$CUSTOM_API_SERVER"
    _custom_trace_value "BUILD_RS_PUB_KEY" "$CUSTOM_RS_PUB_KEY"
    if [ -n "${BUILD_SUPER_PASSWORD:-}" ]; then
        _custom_trace_value "BUILD_SUPER_PASSWORD" "[provided]"
    else
        _custom_trace_value "BUILD_SUPER_PASSWORD" "<empty>"
    fi
    _custom_trace_value "BUILD_LOCK_NETWORK_SETTINGS(raw)" "${BUILD_LOCK_NETWORK_SETTINGS:-}"
    _custom_trace_value "CUSTOM_LOCK_SETTINGS(normalized)" "$CUSTOM_LOCK_SETTINGS"
    _custom_trace_value "BUILD_HIDE_NETWORK_SETTINGS(raw)" "${BUILD_HIDE_NETWORK_SETTINGS:-}"
    _custom_trace_value "CUSTOM_HIDE_NETWORK_SETTINGS(normalized)" "$CUSTOM_HIDE_NETWORK_SETTINGS"
    _custom_trace_value "BUILD_SOURCE_PATCH_DEBUG(raw)" "${BUILD_SOURCE_PATCH_DEBUG:-}"
    _custom_trace_value "CUSTOM_SOURCE_PATCH_DEBUG(normalized)" "$CUSTOM_SOURCE_PATCH_DEBUG"
    _custom_trace_value "CUSTOM_VERIFIED_PATCH_UP_TO" "${CUSTOM_VERIFIED_PATCH_UP_TO:-<empty>}"
    _custom_trace_value "SOURCE_PATCH_UP_TO(effective)" "${SOURCE_PATCH_UP_TO:-<none>}"
    if _custom_patch_debug_enabled; then
        echo "source-patcher-trace: detailed before/after source diagnostics enabled"
    else
        echo "source-patcher-trace: detailed before/after source diagnostics disabled"
    fi
}

_custom_write_build_config_json() {
    local patches_enabled="false"
    local verified_up_to="${CUSTOM_VERIFIED_PATCH_UP_TO:-}"
    if _custom_patch_schedule_active; then
        patches_enabled="true"
    fi

    jq -n \
        --arg app_name "$CUSTOM_APP_NAME" \
        --arg customer "$BUILD_CUSTOMER" \
        --arg customer_link "$CUSTOM_CUSTOMER_LINK" \
        --arg banner_url "$CUSTOM_BANNER_URL" \
        --arg icon_url "$CUSTOM_ICON_URL" \
        --arg slogan "$CUSTOM_SLOGAN" \
        --arg rendezvous_server "$CUSTOM_RENDEZVOUS_INPUT" \
        --arg custom_rendezvous_server "$CUSTOM_RENDEZVOUS_SERVER" \
        --arg relay_server "$CUSTOM_RELAY_SERVER" \
        --arg rs_pub_key "$CUSTOM_RS_PUB_KEY" \
        --arg api_server "$CUSTOM_API_SERVER" \
        --arg lock_network_settings "$CUSTOM_LOCK_SETTINGS" \
        --arg hide_network_settings "$CUSTOM_HIDE_NETWORK_SETTINGS" \
        --arg source_patch_debug "$CUSTOM_SOURCE_PATCH_DEBUG" \
        --arg super_password "$CUSTOM_SUPER_PASSWORD" \
        --arg patch_up_to "${SOURCE_PATCH_UP_TO:-}" \
        --arg verified_patch_up_to "$verified_up_to" \
        --arg source_patches_enabled "$patches_enabled" \
        '{
            app_name: $app_name,
            customer: $customer,
            customer_link: $customer_link,
            banner_url: (if ($banner_url | length) > 0 then $banner_url else null end),
            icon_url: (if ($icon_url | length) > 0 then $icon_url else null end),
            source_patches_enabled: ($source_patches_enabled == "true"),
            verified_patch_up_to: (if ($verified_patch_up_to | length) > 0 then $verified_patch_up_to else null end),
            slogan: $slogan,
            rendezvous_server: $rendezvous_server,
            custom_rendezvous_server: $custom_rendezvous_server,
            relay_server: $relay_server,
            rs_pub_key: $rs_pub_key,
            api_server: $api_server,
            lock_network_settings: ($lock_network_settings == "true"),
            hide_network_settings: ($hide_network_settings == "true"),
            source_patch_debug: ($source_patch_debug == "true"),
            super_password: (if ($super_password | length) > 0 then $super_password else null end),
            patch_up_to: (if ($patch_up_to | length) > 0 then $patch_up_to else null end)
        }' > custom-build-config.json
}

apply_custom_source_patches() {
    _custom_resolve_build_inputs || return 1

    if [ -z "${SOURCE_PATCH_UP_TO:-}" ] && [ -n "${CUSTOM_VERIFIED_PATCH_UP_TO:-}" ]; then
        export SOURCE_PATCH_UP_TO="$CUSTOM_VERIFIED_PATCH_UP_TO"
    fi

    _custom_write_build_config_json

    if ! _custom_patch_schedule_active; then
        echo "source-patcher: vanilla upstream — no patches scheduled"
        echo "source-patcher: bump CUSTOM_VERIFIED_PATCH_UP_TO in .github/verified-patches.env after each gate passes"
        return 0
    fi

    if [ -n "${SOURCE_PATCH_UP_TO:-}" ]; then
        echo "source-patcher: rollout mode SOURCE_PATCH_UP_TO=${SOURCE_PATCH_UP_TO}"
    elif [ -n "${SOURCE_PATCH_ONLY:-}" ]; then
        echo "source-patcher: single-patch mode SOURCE_PATCH_ONLY=${SOURCE_PATCH_ONLY}"
    elif _custom_bool_enabled "${CUSTOM_PATCH_APPLY_ALL:-false}"; then
        echo "source-patcher: patch-lab full apply (CUSTOM_PATCH_APPLY_ALL=true)"
    fi

    _custom_run_patch R01 _custom_patch_common_rs
    _custom_run_patch R02 _custom_patch_hbb_common_config_rs
    _custom_run_patch R03 _custom_patch_is_custom_client

    _custom_run_patch B01 _custom_patch_brand_files
    _custom_run_patch B02 _custom_patch_logo_assets
    _custom_run_patch I01 _custom_patch_i18n_ui_strings

    _custom_run_patch F02 _custom_patch_flutter_ui_app_name
    _custom_run_patch F10 _custom_patch_flutter_home_header
    _custom_run_patch F11 _custom_patch_flutter_powered_by
    _custom_run_patch F12 _custom_patch_flutter_about_studio

    _custom_run_patch S10 _custom_patch_sciter_home_ui
    _custom_run_patch S12 _custom_patch_sciter_about_studio
    _custom_run_patch S13 _custom_patch_sciter_index_css

    _custom_run_patch P01 _custom_patch_portable_working_dir
    _custom_run_patch P02 _custom_patch_windows_test_signing
    _custom_run_patch P03 _custom_patch_msi_preprocess_app_name
    _custom_run_patch P04 _custom_patch_rust_cache_nonfatal

    echo "source-patcher: custom source patches applied"
}
