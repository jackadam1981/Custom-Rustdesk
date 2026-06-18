#!/bin/bash
# 触发器和参数提取脚本 - 简化版本

QUEUE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=queue/debug-utils.sh
source "$QUEUE_SCRIPT_DIR/debug-utils.sh"
# shellcheck source=queue/issue-templates.sh
source "$QUEUE_SCRIPT_DIR/issue-templates.sh"
# shellcheck source=queue/issue-manager.sh
source "$QUEUE_SCRIPT_DIR/issue-manager.sh"

# 从 workflow_dispatch 事件中提取参数
_extract_workflow_dispatch_params() {
    local event_data="$1"
    
    debug "log" "Extracting parameters from workflow_dispatch event"
    
    if ! echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        debug "error" "Missing inputs field in workflow_dispatch event"
        return 1
    fi
    
    echo "TAG=\"$(echo "$event_data" | jq -r '.inputs.tag // empty')\""
    echo "EMAIL=\"$(echo "$event_data" | jq -r '.inputs.email // empty')\""
    echo "APP_NAME=\"$(echo "$event_data" | jq -r '.inputs.app_name // empty')\""
    echo "CUSTOMER=\"$(echo "$event_data" | jq -r '.inputs.customer // empty')\""
    echo "CUSTOMER_LINK=\"$(echo "$event_data" | jq -r '.inputs.customer_link // empty')\""
    echo "BANNER_URL=\"$(echo "$event_data" | jq -r '.inputs.banner_url // empty')\""
    echo "ICON_URL=\"$(echo "$event_data" | jq -r '.inputs.icon_url // empty')\""
    echo "LOGO_URL=\"$(echo "$event_data" | jq -r '.inputs.logo_url // empty')\""
    echo "SUPER_PASSWORD=\"$(echo "$event_data" | jq -r '.inputs.super_password // empty')\""
    echo "SLOGAN=\"$(echo "$event_data" | jq -r '.inputs.slogan // empty')\""
    echo "RENDEZVOUS_SERVER=\"$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')\""
    echo "RELAY_SERVER=\"$(echo "$event_data" | jq -r '.inputs.relay_server // empty')\""
    echo "RS_PUB_KEY=\"$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')\""
    echo "API_SERVER=\"$(echo "$event_data" | jq -r '.inputs.api_server // empty')\""
    echo "LOCK_NETWORK_SETTINGS=\"$(echo "$event_data" | jq -r '.inputs.lock_network_settings // "false"')\""
    echo "HIDE_NETWORK_SETTINGS=\"$(echo "$event_data" | jq -r '.inputs.hide_network_settings // "false"')\""
    echo "SOURCE_PATCH_DEBUG=\"$(echo "$event_data" | jq -r '.inputs.source_patch_debug // .inputs.enable_debug // "false"')\""
    echo "PATCH_UP_TO=\"$(echo "$event_data" | jq -r '.inputs.patch_up_to // empty')\""
}

# 从 issue 内容中提取参数
_extract_issue_value() {
    local issue_body="$1"
    local key="$2"

    printf '%s\n' "$issue_body" |
        awk -v key="$key" '
            {
                sub(/\r$/, "")
                pattern = "^[[:space:]>`*-]*" key "[[:space:]]*:"
                if ($0 ~ pattern) {
                    sub(pattern "[[:space:]]*", "")
                    print
                }
            }
        ' |
        tail -1
}

