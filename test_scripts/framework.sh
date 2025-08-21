#!/bin/bash

# 测试框架脚本
# 该脚本提供了一个通用的测试框架，用于组织和管理单元测试

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志级别
LOG_LEVEL_ERROR=1
LOG_LEVEL_WARN=2
LOG_LEVEL_INFO=3
LOG_LEVEL_DEBUG=4

# 当前日志级别，默认为INFO
CURRENT_LOG_LEVEL=3

# 测试结果数组
TEST_RESULTS=()

# 测试统计
TEST_PASS_COUNT=0
TEST_FAIL_COUNT=0

# 是否已调用测试运行器的标志
export TEST_RUNNER_CALLED="true"

# 初始化测试框架
function init_test_framework() {
    log_info "初始化测试框架..."
    TEST_START_TIME=$(date +%s)
    TEST_FAIL_COUNT=0
    TEST_RESULTS=()
    
    # 设置日志文件
    LOG_FILE="run-tests.log"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1
    
    log_info "测试框架已初始化，日志将被写入到 $LOG_FILE"
}

# 日志函数
function log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [ $level -le $CURRENT_LOG_LEVEL ]; then
        case $level in
            $LOG_LEVEL_ERROR)
                echo "[$timestamp] [ERROR] $message" >&2
                ;;
            $LOG_LEVEL_WARN)
                echo "[$timestamp] [WARN] $message"
                ;;
            $LOG_LEVEL_INFO)
                echo "[$timestamp] [INFO] $message"
                ;;
            $LOG_LEVEL_DEBUG)
                echo "[$timestamp] [DEBUG] $message"
                ;;
        esac
    fi
}

# 错误日志
function log_error() {
    log $LOG_LEVEL_ERROR "$@"
}

# 警告日志
function log_warn() {
    log $LOG_LEVEL_WARN "$@"
}

# 信息日志
function log_info() {
    log $LOG_LEVEL_INFO "$@"
    # 移除重复的 echo 输出，避免重复日志信息
    # log 函数已经处理了输出
}

# 调试日志
function log_debug() {
    log $LOG_LEVEL_DEBUG "$@"
}

# 设置日志级别
function set_log_level() {
    local level=$1
    case $level in
        "error")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR
            log_info "日志级别设置为ERROR"
            ;;
        "warn")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN
            log_info "日志级别设置为WARN"
            ;;
        "info")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
            log_info "日志级别设置为INFO"
            ;;
        "debug")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG
            log_info "日志级别设置为DEBUG"
            ;;
        *)
            log_error "无效的日志级别: $level"
            return 1
            ;;
    esac
    return 0
}

# 设置测试环境
function setup_test_environment() {
    log_info "设置测试环境..."
    
    # 加载环境变量
    if [ -f "env.sh" ]; then
        log_info "从env.sh加载环境变量"
        source env.sh
    else
        log_warn "未找到env.sh文件，将使用默认值或环境变量"
    fi
    
    # 设置默认值
    GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-"jackadam1981/Custom-Rustdesk"}
    GITHUB_TOKEN=${GITHUB_TOKEN:-""}
    
    # 检查必要的环境变量
    if [ -z "$GITHUB_TOKEN" ] || [ "$GITHUB_TOKEN" == "YOUR_GITHUB_TOKEN" ]; then
        log_warn "未设置有效的GITHUB_TOKEN，尝试使用gh auth token获取"
        GITHUB_TOKEN=$(gh auth token)
        if [ $? -eq 0 ] && [ -n "$GITHUB_TOKEN" ]; then
            log_info "成功从gh auth token获取GITHUB_TOKEN"
            export GITHUB_TOKEN
        else
            log_error "无法从gh auth token获取GITHUB_TOKEN，请确保已使用gh auth login进行身份验证"
            return 1
        fi
    fi
    
    log_info "环境变量:"
    log_info "  GITHUB_RUN_ID: ${GITHUB_RUN_ID:-未设置}"
    log_info "  GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}... (已隐藏完整令牌)"
    log_info "  GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
    
    # 检查GitHub API连接
    log_info "测试GitHub API连接..."
    local api_response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY" -w '%{http_code}' -o /dev/null)
    if [ "$api_response" -eq 200 ]; then
        log_info "GitHub API连接成功 (HTTP $api_response)"
    else
        log_error "GitHub API连接失败 (HTTP $api_response)"
        return 1
    fi
    
    log_info "测试环境设置完成"
    return 0
}

