#!/bin/bash
# 队列功能综合测试脚本

set -e
source test_scripts/test-utils.sh

echo "========================================"
echo "    Queue Function Sequence Tests"
echo "========================================"

# 设置测试环境
setup_test_env

# 重置队列状态
log_info "Resetting queue state..."
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'

# 显示初始状态
log_info "=== Initial Queue Status ==="
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status'

echo ""
echo "========================================"
echo "Step 1: Join first item"
echo "========================================"

# 显示当前Issue #1完整内容
log_info "=== Current Issue #1 Full Content (Before Join) ==="
gh issue view 1

# 测试1: 加入第一个项目
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"sequence-test-1","email":"test1@example.com","customer":"test-customer-1","trigger_type":"workflow_dispatch"}'

# 显示验证后的Issue #1完整内容
log_info "=== Issue #1 Full Content After Join ==="
gh issue view 1

echo ""
echo "========================================"
echo "Step 2: Join second item"
echo "========================================"

# 显示当前Issue #1完整内容
log_info "=== Current Issue #1 Full Content (Before Second Join) ==="
gh issue view 1

# 测试2: 加入第二个项目
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"sequence-test-2","email":"test2@example.com","customer":"test-customer-2","trigger_type":"workflow_dispatch"}'

# 显示验证后的Issue #1完整内容
log_info "=== Issue #1 Full Content After Second Join ==="
gh issue view 1

echo ""
echo "========================================"
echo "Step 3: Status query"
echo "========================================"

# 显示当前Issue #1完整内容
log_info "=== Current Issue #1 Full Content (Before Status Query) ==="
gh issue view 1

# 测试3: 状态查询
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'status'

# 显示验证后的Issue #1完整内容
log_info "=== Issue #1 Full Content After Status Query ==="
gh issue view 1

echo ""
echo "========================================"
echo "Step 4: Leave queue"
echo "========================================"

# 显示当前Issue #1完整内容
log_info "=== Current Issue #1 Full Content (Before Leave) ==="
gh issue view 1

# 测试4: 离开队列
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'leave'

# 显示验证后的Issue #1完整内容
log_info "=== Issue #1 Full Content After Leave ==="
gh issue view 1

echo ""
echo "========================================"
echo "Step 5: Queue cleanup"
echo "========================================"

# 显示当前Issue #1状态
log_info "=== Current Issue #1 Status (Before Adding Test Data) ==="
show_issue_status "Before Adding Test Data for Cleanup"

# 先加入一些测试数据用于清理测试
log_info "Adding test data for cleanup testing..."
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"cleanup-test-1","email":"cleanup1@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"cleanup-test-2","email":"cleanup2@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' '{"tag":"cleanup-test-3","email":"cleanup3@example.com","customer":"test-customer","trigger_type":"workflow_dispatch"}'

# 模拟真实的cleanup测试场景：添加已完成和错误的工作流到队列
log_info "Simulating real cleanup scenario: adding completed and failed workflows to queue..."

# 获取已完成的GitHub Actions runs
log_info "Getting completed GitHub Actions runs..."
completed_runs=$(gh run list --limit 5 --json databaseId,status,conclusion,createdAt,updatedAt | jq -r '.[] | select(.status == "completed") | .databaseId')

# 获取失败的工作流runs
log_info "Getting failed GitHub Actions runs..."
failed_runs=$(gh run list --limit 5 --json databaseId,status,conclusion,createdAt,updatedAt | jq -r '.[] | select(.status == "completed" and .conclusion == "failure") | .databaseId')

# 添加已完成的工作流到队列（这些应该被cleanup清理）
if [ -n "$completed_runs" ]; then
    log_info "Adding completed workflows to queue for cleanup testing..."
    count=0
    for run_id in $completed_runs; do
        if [ $count -lt 2 ]; then  # 添加2个已完成的工作流
            log_info "Adding completed workflow $run_id to queue..."
            # 直接使用真实的run_id，这样cleanup可以检查到它的状态
            export GITHUB_RUN_ID="$run_id"
            source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' "{\"tag\":\"completed-workflow-$run_id\",\"email\":\"test@example.com\",\"customer\":\"test-customer\",\"trigger_type\":\"workflow_dispatch\"}"
            count=$((count + 1))
        fi
    done
fi

