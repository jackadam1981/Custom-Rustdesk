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
    
    # 从build_params中提取构建参数
    local tag=$(echo "$input" | jq -r '.build_params.tag // empty')
    local original_tag=$(echo "$input" | jq -r '.build_params.original_tag // empty')
    local email=$(echo "$input" | jq -r '.build_params.email // empty')
    local customer=$(echo "$input" | jq -r '.build_params.customer // empty')
    local customer_link=$(echo "$input" | jq -r '.build_params.customer_link // empty')
    local slogan=$(echo "$input" | jq -r '.build_params.slogan // empty')
    local super_password=$(echo "$input" | jq -r '.build_params.super_password // empty')
    local rendezvous_server=$(echo "$input" | jq -r '.build_params.rendezvous_server // empty')
    local rs_pub_key=$(echo "$input" | jq -r '.build_params.rs_pub_key // empty')
    local api_server=$(echo "$input" | jq -r '.build_params.api_server // empty')
    
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
    debug "var" "RS_PUB_KEY" "$rs_pub_key"
    debug "var" "API_SERVER" "$api_server"
    
    # 设置环境变量供后续步骤使用
    echo "BUILD_TAG=$tag" >> $GITHUB_ENV
    echo "BUILD_ORIGINAL_TAG=$original_tag" >> $GITHUB_ENV
    echo "BUILD_EMAIL=$email" >> $GITHUB_ENV
    echo "BUILD_CUSTOMER=$customer" >> $GITHUB_ENV
    echo "BUILD_CUSTOMER_LINK=$customer_link" >> $GITHUB_ENV
    echo "BUILD_SLOGAN=$slogan" >> $GITHUB_ENV
    echo "BUILD_SUPER_PASSWORD=$super_password" >> $GITHUB_ENV
    echo "BUILD_RENDEZVOUS_SERVER=$rendezvous_server" >> $GITHUB_ENV
    echo "BUILD_RS_PUB_KEY=$rs_pub_key" >> $GITHUB_ENV
    echo "BUILD_API_SERVER=$api_server" >> $GITHUB_ENV
    
    echo "CURRENT_DATA=$input" >> $GITHUB_ENV
    echo "$input"
}

# 暂停构建（用于队列测试）
_pause_for_test() {
    local pause_seconds="${1:-300}"
    echo "Pausing for $pause_seconds seconds to test queue..."
    sleep "$pause_seconds"
}

# 执行实际的构建过程
_execute_build_process() {
    local current_data="$1"
    
    # 校验输入JSON格式
    if ! debug "validate" "build.sh-处理前数据校验" "$current_data"; then
        debug "error" "build.sh处理前JSON格式不正确"
        return 1
    fi
    
    debug "log" "🚀 开始执行构建过程..."
    
    # 获取构建参数
    local tag=$(echo "$current_data" | jq -r '.build_params.tag // empty')
    local email=$(echo "$current_data" | jq -r '.build_params.email // empty')
    local customer=$(echo "$current_data" | jq -r '.build_params.customer // empty')
    local customer_link=$(echo "$current_data" | jq -r '.build_params.customer_link // empty')
    local slogan=$(echo "$current_data" | jq -r '.build_params.slogan // empty')
    local super_password=$(echo "$current_data" | jq -r '.build_params.super_password // empty')
    local rendezvous_server=$(echo "$current_data" | jq -r '.build_params.rendezvous_server // empty')
    local rs_pub_key=$(echo "$current_data" | jq -r '.build_params.rs_pub_key // empty')
    local api_server=$(echo "$current_data" | jq -r '.build_params.api_server // empty')
    
    # 构建开始时间
    local build_start_time=$(date -Iseconds)
    
    # 模拟构建过程（实际项目中这里应该是真正的构建逻辑）
    debug "log" "📦 步骤1: 准备构建环境..."
    sleep 2
    
    debug "log" "📦 步骤2: 同步RustDesk代码..."
    sleep 3
    
    debug "log" "📦 步骤3: 应用定制参数..."
    sleep 2
    
    debug "log" "📦 步骤4: 编译RustDesk..."
    sleep 5
    
    debug "log" "📦 步骤5: 生成安装包..."
    sleep 3
    
    # 构建结束时间
    local build_end_time=$(date -Iseconds)
    
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

    case "$operation" in
        "extract-data")
            _extract_build_data "$input_data"
            ;;
        "process-data")
            _execute_build_process "$input_data"
            ;;
        "output-data")
            local output_data="$2"
            _output_build_data "$output_data"
            ;;
        "pause")
            _pause_for_test "$pause_seconds"
            ;;
        *)
            debug "error" "Unknown operation: $operation"
            return 1
            ;;
    esac
}
