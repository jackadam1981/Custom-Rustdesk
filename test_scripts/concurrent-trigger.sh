#!/bin/bash

# 真实工作流触发测试脚本
# 该脚本测试真实触发工作流的功能

# 加载测试框架
if [ -z "$TEST_RUNNER_CALLED" ]; then
    source test_scripts/framework.sh
    standalone=true
else
    standalone=false
fi

# 测试真实工作流触发
function test_real_workflow_trigger() {
    log_info "测试真实工作流触发..."
    
    # 使用gh命令触发真实工作流
    local run_id=$(gh workflow run manual-build.yml --repo $GITHUB_REPOSITORY -f build_type=release 2>&1 | grep -oP 'run ID \K\d+')
    log_debug "尝试触发真实工作流，命令输出: $run_id"
    
    if [ -z "$run_id" ]; then
        log_error "无法获取run ID，真实工作流触发失败"
        record_test_result "real_workflow_trigger" "FAIL" "无法获取run ID，真实工作流触发失败"
        return 1
    fi
    
    log_info "真实工作流触发成功，Run ID: $run_id"
    record_test_result "real_workflow_trigger" "PASS" "真实工作流触发成功，Run ID: $run_id"
    return 0
}

# 运行所有真实工作流触发测试
function run_real_workflow_trigger_tests() {
    log_info "开始运行真实工作流触发测试..."
    test_real_workflow_trigger
    local result=$?
    log_info "真实工作流触发测试完成"
    return $result
}

# 如果作为独立脚本运行
if [ "$standalone" = true ]; then
    init_test_framework
    if setup_test_environment; then
        run_real_workflow_trigger_tests
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
