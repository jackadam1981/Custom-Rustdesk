#!/bin/bash
# Script Name: create_workflow.sh
# Description: 创建新的GitHub工作流文件，包含随机人名
# Author: GitHub Actions Bot
# Date: 2024-01-01
# Version: 1.0.0

set -euo pipefail # Exit on error, undefined vars, pipe failures

# Constants
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_DIR=".github/workflows"
WORKFLOW_FILE="hello.yml"

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

# 检查并删除已存在的工作流文件
cleanup_existing_workflow() {
  log_info "检查是否存在现有的工作流文件..."

  if [ -f "${WORKFLOW_DIR}/${WORKFLOW_FILE}" ]; then
    log_warning "${WORKFLOW_FILE}已存在，正在删除..."
    rm "${WORKFLOW_DIR}/${WORKFLOW_FILE}"
    log_success "已删除现有的${WORKFLOW_FILE}文件"
  else
    log_info "没有找到现有的${WORKFLOW_FILE}文件"
  fi
}

# 生成随机人名
generate_random_name() {
  log_info "生成随机人名..."

  # 定义中文人名数组
  local names=("张三" "李四" "王五" "赵六" "刘七" "孙八" "周九" "吴十" "郑十一" "钱十二")

  # 生成随机索引
  local random_index=$((RANDOM % ${#names[@]}))
  local random_name="${names[$random_index]}"

  log_success "生成的人名: ${random_name}"
  echo "$random_name"
}

# 创建工作流文件
create_workflow_file() {
  local random_name="$1"

  log_info "创建目录结构..."
  mkdir -p "${WORKFLOW_DIR}"

  log_info "生成工作流文件内容..."

  # 创建工作流文件内容
  cat >"${WORKFLOW_DIR}/${WORKFLOW_FILE}" <<EOF
name: Hello World
on:
  workflow_dispatch:
jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - name: Say Hello
        run: echo "Hello ${random_name}!"
EOF

  log_success "已创建工作流文件: ${WORKFLOW_DIR}/${WORKFLOW_FILE}"
}

# 显示创建的文件内容
display_workflow_content() {
  log_info "显示创建的工作流文件内容："
  echo "----------------------------------------"
  cat "${WORKFLOW_DIR}/${WORKFLOW_FILE}"
  echo "----------------------------------------"
}

# 主函数
main() {
  log_info "开始创建工作流文件..."

  # 检查并清理现有文件
  cleanup_existing_workflow

  # 生成随机人名
  local random_name
  random_name=$(generate_random_name)

  # 创建工作流文件
  create_workflow_file "$random_name"

  # 显示文件内容
  display_workflow_content

  log_success "工作流文件创建完成"
}

# 帮助函数
show_help() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Description: 创建新的GitHub工作流文件，包含随机人名

Options:
    -h, --help      Show this help message
    -v, --version   Show version information

Examples:
    $SCRIPT_NAME
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
