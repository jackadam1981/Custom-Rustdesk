#!/bin/bash
# 测试调度脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试结果
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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

# 运行单个测试
run_single_test() {
    local test_name="$1"
    local test_script="$2"
    
    log_info "Running test: $test_name"
    echo "Script: $test_script"
    echo "----------------------------------------"
    
    if [ -f "$test_script" ]; then
        if bash "$test_script"; then
            log_success "Test PASSED: $test_name"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            log_error "Test FAILED: $test_name"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        log_error "Test script not found: $test_script"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
}

# 显示帮助信息
show_help() {
    echo "Usage: $0 [OPTIONS] [TEST_NAMES...]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -a, --all      Run all tests"
    echo "  -l, --list     List available tests"
    echo ""
    echo "Available Tests:"
    echo "  env-test           Test GitHub API environment and basic functionality"
    echo "  queue-join         Test queue join functionality"
    echo "  queue-leave        Test queue leave functionality"
    echo "  queue-cleanup      Test queue cleanup functionality"
    echo "  queue-reset        Test queue reset functionality"
    echo "  queue-status       Test queue status query functionality"
    echo "  queue-sequence     Test all queue functions in sequence"
    echo "  queue-build-lock   Test build lock acquisition/release functionality"
    echo "  queue-concurrent   Test concurrent build lock polling functionality"
    echo ""
    echo "Examples:"
    echo "  $0 --all                           # Run all tests"
    echo "  $0 env-test                       # Test environment"
    echo "  $0 queue-join                     # Test queue join"
    echo "  $0 queue-leave                    # Test queue leave"
    echo "  $0 queue-cleanup                  # Test queue cleanup"
    echo "  $0 queue-reset                    # Test queue reset"
    echo "  $0 queue-status                   # Test status queries"
    echo "  $0 queue-sequence                 # Test all functions in sequence"
    echo "  $0 queue-build-lock               # Test build lock functionality"
    echo "  $0 queue-concurrent               # Test concurrent lock polling"
    echo "  $0 queue-join --help              # Show help for specific test"
}

# 列出可用测试
list_tests() {
    echo "Available Tests:"
    echo "  env-test           - GitHub API environment and basic functionality test"
    echo "  queue-join         - Queue join functionality test"
    echo "  queue-leave        - Queue leave functionality test"
    echo "  queue-cleanup      - Queue cleanup functionality test"
    echo "  queue-reset        - Queue reset functionality test"
    echo "  queue-status       - Queue status query functionality test"
    echo "  queue-sequence     - All queue functions in sequence test"
    echo "  queue-build-lock   - Build lock acquisition/release functionality test"
    echo "  queue-concurrent   - Concurrent build lock polling functionality test"
    echo ""
    echo "Test Scripts:"
    echo "  test_scripts/env-test.sh"
    echo "  test_scripts/test-queue-join.sh"
    echo "  test_scripts/test-queue-leave.sh"
    echo "  test_scripts/test-queue-cleanup.sh"
    echo "  test_scripts/test-queue-reset.sh"
    echo "  test_scripts/test-queue-status.sh"
    echo "  test_scripts/test-queue-sequence.sh"
    echo "  test_scripts/test-queue-build-lock.sh"
    echo "  test_scripts/test-queue-concurrent.sh"
    echo ""
}

# 显示测试结果
show_results() {
    echo ""
    echo "========================================"
    echo "           OVERALL TEST RESULTS"
    echo "========================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ] && [ $TOTAL_TESTS -gt 0 ]; then
        log_success "All tests passed! 🎉"
    elif [ $TOTAL_TESTS -gt 0 ]; then
        log_error "Some tests failed! ❌"
    else
        log_warning "No tests were run."
    fi
    
    echo ""
    echo "========================================"
}

# 主函数
main() {
    # 检查参数
    if [ $# -eq 0 ]; then
        show_help
        exit 1
    fi
    
    # 处理参数
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            list_tests
            exit 0
            ;;
        -a|--all)
            log_info "Running all tests..."
            run_single_test "Environment Test" "test_scripts/env-test.sh"
            run_single_test "Queue Join" "test_scripts/test-queue-join.sh"
            run_single_test "Queue Leave" "test_scripts/test-queue-leave.sh"
            run_single_test "Queue Cleanup" "test_scripts/test-queue-cleanup.sh"
            run_single_test "Queue Reset" "test_scripts/test-queue-reset.sh"
            run_single_test "Queue Status" "test_scripts/test-queue-status.sh"
            run_single_test "Queue Build Lock" "test_scripts/test-queue-build-lock.sh"
            run_single_test "Queue Concurrent" "test_scripts/test-queue-concurrent.sh"
            ;;
        env-test)
            run_single_test "Environment Test" "test_scripts/env-test.sh"
            ;;
        queue-join)
            run_single_test "Queue Join" "test_scripts/test-queue-join.sh"
            ;;
        queue-leave)
            run_single_test "Queue Leave" "test_scripts/test-queue-leave.sh"
            ;;
        queue-cleanup)
            run_single_test "Queue Cleanup" "test_scripts/test-queue-cleanup.sh"
            ;;
        queue-reset)
            run_single_test "Queue Reset" "test_scripts/test-queue-reset.sh"
            ;;
        queue-status)
            run_single_test "Queue Status" "test_scripts/test-queue-status.sh"
            ;;
        queue-sequence)
            run_single_test "Queue Sequence" "test_scripts/test-queue-sequence.sh"
            ;;
        queue-build-lock)
            run_single_test "Queue Build Lock" "test_scripts/test-queue-build-lock.sh"
            ;;
        queue-concurrent)
            run_single_test "Queue Concurrent" "test_scripts/test-queue-concurrent.sh"
            ;;
        *)
            log_error "Unknown test: $1"
            show_help
            exit 1
            ;;
    esac
    
    # 显示结果
    show_results
    
    # 返回适当的退出码
    if [ $FAILED_TESTS -eq 0 ] && [ $TOTAL_TESTS -gt 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 运行主函数
main "$@" 