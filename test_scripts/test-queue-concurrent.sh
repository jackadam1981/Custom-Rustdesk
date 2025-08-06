#!/bin/bash
# 构建锁并发轮询测试脚本

set -e
source test_scripts/test-utils.sh

echo "========================================"
echo "    Queue Build Lock Concurrent Tests"
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
echo "Step 1: Test Concurrent Build Lock Polling"
echo "========================================"

# 显示当前Issue #1完整内容
log_info "=== Current Issue #1 Full Content (Before Concurrent Test) ==="
get_issue_json_data

# 测试1: 测试构建锁并发轮询机制
log_info "Testing build lock concurrent polling mechanism..."

# 加入三个项目到队列（模拟真实并发场景）
log_info "Adding three items to queue for concurrent polling test..."
export GITHUB_RUN_ID="concurrent_test_1_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"concurrent-test-1","email":"concurrent1@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'

export GITHUB_RUN_ID="concurrent_test_2_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"concurrent-test-2","email":"concurrent2@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'

export GITHUB_RUN_ID="concurrent_test_3_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"concurrent-test-3","email":"concurrent3@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'

# 显示加入三个项目后的状态
log_info "=== Issue #1 Full Content After Adding Three Items ==="
get_issue_json_data

# 第一个项目获取锁
log_info "First item acquiring build lock..."
export GITHUB_RUN_ID="concurrent_test_1_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire'

# 显示第一个项目获取锁后的状态
log_info "=== Issue #1 Full Content After First Item Acquired Lock ==="
get_issue_json_data

# 第二个和第三个项目同时开始轮询获取锁
log_info "Starting concurrent polling: second and third items will poll every 30 seconds..."
log_info "Second item starting to poll for build lock..."
export GITHUB_RUN_ID="concurrent_test_2_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire' &
POLLING_PID_2=$!

log_info "Third item starting to poll for build lock..."
export GITHUB_RUN_ID="concurrent_test_3_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'acquire' &
POLLING_PID_3=$!

# 等待一段时间让轮询开始
log_info "Waiting 15 seconds to let polling start (first polling cycle)..."
sleep 15

# 显示轮询开始后的状态
log_info "=== Issue #1 Full Content After First Polling Cycle ==="
get_issue_json_data

# 第一个项目完成构建，释放锁（应该自动从队列中移除）
log_info "First item completing build and releasing lock (should auto-leave queue)..."
export GITHUB_RUN_ID="concurrent_test_1_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'

# 显示第一个项目释放锁后的状态
log_info "=== Issue #1 Full Content After First Item Released Lock ==="
get_issue_json_data

# 等待第二个项目获取锁
log_info "Waiting for second item to acquire lock after first item completed..."
wait $POLLING_PID_2

# 显示第二个项目获取锁后的状态
log_info "=== Issue #1 Full Content After Second Item Acquired Lock ==="
get_issue_json_data

# 第二个项目完成构建，释放锁
log_info "Second item completing build and releasing lock..."
export GITHUB_RUN_ID="concurrent_test_2_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'

# 显示第二个项目释放锁后的状态
log_info "=== Issue #1 Full Content After Second Item Released Lock ==="
get_issue_json_data

# 等待第三个项目获取锁
log_info "Waiting for third item to acquire lock after second item completed..."
wait $POLLING_PID_3

# 显示第三个项目获取锁后的状态
log_info "=== Issue #1 Full Content After Third Item Acquired Lock ==="
get_issue_json_data

# 第三个项目完成构建，释放锁
log_info "Third item completing build and releasing lock..."
export GITHUB_RUN_ID="concurrent_test_3_$(date +%s)"
source .github/workflows/scripts/queue-manager.sh && queue_manager 'build_lock' 'release'

# 显示最终状态
log_info "=== Issue #1 Full Content After All Items Completed ==="
get_issue_json_data

echo ""
echo "========================================"
echo "Concurrent Tests Completed Successfully! 🎉"
echo "========================================" 