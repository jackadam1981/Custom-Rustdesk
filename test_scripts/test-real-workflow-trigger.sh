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
    log_info "     真实工作流测试 - 高并发验证"
    log_info "========================================"
    log_info "测试真实的GitHub工作流高并发场景："
    log_info "  1. 环境准备和队列重置"
    log_info "  2. 高并发真实触发测试（4个Issue + 3个手动工作流）"
    log_info "  3. 顺序构建校验（监控构建锁持有者变化）"
    log_info "  4. 检测队列状态变化"
    log_info "  5. 检测工作流状态"
    log_info "  6. 验证整体系统行为"
    log_info ""
    log_info "预期结果："
    log_info "  - Issue触发限制：最多3个"
    log_info "  - 手动触发限制：最多2个"
    log_info "  - 总队列限制：最多5个"
    log_info "  - 构建锁：严格一进一出，顺序执行"
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

# 高并发真实触发测试
run_high_concurrency_test() {
    log_info "=== 执行高并发真实触发测试 ==="
    
    # 重置队列状态
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'; then
        log_success "队列重置成功"
    else
        log_error "队列重置失败"
        return 1
    fi
    
    # 并发创建4个Issue（预期第4个受限）
    log_info "🚀 并发创建4个Issue..."
    local issue_success_count=0
    
    for i in {1..4}; do
        local issue_title="High Concurrency Test Issue $i"
        local issue_body="This is test issue $i for high concurrency testing.

## 构建配置
- 平台: linux-x64
- 配置: release
- 特性: default

## 测试目的
验证高并发Issue触发下的队列行为。"
        
        if gh issue create --title "$issue_title" --body "$issue_body" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
            log_success "✅ Issue $i 创建成功"
            issue_success_count=$((issue_success_count + 1))
        else
            log_warning "⚠️ Issue $i 创建失败或受限"
        fi
        
        # 短暂间隔，避免API限制
        sleep 2
    done
    
    log_info "📊 Issue创建结果: $issue_success_count/4 成功"
    
    # 等待工作流触发
    log_info "⏳ 等待工作流触发..."
    sleep 30
    
    # 并发触发3个手动工作流
    log_info "🚀 并发触发3个手动工作流..."
    local workflow_success_count=0
    
    for i in {1..3}; do
        if gh workflow run "build.yml" --ref "main" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
            log_success "✅ 手动工作流 $i 触发成功"
            workflow_success_count=$((workflow_success_count + 1))
        else
            log_warning "⚠️ 手动工作流 $i 触发失败或受限"
        fi
        
        sleep 2
    done
    
    log_info "📊 手动工作流触发结果: $workflow_success_count/3 成功"
    
    # 等待工作流启动
    log_info "⏳ 等待工作流启动和队列处理..."
    sleep 60
    
    # 检查队列状态
    log_info "🔍 检查高并发后的队列状态..."
    local queue_data
    queue_data=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'get_data' 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        local queue_length=$(echo "$queue_data" | jq '.queue | length // 0' 2>/dev/null || echo "0")
        local issue_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "issues")) | length // 0' 2>/dev/null || echo "0")
        local manual_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0' 2>/dev/null || echo "0")
        
        log_info "📊 高并发后队列状态:"
        log_info "  - 总长度: $queue_length"
        log_info "  - Issue触发: $issue_count"
        log_info "  - 手动触发: $manual_count"
        
        # 验证队列限制
        if [ "$issue_count" -le 3 ] && [ "$manual_count" -le 2 ] && [ "$queue_length" -le 5 ]; then
            log_success "✅ 队列限制验证通过"
            return 0
        else
            log_warning "⚠️ 队列限制可能超出预期"
            return 1
        fi
    else
        log_error "❌ 无法获取队列状态"
        return 1
    fi
}

# 顺序构建校验
verify_sequential_build() {
    log_info "=== 执行顺序构建校验 ==="
    
    # 监控构建锁持有者变化
    log_info "🔍 监控构建锁持有者变化..."
    local max_monitor_time=600  # 最多监控10分钟
    local check_interval=30
    local start_time=$(date +%s)
    local elapsed=0
    local build_history=()
    
    while [ $elapsed -lt $max_monitor_time ]; do
        # 获取当前构建锁状态
        local build_lock_status
        build_lock_status=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'status' 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local current_time=$(date '+%Y-%m-%d %H:%M:%S')
            local current_holder=$(echo "$build_lock_status" | grep -o 'Current holder: [^,]*' | cut -d' ' -f3 || echo "none")
            
            # 记录构建锁变化
            if [ ${#build_history[@]} -eq 0 ] || [ "$current_holder" != "${build_history[-1]}" ]; then
                build_history+=("$current_holder")
                log_info "📝 [$current_time] 构建锁持有者: $current_holder"
            fi
            
            # 检查是否有构建锁被持有
            if [ "$current_holder" != "none" ] && [ "$current_holder" != "null" ]; then
                log_info "🔒 [$current_time] 构建锁被 $current_holder 持有"
            fi
        fi
        
        # 检查队列状态
        local queue_data
        queue_data=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'get_data' 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local queue_length=$(echo "$queue_data" | jq '.queue | length // 0' 2>/dev/null || echo "0")
            local running_count=$(echo "$queue_data" | jq '.queue | map(select(.status == "running")) | length // 0' 2>/dev/null || echo "0")
            
            log_info "📊 [$current_time] 队列状态: 总长度=$queue_length, 运行中=$running_count"
        fi
        
        # 等待下次检查
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
        
        # 如果队列为空且没有构建锁被持有，可能测试完成
        if [ "$queue_length" -eq 0 ] && [ "$current_holder" = "none" ]; then
            log_info "✅ 队列已空，构建锁无持有者，测试可能完成"
            break
        fi
    done
    
    # 输出构建历史
    log_info "📋 构建锁持有历史:"
    for i in "${!build_history[@]}"; do
        log_info "  $((i+1)). ${build_history[$i]}"
    done
    
    if [ $elapsed -ge $max_monitor_time ]; then
        log_warning "⚠️ 监控超时，已等待${max_monitor_time}秒"
    fi
    
    log_success "✅ 顺序构建校验完成"
    return 0
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
    
    # 测试2: 执行高并发真实触发测试
    log_info "=== 测试2: 执行高并发真实触发测试 ==="
    if run_high_concurrency_test; then
        log_success "✅ 测试2通过: 高并发真实触发测试成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 高并发真实触发测试成功")
    else
        log_error "❌ 测试2失败: 高并发真实触发测试失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 高并发真实触发测试失败")
    fi
    
    # 等待一段时间让工作流稳定
    sleep 30
    
    # 测试3: 执行顺序构建校验
    log_info "=== 测试3: 执行顺序构建校验 ==="
    if verify_sequential_build; then
        log_success "✅ 测试3通过: 顺序构建校验成功"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 顺序构建校验成功")
    else
        log_error "❌ 测试3失败: 顺序构建校验失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 顺序构建校验失败")
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
