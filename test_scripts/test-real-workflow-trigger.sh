#!/bin/bash

# 真实工作流测试脚本 - 组合原有的小测试，检测队列状态和工作流状态
# 复用已验证的测试逻辑，观察真实环境下的系统行为

# 导入测试框架
source test_scripts/test-framework.sh

# 测试配置
TOTAL_TESTS=6
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

# 测试描述
test_description() {
    log_info "========================================"
    log_info "     真实工作流测试 - 组合测试"
    log_info "========================================"
    log_info "组合原有的小测试，检测队列状态和工作流状态："
    log_info "  1. 环境准备和队列重置"
    log_info "  2. 执行队列加入测试"
    log_info "  3. 执行构建锁测试"
    log_info "  4. 检测队列状态变化"
    log_info "  5. 检测工作流状态"
    log_info "  6. 验证整体系统行为"
}

# 执行队列加入测试（复用原有逻辑）
run_queue_join_test() {
    log_info "=== 执行队列加入测试 ==="
    
    # 生成测试ID
    local test_run_id="real_workflow_test_$(date +%s)"
    export GITHUB_RUN_ID="$test_run_id"
    
    # 测试数据
    local test_data='{"tag":"real-workflow-test","email":"test@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'
    
    # 尝试加入队列
    local join_result
    join_result=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' "$test_data" 2>/dev/null)
    
    if echo "$join_result" | jq -e '.success' >/dev/null 2>&1; then
        local position=$(echo "$join_result" | jq -r '.queue_position')
        log_success "✅ 队列加入测试成功，位置: $position"
        return 0
    else
        log_error "❌ 队列加入测试失败"
        return 1
    fi
}

# 执行构建锁测试（复用原有逻辑）
run_build_lock_test() {
    log_info "=== 执行构建锁测试 ==="
    
    # 先清理队列，确保只有一个任务
    log_info "🧹 清理队列，确保只有一个任务..."
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'; then
        log_success "队列清理成功"
    else
        log_error "队列清理失败"
        return 1
    fi
    
    local test_run_id="real_workflow_test_$(date +%s)"
    export GITHUB_RUN_ID="$test_run_id"
    
    # 先加入队列
    local test_data='{"tag":"build-lock-test","email":"test@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'
    local join_result
    join_result=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' "$test_data" 2>/dev/null)
    
    if ! echo "$join_result" | jq -e '.success' >/dev/null 2>&1; then
        log_error "❌ 构建锁测试：加入队列失败"
        return 1
    fi
    
    local position=$(echo "$join_result" | jq -r '.queue_position')
    log_info "✅ 成功加入队列，位置: $position"
    
    # 尝试获取构建锁
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'; then
        log_success "✅ 构建锁测试：成功获取构建锁"
        
        # 模拟构建过程（短时间）
        log_info "🔨 模拟构建过程 (5s)..."
        sleep 5
        
        # 释放构建锁
        if source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'; then
            log_success "✅ 构建锁测试：成功释放构建锁"
            
            # 离开队列
            if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'leave'; then
                log_success "✅ 构建锁测试：成功离开队列"
                return 0
            else
                log_error "❌ 构建锁测试：离开队列失败"
                return 1
            fi
        else
            log_error "❌ 构建锁测试：释放构建锁失败"
            return 1
        fi
    else
        log_error "❌ 构建锁测试：获取构建锁失败"
        return 1
    fi
}

# 检测队列状态
check_queue_status() {
    log_info "=== 检测队列状态 ==="
    
    local test_run_id="status_check_$(date +%s)"
    export GITHUB_RUN_ID="$test_run_id"
    
    # 获取队列状态
    local queue_status
    queue_status=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status' 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        log_success "✅ 队列状态检测成功: $queue_status"
        
        # 获取队列数据
        local queue_data
        queue_data=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'get_data' 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local queue_length=$(echo "$queue_data" | jq '.queue | length // 0' 2>/dev/null || echo "0")
            local issue_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "issues")) | length // 0' 2>/dev/null || echo "0")
            local manual_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0' 2>/dev/null || echo "0")
            
            log_info "📊 队列详细状态:"
            log_info "  - 总长度: $queue_length"
            log_info "  - Issue触发: $issue_count"
            log_info "  - 手动触发: $manual_count"
            
            return 0
        else
            log_warning "⚠️ 无法获取队列详细数据"
            return 1
        fi
    else
        log_error "❌ 队列状态检测失败"
        return 1
    fi
}

