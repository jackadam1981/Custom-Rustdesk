#!/bin/bash
# 队列管理脚本 - 伪面向对象模式
# 这个文件包含所有队列操作功能，采用简单的伪面向对象设计
# 主要用于被 CustomBuildRustdesk.yml 工作流调用
# 整合了三锁架构（Issue锁 + 队列锁 + 构建锁）

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh
source .github/workflows/scripts/encryption-utils.sh
source .github/workflows/scripts/issue-templates.sh
source .github/workflows/scripts/issue-manager.sh

# 队列管理器 - 伪面向对象实现
# 使用全局变量存储实例状态
# 设计理念：队列管理器与触发方式解耦，统一使用Issue #1作为队列存储

# 队列管理Issue编号（固定值）
# 无论手动触发还是issue触发，都使用同一个Issue #1来管理队列状态
_QUEUE_MANAGER_ISSUE_NUMBER="1"

# 私有属性（全局变量）
_QUEUE_MANAGER_QUEUE_DATA=""

# 三锁架构配置参数
_QUEUE_MANAGER_MAX_RETRIES=3
_QUEUE_MANAGER_RETRY_DELAY=1
_QUEUE_MANAGER_MAX_WAIT_TIME=7200      # 2小时 - 构建锁获取超时
_QUEUE_MANAGER_CHECK_INTERVAL=30       # 30秒 - 检查间隔
_QUEUE_MANAGER_ISSUE_LOCK_TIMEOUT=30   # Issue 锁超时（30秒）
_QUEUE_MANAGER_QUEUE_LOCK_TIMEOUT=300  # 队列锁超时（5分钟）
_QUEUE_MANAGER_BUILD_LOCK_TIMEOUT=7200 # 构建锁超时（2小时）
_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS=6   # 队列项超时（6小时）

# 默认队列数据结构
_QUEUE_MANAGER_DEFAULT_DATA='{"issue_locked_by":null,"queue_locked_by":null,"build_locked_by":null,"issue_lock_version":1,"queue_lock_version":1,"build_lock_version":1,"version":1,"queue":[]}'

# 私有方法：加载队列数据
queue_manager_load_data() {
  debug "log" "Loading queue data from issue #$_QUEUE_MANAGER_ISSUE_NUMBER"

  local queue_manager_content=$(queue_manager_get_content "$_QUEUE_MANAGER_ISSUE_NUMBER")
  if [ $? -ne 0 ]; then
    debug "error" "Failed to get queue manager content"
    return 1
  fi

  debug "log" "Queue manager content received"

  _QUEUE_MANAGER_QUEUE_DATA=$(queue_manager_extract_json "$queue_manager_content")
  debug "log" "Queue data loaded successfully: $_QUEUE_MANAGER_QUEUE_DATA"
}

# 私有方法：获取队列管理器内容
queue_manager_get_content() {
  local issue_number="$1"

  # 确保issue_number有效
  if [ -z "$issue_number" ]; then
    debug "error" "Issue number is empty, using default issue #1"
    issue_number="1"
  fi



  local response=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/issues/$issue_number")

  if echo "$response" | jq -e '.message' | grep -q "Not Found"; then
    echo "Queue manager issue not found"
    return 1
  fi

  echo "$response"
}

