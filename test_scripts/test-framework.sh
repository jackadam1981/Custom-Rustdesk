#!/bin/bash
# 统一测试框架 - 所有测试脚本的基础框架
# 合并了原test-framework.sh和test-utils.sh的功能

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 测试状态变量
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

# ============================================================================
# 日志函数 - 提供统一的日志输出格式
# ============================================================================

# 信息日志 - 显示一般信息
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 成功日志 - 显示成功操作
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 警告日志 - 显示警告信息
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 错误日志 - 显示错误信息
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 步骤日志 - 显示测试步骤
log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# 测试日志 - 显示测试执行信息
log_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

# ============================================================================
# 环境检查和设置函数
# ============================================================================

# 检查是否通过run-tests.sh调用
check_test_runner() {
    if [ -z "$TEST_RUNNER_CALLED" ]; then
        log_error "此测试脚本只能通过 run-tests.sh 调用"
        log_error "请使用: ./run-tests.sh <test-name>"
        exit 1
    fi
}

# 设置测试环境 - 统一的环境设置函数，合并了两个框架的环境设置逻辑
setup_test_environment() {
    log_step "Setting up test environment..."
    
    # 加载本地环境变量，支持多种路径
    local env_loaded=false
    for env_file in "../env.sh" "env.sh" "./env.sh"; do
        if [ -f "$env_file" ]; then
            source "$env_file"
            log_info "Loaded environment variables from: $env_file"
            env_loaded=true
            break
        fi
    done
    
    if [ "$env_loaded" = false ]; then
        log_warning "env.sh not found, using automatic detection"
    fi
    
    # 检测GitHub CLI并设置认证
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        log_info "GitHub CLI detected, using real authentication"
        
        # 获取GitHub token（如果未设置）
        if [ -z "$GITHUB_TOKEN" ]; then
            export GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
        fi
        
        # 获取仓库信息（如果未设置）
        if [ -z "$GITHUB_REPOSITORY" ]; then
            local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
            if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
                export GITHUB_REPOSITORY="${BASH_REMATCH[1]%.git}"
                log_info "Detected GITHUB_REPOSITORY from git remote: $GITHUB_REPOSITORY"
            else
                export GITHUB_REPOSITORY="jackadam1981/Custom-Rustdesk"
                log_warning "Using default GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
            fi
        fi
    else
        log_warning "GitHub CLI not available, using test environment"
        
        # 设置默认值
        if [ -z "$GITHUB_TOKEN" ]; then
            export GITHUB_TOKEN="test_token"
        fi
        if [ -z "$GITHUB_REPOSITORY" ]; then
            export GITHUB_REPOSITORY="test/repo"
        fi
    fi
    
    # 设置运行ID（如果未设置）
    if [ -z "$GITHUB_RUN_ID" ]; then
        export GITHUB_RUN_ID="test_$(date +%s)"
    fi
    
    # 显示环境变量信息
    echo "Environment variables:"
    echo "  GITHUB_RUN_ID: $GITHUB_RUN_ID"
    echo "  GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}..."
    echo "  GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
    echo ""
    
    # 验证必要的环境变量
    if [ -z "$GITHUB_TOKEN" ] || [ -z "$GITHUB_REPOSITORY" ]; then
        log_error "Required environment variables not set"
        return 1
    fi
    
    # 测试GitHub API连接
    log_info "Testing GitHub API connection..."
    local api_response=$(curl -s -w "%{http_code}" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/1")
    
    local http_code="${api_response: -3}"
    local response_body="${api_response%???}"
    
    if [ "$http_code" = "200" ]; then
        log_success "GitHub API connection successful (HTTP 200)"
        
        # 验证Issue #1存在
        local issue_number=$(echo "$response_body" | jq -r '.number // empty' 2>/dev/null || echo "")
        if [ "$issue_number" = "1" ]; then
            log_success "Issue #1 exists and accessible"
        else
            log_error "Issue #1 not found or not accessible"
            return 1
        fi
    else
        log_error "GitHub API connection failed (HTTP $http_code)"
        case "$http_code" in
            "401") log_error "Authentication failed - check GITHUB_TOKEN" ;;
            "404") log_error "Repository not found - check GITHUB_REPOSITORY" ;;
            *) log_error "Unexpected HTTP status: $http_code" ;;
        esac
        return 1
    fi
    
    log_success "Test environment setup completed"
    return 0
}

# ============================================================================
# GitHub Issue 数据操作函数
# ============================================================================

