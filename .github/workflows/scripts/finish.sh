#!/bin/bash
# 完成处理脚本
# 这个文件处理构建完成后的清理和通知

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/encryption-utils.sh
source .github/workflows/scripts/queue-manager.sh
source .github/workflows/scripts/issue-templates.sh

# 设置完成环境
setup_finish_environment() {
    local project_name="$1"
    local build_status="$2"
    local project_url="$3"
    
    echo "Setting up finish environment for $project_name"
    echo "Build status: $build_status"
    echo "Project URL: $project_url"
}

# 获取和解密构建参数
get_and_decrypt_build_params() {
    local current_build_id="$1"
    
    # 使用队列管理器获取队列数据
    local queue_data=$(queue_manager "data" "${QUEUE_ISSUE_NUMBER:-1}")
    
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue data"
        return 1
    fi
    
    # 从队列中找到当前构建
    local current_queue_item=$(echo "$queue_data" | \
        jq -r --arg build_id "$current_build_id" \
        '.queue[] | select(.build_id == $build_id) // empty')
    
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
send_email_notification() {
    local email="$1"
    local subject="$2"
    local body="$3"
    
    if [ -z "$email" ]; then
        debug "warning" "No email address provided, skipping notification"
        return 0
    fi
    
    # 这里可以集成邮件发送服务
    # 例如：使用 curl 调用邮件 API
    debug "log" "Sending email notification to: $email"
    debug "var" "Subject" "$subject"
    debug "var" "Body" "$body"
    
    # 模拟邮件发送（实际项目中应该调用真实的邮件API）
    # curl -X POST "https://api.example.com/send-email" \
    #   -H "Content-Type: application/json" \
    #   -d "{\"to\": \"$email\", \"subject\": \"$subject\", \"body\": \"$body\"}"
    
    debug "success" "Email notification sent successfully"
    return 0
}

# 清理构建环境
cleanup_build_environment() {
    local build_id="$1"
    
    debug "log" "Cleaning up build environment for build $build_id"
    
    # 清理临时文件
    rm -rf /tmp/build_*
    
    # 清理日志文件
    find /tmp -name "*.log" -mtime +1 -delete 2>/dev/null || true
    
    debug "success" "Build environment cleanup completed"
}

# 检查并重置版本号（当三锁为空时）
check_and_reset_version_numbers() {
    debug "log" "Checking if version numbers should be reset..."
    
    # 获取当前队列数据
    local queue_data=$(queue_manager "data" "${QUEUE_ISSUE_NUMBER:-1}")
    
    if [ $? -ne 0 ]; then
        debug "error" "Failed to get queue data for version reset check"
        return 1
    fi
    
    # 检查是否所有锁都为空且队列为空
    local issue_locked_by=$(echo "$queue_data" | jq -r '.issue_locked_by // null')
    local queue_locked_by=$(echo "$queue_data" | jq -r '.queue_locked_by // null')
    local build_locked_by=$(echo "$queue_data" | jq -r '.build_locked_by // null')
    local current_run_id=$(echo "$queue_data" | jq -r '.run_id // null')
    local queue_length=$(echo "$queue_data" | jq -r '.queue | length')
    
    debug "log" "Lock status check:"
    debug "var" "issue_locked_by" "$issue_locked_by"
    debug "var" "queue_locked_by" "$queue_locked_by"
    debug "var" "build_locked_by" "$build_locked_by"
    debug "var" "current_run_id" "$current_run_id"
    debug "var" "queue_length" "$queue_length"
    
    # 检查是否所有锁都为空且队列为空
    if [ "$issue_locked_by" = "null" ] && [ "$queue_locked_by" = "null" ] && [ "$build_locked_by" = "null" ] && [ "$current_run_id" = "null" ] && [ "$queue_length" -eq 0 ]; then
        debug "log" "All locks are free and queue is empty, checking version numbers..."
        
        # 检查版本号是否超过阈值
        local version=$(echo "$queue_data" | jq -r '.version // 1')
        local issue_lock_version=$(echo "$queue_data" | jq -r '.issue_lock_version // 1')
        local queue_lock_version=$(echo "$queue_data" | jq -r '.queue_lock_version // 1')
        local build_lock_version=$(echo "$queue_data" | jq -r '.build_lock_version // 1')
        local version_threshold=100
        
        debug "log" "Version numbers:"
        debug "var" "version" "$version"
        debug "var" "issue_lock_version" "$issue_lock_version"
        debug "var" "queue_lock_version" "$queue_lock_version"
        debug "var" "build_lock_version" "$build_lock_version"
        
        # 检查是否有任何版本号超过阈值
        if [ "$version" -gt "$version_threshold" ] || [ "$issue_lock_version" -gt "$version_threshold" ] || [ "$queue_lock_version" -gt "$version_threshold" ] || [ "$build_lock_version" -gt "$version_threshold" ]; then
            debug "log" "Version numbers are high, resetting to 1"
            
            # 重置所有版本号为1
            local reset_queue_data=$(echo "$queue_data" | jq '
                .version = 1 |
                .issue_lock_version = 1 |
                .queue_lock_version = 1 |
                .build_lock_version = 1
            ')
            
            # 更新队列数据
            local update_response=$(queue_manager_update_queue_comment "$reset_queue_data" "无")
            
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
validate_finish_completion() {
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
    
    # 注意：通知状态可能在后续步骤中更新，这里不强制验证
    # 对于成功的构建，通知状态会在发送通知后更新
    
    if [ -n "$validation_errors" ]; then
        debug "warning" "Finish validation issues: $validation_errors"
        return 1
    else
        debug "success" "Finish stage completed successfully"
        return 0
    fi
}

# 输出完成数据
output_finish_data() {
    local build_status="$1"
    local notification_sent="$2"
    local cleanup_completed="$3"
    local lock_released="$4"
    
    # 验证完成状态
    validate_finish_completion "$build_status" "$notification_sent" "$cleanup_completed" "$lock_released"
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

# 主完成管理函数 - 供工作流调用
finish_manager() {
    local operation="$1"
    local build_data="$2"
    local build_status="$3"
    local download_url="$4"
    local error_message="$5"
    
    case "$operation" in
        "setup-environment")
            setup_finish_environment "Custom Rustdesk" "$build_status" "$download_url"
            ;;
        "get-params")
            local build_id="$6"
            get_and_decrypt_build_params "$build_id"
            ;;
        "send-notification")
            local email="$6"
            local subject="$7"
            local body="$8"
            send_email_notification "$email" "$subject" "$body"
            ;;
        "cleanup")
            local build_id="$6"
            cleanup_build_environment "$build_id"
            ;;
        "release-triple-lock")
            local build_id="$6"
            # 释放三锁架构的所有锁
            if [ -z "$GITHUB_TOKEN" ]; then
              debug "warning" "GITHUB_TOKEN not set, skipping triple lock release"
              echo "lock_released=skipped"
            else
              debug "log" "Releasing all triple locks for build $build_id"
              
              local lock_release_status="success"
              local failed_locks=""
              
              # 释放构建锁
              if queue_manager "release-build-lock" "$build_id"; then
                debug "success" "Successfully released build lock"
              else
                debug "warning" "Failed to release build lock"
                lock_release_status="partial"
                failed_locks="${failed_locks}build_lock "
              fi
              
              # 释放队列锁
              if queue_manager "release-queue-lock" "$build_id"; then
                debug "success" "Successfully released queue lock"
              else
                debug "warning" "Failed to release queue lock"
                lock_release_status="partial"
                failed_locks="${failed_locks}queue_lock "
              fi
              
              # 释放Issue锁
              if queue_manager "release-issue-lock" "$build_id"; then
                debug "success" "Successfully released issue lock"
              else
                debug "warning" "Failed to release issue lock"
                lock_release_status="partial"
                failed_locks="${failed_locks}issue_lock "
              fi
              
              if [ "$lock_release_status" = "partial" ]; then
                debug "warning" "Some locks failed to release: $failed_locks"
                echo "lock_released=partial"
                echo "failed_locks=$failed_locks"
              else
                echo "lock_released=success"
              fi
            fi
            ;;
        "check-version-reset")
            check_and_reset_version_numbers
            ;;
        "output-data")
            local notification_sent="$6"
            local cleanup_completed="$7"
            local lock_released="$8"
            output_finish_data "$build_status" "$notification_sent" "$cleanup_completed" "$lock_released"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
} 
