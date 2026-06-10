#!/bin/bash
# 构建脚本 - 简化版本

# 加载依赖脚本
source .github/workflows/scripts/debug-utils.sh

# 提取构建数据
_extract_build_data() {
    local input="$1"
    
    # 校验输入JSON格式
    if ! debug "validate" "build.sh-输入数据校验" "$input"; then
        debug "error" "build.sh输入的JSON格式不正确"
        return 1
    fi
    
    # 检查数据格式：可能是 github.event 格式（有 inputs）或已处理格式（有 build_params）
    local tag=""
    local original_tag=""
    local email=""
    local customer=""
    local customer_link=""
    local slogan=""
    local super_password=""
    local rendezvous_server=""
    local relay_server=""
    local rs_pub_key=""
    local api_server=""
    local source_patch_debug=""
    
    # 尝试从 build_params 提取（已处理格式）
    if echo "$input" | jq -e '.build_params' > /dev/null 2>&1; then
        debug "log" "从 build_params 提取构建参数"
        tag=$(echo "$input" | jq -r '.build_params.tag // empty')
        original_tag=$(echo "$input" | jq -r '.build_params.original_tag // empty')
        email=$(echo "$input" | jq -r '.build_params.email // empty')
        customer=$(echo "$input" | jq -r '.build_params.customer // empty')
        customer_link=$(echo "$input" | jq -r '.build_params.customer_link // empty')
        slogan=$(echo "$input" | jq -r '.build_params.slogan // empty')
        super_password=$(echo "$input" | jq -r '.build_params.super_password // empty')
        rendezvous_server=$(echo "$input" | jq -r '.build_params.rendezvous_server // empty')
        relay_server=$(echo "$input" | jq -r '.build_params.relay_server // empty')
        rs_pub_key=$(echo "$input" | jq -r '.build_params.rs_pub_key // empty')
        api_server=$(echo "$input" | jq -r '.build_params.api_server // empty')
        source_patch_debug=$(echo "$input" | jq -r '.build_params.source_patch_debug // "false"')
    # 尝试从 inputs 提取（github.event 格式）
    elif echo "$input" | jq -e '.inputs' > /dev/null 2>&1; then
        debug "log" "从 inputs 提取构建参数"
        tag=$(echo "$input" | jq -r '.inputs.tag // empty')
        original_tag=$(echo "$input" | jq -r '.inputs.tag // empty')  # 对于 inputs，original_tag 就是 tag
        email=$(echo "$input" | jq -r '.inputs.email // empty')
        customer=$(echo "$input" | jq -r '.inputs.customer // empty')
        customer_link=$(echo "$input" | jq -r '.inputs.customer_link // empty')
        slogan=$(echo "$input" | jq -r '.inputs.slogan // empty')
        super_password=$(echo "$input" | jq -r '.inputs.super_password // empty')
        rendezvous_server=$(echo "$input" | jq -r '.inputs.rendezvous_server // empty')
        relay_server=$(echo "$input" | jq -r '.inputs.relay_server // empty')
        rs_pub_key=$(echo "$input" | jq -r '.inputs.rs_pub_key // empty')
        api_server=$(echo "$input" | jq -r '.inputs.api_server // empty')
        source_patch_debug=$(echo "$input" | jq -r '.inputs.source_patch_debug // .inputs.enable_debug // "false"')
    else
        debug "error" "无法识别的数据格式，缺少 build_params 或 inputs 字段"
        return 1
    fi
    
    # 验证必要参数
    if [ -z "$email" ]; then
        debug "error" "build.sh缺少必要参数: email"
        return 1
    fi
    
    # 输出提取的参数
    debug "log" "🔧 提取的构建参数:"
    debug "var" "TAG" "$tag"
    debug "var" "ORIGINAL_TAG" "$original_tag"
    debug "var" "EMAIL" "$email"
    debug "var" "CUSTOMER" "$customer"
    debug "var" "CUSTOMER_LINK" "$customer_link"
    debug "var" "SLOGAN" "$slogan"
    debug "var" "SUPER_PASSWORD" "$super_password"
    debug "var" "RENDEZVOUS_SERVER" "$rendezvous_server"
    debug "var" "RELAY_SERVER" "$relay_server"
    debug "var" "RS_PUB_KEY" "$rs_pub_key"
    debug "var" "API_SERVER" "$api_server"
    debug "var" "SOURCE_PATCH_DEBUG" "$source_patch_debug"
    
    # 设置环境变量供后续步骤使用（仅在 GitHub Actions 环境中）
    if [ -n "$GITHUB_ENV" ]; then
        echo "BUILD_TAG=$tag" >> $GITHUB_ENV
        echo "BUILD_ORIGINAL_TAG=$original_tag" >> $GITHUB_ENV
        echo "BUILD_EMAIL=$email" >> $GITHUB_ENV
        echo "BUILD_CUSTOMER=$customer" >> $GITHUB_ENV
        echo "BUILD_CUSTOMER_LINK=$customer_link" >> $GITHUB_ENV
        echo "BUILD_SLOGAN=$slogan" >> $GITHUB_ENV
        echo "BUILD_SUPER_PASSWORD=$super_password" >> $GITHUB_ENV
        echo "BUILD_RENDEZVOUS_SERVER=$rendezvous_server" >> $GITHUB_ENV
        echo "BUILD_RELAY_SERVER=$relay_server" >> $GITHUB_ENV
        echo "BUILD_RS_PUB_KEY=$rs_pub_key" >> $GITHUB_ENV
        echo "BUILD_API_SERVER=$api_server" >> $GITHUB_ENV
        echo "BUILD_SOURCE_PATCH_DEBUG=${source_patch_debug:-false}" >> $GITHUB_ENV
        echo "CURRENT_DATA=$input" >> $GITHUB_ENV
    else
        # 本地测试环境：输出到标准输出
        echo "BUILD_TAG=$tag" >&2
        echo "BUILD_ORIGINAL_TAG=$original_tag" >&2
        echo "BUILD_EMAIL=$email" >&2
        echo "BUILD_CUSTOMER=$customer" >&2
        echo "BUILD_CUSTOMER_LINK=$customer_link" >&2
        echo "BUILD_SLOGAN=$slogan" >&2
        echo "BUILD_SUPER_PASSWORD=$super_password" >&2
        echo "BUILD_RENDEZVOUS_SERVER=$rendezvous_server" >&2
        echo "BUILD_RELAY_SERVER=$relay_server" >&2
        echo "BUILD_RS_PUB_KEY=$rs_pub_key" >&2
        echo "BUILD_API_SERVER=$api_server" >&2
        echo "BUILD_SOURCE_PATCH_DEBUG=${source_patch_debug:-false}" >&2
        echo "CURRENT_DATA=$input" >&2
    fi
    
    # 构建包含 build_params 的输出数据
    local output_data=$(echo "$input" | jq -c \
        --arg tag "$tag" \
        --arg original_tag "$original_tag" \
        --arg email "$email" \
        --arg customer "$customer" \
        --arg customer_link "$customer_link" \
        --arg slogan "$slogan" \
        --arg super_password "$super_password" \
        --arg rendezvous_server "$rendezvous_server" \
        --arg relay_server "$relay_server" \
        --arg rs_pub_key "$rs_pub_key" \
        --arg api_server "$api_server" \
        --arg source_patch_debug "${source_patch_debug:-false}" \
        '. + {
            build_params: {
                tag: $tag,
                original_tag: $original_tag,
                email: $email,
                customer: $customer,
                customer_link: $customer_link,
                slogan: $slogan,
                super_password: $super_password,
                rendezvous_server: $rendezvous_server,
                relay_server: $relay_server,
                rs_pub_key: $rs_pub_key,
                api_server: $api_server,
                source_patch_debug: $source_patch_debug
            }
        }')
    
    echo "$output_data"
}

