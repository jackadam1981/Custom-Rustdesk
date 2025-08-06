#!/bin/bash
# 队列管理脚本 - 重构版本（1层调用架构）

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 配置
QUEUE_ISSUE_NUMBER="1"
QUEUE_LIMIT=5
ISSUE_LOCK_TIMEOUT=300       # 5分钟issue锁超时
BUILD_LOCK_HOLD_TIMEOUT=5400 # 90分钟构建锁持有超时

# 默认队列数据（双锁架构）
DEFAULT_QUEUE_DATA='{"issue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"build_lock_version":1,"version":1,"queue":[]}'

# 全局状态
QUEUE_DATA=""
TRIGGER_DATA=""

# 加载队列数据
_load_queue_data() {
  debug "log" "Loading queue data from issue #$QUEUE_ISSUE_NUMBER"

  local response=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$QUEUE_ISSUE_NUMBER")

  if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
    debug "error" "Queue manager issue not found"
    return 1
  fi

  local body_content=$(echo "$response" | jq -r '.body // empty')
  if [ -z "$body_content" ]; then
    debug "log" "No body content, using default data"
    QUEUE_DATA="$DEFAULT_QUEUE_DATA"
    return 0
  fi

  # 提取JSON数据
  local json_data=$(echo "$body_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
    QUEUE_DATA=$(echo "$json_data" | jq -c .)
    debug "log" "Queue data loaded successfully"
    return 0
  else
    debug "log" "Invalid JSON, using default data"
    QUEUE_DATA="$DEFAULT_QUEUE_DATA"
    return 0
  fi
}

# 更新队列数据
_update_queue_data() {
  local new_data="$1"
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')
  local version=$(echo "$new_data" | jq -r '.version // 1')

  # 生成issue body
  local body=$(generate_dual_lock_status_body "$current_time" "$new_data")

  debug "log" "Updating issue #$QUEUE_ISSUE_NUMBER"

  if issue_manager "update-content" "$QUEUE_ISSUE_NUMBER" "$body"; then
    QUEUE_DATA="$new_data"
    debug "success" "Queue data updated successfully"
    return 0
  else
    debug "error" "Failed to update queue data"
    return 1
  fi
}

# 内部锁操作函数（仅内部使用）
_acquire_lock() {
  local lock_type="$1" # issue/build
  local build_id="$2"
  local timeout="${3:-$ISSUE_LOCK_TIMEOUT}"

  debug "log" "Acquiring $lock_type lock for $build_id"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
    attempt=$((attempt + 1))
    debug "log" "Attempt $attempt: Loading queue data..."
    _load_queue_data

    local locked_by=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_locked_by // null")
    local lock_version=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_lock_version // 1")
    
    debug "log" "Attempt $attempt: Current ${lock_type}_locked_by=$locked_by, ${lock_type}_lock_version=$lock_version"

    # 检查是否可以获取锁
    if [ "$locked_by" = "null" ] || [ "$locked_by" = "$build_id" ]; then
      # 执行乐观锁更新
      local updated_data=$(echo "$QUEUE_DATA" | jq --arg build_id "$build_id" --arg version "$lock_version" "
        if (.${lock_type}_lock_version | tonumber) == (\$version | tonumber) then
          .${lock_type}_locked_by = \$build_id |
          .${lock_type}_lock_version = (.${lock_type}_lock_version | tonumber) + 1
        else
          .
        end
      ")

      local new_version=$(echo "$updated_data" | jq -r ".${lock_type}_lock_version // 1")
      local new_locked_by=$(echo "$updated_data" | jq -r ".${lock_type}_locked_by // null")

      # 检查操作是否成功
      if [ "$new_version" -gt "$lock_version" ] 2>/dev/null && [ "$new_locked_by" = "$build_id" ]; then
        if _update_queue_data "$updated_data"; then
          debug "success" "Successfully acquired $lock_type lock (attempt: $attempt)"
          return 0
        else
          debug "log" "Failed to update queue data, retrying... (attempt: $attempt)"
        fi
      else
        debug "log" "Optimistic lock failed, version mismatch, retrying... (attempt: $attempt)"
      fi
    else
      debug "log" "$lock_type lock held by $locked_by, waiting... (attempt: $attempt)"
    fi

    sleep 5
  done

  debug "error" "Failed to acquire $lock_type lock after $timeout seconds"
  return 1
}

_release_lock() {
  local lock_type="$1" # issue/build
  local build_id="$2"
  local timeout="${3:-$ISSUE_LOCK_TIMEOUT}"

  debug "log" "Releasing $lock_type lock for $build_id"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
    attempt=$((attempt + 1))
    debug "log" "Attempt $attempt: Loading queue data for lock release..."
    _load_queue_data

    local locked_by=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_locked_by // null")
    local lock_version=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_lock_version // 1")
    
    debug "log" "Attempt $attempt: Current ${lock_type}_locked_by=$locked_by, ${lock_type}_lock_version=$lock_version"

    # 检查是否可以释放锁
    if [ "$locked_by" = "$build_id" ]; then
      # 执行乐观锁更新
      local updated_data=$(echo "$QUEUE_DATA" | jq --arg version "$lock_version" "
        if (.${lock_type}_lock_version | tonumber) == (\$version | tonumber) then
          .${lock_type}_locked_by = null |
          .${lock_type}_lock_version = (.${lock_type}_lock_version | tonumber) + 1
        else
          .
        end
      ")

      local new_version=$(echo "$updated_data" | jq -r ".${lock_type}_lock_version // 1")
      local new_locked_by=$(echo "$updated_data" | jq -r ".${lock_type}_locked_by // null")

      # 检查操作是否成功
      if [ "$new_version" -gt "$lock_version" ] 2>/dev/null && [ "$new_locked_by" = "null" ]; then
        if _update_queue_data "$updated_data"; then
          debug "success" "Successfully released $lock_type lock (attempt: $attempt)"
          return 0
        else
          debug "log" "Failed to update queue data, retrying... (attempt: $attempt)"
        fi
      else
        debug "log" "Optimistic lock failed, version mismatch, retrying... (attempt: $attempt)"
      fi
    else
      debug "log" "Not holding $lock_type lock, no release needed"
      return 0
    fi

    sleep 5
  done

  debug "error" "Failed to release $lock_type lock after $timeout seconds"
  return 1
}

# 队列操作函数（自动处理Issue锁）
_join_queue() {
  local build_id="${GITHUB_RUN_ID:-}"
  local trigger_data="$1"
  
  debug "log" "Joining queue for $build_id"
  
  # 检查trigger_data是否提供
  if [ -z "$trigger_data" ]; then
    debug "error" "Trigger data is required for join queue operation"
    return 1
  fi
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for join queue"
    return 1
  fi
  
  # 执行队列操作
  _load_queue_data
  local queue_length=$(echo "$QUEUE_DATA" | jq '.queue | length // 0')

  if [ "$queue_length" -ge "$QUEUE_LIMIT" ]; then
    debug "error" "Queue is full ($queue_length/$QUEUE_LIMIT)"
    _release_lock "issue" "$build_id"
    return 1
  fi

  local already_in_queue=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(select(.run_id == $run_id)) | length')
  if [ "$already_in_queue" -gt 0 ]; then
    debug "log" "Already in queue"
    _release_lock "issue" "$build_id"
    return 0
  fi

  local parsed_data=$(echo "$trigger_data" | jq -c . 2>/dev/null || echo "{}")
  local tag=$(echo "$parsed_data" | jq -r '.tag // "latest"')
  local email=$(echo "$parsed_data" | jq -r '.email // "unknown"')
  local customer=$(echo "$parsed_data" | jq -r '.customer // "unknown"')
  local trigger_type=$(echo "$parsed_data" | jq -r '.trigger_type // "workflow_dispatch"')

  local new_item=$(jq -n \
    --arg run_id "$build_id" \
    --arg tag "$tag" \
    --arg email "$email" \
    --arg customer "$customer" \
    --arg trigger_type "$trigger_type" \
    --arg join_time "$(date '+%Y-%m-%d %H:%M:%S')" \
    '{run_id: $run_id, tag: $tag, email: $email, customer: $customer, trigger_type: $trigger_type, join_time: $join_time}')

  local updated_data=$(echo "$QUEUE_DATA" | jq --argjson new_item "$new_item" '
    .queue += [$new_item] |
    .version = (.version // 0) + 1
  ')

  if _update_queue_data "$updated_data"; then
    local position=$((queue_length + 1))
    debug "success" "Successfully joined queue at position $position"
    _release_lock "issue" "$build_id"
    echo "{\"queue_position\": $position, \"success\": true}"
    return 0
  else
    debug "error" "Failed to join queue"
    _release_lock "issue" "$build_id"
    return 1
  fi
}

_leave_queue() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Leaving queue for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for leave queue"
    return 1
  fi
  
  _load_queue_data
  local updated_data=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '
    .queue = (.queue | map(select(.run_id != $run_id))) |
    .version = (.version // 0) + 1
  ')

  if _update_queue_data "$updated_data"; then
    debug "success" "Successfully left queue"
    _release_lock "issue" "$build_id"
    return 0
  else
    debug "error" "Failed to leave queue"
    _release_lock "issue" "$build_id"
    return 1
  fi
}

_get_queue_status() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Getting queue status for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for get queue status"
    return 1
  fi
  
  _load_queue_data
  local queue_length=$(echo "$QUEUE_DATA" | jq '.queue | length // 0')
  echo "Queue length: $queue_length"
  
  _release_lock "issue" "$build_id"
  return 0
}

_cleanup_queue() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Cleaning up queue for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for cleanup queue"
    return 1
  fi
  
  _load_queue_data
  local cutoff_time=$(date -d "6 hours ago" '+%Y-%m-%d %H:%M:%S')
  
  # 获取队列中的run_ids
  local queue_run_ids=$(echo "$QUEUE_DATA" | jq -r '.queue[].run_id // empty')
  
  # 检查每个run_id的状态
  local cleaned_queue="[]"
  if [ -n "$queue_run_ids" ]; then
    for run_id in $queue_run_ids; do
      local should_keep=true
      
      # 检查时间（超过6小时的任务）
      local join_time=$(echo "$QUEUE_DATA" | jq -r --arg rid "$run_id" '.queue[] | select(.run_id == $rid) | .join_time')
      if [ "$join_time" != "null" ] && [ "$join_time" \< "$cutoff_time" ]; then
        debug "log" "Removing old task: $run_id (join_time: $join_time)"
        should_keep=false
      fi
      
      # 检查GitHub Actions状态（如果run_id看起来像真实的run ID）
      if [[ "$run_id" =~ ^[0-9]+$ ]] && [ "$should_keep" = true ]; then
        local run_status=$(gh run view "$run_id" --json status,conclusion 2>/dev/null | jq -r '.status // empty')
        if [ "$run_status" = "completed" ]; then
          debug "log" "Removing completed task: $run_id"
          should_keep=false
        elif [ "$run_status" = "failure" ]; then
          debug "log" "Removing failed task: $run_id"
          should_keep=false
        elif [ "$run_status" = "cancelled" ]; then
          debug "log" "Removing cancelled task: $run_id"
          should_keep=false
        elif [ "$run_status" = "timed_out" ]; then
          debug "log" "Removing timed out task: $run_id"
          should_keep=false
        elif [ "$run_status" = "skipped" ]; then
          debug "log" "Removing skipped task: $run_id"
          should_keep=false
        elif [ -z "$run_status" ]; then
          debug "log" "Removing non-existent task: $run_id"
          should_keep=false
        fi
      fi
      
      # 检查无效格式的run_id
      if [ -z "$run_id" ] || [ "$run_id" = "null" ] || [ "$run_id" = "undefined" ]; then
        debug "log" "Removing task with invalid run_id: $run_id"
        should_keep=false
      fi
      
      # 保留应该保留的任务
      if [ "$should_keep" = true ]; then
        local task_data=$(echo "$QUEUE_DATA" | jq -r --arg rid "$run_id" '.queue[] | select(.run_id == $rid)')
        cleaned_queue=$(echo "$cleaned_queue" | jq --argjson task "$task_data" '. += [$task]')
      fi
    done
  fi
  
  local cleaned_data=$(echo "$QUEUE_DATA" | jq --argjson cleaned_queue "$cleaned_queue" '
    .queue = $cleaned_queue |
    .version = (.version // 0) + 1
  ')

  if [ "$cleaned_data" != "$QUEUE_DATA" ]; then
    if _update_queue_data "$cleaned_data"; then
      debug "success" "Queue cleaned up"
      _release_lock "issue" "$build_id"
      return 0
    else
      debug "error" "Failed to cleanup queue"
      _release_lock "issue" "$build_id"
      return 1
    fi
  else
    debug "log" "No cleanup needed"
    _release_lock "issue" "$build_id"
    return 0
  fi
}

_reset_queue() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Resetting queue for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for reset queue"
    return 1
  fi
  
  local default_data='{"version":1,"issue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"build_lock_version":1,"queue":[]}'
  
  if _update_queue_data "$default_data"; then
    debug "success" "Successfully reset queue"
    _release_lock "issue" "$build_id"
    return 0
  else
    debug "error" "Failed to reset queue"
    _release_lock "issue" "$build_id"
    return 1
  fi
}

# 构建锁操作函数（自动处理Issue锁）
_acquire_build_lock() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Acquiring build lock for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for build lock acquisition"
    return 1
  fi
  
  # 检查队列位置
  _load_queue_data
  local current_build=$(echo "$QUEUE_DATA" | jq -r '.build_locked_by // null')
  local queue_position=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(.run_id) | index($run_id) // -1')
  
  if [ "$current_build" = "null" ] && [ "$queue_position" -eq 0 ]; then
    # 获取构建锁
    if _acquire_lock "build" "$build_id"; then
      debug "success" "Successfully acquired build lock"
      _release_lock "issue" "$build_id"
      return 0
    else
      debug "error" "Failed to acquire build lock"
      _release_lock "issue" "$build_id"
      return 1
    fi
  else
    debug "log" "Not our turn: current=$current_build, position=$queue_position"
    _release_lock "issue" "$build_id"
    return 1
  fi
}

_release_build_lock() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Releasing build lock for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for build lock release"
    return 1
  fi
  
  # 释放构建锁
  if _release_lock "build" "$build_id"; then
    debug "success" "Successfully released build lock"
    
    # 从队列中移除当前任务（构建完成后自动离开队列）
    _load_queue_data
    local updated_data=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '
      .queue = (.queue | map(select(.run_id != $run_id))) |
      .version = (.version // 0) + 1
    ')

    if _update_queue_data "$updated_data"; then
      debug "success" "Successfully removed task from queue after build completion"
    else
      debug "error" "Failed to remove task from queue after build completion"
    fi
    
    _release_lock "issue" "$build_id"
    return 0
  else
    debug "error" "Failed to release build lock"
    _release_lock "issue" "$build_id"
    return 1
  fi
}

_get_build_lock_status() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Getting build lock status for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for get build lock status"
    return 1
  fi
  
  _load_queue_data
  local current_build=$(echo "$QUEUE_DATA" | jq -r '.build_locked_by // null')

  if [ "$current_build" = "$build_id" ]; then
    echo "Build lock held by: $build_id"
  else
    echo "Build lock held by: $current_build"
  fi
  
  _release_lock "issue" "$build_id"
  return 0
}

# 构建锁获取重试函数（带超时）
_acquire_build_lock_with_retry() {
  local build_id="${GITHUB_RUN_ID:-}"

  if [ -z "$build_id" ]; then
    debug "error" "GITHUB_RUN_ID not available"
    return 1
  fi

  debug "log" "Acquiring build lock for $build_id with retry"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$BUILD_LOCK_HOLD_TIMEOUT" ]; do
    attempt=$((attempt + 1))

    # 尝试获取构建锁
    if _acquire_build_lock; then
      debug "success" "Successfully acquired build lock after $attempt attempts"
      return 0
    fi

    debug "log" "Build lock acquisition failed, retrying in 30 seconds... (attempt: $attempt)"
    sleep 30
  done

  debug "error" "Failed to acquire build lock after $BUILD_LOCK_HOLD_TIMEOUT seconds"
  return 1
}

# 主队列管理函数（1层调用架构）
queue_manager() {
  local lock_type="$1" # queue_lock/build_lock
  local operation="$2" # join/leave/acquire/release/status/cleanup/reset
  shift 2

  case "$lock_type" in
  "queue_lock")
    case "$operation" in
    "join")
      local trigger_data="$1"
      _join_queue "$trigger_data"
      ;;
    "leave")
      _leave_queue
      ;;
    "status")
      _get_queue_status
      ;;
    "cleanup")
      _cleanup_queue
      ;;
    "reset")
      _reset_queue
      ;;
    *)
      debug "error" "Unknown queue_lock operation: $operation"
      return 1
      ;;
    esac
    ;;
  "build_lock")
    case "$operation" in
    "acquire")
      _acquire_build_lock_with_retry
      ;;
    "release")
      _release_build_lock
      ;;
    "status")
      _get_build_lock_status
      ;;
    *)
      debug "error" "Unknown build_lock operation: $operation"
      return 1
      ;;
    esac
    ;;
  *)
    debug "error" "Unknown lock type: $lock_type"
    return 1
    ;;
  esac
}
