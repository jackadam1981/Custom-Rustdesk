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
    echo "CUSTOMER=\"$(echo "$event_data" | jq -r '.inputs.customer // empty')\""
    echo "CUSTOMER_LINK=\"$(echo "$event_data" | jq -r '.inputs.customer_link // empty')\""
    echo "SUPER_PASSWORD=\"$(echo "$event_data" | jq -r '.inputs.super_password // empty')\""
    echo "SLOGAN=\"$(echo "$event_data" | jq -r '.inputs.slogan // empty')\""
    echo "RENDEZVOUS_SERVER=\"$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')\""
    echo "RS_PUB_KEY=\"$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')\""
    echo "API_SERVER=\"$(echo "$event_data" | jq -r '.inputs.api_server // empty')\""
}

# 从 issue 内容中提取参数
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
    local tag=$(echo "$issue_body" | sed -n 's/.*tag:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local email=$(echo "$issue_body" | sed -n 's/.*email:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local customer=$(echo "$issue_body" | sed -n 's/.*customer:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local customer_link=$(echo "$issue_body" | sed -n 's/.*customer_link:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local super_password=$(echo "$issue_body" | sed -n 's/.*super_password:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local slogan=$(echo "$issue_body" | sed -n 's/.*slogan:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local rendezvous_server=$(echo "$issue_body" | sed -n 's/.*rendezvous_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local rs_pub_key=$(echo "$issue_body" | sed -n 's/.*rs_pub_key:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    local api_server=$(echo "$issue_body" | sed -n 's/.*api_server:[[:space:]]*\([^[:space:]\r\n]*\).*/\1/p' | tail -1)
    
    echo "BUILD_ID=\"$build_id\""
    echo "TAG=\"$tag\""
    echo "EMAIL=\"$email\""
    echo "CUSTOMER=\"$customer\""
    echo "CUSTOMER_LINK=\"$customer_link\""
    echo "SUPER_PASSWORD=\"$super_password\""
    echo "SLOGAN=\"$slogan\""
    echo "RENDEZVOUS_SERVER=\"$rendezvous_server\""
    echo "RS_PUB_KEY=\"$rs_pub_key\""
    echo "API_SERVER=\"$api_server\""
}

# 应用默认值
_apply_default_values() {
    local event_data="$1"
    
    debug "log" "Applying default values"
    
    if echo "$event_data" | jq -e '.inputs' > /dev/null 2>&1; then
        local tag=$(echo "$event_data" | jq -r '.inputs.tag // empty')
        local email=$(echo "$event_data" | jq -r '.inputs.email // empty')
        local customer=$(echo "$event_data" | jq -r '.inputs.customer // empty')
        local customer_link=$(echo "$event_data" | jq -r '.inputs.customer_link // empty')
        local super_password=$(echo "$event_data" | jq -r '.inputs.super_password // empty')
        local slogan=$(echo "$event_data" | jq -r '.inputs.slogan // empty')
        local rendezvous_server=$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')
        local rs_pub_key=$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')
        local api_server=$(echo "$event_data" | jq -r '.inputs.api_server // empty')
    else
        local tag="$TAG"
        local email="$EMAIL"
        local customer="$CUSTOMER"
        local customer_link="$CUSTOMER_LINK"
        local super_password="$SUPER_PASSWORD"
        local slogan="$SLOGAN"
        local rendezvous_server="$RENDEZVOUS_SERVER"
        local rs_pub_key="$RS_PUB_KEY"
        local api_server="$API_SERVER"
    fi
    
    echo "TAG=\"${tag:-${DEFAULT_TAG:-}}\""
    echo "EMAIL=\"${email:-${DEFAULT_EMAIL:-}}\""
    echo "CUSTOMER=\"${customer:-${DEFAULT_CUSTOMER:-}}\""
    echo "CUSTOMER_LINK=\"${customer_link:-${DEFAULT_CUSTOMER_LINK:-}}\""
    echo "SUPER_PASSWORD=\"${super_password:-${DEFAULT_SUPER_PASSWORD:-}}\""
    echo "SLOGAN=\"${slogan:-${DEFAULT_SLOGAN:-}}\""
    echo "RENDEZVOUS_SERVER=\"${rendezvous_server:-${DEFAULT_RENDEZVOUS_SERVER:-}}\""
    echo "RS_PUB_KEY=\"${rs_pub_key:-${DEFAULT_RS_PUB_KEY:-}}\""
    echo "API_SERVER=\"${api_server:-${DEFAULT_API_SERVER:-}}\""
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
        local customer=$(echo "$event_data" | jq -r '.inputs.customer // empty')
        local customer_link=$(echo "$event_data" | jq -r '.inputs.customer_link // empty')
        local super_password=$(echo "$event_data" | jq -r '.inputs.super_password // empty')
        local slogan=$(echo "$event_data" | jq -r '.inputs.slogan // empty')
        local rendezvous_server=$(echo "$event_data" | jq -r '.inputs.rendezvous_server // empty')
        local rs_pub_key=$(echo "$event_data" | jq -r '.inputs.rs_pub_key // empty')
        local api_server=$(echo "$event_data" | jq -r '.inputs.api_server // empty')
        local trigger_type="workflow_dispatch"
        local issue_number="null"
    else
        local tag="$TAG"
        local email="$EMAIL"
        local customer="$CUSTOMER"
        local customer_link="$CUSTOMER_LINK"
        local super_password="$SUPER_PASSWORD"
        local slogan="$SLOGAN"
        local rendezvous_server="$RENDEZVOUS_SERVER"
        local rs_pub_key="$RS_PUB_KEY"
        local api_server="$API_SERVER"
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
        --arg customer "$customer" \
        --arg customer_link "$customer_link" \
        --arg super_password "$super_password" \
        --arg slogan "$slogan" \
        --arg rendezvous_server "$rendezvous_server" \
        --arg rs_pub_key "$rs_pub_key" \
        --arg api_server "$api_server" \
        '{build_id: $build_id, trigger_type: $trigger_type, issue_number: $issue_number, build_params: {tag: $tag, original_tag: $original_tag, email: $email, customer: $customer, customer_link: $customer_link, super_password: $super_password, slogan: $slogan, rendezvous_server: $rendezvous_server, rs_pub_key: $rs_pub_key, api_server: $api_server}}')
    
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
    local api_server=$(echo "$final_data" | jq -r '.build_params.api_server // empty')
    local super_password=$(echo "$final_data" | jq -r '.build_params.super_password // empty')
    
    local errors=()
    [ -z "$tag" ] && errors+=("tag is required")
    [ -z "$email" ] && errors+=("email is required")
    [ -z "$customer" ] && errors+=("customer is required")
    [ -z "$rendezvous_server" ] && errors+=("rendezvous_server is required")
    [ -z "$api_server" ] && errors+=("api_server is required")
    [ -z "$super_password" ] && errors+=("super_password is required")
    
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
