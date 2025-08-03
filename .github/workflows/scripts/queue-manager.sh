#!/bin/bash
# 队列管理脚本 - 重构版本
# 简化设计：统一锁管理，减少函数数量，清晰的数据流

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 配置
QUEUE_ISSUE_NUMBER="1"
QUEUE_LIMIT=5
LOCK_TIMEOUT=300 # 5分钟统一超时

# 默认队列数据（双锁架构）
DEFAULT_QUEUE_DATA='{"issue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"build_lock_version":1,"version":1,"queue":[]}'

# 全局状态
QUEUE_DATA=""

# ========== 核心数据操作 ==========

# 加载队列数据
load_queue_data() {
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
update_queue_data() {
  local new_data="$1"
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')
  local version=$(echo "$new_data" | jq -r '.version // 1')

  # 生成issue body
  local body=$(generate_dual_lock_status_body "$current_time" "$new_data" "$version")

  debug "log" "Updating issue #$QUEUE_ISSUE_NUMBER"

  if issue_manager "update-content" "$QUEUE_ISSUE_NUMBER" "" "$body"; then
    QUEUE_DATA="$new_data"
    debug "success" "Queue data updated successfully"
    return 0
  else
    debug "error" "Failed to update queue data"
    return 1
  fi
}

# ========== 锁操作 ==========

# 获取锁
acquire_lock() {
  local lock_type="$1" # issue/build
  local build_id="$2"
  local timeout="${3:-$LOCK_TIMEOUT}"

  debug "log" "Acquiring $lock_type lock for $build_id"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
    attempt=$((attempt + 1))
    load_queue_data

    local locked_by=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_locked_by // null")
    local lock_version=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_lock_version // 1")

    if [ "$locked_by" = "null" ] || [ "$locked_by" = "$build_id" ]; then
      # 乐观锁：检查版本号，如果匹配则更新
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

      # 检查乐观锁是否成功
      if [ "$new_version" -gt "$lock_version" ] && [ "$new_locked_by" = "$build_id" ]; then
        if update_queue_data "$updated_data"; then
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

# 释放锁
release_lock() {
  local lock_type="$1" # issue/build
  local build_id="$2"

  debug "log" "Releasing $lock_type lock for $build_id"

  load_queue_data
  local locked_by=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_locked_by // null")

  if [ "$locked_by" = "$build_id" ]; then
    # 乐观锁：检查版本号，确保我们持有的是最新版本
    local lock_version=$(echo "$QUEUE_DATA" | jq -r ".${lock_type}_lock_version // 1")
    
    local updated_data=$(echo "$QUEUE_DATA" | jq --arg lock_type "$lock_type" --arg version "$lock_version" "
      if (.${lock_type}_lock_version | tonumber) == (\$version | tonumber) then
        .${lock_type}_locked_by = null |
        .${lock_type}_lock_version = (.${lock_type}_lock_version | tonumber) + 1
      else
        .
      end
    ")

    local new_version=$(echo "$updated_data" | jq -r ".${lock_type}_lock_version // 1")
    local new_locked_by=$(echo "$updated_data" | jq -r ".${lock_type}_locked_by // null")

    # 检查乐观锁是否成功
    if [ "$new_version" -gt "$lock_version" ] && [ "$new_locked_by" = "null" ]; then
      if update_queue_data "$updated_data"; then
        debug "success" "Successfully released $lock_type lock"
          return 0
      else
        debug "error" "Failed to update queue data when releasing lock"
  return 1
    fi
  else
      debug "error" "Optimistic lock failed when releasing lock, version mismatch"
  return 1
    fi
  else
    debug "log" "Not holding $lock_type lock, no release needed"
          return 0
        fi
}

# ========== 队列操作 ==========

# 加入队列
join_queue() {
  local trigger_data="$1"
  local build_id="${GITHUB_RUN_ID:-}"

  if [ -z "$build_id" ]; then
    debug "error" "GITHUB_RUN_ID not available"
    return 1
  fi

  debug "log" "Joining queue with build_id: $build_id"

  # 获取issue锁（队列操作只需要issue锁）
  if ! acquire_lock "issue" "$build_id"; then
        debug "error" "Failed to acquire issue lock"
        return 1
    fi
    
  # 检查队列状态
  load_queue_data
  local queue_length=$(echo "$QUEUE_DATA" | jq '.queue | length // 0')

  if [ "$queue_length" -ge "$QUEUE_LIMIT" ]; then
    debug "error" "Queue is full ($queue_length/$QUEUE_LIMIT)"
    release_lock "issue" "$build_id"
      return 1
    fi

    # 检查是否已在队列中
  local already_in_queue=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(select(.run_id == $run_id)) | length')
    if [ "$already_in_queue" -gt 0 ]; then
      debug "log" "Already in queue"
    release_lock "issue" "$build_id"
      return 0
    fi

    # 解析触发数据
  local parsed_data=$(echo "$trigger_data" | jq -c . 2>/dev/null || echo "{}")
  local tag=$(echo "$parsed_data" | jq -r '.tag // "latest"')
  local email=$(echo "$parsed_data" | jq -r '.email // "unknown"')
  local customer=$(echo "$parsed_data" | jq -r '.customer // "unknown"')
  local trigger_type=$(echo "$parsed_data" | jq -r '.trigger_type // "workflow_dispatch"')

  # 创建队列项
  local new_item=$(jq -n \
    --arg run_id "$build_id" \
      --arg tag "$tag" \
      --arg email "$email" \
      --arg customer "$customer" \
      --arg trigger_type "$trigger_type" \
    --arg join_time "$(date '+%Y-%m-%d %H:%M:%S')" \
    '{run_id: $run_id, tag: $tag, email: $email, customer: $customer, trigger_type: $trigger_type, join_time: $join_time}')

  # 添加到队列
  local updated_data=$(echo "$QUEUE_DATA" | jq --argjson new_item "$new_item" '
            .queue += [$new_item] |
            .version = (.version // 0) + 1
        ')

  if update_queue_data "$updated_data"; then
    local position=$((queue_length + 1))
    debug "success" "Successfully joined queue at position $position"
    release_lock "issue" "$build_id"
    echo "{\"queue_position\": $position, \"success\": true}"
      return 0
    else
    debug "error" "Failed to join queue"
    release_lock "issue" "$build_id"
      return 1
    fi
}

# 获取构建锁
acquire_build_lock() {
  local build_id="${GITHUB_RUN_ID:-}"

  if [ -z "$build_id" ]; then
    debug "error" "GITHUB_RUN_ID not available"
    return 1
  fi

  debug "log" "Acquiring build lock for $build_id"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$LOCK_TIMEOUT" ]; do
    attempt=$((attempt + 1))
    load_queue_data

    # 检查是否在队列中
    local in_queue=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(select(.run_id == $run_id)) | length')
    if [ "$in_queue" -eq 0 ]; then
      debug "error" "Not in queue anymore"
      return 1
    fi

    # 检查是否轮到我们
    local current_build=$(echo "$QUEUE_DATA" | jq -r '.build_locked_by // null')
    local queue_position=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(.run_id) | index($run_id) // -1')

    if [ "$current_build" = "null" ] && [ "$queue_position" -eq 0 ]; then
      # 获取issue锁来保护构建锁获取
      if acquire_lock "issue" "$build_id"; then
        if acquire_lock "build" "$build_id"; then
          # 获取构建锁成功后，立即释放issue锁（构建过程很长，不能长时间持有issue锁）
          release_lock "issue" "$build_id"
          debug "success" "Successfully acquired build lock and released issue lock"
        return 0
                else
          release_lock "issue" "$build_id"
                fi
      fi
    fi

    debug "log" "Waiting for build lock, current: $current_build, position: $queue_position (attempt: $attempt)"
    sleep 30
  done

  debug "error" "Failed to acquire build lock after $LOCK_TIMEOUT seconds"
  return 1
}

# 释放所有锁
release_all_locks() {
  local build_id="${GITHUB_RUN_ID:-}"

  if [ -z "$build_id" ]; then
    debug "error" "GITHUB_RUN_ID not available"
        return 1
    fi

  debug "log" "Releasing all locks for $build_id"

  # 释放可能持有的锁（构建锁）
  release_lock "build" "$build_id"

  # 从队列中移除（需要issue锁保护）
  if acquire_lock "issue" "$build_id"; then
    load_queue_data
    local updated_data=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '
      .queue = (.queue | map(select(.run_id != $run_id))) |
        .version = (.version // 0) + 1
    ')

    update_queue_data "$updated_data"
    release_lock "issue" "$build_id"
    debug "success" "All locks released and removed from queue"
  else
    debug "error" "Failed to acquire issue lock for queue update"
    return 1
  fi
}

# 清理队列
cleanup_queue() {
  debug "log" "Cleaning up queue"
  load_queue_data

  # 清理超时项（6小时）
  local cutoff_time=$(date -d "6 hours ago" '+%Y-%m-%d %H:%M:%S')
  local cleaned_data=$(echo "$QUEUE_DATA" | jq --arg cutoff "$cutoff_time" '
    .queue = (.queue | map(select(.join_time >= $cutoff))) |
                .version = (.version // 0) + 1
            ')

  if [ "$cleaned_data" != "$QUEUE_DATA" ]; then
    update_queue_data "$cleaned_data"
    debug "success" "Queue cleaned up"
  else
    debug "log" "No cleanup needed"
  fi
}

# ========== 主函数 ==========

# 主队列管理函数
queue_manager() {
  local operation="$1"
  shift 1

  case "$operation" in
  "join")
    local trigger_data="$1"
    join_queue "$trigger_data"
    ;;
  "acquire")
    acquire_build_lock
    ;;
  "release")
    release_all_locks
    ;;
  "cleanup")
    cleanup_queue
    ;;
  "status")
    load_queue_data
    local queue_length=$(echo "$QUEUE_DATA" | jq '.queue | length // 0')
    echo "Queue length: $queue_length"
    ;;
  *)
    debug "error" "Unknown operation: $operation"
    return 1
    ;;
  esac
}
