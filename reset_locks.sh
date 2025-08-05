#!/bin/bash

# 重置锁和队列测试脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查依赖
check_deps() {
    log_info "检查依赖..."
    command -v gh >/dev/null 2>&1 || { log_error "GitHub CLI (gh) 未安装"; exit 1; }
    command -v jq >/dev/null 2>&1 || { log_error "jq 未安装"; exit 1; }
    log_success "依赖检查通过"
}

# 检查认证
check_auth() {
    log_info "检查GitHub认证..."
    gh auth status >/dev/null 2>&1 || { log_error "GitHub CLI 未认证，请运行: gh auth login"; exit 1; }
    log_success "认证检查通过"
}

# 显示当前锁状态
show_current_status() {
    log_info "显示当前锁状态..."
    
    # 获取Issue #1的内容
    local issue_content=$(gh issue view 1 --json body --jq '.body')
    
    if [ -z "$issue_content" ] || [ "$issue_content" = "null" ]; then
        log_warning "Issue #1 内容为空"
        return
    fi
    
    # 提取JSON数据（从markdown代码块中）
    local json_data=$(echo "$issue_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
        log_info "Issue #1 包含有效的JSON数据"
        
        # 显示锁状态
        local issue_locked_by=$(echo "$json_data" | jq -r '.issue_locked_by // "null"')
        local build_locked_by=$(echo "$json_data" | jq -r '.build_locked_by // "null"')
        local issue_lock_version=$(echo "$json_data" | jq -r '.issue_lock_version // "1"')
        local build_lock_version=$(echo "$json_data" | jq -r '.build_lock_version // "1"')
        local queue_length=$(echo "$json_data" | jq '.queue | length // 0')
        local version=$(echo "$json_data" | jq -r '.version // "null"')
        
        echo "当前状态:"
        echo "  版本: $version"
        echo "  Issue锁: $([ "$issue_locked_by" = "null" ] && echo "未锁定" || echo "已锁定 (持有者: $issue_locked_by)") (版本: $issue_lock_version)"
        echo "  构建锁: $([ "$build_locked_by" = "null" ] && echo "未锁定" || echo "已锁定 (持有者: $build_locked_by)") (版本: $build_lock_version)"
        echo "  队列长度: $queue_length"
        
        if [ "$queue_length" -gt 0 ]; then
            echo "  队列内容:"
            echo "$json_data" | jq -r '.queue[] | "    - \(.run_id): \(.customer) (\(.join_time))"'
        fi
    else
        log_warning "Issue #1 内容不是有效的JSON格式或未找到JSON数据"
        echo "内容预览:"
        echo "$issue_content" | head -10
    fi
}

# 重置锁和队列
reset_locks() {
    log_info "重置锁和队列..."
    
    # 创建默认的队列数据
    local default_data='{"version":1,"issue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"build_lock_version":1,"queue":[]}'
    
    # 格式化JSON数据
    local formatted_json=$(echo "$default_data" | jq .)
    
    # 使用统一模板生成内容
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local reset_reason="手动重置"
    
    # 生成重置记录
    local body_content=$(cat <<EOF
## 构建队列管理

**最后更新时间：** $current_time

### 重置记录
- **重置原因：** $reset_reason
- **重置时间：** $current_time
- **版本：** 1

### 双锁状态
- **Issue 锁状态：** 空闲 🔓
- **构建锁状态：** 空闲 🔓

### 锁持有者
- **Issue 锁持有者：** 无
- **构建锁持有者：** 无

### 当前构建标识
- **Run ID：** 未获取
- **Issue ID：** 未获取

### 构建队列
- **当前数量：** 0/5
- **Issue触发：** 0/3
- **手动触发：** 0/5

---

### 队列数据
\`\`\`json
$formatted_json
\`\`\`
EOF
)
    
    # 更新Issue #1的内容
    local update_result=$(gh issue edit 1 --body "$body_content" 2>&1)
    
    if [ $? -eq 0 ]; then
        log_success "成功重置锁和队列"
        log_info "Issue #1 已更新为默认状态"
    else
        log_error "重置失败: $update_result"
        return 1
    fi
}

# 验证重置结果
verify_reset() {
    log_info "验证重置结果..."
    
    # 等待一下让更新生效
    sleep 2
    
    # 获取更新后的内容
    local issue_content=$(gh issue view 1 --json body --jq '.body')
    
    # 提取JSON数据（从markdown代码块中）
    local json_data=$(echo "$issue_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
        local issue_locked_by=$(echo "$json_data" | jq -r '.issue_locked_by // "null"')
        local build_locked_by=$(echo "$json_data" | jq -r '.build_locked_by // "null"')
        local queue_length=$(echo "$json_data" | jq '.queue | length // 0')
        local version=$(echo "$json_data" | jq -r '.version // "null"')
        
        if [ "$issue_locked_by" = "null" ] && [ "$build_locked_by" = "null" ] && [ "$queue_length" -eq 0 ] && [ "$version" = "1" ]; then
            log_success "重置验证成功"
            echo "重置后状态:"
            echo "  版本: $version"
            echo "  Issue锁: 未锁定"
            echo "  构建锁: 未锁定"
            echo "  队列长度: $queue_length"
        else
            log_error "重置验证失败"
            echo "当前状态:"
            echo "  版本: $version"
            echo "  Issue锁: $([ "$issue_locked_by" = "null" ] && echo "未锁定" || echo "已锁定 (持有者: $issue_locked_by)")"
            echo "  构建锁: $([ "$build_locked_by" = "null" ] && echo "未锁定" || echo "已锁定 (持有者: $build_locked_by)")"
            echo "  队列长度: $queue_length"
            return 1
        fi
    else
        log_error "无法解析Issue内容或未找到JSON数据"
        return 1
    fi
}

# 显示帮助
show_help() {
    echo "重置锁和队列测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示帮助"
    echo "  -s, --status            显示当前状态"
    echo "  -r, --reset             重置锁和队列"
    echo "  -f, --full              完整重置流程（状态+重置+验证）"
    echo ""
    echo "示例:"
    echo "  $0 -s                    # 显示当前状态"
    echo "  $0 -r                    # 重置锁和队列"
    echo "  $0 -f                    # 完整重置流程"
    echo ""
}

# 主函数
main() {
    local show_status=false
    local do_reset=false
    local full_process=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--status)
                show_status=true
                shift
                ;;
            -r|--reset)
                do_reset=true
                shift
                ;;
            -f|--full)
                full_process=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "=== 重置锁和队列测试脚本 ==="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    check_deps
    check_auth
    
    if [ "$full_process" = true ]; then
        show_current_status
        echo ""
        reset_locks
        echo ""
        verify_reset
        exit 0
    fi
    
    if [ "$show_status" = true ]; then
        show_current_status
        exit 0
    fi
    
    if [ "$do_reset" = true ]; then
        reset_locks
        echo ""
        verify_reset
        exit 0
    fi
    
    log_error "请指定操作选项"
    show_help
    exit 1
}

main "$@" 