# 获取Issue #1的JSON数据
get_issue_json_data() {
    local issue_response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/1")
    
    # 检查是否找到Issue
    if echo "$issue_response" | jq -e '.message' 2>/dev/null | grep -q "Not Found"; then
        log_error "Issue #1 not found"
        return 1
    fi
    
    # 提取JSON数据
    local body_content=$(echo "$issue_response" | jq -r '.body // empty' 2>/dev/null || echo "")
    local json_data=$(echo "$body_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # 验证JSON数据有效性
    if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
        echo "$json_data"
        return 0
    else
        log_error "Failed to extract valid JSON data from Issue #1"
        return 1
    fi
}

# 获取当前队列状态
get_current_queue_state() {
    local json_data=$(get_issue_json_data)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local queue_length=$(echo "$json_data" | jq '.queue | length' 2>/dev/null || echo "0")
    local version=$(echo "$json_data" | jq '.version' 2>/dev/null || echo "0")
    local issue_locked_by=$(echo "$json_data" | jq -r '.issue_locked_by // "null"' 2>/dev/null || echo "null")
    local build_locked_by=$(echo "$json_data" | jq -r '.build_locked_by // "null"' 2>/dev/null || echo "null")
    
    echo "queue_length=$queue_length"
    echo "version=$version"
    echo "issue_locked_by=$issue_locked_by"
    echo "build_locked_by=$build_locked_by"
    return 0
}

# 显示Issue #1的详细状态
show_issue_status() {
    local title="$1"
    log_info "$title"
    
    local json_data=$(get_issue_json_data)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "Issue #1 JSON data:"
    echo "$json_data" | jq . 2>/dev/null || echo "$json_data"
    
    local queue_length=$(echo "$json_data" | jq '.queue | length' 2>/dev/null || echo "0")
    local version=$(echo "$json_data" | jq '.version' 2>/dev/null || echo "0")
    local issue_locked_by=$(echo "$json_data" | jq -r '.issue_locked_by // "null"' 2>/dev/null || echo "null")
    local build_locked_by=$(echo "$json_data" | jq -r '.build_locked_by // "null"' 2>/dev/null || echo "null")
    
    echo "Summary:"
    echo "  Queue length: $queue_length"
    echo "  Version: $version"
    echo "  Issue locked by: $issue_locked_by"
    echo "  Build locked by: $build_locked_by"
    
    if [ "$queue_length" -gt 0 ]; then
        echo "Queue items:"
        echo "$json_data" | jq -r '.queue[] | "  - \(.run_id): \(.tag) (\(.join_time))"' 2>/dev/null || echo "  Unable to parse queue items"
    fi
}

# 验证队列操作是否真正生效
verify_queue_operation() {
    local operation="$1"
    local expected_queue_length="$2"
    local expected_version="$3"
    
    log_info "Verifying $operation operation..."
    
    # 获取操作后的Issue #1数据
    local json_data=$(get_issue_json_data)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 验证队列长度
    local actual_queue_length=$(echo "$json_data" | jq '.queue | length' 2>/dev/null || echo "0")
    if [ "$actual_queue_length" -eq "$expected_queue_length" ]; then
        log_success "$operation: Queue length is correct ($actual_queue_length)"
    else
        log_error "$operation: Queue length mismatch (Expected: $expected_queue_length, Got: $actual_queue_length)"
        return 1
    fi
    
    # 验证版本号
    local actual_version=$(echo "$json_data" | jq '.version' 2>/dev/null || echo "0")
    if [ "$actual_version" -eq "$expected_version" ]; then
        log_success "$operation: Version is correct ($actual_version)"
    else
        log_error "$operation: Version mismatch (Expected: $expected_version, Got: $actual_version)"
        return 1
    fi
    
    return 0
}

# ============================================================================
# 测试执行函数
# ============================================================================

# 运行单个测试 - 核心测试执行函数
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    local timeout="${4:-60}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    echo ""
    log_test "Running test: $test_name"
    echo "Command: $test_command"
    echo "Expected exit code: $expected_exit_code"
    echo "Timeout: ${timeout}s"
    echo "----------------------------------------"
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 显示执行进度
    echo -n "Executing test... "
    
    # 执行测试命令，确保环境变量传递
    local actual_exit_code=0
    if timeout "$timeout" bash -c "export GITHUB_TOKEN='$GITHUB_TOKEN'; export GITHUB_REPOSITORY='$GITHUB_REPOSITORY'; export GITHUB_RUN_ID='$GITHUB_RUN_ID'; $test_command" > /tmp/test_output.log 2>&1; then
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
        
        # 显示成功输出（如果有且不为空）
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

# ============================================================================
# 测试结果显示函数
# ============================================================================

# 显示测试结果摘要
show_test_results() {
    echo ""
    echo "========================================"
    echo "           TEST RESULTS SUMMARY"
    echo "========================================"
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    echo ""
    
    # 显示详细结果
    if [ ${#TEST_RESULTS[@]} -gt 0 ]; then
        echo "Detailed Results:"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == "PASS:"* ]]; then
                echo "  ✅ $result"
            else
                echo "  ❌ $result"
            fi
        done
        echo ""
    fi
    
    # 显示总体结果
    if [ $FAILED_TESTS -eq 0 ] && [ $TOTAL_TESTS -gt 0 ]; then
        log_success "All tests passed! 🎉"
    elif [ $TOTAL_TESTS -gt 0 ]; then
        log_error "Some tests failed! ❌"
    else
        log_warning "No tests were run."
    fi
    
    echo "========================================"
}

# ============================================================================
# 测试框架生命周期函数
# ============================================================================

# 测试框架初始化 - 设置环境并进行基本检查
init_test_framework() {
    export TEST_MODE=true  # 启用测试模式，使用快速重试配置
    export ENVIRONMENT=test  # 设置环境为测试
    
    # 设置测试构建暂停时间（可通过环境变量覆盖）
    export TEST_BUILD_PAUSE="${TEST_BUILD_PAUSE:-60}"  # 默认60秒
    
    setup_test_environment
}

# 测试框架清理 - 清理临时文件并显示结果
cleanup_test_framework() {
    log_step "Cleaning up test environment..."
    
    # 清理临时文件
    rm -f /tmp/test_output.log
    
    log_success "Test environment cleanup completed"
    
    # 根据测试结果返回适当的退出码
    if [ $FAILED_TESTS -eq 0 ] && [ $TOTAL_TESTS -gt 0 ]; then
        exit 0
    else
        exit 1
    fi
}