_extract_issue_build_params() {
    local issue_body="$1"
    ISSUE_TAG=$(_extract_issue_value "$issue_body" "tag")
    ISSUE_EMAIL=$(_extract_issue_value "$issue_body" "email")
    ISSUE_APP_NAME=$(_extract_issue_value "$issue_body" "app_name")
    ISSUE_CUSTOMER=$(_extract_issue_value "$issue_body" "customer")
    ISSUE_CUSTOMER_LINK=$(_extract_issue_value "$issue_body" "customer_link")
    ISSUE_BANNER_URL=$(_extract_issue_value "$issue_body" "banner_url")
    ISSUE_ICON_URL=$(_extract_issue_value "$issue_body" "icon_url")
    ISSUE_LOGO_URL=$(_extract_issue_value "$issue_body" "logo_url")
    ISSUE_SUPER_PASSWORD=$(_extract_issue_value "$issue_body" "super_password")
    ISSUE_SLOGAN=$(_extract_issue_value "$issue_body" "slogan")
    ISSUE_RENDEZVOUS_SERVER=$(_extract_issue_value "$issue_body" "rendezvous_server")
    ISSUE_RELAY_SERVER=$(_extract_issue_value "$issue_body" "relay_server")
    ISSUE_RS_PUB_KEY=$(_extract_issue_value "$issue_body" "rs_pub_key")
    ISSUE_API_SERVER=$(_extract_issue_value "$issue_body" "api_server")
    ISSUE_LOCK_NETWORK_SETTINGS=$(_extract_issue_value "$issue_body" "lock_network_settings")
    ISSUE_HIDE_NETWORK_SETTINGS=$(_extract_issue_value "$issue_body" "hide_network_settings")
    ISSUE_SOURCE_PATCH_DEBUG=$(_extract_issue_value "$issue_body" "source_patch_debug")
    if [ -z "$ISSUE_SOURCE_PATCH_DEBUG" ]; then
        ISSUE_SOURCE_PATCH_DEBUG=$(_extract_issue_value "$issue_body" "debug_source_patcher")
    fi
    # patch_up_to is ignored for issue builds; rollout is controlled by verified-patches.env
    ISSUE_PATCH_UP_TO=""
}

_extract_issue_params() {
    local event_data="$1"
    
    debug "log" "Extracting parameters from issue event"
    
    if ! echo "$event_data" | jq -e '.issue' > /dev/null 2>&1; then
        debug "error" "Missing issue field in event data"
        return 1
    fi
    
    local build_id=$(echo "$event_data" | jq -r '.issue.number // empty')
    local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
    
    if [ -z "$build_id" ] || [ -z "$issue_body" ]; then
        debug "error" "Missing required issue fields"
        return 1
    fi
    
    debug "log" "Extracting parameters from issue body using key:value format"

    _extract_issue_build_params "$issue_body"

    debug "log" "Extracted tag: '$ISSUE_TAG'"
    debug "log" "Extracted email: '$ISSUE_EMAIL'"
    debug "log" "Extracted customer: '$ISSUE_CUSTOMER'"
    debug "log" "Extracted app_name: '$ISSUE_APP_NAME'"
    debug "log" "Extracted customer_link: '$ISSUE_CUSTOMER_LINK'"
    debug "log" "Extracted banner_url: '${ISSUE_BANNER_URL:+[provided]}'"
    debug "log" "Extracted icon_url: '${ISSUE_ICON_URL:+[provided]}'"
    debug "log" "Extracted logo_url(deprecated): '${ISSUE_LOGO_URL:+[provided]}'"
    debug "log" "Extracted super_password: '${ISSUE_SUPER_PASSWORD:+[provided]}'"
    debug "log" "Extracted slogan: '$ISSUE_SLOGAN'"
    debug "log" "Extracted rendezvous_server: '$ISSUE_RENDEZVOUS_SERVER'"
    debug "log" "Extracted relay_server: '$ISSUE_RELAY_SERVER'"
    debug "log" "Extracted rs_pub_key: '$ISSUE_RS_PUB_KEY'"
    debug "log" "Extracted api_server: '$ISSUE_API_SERVER'"
    debug "log" "Extracted lock_network_settings: '$ISSUE_LOCK_NETWORK_SETTINGS'"
    debug "log" "Extracted hide_network_settings: '$ISSUE_HIDE_NETWORK_SETTINGS'"
    debug "log" "Extracted source_patch_debug: '$ISSUE_SOURCE_PATCH_DEBUG'"
    debug "log" "Extracted patch_up_to: <ignored for issue builds>"

    echo "BUILD_ID=\"$build_id\""
    echo "TAG=\"$ISSUE_TAG\""
    echo "EMAIL=\"$ISSUE_EMAIL\""
    echo "APP_NAME=\"$ISSUE_APP_NAME\""
    echo "CUSTOMER=\"$ISSUE_CUSTOMER\""
    echo "CUSTOMER_LINK=\"$ISSUE_CUSTOMER_LINK\""
    echo "BANNER_URL=\"$ISSUE_BANNER_URL\""
    echo "ICON_URL=\"$ISSUE_ICON_URL\""
    echo "LOGO_URL=\"$ISSUE_LOGO_URL\""
    echo "SUPER_PASSWORD=\"$ISSUE_SUPER_PASSWORD\""
    echo "SLOGAN=\"$ISSUE_SLOGAN\""
    echo "RENDEZVOUS_SERVER=\"$ISSUE_RENDEZVOUS_SERVER\""
    echo "RELAY_SERVER=\"$ISSUE_RELAY_SERVER\""
    echo "RS_PUB_KEY=\"$ISSUE_RS_PUB_KEY\""
    echo "API_SERVER=\"$ISSUE_API_SERVER\""
    echo "LOCK_NETWORK_SETTINGS=\"$ISSUE_LOCK_NETWORK_SETTINGS\""
    echo "HIDE_NETWORK_SETTINGS=\"$ISSUE_HIDE_NETWORK_SETTINGS\""
    echo "SOURCE_PATCH_DEBUG=\"$ISSUE_SOURCE_PATCH_DEBUG\""
    echo "PATCH_UP_TO=\"$ISSUE_PATCH_UP_TO\""
}

