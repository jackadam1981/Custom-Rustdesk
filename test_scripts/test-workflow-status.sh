#!/bin/bash

# 工作流状态测试脚本
# 该脚本测试检查工作流状态的功能

# 加载测试框架
if [ -z "$TEST_RUNNER_CALLED" ]; then
    source test_scripts/test-framework.sh
    standalone=true
else
    standalone=false
fi

# 测试检查工作流状态
function test_check_workflow_status() {
    log_info "测试检查工作流状态..."
    
    # 获取最新的工作流运行ID
    local run_id=$(get_latest_workflow_run_id "manual-build.yml")
    log_debug "获取最新工作流运行ID: $run_id"
    
    if [ -z "$run_id" ]; then
        log_error "无法获取最新的工作流运行ID"
        record_test_result "check_workflow_status" "FAIL" "无法获取最新的工作流运行ID"
        return 1
    fi
    
    log_info "最新工作流运行ID: $run_id"
    
    # 检查工作流状态
    local status=$(check_workflow_status "$run_id" "completed")
    log_debug "检查工作流状态结果: $status"
    
    if [ $? -eq 0 ]; then
        log_info "工作流状态检查成功"
        record_test_result "check_workflow_status" "PASS" "工作流状态检查成功"
        return 0
    else
        log_error "工作流状态检查失败"
        record_test_result "check_workflow_status" "FAIL" "工作流状态检查失败"
        return 1
    fi
}

# 运行所有工作流状态测试
function run_workflow_status_tests() {
    log_info "开始运行工作流状态测试..."
    test_check_workflow_status
    local result=$?
    log_info "工作流状态测试完成"
    return $result
}

# 如果作为独立脚本运行
if [ "$standalone" = true ]; then
    init_test_framework
    if setup_test_environment; then
        run_workflow_status_tests
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
