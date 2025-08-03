#!/bin/bash
# 测试 trigger.sh 脚本的功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 测试函数
test_function() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${BLUE}Running test: $test_name${NC}"
    
    if eval "$test_command" > /tmp/test_output.log 2>&1; then
        actual_exit_code=$?
    else
        actual_exit_code=$?
    fi
    
    if [ $actual_exit_code -eq $expected_exit_code ]; then
        echo -e "${GREEN}✓ PASS: $test_name${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: $test_name (expected: $expected_exit_code, got: $actual_exit_code)${NC}"
        echo -e "${YELLOW}Output:${NC}"
        cat /tmp/test_output.log
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    echo
}

# 设置测试环境
setup_test_environment() {
    echo -e "${BLUE}Setting up test environment...${NC}"
    
    # 创建测试目录
    mkdir -p .github/workflows/scripts
    
    # 设置测试环境变量
    export GITHUB_TOKEN="test_token"
    export GITHUB_REPOSITORY="test/repo"
    export GITHUB_RUN_ID="123456789"
    export GITHUB_OUTPUT="/tmp/github_output"
    
    # 设置默认值
    export DEFAULT_TAG="test-tag"
    export DEFAULT_EMAIL="test@example.com"
    export DEFAULT_CUSTOMER="test-customer"
    export DEFAULT_CUSTOMER_LINK="https://example.com"
    export DEFAULT_SUPER_PASSWORD="test-password"
    export DEFAULT_SLOGAN="Test Slogan"
    export DEFAULT_RENDEZVOUS_SERVER="192.168.1.100"
    export DEFAULT_RS_PUB_KEY="test-key"
    export DEFAULT_API_SERVER="http://192.168.1.100:21114"
    
    # 清空输出文件
    > "$GITHUB_OUTPUT"
    
    echo -e "${GREEN}Test environment setup complete${NC}"
    echo
}

# 测试 workflow_dispatch 事件参数提取
test_workflow_dispatch_extraction() {
    local test_event='{
        "inputs": {
            "tag": "test-tag",
            "email": "test@example.com",
            "customer": "test-customer",
            "customer_link": "https://example.com",
            "super_password": "test-password",
            "slogan": "Test Slogan",
            "rendezvous_server": "192.168.1.100",
            "rs_pub_key": "test-key",
            "api_server": "http://192.168.1.100:21114"
        }
    }'
    
    # 测试参数提取
    local result=$(source .github/workflows/scripts/trigger.sh && trigger_manager "extract-workflow-dispatch" "$test_event")
    
    # 验证结果包含所有必需参数
    if echo "$result" | grep -q 'TAG="test-tag"' && \
       echo "$result" | grep -q 'EMAIL="test@example.com"' && \
       echo "$result" | grep -q 'CUSTOMER="test-customer"'; then
        echo -e "${GREEN}✓ PASS: workflow_dispatch parameter extraction${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: workflow_dispatch parameter extraction${NC}"
        echo "Result: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试 issue 事件参数提取
test_issue_extraction() {
    local test_event='{
        "issue": {
            "number": 123,
            "body": "{\"tag\":\"test-tag\",\"email\":\"test@example.com\",\"customer\":\"test-customer\"}"
        }
    }'
    
    # 测试参数提取
    local result=$(source .github/workflows/scripts/trigger.sh && trigger_manager "extract-issue" "$test_event")
    
    # 验证结果包含所有必需参数
    if echo "$result" | grep -q 'BUILD_ID="123"' && \
       echo "$result" | grep -q 'TAG="test-tag"' && \
       echo "$result" | grep -q 'EMAIL="test@example.com"'; then
        echo -e "${GREEN}✓ PASS: issue parameter extraction${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: issue parameter extraction${NC}"
        echo "Result: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试参数验证
test_parameter_validation() {
    local valid_data='{
        "tag": "test-tag",
        "email": "test@example.com",
        "customer": "test-customer",
        "rendezvous_server": "192.168.1.100",
        "api_server": "http://192.168.1.100:21114",
        "super_password": "test-password"
    }'
    
    local invalid_data='{
        "tag": "",
        "email": "invalid-email",
        "customer": "",
        "rendezvous_server": "",
        "api_server": "",
        "super_password": ""
    }'
    
    # 测试有效参数
    if source .github/workflows/scripts/trigger.sh && trigger_manager "validate-parameters" "$valid_data"; then
        echo -e "${GREEN}✓ PASS: valid parameter validation${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: valid parameter validation${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # 测试无效参数
    if ! source .github/workflows/scripts/trigger.sh && trigger_manager "validate-parameters" "$invalid_data"; then
        echo -e "${GREEN}✓ PASS: invalid parameter validation (correctly rejected)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: invalid parameter validation (should have been rejected)${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试默认值应用
