#!/bin/bash
# 环境测试脚本 - 验证GitHub API环境和基本功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 自动设置和验证环境变量
log_info "=== 自动环境变量设置和验证 ==="

# 1. 检查GitHub CLI
if ! command -v gh > /dev/null 2>&1; then
    log_error "❌ GitHub CLI (gh) not found. Please install it first."
    exit 1
fi

# 2. 检查GitHub认证状态
if ! gh auth status > /dev/null 2>&1; then
    log_error "❌ GitHub CLI not authenticated. Please run 'gh auth login' first."
    exit 1
fi

# 3. 自动获取GitHub Token
log_info "Getting GitHub token..."
export GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
if [ -z "$GITHUB_TOKEN" ]; then
    log_error "❌ Failed to get GitHub token"
    exit 1
fi
log_success "✅ GitHub token obtained"

# 4. 自动检测仓库信息
log_info "Detecting repository information..."
if [ -n "$GITHUB_REPOSITORY" ]; then
    log_info "Using existing GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
else
    # 从git remote获取仓库信息
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ "$remote_url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
        export GITHUB_REPOSITORY="${BASH_REMATCH[1]}"
        # 移除可能的.git后缀
        export GITHUB_REPOSITORY="${GITHUB_REPOSITORY%.git}"
        log_success "✅ Detected repository: $GITHUB_REPOSITORY"
    else
        log_error "❌ Could not detect repository from git remote"
        exit 1
    fi
fi

# 5. 设置运行ID
export GITHUB_RUN_ID="test_$(date +%s)"

# 6. 显示环境变量
echo "Environment variables:"
echo "  GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}..."
echo "  GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
echo "  GITHUB_RUN_ID: $GITHUB_RUN_ID"
echo ""

# 7. 验证GitHub API连接
log_info "Testing GitHub API connection..."
api_response=$(curl -s -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/1")

http_code="${api_response: -3}"
response_body="${api_response%???}"

if [ "$http_code" = "200" ]; then
    log_success "✅ GitHub API connection successful (HTTP 200)"
    
    # 验证Issue #1存在
    issue_number=$(echo "$response_body" | jq -r '.number // empty')
    if [ "$issue_number" = "1" ]; then
        log_success "✅ Issue #1 exists and accessible"
    else
        log_error "❌ Issue #1 not found or not accessible"
        exit 1
    fi
else
    log_error "❌ GitHub API connection failed (HTTP $http_code)"
    if [ "$http_code" = "401" ]; then
        log_error "Authentication failed - check GITHUB_TOKEN"
    elif [ "$http_code" = "404" ]; then
        log_error "Repository not found - check GITHUB_REPOSITORY"
    fi
    exit 1
fi

log_success "✅ Environment setup and verification completed"
echo ""



# 测试1: 直接执行方式验证
log_info "=== 测试1: 直接执行方式 ==="
if source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"test-tag","email":"test@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'; then
    log_success "✅ 直接执行方式验证通过"
else
    log_error "❌ 直接执行方式验证失败"
fi
echo ""

# 测试2: 子shell执行方式验证
log_info "=== 测试2: 子shell执行方式 ==="
if bash -c "export GITHUB_TOKEN='$GITHUB_TOKEN'; export GITHUB_REPOSITORY='$GITHUB_REPOSITORY'; export GITHUB_RUN_ID='$GITHUB_RUN_ID'; source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{\"tag\":\"test-tag\",\"email\":\"test@example.com\",\"customer\":\"test-customer\",\"trigger_type\":\"workflow_dispatch\"}'"; then
    log_success "✅ 子shell执行方式验证通过"
else
    log_error "❌ 子shell执行方式验证失败"
fi
echo ""

# 测试3: GitHub API连接验证
log_info "=== 测试3: GitHub API连接 ==="
if gh issue view 1 --repo jackadam1981/Custom-Rustdesk | grep -A 10 "队列数据"; then
    log_success "✅ GitHub API连接验证通过"
else
    log_error "❌ GitHub API连接验证失败"
fi
echo ""

log_info "=== 环境测试完成 ===" 