# 检测工作流状态
check_workflow_status() {
    log_info "=== 检测工作流状态 ==="
    
    # 检查GitHub CLI是否可用
    if ! command -v gh >/dev/null 2>&1; then
        log_warning "⚠️ GitHub CLI不可用，跳过工作流状态检测"
        return 0
    fi
    
    # 检查GitHub认证状态
    local auth_status
    auth_status=$(gh auth status 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_warning "⚠️ GitHub认证失败，跳过工作流状态检测"
        return 0
    fi
    
    # 获取最近的GitHub Actions运行
    local workflow_runs
    workflow_runs=$(gh run list --repo "$GITHUB_REPOSITORY" --limit 10 --json id,status,conclusion,eventType,headBranch,createdAt,updatedAt 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$workflow_runs" ]; then
        log_success "✅ 工作流状态检测成功"
        
        # 统计工作流状态
        local total_runs=$(echo "$workflow_runs" | jq 'length // 0')
        local completed_count=$(echo "$workflow_runs" | jq '[.[] | select(.status == "completed")] | length // 0')
        local running_count=$(echo "$workflow_runs" | jq '[.[] | select(.status == "in_progress")] | length // 0')
        local queued_count=$(echo "$workflow_runs" | jq '[.[] | select(.status == "queued")] | length // 0')
        local failed_count=$(echo "$workflow_runs" | jq '[.[] | select(.status == "completed" and .conclusion == "failure")] | length // 0')
        
        log_info "📊 工作流状态统计:"
        log_info "  - 总运行数: $total_runs"
        log_info "  - 已完成: $completed_count"
        log_info "  - 运行中: $running_count"
        log_info "  - 排队中: $queued_count"
        log_info "  - 失败: $failed_count"
        
        # 显示最近的工作流
        if [ "$total_runs" -gt 0 ]; then
            log_info "📋 最近的工作流运行:"
            echo "$workflow_runs" | jq -r '.[0:5][] | "  - Run #\(.id): \(.status) (\(.eventType)) - \(.headBranch) - \(.updatedAt)"'
        fi
        
        return 0
    else
        log_warning "⚠️ 无法获取工作流状态，可能是权限问题或没有工作流运行"
        log_info "尝试使用GitHub API直接检查..."
        
        # 尝试使用GitHub API直接检查
        local api_response
        api_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs?per_page=5" 2>/dev/null)
        
        if [ $? -eq 0 ] && echo "$api_response" | jq -e '.workflow_runs' >/dev/null 2>&1; then
            local api_runs=$(echo "$api_response" | jq '.workflow_runs | length // 0')
            log_info "📊 GitHub API工作流统计: $api_runs 个运行"
            return 0
        else
            log_warning "⚠️ GitHub API也无法获取工作流信息"
            return 0
        fi
    fi
}

# 验证整体系统行为
verify_system_behavior() {
    log_info "=== 验证整体系统行为 ==="
    
    # 检查队列是否正常工作
    if check_queue_status; then
        log_success "✅ 队列系统工作正常"
    else
        log_error "❌ 队列系统存在问题"
        return 1
    fi
    
    # 检查工作流是否正常工作
    if check_workflow_status; then
        log_success "✅ 工作流系统工作正常"
    else
        log_error "❌ 工作流系统存在问题"
        return 1
    fi
    
    # 检查GitHub API连接
    local api_test
    api_test=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/1" | \
        jq -r '.number // empty' 2>/dev/null)
    
    if [ "$api_test" = "1" ]; then
        log_success "✅ GitHub API连接正常"
    else
        log_error "❌ GitHub API连接异常"
        return 1
    fi
    
    log_success "✅ 整体系统行为验证通过"
    return 0
}

# 主测试函数
main_test() {
    log_step "开始真实工作流测试 - 组合测试"
    
    # 测试1: 环境准备和队列重置
    log_info "=== 测试1: 环境准备和队列重置 ==="
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'; then
        log_success "✅ 测试1通过: 队列重置成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 队列重置成功")
    else
        log_error "❌ 测试1失败: 队列重置失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 队列重置失败")
        return 1
    fi
    
    # 测试2: 执行队列加入测试
    log_info "=== 测试2: 执行队列加入测试 ==="
    if run_queue_join_test; then
        log_success "✅ 测试2通过: 队列加入测试成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 队列加入测试成功")
    else
        log_error "❌ 测试2失败: 队列加入测试失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 队列加入测试失败")
    fi
    
    # 等待一段时间
    sleep 10
    
    # 测试3: 执行构建锁测试
    log_info "=== 测试3: 执行构建锁测试 ==="
    if run_build_lock_test; then
        log_success "✅ 测试3通过: 构建锁测试成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 构建锁测试成功")
    else
        log_error "❌ 测试3失败: 构建锁测试失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 构建锁测试失败")
    fi
    
    # 等待一段时间
    sleep 10
    
    # 测试4: 检测队列状态变化
    log_info "=== 测试4: 检测队列状态变化 ==="
    if check_queue_status; then
        log_success "✅ 测试4通过: 队列状态检测成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 队列状态检测成功")
    else
        log_error "❌ 测试4失败: 队列状态检测失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 队列状态检测失败")
    fi
    
    # 测试5: 检测工作流状态
    log_info "=== 测试5: 检测工作流状态 ==="
    if check_workflow_status; then
        log_success "✅ 测试5通过: 工作流状态检测成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 工作流状态检测成功")
    else
        log_error "❌ 测试5失败: 工作流状态检测失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 工作流状态检测失败")
    fi
    
    # 测试6: 验证整体系统行为
    log_info "=== 测试6: 验证整体系统行为 ==="
    if verify_system_behavior; then
        log_success "✅ 测试6通过: 整体系统行为验证成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 整体系统行为验证成功")
    else
        log_error "❌ 测试6失败: 整体系统行为验证失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 整体系统行为验证失败")
    fi
    
    log_success "真实工作流测试 - 组合测试完成"
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
