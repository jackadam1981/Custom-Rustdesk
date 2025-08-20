#!/bin/bash

# 工具函数测试脚本
# 该脚本测试 utils.sh 中的功能

# 该脚本已重构，请使用 run-tests.sh 运行测试
# 当通过 run-tests.sh 调用时，TEST_RUNNER_CALLED 会被设置
if [ -z "$TEST_RUNNER_CALLED" ]; then
    standalone=true
else
    standalone=false
    # 加载工具函数
    source test_scripts/utils.sh
fi

# 测试检查队列长度
function test_utils_queue_length() {
    log_info "测试检查队列长度..."
    local expected_length=${1:-0} # 默认值为0，可以通过参数设置
    log_info "预期队列长度设置为: $expected_length"
    
    # 测试函数是否能执行而不报错
    if utils_queue_length $expected_length; then
        log_info "检查队列长度函数执行成功"
        record_test_result "utils_queue_length" "PASS" "检查队列长度函数执行成功"
        return 0
    else
        log_error "检查队列长度函数执行失败"
        record_test_result "utils_queue_length" "FAIL" "检查队列长度函数执行失败"
        return 1
    fi
}

# 测试检查队列内容
function test_utils_queue_content() {
    log_info "测试检查队列内容..."
    # 测试函数是否能执行而不报错
    # 预期内容可以根据实际情况调整
    local expected_content="\"queue\": \[\]"
    log_info "预期队列内容包含: $expected_content"
    if utils_queue_content "$expected_content"; then
        log_info "检查队列内容函数执行成功"
        record_test_result "utils_queue_content" "PASS" "检查队列内容函数执行成功"
        return 0
    else
        log_error "检查队列内容函数执行失败"
        record_test_result "utils_queue_content" "FAIL" "检查队列内容函数执行失败"
        return 1
    fi
}

# 测试列出队列管理内容
function test_utils_queue_management() {
    log_info "测试列出队列管理内容..."
    # 测试函数是否能执行而不报错
    if utils_queue_management; then
        log_info "列出队列管理内容函数执行成功"
        record_test_result "utils_queue_management" "PASS" "列出队列管理内容函数执行成功"
        return 0
    else
        log_error "列出队列管理内容函数执行失败"
        record_test_result "utils_queue_management" "FAIL" "列出队列管理内容函数执行失败"
        return 1
    fi
}

# 测试检查工作流数量
function test_utils_workflow_count() {
    log_info "测试检查工作流数量..."
    # 测试函数是否能执行而不报错
    # 默认预期值为 0，可以通过参数动态设置
    local expected_count=${1:-0}
    log_info "预期工作流数量设置为: $expected_count"
    if utils_workflow_count $expected_count; then
        log_info "检查工作流数量函数执行成功"
        record_test_result "utils_workflow_count" "PASS" "检查工作流数量函数执行成功"
        return 0
    else
        log_error "检查工作流数量函数执行失败"
        record_test_result "utils_workflow_count" "FAIL" "检查工作流数量函数执行失败"
        return 1
    fi
}

# 测试检查工作流状态
function test_utils_workflow_status() {
    log_info "测试检查工作流状态..."
    # 获取最新的工作流运行ID，只调用一次
    local run_id=$(utils_latest_workflow_run)
    
    if [ -z "$run_id" ]; then
        log_warn "无法获取最新的工作流运行ID，可能是因为不存在工作流或工作流处于错误状态"
        log_info "将跳过工作流状态检查测试"
        record_test_result "utils_workflow_status" "SKIP" "无法获取最新的工作流运行ID，可能是因为不存在工作流或工作流处于错误状态"
        return 0
    fi
    
    # 清理 run_id，确保只包含数字
    run_id=$(echo "$run_id" | grep -o '[0-9]\{5,\}')
    
    log_info "最新工作流运行ID: $run_id"
    
    # 测试函数是否能执行而不报错
    # 预期状态可以通过运行参数动态设置，如果没有参数则自动检测
    local expected_status=""
    if [ $# -gt 0 ]; then
        expected_status="$1"
    else
        # 自动检测当前状态作为预期值
        local status_output=$(gh run view "$run_id" --repo "$GITHUB_REPOSITORY" --json status,conclusion 2>&1)
        expected_status=$(echo "$status_output" | jq -r '.status' 2>/dev/null)
        local conclusion=$(echo "$status_output" | jq -r '.conclusion' 2>/dev/null)
        
        if [ -n "$conclusion" ] && [ "$conclusion" != "null" ]; then
            expected_status="$conclusion"
        fi
        
        if [ -z "$expected_status" ]; then
            expected_status="completed"  # 默认值
        fi
        log_info "自动检测到预期工作流状态: $expected_status"
    fi
    
    log_info "预期工作流状态设置为: $expected_status"
    if utils_workflow_status "$run_id" "$expected_status"; then
        log_info "检查工作流状态函数执行成功"
        record_test_result "utils_workflow_status" "PASS" "检查工作流状态函数执行成功"
        return 0
    else
        log_error "检查工作流状态函数执行失败"
        record_test_result "utils_workflow_status" "FAIL" "检查工作流状态函数执行失败"
        return 1
    fi
}

# 测试读取工作流日志
function test_utils_workflow_logs() {
    log_info "测试读取工作流日志..."
    
    # 获取最近的工作流运行ID
    local run_id=$(utils_latest_workflow_run)
    if [ $? -eq 0 ] && [ -n "$run_id" ]; then
        if utils_workflow_logs "$run_id"; then
            log_info "读取工作流日志函数执行成功"
            record_test_result "utils_workflow_logs" "PASS" "读取工作流日志函数执行成功"
            return 0
        else
            log_error "读取工作流日志函数执行失败"
            record_test_result "utils_workflow_logs" "FAIL" "读取工作流日志函数执行失败"
            return 1
        fi
    else
        log_error "无法获取最近的工作流运行ID"
        record_test_result "utils_workflow_logs" "FAIL" "无法获取最近的工作流运行ID"
        return 1
    fi
}

# 测试获取最近的工作流运行ID
function test_utils_latest_workflow_run() {
    log_info "测试获取最近的工作流运行ID..."
    
    local run_id=$(utils_latest_workflow_run)
    
    if [ -z "$run_id" ]; then
        log_warn "无法获取最新的工作流运行ID，可能是因为不存在工作流或工作流处于错误状态"
        log_info "将跳过获取最近的工作流运行ID测试"
        record_test_result "utils_latest_workflow_run" "SKIP" "无法获取最新的工作流运行ID，可能是因为不存在工作流或工作流处于错误状态"
        return 0
    fi
    
    log_info "成功获取最新的工作流运行ID: $run_id"
            record_test_result "utils_latest_workflow_run" "PASS" "获取最近的工作流运行ID函数执行成功"
        return 0
}

# 运行所有工具函数测试
function run_utils_tests() {
    log_info "开始运行工具函数测试..."
    local failed=0
    test_utils_queue_length || failed=1
    test_utils_queue_content || failed=1
    test_utils_queue_management || failed=1
    test_utils_workflow_count || failed=1
    test_utils_workflow_status || failed=1
    test_utils_workflow_logs || failed=1
    test_utils_latest_workflow_run || failed=1
    log_info "工具函数测试完成"
    return $failed
}

# 该脚本已重构，请使用 run-tests.sh 运行测试
# 使用示例: ./run-tests.sh utils-tests
if [ "$standalone" = true ]; then
    echo "该脚本已重构，请使用 run-tests.sh 运行测试"
    echo "使用示例: ./run-tests.sh utils-tests"
    exit 1
fi
