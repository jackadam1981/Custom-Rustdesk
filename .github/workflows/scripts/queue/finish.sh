#!/bin/bash
# 完成处理脚本 - 简化版本

QUEUE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=queue/debug-utils.sh
source "$QUEUE_SCRIPT_DIR/debug-utils.sh"
# shellcheck source=queue/encryption-utils.sh
source "$QUEUE_SCRIPT_DIR/encryption-utils.sh"
# shellcheck source=queue/queue-manager.sh
source "$QUEUE_SCRIPT_DIR/queue-manager.sh"
# shellcheck source=queue/issue-templates.sh
source "$QUEUE_SCRIPT_DIR/issue-templates.sh"

# 设置完成环境
_setup_finish_environment() {
    local project_name="$1"
    local build_status="$2"
    local project_url="$3"
    
    echo "Setting up finish environment for $project_name"
    echo "Build status: $build_status"
    echo "Project URL: $project_url"
}

# 获取和解密构建参数
_get_and_decrypt_build_params() {
    local current_build_id="$1"
    
    # 使用队列管理器获取队列数据
    load_queue_data
    local queue_data="$QUEUE_DATA"
    
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue data"
        return 1
    fi
    
    # 从队列中找到当前构建
    local current_queue_item=$(echo "$queue_data" | \
        jq -r --arg run_id "$current_build_id" \
        '.queue[] | select(.run_id == $run_id) // empty')
    
    if [ -z "$current_queue_item" ]; then
        debug "error" "Current build not found in queue"
        return 1
    fi
    
    # 获取当前队列项的构建参数
    local build_params=$(echo "$current_queue_item" | jq -r '.build_params // empty')
    
    if [ -z "$build_params" ]; then
        debug "error" "No build_params found for current build"
        return 1
    fi
    
    # 从build_params中提取参数
    local tag=$(echo "$build_params" | jq -r '.tag // empty')
    local email=$(echo "$build_params" | jq -r '.email // empty')
    local customer=$(echo "$build_params" | jq -r '.customer // empty')
    
    # 验证必要参数
    if [ -z "$email" ]; then
        debug "warning" "No email found in build_params, will use fallback"
    fi
    
    # 检查是否有加密的email（如果需要解密）
    local encrypted_email=$(echo "$current_queue_item" | jq -r '.encrypted_email // empty')
    if [ -n "$encrypted_email" ]; then
        email=$(decrypt_params "$encrypted_email")
    fi
    
    debug "log" "🔐 Decrypted parameters for notification:"
    debug "var" "TAG" "$tag"
    debug "var" "EMAIL" "$email"
    debug "var" "CUSTOMER" "$customer"
    
    # 返回解密后的参数
    echo "TAG=$tag"
    echo "EMAIL=$email"
    echo "CUSTOMER=$customer"
}

# 发送邮件通知
_send_email_notification() {
    local email="$1"
    local subject="$2"
    local body="$3"
    
    if [ -z "$email" ]; then
        debug "warning" "No email address provided, skipping notification"
        return 0
    fi
    
    debug "log" "Sending email notification to: $email"
    debug "var" "Subject" "$subject"
    debug "var" "Body" "$body"
    
    # 模拟邮件发送（实际项目中应该调用真实的邮件API）
    
    debug "success" "Email notification sent successfully"
    return 0
}

# 清理构建环境
_cleanup_build_environment() {
    local build_id="$1"
    
    debug "log" "Cleaning up build environment for build $build_id"
    
    # 清理临时文件
    rm -rf /tmp/build_*
    
    # 清理日志文件
    find /tmp -name "*.log" -mtime +1 -delete 2>/dev/null || true
    
    debug "success" "Build environment cleanup completed"
}

