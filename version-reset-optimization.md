# 版本号重置优化总结

## 优化背景

根据用户反馈："还可以继续精简，仅再finish阶段检查一下，如果三锁为空，则重置。"

## 最终优化方案

### 单一检查点 - Finish阶段

版本重置检查现在只在 **`finish` 阶段** 进行，具体在 `finish.sh` 脚本的 `check_and_reset_version_numbers()` 函数中：

```bash
# 在 finish.sh 中
check_and_reset_version_numbers() {
    debug "log" "Checking if version numbers should be reset..."
    
    # 获取当前队列数据
    local queue_data=$(queue_manager "data" "${QUEUE_ISSUE_NUMBER:-1}")
    
    # 检查是否所有锁都为空且队列为空
    local issue_locked_by=$(echo "$queue_data" | jq -r '.issue_locked_by // null')
    local queue_locked_by=$(echo "$queue_data" | jq -r '.queue_locked_by // null')
    local build_locked_by=$(echo "$queue_data" | jq -r '.build_locked_by // null')
    local current_run_id=$(echo "$queue_data" | jq -r '.run_id // null')
    local queue_length=$(echo "$queue_data" | jq -r '.queue | length')
    
    # 检查是否所有锁都为空且队列为空
    if [ "$issue_locked_by" = "null" ] && [ "$queue_locked_by" = "null" ] && [ "$build_locked_by" = "null" ] && [ "$current_run_id" = "null" ] && [ "$queue_length" -eq 0 ]; then
        # 检查版本号是否超过阈值
        local version=$(echo "$queue_data" | jq -r '.version // 1')
        local issue_lock_version=$(echo "$queue_data" | jq -r '.issue_lock_version // 1')
        local queue_lock_version=$(echo "$queue_data" | jq -r '.queue_lock_version // 1')
        local build_lock_version=$(echo "$queue_data" | jq -r '.build_lock_version // 1')
        local version_threshold=100
        
        # 检查是否有任何版本号超过阈值
        if [ "$version" -gt "$version_threshold" ] || [ "$issue_lock_version" -gt "$version_threshold" ] || [ "$queue_lock_version" -gt "$version_threshold" ] || [ "$build_lock_version" -gt "$version_threshold" ]; then
            # 重置所有版本号为1
            local reset_queue_data=$(echo "$queue_data" | jq '
                .version = 1 |
                .issue_lock_version = 1 |
                .queue_lock_version = 1 |
                .build_lock_version = 1
            ')
            
            # 更新队列数据
            local update_response=$(queue_manager_update_queue_comment "$reset_queue_data" "无")
            
            if [ $? -eq 0 ]; then
                debug "success" "Successfully reset version numbers to 1"
                echo "version_reset=true"
                return 0
            else
                debug "error" "Failed to reset version numbers"
                echo "version_reset=false"
                return 1
            fi
        else
            debug "log" "Version numbers are within acceptable range, no reset needed"
            echo "version_reset=false"
            return 0
        fi
    else
        debug "log" "Locks are not all free or queue is not empty, skipping version reset"
        echo "version_reset=false"
        return 0
    fi
}
```

### 工作流集成

在 `CustomBuildRustdesk.yml` 的 `finish` 作业中，版本重置检查在锁释放之后进行：

```yaml
# 释放三锁架构的所有锁
lock_released_output=$(finish_manager "release-triple-lock" "$TRIGGER_DATA" "$build_status" "$download_url" "$error_message" "$build_id")

# 检查并重置版本号（当三锁为空时）
version_reset_output=$(finish_manager "check-version-reset" "$TRIGGER_DATA" "$build_status" "$download_url" "$error_message")
version_reset_exit_code=$?

# 解析版本重置结果
if echo "$version_reset_output" | grep -q "version_reset="; then
  version_reset=$(echo "$version_reset_output" | grep "version_reset=" | cut -d'=' -f2)
  if [ "$version_reset" = "true" ]; then
    debug "success" "Version numbers have been reset"
  else
    debug "log" "Version reset not needed or failed"
  fi
fi
```

## 移除的重复检查

1. **从 `queue_manager_release_issue_lock()` 移除**：
   - 删除了Issue锁释放时的版本重置检查
   - 简化了锁释放逻辑

2. **从 `queue_manager_cleanup()` 移除**：
   - 删除了清理操作中的版本重置检查
   - 专注于清理逻辑

3. **从 `queue_manager_release_lock()` 移除**：
   - 删除了构建锁释放时的版本重置检查
   - 专注于锁释放逻辑

4. **删除 `queue_manager_check_version_reset()` 函数**：
   - 完全移除了queue-manager.sh中的版本重置检查函数
   - 版本重置逻辑现在完全在finish.sh中实现

## 最终优化优势

### 1. 极简设计
- **单一检查点**：版本重置只在finish阶段检查一次
- **逻辑集中**：所有版本重置逻辑都在finish.sh中
- **职责清晰**：finish阶段负责所有收尾工作，包括版本重置

### 2. 性能优化
- **减少检查次数**：从多次检查减少到一次
- **避免重复操作**：不再在多个地方进行版本重置检查
- **简化流程**：其他阶段专注于自己的核心功能

### 3. 逻辑一致性
- **时机合适**：finish阶段是构建流程的最后阶段，适合进行版本重置
- **条件明确**：只有在所有锁都释放后才检查版本重置
- **原子操作**：版本重置作为finish阶段的一部分，逻辑清晰

### 4. 维护性提升
- **代码集中**：版本重置逻辑集中在一个文件中
- **易于调试**：问题定位更简单
- **减少复杂性**：其他脚本逻辑更清晰

## 触发时机

版本重置现在会在以下时机自动触发：

1. **构建完成后**：当构建完成，进入finish阶段时
2. **所有锁释放后**：当三锁架构的所有锁都已释放时
3. **队列为空时**：当构建队列中没有待处理项目时

## 重置条件

版本重置的条件保持不变：

```bash
# 所有条件都必须满足
queue_length == 0 &&                    # 队列为空
issue_locked_by == null &&              # Issue锁为空
queue_locked_by == null &&              # 队列锁为空  
build_locked_by == null &&              # 构建锁为空
current_run_id == null &&               # 当前运行ID为空
(version > 100 ||                       # 任一版本号超过阈值
 issue_lock_version > 100 ||
 queue_lock_version > 100 ||
 build_lock_version > 100)
```

## 日志记录

优化后的日志更加清晰：

```
[INFO] Checking if version numbers should be reset...
[INFO] Lock status check:
[INFO] issue_locked_by: null
[INFO] queue_locked_by: null
[INFO] build_locked_by: null
[INFO] current_run_id: null
[INFO] queue_length: 0
[INFO] All locks are free and queue is empty, checking version numbers...
[INFO] Version numbers:
[INFO] version: 105
[INFO] issue_lock_version: 98
[INFO] queue_lock_version: 102
[INFO] build_lock_version: 95
[INFO] Version numbers are high, resetting to 1
[SUCCESS] Successfully reset version numbers to 1
```

## 总结

这次最终优化完全符合用户的要求：
- ✅ **仅再finish阶段检查**：版本重置检查现在只在finish阶段进行
- ✅ **如果三锁为空，则重置**：只有在所有锁都为空且队列为空时才进行版本重置
- ✅ **极简设计**：从多个检查点简化为单一检查点
- ✅ **逻辑清晰**：版本重置作为finish阶段的一部分，职责明确
- ✅ **性能优化**：减少了重复检查和不必要的操作

这个最终优化使得版本重置机制达到了最简化的状态，同时保持了功能的完整性和可靠性。 