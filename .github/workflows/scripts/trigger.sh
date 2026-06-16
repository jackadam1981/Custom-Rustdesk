#!/bin/bash
# 触发器和参数提取脚本 - 简化版本

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

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
    
    # 从Issue内容中提取参数（key: value格式）
    debug "log" "Extracting parameters from issue body using key:value format"
    debug "log" "Raw issue body: '$issue_body'"

    local tag=$(_extract_issue_value "$issue_body" "tag")
    debug "log" "Extracted tag: '$tag'"

    local email=$(_extract_issue_value "$issue_body" "email")
    debug "log" "Extracted email: '$email'"

    local customer=$(_extract_issue_value "$issue_body" "customer")
    debug "log" "Extracted customer: '$customer'"

    local app_name=$(_extract_issue_value "$issue_body" "app_name")
    debug "log" "Extracted app_name: '$app_name'"

    local customer_link=$(_extract_issue_value "$issue_body" "customer_link")
    debug "log" "Extracted customer_link: '$customer_link'"

    local banner_url=$(_extract_issue_value "$issue_body" "banner_url")
    debug "log" "Extracted banner_url: '${banner_url:+[provided]}'"

    local icon_url=$(_extract_issue_value "$issue_body" "icon_url")
    debug "log" "Extracted icon_url: '${icon_url:+[provided]}'"

    local logo_url=$(_extract_issue_value "$issue_body" "logo_url")
    debug "log" "Extracted logo_url(deprecated): '${logo_url:+[provided]}'"

    local super_password=$(_extract_issue_value "$issue_body" "super_password")
    debug "log" "Extracted super_password: '$super_password'"

    local slogan=$(_extract_issue_value "$issue_body" "slogan")
    debug "log" "Extracted slogan: '$slogan'"

    local rendezvous_server=$(_extract_issue_value "$issue_body" "rendezvous_server")
    debug "log" "Extracted rendezvous_server: '$rendezvous_server'"

    local relay_server=$(_extract_issue_value "$issue_body" "relay_server")
    debug "log" "Extracted relay_server: '$relay_server'"

    local rs_pub_key=$(_extract_issue_value "$issue_body" "rs_pub_key")
    debug "log" "Extracted rs_pub_key: '$rs_pub_key'"

    local api_server=$(_extract_issue_value "$issue_body" "api_server")
    debug "log" "Extracted api_server: '$api_server'"
    local lock_network_settings=$(_extract_issue_value "$issue_body" "lock_network_settings")
    debug "log" "Extracted lock_network_settings: '$lock_network_settings'"
    local hide_network_settings=$(_extract_issue_value "$issue_body" "hide_network_settings")
    debug "log" "Extracted hide_network_settings: '$hide_network_settings'"
    local source_patch_debug=$(_extract_issue_value "$issue_body" "source_patch_debug")
    if [ -z "$source_patch_debug" ]; then
        source_patch_debug=$(_extract_issue_value "$issue_body" "debug_source_patcher")
    fi
    debug "log" "Extracted source_patch_debug: '$source_patch_debug'"
    local patch_up_to=$(_extract_issue_value "$issue_body" "patch_up_to")
    debug "log" "Extracted patch_up_to: '$patch_up_to'"
    
    echo "BUILD_ID=\"$build_id\""
    echo "TAG=\"$tag\""
    echo "EMAIL=\"$email\""
    echo "APP_NAME=\"$app_name\""
    echo "CUSTOMER=\"$customer\""
    echo "CUSTOMER_LINK=\"$customer_link\""
    echo "BANNER_URL=\"$banner_url\""
    echo "ICON_URL=\"$icon_url\""
    echo "LOGO_URL=\"$logo_url\""
    echo "SUPER_PASSWORD=\"$super_password\""
    echo "SLOGAN=\"$slogan\""
    echo "RENDEZVOUS_SERVER=\"$rendezvous_server\""
    echo "RELAY_SERVER=\"$relay_server\""
    echo "RS_PUB_KEY=\"$rs_pub_key\""
    echo "API_SERVER=\"$api_server\""
    echo "LOCK_NETWORK_SETTINGS=\"$lock_network_settings\""
    echo "HIDE_NETWORK_SETTINGS=\"$hide_network_settings\""
    echo "SOURCE_PATCH_DEBUG=\"$source_patch_debug\""
    echo "PATCH_UP_TO=\"$patch_up_to\""
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
        local tag="$TAG"
        local email="$EMAIL"
        local app_name="$APP_NAME"
        local customer="$CUSTOMER"
        local customer_link="$CUSTOMER_LINK"
        local banner_url="$BANNER_URL"
        local icon_url="$ICON_URL"
        local logo_url="$LOGO_URL"
        local super_password="$SUPER_PASSWORD"
        local slogan="$SLOGAN"
        local rendezvous_server="$RENDEZVOUS_SERVER"
        local relay_server="$RELAY_SERVER"
        local rs_pub_key="$RS_PUB_KEY"
        local api_server="$API_SERVER"
        local lock_network_settings="${LOCK_NETWORK_SETTINGS:-false}"
        local hide_network_settings="${HIDE_NETWORK_SETTINGS:-false}"
        local source_patch_debug="${SOURCE_PATCH_DEBUG:-false}"
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
        tag="$TAG"
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
        local tag="$TAG"
        local email="$EMAIL"
        local app_name="$APP_NAME"
        local customer="$CUSTOMER"
        local customer_link="$CUSTOMER_LINK"
        local banner_url="$BANNER_URL"
        local icon_url="$ICON_URL"
        local logo_url="$LOGO_URL"
        local super_password="$SUPER_PASSWORD"
        local slogan="$SLOGAN"
        local rendezvous_server="$RENDEZVOUS_SERVER"
        local relay_server="$RELAY_SERVER"
        local rs_pub_key="$RS_PUB_KEY"
        local api_server="$API_SERVER"
        local lock_network_settings="${LOCK_NETWORK_SETTINGS:-false}"
        local hide_network_settings="${HIDE_NETWORK_SETTINGS:-false}"
        local source_patch_debug="${SOURCE_PATCH_DEBUG:-false}"
        local patch_up_to="${PATCH_UP_TO:-}"
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
