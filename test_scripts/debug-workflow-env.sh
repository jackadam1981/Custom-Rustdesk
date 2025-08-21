#!/bin/bash
# 模拟 GitHub Actions 工作流环境，测试 github.event 处理

echo "🔍 模拟 GitHub Actions 工作流环境"
echo "=================================="

# 模拟 github.event 数据（手动触发）
export GITHUB_EVENT_NAME="workflow_dispatch"
export GITHUB_EVENT='{"inputs":{"tag":"test-tag","customer":"test-customer","email":"test@example.com","super_password":"testpass","rendezvous_server":"192.168.1.100","api_server":"http://192.168.1.100:21114"}}'

echo "📋 模拟的环境变量:"
echo "GITHUB_EVENT_NAME: $GITHUB_EVENT_NAME"
echo "GITHUB_EVENT: $GITHUB_EVENT"
echo ""

# 测试不同的数据传递方式
echo "🔍 测试不同的数据传递方式..."
echo ""

echo "1. 测试直接使用 github.event.inputs:"
echo "   tag: $(echo "$GITHUB_EVENT" | jq -r '.inputs.tag // empty')"
echo "   customer: $(echo "$GITHUB_EVENT" | jq -r '.inputs.customer // empty')"
echo "   email: $(echo "$GITHUB_EVENT" | jq -r '.inputs.email // empty')"
echo ""

echo "2. 测试构建 JSON 字符串:"
export EVENT_DATA_1='{"inputs":{"tag":"test-tag","customer":"test-customer","email":"test@example.com","super_password":"testpass","rendezvous_server":"192.168.1.100","api_server":"http://192.168.1.100:21114"}}'
echo "   EVENT_DATA_1: $EVENT_DATA_1"
echo ""

echo "3. 测试使用 jq 处理:"
export EVENT_DATA_2=$(echo "$GITHUB_EVENT" | jq -c .)
echo "   EVENT_DATA_2: $EVENT_DATA_2"
echo ""

echo "4. 测试加载 trigger.sh 并处理:"
source .github/workflows/scripts/trigger.sh

echo "   测试参数提取..."
params=$(trigger_manager "extract-workflow-dispatch" "$EVENT_DATA_2")
echo "   提取的参数: $params"
echo ""

echo "   执行参数提取..."
eval "$params"
echo "   环境变量设置后:"
echo "   TAG=$TAG"
echo "   EMAIL=$EMAIL"
echo "   CUSTOMER=$CUSTOMER"
echo ""

echo "   测试时间戳处理..."
final_tag=$(trigger_manager "process-tag" "$EVENT_DATA_2")
echo "   最终标签: $final_tag"
echo ""

echo "   测试数据生成..."
final_data=$(trigger_manager "generate-data" "$EVENT_DATA_2" "$final_tag")
echo "   生成的最终数据: $final_data"
echo ""

echo "   测试 GitHub 输出..."
export GITHUB_OUTPUT="/tmp/github_output_test"
trigger_manager "output-to-github" "$final_data"
echo "   GitHub 输出内容:"
cat $GITHUB_OUTPUT
echo ""

echo "🧹 清理测试文件..."
rm -f /tmp/github_output_test

echo "✅ 测试完成！"
echo ""
echo "📝 关键发现："
echo "   - 直接使用 github.event.inputs 是否有效"
echo "   - jq 处理后的数据格式是否正确"
echo "   - trigger.sh 是否能正确处理数据"
