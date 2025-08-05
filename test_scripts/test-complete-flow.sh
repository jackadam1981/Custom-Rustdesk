#!/bin/bash
# 完整流程测试脚本 - 组合多个小测试脚本

# 设置测试环境
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试结果记录
TEST_RESULTS=()

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 运行子测试脚本
run_sub_test() {
    local test_name="$1"
    local test_script="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log_info "Running sub-test: $test_name"
    echo "Script: $test_script"
    
    if [ -f "$test_script" ]; then
        if bash "$test_script"; then
            log_success "Sub-test PASSED: $test_name"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            TEST_RESULTS+=("PASS: $test_name")
        else
            log_error "Sub-test FAILED: $test_name"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            TEST_RESULTS+=("FAIL: $test_name")
        fi
    else
        log_error "Sub-test script not found: $test_script"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: $test_name (script not found)")
    fi
    
    echo "----------------------------------------"
}

# 设置环境变量
setup_test_env() {
    log_info "Setting up test environment..."
    
    # 设置必要的环境变量
    export GITHUB_TOKEN=$(gh auth token)
    export GITHUB_REPOSITORY="jackadam1981/Custom-Rustdesk"
    export GITHUB_RUN_ID="test_$(date +%s)"
    
    log_success "Test environment setup completed"
}

# 清理测试环境
cleanup_test_env() {
    log_info "Cleaning up test environment..."
    
    # 清理临时文件
    rm -f /tmp/test_output.log
    
    log_success "Test environment cleanup completed"
}

# 完整流程测试
test_complete_flow() {
    log_info "Testing complete queue management flow..."
    
    # 步骤1: 环境验证
    run_sub_test "Environment Validation" "test_scripts/env-test.sh"
    
    # 步骤2: 加入队列
    run_sub_test "Join Queue" "test_scripts/test-queue-join-leave.sh"
    
    # 步骤3: 查询状态
    run_sub_test "Query Status" "test_scripts/test-queue-status.sh"
    
    # 步骤4: 离开队列
    # 注意：这里需要特殊处理，因为join-leave脚本会同时测试加入和离开
    # 未来可以创建独立的join和leave测试脚本
    
    log_info "Complete flow test finished"
}

# 显示测试结果
show_test_results() {
    echo ""
    echo "========================================"
    echo "           COMPLETE FLOW TEST RESULTS"
    echo "========================================"
    echo "Total Sub-tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All sub-tests passed! 🎉"
        echo ""
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            echo "  ✅ $result"
        done
    else
        log_error "Some sub-tests failed! ❌"
        echo ""
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == "PASS:"* ]]; then
                echo "  ✅ $result"
            else
                echo "  ❌ $result"
            fi
        done
    fi
    
    echo ""
    echo "========================================"
}

# 主函数
main() {
    echo "========================================"
    echo "    Complete Queue Management Flow Test"
    echo "========================================"
    echo ""
    echo "This test combines multiple smaller test scripts to verify"
    echo "the complete queue management workflow."
    echo ""
    
    # 设置测试环境
    setup_test_env
    
    # 运行完整流程测试
    test_complete_flow
    
    # 清理测试环境
    cleanup_test_env
    
    # 显示测试结果
    show_test_results
    
    # 返回适当的退出码
    if [ $FAILED_TESTS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@" 