# 私有方法：提取JSON数据
queue_manager_extract_json() {
  local issue_content="$1"

  debug "log" "Extracting JSON from issue content..."

  # 从issue body中提取
  local body_content=$(echo "$issue_content" | jq -r '.body // empty')

  if [ -z "$body_content" ]; then
    debug "error" "No body content found in issue"
    echo "$_QUEUE_MANAGER_DEFAULT_DATA"
    return
  fi

  # 提取 ```json ... ``` 代码块
  local json_data=$(echo "$body_content" | sed -n '/```json/,/```/p' | sed '1d;$d' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # 验证JSON格式并返回
  if [ -n "$json_data" ] && echo "$json_data" | jq . >/dev/null 2>&1; then
    local result=$(echo "$json_data" | jq -c .)
    debug "log" "Valid JSON extracted: $result"
    echo "$result"
  else
    debug "error" "JSON parsing failed, using default"
    echo "$_QUEUE_MANAGER_DEFAULT_DATA"
  fi
}

# 私有方法：更新issue（使用模板）
queue_manager_update_issue() {
  local queue_data="$1"



  # 获取当前时间并生成body
  local current_time=$(date '+%Y-%m-%d %H:%M:%S')
  local version=$(echo "$queue_data" | jq -r '.version // 1')
  
  # 从队列数据中提取锁状态
  local issue_locked_by=$(echo "$queue_data" | jq -r '.issue_locked_by // "无"')
  local queue_locked_by=$(echo "$queue_data" | jq -r '.queue_locked_by // "无"')
  local build_locked_by=$(echo "$queue_data" | jq -r '.build_locked_by // "无"')
  
  # 确定锁状态
  local issue_lock_status="空闲 🔓"
  local queue_lock_status="空闲 🔓"
  local build_lock_status="空闲 🔓"
  
  if [ "$issue_locked_by" != "无" ] && [ "$issue_locked_by" != "null" ]; then
    issue_lock_status="占用 🔒"
  fi
  if [ "$queue_locked_by" != "无" ] && [ "$queue_locked_by" != "null" ]; then
    queue_lock_status="占用 🔒"
  fi
  if [ "$build_locked_by" != "无" ] && [ "$build_locked_by" != "null" ]; then
    build_lock_status="占用 🔒"
  fi
  
  local body=$(generate_triple_lock_status_body "$current_time" "$queue_data" "$version" "$issue_lock_status" "$queue_lock_status" "$build_lock_status")

  debug "log" "Updating issue #$_QUEUE_MANAGER_ISSUE_NUMBER with template-generated body"

  # 使用 issue_manager 更新 issue 内容
  if issue_manager "update-content" "$_QUEUE_MANAGER_ISSUE_NUMBER" "" "$body"; then
    debug "success" "Issue updated successfully using template"
    return 0
  else
    debug "error" "Failed to update issue"
    return 1
  fi
}

# ========== 三锁架构核心函数 ==========

# 私有方法：更新锁状态（统一函数）
queue_manager_update_lock() {
  local queue_data="$1"
  local lock_type="$2" # issue/queue/build
  local locked_by="${3:-无}"

  # 确定要更新的字段
  local field_name=""
  case "$lock_type" in
  "issue") field_name="issue_locked_by" ;;
  "queue") field_name="queue_locked_by" ;;
  "build") field_name="build_locked_by" ;;
  *)
    debug "error" "Unknown lock type: $lock_type"
    return 1
    ;;
  esac

  # 更新队列数据中的锁字段
  local updated_data=$(echo "$queue_data" | jq --arg locked_by "$locked_by" --arg field "$field_name" '.[$field] = $locked_by')

  # 使用统一的更新函数
  queue_manager_update_issue "$updated_data"
}

# 统一的锁操作函数
queue_manager_lock_operation() {
  local operation="$1" # acquire/release
  local lock_type="$2" # issue/queue/build
  local build_id="$3"
  local timeout="$4"

  # 设置默认超时时间
  case "$lock_type" in
  "issue")
    timeout="${timeout:-$_QUEUE_MANAGER_ISSUE_LOCK_TIMEOUT}"
    ;;
  "queue")
    timeout="${timeout:-$_QUEUE_MANAGER_QUEUE_LOCK_TIMEOUT}"
    ;;
  "build")
    timeout="${timeout:-$_QUEUE_MANAGER_BUILD_LOCK_TIMEOUT}"
    ;;
  *)
    debug "error" "未知的锁类型: $lock_type"
    return 1
    ;;
  esac

  debug "log" "执行锁操作: $operation $lock_type, 构建ID: $build_id, 超时: ${timeout}s"

  case "$operation" in
  "acquire")
    queue_manager_acquire_lock_internal "$lock_type" "$build_id" "$timeout"
    ;;
  "release")
    queue_manager_release_lock_internal "$lock_type" "$build_id"
    ;;
  *)
    debug "error" "未知的操作类型: $operation"
    return 1
    ;;
  esac
}