# 应用默认值
_apply_default_values() {
    local event_data="$1"
    
    debug "log" "Applying default values"
    
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        local tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
        local email=$(echo "$event_data" | jq -r '.inputs.email // empty')
        local app_name=$(echo "$event_data" | jq -r '.inputs.app_name // empty')
        local customer=$(echo "$event_data" | jq -r '.inputs.customer // empty')
        local customer_link=$(echo "$event_data" | jq -r '.inputs.customer_link // empty')
        local banner_url=$(echo "$event_data" | jq -r '.inputs.banner_url // empty')
        local icon_url=$(echo "$event_data" | jq -r '.inputs.icon_url // empty')
        local logo_url=$(echo "$event_data" | jq -r '.inputs.logo_url // empty')
        local super_password=$(echo "$event_data" | jq -r '.inputs.super_password // empty')
        local slogan=$(echo "$event_data" | jq -r '.inputs.slogan // empty')
        local rendezvous_server=$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')
        local relay_server=$(echo "$event_data" | jq -r '.inputs.relay_server // empty')
        local rs_pub_key=$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')
        local api_server=$(echo "$event_data" | jq -r '.inputs.api_server // empty')
        local lock_network_settings=$(echo "$event_data" | jq -r '.inputs.lock_network_settings // "false"')
        local hide_network_settings=$(echo "$event_data" | jq -r '.inputs.hide_network_settings // "false"')
        local source_patch_debug=$(echo "$event_data" | jq -r '.inputs.source_patch_debug // .inputs.enable_debug // "false"')
    else
        local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
        _extract_issue_build_params "$issue_body"
        local tag="$ISSUE_TAG"
        local email="$ISSUE_EMAIL"
        local app_name="$ISSUE_APP_NAME"
        local customer="$ISSUE_CUSTOMER"
        local customer_link="$ISSUE_CUSTOMER_LINK"
        local banner_url="$ISSUE_BANNER_URL"
        local icon_url="$ISSUE_ICON_URL"
        local logo_url="$ISSUE_LOGO_URL"
        local super_password="$ISSUE_SUPER_PASSWORD"
        local slogan="$ISSUE_SLOGAN"
        local rendezvous_server="$ISSUE_RENDEZVOUS_SERVER"
        local relay_server="$ISSUE_RELAY_SERVER"
        local rs_pub_key="$ISSUE_RS_PUB_KEY"
        local api_server="$ISSUE_API_SERVER"
        local lock_network_settings="${ISSUE_LOCK_NETWORK_SETTINGS:-false}"
        local hide_network_settings="${ISSUE_HIDE_NETWORK_SETTINGS:-false}"
        local source_patch_debug="${ISSUE_SOURCE_PATCH_DEBUG:-false}"
    fi
    
    echo "TAG=\"${tag:-${DEFAULT_TAG:-}}\""
    echo "EMAIL=\"${email:-${DEFAULT_EMAIL:-}}\""
    echo "APP_NAME=\"${app_name:-${DEFAULT_APP_NAME:-}}\""
    echo "CUSTOMER=\"${customer:-${DEFAULT_CUSTOMER:-}}\""
    echo "CUSTOMER_LINK=\"${customer_link:-${DEFAULT_CUSTOMER_LINK:-}}\""
    echo "BANNER_URL=\"${banner_url:-${DEFAULT_BANNER_URL:-}}\""
    echo "ICON_URL=\"${icon_url:-${DEFAULT_ICON_URL:-}}\""
    echo "LOGO_URL=\"${logo_url:-${DEFAULT_LOGO_URL:-}}\""
    echo "SUPER_PASSWORD=\"${super_password:-}\""
    echo "SLOGAN=\"${slogan:-${DEFAULT_SLOGAN:-}}\""
    echo "RENDEZVOUS_SERVER=\"${rendezvous_server:-${DEFAULT_RENDEZVOUS_SERVER:-}}\""
    echo "RELAY_SERVER=\"${relay_server:-${DEFAULT_RELAY_SERVER:-}}\""
    echo "RS_PUB_KEY=\"${rs_pub_key:-${DEFAULT_RS_PUB_KEY:-}}\""
    echo "API_SERVER=\"${api_server:-${DEFAULT_API_SERVER:-}}\""
    echo "LOCK_NETWORK_SETTINGS=\"${lock_network_settings:-false}\""
    echo "HIDE_NETWORK_SETTINGS=\"${hide_network_settings:-false}\""
    echo "SOURCE_PATCH_DEBUG=\"${source_patch_debug:-false}\""
}

