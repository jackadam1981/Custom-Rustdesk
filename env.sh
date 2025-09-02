#!/bin/bash

# 环境变量配置文件
# 此文件从 .env 文件读取敏感信息，.env 文件已被 .gitignore 忽略

# GitHub仓库
export GITHUB_REPOSITORY="jackadam1981/Custom-Rustdesk"

# 测试构建暂停时间（秒）
export TEST_BUILD_PAUSE=60

# 启用调试模式
export DEBUG_ENABLED=true

# 加载 .env 文件（必须存在）
if [ -f ".env" ]; then
    source .env
    echo ".env 文件已加载"
else
    echo "错误: .env 文件不存在，请创建该文件并设置必要的环境变量"
    echo "示例 .env 文件内容："
    echo "GITHUB_TOKEN=\"your_github_token_here\""
    exit 1
fi

# 验证必要的环境变量
if [ -z "$GITHUB_TOKEN" ]; then
    echo "错误: GITHUB_TOKEN 未在 .env 文件中设置"
    exit 1
fi

# 加载本地环境变量文件（如果存在）
if [ -f ".env.local" ]; then
    source .env.local
    echo "本地环境变量已加载"
fi

# 加载自定义的本地环境变量文件（如果存在）
if [ -f "my_env.sh" ]; then
    source my_env.sh
    echo "自定义环境变量已加载"
fi

echo "环境变量已加载完成"
echo "仓库: $GITHUB_REPOSITORY"
echo "测试构建暂停时间: ${TEST_BUILD_PAUSE}秒"
echo "调试模式: ${DEBUG_ENABLED}"
