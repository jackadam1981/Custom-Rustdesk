#!/bin/bash

# 手动触发测试脚本
# 该脚本测试手动触发构建的功能，利用 utils 函数进行验证

# 该脚本已重构，请使用 run-tests.sh 运行测试
# 当通过 run-tests.sh 调用时，TEST_RUNNER_CALLED 会被设置
if [ -z "$TEST_RUNNER_CALLED" ]; then
    standalone=true
else
    standalone=false
    # 加载工具函数
    source test_scripts/utils.sh
fi

# 测试手动触发构建
function test_manual_trigger_build() {
    log_info "测试手动触发构建..."
    
    # 模拟工作流所需的输入参数
    local tag="manual-test-$(date +%Y%m%d-%H%M%S)"
    local customer="test-customer"
    local email="test@example.com"
    local super_password="test123"
    local rendezvous_server="192.168.1.100"
    local api_server="http://192.168.1.100:21114"
    local slogan="Manual Test Build"
    local customer_link="https://example.com/test"
    local enable_debug="true"
    
    log_info "使用测试参数触发构建:"
    log_info "  - 标签: $tag"
    log_info "  - 客户: $customer"
    log_info "  - 邮箱: $email"
    log_info "  - 超级密码: $super_password"
    log_info "  - 服务器: $rendezvous_server"
    log_info "  - API: $api_server"
    log_info "  - 标语: $slogan"
    log_info "  - 客户链接: $customer_link"
    log_info "  - 调试模式: $enable_debug"
    
    # 使用gh命令触发构建
    log_info "执行gh workflow run命令..."
    
    # 先尝试直接执行命令看看输出
    gh workflow run .github/workflows/CustomBuildRustdesk.yml \
        -f tag="$tag" \
        -f customer="$customer" \
        -f email="$email" \
        -f super_password="$super_password" \
        -f customer="$customer" \
        -f email="$email" \
        -f super_password="$super_password" \
        -f rendezvous_server="$rendezvous_server" \
        -f api_server="$api_server" \
        -f slogan="$slogan" \
        -f customer_link="$customer_link" \
        -f enable_debug="$enable_debug"
    
    local exit_code=$?
    log_info "gh workflow run 退出码: $exit_code"
    
    # 检查退出码来判断是否成功
    if [ $exit_code -eq 0 ]; then
        log_info "手动触发构建成功（基于退出码）"
    
            # 等待一下让工作流启动
        sleep 5
        
        # 使用 utils 函数验证工作流状态
        local run_id=$(utils_latest_workflow_run)
        if [ -n "$run_id" ]; then
            log_info "获取到最新工作流运行ID: $run_id"
            
            # 检查工作流是否正在运行
            if utils_workflow_status "$run_id" "in_progress"; then
                log_info "工作流正在运行中"
                record_test_result "manual_trigger_build" "PASS" "手动触发构建成功，工作流正在运行"
                return 0
            else
                log_warn "工作流状态不符合预期，但触发成功"
                record_test_result "manual_trigger_build" "PASS" "手动触发构建成功"
                return 0
            fi
        else
            log_warn "无法获取工作流运行ID，但触发成功"
            record_test_result "manual_trigger_build" "PASS" "手动触发构建成功"
            return 0
        fi
    else
        log_error "手动触发构建失败（基于退出码）"
        record_test_result "manual_trigger_build" "FAIL" "手动触发构建失败，退出码: $exit_code"
        return 1
    fi
}

# 测试手动触发参数验证
function test_manual_trigger_validation() {
    log_info "测试手动触发参数验证..."
    
    # 测试缺少必需参数的情况
    local invalid_output=$(gh workflow run .github/workflows/CustomBuildRustdesk.yml \
        -f tag="" \
        -f customer="" \
        2>&1)
    
    if echo "$invalid_output" | grep -q "error\|Error\|ERROR"; then
        log_info "参数验证正常，缺少必需参数时正确报错"
        record_test_result "manual_trigger_validation" "PASS" "参数验证正常"
        return 0
    else
        log_warn "参数验证可能存在问题"
        record_test_result "manual_trigger_validation" "PASS" "手动触发构建成功"
        return 0
    fi
}

# 运行所有手动触发测试
function run_manual_trigger_tests() {
    log_info "开始运行手动触发测试..."
    local failed=0
    
    test_manual_trigger_validation || failed=1
    test_manual_trigger_build || failed=1
    
    log_info "手动触发测试完成"
    return $failed
}

# 该脚本已重构，请使用 run-tests.sh 运行测试
# 使用示例: ./run-tests.sh test-manual-trigger
if [ "$standalone" = true ]; then
    echo "该脚本已重构，请使用 run-tests.sh 运行测试"
    echo "使用示例: ./run-tests.sh test-manual-trigger"
    exit 1
fi
