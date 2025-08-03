#!/bin/bash

# Custom Rustdesk 工作流测试脚本
# 使用 gh 命令模拟真实数据并跟踪工作流运行情况

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 全局变量
REPO=""
BUILD_ID=""
WORKFLOW_RUN_ID=""
TEST_ISSUE_NUMBER=""

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."
    
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) 未安装"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq 未安装"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI 未登录"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 获取仓库信息
get_repo_info() {
    log_info "获取仓库信息..."
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    log_success "当前仓库: $REPO"
}

# 获取工作流信息
get_workflow_info() {
    log_info "获取工作流信息..."
    local target_workflow=$(gh workflow list --json id,path | jq -r '.[] | select(.path == ".github/workflows/CustomBuildRustdesk.yml") | .id')
    
    if [ -z "$target_workflow" ]; then
        log_error "未找到目标工作流"
        exit 1
    fi
    
    log_success "工作流ID: $target_workflow"
    echo "$target_workflow"
}

# 生成测试数据
generate_test_data() {
    log_info "生成测试数据..."
    local timestamp=$(date +%s)
    BUILD_ID="test-${timestamp}"
    
    local test_data='{
        "tag": "test-build-'${timestamp}'",
        "customer": "测试客户-'${timestamp}'",
        "email": "test-'${timestamp}'@example.com",
        "super_password": "testpass'${timestamp}'",
        "rendezvous_server": "192.168.1.100",
        "api_server": "http://192.168.1.100:21114",
        "slogan": "测试标语-'${timestamp}'",
        "customer_link": "https://example.com/test-'${timestamp}'",
        "rs_pub_key": "",
        "enable_debug": true
    }'
    
    log_success "测试数据生成完成"
    echo "$test_data"
}

# 触发工作流 - workflow_dispatch
trigger_workflow_dispatch() {
    log_info "=== 触发工作流 (workflow_dispatch) ==="
    
    local workflow_id="$1"
    local test_data="$2"
    
    local tag=$(echo "$test_data" | jq -r '.tag')
    local customer=$(echo "$test_data" | jq -r '.customer')
    local email=$(echo "$test_data" | jq -r '.email')
    local super_password=$(echo "$test_data" | jq -r '.super_password')
    local rendezvous_server=$(echo "$test_data" | jq -r '.rendezvous_server')
    local api_server=$(echo "$test_data" | jq -r '.api_server')
    local slogan=$(echo "$test_data" | jq -r '.slogan')
    local customer_link=$(echo "$test_data" | jq -r '.customer_link')
    local rs_pub_key=$(echo "$test_data" | jq -r '.rs_pub_key')
    local enable_debug=$(echo "$test_data" | jq -r '.enable_debug')
    
    local trigger_result=$(gh workflow run "$workflow_id" \
        --field tag="$tag" \
        --field customer="$customer" \
        --field email="$email" \
        --field super_password="$super_password" \
        --field rendezvous_server="$rendezvous_server" \
        --field api_server="$api_server" \
        --field slogan="$slogan" \
        --field customer_link="$customer_link" \
        --field rs_pub_key="$rs_pub_key" \
        --field enable_debug="$enable_debug" 2>/dev/null && echo '{"id":"triggered","url":"https://github.com/'"$REPO"'/actions"}')
    
    if [ -n "$trigger_result" ]; then
        WORKFLOW_RUN_ID=$(echo "$trigger_result" | jq -r '.databaseId')
        local run_url=$(echo "$trigger_result" | jq -r '.url')
        
        log_success "工作流触发成功"
        log_info "运行ID: $WORKFLOW_RUN_ID"
        log_info "运行URL: $run_url"
        return 0
    else
        log_error "工作流触发失败"
        return 1
    fi
}

