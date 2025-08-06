#!/bin/bash
# 简化的构建锁测试脚本

set -e
source test_scripts/test-utils.sh

echo "========================================"
echo "    Simple Queue Build Lock Tests"
echo "========================================"

# 设置测试环境
setup_test_env

# 重置队列状态
log_info "Resetting queue state..."
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'

# 显示初始状态
log_info "=== Initial Queue Status ==="
get_issue_json_data

echo ""
echo "========================================"
echo "Step 1: Test Basic Build Lock Acquisition"
echo "========================================"

# 加入一个项目到队列
log_info "Adding item to queue..."
export GITHUB_RUN_ID="simple_test_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"simple-test","email":"simple@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'

# 显示加入后的状态
log_info "=== Issue #1 Full Content After Adding Item ==="
get_issue_json_data

# 获取构建锁
log_info "Acquiring build lock..."
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'

# 显示获取锁后的状态
log_info "=== Issue #1 Full Content After Acquiring Lock ==="
get_issue_json_data

# 释放构建锁
log_info "Releasing build lock..."
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'

# 显示释放锁后的状态
log_info "=== Issue #1 Full Content After Releasing Lock ==="
get_issue_json_data

echo ""
echo "========================================"
echo "Simple Build Lock Tests Completed Successfully! 🎉"
echo "========================================" 