# 内部获取锁实现
queue_manager_acquire_lock_internal() {
  local lock_type="$1"
  local build_id="$2"
  local timeout="$3"

  local start_time=$(date +%s)
  local attempt=0

  while [ $(($(date +%s) - start_time)) -lt "$timeout" ]; do
    attempt=$((attempt + 1))

    case "$lock_type" in
    "issue")
      # Issue锁逻辑
      queue_manager_refresh
      local locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_locked_by // null')
      local lock_version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_lock_version // 1')

      if [ "$locked_by" = "null" ] || [ "$locked_by" = "$build_id" ]; then
        local updated_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" --arg version "$lock_version" '
            if (.issue_lock_version | tonumber) == ($version | tonumber) then
              .issue_locked_by = $build_id |
              .issue_lock_version = (.issue_lock_version | tonumber) + 1
            else
              .
            end
          ')

        local new_version=$(echo "$updated_data" | jq -r '.issue_lock_version // 1')
        local new_locked_by=$(echo "$updated_data" | jq -r '.issue_locked_by // null')

        if [ "$new_version" -gt "$lock_version" ] && [ "$new_locked_by" = "$build_id" ]; then
          if queue_manager_update_lock "$updated_data" "issue" "$build_id"; then
            debug "success" "成功获取 Issue 锁（版本: $lock_version → $new_version，尝试次数: $attempt）"
            _QUEUE_MANAGER_QUEUE_DATA="$updated_data"
            return 0
          fi
        else
          debug "log" "版本检查失败，其他构建抢先获取了 Issue 锁（版本: $lock_version，尝试次数: $attempt）"
        fi
      else
        debug "log" "Issue 锁被 $locked_by 持有，等待释放...（尝试次数: $attempt）"
      fi
      ;;

    "queue" | "build")
      # 队列锁和构建锁逻辑（简化版）
      local comment_type="$lock_type"
      local lock_field="${lock_type}_locked_by"
      local version_field="${lock_type}_lock_version"

      # 从issue body中获取锁数据
      local lock_version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r ".$version_field // 1")
      local locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r ".$lock_field // null")

      if [ "$locked_by" = "null" ] || [ "$locked_by" = "$build_id" ]; then
        local updated_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg build_id "$build_id" --arg version "$lock_version" --arg lock_field "$lock_field" --arg version_field "$version_field" "
            if (.$version_field | tonumber) == (\$version | tonumber) then
              .$lock_field = \$build_id |
              .$version_field = (.$version_field | tonumber) + 1
            else
              .
            end
          ")

        local new_version=$(echo "$updated_data" | jq -r ".$version_field // 1")
        local new_locked_by=$(echo "$updated_data" | jq -r ".$lock_field // null")

        if [ "$new_version" -gt "$lock_version" ] && [ "$new_locked_by" = "$build_id" ]; then
          if queue_manager_update_issue "$updated_data"; then
            debug "success" "成功获取 ${comment_type} 锁（版本: $lock_version → $new_version，尝试次数: $attempt）"
            _QUEUE_MANAGER_QUEUE_DATA="$updated_data"
            return 0
          fi
        else
          debug "log" "版本检查失败，其他构建抢先获取了 ${comment_type} 锁（版本: $lock_version，尝试次数: $attempt）"
        fi
      else
        debug "log" "${comment_type} 锁被 $locked_by 持有，等待释放...（尝试次数: $attempt）"
      fi
      ;;
    esac

    # 指数退避延迟
    if [ "$attempt" -gt 1 ]; then
      local backoff_delay=$((_QUEUE_MANAGER_RETRY_DELAY * (2 ** (attempt - 1))))
      local max_backoff=10
      if [ "$backoff_delay" -gt "$max_backoff" ]; then
        backoff_delay="$max_backoff"
      fi
      debug "log" "指数退避延迟${backoff_delay}秒"
      sleep "$backoff_delay"
    else
      sleep "$_QUEUE_MANAGER_RETRY_DELAY"
    fi
  done

  debug "error" "获取 $lock_type 锁超时（总尝试次数: $attempt）"
  return 1
}

# 内部释放锁实现
queue_manager_release_lock_internal() {
  local lock_type="$1"
  local build_id="$2"

  debug "log" "释放 $lock_type 锁，构建ID: $build_id"

  case "$lock_type" in
  "issue")
    # Issue锁释放逻辑
    queue_manager_refresh
    local locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_locked_by // null')

    if [ "$locked_by" = "$build_id" ]; then
      local updated_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
          .issue_locked_by = null |
          .issue_lock_version = (.issue_lock_version // 0) + 1
        ')

      if queue_manager_update_lock "$updated_data" "issue" "无"; then
        debug "success" "成功释放 Issue 锁"
        _QUEUE_MANAGER_QUEUE_DATA="$updated_data"
        return 0
      fi
    else
      debug "log" "未持有 Issue 锁，无需释放"
      return 0
    fi
    ;;

  "queue" | "build")
    # 队列锁和构建锁释放逻辑（统一到issue body）
    local lock_field="${lock_type}_locked_by"
    local version_field="${lock_type}_lock_version"

    local locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r ".$lock_field // null")

    if [ "$locked_by" = "$build_id" ]; then
      local updated_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg lock_field "$lock_field" --arg version_field "$version_field" "
          .$lock_field = null |
          .$version_field = (.$version_field // 0) + 1
        ")

      if queue_manager_update_issue "$updated_data"; then
        debug "success" "成功释放 ${lock_type} 锁"
        _QUEUE_MANAGER_QUEUE_DATA="$updated_data"
        return 0
      fi
    else
      debug "log" "未持有 ${lock_type} 锁，无需释放"
      return 0
    fi
    ;;

  *)
    debug "error" "未知的锁类型: $lock_type"
    return 1
    ;;
  esac

  debug "error" "释放 $lock_type 锁失败"
  return 1
}