# 创建测试issue并触发工作流
trigger_workflow_issue() {
    log_info "=== 触发工作流 (issue) ==="
    
    local test_data="$1"
    local tag=$(echo "$test_data" | jq -r '.tag')
    local customer=$(echo "$test_data" | jq -r '.customer')
    local email=$(echo "$test_data" | jq -r '.email')
    local super_password=$(echo "$test_data" | jq -r '.super_password')
    local rendezvous_server=$(echo "$test_data" | jq -r '.rendezvous_server')
    local api_server=$(echo "$test_data" | jq -r '.api_server')
    local slogan=$(echo "$test_data" | jq -r '.slogan')
    local customer_link=$(echo "$test_data" | jq -r '.customer_link')
    local rs_pub_key=$(echo "$test_data" | jq -r '.rs_pub_key')
    
    # 导入模板函数
    source .github/workflows/scripts/issue-templates.sh
    
    local issue_title="测试构建请求 - $customer"
    local issue_body=$(generate_full_test_issue_body "$tag" "$customer" "$email" "$super_password" "$rendezvous_server" "$api_server" "$customer_link" "$rs_pub_key" "$BUILD_ID")
    
    log_info "创建测试issue..."
    
    local issue_result=$(gh issue create \
        --title "$issue_title" \
        --body "$issue_body" 2>/dev/null && echo '{"number":"created","url":"https://github.com/'"$REPO"'/issues"}')
    
    if [ -n "$issue_result" ]; then
        TEST_ISSUE_NUMBER=$(echo "$issue_result" | jq -r '.number')
        local issue_url=$(echo "$issue_result" | jq -r '.url')
        
        log_success "测试issue创建成功"
        log_info "Issue编号: #$TEST_ISSUE_NUMBER"
        log_info "Issue URL: $issue_url"
        
        log_info "等待工作流自动触发..."
        sleep 5
        
        local latest_run=$(gh run list --limit 1 --json databaseId,workflowName,status,conclusion,createdAt,url | jq -r '.[0]')
        
        if [ -n "$latest_run" ]; then
            WORKFLOW_RUN_ID=$(echo "$latest_run" | jq -r '.databaseId')
            local run_url=$(echo "$latest_run" | jq -r '.url')
            local workflow_name=$(echo "$latest_run" | jq -r '.workflowName')
            
            log_success "工作流已触发"
            log_info "运行ID: $WORKFLOW_RUN_ID"
            log_info "工作流名称: $workflow_name"
            log_info "运行URL: $run_url"
            return 0
        else
            log_error "未检测到工作流触发"
            return 1
        fi
    else
        log_error "创建测试issue失败"
        return 1
    fi
}

# 监控工作流运行状态
monitor_workflow_run() {
    log_info "=== 监控工作流运行状态 ==="
    
    local run_id="$1"
    local max_wait_time=1800
    local check_interval=30
    local elapsed_time=0
    
    log_info "开始监控工作流运行 (ID: $run_id)"
    
    while [ $elapsed_time -lt $max_wait_time ]; do
        local run_status=$(gh run view "$run_id" --json status,conclusion,createdAt,updatedAt,url,jobs 2>/dev/null || echo "")
        
        if [ -n "$run_status" ]; then
            local status=$(echo "$run_status" | jq -r '.status')
            local conclusion=$(echo "$run_status" | jq -r '.conclusion // "null"')
            local run_url=$(echo "$run_status" | jq -r '.url')
            
            log_info "状态: $status, 结论: $conclusion"
            log_info "运行URL: $run_url"
            
            if [ "$status" = "completed" ]; then
                if [ "$conclusion" = "success" ]; then
                    log_success "工作流运行成功完成！"
                    return 0
                elif [ "$conclusion" = "failure" ]; then
                    log_error "工作流运行失败！"
                    return 1
                else
                    log_warning "工作流运行完成，但结论未知: $conclusion"
                    return 3
                fi
            elif [ "$status" = "in_progress" ]; then
                log_info "工作流正在运行中..."
                local jobs=$(echo "$run_status" | jq -r '.jobs[] | "  - \(.name): \(.status) (\(.conclusion // "running"))"')
                if [ -n "$jobs" ]; then
                    log_info "作业状态:"
                    echo "$jobs"
                fi
            else
                log_info "工作流状态: $status"
            fi
        else
            log_warning "无法获取运行状态"
        fi
        
        log_info "等待 ${check_interval} 秒后重新检查..."
        sleep $check_interval
        elapsed_time=$((elapsed_time + check_interval))
        log_info "已等待: ${elapsed_time}秒 / ${max_wait_time}秒"
    done
    
    log_error "监控超时，工作流运行时间超过 ${max_wait_time} 秒"
    return 4
}

# 获取工作流运行日志
get_workflow_logs() {
    log_info "=== 获取工作流运行日志 ==="
    
    local run_id="$1"
    local log_dir="workflow_logs_${run_id}"
    
    log_info "下载工作流运行日志..."
    mkdir -p "$log_dir"
    
    gh run download "$run_id" --dir "$log_dir" 2>/dev/null || {
        log_warning "无法下载完整日志，尝试获取作业日志..."
        local jobs=$(gh run view "$run_id" --json jobs --jq '.jobs[].name')
        for job in $jobs; do
            log_info "获取作业日志: $job"
            gh run download "$run_id" --dir "$log_dir" --name "$job" 2>/dev/null || log_warning "无法下载作业 $job 的日志"
        done
    }
    
    if [ -d "$log_dir" ] && [ "$(ls -A "$log_dir" 2>/dev/null)" ]; then
        log_success "日志已下载到目录: $log_dir"
        find "$log_dir" -type f -name "*.txt" | head -5 | while read -r file; do
            log_info "  - $file"
        done
    else
        log_warning "未找到日志文件"
    fi
}

