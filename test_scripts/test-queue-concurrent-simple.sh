#!/bin/bash

# 完整高并发队列构建测试脚本 - 测试完整的构建流程
# 包含构建参数、构建过程和队列管理

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
    log_info "     完整高并发队列构建测试"
    log_info "========================================"
    log_info "测试完整的队列构建流程，包含构建参数和构建过程："
    log_info "  - 任务 1-3: Issue触发（应该成功，达到issue限制3个）"
    log_info "  - 任务 4: Issue触发（应该被拒绝 - issue限制已达3个）"
    log_info "  - 任务 5-6: 手动触发（应该成功，达到手动限制2个）"
    log_info "  - 任务 7: 手动触发（应该被拒绝 - 手动限制已达2个）"
    log_info "  构建参数："
    log_info "    * Issue触发: release配置，linux-x64平台，默认特性"
    log_info "    * 手动触发: debug配置，linux-x64平台，测试特性"
    log_info "  构建过程：获取锁 → 构建 → 释放锁 → 离开队列"
}

# 队列状态检测
check_queue_state() {
    local expected_issue_count="$1"
    local expected_manual_count="$2"
    local expected_total="$3"
    
    log_info "🔍 检查队列状态..."
    
    # 获取队列状态（显示长度）
    local queue_status
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status' >/dev/null 2>&1; then
        queue_status=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status' 2>/dev/null)
        log_info "当前队列状态: $queue_status"
    else
        log_error "无法获取队列状态"
        return 1
    fi
    
    # 获取队列数据（JSON格式）
    local queue_data
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'get_data' >/dev/null 2>&1; then
        queue_data=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'get_data' 2>/dev/null)
    else
        log_error "无法获取队列数据"
        return 1
    fi
    
    # 检查队列长度
    local actual_total=$(echo "$queue_data" | jq '.queue | length // 0' 2>/dev/null || echo "0")
    local actual_issue_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "issues")) | length // 0' 2>/dev/null || echo "0")
    local actual_manual_count=$(echo "$queue_data" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0' 2>/dev/null || echo "0")
    
    log_info "队列统计:"
    log_info "  - 总数量: $actual_total/$expected_total"
    log_info "  - Issue触发: $actual_issue_count/$expected_issue_count"
    log_info "  - 手动触发: $actual_manual_count/$expected_manual_count"
    
    # 验证结果
    if [ "$actual_total" -eq "$expected_total" ] && [ "$actual_issue_count" -eq "$expected_issue_count" ] && [ "$actual_manual_count" -eq "$expected_manual_count" ]; then
        log_success "✅ 队列状态符合预期"
        return 0
    else
        log_error "❌ 队列状态不符合预期"
        return 1
    fi
}