# 公共方法：获取队列状态
queue_manager_get_status() {
  local queue_length=$(queue_manager_get_length)
  local issue_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.issue_locked_by // "null"')
  local queue_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue_locked_by // "null"')
  local build_locked_by=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.build_locked_by // "null"')
  local version=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.version // 1')

  echo "队列统计:"
  echo "  总数量: $queue_length"
  echo "  版本: $version"
  echo "  锁状态:"
  echo "    Issue 锁: $issue_locked_by"
  echo "    队列锁: $queue_locked_by"
  echo "    构建锁: $build_locked_by"
}

# 公共方法：悲观锁加入队列
queue_manager_join() {
  local trigger_data="$1"
  local queue_limit="${2:-5}"

  echo "=== 悲观锁加入队列 ==="
  debug "log" "Starting pessimistic lock queue join process..."

  # 统一使用 GITHUB_RUN_ID 作为构建标识符
  local build_id="${GITHUB_RUN_ID:-}"
  if [ -z "$build_id" ]; then
    debug "error" "GITHUB_RUN_ID not available"
    return 1
  fi
  debug "log" "Using GITHUB_RUN_ID as build_id: $build_id"

  # 加载队列数据
  queue_manager_load_data

  # 执行统一的清理操作
  queue_manager_cleanup

  # 获取 Issue 锁
  if ! queue_manager_lock_operation "acquire" "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock"
    return 1
  fi

  # 获取队列锁
  if ! queue_manager_lock_operation "acquire" "queue" "$build_id"; then
    debug "error" "Failed to acquire queue lock"
    queue_manager_lock_operation "release" "issue" "$build_id"
    return 1
  fi

  # 在队列锁保护下执行队列操作
  debug "log" "Issue lock and queue lock acquired, performing queue operations..."

  # 刷新队列数据
  queue_manager_refresh

  # 验证队列数据结构
  local queue_data_valid=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -e '.queue != null and .version != null' >/dev/null 2>&1 && echo "true" || echo "false")
  if [ "$queue_data_valid" != "true" ]; then
    debug "error" "Invalid queue data structure"
    queue_manager_lock_operation "release" "queue" "$build_id"
    queue_manager_lock_operation "release" "issue" "$build_id"
    return 1
  fi

  # 检查队列长度
  local current_queue_length=$(queue_manager_get_length)

  # 如果队列为空，重置队列状态到版本1
  if [ "$current_queue_length" -eq 0 ]; then
    debug "log" "Queue is empty, resetting queue state to version 1"
    # 直接重置队列数据，因为已经持有issue锁和队列锁
    local reset_queue_data='{"issue_locked_by": null, "queue_locked_by": null, "build_locked_by": null, "issue_lock_version": 1, "queue_lock_version": 1, "build_lock_version": 1, "version": 1, "queue": []}'
    _QUEUE_MANAGER_QUEUE_DATA="$reset_queue_data"
    current_queue_length=0
  fi

  if [ "$current_queue_length" -ge "$queue_limit" ]; then
    debug "error" "Queue is full ($current_queue_length/$queue_limit)"
    queue_manager_lock_operation "release" "queue" "$build_id"
    queue_manager_lock_operation "release" "issue" "$build_id"
    return 1
  fi

  # 检查是否已在队列中
  local already_in_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(select(.run_id == $run_id)) | length')
  if [ "$already_in_queue" -gt 0 ]; then
    debug "log" "Already in queue"
    queue_manager_lock_operation "release" "queue" "$build_id"
    queue_manager_lock_operation "release" "issue" "$build_id"
    return 0
  fi

  # 解析触发数据
  debug "log" "Parsing trigger data: $trigger_data"
  local parsed_trigger_data=$(echo "$trigger_data" | jq -c . 2>/dev/null || echo "{}")
  debug "log" "Parsed trigger data: $parsed_trigger_data"

  # 提取构建信息
  debug "log" "Extracting build information..."
  local tag=$(echo "$parsed_trigger_data" | jq -r '.build_params.tag // empty')
  local email=$(echo "$parsed_trigger_data" | jq -r '.build_params.email // empty')
  local customer=$(echo "$parsed_trigger_data" | jq -r '.build_params.customer // empty')
  local customer_link=$(echo "$parsed_trigger_data" | jq -r '.build_params.customer_link // empty')
  local super_password=$(echo "$parsed_trigger_data" | jq -r '.build_params.super_password // empty')
  local slogan=$(echo "$parsed_trigger_data" | jq -r '.build_params.slogan // empty')
  local rendezvous_server=$(echo "$parsed_trigger_data" | jq -r '.build_params.rendezvous_server // empty')
  local rs_pub_key=$(echo "$parsed_trigger_data" | jq -r '.build_params.rs_pub_key // empty')
  local api_server=$(echo "$parsed_trigger_data" | jq -r '.build_params.api_server // empty')
  local trigger_type=$(echo "$parsed_trigger_data" | jq -r '.trigger_type // empty')

  debug "log" "Extracted build info - tag: '$tag', email: '$email', customer: '$customer', slogan: '$slogan', trigger_type: '$trigger_type'"
  debug "log" "Extracted privacy info - rendezvous_server: '$rendezvous_server', api_server: '$api_server'"

  # 创建新队列项
  debug "log" "Creating new queue item..."
  local new_queue_item=$(jq -c -n \
    --arg run_id "$build_id" \
    --arg build_title "Custom Rustdesk Build" \
    --arg tag "$tag" \
    --arg email "$email" \
    --arg customer "$customer" \
    --arg customer_link "$customer_link" \
    --arg super_password "$super_password" \
    --arg slogan "$slogan" \
    --arg rendezvous_server "$rendezvous_server" \
    --arg rs_pub_key "$rs_pub_key" \
    --arg api_server "$api_server" \
    --arg trigger_type "$trigger_type" \
    --arg join_time "$(date '+%Y-%m-%d %H:%M:%S')" \
    '{run_id: $run_id, build_title: $build_title, tag: $tag, email: $email, customer: $customer, customer_link: $customer_link, super_password: $super_password, slogan: $slogan, rendezvous_server: $rendezvous_server, rs_pub_key: $rs_pub_key, api_server: $api_server, trigger_type: $trigger_type, join_time: $join_time}')

  debug "log" "New queue item created: $new_queue_item"

  # 添加新项到队列
  debug "log" "Current queue data: $_QUEUE_MANAGER_QUEUE_DATA"
  local new_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --argjson new_item "$new_queue_item" '
            .queue += [$new_item] |
            .version = (.version // 0) + 1
        ')

  debug "log" "Updated queue data: $new_queue_data"

  # 更新队列（在队列锁保护下）
  local update_response=$(queue_manager_update_lock "$new_queue_data" "queue" "$build_id")

  if [ $? -eq 0 ]; then
    local queue_position=$((current_queue_length + 1))
    debug "success" "Successfully joined queue at position $queue_position"
    _QUEUE_MANAGER_QUEUE_DATA="$new_queue_data"

    # 释放队列锁和 Issue 锁
    queue_manager_lock_operation "release" "queue" "$build_id"
    queue_manager_lock_operation "release" "issue" "$build_id"

    # 返回包含队列位置的 JSON 数据
    echo "{\"queue_position\": $queue_position, \"success\": true}"
    return 0
  else
    debug "error" "Failed to update queue"
    queue_manager_lock_operation "release" "queue" "$build_id"
    queue_manager_lock_operation "release" "issue" "$build_id"

    # 返回失败信息
    echo "{\"queue_position\": -1, \"success\": false}"
    return 1
  fi
}

