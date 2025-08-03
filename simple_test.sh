#!/bin/bash

# 简化的工作流测试脚本

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
    local workflows=$(gh workflow list --json id,name,path)
    log_info "可用工作流:"
    echo "$workflows" | jq -r '.[] | "  - \(.name) (\(.path))"'
    
    local target_workflow=$(echo "$workflows" | jq -r '.[] | select(.path == ".github/workflows/CustomBuildRustdesk.yml") | .id')
    
    if [ -z "$target_workflow" ]; then
        log_error "未找到目标工作流"
        exit 1
    fi
    
    log_success "目标工作流ID: $target_workflow"
    echo "$target_workflow"
}

# 测试 workflow_dispatch 触发
test_workflow_dispatch() {
    log_info "=== 测试 workflow_dispatch 触发 ==="
    
    local workflow_id="$1"
    local timestamp=$(date +%s)
    
    log_info "生成测试数据..."
    local tag="test-build-${timestamp}"
    local customer="测试客户-${timestamp}"
    local email="test-${timestamp}@example.com"
    
    log_info "触发工作流..."
    log_info "  Tag: $tag"
    log_info "  Customer: $customer"
    log_info "  Email: $email"
    
    if gh workflow run "$workflow_id" \
        --field tag="$tag" \
        --field customer="$customer" \
        --field email="$email" \
        --field super_password="testpass123" \
        --field rendezvous_server="192.168.1.100" \
        --field api_server="http://192.168.1.100:21114" \
        --field slogan="测试标语" \
        --field customer_link="https://example.com" \
        --field rs_pub_key="" \
        --field enable_debug="true"; then
        
        log_success "工作流触发成功"
        
        # 获取最新的运行
        log_info "获取最新运行信息..."
        local latest_run=$(gh run list --limit 1 --json databaseId,workflowName,status,createdAt,url | jq -r '.[0]')
        
        if [ -n "$latest_run" ]; then
            local run_id=$(echo "$latest_run" | jq -r '.id')
            local status=$(echo "$latest_run" | jq -r '.status')
            local run_url=$(echo "$latest_run" | jq -r '.url')
            
            log_success "运行信息:"
            log_info "  运行ID: $run_id"
            log_info "  状态: $status"
            log_info "  运行URL: $run_url"
            
            # 监控运行状态
            log_info "开始监控运行状态..."
            local max_wait=300  # 5分钟
            local wait_time=0
            local check_interval=30
            
            while [ $wait_time -lt $max_wait ]; do
                local run_status=$(gh run view "$run_id" --json status,conclusion 2>/dev/null || echo "")
                
                if [ -n "$run_status" ]; then
                    local current_status=$(echo "$run_status" | jq -r '.status')
                    local conclusion=$(echo "$run_status" | jq -r '.conclusion // "null"')
                    
                    log_info "当前状态: $current_status, 结论: $conclusion"
                    
                    if [ "$current_status" = "completed" ]; then
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
                    fi
                fi
                
                log_info "等待 ${check_interval} 秒后重新检查..."
                sleep $check_interval
                wait_time=$((wait_time + check_interval))
            done
            
            log_warning "监控超时，但工作流可能仍在运行"
            return 0
        else
            log_error "无法获取运行信息"
            return 1
        fi
    else
        log_error "工作流触发失败"
        return 1
    fi
}

# 测试 issue 触发
test_issue_trigger() {
    log_info "=== 测试 issue 触发 ==="
    
    local timestamp=$(date +%s)
    local tag="test-issue-${timestamp}"
    local customer="测试客户-${timestamp}"
    local email="test-${timestamp}@example.com"
    
    log_info "创建测试issue..."
    log_info "  Tag: $tag"
    log_info "  Customer: $customer"
    log_info "  Email: $email"
    
    # 导入模板函数
    source .github/workflows/scripts/issue-templates.sh
    
    local issue_title="测试构建请求 - $customer"
    local build_id="test-${timestamp}"
    local issue_body=$(generate_test_issue_body "$tag" "$customer" "$email" "$build_id")
    
    if gh issue create --title "$issue_title" --body "$issue_body"; then
        log_success "测试issue创建成功"
        
        # 等待工作流触发
        log_info "等待工作流自动触发..."
        sleep 10
        
        # 获取最新的运行
        local latest_run=$(gh run list --limit 1 --json databaseId,workflowName,status,createdAt,url | jq -r '.[0]')
        
        if [ -n "$latest_run" ]; then
            local run_id=$(echo "$latest_run" | jq -r '.databaseId')
            local status=$(echo "$latest_run" | jq -r '.status')
            local run_url=$(echo "$latest_run" | jq -r '.url')
            
            log_success "工作流已触发:"
            log_info "  运行ID: $run_id"
            log_info "  状态: $status"
            log_info "  运行URL: $run_url"
            
            return 0
        else
            log_warning "未检测到工作流触发"
            return 0
        fi
    else
        log_error "创建测试issue失败"
        return 1
    fi
}

# 主函数
main() {
    log_info "开始简化的工作流测试"
    log_info "=========================="
    
    check_dependencies
    get_repo_info
    
    local workflow_id=$(get_workflow_info)
    
    echo ""
    log_info "请选择测试方式:"
    echo "1) workflow_dispatch 触发"
    echo "2) issue 触发"
    echo "3) 两种都测试"
    read -p "请输入选择 (1/2/3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            test_workflow_dispatch "$workflow_id"
            ;;
        2)
            test_issue_trigger
            ;;
        3)
            test_workflow_dispatch "$workflow_id"
            echo ""
            test_issue_trigger
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    log_info ""
    log_success "测试完成！"
}

# 运行主函数
main "$@" 