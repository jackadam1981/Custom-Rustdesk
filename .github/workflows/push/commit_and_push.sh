#!/bin/bash
# Script Name: commit_and_push.sh
# Description: 配置Git用户信息，提交文件并推送到远程仓库
# Author: GitHub Actions Bot
# Date: 2024-01-01
# Version: 1.0.0

set -euo pipefail # Exit on error, undefined vars, pipe failures

# Constants
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEFAULT_USER_EMAIL="github-actions[bot]@users.noreply.github.com"
DEFAULT_USER_NAME="github-actions[bot]"
DEFAULT_COMMIT_MESSAGE="Add hello workflow with random name"
DEFAULT_BRANCH="main"

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

# 配置Git用户信息
configure_git_user() {
  local user_email="${1:-$DEFAULT_USER_EMAIL}"
  local user_name="${2:-$DEFAULT_USER_NAME}"

  log_info "配置Git用户信息..."

  # 设置用户邮箱
  git config --local user.email "$user_email"
  log_success "设置用户邮箱: $user_email"

  # 设置用户名
  git config --local user.name "$user_name"
  log_success "设置用户名: $user_name"

  # 验证配置
  echo "当前Git配置:"
  echo "  Email: $(git config --local user.email)"
  echo "  Name: $(git config --local user.name)"
}

# 检查Git状态
check_git_status() {
  log_info "检查Git状态..."

  # 检查是否有未提交的更改
  if [[ -n "$(git status --porcelain)" ]]; then
    log_info "发现未提交的更改:"
    git status --short
    return 0
  else
    log_warning "没有发现需要提交的更改"
    return 1
  fi
}

# 添加文件到暂存区
stage_files() {
  local files_to_add="${1:-.}"

  log_info "添加文件到暂存区: $files_to_add"

  # 添加指定文件或所有文件
  if git add "$files_to_add"; then
    log_success "文件已添加到暂存区"

    # 显示暂存区状态
    echo "暂存区状态:"
    git status --short
  else
    log_error "添加文件到暂存区失败"
    return 1
  fi
}

# 提交更改
commit_changes() {
  local commit_message="${1:-$DEFAULT_COMMIT_MESSAGE}"

  log_info "提交更改..."
  log_info "提交信息: $commit_message"

  # 检查是否有文件在暂存区
  if [[ -n "$(git diff --cached --name-only)" ]]; then
    if git commit -m "$commit_message"; then
      log_success "更改已提交"

      # 显示提交信息
      echo "最新提交:"
      git log --oneline -1
    else
      log_error "提交更改失败"
      return 1
    fi
  else
    log_warning "暂存区中没有文件，跳过提交"
    return 1
  fi
}

# 配置远程仓库URL
configure_remote_url() {
  local token="${1:-}"
  local repository="${2:-}"

  if [[ -z "$token" ]]; then
    log_error "未提供GitHub Token"
    return 1
  fi

  if [[ -z "$repository" ]]; then
    log_error "未提供仓库名称"
    return 1
  fi

  log_info "配置远程仓库URL..."

  # 构建包含token的URL
  local remote_url="https://x-access-token:$token@github.com/$repository.git"

  # 设置远程URL
  if git remote set-url origin "$remote_url"; then
    log_success "远程仓库URL已配置"
    echo "远程URL: https://x-access-token:***@github.com/$repository.git"
  else
    log_error "配置远程仓库URL失败"
    return 1
  fi
}

# 推送到远程仓库
push_to_remote() {
  local branch="${1:-$DEFAULT_BRANCH}"
  local force_push="${2:-false}"

  log_info "推送到远程仓库..."
  log_info "目标分支: $branch"

  if [[ "$force_push" == "true" ]]; then
    log_warning "使用强制推送模式"
    if git push -f origin "$branch"; then
      log_success "强制推送成功"
    else
      log_error "强制推送失败"
      return 1
    fi
  else
    if git push origin "$branch"; then
      log_success "推送成功"
    else
      log_error "推送失败"
      return 1
    fi
  fi
}