# 分析工作流运行结果
analyze_workflow_result() {
    log_info "=== 分析工作流运行结果 ==="
    
    local run_id="$1"
    local run_details=$(gh run view "$run_id" --json status,conclusion,createdAt,updatedAt,url,jobs,steps)
    
    if [ -n "$run_details" ]; then
        local status=$(echo "$run_details" | jq -r '.status')
        local conclusion=$(echo "$run_details" | jq -r '.conclusion // "null"')
        local run_url=$(echo "$run_details" | jq -r '.url')
        
        log_info "运行详情:"
        log_info "  - 状态: $status"
        log_info "  - 结论: $conclusion"
        log_info "  - 运行URL: $run_url"
        
        log_info "作业结果分析:"
        echo "$run_details" | jq -r '.jobs[] | "  - \(.name): \(.status) (\(.conclusion // "running"))"' | while read -r job_info; do
            log_info "$job_info"
        done
        
        local failed_steps=$(echo "$run_details" | jq -r '.jobs[] | select(.conclusion == "failure") | .steps[] | select(.conclusion == "failure") | "  - \(.name): \(.conclusion)"')
        
        if [ -n "$failed_steps" ]; then
            log_error "失败的步骤:"
            echo "$failed_steps"
        else
            log_success "所有步骤都成功完成"
        fi
    else
        log_error "无法获取运行详情"
    fi
}

# 清理测试资源
cleanup_test_resources() {
    log_info "=== 清理测试资源 ==="
    
    if [ -n "$TEST_ISSUE_NUMBER" ]; then
        log_info "关闭测试issue #$TEST_ISSUE_NUMBER..."
        gh issue close "$TEST_ISSUE_NUMBER" --delete-branch 2>/dev/null || log_warning "关闭issue失败"
    fi
    
    if [ -n "$WORKFLOW_RUN_ID" ]; then
        local log_dir="workflow_logs_${WORKFLOW_RUN_ID}"
        if [ -d "$log_dir" ]; then
            log_info "清理日志目录: $log_dir"
            rm -rf "$log_dir"
        fi
    fi
    
    log_success "测试资源清理完成"
}

# 主函数
main() {
    log_info "开始 Custom Rustdesk 工作流测试"
    log_info "=================================="
    
    check_dependencies
    get_repo_info
    
    local workflow_id=$(get_workflow_info)
    local test_data=$(generate_test_data)
    
    echo ""
    log_info "请选择触发方式:"
    echo "1) workflow_dispatch (手动触发)"
    echo "2) issue (创建issue触发)"
    echo "3) 两种方式都测试"
    read -p "请输入选择 (1/2/3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            if trigger_workflow_dispatch "$workflow_id" "$test_data"; then
                monitor_workflow_run "$WORKFLOW_RUN_ID"
                get_workflow_logs "$WORKFLOW_RUN_ID"
                analyze_workflow_result "$WORKFLOW_RUN_ID"
            fi
            ;;
        2)
            if trigger_workflow_issue "$test_data"; then
                monitor_workflow_run "$WORKFLOW_RUN_ID"
                get_workflow_logs "$WORKFLOW_RUN_ID"
                analyze_workflow_result "$WORKFLOW_RUN_ID"
            fi
            ;;
        3)
            log_info "测试 workflow_dispatch 方式..."
            if trigger_workflow_dispatch "$workflow_id" "$test_data"; then
                monitor_workflow_run "$WORKFLOW_RUN_ID"
                get_workflow_logs "$WORKFLOW_RUN_ID"
                analyze_workflow_result "$WORKFLOW_RUN_ID"
            fi
            
            echo ""
            log_info "测试 issue 触发方式..."
            if trigger_workflow_issue "$test_data"; then
                monitor_workflow_run "$WORKFLOW_RUN_ID"
                get_workflow_logs "$WORKFLOW_RUN_ID"
                analyze_workflow_result "$WORKFLOW_RUN_ID"
            fi
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    cleanup_test_resources
    
    log_info ""
    log_success "测试完成！"
    log_info "测试总结:"
    log_info "  - 仓库: $REPO"
    log_info "  - 构建ID: $BUILD_ID"
    if [ -n "$WORKFLOW_RUN_ID" ]; then
        log_info "  - 工作流运行ID: $WORKFLOW_RUN_ID"
    fi
    if [ -n "$TEST_ISSUE_NUMBER" ]; then
        log_info "  - 测试Issue编号: #$TEST_ISSUE_NUMBER"
    fi
}

# 清理函数
cleanup() {
    log_info "执行清理..."
    cleanup_test_resources
    log_success "清理完成"
}

# 设置退出时清理
trap cleanup EXIT

# 运行主函数
main "$@"
