#!/bin/bash
# 测试工具函数库

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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

# 获取Issue #1的JSON数据
get_issue_json_data() {
    local issue_response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/1")
    
    if echo "$issue_response" | jq -e '.message' | grep -q "Not Found"; then
        log_error "Issue #1 not found"
        return 1
    fi
    
    # 提取JSON数据
    local body_content=$(echo "$issue_response" | jq -r '.body // empty')
    local json_data=$(echo "$body_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
        echo "$json_data"
        return 0
    else
        log_error "Failed to extract valid JSON data from Issue #1"
        return 1
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
    local actual_queue_length=$(echo "$json_data" | jq '.queue | length')
    if [ "$actual_queue_length" -eq "$expected_queue_length" ]; then
        log_success "$operation: Queue length is correct ($actual_queue_length)"
    else
        log_error "$operation: Queue length mismatch (Expected: $expected_queue_length, Got: $actual_queue_length)"
        return 1
    fi
    
    # 验证版本号
    local actual_version=$(echo "$json_data" | jq '.version')
    if [ "$actual_version" -eq "$expected_version" ]; then
        log_success "$operation: Version is correct ($actual_version)"
    else
        log_error "$operation: Version mismatch (Expected: $expected_version, Got: $actual_version)"
        return 1
    fi
    
    return 0
}

# 获取当前队列状态
get_current_queue_state() {
    local json_data=$(get_issue_json_data)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local queue_length=$(echo "$json_data" | jq '.queue | length')
    local version=$(echo "$json_data" | jq '.version')
    local issue_locked_by=$(echo "$json_data" | jq -r '.issue_locked_by // "null"')
    local build_locked_by=$(echo "$json_data" | jq -r '.build_locked_by // "null"')
    
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
    echo "$json_data" | jq .
    
    local queue_length=$(echo "$json_data" | jq '.queue | length')
    local version=$(echo "$json_data" | jq '.version')
    local issue_locked_by=$(echo "$json_data" | jq -r '.issue_locked_by // "null"')
    local build_locked_by=$(echo "$json_data" | jq -r '.build_locked_by // "null"')
    
    echo "Summary:"
    echo "  Queue length: $queue_length"
    echo "  Version: $version"
    echo "  Issue locked by: $issue_locked_by"
    echo "  Build locked by: $build_locked_by"
    
    if [ "$queue_length" -gt 0 ]; then
        echo "Queue items:"
        echo "$json_data" | jq -r '.queue[] | "  - \(.run_id): \(.tag) (\(.join_time))"'
    fi
}

# 设置测试环境
setup_test_env() {
    log_step "Setting up test environment..."
    
    # 加载本地测试环境变量
    if [ -f "../env.sh" ]; then
        source ../env.sh
        log_info "Loaded local test environment variables"
    elif [ -f "env.sh" ]; then
        source env.sh
        log_info "Loaded local test environment variables"
    else
        log_warning "env.sh not found, using default environment"
    fi
    
    # 检查是否有真实的GitHub认证
    if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
        log_info "GitHub CLI detected, using real authentication"
        
        # 获取真实的GitHub token（如果env.sh中没有设置）
        if [ -z "$GITHUB_TOKEN" ]; then
            export GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
        fi
        
        # 获取真实的仓库信息（如果env.sh中没有设置）
        if [ -z "$GITHUB_REPOSITORY" ]; then
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
        if [ -z "$GITHUB_TOKEN" ]; then
            export GITHUB_TOKEN="test_token"
        fi
        if [ -z "$GITHUB_REPOSITORY" ]; then
            export GITHUB_REPOSITORY="test/repo"
        fi
    fi
    
    echo "Environment variables set:"
    echo "  GITHUB_RUN_ID: $GITHUB_RUN_ID"
    echo "  GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}..."  # 只显示token的前10个字符
    echo "  GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
    
    # 验证环境变量是否正确设置
    log_info "Verifying environment variables..."
    
    # 检查GITHUB_TOKEN是否为空
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "GITHUB_TOKEN is not set or empty"
        return 1
    fi
    
    # 检查GITHUB_REPOSITORY是否为空
    if [ -z "$GITHUB_REPOSITORY" ]; then
        log_error "GITHUB_REPOSITORY is not set or empty"
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
        local issue_number=$(echo "$response_body" | jq -r '.number // empty')
        if [ "$issue_number" = "1" ]; then
            log_success "Issue #1 exists and accessible"
        else
            log_error "Issue #1 not found or not accessible"
            return 1
        fi
    else
        log_error "GitHub API connection failed (HTTP $http_code)"
        if [ "$http_code" = "401" ]; then
            log_error "Authentication failed - check GITHUB_TOKEN"
        elif [ "$http_code" = "404" ]; then
            log_error "Repository not found - check GITHUB_REPOSITORY"
        fi
        return 1
    fi
    
    log_success "Test environment setup and verification completed"
} 