# 显示推送结果
show_push_result() {
  log_info "推送结果信息..."

  echo "----------------------------------------"
  echo "当前分支: $(git branch --show-current)"
  echo "最新提交:"
  git log --oneline -1
  echo "远程仓库:"
  git remote -v
  echo "----------------------------------------"
}

# 主函数
main() {
  local user_email="${GIT_USER_EMAIL:-$DEFAULT_USER_EMAIL}"
  local user_name="${GIT_USER_NAME:-$DEFAULT_USER_NAME}"
  local commit_message="${COMMIT_MESSAGE:-$DEFAULT_COMMIT_MESSAGE}"
  local branch="${TARGET_BRANCH:-$DEFAULT_BRANCH}"
  local force_push="${FORCE_PUSH:-false}"
  local files_to_add="${FILES_TO_ADD:-.}"

  log_info "开始Git提交和推送流程..."

  # 配置Git用户信息
  configure_git_user "$user_email" "$user_name"

  # 检查Git状态
  if ! check_git_status; then
    log_warning "没有需要提交的更改，退出"
    exit 0
  fi

  # 添加文件到暂存区
  if ! stage_files "$files_to_add"; then
    log_error "添加文件失败，退出"
    exit 1
  fi

  # 提交更改
  if ! commit_changes "$commit_message"; then
    log_warning "没有文件被提交，退出"
    exit 0
  fi

  # 配置远程仓库URL（如果提供了token和repository）
  if [[ -n "${GITHUB_TOKEN:-}" ]] && [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
    if ! configure_remote_url "$GITHUB_TOKEN" "$GITHUB_REPOSITORY"; then
      log_error "配置远程仓库URL失败，退出"
      exit 1
    fi
  else
    log_warning "未提供GITHUB_TOKEN或GITHUB_REPOSITORY，跳过远程URL配置"
  fi

  # 推送到远程仓库
  if ! push_to_remote "$branch" "$force_push"; then
    log_error "推送失败，退出"
    exit 1
  fi

  # 显示推送结果
  show_push_result

  log_success "Git提交和推送流程完成"
}

# 帮助函数
show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Description: 配置Git用户信息，提交文件并推送到远程仓库

Environment Variables:
  GIT_USER_EMAIL      Git用户邮箱 (默认: $DEFAULT_USER_EMAIL)
  GIT_USER_NAME       Git用户名 (默认: $DEFAULT_USER_NAME)
  COMMIT_MESSAGE      提交信息 (默认: $DEFAULT_COMMIT_MESSAGE)
  TARGET_BRANCH       目标分支 (默认: $DEFAULT_BRANCH)
  FORCE_PUSH          是否强制推送 (默认: false)
  FILES_TO_ADD        要添加的文件 (默认: .)
  GITHUB_TOKEN        GitHub Token
  GITHUB_REPOSITORY   GitHub仓库名称

Options:
  -h, --help          Show this help message
  -v, --version       Show version information
  --dry-run           只显示将要执行的操作，不实际执行

Examples:
  $SCRIPT_NAME
  GITHUB_TOKEN=xxx GITHUB_REPOSITORY=user/repo $SCRIPT_NAME
  COMMIT_MESSAGE="Custom message" $SCRIPT_NAME
  FORCE_PUSH=true $SCRIPT_NAME

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
  --dry-run)
    log_info "DRY RUN模式 - 只显示将要执行的操作"
    echo "将要配置的用户信息:"
    echo "  Email: ${GIT_USER_EMAIL:-$DEFAULT_USER_EMAIL}"
    echo "  Name: ${GIT_USER_NAME:-$DEFAULT_USER_NAME}"
    echo "将要提交的信息: ${COMMIT_MESSAGE:-$DEFAULT_COMMIT_MESSAGE}"
    echo "目标分支: ${TARGET_BRANCH:-$DEFAULT_BRANCH}"
    echo "强制推送: ${FORCE_PUSH:-false}"
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