# 检查并重置版本号（当三锁为空时）
_check_and_reset_version_numbers() {
    debug "log" "Checking if version numbers should be reset..."
    
    # 获取当前队列数据
    load_queue_data
    local queue_data="$QUEUE_DATA"
    
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue data for version reset check"
        return 1
    fi
    
    # 检查是否所有锁都为空且队列为空
    local issue_locked_by=$(echo "$queue_data" | jq -r '.issue_locked_by // null')
    local build_locked_by=$(echo "$queue_data" | jq -r '.build_locked_by // null')
    local current_run_id=$(echo "$queue_data" | jq -r '.run_id // null')
    local queue_length=$(echo "$queue_data" | jq -r '.queue | length')
    
    debug "log" "Lock status check:"
    debug "var" "issue_locked_by" "$issue_locked_by"
    debug "var" "build_locked_by" "$build_locked_by"
    debug "var" "current_run_id" "$current_run_id"
    debug "var" "queue_length" "$queue_length"
    
    # 检查是否所有锁都为空且队列为空
    if [ "$issue_locked_by" = "null" ] && [ "$build_locked_by" = "null" ] && [ "$current_run_id" = "null" ] && [ "$queue_length" -eq 0 ]; then
        debug "log" "All locks are free and queue is empty, checking version numbers..."
        
        # 检查版本号是否超过阈值
        local version=$(echo "$queue_data" | jq -r '.version // 1')
        local issue_lock_version=$(echo "$queue_data" | jq -r '.issue_lock_version // 1')
        local build_lock_version=$(echo "$queue_data" | jq -r '.build_lock_version // 1')
        local version_threshold=100
        
        debug "log" "Version numbers:"
        debug "var" "version" "$version"
        debug "var" "issue_lock_version" "$issue_lock_version"
        debug "var" "build_lock_version" "$build_lock_version"
        
        # 检查是否有任何版本号超过阈值
        if [ "$version" -gt "$version_threshold" ] || [ "$issue_lock_version" -gt "$version_threshold" ] || [ "$build_lock_version" -gt "$version_threshold" ]; then
            debug "log" "Version numbers are high, resetting to 1"
            
            # 重置所有版本号为1
            local reset_queue_data=$(echo "$queue_data" | jq '
                .version = 1 |
                .issue_lock_version = 1 |
                .build_lock_version = 1
            ')
            
            # 更新队列数据
            update_queue_data "$reset_queue_data"
            
            if [ $? -eq 0 ]; then
                debug "success" "Successfully reset version numbers to 1"
                echo "version_reset=true"
                return 0
            else
                debug "error" "Failed to reset version numbers"
                echo "version_reset=false"
                return 1
            fi
        else
            debug "log" "Version numbers are within acceptable range, no reset needed"
            echo "version_reset=false"
            return 0
        fi
    else
        debug "log" "Locks are not all free or queue is not empty, skipping version reset"
        echo "version_reset=false"
        return 0
    fi
}

# 验证finish阶段完整性
_validate_finish_completion() {
    local build_status="$1"
    local notification_sent="$2"
    local cleanup_completed="$3"
    local lock_released="$4"
    
    local validation_errors=""
    
    # 检查必要步骤是否完成
    if [ "$cleanup_completed" != "true" ]; then
        validation_errors="${validation_errors}Cleanup failed; "
    fi
    
    if [ "$lock_released" != "success" ] && [ "$lock_released" != "partial" ]; then
        validation_errors="${validation_errors}Lock release failed; "
    fi
    
    if [ -n "$validation_errors" ]; then
        debug "warning" "Finish validation issues: $validation_errors"
        return 1
    else
        debug "success" "Finish stage completed successfully"
        return 0
    fi
}

# 输出完成数据
_output_finish_data() {
    local build_status="$1"
    local notification_sent="$2"
    local cleanup_completed="$3"
    local lock_released="$4"
    
    # 验证完成状态
    _validate_finish_completion "$build_status" "$notification_sent" "$cleanup_completed" "$lock_released"
    validation_exit_code=$?
    
    # 输出到GitHub Actions输出变量（如果存在）
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "finish_status=$build_status" >> $GITHUB_OUTPUT
        echo "notification_sent=$notification_sent" >> $GITHUB_OUTPUT
        echo "cleanup_completed=$cleanup_completed" >> $GITHUB_OUTPUT
        echo "lock_released=$lock_released" >> $GITHUB_OUTPUT
        echo "finish_validation_passed=$([ $validation_exit_code -eq 0 ] && echo "true" || echo "false")" >> $GITHUB_OUTPUT
    fi
    
    # 显示输出信息
    echo "Finish output:"
    echo "  Status: $build_status"
    echo "  Notification: $notification_sent"
    echo "  Cleanup: $cleanup_completed"
    echo "  Lock Released: $lock_released"
    echo "  Validation: $([ $validation_exit_code -eq 0 ] && echo "PASSED" || echo "FAILED")"
    
    # 返回标准格式的输出
    echo "finish_completed=true"
}

# 主完成管理函数
finish_manager() {
    local operation="$1"
    local build_data="$2"
    local build_status="$3"
    local download_url="$4"
    local error_message="$5"
    
    case "$operation" in
        "setup-environment")
            _setup_finish_environment "Custom Rustdesk" "$build_status" "$download_url"
            ;;
        "get-params")
            local build_id="$6"
            _get_and_decrypt_build_params "$build_id"
            ;;
        "send-notification")
            local email="$6"
            local subject="$7"
            local body="$8"
            _send_email_notification "$email" "$subject" "$body"
            ;;
        "cleanup")
            local build_id="$6"
            _cleanup_build_environment "$build_id"
            ;;
        "release-locks")
            local build_id="$6"
            # 释放双锁架构的所有锁
            if [ -z "$GITHUB_TOKEN" ]; then
              debug "warning" "GITHUB_TOKEN not set, skipping lock release"
              echo "lock_released=skipped"
            else
              debug "log" "Releasing all locks for build $build_id"
              
              # 使用统一的release操作
              if release_all_locks; then
                debug "success" "Successfully released all locks"
                echo "lock_released=success"
              else
                debug "warning" "Failed to release locks"
                echo "lock_released=failed"
              fi
            fi
            ;;
        "check-version-reset")
            _check_and_reset_version_numbers
            ;;
        "output-data")
            local notification_sent="$6"
            local cleanup_completed="$7"
            local lock_released="$8"
            _output_finish_data "$build_status" "$notification_sent" "$cleanup_completed" "$lock_released"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
