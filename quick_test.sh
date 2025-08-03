#!/bin/bash

# 快速测试脚本 - 验证工作流基本功能

echo "=== Custom Rustdesk 工作流快速测试 ==="

# 检查依赖
echo "1. 检查依赖..."
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI 未安装"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq 未安装"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "❌ GitHub CLI 未登录"
    exit 1
fi

echo "✅ 依赖检查通过"

# 获取仓库信息
echo "2. 获取仓库信息..."
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "✅ 当前仓库: $REPO"

# 获取工作流信息
echo "3. 获取工作流信息..."
WORKFLOW_ID=$(gh workflow list --json id,path | jq -r '.[] | select(.path == ".github/workflows/CustomBuildRustdesk.yml") | .id')

if [ -z "$WORKFLOW_ID" ]; then
    echo "❌ 未找到目标工作流"
    exit 1
fi

echo "✅ 工作流ID: $WORKFLOW_ID"

# 生成测试数据
echo "4. 生成测试数据..."
TIMESTAMP=$(date +%s)
TAG="quick-test-${TIMESTAMP}"
CUSTOMER="快速测试客户"
EMAIL="quick-test-${TIMESTAMP}@example.com"

echo "✅ 测试数据:"
echo "  Tag: $TAG"
echo "  Customer: $CUSTOMER"
echo "  Email: $EMAIL"

# 测试工作流触发
echo "5. 测试工作流触发..."
if gh workflow run "$WORKFLOW_ID" \
    --field tag="$TAG" \
    --field customer="$CUSTOMER" \
    --field email="$EMAIL" \
    --field super_password="testpass123" \
    --field rendezvous_server="192.168.1.100" \
    --field api_server="http://192.168.1.100:21114" \
    --field slogan="快速测试标语" \
    --field customer_link="https://example.com" \
    --field rs_pub_key="" \
    --field enable_debug="true"; then
    
    echo "✅ 工作流触发成功"
    
    # 获取最新运行
    echo "6. 获取运行信息..."
    LATEST_RUN=$(gh run list --limit 1 --json databaseId,workflowName,status,createdAt,url | jq -r '.[0]')
    
    if [ -n "$LATEST_RUN" ]; then
        RUN_ID=$(echo "$LATEST_RUN" | jq -r '.databaseId')
        STATUS=$(echo "$LATEST_RUN" | jq -r '.status')
        RUN_URL=$(echo "$LATEST_RUN" | jq -r '.url')
        
        echo "✅ 运行信息:"
        echo "  运行ID: $RUN_ID"
        echo "  状态: $STATUS"
        echo "  运行URL: $RUN_URL"
        
        # 简单监控
        echo "7. 监控运行状态..."
        for i in {1..6}; do
            echo "  检查第 $i 次..."
            RUN_STATUS=$(gh run view "$RUN_ID" --json status,conclusion 2>/dev/null || echo "")
            
            if [ -n "$RUN_STATUS" ]; then
                CURRENT_STATUS=$(echo "$RUN_STATUS" | jq -r '.status')
                CONCLUSION=$(echo "$RUN_STATUS" | jq -r '.conclusion // "null"')
                
                echo "    状态: $CURRENT_STATUS, 结论: $CONCLUSION"
                
                if [ "$CURRENT_STATUS" = "completed" ]; then
                    if [ "$CONCLUSION" = "success" ]; then
                        echo "✅ 工作流运行成功完成！"
                        break
                    elif [ "$CONCLUSION" = "failure" ]; then
                        echo "❌ 工作流运行失败！"
                        break
                    fi
                fi
            fi
            
            if [ $i -lt 6 ]; then
                echo "  等待 30 秒..."
                sleep 30
            fi
        done
        
        echo "8. 测试完成！"
        echo "📊 测试总结:"
        echo "  - 仓库: $REPO"
        echo "  - 工作流ID: $WORKFLOW_ID"
        echo "  - 运行ID: $RUN_ID"
        echo "  - 测试标签: $TAG"
        echo "  - 测试客户: $CUSTOMER"
        echo "  - 测试邮箱: $EMAIL"
        echo ""
        echo "🔗 查看运行详情: $RUN_URL"
        
    else
        echo "❌ 无法获取运行信息"
    fi
else
    echo "❌ 工作流触发失败"
    exit 1
fi

echo ""
echo "=== 快速测试完成 ===" 