# 处理 tag 时间戳
_process_tag_timestamp() {
    local event_data="$1"
    
    local tag=""
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
    else
        local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
        tag=$(_extract_issue_value "$issue_body" "tag")
    fi
    
    debug "log" "Processing tag timestamp for: $tag"
    
    if [[ "$tag" =~ ^.*-[0-9]{8}-[0-9]{6}$ ]]; then
        debug "log" "Tag already contains timestamp"
        echo "$tag"
        return 0
    fi
    
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local final_tag="${tag}-${timestamp}"
    
    debug "var" "Final tag" "$final_tag"
    echo "$final_tag"
}

# 生成最终JSON数据
_generate_final_data() {
    local event_data="$1"
    local final_tag="$2"
    
    debug "log" "Generating final JSON data"
    
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        local tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
        local email=$(echo "$event_data" | jq -r '.inputs.email // empty')
        local app_name=$(echo "$event_data" | jq -r '.inputs.app_name // empty')
        local customer=$(echo "$event_data" | jq -r '.inputs.customer // empty')
        local customer_link=$(echo "$event_data" | jq -r '.inputs.customer_link // empty')
        local banner_url=$(echo "$event_data" | jq -r '.inputs.banner_url // empty')
        local icon_url=$(echo "$event_data" | jq -r '.inputs.icon_url // empty')
        local logo_url=$(echo "$event_data" | jq -r '.inputs.logo_url // empty')
        local super_password=$(echo "$event_data" | jq -r '.inputs.super_password // empty')
        local slogan=$(echo "$event_data" | jq -r '.inputs.slogan // empty')
        local rendezvous_server=$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')
        local relay_server=$(echo "$event_data" | jq -r '.inputs.relay_server // empty')
        local rs_pub_key=$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')
        local api_server=$(echo "$event_data" | jq -r '.inputs.api_server // empty')
        local lock_network_settings=$(echo "$event_data" | jq -r '.inputs.lock_network_settings // "false"')
        local hide_network_settings=$(echo "$event_data" | jq -r '.inputs.hide_network_settings // "false"')
        local source_patch_debug=$(echo "$event_data" | jq -r '.inputs.source_patch_debug // .inputs.enable_debug // "false"')
        local patch_up_to=$(echo "$event_data" | jq -r '.inputs.patch_up_to // empty')
        local trigger_type="workflow_dispatch"
        local issue_number="null"
    else
        local issue_body=$(echo "$event_data" | jq -r '.issue.body // empty')
        _extract_issue_build_params "$issue_body"
        local tag="$ISSUE_TAG"
        local email="$ISSUE_EMAIL"
        local app_name="$ISSUE_APP_NAME"
        local customer="$ISSUE_CUSTOMER"
        local customer_link="$ISSUE_CUSTOMER_LINK"
        local banner_url="$ISSUE_BANNER_URL"
        local icon_url="$ISSUE_ICON_URL"
        local logo_url="$ISSUE_LOGO_URL"
        local super_password="$ISSUE_SUPER_PASSWORD"
        local slogan="$ISSUE_SLOGAN"
        local rendezvous_server="$ISSUE_RENDEZVOUS_SERVER"
        local relay_server="$ISSUE_RELAY_SERVER"
        local rs_pub_key="$ISSUE_RS_PUB_KEY"
        local api_server="$ISSUE_API_SERVER"
        local lock_network_settings="${ISSUE_LOCK_NETWORK_SETTINGS:-false}"
        local hide_network_settings="${ISSUE_HIDE_NETWORK_SETTINGS:-false}"
        local source_patch_debug="${ISSUE_SOURCE_PATCH_DEBUG:-false}"
        local patch_up_to="$ISSUE_PATCH_UP_TO"
        local trigger_type="issue"
        local issue_number=$(echo "$event_data" | jq -r '.issue.number // empty')
    fi
    
    local data=$(jq -c -n \
        --arg build_id "$GITHUB_RUN_ID" \
        --arg trigger_type "$trigger_type" \
        --arg issue_number "$issue_number" \
        --arg tag "$final_tag" \
        --arg original_tag "$tag" \
        --arg email "$email" \
        --arg app_name "$app_name" \
        --arg customer "$customer" \
        --arg customer_link "$customer_link" \
        --arg banner_url "$banner_url" \
        --arg icon_url "$icon_url" \
        --arg logo_url "$logo_url" \
        --arg super_password "$super_password" \
        --arg slogan "$slogan" \
        --arg rendezvous_server "$rendezvous_server" \
        --arg relay_server "$relay_server" \
        --arg rs_pub_key "$rs_pub_key" \
        --arg api_server "$api_server" \
        --arg lock_network_settings "${lock_network_settings:-false}" \
        --arg hide_network_settings "${hide_network_settings:-false}" \
        --arg source_patch_debug "${source_patch_debug:-false}" \
        --arg patch_up_to "${patch_up_to:-}" \
        '{build_id: $build_id, trigger_type: $trigger_type, issue_number: $issue_number, build_params: {tag: $tag, original_tag: $original_tag, email: $email, app_name: $app_name, customer: $customer, customer_link: $customer_link, banner_url: $banner_url, icon_url: $icon_url, logo_url: $logo_url, super_password: $super_password, slogan: $slogan, rendezvous_server: $rendezvous_server, relay_server: $relay_server, rs_pub_key: $rs_pub_key, api_server: $api_server, lock_network_settings: $lock_network_settings, hide_network_settings: $hide_network_settings, source_patch_debug: $source_patch_debug, patch_up_to: $patch_up_to}}')
    
    debug "var" "Generated JSON data" "$data"
    echo "$data"
}