# 暂停构建（用于队列测试）
_pause_for_test() {
    # 使用环境变量控制测试等待时间，提供灵活性
    local default_pause="${TEST_BUILD_PAUSE:-60}"  # 默认60秒，可通过TEST_BUILD_PAUSE环境变量覆盖
    local pause_seconds="${1:-$default_pause}"
    echo "Pausing for $pause_seconds seconds to test queue..."
    echo "Test build pause time: ${TEST_BUILD_PAUSE:-60}s (default)"
    sleep "$pause_seconds"
}

# 执行实际的构建过程
_execute_build_process() {
    local current_data="$1"
    
    debug "log" "🚀 _execute_build_process 开始，输入数据长度: ${#current_data}"
    
    # 校验输入JSON格式
    if ! debug "validate" "build.sh-处理前数据校验" "$current_data"; then
        debug "error" "build.sh处理前JSON格式不正确"
        return 1
    fi
    
    debug "log" "🚀 开始执行构建过程..."
    
    # 获取构建参数
    local tag=$(echo "$current_data" | jq -r '.build_params.tag // .inputs.tag // empty')
    local email=$(echo "$current_data" | jq -r '.build_params.email // .inputs.email // empty')
    local customer=$(echo "$current_data" | jq -r '.build_params.customer // .inputs.customer // empty')
    local customer_link=$(echo "$current_data" | jq -r '.build_params.customer_link // .inputs.customer_link // empty')
    local slogan=$(echo "$current_data" | jq -r '.build_params.slogan // .inputs.slogan // empty')
    local super_password=$(echo "$current_data" | jq -r '.build_params.super_password // .inputs.super_password // empty')
    local rendezvous_server=$(echo "$current_data" | jq -r '.build_params.rendezvous_server // .inputs.rendezvous_server // empty')
    local relay_server=$(echo "$current_data" | jq -r '.build_params.relay_server // .inputs.relay_server // empty')
    local rs_pub_key=$(echo "$current_data" | jq -r '.build_params.rs_pub_key // .inputs.rs_pub_key // empty')
    local api_server=$(echo "$current_data" | jq -r '.build_params.api_server // .inputs.api_server // empty')
    local source_patch_debug=$(echo "$current_data" | jq -r '.build_params.source_patch_debug // .inputs.source_patch_debug // .inputs.enable_debug // "false"')
    
    debug "log" "🔧 提取的构建参数:"
    debug "var" "TAG" "$tag"
    debug "var" "EMAIL" "$email"
    debug "var" "CUSTOMER" "$customer"
    debug "var" "SOURCE_PATCH_DEBUG" "$source_patch_debug"
    
    # 构建开始时间
    local build_start_time=$(date -Iseconds)
    debug "log" "⏰ 构建开始时间: $build_start_time"
    
    # 模拟构建过程（300秒，用于测试并发抢锁）
    debug "log" "📦 步骤1: 准备构建环境..."
    sleep 30
    
    debug "log" "📦 步骤2: 同步RustDesk代码..."
    sleep 60
    
    debug "log" "📦 步骤3: 应用定制参数..."
    sleep 30
    
    debug "log" "📦 步骤4: 编译RustDesk..."
    sleep 120
    
    debug "log" "📦 步骤5: 生成安装包..."
    sleep 60
    
    # 构建结束时间
    local build_end_time=$(date -Iseconds)
    debug "log" "⏰ 构建结束时间: $build_end_time"
    
    # 生成下载URL（实际项目中应该上传到release或artifact）
    local download_filename="${tag:-custom}-rustdesk-$(date +%Y%m%d-%H%M%S).zip"
    local download_url="https://github.com/$GITHUB_REPOSITORY/releases/download/${tag:-latest}/$download_filename"
    
    # 更新数据，添加构建结果
    local processed=$(echo "$current_data" | jq -c \
        --arg build_time "$build_start_time" \
        --arg build_end_time "$build_end_time" \
        --arg download_url "$download_url" \
        --arg download_filename "$download_filename" \
        '. + {
            built: true, 
            build_start_time: $build_time,
            build_end_time: $build_end_time,
            download_url: $download_url,
            download_filename: $download_filename
        }')
    
    # 校验处理后JSON格式
    if ! debug "validate" "build.sh-处理后数据校验" "$processed"; then
        debug "error" "build.sh处理后JSON格式不正确"
        return 1
    fi
    
    # 设置构建结果环境变量
    echo "BUILD_DOWNLOAD_URL=$download_url" >> $GITHUB_ENV
    echo "BUILD_DOWNLOAD_FILENAME=$download_filename" >> $GITHUB_ENV
    echo "BUILD_START_TIME=$build_start_time" >> $GITHUB_ENV
    echo "BUILD_END_TIME=$build_end_time" >> $GITHUB_ENV
    
    echo "CURRENT_DATA=$processed" >> $GITHUB_ENV
    echo "$processed"
}

