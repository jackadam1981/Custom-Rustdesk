#!/bin/bash

# 主测试脚本
# 该脚本负责运行Custom Rustdesk构建系统的完整测试流程

# 加载测试框架
source test_scripts/test-framework.sh

# 设置默认日志级别为INFO
log_level="info"

# 检查是否提供了日志级别参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --log-level)
            log_level="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# 设置日志级别
set_log_level "$log_level"

# 初始化测试框架
init_test_framework

# 检查是否提供了特定测试名称参数
if [ $# -gt 0 ]; then
    # 设置测试环境
    if ! setup_test_environment; then
        log_error "测试环境设置失败，退出测试"
        exit 1
    fi
    test_name="$1"
    shift 1  # 移除测试名称参数，以便后续参数可以传递给测试函数
    if [ "$test_name" == "all" ]; then
        log_info "运行所有测试..."
        # 运行手动触发测试
        log_info "开始手动触发测试"
        source test_scripts/test-manual-trigger.sh
        if run_manual_trigger_tests; then
            log_info "手动触发测试完成"
        else
            log_error "手动触发测试失败"
        fi
        # 运行问题触发测试
        log_info "开始问题触发测试"
        source test_scripts/test-issue-trigger.sh
        if run_issue_trigger_tests; then
            log_info "问题触发测试完成"
        else
            log_error "问题触发测试失败"
        fi
        # 运行工作流状态测试
        log_info "开始工作流状态测试"
        source test_scripts/test-workflow-status.sh
        if run_workflow_status_tests; then
            log_info "工作流状态测试完成"
        else
            log_error "工作流状态测试失败"
        fi
        # 运行队列状态测试
        log_info "开始队列状态测试"
        source test_scripts/test-queue-status.sh
        if run_queue_status_tests; then
            log_info "队列状态测试完成"
        else
            log_error "队列状态测试失败"
        fi
        # 运行真实工作流触发测试
        log_info "开始真实工作流触发测试"
        source test_scripts/test-real-workflow-trigger.sh
        if run_real_workflow_trigger_tests; then
            log_info "真实工作流触发测试完成"
        else
            log_error "真实工作流触发测试失败"
        fi
        # 运行工具函数测试
        log_info "开始工具函数测试"
        source test_scripts/test-utils-tests.sh
        if run_utils_tests; then
            log_info "工具函数测试完成"
        else
            log_error "工具函数测试失败"
        fi
        # 显示测试结果
        show_test_results
        # 清理测试环境
        cleanup_test_framework
        # 根据测试结果设置退出码
        if [ $TEST_FAIL_COUNT -gt 0 ]; then
            exit 1
        fi
        exit 0
    else
        if run_specific_test "$test_name" "$@"; then
            log_info "测试 $test_name 完成"
        else
            log_error "测试 $test_name 失败"
        fi
        show_test_results
        cleanup_test_framework
        exit $?
    fi
else
    log_info "未提供测试参数。以下是可用的测试参数："
    log_info "  - test-manual-trigger：运行手动触发测试"
    log_info "  - test-issue-trigger：运行问题触发测试"
    log_info "  - test-workflow-status：运行工作流状态测试"
    log_info "  - test-queue-status：运行队列状态测试"
    log_info "  - test-real-workflow-trigger：运行真实工作流触发测试"
    log_info "  - test-utils：运行所有工具函数测试"
    log_info "  - test-check-queue-length：测试检查队列长度函数"
    log_info "  - test-check-queue-content：测试检查队列内容函数"
    log_info "  - test-list-queue-management：测试列出队列管理内容函数"
    log_info "  - test-check-workflow-count：测试检查工作流数量函数"
    log_info "  - test-check-workflow-status：测试检查工作流状态函数"
    log_info "  - test-read-workflow-logs：测试读取工作流日志函数"
    log_info "  - test-get-latest-workflow-run-id：测试获取最近的工作流运行ID函数"
    log_info "  - all：运行所有测试"
    log_info "使用示例：./run-tests.sh test-manual-trigger"
    log_info "可以通过 --log-level 参数设置日志级别，例如：./run-tests.sh --log-level debug test-manual-trigger"
    log_info "对于特定测试，可以传递额外参数，例如：./run-tests.sh test-check-workflow-status failure"
        exit 1
    fi
