#!/bin/bash
# 审核和验证脚本 - 简化版本

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 验证服务器地址格式
_validate_server_address() {
    local server_address="$1"
    local server_name="$2"
    
    local clean_address="$server_address"
    clean_address="${clean_address#*://}"
    clean_address="${clean_address%%:*}"
    clean_address="${clean_address%%/*}"
    
    if [ -z "$clean_address" ]; then
        echo "$server_name 地址不能为空"
        return 1
    fi
    
    if [[ "$clean_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$clean_address"
        for segment in "${ADDR[@]}"; do
            if [ "$segment" -lt 0 ] || [ "$segment" -gt 255 ]; then
                echo "$server_name 地址格式错误: $server_address (IP地址段超出范围0-255)"
                return 1
            fi
        done
        return 0
    fi
    
    local fqdn_regex='^([a-zA-Z0-9][-a-zA-Z0-9]{0,62}\.)+[a-zA-Z]{2,63}$'
    if [[ "$clean_address" =~ $fqdn_regex ]]; then
        return 0
    fi
    
    echo "$server_name 地址格式错误: $server_address (请提供有效的IP地址或完整域名)"
    return 1
}

# 检查是否需要审核（公网IP或域名需要审核）
_needs_review() {
    local address="$1"
    
    local clean_address="$address"
    clean_address="${clean_address#*://}"
    clean_address="${clean_address%%:*}"
    clean_address="${clean_address%%/*}"
    
    if [[ "$clean_address" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        if [[ "$clean_address" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|169\.254\.) ]]; then
            return 1  # 私有IP，不需要审核
        else
            return 0  # 公网IP，需要审核
        fi
    else
        return 0  # 域名，需要审核
    fi
}

# 统一验证服务器地址（格式验证 + 审核检查）
_validate_server_with_review() {
    local server_address="$1"
    local server_name="$2"
    
    local issues=()
    local needs_review=false
    
    if [ -n "$server_address" ]; then
        if ! _validate_server_address "$server_address" "$server_name" > /dev/null 2>&1; then
            issues+=("$server_name 地址格式错误: $server_address (请提供有效的IP地址或完整域名)")
        else
            if _needs_review "$server_address"; then
                needs_review=true
            fi
        fi
    else
        issues+=("$server_name 地址不能为空")
    fi
    
    echo "${issues[*]}|$needs_review"
}

# 获取触发类型和用户信息
_get_trigger_info() {
    local event_data="$1"
    
    local actor=$(echo "$event_data" | jq -r '.sender.login // empty' || echo "")
    local repo_owner=$(echo "$event_data" | jq -r '.repository.owner.login // empty' || echo "")
    
    local trigger_type=""
    if [ -n "$GITHUB_EVENT_NAME" ]; then
        case "$GITHUB_EVENT_NAME" in
            "workflow_dispatch")
                trigger_type="workflow_dispatch"
                ;;
            "issues")
                trigger_type="issue"
                ;;
            *)
                trigger_type="$GITHUB_EVENT_NAME"
                ;;
        esac
    else
        trigger_type="${TRIGGER_TYPE:-unknown}"
    fi
    
    echo "$trigger_type|$actor|$repo_owner"
}

# 获取原始issue编号
_get_original_issue_number() {
    local event_data="$1"
    local trigger_type="$2"
    
    if [ "$trigger_type" = "issue" ]; then
        if [ -n "$GITHUB_EVENT_PATH" ]; then
            jq -r '.issue.number // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || echo ""
        else
            echo "$event_data" | jq -r '.issue.number // empty' || echo ""
        fi
    else
        echo ""
    fi
}

