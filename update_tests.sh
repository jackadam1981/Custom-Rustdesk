#!/bin/bash
# 批量更新测试脚本以使用统一的测试框架

# 测试脚本列表
test_scripts=(
    "test-queue-leave.sh"
    "test-queue-cleanup.sh"
    "test-queue-reset.sh"
    "test-queue-status.sh"
    "test-queue-build-lock.sh"
    "test-queue-concurrent.sh"
    "test-queue-build-lock-simple.sh"
    "test-queue-sequence.sh"
)

echo "开始批量更新测试脚本..."

for script in "${test_scripts[@]}"; do
    script_path="test_scripts/$script"
    
    if [ -f "$script_path" ]; then
        echo "更新 $script..."
        
        # 替换 source 语句
        sed -i 's/source test_scripts\/test-utils\.sh/source test_scripts\/test-framework.sh/' "$script_path"
        
        # 移除重复的测试计数器变量定义
        sed -i '/^# 测试计数器$/,/^TEST_RESULTS=()$/d' "$script_path"
        
        # 移除重复的run_test函数（如果存在）
        # 这个比较复杂，我们稍后单独处理每个文件
        
        echo "✅ $script 基本更新完成"
    else
        echo "❌ 文件不存在: $script_path"
    fi
done

echo "批量更新完成！"
