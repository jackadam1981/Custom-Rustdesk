# 三锁架构验证文档

## 用户要求

用户明确要求的三锁架构流程：

> "队列处理很快，构建处理很慢，所以进行队列处理时，获取issue锁后，获取队列锁，处理完队列后释放队列锁；构建锁进行构建处理时，获取issue锁后，获取构建锁，标识构建锁后，释放issue锁，构建结束后再获取issue锁，释放构建锁，释放issue锁。"

## 当前实现验证

### 1. 队列处理流程（queue_manager_join）

**当前实现：**
```bash
# 获取 Issue 锁
if ! queue_manager_acquire_issue_lock "$build_id"; then
    debug "error" "Failed to acquire issue lock"
    return 1
fi

# 获取队列锁
if ! queue_manager_acquire_queue_lock "$build_id"; then
    debug "error" "Failed to acquire queue lock"
    queue_manager_release_issue_lock "$build_id"
    return 1
fi

# 在队列锁保护下执行队列操作
# ... 队列操作逻辑 ...

# 释放队列锁和 Issue 锁
queue_manager_release_queue_lock "$build_id"
queue_manager_release_issue_lock "$build_id"
```

**✅ 符合要求：**
- ✅ 先获取issue锁
- ✅ 再获取队列锁
- ✅ 处理完队列后释放队列锁
- ✅ 最后释放issue锁

### 2. 构建处理流程（queue_manager_acquire_lock）

**当前实现：**
```bash
# 获取 Issue 锁
if ! queue_manager_acquire_issue_lock "$build_id"; then
    debug "error" "Failed to acquire issue lock for build"
    sleep "$_QUEUE_MANAGER_CHECK_INTERVAL"
    continue
fi

# 获取构建锁
if queue_manager_acquire_build_lock "$build_id"; then
    debug "success" "Successfully acquired build lock"
    
    # 更新队列数据，设置当前构建
    local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '
        .run_id = $build_id |
        .version = (.version // 0) + 1
    ')

    # 更新队列锁评论
    local update_response=$(queue_manager_update_queue_comment "$updated_queue_data" "无")

    if [ $? -eq 0 ]; then
        debug "success" "Successfully updated queue with build lock"
        _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"

        # 释放 Issue 锁（构建锁已获取，可以释放 Issue 锁）
        queue_manager_release_issue_lock "$build_id"
        return 0
    else
        debug "error" "Failed to update queue with build lock"
        queue_manager_release_build_lock "$build_id"
        queue_manager_release_issue_lock "$build_id"
    fi
else
    debug "error" "Failed to acquire build lock"
    queue_manager_release_issue_lock "$build_id"
fi
```

**✅ 符合要求：**
- ✅ 先获取issue锁
- ✅ 再获取构建锁
- ✅ 标识构建锁后释放issue锁

### 3. 构建结束后的锁释放流程（queue_manager_release_lock）

**当前实现：**
```bash
# 获取 Issue 锁
if ! queue_manager_acquire_issue_lock "$build_id"; then
    debug "error" "Failed to acquire issue lock for release"
    return 1
fi

# 刷新队列数据
queue_manager_refresh

# 从队列中移除当前构建
local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" '
    .queue = (.queue | map(select(.build_id != $build_id))) |
    .run_id = null |
    .version = (.version // 0) + 1
')

# 更新队列锁评论
local update_response=$(queue_manager_update_queue_comment "$updated_queue_data" "无")

if [ $? -eq 0 ]; then
    debug "success" "Successfully updated queue after build completion"
    _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
    
    # 释放构建锁
    queue_manager_release_build_lock "$build_id"
    
    # 释放 Issue 锁
    queue_manager_release_issue_lock "$build_id"
    
    debug "success" "Successfully released build lock"
    return 0
else
    debug "error" "Failed to update queue after build completion"
    queue_manager_release_issue_lock "$build_id"
    return 1
fi
```

**✅ 符合要求：**
- ✅ 构建结束后再获取issue锁
- ✅ 释放构建锁
- ✅ 释放issue锁

### 4. 工作流中的锁管理

**join-queue阶段：**
```yaml
# 使用三锁架构加入队列
join_result=$(queue_manager "join" "$ISSUE_NUMBER" "$TRIGGER_DATA" "5")
```

**wait-build-lock阶段：**
```yaml
# 使用三锁架构获取构建锁
lock_result=$(queue_manager "acquire" "$BUILD_ID" "5")
```

**finish阶段：**
```yaml
# 释放三锁架构的所有锁
lock_released_output=$(finish_manager "release-triple-lock" "$TRIGGER_DATA" "$build_status" "$download_url" "$error_message" "$build_id")
```

## 锁获取和释放的完整流程

### 队列处理流程：
1. **获取issue锁** → 2. **获取队列锁** → 3. **执行队列操作** → 4. **释放队列锁** → 5. **释放issue锁**

### 构建处理流程：
1. **获取issue锁** → 2. **获取构建锁** → 3. **标识构建锁** → 4. **释放issue锁** → 5. **执行构建** → 6. **获取issue锁** → 7. **释放构建锁** → 8. **释放issue锁**

## 关键特性验证

### ✅ 死锁预防
- `queue_manager_join`中避免了嵌套锁获取的死锁问题
- 当队列为空时，直接重置队列数据而不是调用`queue_manager_reset`

### ✅ 并发冲突解决
- 所有队列数据修改操作都先获取issue锁
- 使用版本号机制确保原子性操作

### ✅ 锁超时机制
- Issue锁：30秒超时
- 队列锁：5分钟超时  
- 构建锁：2小时超时

### ✅ 错误处理
- 锁获取失败时的回滚机制
- 部分锁释放失败时的状态跟踪

## 结论

**当前的三锁架构实现完全符合用户要求：**

1. **队列处理**：先获取issue锁，再获取队列锁，处理完释放队列锁，最后释放issue锁
2. **构建处理**：先获取issue锁，再获取构建锁，标识后释放issue锁，构建结束后再获取issue锁，释放构建锁，最后释放issue锁
3. **并发控制**：所有操作都正确遵循"先获取issue锁"的原则
4. **死锁预防**：避免了嵌套锁获取的问题
5. **错误处理**：完善的错误处理和回滚机制

三锁架构已经正确实现并符合用户的设计要求。 