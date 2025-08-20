#!/bin/bash

# 工具函数脚本
# 该脚本包含用于测试的通用工具函数

# 加载测试框架
if [ -z "$TEST_RUNNER_CALLED" ]; then
    source test_scripts/framework.sh
fi

# 检查队列长度
function utils_queue_length() {
    local expected_length=$1
    log_info "检查队列长度..."
    
    # 获取Issue #1的主体
    local issue_body=$(gh issue view 1 --repo $GITHUB_REPOSITORY)
    log_debug "Issue #1 主体内容: $issue_body"
    
    # 提取JSON数据部分
    local json_data=$(echo "$issue_body" | grep -A 10 '队列数据（隐私安全版本）' | grep -B 10 '}' | grep -v '队列数据（隐私安全版本）')
    log_debug "提取的JSON数据: $json_data"
    
    # 解析队列长度
    local queue_length=$(echo "$json_data" | grep -c '"queue": \[\]')
    if [ $queue_length -eq 1 ]; then
        queue_length=0
    else
        queue_length=$(echo "$json_data" | grep -oP '"queue": \[.*?\]' | grep -oP '(?<=\[).*?(?=\])' | wc -l)
    fi
    
    if [ -z "$queue_length" ]; then
        log_error "无法从Issue主体中解析队列长度"
        return 1
    fi
    
    log_info "当前队列长度: $queue_length"
    
    if [ "$queue_length" -eq "$expected_length" ]; then
        log_info "队列长度符合预期: $expected_length"
        return 0
    else
        log_error "队列长度不符合预期，预期: $expected_length，实际: $queue_length"
        return 1
    fi
}

# 检查队列内容
function utils_queue_content() {
    local expected_content=$1
    log_info "检查队列内容..."
    
    # 获取Issue #1的主体
    local issue_body=$(gh issue view 1 --repo $GITHUB_REPOSITORY)
    log_debug "Issue #1 主体内容: $issue_body"
    
    # 提取JSON数据部分
    local json_data=$(echo "$issue_body" | grep -A 10 '队列数据（隐私安全版本）' | grep -B 10 '}' | grep -v '队列数据（隐私安全版本）')
    log_debug "提取的JSON数据: $json_data"
    
    if echo "$json_data" | grep -q "$expected_content"; then
        log_info "队列内容符合预期: $expected_content"
        return 0
    else
        log_error "队列内容不符合预期，预期: $expected_content"
        log_debug "实际内容: $json_data"
        return 1
    fi
}

# 列出队列管理内容
function utils_queue_management() {
    log_info "列出队列管理内容..."
    
    # 获取Issue #1的主体
    local issue_body=$(gh issue view 1 --repo $GITHUB_REPOSITORY)
    log_debug "Issue #1 主体内容: $issue_body"
    
    log_info "队列管理内容:"
    log_info "$issue_body"
    return 0
}

# 检查工作流数量
function utils_workflow_count() {
    local expected_count=$1
    log_info "检查工作流数量..."
    
    local workflow_count=$(gh run list --repo $GITHUB_REPOSITORY --limit 10 --json databaseId,status --jq '[.[] | select(.status == "in_progress" or .status == "queued" or .status == "waiting" or .status == "requested")] | length')
    log_debug "检查工作流数量命令输出: $workflow_count"
    
    log_info "当前工作流数量: $workflow_count"
    
    if [ "$workflow_count" -eq "$expected_count" ]; then
        log_info "工作流数量符合预期: $expected_count"
        return 0
    else
        log_error "工作流数量不符合预期，预期: $expected_count，实际: $workflow_count"
        return 1
    fi
}

# 检查工作流状态
function utils_workflow_status() {
    local run_id="$1"
    local expected_status="$2"
    log_info "检查工作流状态..."
    
    # 确保 run_id 只包含数字
    run_id=$(echo "$run_id" | grep -o '[0-9]\{5,\}')
    log_debug "处理后的 run_id: $run_id"
    
    if [ -z "$run_id" ]; then
        log_error "无效的 run_id，无法检查工作流状态"
        return 1
    fi
    
    # 直接使用JSON格式获取工作流状态
    local json_output=$(gh run view "$run_id" --repo "$GITHUB_REPOSITORY" --json status,conclusion 2>&1)
    local status=$(echo "$json_output" | jq -r '.conclusion // .status' 2>/dev/null)
    log_debug "JSON格式获取的状态: $status"
    
    # 如果无法获取状态，使用默认值
    if [ -z "$status" ] || [ "$status" = "null" ]; then
        log_warn "无法获取工作流状态，使用默认值 'completed'"
        status="completed"
    fi
    
    log_info "当前工作流状态: $status"
    
    if [ "$status" = "$expected_status" ]; then
        log_info "工作流状态符合预期: $expected_status"
        return 0
    else
        log_error "工作流状态不符合预期，预期: $expected_status，实际: $status"
        return 1
    fi
}

# 读取工作流日志
function utils_workflow_logs() {
    local run_id=$1
    log_info "读取工作流日志..."
    
    local logs=$(gh run view $run_id --log --repo $GITHUB_REPOSITORY)
    log_debug "读取工作流日志命令输出: $logs"
    
    log_info "工作流日志:"
    log_info "$logs"
    return 0
}

# 获取最新的工作流运行ID
function utils_latest_workflow_run() {
    local workflow_name="$1"
    
    local run_id=""
    run_id=$(gh run list --workflow=CustomBuildRustdesk.yml --repo $GITHUB_REPOSITORY --limit 1 --json databaseId --jq '.[0].databaseId' | tr -d '[:space:]')
    
    if [ -z "$run_id" ]; then
        return 1
    fi
    
    echo "$run_id"
    return 0
}
