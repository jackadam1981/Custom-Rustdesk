#!/bin/bash
# 本地测试环境变量配置文件

# GitHub API Configuration (仅用于本地测试)
export GITHUB_REPOSITORY="jackadam1981/Custom-Rustdesk"

# 自动获取GitHub Token（如果gh CLI可用）
if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
    export GITHUB_TOKEN=$(gh auth token 2>/dev/null || echo "")
fi

# 显示环境变量状态
echo "Local test environment variables loaded:"
echo "  GITHUB_REPOSITORY: $GITHUB_REPOSITORY"
echo "  GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}..." 