# 添加失败的工作流到队列（这些也应该被cleanup清理）
if [ -n "$failed_runs" ]; then
    log_info "Adding failed workflows to queue for cleanup testing..."
    count=0
    for run_id in $failed_runs; do
        if [ $count -lt 2 ]; then  # 添加2个失败的工作流
            log_info "Adding failed workflow $run_id to queue..."
            # 直接使用真实的run_id，这样cleanup可以检查到它的状态
            export GITHUB_RUN_ID="$run_id"
            source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'join' "{\"tag\":\"failed-workflow-$run_id\",\"email\":\"test@example.com\",\"customer\":\"test-customer\",\"trigger_type\":\"workflow_dispatch\"}"
            count=$((count + 1))
        fi
    done
fi

# 添加一些需要清理的旧任务（通过直接修改Issue #1的JSON数据）
log_info "Adding old tasks that should be cleaned up..."
json_data=$(get_issue_json_data)
if [ $? -eq 0 ]; then
    # 创建一些旧任务（7小时前，超过cleanup的6小时阈值）
    old_time1=$(date -d "7 hours ago" '+%Y-%m-%d %H:%M:%S')
    old_time2=$(date -d "8 hours ago" '+%Y-%m-%d %H:%M:%S')
    old_time3=$(date -d "9 hours ago" '+%Y-%m-%d %H:%M:%S')
    
    # 添加旧任务到队列
    modified_json=$(echo "$json_data" | jq --arg old_time1 "$old_time1" --arg old_time2 "$old_time2" --arg old_time3 "$old_time3" '
        .queue += [
            {
                "run_id": "old_task_1",
                "tag": "old-task-1",
                "email": "old1@example.com",
                "customer": "test-customer",
                "trigger_type": "workflow_dispatch",
                "join_time": $old_time1
            },
            {
                "run_id": "old_task_2", 
                "tag": "old-task-2",
                "email": "old2@example.com",
                "customer": "test-customer",
                "trigger_type": "workflow_dispatch",
                "join_time": $old_time2
            },
            {
                "run_id": "old_task_3",
                "tag": "old-task-3", 
                "email": "old3@example.com",
                "customer": "test-customer",
                "trigger_type": "workflow_dispatch",
                "join_time": $old_time3
            }
        ] |
        .version = (.version // 0) + 1
    ')
    
    # 更新Issue #1
    current_time=$(date '+%Y-%m-%d %H:%M:%S')
    body="## 构建队列管理

**最后更新时间：** $current_time

### 双锁状态
- **Issue 锁状态：** 空闲 🔓
- **构建锁状态：** 空闲 🔓

### 锁持有者
- **Issue 锁持有者：** 无
- **构建锁持有者：** 无

### 当前构建标识
- **Run ID：** 未获取
- **Issue ID：** 未获取

### 构建队列
- **当前数量：** $(echo "$modified_json" | jq '.queue | length')/5
- **Issue触发：** 0/3
- **手动触发：** $(echo "$modified_json" | jq '.queue | length')/5

---

### 队列数据（隐私安全版本）
\`\`\`json
$modified_json
\`\`\`"

    # 使用gh命令更新Issue #1
    echo "$body" | gh issue edit 1 --body-file -
    log_info "Successfully added 3 old tasks (7, 8, 9 hours ago) for cleanup testing"
else
    log_warning "Failed to get current JSON data for modification"
fi

# 显示添加测试数据后的Issue #1完整内容
log_info "=== Issue #1 Full Content After Adding Test Data ==="
gh issue view 1

# 测试5: 队列清理
log_info "=== Current Issue #1 Full Content (Before Cleanup) ==="
gh issue view 1

source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'cleanup'

# 显示验证后的Issue #1完整内容
log_info "=== Issue #1 Full Content After Cleanup ==="
gh issue view 1

echo ""
echo "========================================"
echo "Step 6: Queue reset"
echo "========================================"

# 显示当前Issue #1完整内容
log_info "=== Current Issue #1 Full Content (Before Reset) ==="
gh issue view 1

# 测试6: 队列重置
source .github/workflows/scripts/queue-manager.sh && queue_manager 'queue_lock' 'reset'

# 显示验证后的Issue #1完整内容
log_info "=== Issue #1 Full Content After Reset ==="
gh issue view 1

echo ""
echo "========================================"
echo "Test Sequence Completed Successfully! 🎉"
echo "========================================" 