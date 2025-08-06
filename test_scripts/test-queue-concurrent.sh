#!/bin/bash
# 构建锁并发轮询测试脚本

source test_scripts/test-utils.sh

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 运行测试函数
run_test() {
    local test_name="$1"
    local command="$2"
    local expected_exit="$3"
    local timeout="${4:-60}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log_test "Running test: $test_name"
    echo "Command: $command"
    echo "Expected exit code: $expected_exit"
    echo "----------------------------------------"
    
    # 执行测试命令
    echo "Executing test..."
    start_time=$(date +%s)
    
    if timeout $timeout bash -c "$command" > /tmp/test_output.log 2>&1; then
        actual_exit=0
    else
        actual_exit=$?
    fi
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    
    echo "Done! (${duration}s)"
    echo "Actual exit code: $actual_exit"
    
    # 检查结果
    if [ "$actual_exit" -eq "$expected_exit" ]; then
        log_success "Test PASSED: $test_name (${duration}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        
        if [ -s /tmp/test_output.log ]; then
            echo "Test output:"
            cat /tmp/test_output.log
        fi
    else
        log_error "Test FAILED: $test_name (Expected: $expected_exit, Got: $actual_exit, ${duration}s)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        
        if [ -s /tmp/test_output.log ]; then
            echo "Error output:"
            cat /tmp/test_output.log
        fi
    fi
    
    echo "----------------------------------------"
    echo
}

