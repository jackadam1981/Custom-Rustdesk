#!/bin/bash

# 真实工作流触发测试脚本
# 该脚本测试真实触发工作流的功能

# 该脚本已重构，请使用 run-tests.sh 运行测试
standalone=true

# 测试真实工作流触发
function test_real_workflow_trigger() {
    log_info "测试真实工作流触发..."
    
    # 使用gh命令触发真实工作流
    local run_id=$(gh workflow run CustomBuildRustdesk.yml --repo $GITHUB_REPOSITORY -f tag="concurrent-test-$(date +%Y%m%d-%H%M%S)" -f customer="concurrent-test" -f email="test@example.com" -f enable_debug="true" 2>&1 | grep -oP 'run ID \K\d+')
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

# 该脚本已重构，请使用 run-tests.sh 运行测试
# 使用示例: ./run-tests.sh test-concurrent-trigger
if [ "$standalone" = true ]; then
    echo "该脚本已重构，请使用 run-tests.sh 运行测试"
    echo "使用示例: ./run-tests.sh test-concurrent-trigger"
    exit 1
fi
