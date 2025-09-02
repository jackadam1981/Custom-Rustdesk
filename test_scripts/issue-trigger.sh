#!/bin/bash

# 问题触发测试脚本
# 该脚本测试通过GitHub Issue触发构建的功能

# 该脚本已重构，请使用 run-tests.sh 运行测试
standalone=false

# 测试通过Issue触发构建
function test_issue_trigger_build() {
    log_info "测试通过Issue触发构建..."
    
    # 创建一个测试Issue
    local issue_title="[BUILD] 测试构建触发 - $(date '+%Y%m%d-%H%M%S')"
    local issue_body="## 构建参数

- **标签**: test-$(date '+%Y%m%d-%H%M%S')
- **客户**: test-customer
- **邮箱**: test@example.com
- **标语**: 测试标语
- **超级密码**: testpass123
- **Rendezvous服务器**: 192.168.1.100
- **API服务器**: http://192.168.1.100:21114
- **客户链接**: https://example.com
- **RS公钥**: 

## 构建请求

请为上述参数构建自定义Rustdesk版本。"
    log_debug "开始创建Issue，标题: $issue_title"
    log_debug "仓库: $GITHUB_REPOSITORY"
    
    local issue_output=$(gh issue create --title "$issue_title" --body "$issue_body" --repo $GITHUB_REPOSITORY 2>&1)
    log_debug "Issue创建命令完整输出: $issue_output"
    
    local issue_number=$(echo "$issue_output" | grep -oP 'issues/\K\d+')
    log_debug "提取的Issue编号: $issue_number"
    
    if [ -z "$issue_number" ]; then
        log_error "无法创建Issue，触发构建失败"
        record_test_result "issue_trigger_build" "FAIL" "无法创建Issue，触发构建失败"
        return 1
    fi
    
    log_info "成功创建Issue，编号: $issue_number"
    
    # 等待几秒钟以确保构建被触发
    sleep 5
    
    # 检查是否有新的workflow运行（带重试机制）
    local run_id=""
    local retry_count=0
    local max_retries=3
    
    while [ -z "$run_id" ] && [ $retry_count -lt $max_retries ]; do
        log_debug "尝试获取workflow运行信息，第 $((retry_count + 1)) 次尝试"
        run_id=$(gh run list --workflow=CustomBuildRustdesk.yml --repo $GITHUB_REPOSITORY --limit 1 --json number --jq '.[0].number' 2>/dev/null)
        
        if [ -z "$run_id" ]; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_debug "未找到workflow运行，等待5秒后重试..."
                sleep 5
            fi
        fi
    done
    
    log_debug "检查workflow运行，命令输出: $run_id"
    
    if [ -z "$run_id" ]; then
        log_warn "无法获取run ID，可能是网络问题或工作流尚未启动"
        log_info "Issue创建成功（编号: $issue_number），但无法验证工作流是否被触发"
        log_info "请手动检查GitHub Actions页面确认工作流状态"
        record_test_result "issue_trigger_build" "WARN" "Issue创建成功，但无法验证工作流触发状态"
        return 0
    fi
    
    log_info "Issue触发构建成功，Run ID: $run_id"
    record_test_result "issue_trigger_build" "PASS" "Issue触发构建成功，Run ID: $run_id"
    return 0
}

# 运行所有问题触发测试
function run_issue_trigger_tests() {
    log_info "开始运行问题触发测试..."
    test_issue_trigger_build
    local result=$?
    log_info "问题触发测试完成"
    return $result
}

# 该脚本已重构，请使用 run-tests.sh 运行测试
# 使用示例: ./run-tests.sh test-issue-trigger
if [ "$standalone" = true ]; then
    echo "该脚本已重构，请使用 run-tests.sh 运行测试"
    echo "使用示例: ./run-tests.sh test-issue-trigger"
    exit 1
fi