# 输出构建数据
_output_build_data() {
    local output_data="$1"
    
    # 校验输出JSON格式
    if ! debug "validate" "build.sh-输出数据校验" "$output_data"; then
        debug "error" "build.sh输出的JSON格式不正确"
        return 1
    fi

    # 从处理后的数据中提取结果
    local build_success=$(echo "$output_data" | jq -r '.built // false')
    local download_url=$(echo "$output_data" | jq -r '.download_url // empty')
    local error_message=""
    
    if [ "$build_success" != "true" ]; then
        error_message="构建过程失败"
        build_success="false"
    fi

    # 安全地输出到 GitHub Actions
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "data=$output_data" >> $GITHUB_OUTPUT
        echo "build_success=$build_success" >> $GITHUB_OUTPUT
        echo "download_url=$download_url" >> $GITHUB_OUTPUT
        echo "error_message=$error_message" >> $GITHUB_OUTPUT
    fi
    
    # 显示输出信息
    echo "Build output: $output_data"
    echo "Build success: $build_success"
    echo "Download URL: $download_url"
    if [ -n "$error_message" ]; then
        echo "Error message: $error_message"
    fi
}

# 主构建管理函数
build_manager() {
    local operation="$1"
    local input_data="$2"
    local pause_seconds="${3:-0}"

    # 添加详细调试信息
    debug "log" "🔍 build_manager 调用: operation=$operation, input_data_length=${#input_data}, pause_seconds=$pause_seconds"
    
    case "$operation" in
        "extract-data")
            debug "log" "📥 开始执行 extract-data 操作..."
            local result=$(_extract_build_data "$input_data")
            local exit_code=$?
            debug "log" "📤 extract-data 完成，退出码: $exit_code, 结果长度: ${#result}"
            echo "$result"
            return $exit_code
            ;;
        "process-data")
            debug "log" "⚙️  开始执行 process-data 操作..."
            local result=$(_execute_build_process "$input_data")
            local exit_code=$?
            debug "log" "⚙️  process-data 完成，退出码: $exit_code, 结果长度: ${#result}"
            echo "$result"
            return $exit_code
            ;;
        "output-data")
            debug "log" "📤 开始执行 output-data 操作..."
            local output_data="$2"
            debug "log" "📤 output-data 输入数据长度: ${#output_data}"
            _output_build_data "$output_data"
            local exit_code=$?
            debug "log" "📤 output-data 完成，退出码: $exit_code"
            return $exit_code
            ;;
        "pause")
            debug "log" "⏸️  开始执行 pause 操作..."
            _pause_for_test "$pause_seconds"
            local exit_code=$?
            debug "log" "⏸️  pause 完成，退出码: $exit_code"
            return $exit_code
            ;;
        *)
            debug "error" "❌ 未知操作: $operation"
            return 1
            ;;
    esac
}
