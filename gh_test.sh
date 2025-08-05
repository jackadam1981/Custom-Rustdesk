#!/bin/bash

# GitHub CLI 工作流测试脚本
# 用于直接推送模拟真实信息到GitHub Actions进行工作流测试

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }
log_debug() { echo -e "${CYAN}[DEBUG]${NC} $1"; }

# 全局变量
REPO_OWNER=""
REPO_NAME=""
TIMESTAMP=""
TEST_TAG=""
TEST_EMAIL=""
TEST_CUSTOMER=""
TEST_SLOGAN=""

# 检查依赖
check_dependencies() {
    log_step "检查依赖..."
    
    # 检查gh CLI
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) 未安装"
        log_info "请访问: https://cli.github.com/ 安装GitHub CLI"
        exit 1
    fi
    
    # 检查jq
    if ! command -v jq &> /dev/null; then
        log_error "jq 未安装"
        log_info "请安装jq: sudo apt install jq"
        exit 1
    fi
    
    # 检查是否在Git仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "当前目录不是Git仓库"
        log_info "请确保在Git仓库根目录中运行此脚本"
        exit 1
    fi
    
    log_success "依赖检查通过"
}

# 检查GitHub认证
check_github_auth() {
    log_step "检查GitHub认证..."
    
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI 未认证"
        log_info "请运行: gh auth login"
        exit 1
    fi
    
    # 获取当前用户信息
    CURRENT_USER=$(gh api user --jq '.login')
    log_info "当前用户: $CURRENT_USER"
    
    # 获取当前仓库信息
    REPO_INFO=$(gh repo view --json name,owner,url 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_error "无法获取仓库信息，请确保在Git仓库中运行此脚本"
        exit 1
    fi
    REPO_NAME=$(echo "$REPO_INFO" | jq -r '.name')
    REPO_OWNER=$(echo "$REPO_INFO" | jq -r '.owner.login')
    REPO_URL=$(echo "$REPO_INFO" | jq -r '.url')
    
    log_info "当前仓库: $REPO_OWNER/$REPO_NAME"
    log_info "仓库地址: $REPO_URL"
    
    log_success "GitHub认证检查通过"
}

# 获取工作流信息
get_workflow_info() {
    log_step "获取工作流信息..."
    
    # 获取工作流列表
    WORKFLOWS=$(gh api repos/$REPO_OWNER/$REPO_NAME/actions/workflows 2>/dev/null)
    if [ $? -ne 0 ]; then
        log_error "无法获取工作流列表，请检查仓库权限"
        exit 1
    fi
    WORKFLOW_COUNT=$(echo "$WORKFLOWS" | jq '.total_count')
    
    log_info "找到 $WORKFLOW_COUNT 个工作流"
    
    # 查找主构建工作流
    MAIN_WORKFLOW=$(echo "$WORKFLOWS" | jq -r '.workflows[] | select(.name == "Custom Rustdesk Build Workflow") | {id: .id, name: .name, path: .path}')
    
    if [ -z "$MAIN_WORKFLOW" ] || [ "$MAIN_WORKFLOW" = "null" ]; then
        log_error "未找到主构建工作流 'Custom Rustdesk Build Workflow'"
        log_info "可用的工作流:"
        echo "$WORKFLOWS" | jq -r '.workflows[] | "  - \(.name) (\(.path))"'
        exit 1
    fi
    
    WORKFLOW_ID=$(echo "$MAIN_WORKFLOW" | jq -r '.id')
    WORKFLOW_NAME=$(echo "$MAIN_WORKFLOW" | jq -r '.name')
    WORKFLOW_PATH=$(echo "$MAIN_WORKFLOW" | jq -r '.path')
    
    log_info "主构建工作流: $WORKFLOW_NAME"
    log_info "工作流ID: $WORKFLOW_ID"
    log_info "工作流路径: $WORKFLOW_PATH"
    
    # 检查工作流文件是否存在
    if [ ! -f ".github/workflows/CustomBuildRustdesk.yml" ]; then
        log_warning "本地工作流文件不存在: .github/workflows/CustomBuildRustdesk.yml"
        log_info "这可能会影响工作流触发，请确保工作流文件已提交到仓库"
    else
        log_info "本地工作流文件存在: .github/workflows/CustomBuildRustdesk.yml"
    fi
    
    log_success "工作流信息获取成功"
}

# 生成测试数据
generate_test_data() {
    log_step "生成测试数据..."
    
    # 生成时间戳
    TIMESTAMP=$(date +%s)
    TEST_TAG="gh-test-$TIMESTAMP"
    TEST_EMAIL="gh-test-$TIMESTAMP@example.com"
    TEST_CUSTOMER="GitHub CLI测试客户"
    TEST_SLOGAN="GitHub CLI测试构建"
    
    # 验证测试数据
    if [ -z "$TIMESTAMP" ] || [ -z "$TEST_TAG" ] || [ -z "$TEST_EMAIL" ]; then
        log_error "测试数据生成失败"
        return 1
    fi
    
    log_info "测试标签: $TEST_TAG"
    log_info "测试邮箱: $TEST_EMAIL"
    log_info "测试客户: $TEST_CUSTOMER"
    log_info "测试标语: $TEST_SLOGAN"
    
    log_success "测试数据生成完成"
}

# 测试手动触发工作流
test_workflow_dispatch() {
    log_step "测试手动触发工作流..."
    
    log_info "使用workflow_dispatch事件触发工作流..."
    
    # 触发工作流
    log_debug "执行命令: gh workflow run CustomBuildRustdesk.yml --field tag=$TEST_TAG --field email=$TEST_EMAIL ..."
    
    TRIGGER_RESULT=$(gh workflow run "CustomBuildRustdesk.yml" \
        --field tag="$TEST_TAG" \
        --field email="$TEST_EMAIL" \
        --field customer="$TEST_CUSTOMER" \
        --field customer_link="https://github.com/$REPO_OWNER/$REPO_NAME" \
        --field super_password="gh-test-password-$TIMESTAMP" \
        --field slogan="$TEST_SLOGAN" \
        --field rendezvous_server="192.168.1.100:21117" \
        --field rs_pub_key="gh-test-public-key-$TIMESTAMP" \
        --field api_server="http://192.168.1.100:21114" 2>&1)
    
    TRIGGER_EXIT_CODE=$?
    
    if [ $TRIGGER_EXIT_CODE -eq 0 ]; then
        log_success "工作流触发成功"
        log_info "触发结果: $TRIGGER_RESULT"
        
        # 等待一下让工作流启动
        log_info "等待3秒让工作流启动..."
        sleep 3
        
        # 获取最新的运行ID
        log_debug "获取最新运行信息..."
        LATEST_RUN=$(gh run list --workflow="CustomBuildRustdesk.yml" --limit 1 --json databaseId,status,createdAt,url 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$LATEST_RUN" ]; then
            RUN_ID=$(echo "$LATEST_RUN" | jq -r '.[0].databaseId // empty')
            RUN_URL=$(echo "$LATEST_RUN" | jq -r '.[0].url // empty')
            
            if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]; then
                log_info "运行ID: $RUN_ID"
                log_info "运行URL: $RUN_URL"
                echo "$RUN_ID" > .gh_test_run_id
                echo "$RUN_URL" > .gh_test_run_url
                return 0
            else
                log_warning "无法获取运行ID"
                return 1
            fi
        else
            log_warning "无法获取最新运行信息"
            return 1
        fi
    else
        log_error "工作流触发失败"
        log_error "错误信息: $TRIGGER_RESULT"
        log_error "退出代码: $TRIGGER_EXIT_CODE"
        return 1
    fi
}

# 测试Issue触发工作流
test_issue_trigger() {
    log_step "测试Issue触发工作流..."
    
    # 创建测试Issue
    ISSUE_TITLE="[build] GitHub CLI测试构建 - $TEST_TAG"
    ISSUE_BODY="tag: $TEST_TAG
email: $TEST_EMAIL
customer: $TEST_CUSTOMER
customer_link: https://github.com/$REPO_OWNER/$REPO_NAME
super_password: gh-test-password-$TIMESTAMP
slogan: $TEST_SLOGAN
rendezvous_server: 192.168.1.100:21117
rs_pub_key: gh-test-public-key-$TIMESTAMP
api_server: http://192.168.1.100:21114

---
这是一个GitHub CLI测试创建的构建请求。
测试时间: $(date '+%Y-%m-%d %H:%M:%S')
测试标签: $TEST_TAG"
    
    log_info "创建测试Issue..."
    log_info "Issue标题: $ISSUE_TITLE"
    log_debug "Issue内容预览:"
    echo "$ISSUE_BODY" | head -10 | sed 's/^/  /'
    echo "  ..."
    
    # 创建Issue
    log_debug "执行命令: gh issue create --title \"$ISSUE_TITLE\" --body \"...\""
    
    ISSUE_RESULT=$(gh issue create \
        --title "$ISSUE_TITLE" \
        --body "$ISSUE_BODY" 2>&1)
    
    ISSUE_EXIT_CODE=$?
    
    if [ $ISSUE_EXIT_CODE -eq 0 ]; then
        log_success "Issue创建成功"
        log_info "Issue结果: $ISSUE_RESULT"
        
        # 提取Issue编号
        ISSUE_NUMBER=$(echo "$ISSUE_RESULT" | grep -o 'issues/[0-9]\+' | head -1 | sed 's/issues\///')
        if [ -n "$ISSUE_NUMBER" ]; then
            log_info "Issue编号: #$ISSUE_NUMBER"
            echo "$ISSUE_NUMBER" > .gh_test_issue_id
            echo "$ISSUE_RESULT" > .gh_test_issue_info
            
            # 显示Issue链接
            ISSUE_URL="https://github.com/$REPO_OWNER/$REPO_NAME/issues/$ISSUE_NUMBER"
            log_info "Issue链接: $ISSUE_URL"
            echo "$ISSUE_URL" > .gh_test_issue_url
            
            return 0
        else
            log_warning "无法提取Issue编号"
            return 1
        fi
    else
        log_error "Issue创建失败"
        log_error "错误信息: $ISSUE_RESULT"
        log_error "退出代码: $ISSUE_EXIT_CODE"
        return 1
    fi
}

# 监控工作流运行状态
monitor_workflow_run() {
    local run_id="$1"
    local max_wait=300  # 最大等待5分钟
    local wait_interval=10  # 每10秒检查一次
    local elapsed=0
    
    log_step "监控工作流运行状态 (运行ID: $run_id)..."
    
    while [ $elapsed -lt $max_wait ]; do
        # 获取运行状态
        log_debug "检查运行状态 (已等待 ${elapsed}秒)..."
        RUN_STATUS=$(gh run view "$run_id" --json status,conclusion,url 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$RUN_STATUS" ]; then
            STATUS=$(echo "$RUN_STATUS" | jq -r '.status // "unknown"')
            CONCLUSION=$(echo "$RUN_STATUS" | jq -r '.conclusion // "null"')
            URL=$(echo "$RUN_STATUS" | jq -r '.url // "unknown"')
            
            log_info "状态: $STATUS, 结论: $CONCLUSION"
            
            if [ "$STATUS" = "completed" ]; then
                if [ "$CONCLUSION" = "success" ]; then
                    log_success "工作流运行成功完成"
                    log_info "运行详情: $URL"
                    return 0
                elif [ "$CONCLUSION" = "failure" ]; then
                    log_error "工作流运行失败"
                    log_info "运行详情: $URL"
                    return 1
                elif [ "$CONCLUSION" = "cancelled" ]; then
                    log_warning "工作流运行被取消"
                    log_info "运行详情: $URL"
                    return 1
                else
                    log_warning "工作流运行完成，但结论未知: $CONCLUSION"
                    log_info "运行详情: $URL"
                    return 1
                fi
            elif [ "$STATUS" = "in_progress" ]; then
                log_info "工作流正在运行中... (已等待 ${elapsed}秒)"
            elif [ "$STATUS" = "queued" ]; then
                log_info "工作流正在排队中... (已等待 ${elapsed}秒)"
            else
                log_info "工作流状态: $STATUS (已等待 ${elapsed}秒)"
            fi
        else
            log_warning "无法获取运行状态 (已等待 ${elapsed}秒)"
        fi
        
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    log_error "监控超时 (${max_wait}秒)"
    return 1
}

# 获取工作流日志
get_workflow_logs() {
    local run_id="$1"
    
    log_step "获取工作流日志 (运行ID: $run_id)..."
    
    # 下载日志
    LOG_DIR="workflow_logs_$run_id"
    mkdir -p "$LOG_DIR"
    
    log_info "下载工作流日志到目录: $LOG_DIR"
    
    if gh run download "$run_id" --dir "$LOG_DIR" 2>/dev/null; then
        log_success "日志下载成功"
        log_info "日志目录: $LOG_DIR"
        
        # 显示主要日志文件
        if [ -f "$LOG_DIR/1_trigger.txt" ]; then
            log_info "触发步骤日志:"
            head -10 "$LOG_DIR/1_trigger.txt" | sed 's/^/  /'
            echo "  ..."
        fi
        
        if [ -f "$LOG_DIR/2_review.txt" ]; then
            log_info "审核步骤日志:"
            head -10 "$LOG_DIR/2_review.txt" | sed 's/^/  /'
            echo "  ..."
        fi
        
        if [ -f "$LOG_DIR/3_join-queue.txt" ]; then
            log_info "队列步骤日志:"
            head -10 "$LOG_DIR/3_join-queue.txt" | sed 's/^/  /'
            echo "  ..."
        fi
        
        if [ -f "$LOG_DIR/4_build.txt" ]; then
            log_info "构建步骤日志:"
            head -10 "$LOG_DIR/4_build.txt" | sed 's/^/  /'
            echo "  ..."
        fi
        
        if [ -f "$LOG_DIR/5_finish.txt" ]; then
            log_info "完成步骤日志:"
            head -10 "$LOG_DIR/5_finish.txt" | sed 's/^/  /'
            echo "  ..."
        fi
    else
        log_warning "日志下载失败或日志不可用"
    fi
}

# 清理测试资源
cleanup_test_resources() {
    log_step "清理测试资源..."
    
    # 清理临时文件
    rm -f .gh_test_run_id .gh_test_run_url .gh_test_issue_id .gh_test_issue_info .gh_test_issue_url
    
    # 清理日志目录
    for log_dir in workflow_logs_*; do
        if [ -d "$log_dir" ]; then
            rm -rf "$log_dir"
            log_info "清理日志目录: $log_dir"
        fi
    done
    
    # 清理GitHub Actions运行记录
    cleanup_workflow_runs
    
    # 清理测试Issue（除#1外）
    cleanup_test_issues
    
    log_success "测试资源清理完成"
}

# 清理工作流运行记录
cleanup_workflow_runs() {
    log_step "清理工作流运行记录..."
    
    # 获取所有已完成的运行记录
    log_info "获取所有已完成的workflow runs..."
    RUNS_DATA=$(gh api repos/$REPO_OWNER/$REPO_NAME/actions/runs --paginate --jq '.workflow_runs[] | select(.status == "completed") | {id: .id, name: .name, created_at: .created_at}' 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$RUNS_DATA" ]; then
        RUNS_COUNT=$(echo "$RUNS_DATA" | grep -c '^{' || echo "0")
        log_info "找到 $RUNS_COUNT 个已完成的workflow runs"
        
        if [ $RUNS_COUNT -gt 0 ]; then
            DELETED_COUNT=0
            FAILED_COUNT=0
            
            echo "$RUNS_DATA" | jq -c '.' | while read -r run; do
                RUN_ID=$(echo "$run" | jq -r '.id')
                RUN_NAME=$(echo "$run" | jq -r '.name')
                
                if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]; then
                    log_info "删除 Workflow Run #$RUN_ID ($RUN_NAME)..."
                    
                    if gh api repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID -X DELETE 2>/dev/null; then
                        DELETED_COUNT=$((DELETED_COUNT + 1))
                        log_success "成功删除 Workflow Run #$RUN_ID"
                    else
                        FAILED_COUNT=$((FAILED_COUNT + 1))
                        log_warning "删除 Workflow Run #$RUN_ID 失败"
                    fi
                    
                    # 添加短暂延迟，避免API限制
                    sleep 1
                fi
            done
            
            if [ $DELETED_COUNT -gt 0 ]; then
                log_success "清理完成：成功 $DELETED_COUNT 个，失败 $FAILED_COUNT 个"
            else
                log_info "没有成功删除的运行记录"
            fi
        else
            log_info "没有找到已完成的workflow runs"
        fi
    else
        log_warning "无法获取workflow runs或没有运行记录"
    fi
    
    # 显示剩余runs数量
    REMAINING=$(gh api repos/$REPO_OWNER/$REPO_NAME/actions/runs --jq '.total_count' 2>/dev/null || echo "未知")
    log_info "剩余workflow runs总数：$REMAINING"
}

# 清理测试Issue（除#1外）
cleanup_test_issues() {
    log_step "清理测试Issue（除#1外）..."
    
    # 获取所有Issue（除#1外）
    log_info "获取所有Issue列表..."
    OPEN_ISSUES=$(gh issue list --repo $REPO_OWNER/$REPO_NAME --state open --limit 100 --json number,title 2>/dev/null | jq -r '.[] | select(.number != 1) | .number')
    CLOSED_ISSUES=$(gh issue list --repo $REPO_OWNER/$REPO_NAME --state closed --limit 100 --json number,title 2>/dev/null | jq -r '.[] | select(.number != 1) | .number')
    ISSUES_TO_DELETE=$(echo -e "$OPEN_ISSUES\n$CLOSED_ISSUES" | grep -v '^$' | sort -n | uniq)
    
    if [ -z "$ISSUES_TO_DELETE" ]; then
        log_info "✅ 没有需要删除的issues"
        return 0
    fi
    
    ISSUE_COUNT=$(echo "$ISSUES_TO_DELETE" | wc -l)
    log_info "找到 $ISSUE_COUNT 个issues需要删除"
    
    DELETED_COUNT=0
    FAILED_COUNT=0
    
    for issue in $ISSUES_TO_DELETE; do
        if [ -n "$issue" ] && [ "$issue" != "1" ]; then
            log_info "删除 Issue #$issue..."
            
            if gh issue delete $issue --repo $REPO_OWNER/$REPO_NAME --yes 2>/dev/null; then
                DELETED_COUNT=$((DELETED_COUNT + 1))
                log_success "✅ 删除 Issue #$issue 成功"
            else
                FAILED_COUNT=$((FAILED_COUNT + 1))
                log_warning "❌ 删除 Issue #$issue 失败"
            fi
            
            # 添加短暂延迟，避免API限制
            sleep 1
        fi
    done
    
    if [ $DELETED_COUNT -gt 0 ]; then
        log_success "删除完成：成功 $DELETED_COUNT 个，失败 $FAILED_COUNT 个"
    else
        log_info "没有成功删除的issues"
    fi
    
    # 显示剩余issues
    REMAINING=$(gh issue list --repo $REPO_OWNER/$REPO_NAME --limit 100 --json number 2>/dev/null | jq -r '.[] | .number' | tr '\n' ' ')
    log_info "剩余issues：$REMAINING"
}

# 显示测试结果摘要
show_test_summary() {
    log_step "测试结果摘要..."
    
    echo ""
    echo "=== 测试结果摘要 ==="
    echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "测试标签: $TEST_TAG"
    echo "测试邮箱: $TEST_EMAIL"
    echo ""
    
    # 显示工作流运行信息
    if [ -f ".gh_test_run_id" ]; then
        RUN_ID=$(cat .gh_test_run_id)
        RUN_URL=$(cat .gh_test_run_url 2>/dev/null || echo "未知")
        echo "工作流运行:"
        echo "  运行ID: $RUN_ID"
        echo "  运行URL: $RUN_URL"
        echo ""
    fi
    
    # 显示Issue信息
    if [ -f ".gh_test_issue_id" ]; then
        ISSUE_NUMBER=$(cat .gh_test_issue_id)
        ISSUE_URL=$(cat .gh_test_issue_url 2>/dev/null || echo "未知")
        echo "测试Issue:"
        echo "  Issue编号: #$ISSUE_NUMBER"
        echo "  Issue链接: $ISSUE_URL"
        echo ""
    fi
    
    echo "=== 摘要结束 ==="
    echo ""
}

# 显示帮助信息
show_help() {
    echo "GitHub CLI 工作流测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -t, --trigger TYPE      指定触发类型 (w|workflow_dispatch|i|issue)"
    echo "  -m, --monitor           监控上次运行的工作流"
    echo "  -l, --logs              下载工作流日志"
    echo "  -c, --cleanup           清理测试资源（包括runs和测试issue）"
    echo "  -f, --full              执行完整测试流程"
    echo "  -d, --debug             启用调试模式"
    echo ""
    echo "清理功能说明:"
    echo "  - 删除本地临时文件和日志目录"
    echo "  - 删除已完成的工作流运行记录"
    echo "  - 删除测试创建的Issue（除#1外）"
    echo ""
    echo "示例:"
    echo "  $0 -t w                    # 测试手动触发"
    echo "  $0 -t i                    # 测试Issue触发"
    echo "  $0 -t workflow_dispatch    # 测试手动触发（完整名称）"
    echo "  $0 -t issue                # 测试Issue触发（完整名称）"
    echo "  $0 -f                      # 执行完整测试"
    echo "  $0 -m                      # 监控上次运行"
    echo "  $0 -l                      # 下载上次运行日志"
    echo "  $0 -c                      # 清理测试资源"
    echo ""
}

# 主函数
main() {
    local trigger_type=""
    local monitor_only=false
    local logs_only=false
    local cleanup_only=false
    local full_test=false
    local debug_mode=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -t|--trigger)
                trigger_type="$2"
                shift 2
                ;;
            -m|--monitor)
                monitor_only=true
                shift
                ;;
            -l|--logs)
                logs_only=true
                shift
                ;;
            -c|--cleanup)
                cleanup_only=true
                shift
                ;;
            -f|--full)
                full_test=true
                shift
                ;;
            -d|--debug)
                debug_mode=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 启用调试模式
    if [ "$debug_mode" = true ]; then
        set -x
    fi
    
    # 显示脚本信息
    echo "=== GitHub CLI 工作流测试脚本 ==="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 检查依赖
    check_dependencies
    
    # 检查GitHub认证
    check_github_auth
    
    # 获取工作流信息
    get_workflow_info
    
    # 根据选项执行相应操作
    if [ "$cleanup_only" = true ]; then
        cleanup_test_resources
        exit 0
    fi
    
    if [ "$monitor_only" = true ]; then
        if [ -f ".gh_test_run_id" ]; then
            RUN_ID=$(cat .gh_test_run_id)
            monitor_workflow_run "$RUN_ID"
        else
            log_error "未找到运行ID文件，请先执行测试"
            exit 1
        fi
        exit 0
    fi
    
    if [ "$logs_only" = true ]; then
        if [ -f ".gh_test_run_id" ]; then
            RUN_ID=$(cat .gh_test_run_id)
            get_workflow_logs "$RUN_ID"
        else
            log_error "未找到运行ID文件，请先执行测试"
            exit 1
        fi
        exit 0
    fi
    
    if [ "$full_test" = true ]; then
        # 生成测试数据
        generate_test_data
        
        # 测试手动触发
        log_step "=== 测试手动触发 ==="
        if test_workflow_dispatch; then
            if [ -f ".gh_test_run_id" ]; then
                RUN_ID=$(cat .gh_test_run_id)
                log_info "等待5秒后开始监控..."
                sleep 5
                monitor_workflow_run "$RUN_ID"
                get_workflow_logs "$RUN_ID"
            fi
        fi
        
        # 等待一段时间后测试Issue触发
        log_info "等待10秒后测试Issue触发..."
        sleep 10
        
        # 测试Issue触发
        log_step "=== 测试Issue触发 ==="
        if test_issue_trigger; then
            log_info "Issue触发测试完成，请手动检查工作流是否被触发"
        fi
        
        # 显示测试摘要
        show_test_summary
        exit 0
    fi
    
    # 根据触发类型执行测试
    if [ -n "$trigger_type" ]; then
        # 生成测试数据
        generate_test_data
        
        case "$trigger_type" in
            w|workflow_dispatch)
                log_step "=== 测试手动触发 ==="
                if test_workflow_dispatch; then
                    if [ -f ".gh_test_run_id" ]; then
                        RUN_ID=$(cat .gh_test_run_id)
                        log_info "等待5秒后开始监控..."
                        sleep 5
                        monitor_workflow_run "$RUN_ID"
                        get_workflow_logs "$RUN_ID"
                    fi
                fi
                ;;
            i|issue)
                log_step "=== 测试Issue触发 ==="
                if test_issue_trigger; then
                    log_info "Issue触发测试完成，请手动检查工作流是否被触发"
                fi
                ;;
            *)
                log_error "不支持的触发类型: $trigger_type"
                log_info "支持的触发类型: w/workflow_dispatch, i/issue"
                exit 1
                ;;
        esac
        
        # 显示测试摘要
        show_test_summary
    else
        log_error "请指定触发类型或使用 -f 执行完整测试"
        show_help
        exit 1
    fi
    
    log_success "测试完成"
}

# 执行主函数
main "$@" 