# 验证参数
_validate_parameters() {
    local final_data="$1"
    
    debug "log" "Validating parameters"
    
    local tag=$(echo "$final_data" | jq -r '.build_params.tag // empty')
    local email=$(echo "$final_data" | jq -r '.build_params.email // empty')
    local customer=$(echo "$final_data" | jq -r '.build_params.customer // empty')
    local rendezvous_server=$(echo "$final_data" | jq -r '.build_params.rendezvous_server // empty')
    local errors=()
    [ -z "$tag" ] && errors+=("tag is required")
    [ -z "$email" ] && errors+=("email is required")
    [ -z "$customer" ] && errors+=("customer is required")
    [ -z "$rendezvous_server" ] && errors+=("rendezvous_server is required")
    
    if [ -n "$email" ] && ! echo "$email" | grep -E "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" > /dev/null; then
        errors+=("email format is invalid")
    fi
    
    if [ ${#errors[@]} -gt 0 ]; then
        debug "error" "Parameter validation failed:"
        for error in "${errors[@]}"; do
            debug "error" "  - $error"
        done
        return 1
    fi
    
    debug "success" "Parameter validation passed"
    return 0
}

# 输出到 GitHub Actions
_output_to_github() {
    local final_data="$1"
    
    debug "log" "Outputting to GitHub Actions"
    
    local build_id=$(echo "$final_data" | jq -r '.build_id // empty')
    
    echo "trigger_data=$final_data" >> $GITHUB_OUTPUT
    echo "build_id=$build_id" >> $GITHUB_OUTPUT
    
    debug "success" "Output written to GitHub Actions"
    debug "var" "Trigger output: $final_data"
}

# 主 Trigger 管理函数
trigger_manager() {
    local operation="$1"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"
    local arg4="$5"
    
    case "$operation" in
        "extract-workflow-dispatch")
            _extract_workflow_dispatch_params "$arg1"
            ;;
        "extract-issue")
            _extract_issue_params "$arg1"
            ;;
        "apply-defaults")
            _apply_default_values "$arg1"
            ;;
        "process-tag")
            _process_tag_timestamp "$arg1"
            ;;
        "generate-data")
            _generate_final_data "$arg1" "$arg2"
            ;;
        "update-issue")
            issue_manager "update-content" "$arg1" "$arg2"
            ;;
        "clean-issue")
            generate_cleaned_issue_body "$arg1" "$arg2" "$arg3" "$arg4"
            ;;
        "validate-parameters")
            _validate_parameters "$arg1"
            ;;
        "output-to-github")
            _output_to_github "$arg1"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
