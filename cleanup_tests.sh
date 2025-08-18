#!/bin/bash
# 清理测试脚本中的重复函数

echo "开始清理测试脚本中的重复函数..."

# 需要处理的测试脚本列表
test_scripts=(
    "test-queue-cleanup.sh"
    "test-queue-reset.sh" 
    "test-queue-status.sh"
    "test-queue-build-lock.sh"
    "test-queue-concurrent.sh"
    "test-queue-build-lock-simple.sh"
)

for script in "${test_scripts[@]}"; do
    script_path="test_scripts/$script"
    
    if [ -f "$script_path" ]; then
        echo "处理 $script..."
        
        # 创建临时文件
        temp_file=$(mktemp)
        
        # 处理文件：移除重复的函数定义
        awk '
        BEGIN { in_run_test = 0; in_cleanup = 0; in_show_results = 0; skip_lines = 0 }
        
        # 检测run_test函数开始
        /^# 测试函数$/ { skip_lines = 1; next }
        /^run_test\(\) \{$/ { in_run_test = 1; next }
        
        # 检测cleanup_test_env函数
        /^# 清理测试环境$/ { skip_lines = 1; next }
        /^cleanup_test_env\(\) \{$/ { in_cleanup = 1; next }
        
        # 检测show_test_results函数
        /^# 显示测试结果$/ { skip_lines = 1; next }
        /^show_test_results\(\) \{$/ { in_show_results = 1; next }
        
        # 跳过函数内容
        in_run_test == 1 && /^\}$/ { in_run_test = 0; next }
        in_cleanup == 1 && /^\}$/ { in_cleanup = 0; next }
        in_show_results == 1 && /^\}$/ { in_show_results = 0; next }
        
        # 跳过函数体
        in_run_test == 1 { next }
        in_cleanup == 1 { next }
        in_show_results == 1 { next }
        
        # 跳过注释行
        skip_lines == 1 { skip_lines = 0; next }
        
        # 输出其他行
        { print }
        ' "$script_path" > "$temp_file"
        
        # 替换原文件
        mv "$temp_file" "$script_path"
        
        # 更新主函数调用
        sed -i 's/setup_test_env/init_test_framework/' "$script_path"
        sed -i 's/cleanup_test_env/cleanup_test_framework/' "$script_path"
        sed -i '/show_test_results/d' "$script_path"
        sed -i '/if \[ $FAILED_TESTS -eq 0 \]; then/,/fi$/d' "$script_path"
        
        echo "✅ $script 清理完成"
    else
        echo "❌ 文件不存在: $script_path"
    fi
done

echo "测试脚本清理完成！"
