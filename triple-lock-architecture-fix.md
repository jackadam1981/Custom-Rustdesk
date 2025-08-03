# 三锁架构修复总结

## 问题发现

在深入检查三锁架构时，发现了一个严重的问题：**某些操作直接更新队列数据而没有先获取issue锁**，这违反了"无论队列锁，构建锁，都是要先获取issue锁才能操作的"原则。

## 修复的问题

### 1. `queue_manager_cleanup` 函数

**问题：** 该函数在多个地方被调用，但直接更新队列数据而没有先获取issue锁。

**修复：** 在所有需要更新队列数据的清理操作前，先获取issue锁：
- 清理过期队列项
- 清理已完成的工作流
- 清理已完成的构建锁
- 移除重复项

**修复后的锁获取顺序：**
```bash
# 获取 Issue 锁来保护队列更新
local cleanup_build_id="cleanup_$(date +%s)"
if queue_manager_acquire_issue_lock "$cleanup_build_id"; then
    # 执行队列更新操作
    local update_response=$(queue_manager_update_queue_comment "$updated_data" "无")
    # ...
    queue_manager_release_issue_lock "$cleanup_build_id"
else
    debug "warning" "Failed to acquire issue lock for cleanup, skipping queue update"
fi
```

### 2. `queue_manager_reset` 函数

**问题：** 该函数直接更新issue而没有先获取issue锁。

**修复：** 在更新issue前先获取issue锁：
```bash
# 获取 Issue 锁来保护重置操作
local reset_build_id="reset_$(date +%s)"
if queue_manager_acquire_issue_lock "$reset_build_id"; then
    # 更新issue
    if queue_manager_update_issue "$reset_body"; then
        # ...
        queue_manager_release_issue_lock "$reset_build_id"
        return 0
    else
        queue_manager_release_issue_lock "$reset_build_id"
        return 1
    fi
else
    debug "error" "Failed to acquire issue lock for queue reset"
    return 1
fi
```

### 3. 死锁问题修复

**问题：** 在 `queue_manager_join` 函数中，当队列为空时调用 `queue_manager_reset`，但此时已经持有issue锁和队列锁，会导致死锁。

**修复：** 在已持有锁的情况下，直接重置队列数据而不调用 `queue_manager_reset`：
```bash
# 直接重置队列数据，因为已经持有issue锁和队列锁
local reset_queue_data='{"version": 1, "issue_locked_by": null, "queue_locked_by": null, "build_locked_by": null, "issue_lock_version": 1, "queue_lock_version": 1, "build_lock_version": 1, "queue": []}'
_QUEUE_MANAGER_QUEUE_DATA="$reset_queue_data"
```

## 三锁架构的正确实现

### 锁获取顺序

1. **Issue锁** - 最高优先级，所有操作都需要先获取
2. **队列锁** - 用于保护队列数据操作
3. **构建锁** - 用于保护构建过程

### 正确的操作流程

#### 加入队列操作
```bash
# 1. 获取 Issue 锁
queue_manager_acquire_issue_lock "$build_id"

# 2. 获取队列锁
queue_manager_acquire_queue_lock "$build_id"

# 3. 执行队列操作
# 4. 释放队列锁
queue_manager_release_queue_lock "$build_id"

# 5. 释放 Issue 锁
queue_manager_release_issue_lock "$build_id"
```

#### 获取构建锁操作
```bash
# 1. 获取 Issue 锁
queue_manager_acquire_issue_lock "$build_id"

# 2. 获取构建锁
queue_manager_acquire_build_lock "$build_id"

# 3. 更新队列数据
# 4. 释放 Issue 锁（构建锁已获取，可以释放 Issue 锁）
queue_manager_release_issue_lock "$build_id"
```

#### 释放构建锁操作
```bash
# 1. 获取 Issue 锁
queue_manager_acquire_issue_lock "$build_id"

# 2. 更新队列数据
# 3. 释放构建锁
queue_manager_release_build_lock "$build_id"

# 4. 释放 Issue 锁
queue_manager_release_issue_lock "$build_id"
```

#### 清理操作
```bash
# 1. 获取 Issue 锁
local cleanup_build_id="cleanup_$(date +%s)"
queue_manager_acquire_issue_lock "$cleanup_build_id"

# 2. 执行清理操作
# 3. 更新队列数据
# 4. 释放 Issue 锁
queue_manager_release_issue_lock "$cleanup_build_id"
```

## 修复后的优势

1. **并发安全：** 所有队列和构建锁操作都在issue锁保护下进行
2. **避免死锁：** 正确处理已持有锁的情况
3. **数据一致性：** 确保队列数据更新的原子性
4. **错误处理：** 当无法获取锁时，优雅地跳过操作而不是失败

## 验证要点

修复后的三锁架构确保：
- ✅ 所有队列锁操作都先获取issue锁
- ✅ 所有构建锁操作都先获取issue锁
- ✅ 所有清理操作都先获取issue锁
- ✅ 所有重置操作都先获取issue锁
- ✅ 避免在已持有锁的情况下再次获取锁
- ✅ 正确的锁释放顺序 