test_default_values() {
    local test_event='{
        "inputs": {
            "tag": "",
            "email": "",
            "customer": "test-customer"
        }
    }'
    
    # 测试默认值应用
    local result=$(source .github/workflows/scripts/trigger.sh && trigger_manager "apply-defaults" "$test_event")
    
    # 验证默认值被正确应用
    if echo "$result" | grep -q "TAG=\"$DEFAULT_TAG\"" && \
       echo "$result" | grep -q "EMAIL=\"$DEFAULT_EMAIL\"" && \
       echo "$result" | grep -q 'CUSTOMER="test-customer"'; then
        echo -e "${GREEN}✓ PASS: default value application${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: default value application${NC}"
        echo "Result: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试 tag 时间戳处理
test_tag_timestamp() {
    local test_event='{
        "inputs": {
            "tag": "test-tag"
        }
    }'
    
    # 测试时间戳处理
    local result=$(source .github/workflows/scripts/trigger.sh && trigger_manager "process-tag" "$test_event")
    
    # 验证时间戳被正确添加
    if echo "$result" | grep -q '^test-tag-[0-9]\{8\}-[0-9]\{6\}$'; then
        echo -e "${GREEN}✓ PASS: tag timestamp processing${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: tag timestamp processing${NC}"
        echo "Result: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试 JSON 数据生成
test_json_generation() {
    local test_event='{
        "inputs": {
            "tag": "test-tag",
            "email": "test@example.com",
            "customer": "test-customer"
        }
    }'
    
    local final_tag="test-tag-20231201-120000"
    
    # 测试 JSON 生成
    local result=$(source .github/workflows/scripts/trigger.sh && trigger_manager "generate-data" "$test_event" "$final_tag")
    
    # 验证 JSON 格式正确
    if echo "$result" | jq -e '.' > /dev/null 2>&1 && \
       echo "$result" | jq -r '.tag' | grep -q "$final_tag" && \
       echo "$result" | jq -r '.email' | grep -q "test@example.com"; then
        echo -e "${GREEN}✓ PASS: JSON data generation${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: JSON data generation${NC}"
        echo "Result: $result"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试 GitHub Actions 输出
test_github_output() {
    local test_data='{
        "build_id": "123456789",
        "tag": "test-tag-20231201-120000",
        "email": "test@example.com",
        "customer": "test-customer"
    }'
    
    # 清空输出文件
    > "$GITHUB_OUTPUT"
    
    # 测试输出
    source .github/workflows/scripts/trigger.sh && trigger_manager "output-to-github" "$test_data"
    
    # 验证输出文件内容
    if grep -q 'trigger_data=' "$GITHUB_OUTPUT" && \
       grep -q 'build_id=123456789' "$GITHUB_OUTPUT"; then
        echo -e "${GREEN}✓ PASS: GitHub Actions output${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: GitHub Actions output${NC}"
        echo "Output file content:"
        cat "$GITHUB_OUTPUT"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试错误处理
test_error_handling() {
    # 测试无效 JSON
    local invalid_json='{invalid json}'
    
    if ! source .github/workflows/scripts/trigger.sh && trigger_manager "extract-workflow-dispatch" "$invalid_json" 2>/dev/null; then
        echo -e "${GREEN}✓ PASS: invalid JSON error handling${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: invalid JSON error handling${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # 测试缺少必需字段
    local missing_fields='{"inputs": {}}'
    
    if source .github/workflows/scripts/trigger.sh && trigger_manager "extract-workflow-dispatch" "$missing_fields" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS: missing fields handling (graceful degradation)${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗ FAIL: missing fields handling${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 主测试函数
main() {
    echo -e "${BLUE}Starting trigger.sh tests...${NC}"
    echo
    
    # 设置测试环境
    setup_test_environment
    
    # 运行所有测试
    test_workflow_dispatch_extraction
    test_issue_extraction
    test_parameter_validation
    test_default_values
    test_tag_timestamp
    test_json_generation
    test_github_output
    test_error_handling
    
    # 输出测试结果
    echo -e "${BLUE}Test Results:${NC}"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo -e "${BLUE}Total: $TOTAL_TESTS${NC}"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}All tests passed! ✓${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed! ✗${NC}"
        exit 1
    fi
}

# 运行主函数
main "$@" 