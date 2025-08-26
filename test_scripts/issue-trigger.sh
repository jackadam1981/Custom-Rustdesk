#!/bin/bash

# 问题触发测试脚本
# 该脚本测试通过GitHub Issue触发构建的功能

# 该脚本已重构，请使用 run-tests.sh 运行测试
# 当通过 run-tests.sh 调用时，TEST_RUNNER_CALLED 会被设置
if [ -z "$TEST_RUNNER_CALLED" ]; then
    standalone=true
else
    standalone=false
    # 加载工具函数
    source test_scripts/utils.sh
fi

# 测试通过Issue触发构建
function test_issue_trigger_build() {
    log_info "测试通过Issue触发构建..."
    
    # 创建一个包含构建参数的测试Issue
    local issue_title="[BUILD] 测试构建触发 - $(date '+%Y%m%d-%H%M%S')"
    local issue_body="这是一个用于测试构建触发的Issue。

构建参数：
tag: test-issue-$(date '+%Y%m%d-%H%M%S')
customer: test-customer
email: test@example.com
super_password: test123
rendezvous_server: 192.168.1.100
api_server: http://192.168.1.100:21114
slogan: Issue Test Build
customer_link: https://example.com/test
enable_debug: true"
    local issue_number=$(gh issue create --title "$issue_title" --body "$issue_body" --repo $GITHUB_REPOSITORY 2>&1 | grep -oP 'issues/\K\d+')
    
    log_debug "尝试创建Issue，命令输出: $issue_number"
    
    if [ -z "$issue_number" ]; then
        log_error "无法创建Issue，触发构建失败"
        record_test_result "issue_trigger_build" "FAIL" "无法创建Issue，触发构建失败"
        return 1
    fi
    
    log_info "成功创建Issue，编号: $issue_number"
    
    # 等待几秒钟以确保构建被触发
    sleep 5
    
    # 检查是否有新的workflow运行
    local run_id=$(gh run list --workflow=CustomBuildRustdesk.yml --repo $GITHUB_REPOSITORY --limit 1 --json databaseId --jq '.[0].databaseId')
    
    log_debug "检查workflow运行，命令输出: $run_id"
    
    if [ -z "$run_id" ]; then
        log_error "无法获取run ID，Issue触发构建失败"
        record_test_result "issue_trigger_build" "FAIL" "无法获取run ID，Issue触发构建失败"
        return 1
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
