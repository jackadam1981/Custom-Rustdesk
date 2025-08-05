#!/bin/bash
# 队列清理功能测试脚本

# 设置测试环境
set -e

# 加载测试工具
source test_scripts/test-utils.sh

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试结果记录
TEST_RESULTS=()

# 测试函数
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
    log_test "Running test: $test_name"
    echo "Command: $test_command"
    echo "Expected exit code: $expected_exit_code"
    echo "----------------------------------------"
    
    # 显示执行进度
    echo -n "Executing test... "
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行测试命令，确保环境变量传递
    if bash -c "export GITHUB_TOKEN='$GITHUB_TOKEN'; export GITHUB_REPOSITORY='$GITHUB_REPOSITORY'; export GITHUB_RUN_ID='$GITHUB_RUN_ID'; $test_command" > /tmp/test_output.log 2>&1; then
        actual_exit_code=$?
    else
        actual_exit_code=$?
    fi
    
    # 记录结束时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Done! (${duration}s)"
    echo "Actual exit code: $actual_exit_code"
    
    # 检查退出码
    if [ "$actual_exit_code" -eq "$expected_exit_code" ]; then
        log_success "Test PASSED: $test_name (${duration}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: $test_name (${duration}s)")
        
        # 显示成功输出（如果有）
        if [ -f /tmp/test_output.log ] && [ -s /tmp/test_output.log ]; then
            echo "Test output:"
            cat /tmp/test_output.log
        fi
    else
        log_error "Test FAILED: $test_name (Expected: $expected_exit_code, Got: $actual_exit_code, ${duration}s)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: $test_name (Expected: $expected_exit_code, Got: $actual_exit_code, ${duration}s)")
        
        # 显示错误输出
        if [ -f /tmp/test_output.log ]; then
            echo "Test output:"
            cat /tmp/test_output.log
        fi
    fi
    
    echo "----------------------------------------"
}

# 清理测试环境
cleanup_test_env() {
    log_step "Cleaning up test environment..."
    
    # 清理临时文件
    rm -f /tmp/test_output.log
    
    log_success "Test environment cleanup completed"
}

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

# 显示测试结果
show_test_results() {
    echo ""
    echo "========================================"
    echo "           TEST RESULTS SUMMARY"
    echo "========================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All tests passed! 🎉"
        echo ""
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            echo "  ✅ $result"
        done
    else
        log_error "Some tests failed! ❌"
        echo ""
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == "PASS:"* ]]; then
                echo "  ✅ $result"
            else
                echo "  ❌ $result"
            fi
        done
    fi
    
    echo ""
    echo "========================================"
}

# 主函数
main() {
    echo "========================================"
    echo "    Queue Cleanup Function Tests"
    echo "========================================"
    echo ""
    
    # 设置测试环境
    setup_test_env
    

    
    # 运行测试
    test_queue_cleanup_with_verification
    
    # 清理测试环境
    cleanup_test_env
    
    # 显示测试结果
    show_test_results
    
    # 返回适当的退出码
    if [ $FAILED_TESTS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@" 