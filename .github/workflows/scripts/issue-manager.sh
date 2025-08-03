#!/bin/bash
# Issue 管理器脚本 - 伪面向对象设计
# 使用主调度函数统一管理所有 issue 操作

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh

# 私有属性（全局变量）
_ISSUE_MANAGER_CURRENT_ISSUE_NUMBER=""
_ISSUE_MANAGER_CURRENT_USER=""
_ISSUE_MANAGER_REPOSITORY=""

# 构造函数
issue_manager_init() {
    local issue_number="${1:-}"
    local current_user="${2:-}"
    
    _ISSUE_MANAGER_CURRENT_ISSUE_NUMBER="$issue_number"
    _ISSUE_MANAGER_CURRENT_USER="$current_user"
    _ISSUE_MANAGER_REPOSITORY="$GITHUB_REPOSITORY"
    
    debug "log" "Initializing issue manager"
    debug "var" "Issue number" "$_ISSUE_MANAGER_CURRENT_ISSUE_NUMBER"
    debug "var" "Current user" "$_ISSUE_MANAGER_CURRENT_USER"
    debug "var" "Repository" "$_ISSUE_MANAGER_REPOSITORY"
}

# 私有方法：获取 issue 内容
_issue_manager_get_content() {
    local issue_number="$1"
    
    debug "log" "Fetching content for issue #$issue_number"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")
    
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        debug "error" "Issue #$issue_number not found"
        return 1
    fi
    
    echo "$response"
}

# 私有方法：更新 issue 内容
_issue_manager_update_content() {
    local issue_number="$1"
    local new_body="$2"
    
    debug "log" "Updating content for issue #$issue_number"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$new_body" '{"body": $body}')
    
    # 使用GitHub API更新issue
    local response=$(curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Issue #$issue_number updated successfully"
        return 0
    else
        debug "error" "Failed to update issue #$issue_number"
        return 1
    fi
}

# 私有方法：添加 issue 评论
_issue_manager_add_comment() {
    local issue_number="$1"
    local comment="$2"
    
    debug "log" "Adding comment to issue #$issue_number"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$comment" '{"body": $body}')
    
    # 使用GitHub API添加评论
    local response=$(curl -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Comment added to issue #$issue_number successfully"
        return 0
    else
        debug "error" "Failed to add comment to issue #$issue_number"
        return 1
    fi
}

# 私有方法：获取 issue 评论列表
_issue_manager_get_comments() {
    local issue_number="$1"
    
    debug "log" "Fetching comments for issue #$issue_number"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments")
    
    echo "$response"
}

# 私有方法：检查 issue 是否存在
_issue_manager_exists() {
    local issue_number="$1"
    
    debug "log" "Checking if issue #$issue_number exists"
    
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")
    
    # 检查是否返回错误信息
    if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
        debug "log" "Issue #$issue_number does not exist"
        return 1
    else
        debug "log" "Issue #$issue_number exists"
        return 0
    fi
}

# 私有方法：关闭 issue
_issue_manager_close() {
    local issue_number="$1"
    local reason="${2:-completed}"
    
    debug "log" "Closing issue #$issue_number with reason: $reason"
    
    local json_payload=$(jq -n --arg state "closed" --arg reason "$reason" '{"state": $state, "state_reason": $reason}')
    
    local response=$(curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Issue #$issue_number closed successfully"
        return 0
    else
        debug "error" "Failed to close issue #$issue_number"
        return 1
    fi
}

# 私有方法：检查用户是否有管理员权限
_issue_manager_check_admin_permission() {
    local username="$1"
    
    debug "log" "Checking admin permission for user: $username"
    
    # 检查是否为仓库所有者
    if [ "$username" = "$GITHUB_REPOSITORY_OWNER" ]; then
        debug "log" "User $username is repository owner"
        return 0
    fi
    
    # 检查是否为协作者且有管理员权限
    local response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/collaborators/$username")
    
    local permission=$(echo "$response" | jq -r '.permissions.admin // false')
    
    if [ "$permission" = "true" ]; then
        debug "log" "User $username has admin permission"
        return 0
    else
        debug "log" "User $username does not have admin permission"
        return 1
    fi
}

# 私有方法：获取 issue 属性
_issue_manager_get_property() {
    local issue_number="$1"
    local property="$2"
    
    debug "log" "Getting property '$property' for issue #$issue_number"
    
    local issue_content=$(_issue_manager_get_content "$issue_number")
    
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

# 私有方法：更新评论
_issue_manager_update_comment() {
    local issue_number="$1"
    local comment_id="$2"
    local comment="$3"
    
    debug "log" "Updating comment #$comment_id in issue #$issue_number"
    
    # 使用jq正确转义JSON
    local json_payload=$(jq -n --arg body "$comment" '{"body": $body}')
    
    # 使用GitHub API更新评论
    local response=$(curl -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number/comments/$comment_id" \
        -d "$json_payload")
    
    if echo "$response" | jq -e '.id' > /dev/null 2>&1; then
        debug "success" "Comment #$comment_id updated successfully"
        return 0
    else
        debug "error" "Failed to update comment #$comment_id"
        return 1
    fi
}

# 主调度函数 - 统一管理所有 issue 操作
issue_manager() {
    local operation="$1"
    local issue_number="${2:-}"
    local current_user="${3:-}"
    shift 3
    
    # 初始化 Issue 管理器
    issue_manager_init "$issue_number" "$current_user"
    
    case "$operation" in
        "get-content")
            _issue_manager_get_content "$issue_number"
            ;;
        "update-content")
            local new_body="$1"
            _issue_manager_update_content "$issue_number" "$new_body"
            ;;
        "add-comment")
            local comment="$1"
            _issue_manager_add_comment "$issue_number" "$comment"
            ;;
        "get-comments")
            _issue_manager_get_comments "$issue_number"
            ;;
        "exists")
            _issue_manager_exists "$issue_number"
            ;;
        "close")
            local reason="${1:-completed}"
            _issue_manager_close "$issue_number" "$reason"
            ;;
        "check-admin")
            local username="$1"
            _issue_manager_check_admin_permission "$username"
            ;;
        "get-property")
            local property="$1"
            _issue_manager_get_property "$issue_number" "$property"
            ;;
        "update-comment")
            local comment_id="$1"
            local comment="$2"
            _issue_manager_update_comment "$issue_number" "$comment_id" "$comment"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
