#!/bin/bash
# 构建锁获取/释放功能测试脚本

# 设置测试环境
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

log_progress() {
    echo -e "${YELLOW}[PROGRESS]${NC} $1"
}

# 连通性检测函数
check_connectivity() {
    log_step "Checking connectivity to GitHub API..."
    
    # 检查基本网络连通性
    echo -n "  Checking basic internet connectivity... "
    if ping -c 1 api.github.com > /dev/null 2>&1; then
        echo "✅ OK"
    else
        echo "❌ FAILED"
        log_error "Cannot reach api.github.com"
        return 1
    fi
    
    # 检查GitHub API连通性
    echo -n "  Checking GitHub API connectivity... "
    local api_response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user")
    
    if [ "$api_response" = "200" ]; then
        echo "✅ OK (HTTP $api_response)"
    else
        echo "❌ FAILED (HTTP $api_response)"
        log_error "GitHub API authentication failed"
        return 1
    fi
    
    # 检查仓库访问权限
    echo -n "  Checking repository access... "
    local repo_response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY")
    
    if [ "$repo_response" = "200" ]; then
        echo "✅ OK (HTTP $repo_response)"
    else
        echo "❌ FAILED (HTTP $repo_response)"
        log_error "Cannot access repository: $GITHUB_REPOSITORY"
        
        # 显示详细的错误信息
        local detailed_response=$(curl -s \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$GITHUB_REPOSITORY")
        echo "Detailed error: $(echo "$detailed_response" | jq -r '.message // "Unknown error"')"
        return 1
    fi
    
    # 检查Issue #1是否存在
    echo -n "  Checking queue issue #1... "
    local issue_response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/1")
    
    if echo "$issue_response" | jq -e '.message' | grep -q "Not Found"; then
        echo "❌ NOT FOUND"
        log_warning "Queue issue #1 does not exist, tests may fail"
    else
        echo "✅ EXISTS"
    fi
    
    log_success "Connectivity check completed"
    return 0
}

# 测试函数
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
    log_test "Running test: $test_name"
    echo "Command: $test_command"
    echo "Expected exit code: $expected_exit_code"
    echo "----------------------------------------"
    
    # 显示执行进度
    echo -n "Executing test... "
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行测试命令，确保环境变量传递
    if bash -c "export GITHUB_TOKEN='$GITHUB_TOKEN'; export GITHUB_REPOSITORY='$GITHUB_REPOSITORY'; export GITHUB_RUN_ID='$GITHUB_RUN_ID'; $test_command" > /tmp/test_output.log 2>&1; then
        actual_exit_code=$?
    else
        actual_exit_code=$?
    fi
    
    # 记录结束时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Done! (${duration}s)"
    echo "Actual exit code: $actual_exit_code"
    
    # 检查退出码
    if [ "$actual_exit_code" -eq "$expected_exit_code" ]; then
        log_success "Test PASSED: $test_name (${duration}s)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        TEST_RESULTS+=("PASS: $test_name (${duration}s)")
        
        # 显示成功输出（如果有）
        if [ -f /tmp/test_output.log ] && [ -s /tmp/test_output.log ]; then
            echo "Test output:"
            cat /tmp/test_output.log
        fi
    else
        log_error "Test FAILED: $test_name (Expected: $expected_exit_code, Got: $actual_exit_code, ${duration}s)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        TEST_RESULTS+=("FAIL: $test_name (Expected: $expected_exit_code, Got: $actual_exit_code, ${duration}s)")
        
        # 显示错误输出
        if [ -f /tmp/test_output.log ]; then
            echo "Test output:"
            cat /tmp/test_output.log
        fi
    fi
    
    echo "----------------------------------------"
}

# 模拟环境变量
setup_test_env() {
    log_step "Setting up test environment..."
    
    # 检查是否有真实的GitHub认证
    if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
        log_info "GitHub CLI detected, using real authentication"
        
        # 获取真实的GitHub token
        export GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
        
        # 获取真实的仓库信息
        if [ -n "$GITHUB_REPOSITORY" ]; then
            log_info "Using existing GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
        else
            # 尝试从git remote获取仓库信息
            local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
            if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
                export GITHUB_REPOSITORY="${BASH_REMATCH[1]}"
                # 移除可能的.git后缀
                export GITHUB_REPOSITORY="${GITHUB_REPOSITORY%.git}"
                log_info "Detected GITHUB_REPOSITORY from git remote: $GITHUB_REPOSITORY"
            else
                export GITHUB_REPOSITORY="jackadam1981/Custom-Rustdesk"
                log_warning "Using default GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
            fi
        fi
        
        # 设置真实的运行ID
        export GITHUB_RUN_ID="test_$(date +%s)"
        
    else
        log_warning "GitHub CLI not available, using test environment"
        
        # 设置必要的环境变量
        export GITHUB_RUN_ID="test_$(date +%s)"
        export GITHUB_TOKEN="test_token"
        export GITHUB_REPOSITORY="test/repo"
    fi
    
    echo "Environment variables set:"
    echo "  GITHUB_RUN_ID: $GITHUB_RUN_ID"
    echo "  GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}..."  # 只显示token的前10个字符
    echo "  GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
    
    log_success "Test environment setup completed"
}