# 模拟任务加入队列并完成构建过程
simulate_task_complete() {
    local task_id="$1"
    local trigger_type="$2"
    local task_name="$3"
    local issue_number="${4:-}"
    
    log_info "🚀 模拟 $task_name 完整流程..."
    
    # 设置环境变量
    export GITHUB_RUN_ID="$task_id"
    export GITHUB_EVENT_NAME="$trigger_type"
    
    # 构建触发数据（包含完整的构建参数）
    local trigger_data
    if [ "$trigger_type" = "issues" ]; then
        trigger_data="{\"tag\":\"issue-$issue_number\",\"email\":\"issue$issue_number@example.com\",\"customer\":\"test-customer\",\"trigger_type\":\"issues\",\"issue_number\":$issue_number,\"build_config\":\"release\",\"target_platform\":\"linux-x64\",\"features\":\"default\"}"
    else
        trigger_data="{\"tag\":\"$task_name\",\"email\":\"$task_name@example.com\",\"customer\":\"test-customer\",\"trigger_type\":\"workflow_dispatch\",\"build_config\":\"debug\",\"target_platform\":\"linux-x64\",\"features\":\"test\"}"
    fi
    
    # 尝试加入队列
    local join_result
    join_result=$(source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' "$trigger_data" 2>/dev/null)
    
    if echo "$join_result" | jq -e '.success' >/dev/null 2>&1; then
        local position=$(echo "$join_result" | jq -r '.queue_position')
        log_success "✅ $task_name 成功加入队列，位置: $position"
        
        # 等待轮到该任务（如果是第一个任务，立即开始）
        if [ "$position" = "1" ]; then
            log_info "🎯 $task_name 是队列第一个，开始获取构建锁..."
        else
            log_info "⏳ $task_name 等待队列位置 $position 轮到..."
            # 等待前面的任务完成
            local wait_count=0
            while [ $wait_count -lt 60 ]; do
                sleep 2
                wait_count=$((wait_count + 2))
                log_info "⏳ $task_name 等待中... ($wait_count/60s)"
            done
        fi
        
        # 尝试获取构建锁
        if source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'; then
            log_success "🔒 $task_name 成功获取构建锁"
            
            # 模拟构建过程
            log_info "🔨 $task_name 开始构建 (${TEST_BUILD_PAUSE:-10}s)..."
            sleep "${TEST_BUILD_PAUSE:-10}"
            log_success "✅ $task_name 构建完成"
            
            # 释放构建锁
            if source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'; then
                log_success "🔓 $task_name 成功释放构建锁"
                
                # 离开队列
                if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'leave'; then
                    log_success "🚪 $task_name 成功离开队列"
                    return 0
                else
                    log_error "❌ $task_name 离开队列失败"
                    return 1
                fi
            else
                log_error "❌ $task_name 释放构建锁失败"
                return 1
            fi
        else
            log_error "❌ $task_name 获取构建锁失败"
            return 1
        fi
    else
        log_error "❌ $task_name 加入队列失败"
        return 1
    fi
}

# 主测试函数
main_test() {
    log_step "开始完整高并发队列构建测试"
    
    # 重置队列状态
    log_info "🔄 重置队列状态..."
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'; then
        log_success "队列重置成功"
    else
        log_error "队列重置失败"
        return 1
    fi
    
    # 生成任务ID
    local timestamp=$(date +%s)
    local task1_id="issue_trigger_1_${timestamp}"
    local task2_id="issue_trigger_2_${timestamp}"
    local task3_id="issue_trigger_3_${timestamp}"
    local task4_id="issue_trigger_4_${timestamp}"
    local task5_id="manual_trigger_5_${timestamp}"
    local task6_id="manual_trigger_6_${timestamp}"
    local task7_id="manual_trigger_7_${timestamp}"
    
    log_info "生成的任务ID: $task1_id, $task2_id, $task3_id, $task4_id, $task5_id, $task6_id, $task7_id"
    
    # 测试1: 前3个Issue触发应该成功并完成构建
    log_info "=== 测试1: 前3个Issue触发应该成功并完成构建 ==="
    local success_count=0
    
    if simulate_task_complete "$task1_id" "issues" "Issue Trigger 1" "1001"; then
        success_count=$((success_count + 1))
    fi
    
    if simulate_task_complete "$task2_id" "issues" "Issue Trigger 2" "1002"; then
        success_count=$((success_count + 1))
    fi
    
    if simulate_task_complete "$task3_id" "issues" "Issue Trigger 3" "1003"; then
        success_count=$((success_count + 1))
    fi
    
    if [ $success_count -eq 3 ]; then
        log_success "✅ 测试1通过: 前3个Issue触发都成功完成构建"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 前3个Issue触发都成功完成构建")
    else
        log_error "❌ 测试1失败: 只有 $success_count/3 个Issue触发成功完成构建"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 只有 $success_count/3 个Issue触发成功完成构建")
    fi
    
    # 检查队列状态
    if check_queue_state 3 0 3; then
        log_success "✅ 队列状态验证通过"
    else
        log_error "❌ 队列状态验证失败"
    fi
    
    # 测试2: 第4个Issue触发应该被拒绝
    log_info "=== 测试2: 第4个Issue触发应该被拒绝 ==="
    if simulate_task_complete "$task4_id" "issues" "Issue Trigger 4" "1004"; then
        log_error "❌ 测试2失败: 第4个Issue触发应该被拒绝"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 第4个Issue触发应该被拒绝")
    else
        log_success "✅ 测试2通过: 第4个Issue触发被正确拒绝"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 第4个Issue触发被正确拒绝")
    fi
    
    # 测试3: 前2个手动触发应该成功并完成构建
    log_info "=== 测试3: 前2个手动触发应该成功并完成构建 ==="
    success_count=0
    
    if simulate_task_complete "$task5_id" "workflow_dispatch" "Manual Trigger 5"; then
        success_count=$((success_count + 1))
    fi
    
    if simulate_task_complete "$task6_id" "workflow_dispatch" "Manual Trigger 6"; then
        success_count=$((success_count + 1))
    fi
    
    if [ $success_count -eq 2 ]; then
        log_success "✅ 测试3通过: 前2个手动触发都成功完成构建"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 前2个手动触发都成功完成构建")
    else
        log_error "❌ 测试3失败: 只有 $success_count/2 个手动触发成功完成构建"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 只有 $success_count/2 个手动触发成功完成构建")
    fi
    
    # 检查队列状态
    if check_queue_state 3 2 5; then
        log_success "✅ 队列状态验证通过"
    else
        log_error "❌ 队列状态验证失败"
    fi
    
    # 测试4: 第3个手动触发应该被拒绝
    log_info "=== 测试4: 第3个手动触发应该被拒绝 ==="
    if simulate_task_complete "$task7_id" "workflow_dispatch" "Manual Trigger 7"; then
        log_error "❌ 测试4失败: 第3个手动触发应该被拒绝"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 第3个手动触发应该被拒绝")
    else
        log_success "✅ 测试4通过: 第3个手动触发被正确拒绝"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 第3个手动触发被正确拒绝")
    fi
    
    # 测试5: 最终队列状态验证（所有任务应该已完成并离开队列）
    log_info "=== 测试5: 最终队列状态验证（所有任务应该已完成并离开队列） ==="
    if check_queue_state 0 0 0; then
        log_success "✅ 测试5通过: 最终队列状态正确（所有任务已完成）"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 最终队列状态正确（所有任务已完成）")
    else
        log_error "❌ 测试5失败: 最终队列状态不正确"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 最终队列状态不正确")
    fi
    
    # 测试6: 清理测试状态
    log_info "=== 测试6: 清理测试状态 ==="
    if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'; then
        log_success "✅ 测试6通过: 测试清理完成"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: 测试清理完成")
    else
        log_error "❌ 测试6失败: 测试清理失败"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: 测试清理失败")
    fi
    
    log_success "简化高并发测试完成"
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
