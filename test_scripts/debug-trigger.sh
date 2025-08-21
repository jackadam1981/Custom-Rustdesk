#!/bin/bash
# 调试 trigger.sh 脚本，找出 TRIGGER_DATA 为空的原因

echo "🔍 调试 trigger.sh 脚本"
echo "================================"

# 设置测试环境
export GITHUB_RUN_ID="debug-$(date +%s)"
export GITHUB_OUTPUT="/tmp/github_output_debug"
export DEBUG_ENABLED="true"

# 创建模拟的 workflow_dispatch 事件数据
cat > /tmp/debug_event.json << 'EOF'
{
  "inputs": {
    "tag": "debug-test",
    "customer": "debug-customer",
    "email": "debug@example.com",
    "super_password": "debugpass123",
    "rendezvous_server": "192.168.1.100",
    "api_server": "http://192.168.1.100:21114"
  }
}
EOF

echo "📋 测试数据:"
echo "EVENT_DATA: $(cat /tmp/debug_event.json)"
echo ""

# 加载 trigger.sh
source .github/workflows/scripts/trigger.sh

echo "🔍 逐步测试各个函数..."
echo ""

echo "1. 测试参数提取..."
params=$(trigger_manager "extract-workflow-dispatch" "$(cat /tmp/debug_event.json)")
echo "   提取的参数: $params"
echo ""

echo "2. 执行参数提取..."
eval "$params"
echo "   环境变量设置后:"
echo "   TAG=$TAG"
echo "   EMAIL=$EMAIL"
echo "   CUSTOMER=$CUSTOMER"
echo "   SUPER_PASSWORD=$SUPER_PASSWORD"
echo "   RENDEZVOUS_SERVER=$RENDEZVOUS_SERVER"
echo "   API_SERVER=$API_SERVER"
echo ""

echo "3. 测试时间戳处理..."
final_tag=$(trigger_manager "process-tag" "$(cat /tmp/debug_event.json)")
echo "   最终标签: $final_tag"
echo ""

echo "4. 测试数据生成..."
final_data=$(trigger_manager "generate-data" "$(cat /tmp/debug_event.json)" "$final_tag")
echo "   生成的最终数据: $final_data"
echo ""

echo "5. 测试参数验证..."
validation_result=$(trigger_manager "validate-parameters" "$final_data")
validation_exit_code=$?
echo "   验证结果: $validation_result (退出码: $validation_exit_code)"
echo ""

echo "6. 测试 GitHub 输出..."
echo "   调用前 final_data: $final_data"
trigger_manager "output-to-github" "$final_data"
echo "   GitHub 输出内容:"
cat $GITHUB_OUTPUT
echo ""

echo "🧹 清理测试文件..."
rm -f /tmp/debug_event.json /tmp/github_output_debug

echo "✅ 调试完成！"
echo ""
echo "📝 检查要点："
echo "   - 参数是否正确提取"
echo "   - 数据是否正确生成"
echo "   - GitHub 输出是否包含 trigger_data"
echo "   - 是否有任何函数返回空值"