# 并发轮询测试函数
test_concurrent_polling() {
    log_step "Testing concurrent build lock polling..."
    
    # 重置队列状态
    log_info "Resetting queue state..."
    source .github/workflows/scripts/queue-manager.sh
    queue_manager 'queue_lock' 'reset' > /dev/null 2>&1
    
    # 显示初始状态
    log_info "=== Initial Queue Status ==="
    get_issue_json_data
    
    # 添加多个项目到队列
    log_info "Adding multiple items to queue..."
    
    # 生成一致的run_id（用于后续测试）
    run_id_1="concurrent_test_1_$(date +%s)"
    run_id_2="concurrent_test_2_$(date +%s)"
    run_id_3="concurrent_test_3_$(date +%s)"
    
    # 项目1
    export GITHUB_RUN_ID="$run_id_1"
    queue_manager 'queue_lock' 'join' '{"tag":"concurrent-test-1","email":"test1@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}' > /dev/null 2>&1
    
    # 项目2
    export GITHUB_RUN_ID="$run_id_2"
    queue_manager 'queue_lock' 'join' '{"tag":"concurrent-test-2","email":"test2@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}' > /dev/null 2>&1
    
    # 项目3
    export GITHUB_RUN_ID="$run_id_3"
    queue_manager 'queue_lock' 'join' '{"tag":"concurrent-test-3","email":"test3@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}' > /dev/null 2>&1
    
    log_info "=== Queue Status After Adding Items ==="
    get_issue_json_data
    
    # 验证队列中有3个项目
    queue_length=$(get_issue_json_data | jq -r '.queue | length')
    if [ "$queue_length" -eq 3 ]; then
        log_success "Queue contains 3 items as expected"
    else
        log_error "Queue should contain 3 items, but found $queue_length"
        return 1
    fi
    
    # 项目1获取锁（应该成功，因为它是第一个）- 使用直接调用避免长时间重试
    log_info "=== Step 1: First item acquiring lock ==="
    export GITHUB_RUN_ID="$run_id_1"
    run_test "Concurrent - First Item Acquire Lock" \
        "source .github/workflows/scripts/queue-manager.sh && _acquire_build_lock" \
        0 30
    
    log_info "=== Queue Status After First Item Acquired Lock ==="
    get_issue_json_data
    
    # 验证第一个项目获得了锁
    build_locked_by=$(get_issue_json_data | jq -r '.build_locked_by')
    if [[ "$build_locked_by" == *"concurrent_test_1"* ]]; then
        log_success "First item successfully acquired the build lock"
    else
        log_error "First item should have acquired the lock, but build_locked_by is: $build_locked_by"
        return 1
    fi
    
    # 项目2和项目3同时尝试获取锁（应该失败，因为锁已被占用）
    log_info "=== Step 2: Second and third items attempting to acquire lock concurrently ==="
    
    # 项目2尝试获取锁
    export GITHUB_RUN_ID="$run_id_2"
    run_test "Concurrent - Second Item Attempt Acquire Lock" \
        "source .github/workflows/scripts/queue-manager.sh && _acquire_build_lock" \
        1 30
    
    # 项目3尝试获取锁
    export GITHUB_RUN_ID="$run_id_3"
    run_test "Concurrent - Third Item Attempt Acquire Lock" \
        "source .github/workflows/scripts/queue-manager.sh && _acquire_build_lock" \
        1 30
    
    log_info "=== Queue Status After Concurrent Attempts ==="
    get_issue_json_data
    
    # 验证锁仍然被第一个项目持有
    build_locked_by=$(get_issue_json_data | jq -r '.build_locked_by')
    if [[ "$build_locked_by" == *"concurrent_test_1"* ]]; then
        log_success "Build lock still held by first item after concurrent attempts"
    else
        log_error "Build lock should still be held by first item, but build_locked_by is: $build_locked_by"
        return 1
    fi
    
    # 第一个项目释放锁
    log_info "=== Step 3: First item releasing lock ==="
    export GITHUB_RUN_ID="$run_id_1"
    run_test "Concurrent - First Item Release Lock" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'" \
        0 60
    
    log_info "=== Queue Status After First Item Released Lock ==="
    get_issue_json_data
    
    # 验证锁已释放，第一个项目已从队列中移除
    build_locked_by=$(get_issue_json_data | jq -r '.build_locked_by')
    queue_length=$(get_issue_json_data | jq -r '.queue | length')
    
    if [ "$build_locked_by" = "null" ] && [ "$queue_length" -eq 2 ]; then
        log_success "Lock released and first item removed from queue"
    else
        log_error "Lock should be released and first item removed, but build_locked_by=$build_locked_by, queue_length=$queue_length"
        return 1
    fi
    
    # 项目2现在应该能获取锁（因为它现在是队列第一个）
    log_info "=== Step 4: Second item acquiring lock (now first in queue) ==="
    export GITHUB_RUN_ID="$run_id_2"
    run_test "Concurrent - Second Item Acquire Lock After First Released" \
        "source .github/workflows/scripts/queue-manager.sh && _acquire_build_lock" \
        0 30
    
    log_info "=== Queue Status After Second Item Acquired Lock ==="
    get_issue_json_data
    
    # 验证第二个项目获得了锁
    build_locked_by=$(get_issue_json_data | jq -r '.build_locked_by')
    if [[ "$build_locked_by" == *"concurrent_test_2"* ]]; then
        log_success "Second item successfully acquired the build lock"
    else
        log_error "Second item should have acquired the lock, but build_locked_by is: $build_locked_by"
        return 1
    fi
    
    # 项目2释放锁
    log_info "=== Step 5: Second item releasing lock ==="
    export GITHUB_RUN_ID="$run_id_2"
    run_test "Concurrent - Second Item Release Lock" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'" \
        0 60
    
    log_info "=== Queue Status After Second Item Released Lock ==="
    get_issue_json_data
    
    # 项目3现在应该能获取锁
    log_info "=== Step 6: Third item acquiring lock (now first in queue) ==="
    export GITHUB_RUN_ID="$run_id_3"
    run_test "Concurrent - Third Item Acquire Lock After Second Released" \
        "source .github/workflows/scripts/queue-manager.sh && _acquire_build_lock" \
        0 30
    
    log_info "=== Queue Status After Third Item Acquired Lock ==="
    get_issue_json_data
    
    # 项目3释放锁
    log_info "=== Step 7: Third item releasing lock ==="
    export GITHUB_RUN_ID="$run_id_3"
    run_test "Concurrent - Third Item Release Lock" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'" \
        0 60
    
    log_info "=== Final Queue Status ==="
    get_issue_json_data
    
    # 验证最终状态：队列为空，锁已释放
    build_locked_by=$(get_issue_json_data | jq -r '.build_locked_by')
    queue_length=$(get_issue_json_data | jq -r '.queue | length')
    
    if [ "$build_locked_by" = "null" ] && [ "$queue_length" -eq 0 ]; then
        log_success "Final state correct: queue empty and lock released"
    else
        log_error "Final state should be empty queue and released lock, but build_locked_by=$build_locked_by, queue_length=$queue_length"
        return 1
    fi
}

# 主测试函数
main() {
    echo "========================================"
    echo "    Concurrent Build Lock Tests"
    echo "========================================"
    
    # 设置测试环境
    log_step "Setting up test environment..."
    setup_test_env
    
    # 运行并发轮询测试
    test_concurrent_polling
    
    # 清理测试环境
    log_step "Cleaning up test environment..."
    log_success "Test environment cleanup completed"
    
    # 显示测试结果
    echo "========================================"
    echo "CONCURRENT TEST RESULTS"
    echo "========================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo "========================================"
        log_success "All concurrent tests passed! 🎉"
        echo "========================================"
        exit 0
    else
        echo "========================================"
        log_error "Some concurrent tests failed! ❌"
        echo "========================================"
        exit 1
    fi
}

# 运行主函数
main "$@"