# 清理测试环境
cleanup_test_env() {
    log_step "Cleaning up test environment..."
    
    # 清理临时文件
    rm -f /tmp/test_output.log
    
    log_success "Test environment cleanup completed"
}

# 测试构建锁获取功能
test_build_lock_acquire() {
    log_step "Testing build lock acquire functionality..."
    
    # 测试1: 正常获取构建锁
    run_test "Build Lock Acquire - Normal" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'" \
        0
    
    # 测试2: 重复获取构建锁（应该成功，因为已经持有锁）
    run_test "Build Lock Acquire - Duplicate" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'" \
        0
    
    # 测试3: 获取构建锁时使用无效的lock_type
    run_test "Build Lock Acquire - Invalid Lock Type" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'invalid_lock' 'acquire'" \
        1
    
    # 测试4: 获取构建锁时使用无效的operation
    run_test "Build Lock Acquire - Invalid Operation" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'invalid_op'" \
        1
}

# 测试构建锁释放功能
test_build_lock_release() {
    log_step "Testing build lock release functionality..."
    
    # 测试1: 正常释放构建锁
    run_test "Build Lock Release - Normal" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'" \
        0
    
    # 测试2: 重复释放构建锁（应该成功，因为已经释放）
    run_test "Build Lock Release - Duplicate" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'" \
        0
    
    # 测试3: 释放构建锁时使用无效的lock_type
    run_test "Build Lock Release - Invalid Lock Type" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'invalid_lock' 'release'" \
        1
    
    # 测试4: 释放构建锁时使用无效的operation
    run_test "Build Lock Release - Invalid Operation" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'invalid_op'" \
        1
}

# 测试构建锁状态查询功能
test_build_lock_status() {
    log_step "Testing build lock status functionality..."
    
    # 测试1: 正常查询构建锁状态
    run_test "Build Lock Status - Normal" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'status'" \
        0
    
    # 测试2: 查询构建锁状态时使用无效的lock_type
    run_test "Build Lock Status - Invalid Lock Type" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'invalid_lock' 'status'" \
        1
    
    # 测试3: 查询构建锁状态时使用无效的operation
    run_test "Build Lock Status - Invalid Operation" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'invalid_op'" \
        1
}

# 测试构建锁完整流程
test_build_lock_workflow() {
    log_step "Testing build lock complete workflow..."
    
    # 测试1: 获取锁 -> 查询状态 -> 释放锁的完整流程
    log_info "Testing complete workflow: acquire -> status -> release"
    
    # 先获取锁
    run_test "Build Lock Workflow - Acquire" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'" \
        0
    
    # 查询状态
    run_test "Build Lock Workflow - Status" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'status'" \
        0
    
    # 释放锁
    run_test "Build Lock Workflow - Release" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'" \
        0
    
    # 再次查询状态确认释放
    run_test "Build Lock Workflow - Status After Release" \
        "source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'status'" \
        0
}

# 显示测试结果
show_test_results() {
    echo ""
    echo "========================================"
    echo "           TEST RESULTS SUMMARY"
    echo "========================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo ""
    
    if [ $FAILED_TESTS -eq 0 ]; then
        log_success "All tests passed! 🎉"
        echo ""
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            echo "  ✅ $result"
        done
    else
        log_error "Some tests failed! ❌"
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
    echo "    Build Lock Acquire/Release Tests"
    echo "========================================"
    echo ""
    
    # 检查是否跳过连通性检测
    local skip_connectivity=false
    if [ "$1" = "--skip-connectivity" ]; then
        skip_connectivity=true
        log_warning "Skipping connectivity check as requested"
    fi
    
    # 设置测试环境
    setup_test_env
    
    # 检查连通性（除非跳过）
    if [ "$skip_connectivity" = false ]; then
        if ! check_connectivity; then
            log_error "Connectivity check failed. Please check your network and GitHub token."
            log_info "You can run with --skip-connectivity to bypass this check"
            exit 1
        fi
    fi
    
    # 运行测试
    test_build_lock_acquire
    test_build_lock_release
    test_build_lock_status
    test_build_lock_workflow
    
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