# 验证参数
_validate_parameters() {
    local event_data="$1"
    local trigger_data="$2"
    
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.build_params.rendezvous_server // empty')
    local api_server=$(echo "$trigger_data" | jq -r '.build_params.api_server // empty')
    local email=$(echo "$trigger_data" | jq -r '.build_params.email // empty')
    
    debug "var" "Extracted rendezvous_server" "$rendezvous_server"
    debug "var" "Extracted api_server" "$api_server"
    debug "var" "Extracted email" "$email"
    
    local issues=()
    local has_issues=false
    local needs_review=false
    
    if [ -n "$email" ] && [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        issues+=("邮件地址格式错误: $email (请提供有效的邮件地址)")
        has_issues=true
        debug "log" "Email validation failed: $email"
    else
        debug "log" "Email validation passed: $email"
    fi
    
    local rendezvous_result=$(_validate_server_with_review "$rendezvous_server" "Rendezvous server")
    local rendezvous_issues=$(echo "$rendezvous_result" | cut -d'|' -f1)
    local rendezvous_needs_review=$(echo "$rendezvous_result" | cut -d'|' -f2)
    
    if [ -n "$rendezvous_issues" ]; then
        issues+=("$rendezvous_issues")
        has_issues=true
        debug "log" "Rendezvous server validation failed: $rendezvous_server"
    else
        debug "log" "Rendezvous server validation passed: $rendezvous_server"
        if [ "$rendezvous_needs_review" = "true" ]; then
            needs_review=true
            debug "log" "Rendezvous server needs review (public IP/domain): $rendezvous_server"
        fi
    fi
    
    local api_result=$(_validate_server_with_review "$api_server" "API server")
    local api_issues=$(echo "$api_result" | cut -d'|' -f1)
    local api_needs_review=$(echo "$api_result" | cut -d'|' -f2)
    
    if [ -n "$api_issues" ]; then
        issues+=("$api_issues")
        has_issues=true
        debug "log" "API server validation failed: $api_server"
    else
        debug "log" "API server validation passed: $api_server"
        if [ "$api_needs_review" = "true" ]; then
            needs_review=true
            debug "log" "API server needs review (public IP/domain): $api_server"
        fi
    fi

    if [ "$has_issues" = "true" ]; then
        local issues_json
        if ! issues_json=$(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .); then
            debug "error" "参数校验结果生成JSON失败，内容: ${issues[*]}"
            exit 2
        fi
        debug "log" "Validation failed with issues: $issues_json"
        echo "$issues_json"
        return 1
    else
        debug "log" "All validations passed"
        if [ "$needs_review" = "true" ]; then
            debug "log" "Validation passed but needs review"
        fi
        echo "[]"
        return 0
    fi
}

# 确定是否需要审核
_need_review() {
    local event_data="$1"
    local trigger_data="$2"
    
    local trigger_info=$(_get_trigger_info "$event_data")
    local trigger_type=$(echo "$trigger_info" | cut -d'|' -f1)
    local actor=$(echo "$trigger_info" | cut -d'|' -f2)
    local repo_owner=$(echo "$trigger_info" | cut -d'|' -f3)
    
    if [ "$trigger_type" = "workflow_dispatch" ]; then
        echo "false"
        return 0
    fi
    
    if [ "$trigger_type" = "issue" ]; then
        if [ "$actor" = "$repo_owner" ]; then
            echo "false"
            return 0
        fi
        
        local rendezvous_server=$(echo "$trigger_data" | jq -r '.build_params.rendezvous_server // empty' || echo "")
        local api_server=$(echo "$trigger_data" | jq -r '.build_params.api_server // empty' || echo "")
        
        local needs_review=false
        
        if [ -n "$rendezvous_server" ] && ! _is_private_ip "$rendezvous_server"; then
            needs_review=true
            debug "log" "Rendezvous server needs review (public): $rendezvous_server"
        fi
        
        if [ -n "$api_server" ] && ! _is_private_ip "$api_server"; then
            needs_review=true
            debug "log" "API server needs review (public): $api_server"
        fi
        
        if [ "$needs_review" = "true" ]; then
            echo "true"
            return 0
        fi
        
        echo "false"
        return 0
    fi
    
    echo "false"
}

# 处理审核流程
_handle_review() {
    local event_data="$1"
    local trigger_data="$2"
    
    # 从trigger_data的build_params中提取需要的参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.build_params.rendezvous_server // empty' || echo "")
    local api_server=$(echo "$trigger_data" | jq -r '.build_params.api_server // empty' || echo "")
    
    local trigger_info=$(_get_trigger_info "$event_data")
    local trigger_type=$(echo "$trigger_info" | cut -d'|' -f1)
    local repo_owner=$(echo "$trigger_info" | cut -d'|' -f3)
    
    # 获取原始issue编号
    local original_issue_number=$(_get_original_issue_number "$event_data" "$trigger_type")
    
    # 生成审核评论
    local review_comment=$(generate_review_comment "$rendezvous_server" "$api_server")
    
    # 如果是Issue触发，添加到原始Issue
    if [ -n "$original_issue_number" ]; then
        issue_manager "add-comment" "$original_issue_number" "$review_comment"
    fi
    
    # 循环检查审核回复
    local start_time=$(date +%s)
    local timeout=21600  # 6小时超时
    local approved=false
    local rejected=false
    
    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        # 获取issue的最新评论
        local comments=$(curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$original_issue_number/comments")
        
        # 保证comments一定是数组
        if echo "$comments" | jq -e 'type == "object"' > /dev/null 2>&1; then
            comments="[$comments]"
        fi
        
        # 检查是否有管理员回复        
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("同意构建"))' > /dev/null 2>&1; then
            approved=true
            break
        fi
        
        if echo "$comments" | jq -e --arg owner "$repo_owner" '.[] | select(.user.login == $owner or .user.login == "admin" or .user.login == "管理员用户名") | select(.body | contains("拒绝构建"))' > /dev/null 2>&1; then
            rejected=true
            break
        fi
        
        # 等待30秒后再次检查        
        sleep 30
    done
    
    # 处理审核结果
    if [ "$approved" = "true" ]; then
        debug "success" "Build approved by admin"
        return 0
    elif [ "$rejected" = "true" ]; then
        debug "error" "Build rejected by admin"
        return 1
    else
        debug "error" "Build timed out during review"
        return 2
    fi
}

# 处理拒绝逻辑
_handle_rejection() {
    local event_data="$1"
    local trigger_data="$2"
    local validation_result="$3"

    local trigger_info=$(_get_trigger_info "$event_data")
    local trigger_type=$(echo "$trigger_info" | cut -d'|' -f1)

    # 如果是Issue触发，回复到原始Issue
    if [ "$trigger_type" = "issue" ]; then
        local original_issue_number=$(_get_original_issue_number "$event_data" "$trigger_type")

        if [ -n "$original_issue_number" ]; then
            # 生成包含所有问题的拒绝回复
            local reject_comment="❌ 参数校验失败，原因如下："
            
            # 尝试解析validation_result为JSON数组
            if echo "$validation_result" | jq -e 'type == "array"' > /dev/null 2>&1; then
                local issues_count=$(echo "$validation_result" | jq 'length' 2>/dev/null || echo "0")
                if [ "$issues_count" -gt 0 ] 2>/dev/null; then
                    for ((i=0; i<issues_count; i++)); do
                        local reason=$(echo "$validation_result" | jq -r ".[$i]" 2>/dev/null || echo "未知错误")
                        reject_comment+=$'\n'"- $reason"
                    done
                else
                    reject_comment+=$'\n'"- 未知参数校验错误"
                fi
            else
                reject_comment+=$'\n'"- $validation_result"
            fi
            
            issue_manager "add-comment" "$original_issue_number" "$reject_comment" || true
        fi
    fi

    # 生成拒绝原因
    local reject_reason=""
    if echo "$validation_result" | jq -e 'type == "array"' > /dev/null 2>&1; then
        local issues_count=$(echo "$validation_result" | jq 'length' 2>/dev/null || echo "0")
        if [ "$issues_count" -eq 1 ] 2>/dev/null; then
            reject_reason=$(echo "$validation_result" | jq -r '.[0]' 2>/dev/null || echo "参数格式错误")
        elif [ "$issues_count" -gt 1 ] 2>/dev/null; then
            reject_reason="发现 $issues_count 个参数校验问题"
        else
            reject_reason="未知参数校验错误"
        fi
    else
        reject_reason="参数校验失败"
    fi

    # 设置拒绝原因到环境变量
    if [ -n "$GITHUB_ENV" ] && [ -w "$GITHUB_ENV" ]; then
        echo "REJECT_REASON=$reject_reason" >> $GITHUB_ENV
    fi

    debug "error" "Build rejected: $reject_reason"
}

# 输出数据
_output_data() {
    local event_data="$1"
    local trigger_data="$2"
    local build_rejected="$3"
    local build_timeout="$4"
    
    # 输出到GitHub Actions输出变量
    echo "data=$trigger_data" >> $GITHUB_OUTPUT
    
    # 根据标志设置构建批准状态    
    if [ "$build_rejected" = "true" ]; then
        echo "review_passed=false" >> $GITHUB_OUTPUT
        if [ "$BUILD_REJECTED" = "true" ]; then
            local reject_reason="${REJECT_REASON:-Build was rejected due to validation issues}"
            echo "review_reason=$reject_reason" >> $GITHUB_OUTPUT
            debug "error" "Build was rejected: $reject_reason"
        else
            echo "review_reason=Build was rejected by admin" >> $GITHUB_OUTPUT
            debug "error" "Build was rejected by admin"
        fi
    elif [ "$build_timeout" = "true" ]; then
        echo "review_passed=false" >> $GITHUB_OUTPUT
        echo "review_reason=Build timed out during review" >> $GITHUB_OUTPUT
        debug "error" "Build timed out during review"
    else
        echo "review_passed=true" >> $GITHUB_OUTPUT
        echo "review_reason=" >> $GITHUB_OUTPUT
        debug "success" "Build was approved or no review needed"
    fi
}

# 输出被拒绝构建的数据
_output_rejected_data() {
    local trigger_data="$1"
    echo "data=$trigger_data" >> $GITHUB_OUTPUT
    echo "review_passed=false" >> $GITHUB_OUTPUT
    echo "review_reason=Build was rejected - no data to pass forward" >> $GITHUB_OUTPUT
    debug "error" "Build was rejected - no data to pass forward"
}

# 获取触发数据
_get_trigger_data() {
    local trigger_data="$1"
    echo "$trigger_data"
}

# 获取服务器参数
_get_server_params() {
    local trigger_data="$1"
    
    # 从trigger_data的build_params中提取服务器参数
    local rendezvous_server=$(echo "$trigger_data" | jq -r '.build_params.rendezvous_server // empty' || echo "")
    local api_server=$(echo "$trigger_data" | jq -r '.build_params.api_server // empty' || echo "")
    local email=$(echo "$trigger_data" | jq -r '.build_params.email // empty' || echo "")
    
    echo "RENDEZVOUS_SERVER=$rendezvous_server"
    echo "API_SERVER=$api_server"
    echo "EMAIL=$email"
}

# 主审核管理函数
review_manager() {
    local operation="$1"
    local event_data="$2"
    local trigger_data="$3"
    local arg4="$4"
    local arg5="$5"
    local arg6="$6"
    
    case "$operation" in
        "validate")
            _validate_parameters "$event_data" "$trigger_data"
            ;;
        "need-review")
            _need_review "$event_data" "$trigger_data"
            ;;
        "handle-review")
            _handle_review "$event_data" "$trigger_data"
            ;;
        "handle-rejection")
            _handle_rejection "$event_data" "$trigger_data" "$arg4"
            ;;
        "output-data")
            _output_data "$event_data" "$trigger_data" "$arg4" "$arg5"
            ;;
        "output-rejected")
            _output_rejected_data "$trigger_data"
            ;;
        "get-trigger-data")
            _get_trigger_data "$trigger_data"
            ;;
        "get-server-params")
            _get_server_params "$trigger_data"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
