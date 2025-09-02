#!/bin/bash
# 队列管理脚本 - 重构版本（1层调用架构）

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 配置
QUEUE_ISSUE_NUMBER="1"
QUEUE_LIMIT=5                # 总队列限制：5个
ISSUE_TRIGGER_LIMIT=3        # Issue触发限制：3个
MANUAL_TRIGGER_LIMIT=2       # 手动触发限制：2个
ISSUE_LOCK_TIMEOUT=300       # 5分钟issue锁超时
BUILD_LOCK_HOLD_TIMEOUT=5400 # 90分钟构建锁持有超时

# 环境检测和配置
if [ "${TEST_MODE:-}" = "true" ] || [ "${ENVIRONMENT:-}" = "test" ] || [ "${CI:-}" = "true" ]; then
    # 测试环境：极速模式，最小等待时间
    LOCK_RETRY_INTERVAL=0.05     # 0.05秒重试间隔（进一步减少）
    LOCK_MAX_ATTEMPTS=1          # 测试环境：最多1次尝试（立即失败）
    LOCK_BUSY_WAIT=0             # 测试环境：锁被占用时立即失败
    ISSUE_LOCK_TIMEOUT=5         # 测试环境：5秒超时（进一步减少）
    BUILD_LOCK_HOLD_TIMEOUT=60   # 测试环境：60秒超时（模拟60秒编译过程）
    API_CACHE_DURATION=1         # 测试环境：API缓存1秒
    # issue锁专用配置
    ISSUE_LOCK_RETRY_INTERVAL=0.05  # issue锁重试间隔
    ISSUE_LOCK_MAX_ATTEMPTS=1       # issue锁最大尝试次数
    ISSUE_LOCK_BUSY_WAIT=0          # issue锁被占用时立即失败
    debug "log" "Running in TEST mode: ultra-fast configuration for all locks (60s build timeout)"
else
    # 生产环境：正常重试，标准等待时间
    LOCK_RETRY_INTERVAL=2        # 2秒重试间隔
    LOCK_MAX_ATTEMPTS=10         # 最多10次尝试
    LOCK_BUSY_WAIT=5             # 锁被占用时等待5秒
    API_CACHE_DURATION=0         # 生产环境：无API缓存
    # issue锁专用配置
    ISSUE_LOCK_RETRY_INTERVAL=2     # issue锁重试间隔
    ISSUE_LOCK_MAX_ATTEMPTS=10      # issue锁最大尝试次数
    ISSUE_LOCK_BUSY_WAIT=5          # issue锁被占用时等待5秒
    debug "log" "Running in PRODUCTION mode: standard retry configuration"
fi

# 默认队列数据（双锁架构）
DEFAULT_QUEUE_DATA='{"issue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"build_lock_version":1,"version":1,"queue":[]}'

# 全局状态
QUEUE_DATA=""
TRIGGER_DATA=""
API_CACHE_TIMESTAMP=0
API_CACHE_DATA=""

