#!/bin/bash

# 手动触发测试脚本
# 该脚本测试手动触发构建的功能

# 该脚本已重构，请使用 run-tests.sh 运行测试
standalone=true

# 测试手动触发构建
function test_manual_trigger_build() {
    log_info "测试手动触发构建..."
    
    # 使用gh命令触发构建
    local run_id=$(gh workflow run manual-build.yml --repo $GITHUB_REPOSITORY -f build_type=release 2>&1 | grep -oP 'run ID \K\d+')
    
    log_debug "尝试触发构建，命令输出: $run_id"
    
    if [ -z "$run_id" ]; then
        log_error "无法获取run ID，手动触发构建失败"
        record_test_result "manual_trigger_build" "FAIL" "无法获取run ID，手动触发构建失败"
        return 1
    fi
    
    log_info "手动触发构建成功，Run ID: $run_id"
    record_test_result "manual_trigger_build" "PASS" "手动触发构建成功，Run ID: $run_id"
    return 0
}


# 该脚本已重构，请使用 run-tests.sh 运行测试
# 使用示例: ./run-tests.sh test-manual-trigger
if [ "$standalone" = true ]; then
    echo "该脚本已重构，请使用 run-tests.sh 运行测试"
    echo "使用示例: ./run-tests.sh test-manual-trigger"
    exit 1
fi
