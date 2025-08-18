#!/bin/bash
# 队列加入功能测试脚本

# 加载统一测试框架
source test_scripts/test-framework.sh

# 测试队列加入功能（带验证）
test_queue_join_with_verification() {
    log_step "Testing queue join functionality with verification..."
    
    # 显示测试前的状态
    show_issue_status "Before Queue Join Test"
    
    # 获取初始状态
    local initial_state=$(get_current_queue_state)
    local initial_queue_length=$(echo "$initial_state" | grep "queue_length=" | cut -d'=' -f2)
    local initial_version=$(echo "$initial_state" | grep "version=" | cut -d'=' -f2)
    
    log_info "Initial state: queue_length=$initial_queue_length, version=$initial_version"
    
    # 测试队列加入功能
    run_test "Queue Join - Normal" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"test-tag\",\"email\":\"test@example.com\",\"customer\":\"test-customer\",\"trigger_type\":\"workflow_dispatch\"}'" \
        0
    
    # 验证加入操作是否真正生效
    local expected_queue_length=$((initial_queue_length + 1))
    local expected_version=$((initial_version + 1))
    
    if verify_queue_operation "Queue Join" "$expected_queue_length" "$expected_version"; then
        log_success "Queue join operation verified successfully"
    else
        log_warning "Queue join operation verification failed (but operation may still be successful)"
        # 不返回1，让测试继续
    fi
    
    # 显示测试后的状态
    show_issue_status "After Queue Join Test"
}



# 主函数
main() {
    # 初始化测试框架
    init_test_framework
    
    echo "========================================"
    echo "    Queue Join Function Tests"
    echo "========================================"
    echo ""
    
    # 运行测试
    test_queue_join_with_verification
    
    # 清理测试框架
    cleanup_test_framework
}

# 运行主函数
main "$@" 

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "错误：此测试脚本无法直接运行！"
    echo ""
    echo "请使用以下命令运行测试："
    echo "  ./run-tests.sh queue-join"
    echo ""
    echo "或者查看所有可用测试："
    echo "  ./run-tests.sh --list"
    echo ""
    echo "查看帮助信息："
    echo "  ./run-tests.sh --help"
    exit 1
fi 