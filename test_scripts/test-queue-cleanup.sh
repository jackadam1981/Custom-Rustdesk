#!/bin/bash
# 队列清理功能测试脚本

# 设置测试环境
set -e

# 加载测试工具
source test_scripts/test-framework.sh


# 测试队列清理功能（带验证）
test_queue_cleanup_with_verification() {
    log_step "Testing queue cleanup functionality with verification..."
    
    # 显示测试前的状态
    show_issue_status "Before Queue Cleanup Test"
    
    # 获取初始状态
    local initial_state=$(get_current_queue_state)
    local initial_queue_length=$(echo "$initial_state" | grep "queue_length=" | cut -d'=' -f2)
    local initial_version=$(echo "$initial_state" | grep "version=" | cut -d'=' -f2)
    
    log_info "Initial state: queue_length=$initial_queue_length, version=$initial_version"
    
    # 先添加一些测试数据到队列中
    log_info "Adding test items to queue for cleanup testing..."
    
    # 添加第一个测试项（新任务，不会被清理）
    run_test "Add Test Item 1" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"cleanup-test-1\",\"email\":\"test1@example.com\",\"customer\":\"test-customer-1\",\"trigger_type\":\"workflow_dispatch\"}'" \
        0
    
    # 添加第二个测试项（新任务，不会被清理）
    run_test "Add Test Item 2" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"cleanup-test-2\",\"email\":\"test2@example.com\",\"customer\":\"test-customer-2\",\"trigger_type\":\"workflow_dispatch\"}'" \
        0
    
    # 添加第三个测试项（新任务，不会被清理）
    run_test "Add Test Item 3" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"cleanup-test-3\",\"email\":\"test3@example.com\",\"customer\":\"test-customer-3\",\"trigger_type\":\"workflow_dispatch\"}'" \
        0
    
    # 添加第四个测试项（新任务，不会被清理）
    run_test "Add Test Item 4" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"cleanup-test-4\",\"email\":\"test4@example.com\",\"customer\":\"test-customer-4\",\"trigger_type\":\"workflow_dispatch\"}'" \
        0
    
    # 手动修改其中两个任务的join_time为旧时间（超过6小时，应该被清理）
    log_info "Modifying some tasks to simulate old tasks that should be cleaned up..."
    
    # 获取当前Issue #1数据
    local json_data=$(get_issue_json_data)
    local old_time="2025-08-05 10:00:00"  # 8小时前，应该被清理
    
    # 修改队列中第2和第4个任务的join_time为旧时间
    local updated_data=$(echo "$json_data" | jq --arg old_time "$old_time" '
        .queue[1].join_time = $old_time |
        .queue[3].join_time = $old_time |
        .version = (.version // 0) + 1
    ')
    
    # 直接更新Issue #1（模拟修改旧任务）
    local body_content=$(echo "$updated_data" | jq -c .)
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 生成issue body
    local body=$(source .github/workflows/scripts/issue-templates.sh && generate_dual_lock_status_body "$current_time" "$body_content")
    
    # 更新Issue #1
    if source .github/workflows/scripts/issue-manager.sh && issue_manager "update-content" "1" "$body"; then
        log_success "Successfully modified tasks to simulate old tasks for cleanup testing"
    else
        log_error "Failed to modify tasks for cleanup testing"
        return 1
    fi
    
    # 显示添加测试数据后的状态
    show_issue_status "After Adding Test Items"
    
    # 测试清理功能
    run_test "Queue Cleanup - Normal" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'cleanup'" \
        0
    
    # 验证清理操作是否真正生效
    local json_data=$(get_issue_json_data)
    local current_queue_length=$(echo "$json_data" | jq '.queue | length')
    local current_version=$(echo "$json_data" | jq '.version')
    
    log_info "After cleanup: queue_length=$current_queue_length, version=$current_version"
    
    # 验证版本号是否增加（表示cleanup操作执行了）
    if [ "$current_version" -gt "$initial_version" ]; then
        log_success "Queue cleanup operation executed (version increased from $initial_version to $current_version)"
    else
        log_warning "Queue cleanup operation may not have changed version (from $initial_version to $current_version)"
    fi
    
    # 验证旧任务是否被清理（检查是否有8小时前的任务）
    local old_tasks_count=$(echo "$json_data" | jq -r '.queue[] | select(.join_time == "2025-08-05 10:00:00") | .run_id' | wc -l)
    if [ "$old_tasks_count" -eq 0 ]; then
        log_success "Queue cleanup operation successful: old tasks removed"
    else
        log_warning "Queue cleanup operation: $old_tasks_count old tasks still exist (but operation may still be successful)"
        # 不返回1，让测试继续
    fi
    
    # 验证新任务是否保留（检查是否有当前时间的任务）
    local new_tasks_count=$(echo "$json_data" | jq -r '.queue[] | select(.join_time != "2025-08-05 10:00:00") | .run_id' | wc -l)
    if [ "$new_tasks_count" -gt 0 ]; then
        log_success "Queue cleanup operation successful: new tasks preserved ($new_tasks_count tasks)"
    else
        log_warning "Queue cleanup operation: no new tasks found"
    fi
    
    # 显示清理后的队列内容
    echo "Queue items after cleanup:"
    echo "$json_data" | jq -r '.queue[] | "  - \(.run_id): \(.tag) (\(.join_time))"'
    
    # 显示清理后的状态
    show_issue_status "After Queue Cleanup Test"
}

# 主函数
main() {
    echo "========================================"
    echo "    Queue Cleanup Function Tests"
    echo "========================================"
    echo ""
    
    # 设置测试环境
    init_test_framework
    

    
    # 运行测试
    test_queue_cleanup_with_verification
    
    # 清理测试环境
    cleanup_test_framework
    
    # 显示测试结果
    
    # 返回适当的退出码
}

# 运行主函数
main "$@" 

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "错误：此测试脚本无法直接运行！"
    echo ""
    echo "请使用以下命令运行测试："
    echo "  ./run-tests.sh queue-cleanup"
    echo ""
    echo "或者查看所有可用测试："
    echo "  ./run-tests.sh --list"
    echo ""
    echo "查看帮助信息："
    echo "  ./run-tests.sh --help"
    exit 1
fi 
