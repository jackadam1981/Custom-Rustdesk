#!/bin/bash
# Script Name: debug_github.sh
# Description: 调试GitHub配置和token认证状态
# Author: GitHub Actions Bot
# Date: 2024-01-01
# Version: 1.0.0

set -euo pipefail # Exit on error, undefined vars, pipe failures

# Constants
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# 检查Git远程仓库配置
check_git_remote() {
  log_info "检查Git远程仓库配置..."

  echo "当前Git远程仓库配置："
  echo "----------------------------------------"
  git remote -v
  echo "----------------------------------------"

  # 检查是否有origin远程仓库
  if git remote get-url origin >/dev/null 2>&1; then
    log_success "找到origin远程仓库配置"
  else
    log_warning "未找到origin远程仓库配置"
  fi
}

# 检查GitHub Token是否存在
check_token_existence() {
  log_info "检查GitHub Token是否存在..."

  # 检查BUILD_TOKEN环境变量
  if [[ -n "${BUILD_TOKEN:-}" ]]; then
    log_success "BUILD_TOKEN secret存在且不为空"
    echo "Token长度: ${#BUILD_TOKEN} 字符"
  else
    log_warning "BUILD_TOKEN secret未定义或为空"
  fi

  # 检查GITHUB_TOKEN环境变量
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    log_success "GITHUB_TOKEN secret存在且不为空"
    echo "Token长度: ${#GITHUB_TOKEN} 字符"
  else
    log_warning "GITHUB_TOKEN secret未定义或为空"
  fi
}

# 测试Token认证
test_token_auth() {
  local token_var="${1:-BUILD_TOKEN}"
  local token_value="${!token_var}"

  log_info "测试${token_var}的认证状态..."

  if [[ -n "$token_value" ]]; then
    log_success "${token_var}在环境中可用"

    # 测试GitHub API认证
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: token $token_value" \
      https://api.github.com/user)

    echo "认证状态: $status (200表示成功)"

    if [[ "$status" == "200" ]]; then
      log_success "Token认证成功"
    else
      log_warning "Token认证失败，状态码: $status"
    fi
  else
    log_warning "${token_var}在环境中不可用"
  fi
}

# 检查GitHub API连接
check_github_api() {
  log_info "检查GitHub API连接..."

  # 测试基本连接
  local response
  response=$(curl -s -w "%{http_code}" https://api.github.com/rate_limit)
  local status_code="${response: -3}"
  local body="${response%???}"

  if [[ "$status_code" == "200" ]]; then
    log_success "GitHub API连接正常"

    # 解析速率限制信息
    local remaining
    remaining=$(echo "$body" | grep -o '"remaining":[0-9]*' | cut -d':' -f2)
    local limit
    limit=$(echo "$body" | grep -o '"limit":[0-9]*' | cut -d':' -f2)

    echo "API速率限制: $remaining/$limit 剩余请求"
  else
    log_error "GitHub API连接失败，状态码: $status_code"
  fi
}

# 显示环境信息
show_environment_info() {
  log_info "显示环境信息..."

  echo "----------------------------------------"
  echo "GitHub环境变量:"
  echo "GITHUB_REPOSITORY: ${GITHUB_REPOSITORY:-未设置}"
  echo "GITHUB_REF: ${GITHUB_REF:-未设置}"
  echo "GITHUB_SHA: ${GITHUB_SHA:-未设置}"
  echo "GITHUB_HEAD_REF: ${GITHUB_HEAD_REF:-未设置}"
  echo "----------------------------------------"

  echo "当前工作目录: $(pwd)"
  echo "Git状态:"
  git status --porcelain || log_warning "无法获取Git状态"
  echo "----------------------------------------"
}

# 主函数
main() {
  log_info "开始GitHub调试检查..."

  # 显示环境信息
  show_environment_info

  # 检查Git远程仓库
  check_git_remote

  # 检查Token存在性
  check_token_existence

  # 测试Token认证
  test_token_auth "BUILD_TOKEN"
  test_token_auth "GITHUB_TOKEN"

  # 检查GitHub API连接
  check_github_api

  log_success "GitHub调试检查完成"
}

# 帮助函数
show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Description: 调试GitHub配置和token认证状态

Options:
    -h, --help      Show this help message
    -v, --version   Show version information
    --remote-only   只检查Git远程仓库
    --token-only    只检查Token状态
    --api-only      只检查API连接

Examples:
    $SCRIPT_NAME
    $SCRIPT_NAME --remote-only
    $SCRIPT_NAME --help

EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help)
    show_help
    exit 0
    ;;
  -v | --version)
    echo "$SCRIPT_NAME version 1.0.0"
    exit 0
    ;;
  --remote-only)
    show_environment_info
    check_git_remote
    exit 0
    ;;
  --token-only)
    check_token_existence
    test_token_auth "BUILD_TOKEN"
    test_token_auth "GITHUB_TOKEN"
    exit 0
    ;;
  --api-only)
    check_github_api
    exit 0
    ;;
  *)
    log_error "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
  shift
done

# 运行主函数
main "$@"