# 记录测试结果
function record_test_result() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    # 使用 | 分隔符存储，便于后续解析
    TEST_RESULTS+=("$status|$test_name|$message")
    if [ "$status" == "PASS" ]; then
        ((TEST_PASS_COUNT++))
    else
        ((TEST_FAIL_COUNT++))
    fi
    
    if [ "$status" == "PASS" ]; then
        log_info "✅ [$test_name] 测试通过: $message"
    else
        log_error "❌ [$test_name] 测试失败: $message"
    fi
}

# 显示测试结果
function show_test_results() {
    log_info "========================================"
    log_info "             测试结果汇总"
    log_info "========================================"
    log_info "总测试数: ${#TEST_RESULTS[@]}"
    log_info "通过: $(echo -e '\033[0;32m')${TEST_PASS_COUNT}$(echo -e '\033[0m')"
    log_info "失败: $(echo -e '\033[0;31m')${TEST_FAIL_COUNT}$(echo -e '\033[0m')"
    local pass_rate=0
    if [ ${#TEST_RESULTS[@]} -gt 0 ]; then
        pass_rate=$((TEST_PASS_COUNT * 100 / ${#TEST_RESULTS[@]}))
    fi
    log_info "通过率: $pass_rate%"
    log_info ""
    log_info "详细结果:"
    for result in "${TEST_RESULTS[@]}"; do
        IFS='|' read -r status test_name message <<< "$result"
        if [ "$status" == "PASS" ]; then
            log_info "$(echo -e '\033[0;32m')✅ PASS: $test_name - $message$(echo -e '\033[0m')"
        elif [ "$status" == "FAIL" ]; then
            log_error "$(echo -e '\033[0;31m')❌ FAIL: $test_name - $message$(echo -e '\033[0m')"
        else
            log_info "$(echo -e '\033[1;33m')⚠️ SKIP: $test_name - $message$(echo -e '\033[0m')"
        fi
    done
    log_info "========================================"
    
    if [ $TEST_FAIL_COUNT -gt 0 ]; then
        return 1
    fi
    return 0
}

# 清理测试框架
function cleanup_test_framework() {
    log_info "清理测试环境..."
    log_info "测试框架清理完成"
}

# 运行特定测试
function run_specific_test() {
    local test_name="$1"
    shift  # 移除测试名称，以便后续参数可以传递给测试函数
    log_info "运行特定测试: $test_name"
    
    case "$test_name" in
        "test-manual-trigger")
            source test_scripts/manual-trigger.sh
            run_manual_trigger_tests "$@"
            return $?
            ;;
        "test-queue-reset")
            log_info "🔄 运行队列复位测试..."
            source test_scripts/utils-tests.sh
            if test_utils_queue_reset; then
                log_info "✅ 队列复位测试成功"
                return 0
            else
                log_error "❌ 队列复位测试失败"
                return 1
            fi
            ;;
        "test-issue-trigger")
            source test_scripts/issue-trigger.sh
            run_issue_trigger_tests "$@"
            return $?
            ;;
        "test-concurrent-trigger")
            source test_scripts/concurrent-trigger.sh
            run_real_workflow_trigger_tests "$@"
            return $?
            ;;
        "utils-tests")
            source test_scripts/utils-tests.sh
            run_utils_tests "$@"
            return $?
            ;;
        "utils-queue-length")
            source test_scripts/utils-tests.sh
            test_utils_queue_length "$@"
            return $?
            ;;
        "utils-queue-content")
            source test_scripts/utils-tests.sh
            test_utils_queue_content "$@"
            return $?
            ;;
        "utils-queue-management")
            source test_scripts/utils-tests.sh
            test_utils_queue_management "$@"
            return $?
            ;;
        "utils-workflow-count")
            source test_scripts/utils-tests.sh
            test_utils_workflow_count "$@"
            return $?
            ;;
        "utils-workflow-status")
            source test_scripts/utils-tests.sh
            test_utils_workflow_status "$@"
            return $?
            ;;
        "utils-workflow-logs")
            source test_scripts/utils-tests.sh
            test_utils_workflow_logs "$@"
            return $?
            ;;
        "utils-latest-workflow-run")
            source test_scripts/utils-tests.sh
            test_utils_latest_workflow_run "$@"
            return $?
            ;;
        *)
            log_error "未知的测试名称: $test_name"
            return 1
            ;;
    esac
}

# 默认设置为INFO级别日志
set_log_level "info"

log_info "测试框架已加载"