# 公共方法：悲观锁获取构建权限
queue_manager_acquire_lock() {
  local queue_limit="${2:-5}"

  echo "=== 悲观锁获取构建权限 ==="
  debug "log" "Starting pessimistic lock acquisition..."

  # 统一使用 GITHUB_RUN_ID 作为构建标识符
  local build_id="${GITHUB_RUN_ID:-}"
  if [ -z "$build_id" ]; then
    debug "error" "GITHUB_RUN_ID not available"
    return 1
  fi
  debug "log" "Using GITHUB_RUN_ID as build_id: $build_id"

  local start_time=$(date +%s)

  while [ $(($(date +%s) - start_time)) -lt $_QUEUE_MANAGER_MAX_WAIT_TIME ]; do
    # 刷新队列数据
    queue_manager_refresh

    # 执行统一的清理操作
    queue_manager_cleanup

    # 检查是否已在队列中
    local in_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(select(.run_id == $run_id)) | length')
    if [ "$in_queue" -eq 0 ]; then
      debug "error" "Not in queue anymore"
      return 1
    fi

    # 检查是否轮到我们构建
    local current_run_id=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.run_id // null')
    local queue_position=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg run_id "$build_id" '.queue | map(.run_id) | index($run_id) // -1')

    if [ "$current_run_id" = "null" ] && [ "$queue_position" -eq 0 ]; then
      # 获取 Issue 锁
      if ! queue_manager_lock_operation "acquire" "issue" "$build_id"; then
        debug "error" "Failed to acquire issue lock for build"
        sleep "$_QUEUE_MANAGER_CHECK_INTERVAL"
        continue
      fi

      # 获取构建锁
      if queue_manager_lock_operation "acquire" "build" "$build_id"; then
        debug "success" "Successfully acquired build lock"

        # 更新队列数据，设置当前构建
        local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg run_id "$build_id" '
                .run_id = $run_id |
                .version = (.version // 0) + 1
            ')

        # 更新队列锁
        local update_response=$(queue_manager_update_lock "$updated_queue_data" "queue" "无")

        if [ $? -eq 0 ]; then
          debug "success" "Successfully updated queue with build lock"
          _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"

          # 释放 Issue 锁（构建锁已获取，可以释放 Issue 锁）
          queue_manager_lock_operation "release" "issue" "$build_id"
          return 0
        else
          debug "error" "Failed to update queue with build lock"
          queue_manager_lock_operation "release" "build" "$build_id"
          queue_manager_lock_operation "release" "issue" "$build_id"
        fi
      else
        debug "error" "Failed to acquire build lock"
        queue_manager_lock_operation "release" "issue" "$build_id"
      fi
    elif [ "$current_run_id" = "$build_id" ]; then
      debug "log" "Already have build lock"
      return 0
    else
      debug "log" "Waiting for turn... Position: $((queue_position + 1)), Current: $current_run_id"
    fi

    sleep "$_QUEUE_MANAGER_CHECK_INTERVAL"
  done

  debug "error" "Timeout waiting for build lock"
  return 1
}