# 加载队列数据（带缓存）
_load_queue_data() {
  local current_time=$(date +%s)
  
  # 检查缓存是否有效
  if [ $API_CACHE_DURATION -gt 0 ] && [ $((current_time - API_CACHE_TIMESTAMP)) -lt $API_CACHE_DURATION ] && [ -n "$API_CACHE_DATA" ]; then
    debug "log" "Using cached queue data (age: $((current_time - API_CACHE_TIMESTAMP))s)"
    QUEUE_DATA="$API_CACHE_DATA"
    return 0
  fi
  
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
    API_CACHE_DATA="$DEFAULT_QUEUE_DATA"
    API_CACHE_TIMESTAMP=$current_time
    return 0
  fi

  # 提取JSON数据
  local json_data=$(echo "$body_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
    QUEUE_DATA=$(echo "$json_data" | jq -c .)
    API_CACHE_DATA="$QUEUE_DATA"
    API_CACHE_TIMESTAMP=$current_time
    debug "log" "Queue data loaded successfully and cached"
    return 0
  else
    debug "log" "Invalid JSON, using default data"
    QUEUE_DATA="$DEFAULT_QUEUE_DATA"
    API_CACHE_DATA="$DEFAULT_QUEUE_DATA"
    API_CACHE_TIMESTAMP=$current_time
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

  # 根据锁类型选择配置参数
  local retry_interval
  local max_attempts
  local busy_wait
  
  if [ "$lock_type" = "issue" ]; then
    retry_interval=$ISSUE_LOCK_RETRY_INTERVAL
    max_attempts=$ISSUE_LOCK_MAX_ATTEMPTS
    busy_wait=$ISSUE_LOCK_BUSY_WAIT
  else
    retry_interval=$LOCK_RETRY_INTERVAL
    max_attempts=$LOCK_MAX_ATTEMPTS
    busy_wait=$LOCK_BUSY_WAIT
  fi

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ] && [ $attempt -lt $max_attempts ]; do
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
          # 清除缓存，确保下次读取最新数据
          API_CACHE_DATA=""
          return 0
        else
          debug "log" "Failed to update queue data, retrying... (attempt: $attempt)"
        fi
      else
        debug "log" "Optimistic lock failed, version mismatch, retrying... (attempt: $attempt)"
      fi
    else
      debug "log" "$lock_type lock held by $locked_by, waiting... (attempt: $attempt)"
      
      # 测试模式下，如果锁被占用，使用较短的重试间隔
      if [ $busy_wait -eq 0 ]; then
        debug "log" "TEST MODE: $lock_type lock busy, using short retry interval"
        sleep $retry_interval
        continue
      fi
    fi

    # 动态等待时间：如果锁被占用，等待更长时间
    if [ "$locked_by" != "null" ] && [ "$locked_by" != "$build_id" ]; then
      sleep $busy_wait  # 使用环境感知的等待时间
    else
      sleep $retry_interval   # 使用环境感知的重试间隔
    fi
  done

  debug "error" "Failed to acquire $lock_type lock after $timeout seconds and $attempt attempts"
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
  
  # 高并发重试机制：尝试获取issue锁
  local max_attempts=5
  local attempt=0
  local retry_interval=0.1
  
  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    debug "log" "Join queue attempt $attempt/$max_attempts for $build_id"
    
    # 尝试获取issue锁
    if _acquire_lock "issue" "$build_id"; then
      debug "log" "Successfully acquired issue lock for join queue (attempt: $attempt)"
      break
    else
      if [ $attempt -lt $max_attempts ]; then
        debug "log" "Failed to acquire issue lock, retrying in ${retry_interval}s... (attempt: $attempt)"
        sleep $retry_interval
        # 递增重试间隔，避免过度竞争
        retry_interval=$(echo "$retry_interval * 1.5" | bc -l 2>/dev/null || echo "0.2")
      else
        debug "error" "Failed to acquire issue lock after $max_attempts attempts"
        return 1
      fi
    fi
  done
  
  # 执行队列操作
  _load_queue_data
  local queue_length=$(echo "$QUEUE_DATA" | jq '.queue | length // 0')

  # 检查总队列限制
  if [ "$queue_length" -ge "$QUEUE_LIMIT" ]; then
    debug "error" "Queue is full ($queue_length/$QUEUE_LIMIT)"
    _release_lock "issue" "$build_id"
    return 1
  fi

  # 解析触发类型
  local parsed_data=$(echo "$trigger_data" | jq -c . 2>/dev/null || echo "{}")
  local trigger_type=$(echo "$parsed_data" | jq -r '.trigger_type // "workflow_dispatch"')
  debug "log" "Parsed trigger data: $parsed_data, trigger_type: $trigger_type"
  
  # 检查issue触发限制（改进的高并发版本）
  if [ "$trigger_type" = "issue" ]; then
    local issue_trigger_count=$(echo "$QUEUE_DATA" | jq '.queue | map(select(.trigger_type == "issue")) | length // 0')
    debug "log" "Current issue trigger count: $issue_trigger_count, limit: $ISSUE_TRIGGER_LIMIT"
    if [ "$issue_trigger_count" -ge "$ISSUE_TRIGGER_LIMIT" ]; then
      debug "error" "Issue trigger limit reached ($issue_trigger_count/$ISSUE_TRIGGER_LIMIT)"
      _release_lock "issue" "$build_id"
      return 1
    fi
  fi
  
  # 检查手动触发限制（改进的高并发版本）
  if [ "$trigger_type" = "workflow_dispatch" ]; then
    local manual_trigger_count=$(echo "$QUEUE_DATA" | jq '.queue | map(select(.trigger_type == "workflow_dispatch")) | length // 0')
    debug "log" "Current manual trigger count: $manual_trigger_count, limit: $MANUAL_TRIGGER_LIMIT"
    if [ "$manual_trigger_count" -ge "$MANUAL_TRIGGER_LIMIT" ]; then
      debug "error" "Manual trigger limit reached ($manual_trigger_count/$MANUAL_TRIGGER_LIMIT)"
      _release_lock "issue" "$build_id"
      return 1
    fi
  fi

  local already_in_queue=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(select(.run_id == $run_id)) | length')
  if [ "$already_in_queue" -gt 0 ]; then
    debug "log" "Already in queue"
    _release_lock "issue" "$build_id"
    return 0
  fi

  local tag=$(echo "$parsed_data" | jq -r '.tag // "latest"')
  local email=$(echo "$parsed_data" | jq -r '.email // "unknown"')
  local customer=$(echo "$parsed_data" | jq -r '.customer // "unknown"')

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

# 获取队列数据（JSON格式）
_get_queue_data() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Getting queue data for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for get queue data"
    return 1
  fi
  
  _load_queue_data
  echo "$QUEUE_DATA"
  
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
  # 保持6小时超时时间，这是合理的业务超时
  local cutoff_time=$(date -d "6 hours ago" '+%Y-%m-%d %H:%M:%S')
  
  # 获取队列中的run_ids
  local queue_run_ids=$(echo "$QUEUE_DATA" | jq -r '.queue[].run_id // empty')
  
  # 检查每个run_id的状态
  local cleaned_queue="[]"
  local cleaned_count=0
  local total_count=0
  local should_clear_build_lock=false
  local build_lock_holder=""
  
  # 检查构建锁状态
  local current_build_lock=$(echo "$QUEUE_DATA" | jq -r '.build_locked_by // null')
  if [ "$current_build_lock" != "null" ] && [ -n "$current_build_lock" ]; then
    build_lock_holder="$current_build_lock"
    debug "log" "检查构建锁持有者: $build_lock_holder"
    
    # 检查构建锁持有者的状态
    if [[ "$build_lock_holder" =~ ^[0-9]+$ ]]; then
      local lock_holder_info=$(gh run view "$build_lock_holder" --json status,conclusion 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$lock_holder_info" ]; then
        local lock_holder_status=$(echo "$lock_holder_info" | jq -r '.status // empty')
        local lock_holder_conclusion=$(echo "$lock_holder_info" | jq -r '.conclusion // empty')
        debug "log" "构建锁持有者 $build_lock_holder 状态: $lock_holder_status, 结论: $lock_holder_conclusion"
        
        # 如果构建锁持有者已完成（无论成功还是失败），都应该清理锁
        if [ "$lock_holder_status" = "completed" ]; then
          debug "log" "构建锁持有者已完成，需要清理构建锁"
          should_clear_build_lock=true
        fi
      else
        debug "log" "无法获取构建锁持有者状态，假设需要清理"
        should_clear_build_lock=true
      fi
    else
      debug "log" "构建锁持有者格式无效，需要清理"
      should_clear_build_lock=true
    fi
  fi
  
  if [ -n "$queue_run_ids" ]; then
    for run_id in $queue_run_ids; do
      total_count=$((total_count + 1))
      local should_keep=true
      local cleanup_reason=""
      
      # 检查时间（超过6小时的任务）
      local join_time=$(echo "$QUEUE_DATA" | jq -r --arg rid "$run_id" '.queue[] | select(.run_id == $rid) | .join_time')
      if [ "$join_time" != "null" ] && [ "$join_time" \< "$cutoff_time" ]; then
        cleanup_reason="超时任务 (join_time: $join_time, cutoff: $cutoff_time)"
        should_keep=false
        cleaned_count=$((cleaned_count + 1))
      fi
      
      # 检查GitHub Actions状态（如果run_id看起来像真实的run ID）
      if [[ "$run_id" =~ ^[0-9]+$ ]] && [ "$should_keep" = true ]; then
        local run_status=""
        local run_conclusion=""
        
        # 尝试获取工作流状态，添加错误处理
        local run_info=$(gh run view "$run_id" --json status,conclusion 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$run_info" ]; then
          run_status=$(echo "$run_info" | jq -r '.status // empty')
          run_conclusion=$(echo "$run_info" | jq -r '.conclusion // empty')
          debug "log" "Run $run_id status: $run_status, conclusion: $run_conclusion"
        else
          debug "log" "Failed to get status for run $run_id, treating as invalid"
          run_status="unknown"
        fi
        
        # 更全面的状态检查
        if [ "$run_status" = "completed" ]; then
          cleanup_reason="已完成任务 (status: $run_status, conclusion: $run_conclusion)"
          should_keep=false
          cleaned_count=$((cleaned_count + 1))
        elif [ "$run_status" = "failure" ]; then
          cleanup_reason="失败任务 (status: $run_status, conclusion: $run_conclusion)"
          should_keep=false
          cleaned_count=$((cleaned_count + 1))
        elif [ "$run_status" = "cancelled" ]; then
          cleanup_reason="已取消任务 (status: $run_status, conclusion: $run_conclusion)"
          should_keep=false
          cleaned_count=$((cleaned_count + 1))
        elif [ "$run_status" = "timed_out" ]; then
          cleanup_reason="超时任务 (status: $run_status, conclusion: $run_conclusion)"
          should_keep=false
          cleaned_count=$((cleaned_count + 1))
        elif [ "$run_status" = "skipped" ]; then
          cleanup_reason="已跳过任务 (status: $run_status, conclusion: $run_conclusion)"
          should_keep=false
          cleaned_count=$((cleaned_count + 1))
        elif [ "$run_status" = "unknown" ] || [ -z "$run_status" ]; then
          cleanup_reason="状态未知/无效任务 (status: $run_status)"
          should_keep=false
          cleaned_count=$((cleaned_count + 1))
        elif [ "$run_status" = "in_progress" ] || [ "$run_status" = "queued" ] || [ "$run_status" = "waiting" ]; then
          debug "log" "保留活跃任务: $run_id (status: $run_status)"
        else
          cleanup_reason="未知状态任务 (status: $run_status)，为安全起见移除"
          should_keep=false
          cleaned_count=$((cleaned_count + 1))
        fi
      fi
      
      # 检查无效格式的run_id
      if [ -z "$run_id" ] || [ "$run_id" = "null" ] || [ "$run_id" = "undefined" ]; then
        cleanup_reason="无效run_id格式: $run_id"
        should_keep=false
        cleaned_count=$((cleaned_count + 1))
      fi
      
      # 记录清理原因
      if [ "$should_keep" = false ] && [ -n "$cleanup_reason" ]; then
        debug "log" "移除任务 $run_id: $cleanup_reason"
      fi
      
      # 保留应该保留的任务
      if [ "$should_keep" = true ]; then
        local task_data=$(echo "$QUEUE_DATA" | jq -r --arg rid "$run_id" '.queue[] | select(.run_id == $rid)')
        cleaned_queue=$(echo "$cleaned_queue" | jq --argjson task "$task_data" '. += [$task]')
      fi
    done
  fi
  
  debug "log" "队列清理统计: $cleaned_count/$total_count 个任务被移除"
  
  # 准备清理后的队列数据
  local cleaned_data=$(echo "$QUEUE_DATA" | jq --argjson cleaned_queue "$cleaned_queue" '
    .queue = $cleaned_queue |
    .version = (.version // 0) + 1
  ')
  
  # 如果需要清理构建锁，也一并清理
  if [ "$should_clear_build_lock" = true ]; then
    debug "log" "清理失效的构建锁 (持有者: $build_lock_holder)"
    cleaned_data=$(echo "$cleaned_data" | jq '
      .build_locked_by = null |
      .build_lock_version = (.build_lock_version // 1) + 1
    ')
  fi

  if [ "$cleaned_data" != "$QUEUE_DATA" ]; then
    if _update_queue_data "$cleaned_data"; then
      debug "success" "队列清理完成: $cleaned_count 个任务被移除"
      _release_lock "issue" "$build_id"
      return 0
    else
      debug "error" "队列清理失败"
      _release_lock "issue" "$build_id"
      return 1
    fi
  else
    debug "log" "无需清理"
    _release_lock "issue" "$build_id"
    return 0
  fi
}

_reset_queue() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  echo "🔄 正在复位队列状态..."
  debug "log" "Resetting queue for $build_id"
  
  # reset命令：完全忽略锁检查，直接强制复位
  echo "🚀 管理命令：忽略锁检查，直接复位队列"
  
  # 强制复位为默认状态，确保完全清理
  local default_data='{"version":1,"issue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"build_lock_version":1,"queue":[]}'
  
  if _update_queue_data "$default_data"; then
    echo "✅ 队列复位成功"
    debug "success" "Successfully force reset queue (ignoring all locks)"
    return 0
  else
    echo "❌ 队列复位失败"
    debug "error" "Failed to force reset queue"
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
  
  # 在持有issue锁的情况下，原子性地检查和获取构建锁
  local start_time=$(date +%s)
  local attempt=0
  local max_attempts=$LOCK_MAX_ATTEMPTS
  
  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    debug "log" "Build lock acquisition attempt $attempt"
    
    # 重新加载队列数据（确保最新状态）
    _load_queue_data
    
    local current_build=$(echo "$QUEUE_DATA" | jq -r '.build_locked_by // null')
    local queue_position=$(echo "$QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(.run_id) | index($run_id) // -1')
    local queue_length=$(echo "$QUEUE_DATA" | jq '.queue | length')
    local build_lock_version=$(echo "$QUEUE_DATA" | jq -r '.build_lock_version // 1')
    
    debug "log" "Build lock status: current_holder=$current_build, our_position=$queue_position, queue_length=$queue_length, version=$build_lock_version"
    
    # 检查是否在队列中
    if [ "$queue_position" -eq -1 ]; then
      debug "error" "Cannot acquire build lock: not in queue"
      _release_lock "issue" "$build_id"
      return 2  # 特殊错误码：不在队列中
    fi
    
    # 检查是否轮到我们（必须是队列第一位）
    if [ "$queue_position" -ne 0 ]; then
      debug "log" "Cannot acquire build lock: not at front of queue (position=$queue_position)"
      _release_lock "issue" "$build_id"
      return 3  # 特殊错误码：不在队列首位
    fi
    
    # 检查构建锁是否已被占用
    if [ "$current_build" != "null" ] && [ "$current_build" != "$build_id" ]; then
      debug "log" "Cannot acquire build lock: already held by $current_build"
      _release_lock "issue" "$build_id"
      return 4  # 特殊错误码：锁已被其他进程占用
    fi
    
    # 尝试原子性地获取构建锁（使用改进的乐观锁）
    local updated_data=$(echo "$QUEUE_DATA" | jq --arg build_id "$build_id" --arg version "$build_lock_version" '
      if (.build_lock_version | tonumber) == ($version | tonumber) then
        .build_locked_by = $build_id |
        .build_lock_version = (.build_lock_version | tonumber) + 1
      else
        .
      end
    ')
    
    local new_version=$(echo "$updated_data" | jq -r '.build_lock_version // 1')
    local new_locked_by=$(echo "$updated_data" | jq -r '.build_locked_by // null')
    
    # 检查乐观锁是否成功
    if [ "$new_version" -gt "$build_lock_version" ] 2>/dev/null && [ "$new_locked_by" = "$build_id" ]; then
      # 原子性更新队列数据
      if _update_queue_data "$updated_data"; then
        debug "success" "Successfully acquired build lock (attempt: $attempt)"
        _release_lock "issue" "$build_id"
        return 0
      else
        debug "log" "Failed to update queue data, retrying... (attempt: $attempt)"
      fi
    else
      debug "log" "Optimistic lock failed, version mismatch, retrying... (attempt: $attempt)"
    fi
    
    # 改进的重试等待策略
    if [ "$attempt" -lt 3 ]; then
      # 前几次重试使用较短间隔
      sleep $LOCK_RETRY_INTERVAL
    else
      # 后续重试使用递增间隔
      local wait_time=$(echo "$LOCK_RETRY_INTERVAL * $attempt" | bc -l 2>/dev/null || echo "$LOCK_RETRY_INTERVAL")
      sleep "$wait_time"
    fi
  done
  
  debug "error" "Failed to acquire build lock after $max_attempts attempts"
  _release_lock "issue" "$build_id"
  return 1
}

_release_build_lock() {
  local build_id="${GITHUB_RUN_ID:-}"
  
  debug "log" "Releasing build lock for $build_id"
  
  # 自动获取issue锁
  if ! _acquire_lock "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for build lock release"
    return 1
  fi
  
  # 在持有issue锁的情况下，原子性地检查和释放构建锁
  local start_time=$(date +%s)
  local attempt=0
  local max_attempts=$LOCK_MAX_ATTEMPTS
  
  while [ $attempt -lt $max_attempts ]; do
    attempt=$((attempt + 1))
    debug "log" "Build lock release attempt $attempt"
    
    # 重新加载队列数据（确保最新状态）
    _load_queue_data
    
    local current_build=$(echo "$QUEUE_DATA" | jq -r '.build_locked_by // null')
    local build_lock_version=$(echo "$QUEUE_DATA" | jq -r '.build_lock_version // 1')
    
    debug "log" "Current build lock holder: $current_build, version: $build_lock_version"
    
    # 检查是否有权限释放锁
    if [ "$current_build" = "null" ]; then
      debug "warning" "Build lock is not currently held by anyone"
      _release_lock "issue" "$build_id"
      return 2  # 特殊错误码：锁未被持有
    fi
    
    if [ "$current_build" != "$build_id" ]; then
      debug "error" "Cannot release build lock: held by $current_build, not $build_id"
      _release_lock "issue" "$build_id"
      return 3  # 特殊错误码：锁被其他进程持有
    fi
    
    # 尝试原子性地释放构建锁（使用乐观锁）
    local updated_data=$(echo "$QUEUE_DATA" | jq --arg version "$build_lock_version" '
      if (.build_lock_version | tonumber) == ($version | tonumber) then
        .build_locked_by = null |
        .build_lock_version = (.build_lock_version | tonumber) + 1
      else
        .
      end
    ')
    
    local new_version=$(echo "$updated_data" | jq -r '.build_lock_version // 1')
    local new_locked_by=$(echo "$updated_data" | jq -r '.build_locked_by // null')
    
    # 检查乐观锁是否成功
    if [ "$new_version" -gt "$build_lock_version" ] 2>/dev/null && [ "$new_locked_by" = "null" ]; then
      # 原子性更新队列数据
      if _update_queue_data "$updated_data"; then
        debug "success" "Successfully released build lock (attempt: $attempt)"
        
        # 注意：任务需要主动调用leave_queue来离开队列
        debug "log" "Build lock released, task should call leave_queue to exit queue"
        
        _release_lock "issue" "$build_id"
        return 0
      else
        debug "log" "Failed to update queue data, retrying... (attempt: $attempt)"
      fi
    else
      debug "log" "Optimistic lock failed, version mismatch, retrying... (attempt: $attempt)"
    fi
    
    # 改进的重试等待策略
    if [ "$attempt" -lt 3 ]; then
      # 前几次重试使用较短间隔
      sleep $LOCK_RETRY_INTERVAL
    else
      # 后续重试使用递增间隔
      local wait_time=$(echo "$LOCK_RETRY_INTERVAL * $attempt" | bc -l 2>/dev/null || echo "$LOCK_RETRY_INTERVAL")
      sleep "$wait_time"
    fi
  done
  
  debug "error" "Failed to release build lock after $max_attempts attempts"
  _release_lock "issue" "$build_id"
  return 1
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
    _acquire_build_lock
    local exit_code=$?
    
    case $exit_code in
      0)
        debug "success" "Successfully acquired build lock after $attempt attempts"
        return 0
        ;;
      2)
        debug "error" "Cannot acquire build lock: not in queue (permanent failure)"
        return 2
        ;;
      3)
        debug "log" "Cannot acquire build lock: not at front of queue (attempt $attempt), waiting..."
        ;;
      4)
        debug "log" "Cannot acquire build lock: held by another process (attempt $attempt), waiting..."
        ;;
      *)
        debug "error" "Build lock acquisition failed with error $exit_code (attempt $attempt), retrying..."
        ;;
    esac

    debug "log" "Build lock acquisition failed, retrying in 30 seconds... (attempt: $attempt)"
    sleep 30
  done

  debug "error" "Failed to acquire build lock after $BUILD_LOCK_HOLD_TIMEOUT seconds and $attempt attempts"
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
    "get_data")
      _get_queue_data
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

# 公共接口函数（为工作流提供正确的函数名）
# 这些函数是 _cleanup_queue 和 _release_build_lock 的公共接口

# 清理队列的公共接口
cleanup_queue() {
    debug "log" "Public interface: cleanup_queue() called"
    _cleanup_queue
    return $?
}

# 释放所有锁的公共接口
release_all_locks() {
    local build_id="${GITHUB_RUN_ID:-}"
    debug "log" "Public interface: release_all_locks() called for $build_id"
    
    # 释放构建锁
    local build_lock_result=0
    if _release_build_lock; then
        debug "success" "Build lock released successfully"
        build_lock_result=0
    else
        debug "warning" "Failed to release build lock"
        build_lock_result=1
    fi
    
    # 释放问题锁（如果当前持有）
    local issue_lock_result=0
    local current_issue_holder=$(echo "$QUEUE_DATA" | jq -r '.issue_locked_by // null')
    if [ "$current_issue_holder" = "$build_id" ]; then
        if _release_lock "issue" "$build_id"; then
            debug "success" "Issue lock released successfully"
            issue_lock_result=0
        else
            debug "warning" "Failed to release issue lock"
            issue_lock_result=1
        fi
    else
        debug "log" "Issue lock not held by current build, skipping release"
        issue_lock_result=0
    fi
    
    # 返回总体结果
    if [ $build_lock_result -eq 0 ] && [ $issue_lock_result -eq 0 ]; then
        debug "success" "All locks released successfully"
        return 0
    else
        debug "warning" "Some locks failed to release"
        return 1
    fi
}
