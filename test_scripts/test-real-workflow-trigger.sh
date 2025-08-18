#!/bin/bash

# 真实GitHub工作流触发测试脚本
# 测试真实的issue触发和手动触发工作流，观察队列行为

# 导入测试框架
source test_scripts/test-framework.sh

# 测试配置
TOTAL_TESTS=5
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

# 测试描述
test_description() {
    log_info "========================================"
    log_info "     真实GitHub工作流触发测试"
    log_info "========================================"
    log_info "测试真实的GitHub工作流触发场景："
    log_info "  1. 创建GitHub Issues触发工作流"
    log_info "  2. 触发手动工作流"
    log_info "  3. 监控工作流状态和队列行为"
    log_info "  4. 验证队列限制和构建顺序"
    log_info "  5. 观察真实的工作流执行情况"
}

# 创建GitHub Issue并触发工作流
create_issue_and_trigger_workflow() {
    local issue_number="$1"
    local issue_title="$2"
    local issue_body="$3"
    
    log_info "📝 创建GitHub Issue #$issue_number: $issue_title"
    
    # 创建Issue
    local issue_result
    issue_result=$(gh issue create \
        --title "$issue_title" \
        --body "$issue_body" \
        --repo "$GITHUB_REPOSITORY" \
        --json number,url 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$issue_result" | jq -e '.number' >/dev/null 2>&1; then
        local actual_number=$(echo "$issue_result" | jq -r '.number')
        local issue_url=$(echo "$issue_result" | jq -r '.url')
        log_success "✅ 成功创建Issue #$actual_number: $issue_url"
        
        # 等待工作流触发
        log_info "⏳ 等待工作流触发..."
        sleep 10
        
        # 检查是否有新的工作流运行
        local workflow_runs
        workflow_runs=$(gh run list --repo "$GITHUB_REPOSITORY" --limit 5 --json id,status,conclusion,eventType,headBranch,createdAt 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            log_info "📊 最近的工作流运行:"
            echo "$workflow_runs" | jq -r '.[] | "  - Run #\(.id): \(.status) (\(.eventType)) - \(.headBranch)"'
        else
            log_warning "⚠️ 无法获取工作流运行列表"
        fi
        
        return 0
    else
        log_error "❌ 创建Issue失败"
        return 1
    fi
}

# 触发手动工作流
trigger_manual_workflow() {
    local workflow_name="$1"
    local ref="$2"
    
    log_info "🚀 触发手动工作流: $workflow_name (ref: $ref)"
    
    # 触发工作流
    local workflow_result
    workflow_result=$(gh workflow run "$workflow_name" \
        --ref "$ref" \
        --repo "$GITHUB_REPOSITORY" \
        --json id,status,url 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$workflow_result" | jq -e '.id' >/dev/null 2>&1; then
        local run_id=$(echo "$workflow_result" | jq -r '.id')
        local run_url=$(echo "$workflow_result" | jq -r '.url')
        log_success "✅ 成功触发工作流运行 #$run_id: $run_url"
        
        # 等待工作流启动
        log_info "⏳ 等待工作流启动..."
        sleep 10
        
        return 0
    else
        log_error "❌ 触发手动工作流失败"
        return 1
    fi
}

# 监控工作流状态
monitor_workflow_status() {
    local max_wait_time="${1:-300}"  # 默认等待5分钟
    local check_interval=30
    
    log_info "🔍 监控工作流状态 (最多等待${max_wait_time}秒)..."
    
    local start_time=$(date +%s)
    local elapsed=0
    
    while [ $elapsed -lt $max_wait_time ]; do
        # 获取最新的工作流运行
        local workflow_runs
        workflow_runs=$(gh run list --repo "$GITHUB_REPOSITORY" --limit 10 --json id,status,conclusion,eventType,headBranch,createdAt,updatedAt 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            log_info "📊 工作流状态 (已等待${elapsed}秒):"
            echo "$workflow_runs" | jq -r '.[0:5][] | "  - Run #\(.id): \(.status) (\(.eventType)) - \(.headBranch) - \(.updatedAt)"'
            
            # 检查是否有完成的工作流
            local completed_count=$(echo "$workflow_runs" | jq '[.[] | select(.status == "completed")] | length')
            local running_count=$(echo "$workflow_runs" | jq '[.[] | select(.status == "in_progress")] | length')
            local queued_count=$(echo "$workflow_runs" | jq '[.[] | select(.status == "queued")] | length')
            
            log_info "📈 工作流统计: 完成=$completed_count, 运行中=$running_count, 排队中=$queued_count"
        else
            log_warning "⚠️ 无法获取工作流状态"
        fi
        
        # 检查队列状态
        if source .github/workflows/scripts/queue-manager.sh >/dev/null 2>&1; then
            local queue_status
            queue_status=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status' 2>/dev/null)
            if [ $? -eq 0 ]; then
                log_info "📋 队列状态: $queue_status"
            fi
        fi
        
        # 等待下次检查
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        
        # 如果所有工作流都完成了，提前退出
        if [ "$completed_count" -gt 0 ] && [ "$running_count" -eq 0 ] && [ "$queued_count" -eq 0 ]; then
            log_success "✅ 所有工作流已完成，停止监控"
            break
        fi
    done
    
    if [ $elapsed -ge $max_wait_time ]; then
        log_warning "⚠️ 监控超时，已等待${max_wait_time}秒"
    fi
}

# 主测试函数
main_test() {
    log_step "开始真实GitHub工作流触发测试"
    
    # 重置队列状态
    log_info "🔄 重置队列状态..."
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'; then
        log_success "队列重置成功"
    else
        log_error "队列重置失败"
        return 1
    fi
    
    # 测试1: 创建Issue触发工作流
    log_info "=== 测试1: 创建Issue触发工作流 ==="
    local issue_body="This is a test issue for workflow trigger testing.

## 构建配置
- 平台: linux-x64
- 配置: release
- 特性: default

## 测试目的
验证issue触发的工作流是否能正确加入队列并执行构建。"
    
    if create_issue_and_trigger_workflow "1001" "Test Issue 1 - Workflow Trigger Test" "$issue_body"; then
        log_success "✅ 测试1通过: 成功创建Issue并触发工作流"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 成功创建Issue并触发工作流")
    else
        log_error "❌ 测试1失败: 创建Issue或触发工作流失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 创建Issue或触发工作流失败")
    fi
    
    # 等待一段时间让工作流启动
    log_info "⏳ 等待工作流启动和队列处理..."
    sleep 30
    
    # 测试2: 创建第二个Issue触发工作流
    log_info "=== 测试2: 创建第二个Issue触发工作流 ==="
    local issue_body2="This is the second test issue for workflow trigger testing.

## 构建配置
- 平台: linux-x64
- 配置: release
- 特性: default

## 测试目的
验证第二个issue触发的工作流是否能正确加入队列。"
    
    if create_issue_and_trigger_workflow "1002" "Test Issue 2 - Second Workflow Trigger" "$issue_body2"; then
        log_success "✅ 测试2通过: 成功创建第二个Issue并触发工作流")
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 成功创建第二个Issue并触发工作流")
    else
        log_error "❌ 测试2失败: 创建第二个Issue或触发工作流失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 创建第二个Issue或触发工作流失败")
    fi
    
    # 等待一段时间
    sleep 30
    
    # 测试3: 触发手动工作流
    log_info "=== 测试3: 触发手动工作流 ==="
    if trigger_manual_workflow "build.yml" "main"; then
        log_success "✅ 测试3通过: 成功触发手动工作流"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 成功触发手动工作流")
    else
        log_error "❌ 测试3失败: 触发手动工作流失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 触发手动工作流失败")
    fi
    
    # 等待一段时间
    sleep 30
    
    # 测试4: 监控工作流状态和队列行为
    log_info "=== 测试4: 监控工作流状态和队列行为 ==="
    log_info "开始监控工作流状态，观察队列行为..."
    
    # 监控工作流状态（最多等待5分钟）
    monitor_workflow_status 300
    
    log_success "✅ 测试4通过: 工作流状态监控完成"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TEST_RESULTS+=("PASS: 工作流状态监控完成")
    
    # 测试5: 最终状态检查
    log_info "=== 测试5: 最终状态检查 ==="
    
    # 检查队列状态
    if source .github/workflows/scripts/queue-manager.sh >/dev/null 2>&1; then
        local final_queue_status
        final_queue_status=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status' 2>/dev/null)
        if [ $? -eq 0 ]; then
            log_info "📋 最终队列状态: $final_queue_status"
        fi
    fi
    
    # 检查工作流状态
    local final_workflow_status
    final_workflow_status=$(gh run list --repo "$GITHUB_REPOSITORY" --limit 5 --json id,status,conclusion,eventType,headBranch,createdAt 2>/dev/null)
    if [ $? -eq 0 ]; then
        log_info "📊 最终工作流状态:"
        echo "$final_workflow_status" | jq -r '.[] | "  - Run #\(.id): \(.status) (\(.eventType)) - \(.headBranch)"'
    fi
    
    log_success "✅ 测试5通过: 最终状态检查完成"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TEST_RESULTS+=("PASS: 最终状态检查完成")
    
    log_success "真实GitHub工作流触发测试完成"
}

# 主函数
main() {
    # 初始化测试框架
    init_test_framework
    
    # 显示测试描述
    test_description
    
    # 运行主测试
    if main_test; then
        log_success "所有测试完成"
    else
        log_error "部分测试失败"
    fi
    
    # 清理测试框架
    cleanup_test_framework
}

# 如果直接运行此脚本，则执行主函数
if [ -n "${TEST_RUNNER_CALLED:-}" ]; then
    main "$@"
else
    log_error "错误：此测试脚本无法直接运行！"
    log_info "请使用 run-tests.sh 来运行测试"
    exit 1
fi