# 公共方法：释放构建锁
queue_manager_release_lock() {
  echo "=== 释放构建锁 ==="
  debug "log" "Releasing build lock..."

  # 统一使用 GITHUB_RUN_ID 作为构建标识符
  local build_id="${GITHUB_RUN_ID:-}"
  if [ -z "$build_id" ]; then
    debug "error" "GITHUB_RUN_ID not available"
    return 1
  fi
  debug "log" "Using GITHUB_RUN_ID as build_id: $build_id"

  # 获取 Issue 锁
  if ! queue_manager_lock_operation "acquire" "issue" "$build_id"; then
    debug "error" "Failed to acquire issue lock for release"
    return 1
  fi

  # 刷新队列数据
  queue_manager_refresh

  # 从队列中移除当前构建
  local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg run_id "$build_id" '
        .queue = (.queue | map(select(.run_id != $run_id))) |
        .run_id = null |
        .version = (.version // 0) + 1
    ')

  # 更新队列锁
  local update_response=$(queue_manager_update_lock "$updated_queue_data" "queue" "无")

  if [ $? -eq 0 ]; then
    debug "success" "Successfully updated queue after build completion"
    _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"

    # 释放构建锁
    queue_manager_lock_operation "release" "build" "$build_id"

    # 释放 Issue 锁
    queue_manager_lock_operation "release" "issue" "$build_id"

    debug "success" "Successfully released build lock"
    return 0
  else
    debug "error" "Failed to update queue after build completion"
    queue_manager_lock_operation "release" "issue" "$build_id"
    return 1
  fi
}

# 公共方法：统一的清理操作
queue_manager_cleanup() {
  debug "log" "Performing unified cleanup operations..."

  # 1. 自动清理过期队列项（超过6小时的）
  debug "log" "Step 1: Cleaning expired queue items (older than $_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS hours)"

  # 获取当前时间戳
  local current_time=$(date +%s)

  # 计算超时秒数
  local queue_timeout_seconds=$((_QUEUE_MANAGER_QUEUE_TIMEOUT_HOURS * 3600))

  # 移除超过队列超时时间的队列项
  local cleaned_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --arg current_time "$current_time" --arg timeout_seconds "$queue_timeout_seconds" '
            .queue = (.queue | map(select(
                # 将日期字符串转换为时间戳进行比较
                (($current_time | tonumber) - (try (.join_time | strptime("%Y-%m-%d %H:%M:%S") | mktime) catch 0)) < ($timeout_seconds | tonumber)
            )))
        ')

  # 只有在队列数据发生变化时才更新
  if [ "$cleaned_queue" != "$_QUEUE_MANAGER_QUEUE_DATA" ]; then
    # 获取 Issue 锁来保护队列更新
    local cleanup_build_id="$GITHUB_RUN_ID"
    if queue_manager_lock_operation "acquire" "issue" "$cleanup_build_id"; then
      local update_response=$(queue_manager_update_lock "$cleaned_queue" "queue" "无")
      if [ $? -eq 0 ]; then
        debug "success" "Auto-clean completed"
        _QUEUE_MANAGER_QUEUE_DATA="$cleaned_queue"
      else
        debug "error" "Auto-clean failed"
      fi
      queue_manager_lock_operation "release" "issue" "$cleanup_build_id"
    else
      debug "warning" "Failed to acquire issue lock for cleanup, skipping queue update"
    fi
  else
    debug "log" "No expired items to clean"
  fi

  # 2. 清理已完成的工作流
  debug "log" "Step 2: Cleaning completed workflows"
  local build_ids=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.queue[]?.run_id // empty')
  local builds_to_remove=()

  if [ -n "$build_ids" ]; then
    for build_id in $build_ids; do
      debug "log" "Checking build $build_id..."

      # 获取工作流运行状态
      local run_status="unknown"
      if [ -n "$GITHUB_TOKEN" ]; then
        local run_response=$(curl -s \
          -H "Authorization: token $GITHUB_TOKEN" \
          -H "Accept: application/vnd.github.v3+json" \
          "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$build_id")

        # 检查HTTP状态码
        local http_status=$(echo "$run_response" | jq -r '.status // empty')

        if [[ "$http_status" =~ ^[0-9]+$ ]] && [ "$http_status" -ge 400 ]; then
          run_status="not_found"
        elif echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
          run_status="not_found"
        else
          run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
        fi


      # 检查是否需要清理 - 只清理明确完成或失败的工作流
      case "$run_status" in
      "completed" | "cancelled" | "failure" | "skipped")
        debug "log" "Build $build_id needs cleanup (status: $run_status)"
        builds_to_remove+=("$build_id")
        ;;
      "queued" | "in_progress" | "waiting")
        debug "log" "Build $build_id is still running (status: $run_status), no cleanup needed"
        ;;
      "not_found" | "unknown")
        debug "log" "Build $build_id has unknown/not_found status: $run_status, not cleaning to avoid removing waiting builds"
        ;;
      *)
        debug "log" "Build $build_id has unexpected status: $run_status, not cleaning to avoid removing waiting builds"
        ;;
      esac
    done

    # 执行清理操作
    if [ ${#builds_to_remove[@]} -gt 0 ]; then
      debug "log" "Removing ${#builds_to_remove[@]} completed builds: ${builds_to_remove[*]}"

      # 从队列中移除这些构建
      local cleaned_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq --argjson builds_to_remove "$(printf '%s\n' "${builds_to_remove[@]}" | jq -R . | jq -s .)" '
                .queue = (.queue | map(select(.run_id as $id | $builds_to_remove | index($id) | not))) |
                .version = (.version // 0) + 1
            ')

      # 获取 Issue 锁来保护队列更新
      local cleanup_build_id="$GITHUB_RUN_ID"
      if queue_manager_lock_operation "acquire" "issue" "$cleanup_build_id"; then
        # 更新队列
        local update_response=$(queue_manager_update_lock "$cleaned_queue_data" "queue" "无")

        if [ $? -eq 0 ]; then
          debug "success" "Successfully cleaned ${#builds_to_remove[@]} completed builds"
          _QUEUE_MANAGER_QUEUE_DATA="$cleaned_queue_data"
        else
          debug "error" "Failed to clean completed builds"
        fi
        queue_manager_lock_operation "release" "issue" "$cleanup_build_id"
      else
        debug "warning" "Failed to acquire issue lock for cleanup, skipping queue update"
      fi
    else
      debug "log" "No builds need cleanup"
    fi
  else
    debug "log" "Queue is empty, nothing to clean"
  fi

  # 3. 检查并清理已完成的构建锁
  debug "log" "Step 3: Checking and cleaning completed build locks"
  local current_run_id=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq -r '.run_id // null')

  if [ "$current_run_id" != "null" ]; then
    debug "log" "Current build lock holder: $current_run_id"

    # 检查当前持有构建锁的构建状态
    local run_status="unknown"
    if [ -n "$GITHUB_TOKEN" ]; then
      local run_response=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runs/$current_run_id")

      # 检查HTTP状态码
      local http_status=$(echo "$run_response" | jq -r '.status // empty')

      if [[ "$http_status" =~ ^[0-9]+$ ]] && [ "$http_status" -ge 400 ]; then
        run_status="not_found"
      elif echo "$run_response" | jq -e '.message' | grep -q "Not Found"; then
        run_status="not_found"
      else
        run_status=$(echo "$run_response" | jq -r '.status // "unknown"')
      fi


    # 检查是否需要清理构建锁
    case "$run_status" in
    "completed" | "cancelled" | "failure" | "skipped")
      debug "log" "Current build lock holder needs cleanup (status: $run_status)"

      # 获取 Issue 锁来保护构建锁清理
      local cleanup_build_id="$GITHUB_RUN_ID"
      if queue_manager_lock_operation "acquire" "issue" "$cleanup_build_id"; then
        # 更新队列数据，释放构建锁
        local updated_queue_data=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
                .run_id = null |
                .version = (.version // 0) + 1
            ')

        debug "log" "Updated queue data after pessimistic lock release: $updated_queue_data"

        # 更新时释放三锁架构的所有锁
        local update_response=$(queue_manager_update_lock "$updated_queue_data" "queue" "无")

        if [ $? -eq 0 ]; then
          debug "success" "Successfully released lock for completed build"
          _QUEUE_MANAGER_QUEUE_DATA="$updated_queue_data"
        else
          debug "error" "Failed to release lock for completed build"
        fi
        queue_manager_lock_operation "release" "issue" "$cleanup_build_id"
      else
        debug "warning" "Failed to acquire issue lock for build lock cleanup, skipping"
      fi
      ;;
    "queued" | "in_progress" | "waiting")
      debug "log" "Current build lock holder is still running (status: $run_status), no cleanup needed"
      ;;
    "unknown")
      debug "log" "Current build lock holder has unknown status: $run_status, but not cleaning to avoid removing waiting builds"
      ;;
    *)
      debug "log" "Current build lock holder has unexpected status: $run_status, not cleaning to avoid removing waiting builds"
      ;;
    esac
  else
    debug "log" "No current build lock holder, no cleanup needed"
  fi

  # 4. 移除重复项（可选，仅在需要时执行）
  debug "log" "Step 4: Removing duplicate items (if any)"
  local current_queue_length=$(queue_manager_get_length)
  local unique_queue_length=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | group_by(.run_id) | length // 0')

      if [ "$current_queue_length" -gt "$unique_queue_length" ]; then
      debug "log" "Found duplicate items, removing them"
      local deduplicated_queue=$(echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '
              .queue = (.queue | group_by(.run_id) | map(.[0])) |
              .version = (.version // 0) + 1
          ')

      # 获取 Issue 锁来保护队列更新
      local cleanup_build_id="$GITHUB_RUN_ID"
    if queue_manager_lock_operation "acquire" "issue" "$cleanup_build_id"; then
      local update_response=$(queue_manager_update_lock "$deduplicated_queue" "queue" "无")

      if [ $? -eq 0 ]; then
        debug "success" "Successfully removed duplicate items"
        _QUEUE_MANAGER_QUEUE_DATA="$deduplicated_queue"
      else
        debug "error" "Failed to remove duplicate items"
      fi
      queue_manager_lock_operation "release" "issue" "$cleanup_build_id"
    else
      debug "warning" "Failed to acquire issue lock for deduplication, skipping"
    fi
  else
    debug "log" "No duplicate items found"
  fi

  debug "log" "Unified cleanup completed"
}

# 公共方法：重置队列
queue_manager_reset() {
  local reason="${1:-手动重置}"
  echo "=== 重置队列 ==="
  debug "log" "Resetting queue to default state: $reason"

  local now=$(date '+%Y-%m-%d %H:%M:%S')
  local reset_queue_data='{"issue_locked_by": null, "queue_locked_by": null, "build_locked_by": null, "issue_lock_version": 1, "queue_lock_version": 1, "build_lock_version": 1, "version": 1, "queue": []}'



  # 获取 Issue 锁来保护重置操作
  local reset_build_id="$GITHUB_RUN_ID"
  if queue_manager_lock_operation "acquire" "issue" "$reset_build_id"; then
    # 更新issue（使用模板）
    if queue_manager_update_issue "$reset_queue_data"; then
      debug "success" "Queue reset successful"
      _QUEUE_MANAGER_QUEUE_DATA="$reset_queue_data"
      queue_manager_lock_operation "release" "issue" "$reset_build_id"
      return 0
    else
      debug "error" "Queue reset failed"
      queue_manager_lock_operation "release" "issue" "$reset_build_id"
      return 1
    fi
  else
    debug "error" "Failed to acquire issue lock for queue reset"
    return 1
  fi
}

# 公共方法：刷新队列数据
queue_manager_refresh() {
  debug "log" "Refreshing queue data..."
  queue_manager_load_data
}

# 公共方法：获取队列数据
queue_manager_get_data() {
  echo "$_QUEUE_MANAGER_QUEUE_DATA"
}

# 公共方法：获取队列长度
queue_manager_get_length() {
  echo "$_QUEUE_MANAGER_QUEUE_DATA" | jq '.queue | length // 0'
}

# 公共方法：检查队列是否为空
queue_manager_is_empty() {
  [ "$(queue_manager_get_length)" -eq 0 ]
}

# 主队列管理函数 - 供工作流调用
queue_manager() {
  local operation="$1"
  shift 1

  # 加载队列数据
  queue_manager_load_data

  case "$operation" in
  "status")
    queue_manager_get_status
    ;;
  "join")
    local trigger_data="$1"
    local queue_limit="${2:-5}"
    queue_manager_join "$trigger_data" "$queue_limit"
    ;;
  "acquire")
    local queue_limit="${2:-5}"
    queue_manager_acquire_lock "$queue_limit"
    ;;
  "release")
    queue_manager_release_lock
    ;;
  "cleanup")
    queue_manager_cleanup
    ;;
  "reset")
    local reason="${1:-手动重置}"
    queue_manager_reset "$reason"
    ;;
  "refresh")
    queue_manager_refresh
    ;;
  "length")
    queue_manager_get_length
    ;;
  "empty")
    if queue_manager_is_empty; then
      echo "true"
    else
      echo "false"
    fi
    ;;
  "data")
    queue_manager_get_data
    ;;
  *)
    debug "error" "Unknown operation: $operation"
    return 1
    ;;
  esac
}
