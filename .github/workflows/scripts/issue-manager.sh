#!/bin/bash
# Issue 管理器脚本 - 重构版本
# 保留主调度函数设计，简化内部实现

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh

# ========== 私有辅助函数 ==========

# 通用GitHub API调用函数
_github_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    
    local curl_args=("-s" "-H" "Authorization: token $GITHUB_TOKEN" "-H" "Accept: application/vnd.github.v3+json")
    
    if [ "$method" != "GET" ]; then
        curl_args+=("-X" "$method" "-H" "Content-Type: application/json")
        if [ -n "$data" ]; then
            curl_args+=("-d" "$data")
        fi
    fi
    
    curl "${curl_args[@]}" "https://api.github.com/repos/$GITHUB_REPOSITORY$endpoint"
}

# 检查API响应是否成功
_check_api_response() {
    local response="$1"
    local operation="$2"
    
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        debug "error" "$operation failed: Not Found"
        return 1
    elif echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "$operation completed successfully"
        return 0
    else
        debug "error" "$operation failed: $(echo "$response" | jq -r '.message // "Unknown error"')"
        return 1
    fi
}

# ========== 私有方法 ==========

# 获取 issue 内容
_get_content() {
    local issue_number="$1"
    
    debug "log" "Fetching content for issue #$issue_number"
    _github_api_call "GET" "/issues/$issue_number"
}

# 更新 issue 内容
_update_content() {
    local issue_number="$1"
    local new_body="$2"
    
    debug "log" "Updating content for issue #$issue_number"
    
    local json_payload=$(jq -n --arg body "$new_body" '{"body": $body}')
    local response=$(_github_api_call "PATCH" "/issues/$issue_number" "$json_payload")
    
    _check_api_response "$response" "Issue update"
}

# 添加 issue 评论
_add_comment() {
    local issue_number="$1"
    local comment="$2"
    
    debug "log" "Adding comment to issue #$issue_number"
    
    local json_payload=$(jq -n --arg body "$comment" '{"body": $body}')
    local response=$(_github_api_call "POST" "/issues/$issue_number/comments" "$json_payload")
    
    _check_api_response "$response" "Comment addition"
}

# 获取 issue 评论列表
_get_comments() {
    local issue_number="$1"
    
    debug "log" "Fetching comments for issue #$issue_number"
    _github_api_call "GET" "/issues/$issue_number/comments"
}

# 检查 issue 是否存在
_exists() {
    local issue_number="$1"
    
    debug "log" "Checking if issue #$issue_number exists"
    
    local response=$(_github_api_call "GET" "/issues/$issue_number")
    
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        debug "log" "Issue #$issue_number does not exist"
        return 1
    else
        debug "log" "Issue #$issue_number exists"
        return 0
    fi
}

# 关闭 issue
_close() {
    local issue_number="$1"
    local reason="${2:-completed}"
    
    debug "log" "Closing issue #$issue_number with reason: $reason"
    
    local json_payload=$(jq -n --arg state "closed" --arg reason "$reason" '{"state": $state, "state_reason": $reason}')
    local response=$(_github_api_call "PATCH" "/issues/$issue_number" "$json_payload")
    
    _check_api_response "$response" "Issue closure"
}

# 检查用户权限
_check_admin_permission() {
    local username="$1"
    
    debug "log" "Checking admin permission for user: $username"
    
    # 检查是否为仓库所有者
    if [ "$username" = "$GITHUB_REPOSITORY_OWNER" ]; then
        debug "log" "User $username is repository owner"
        return 0
    fi
    
    # 检查是否为协作者且有管理员权限
    local response=$(_github_api_call "GET" "/collaborators/$username")
    local permission=$(echo "$response" | jq -r '.permissions.admin // false')
    
    if [ "$permission" = "true" ]; then
        debug "log" "User $username has admin permission"
        return 0
    else
        debug "log" "User $username does not have admin permission"
        return 1
    fi
}

# 获取 issue 属性
_get_property() {
    local issue_number="$1"
    local property="$2"
    
    debug "log" "Getting property '$property' for issue #$issue_number"
    
    local issue_content=$(_get_content "$issue_number")
    
    case "$property" in
        "author"|"user")
            echo "$issue_content" | jq -r '.user.login // empty'
            ;;
        "title")
            echo "$issue_content" | jq -r '.title // empty'
            ;;
        "state")
    echo "$issue_content" | jq -r '.state // empty'
            ;;
        "body")
            echo "$issue_content" | jq -r '.body // empty'
            ;;
        *)
            debug "error" "Unknown property: $property"
            return 1
            ;;
    esac
}

# 更新评论
_update_comment() {
    local issue_number="$1"
    local comment_id="$2"
    local comment="$3"
    
    debug "log" "Updating comment #$comment_id in issue #$issue_number"
    
    local json_payload=$(jq -n --arg body "$comment" '{"body": $body}')
    local response=$(_github_api_call "PATCH" "/issues/$issue_number/comments/$comment_id" "$json_payload")
    
    _check_api_response "$response" "Comment update"
}

# ========== 主调度函数 ==========

# 主调度函数 - 统一管理所有 issue 操作
issue_manager() {
    local operation="$1"
    local issue_number="${2:-}"
    shift 2
    
    case "$operation" in
        "get-content")
            _get_content "$issue_number"
            ;;
        "update-content")
            local new_body="$1"
            _update_content "$issue_number" "$new_body"
            ;;
        "add-comment")
            local comment="$1"
            _add_comment "$issue_number" "$comment"
            ;;
        "get-comments")
            _get_comments "$issue_number"
            ;;
        "exists")
            _exists "$issue_number"
            ;;
        "close")
            local reason="${1:-completed}"
            _close "$issue_number" "$reason"
            ;;
        "check-admin")
            local username="$1"
            _check_admin_permission "$username"
            ;;
        "get-property")
            local property="$1"
            _get_property "$issue_number" "$property"
            ;;
        "update-comment")
            local comment_id="$1"
            local comment="$2"
            _update_comment "$issue_number" "$comment_id" "$comment"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
