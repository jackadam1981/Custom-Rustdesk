#!/bin/bash

# 队列状态测试脚本
# 该脚本测试检查队列状态的功能

# 加载测试框架
if [ -z "$TEST_RUNNER_CALLED" ]; then
    source test_scripts/test-framework.sh
    standalone=true
else
    standalone=false
fi

# 测试检查队列状态
function test_check_queue_status() {
    log_info "测试检查队列状态..."
    
    # 检查队列长度
    local queue_length_result=$(check_queue_length 0)
    log_debug "检查队列长度结果: $queue_length_result"
    
    if [ $? -eq 0 ]; then
        log_info "队列长度检查成功"
        record_test_result "check_queue_status_length" "PASS" "队列长度检查成功"
    else
        log_error "队列长度检查失败"
        record_test_result "check_queue_status_length" "FAIL" "队列长度检查失败"
        return 1
    fi
    
    # 列出队列管理内容
    local queue_management_result=$(list_queue_management)
    log_debug "列出队列管理内容结果: $queue_management_result"
    
    if [ $? -eq 0 ]; then
        log_info "队列管理内容列出成功"
        record_test_result "check_queue_status_management" "PASS" "队列管理内容列出成功"
    else
        log_error "队列管理内容列出失败"
        record_test_result "check_queue_status_management" "FAIL" "队列管理内容列出失败"
        return 1
    fi
    
    return 0
}

# 运行所有队列状态测试
function run_queue_status_tests() {
    log_info "开始运行队列状态测试..."
    test_check_queue_status
    local result=$?
    log_info "队列状态测试完成"
    return $result
}

# 如果作为独立脚本运行
if [ "$standalone" = true ]; then
    init_test_framework
    if setup_test_environment; then
        run_queue_status_tests
        show_test_results
    else
        log_error "测试环境设置失败，退出测试"
        exit 1
    fi
    cleanup_test_framework
    if [ $TEST_FAIL_COUNT -gt 0 ]; then
        exit 1
    fi
    exit 0
fi
