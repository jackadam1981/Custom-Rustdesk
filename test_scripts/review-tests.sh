#!/bin/bash

# 本地审核逻辑回归测试，不触发真实 GitHub Actions。

if [ -z "$TEST_RUNNER_CALLED" ]; then
    standalone=true
    source test_scripts/framework.sh
else
    standalone=false
fi

source .github/workflows/scripts/review.sh

function _review_test_event() {
    local event_name="$1"
    local actor="$2"
    local owner="$3"

    jq -c -n \
        --arg actor "$actor" \
        --arg owner "$owner" \
        --arg event_name "$event_name" \
        '{
            action: "opened",
            sender: {login: $actor},
            repository: {owner: {login: $owner}},
            issue: {number: 42}
        }'
}

function _review_test_trigger_data() {
    local rendezvous_server="$1"
    local api_server="$2"

    jq -c -n \
        --arg rendezvous_server "$rendezvous_server" \
        --arg api_server "$api_server" \
        '{
            build_id: "review-test",
            trigger_type: "issue",
            issue_number: "42",
            build_params: {
                tag: "review-test",
                original_tag: "review-test",
                email: "review@example.com",
                customer: "review-customer",
                customer_link: "",
                super_password: "secret",
                slogan: "Review Test",
                rendezvous_server: $rendezvous_server,
                rs_pub_key: "",
                api_server: $api_server
            }
        }'
}

function test_review_private_issue_auto_approves() {
    local event_data trigger_data need_review

    export GITHUB_EVENT_NAME="issues"
    event_data=$(_review_test_event "issues" "external-user" "repo-owner")
    trigger_data=$(_review_test_trigger_data "192.168.2.22:21117" "http://10.0.0.8:21114")

    need_review=$(review_manager "need-review" "$event_data" "$trigger_data")

    if [ "$need_review" = "false" ]; then
        record_test_result "review_private_issue_auto_approves" "PASS" "私有地址 Issue 触发免审批"
        return 0
    fi

    record_test_result "review_private_issue_auto_approves" "FAIL" "私有地址不应需要审批，实际: $need_review"
    return 1
}

function test_review_public_ip_issue_requires_approval() {
    local event_data trigger_data need_review

    export GITHUB_EVENT_NAME="issues"
    event_data=$(_review_test_event "issues" "external-user" "repo-owner")
    trigger_data=$(_review_test_trigger_data "8.8.8.8:21117" "http://192.168.2.22:21114")

    need_review=$(review_manager "need-review" "$event_data" "$trigger_data")

    if [ "$need_review" = "true" ]; then
        record_test_result "review_public_ip_issue_requires_approval" "PASS" "公网 IP Issue 触发需要审批"
        return 0
    fi

    record_test_result "review_public_ip_issue_requires_approval" "FAIL" "公网 IP 应需要审批，实际: $need_review"
    return 1
}

function test_review_domain_issue_requires_approval() {
    local event_data trigger_data need_review

    export GITHUB_EVENT_NAME="issues"
    event_data=$(_review_test_event "issues" "external-user" "repo-owner")
    trigger_data=$(_review_test_trigger_data "rustdesk.example.com:21117" "http://192.168.2.22:21114")

    need_review=$(review_manager "need-review" "$event_data" "$trigger_data")

    if [ "$need_review" = "true" ]; then
        record_test_result "review_domain_issue_requires_approval" "PASS" "域名 Issue 触发需要审批"
        return 0
    fi

    record_test_result "review_domain_issue_requires_approval" "FAIL" "域名应需要审批，实际: $need_review"
    return 1
}

function test_review_workflow_dispatch_auto_approves() {
    local event_data trigger_data need_review

    export GITHUB_EVENT_NAME="workflow_dispatch"
    event_data=$(_review_test_event "workflow_dispatch" "repo-owner" "repo-owner")
    trigger_data=$(_review_test_trigger_data "rustdesk.example.com:21117" "https://api.example.com")

    need_review=$(review_manager "need-review" "$event_data" "$trigger_data")

    if [ "$need_review" = "false" ]; then
        record_test_result "review_workflow_dispatch_auto_approves" "PASS" "手动触发免评论审批"
        return 0
    fi

    record_test_result "review_workflow_dispatch_auto_approves" "FAIL" "手动触发应免评论审批，实际: $need_review"
    return 1
}

function test_review_timeout_is_48_hours() {
    if [ "${REVIEW_TIMEOUT_SECONDS:-}" = "172800" ]; then
        record_test_result "review_timeout_is_48_hours" "PASS" "审批超时为 48 小时"
        return 0
    fi

    record_test_result "review_timeout_is_48_hours" "FAIL" "审批超时应为 172800 秒，实际: ${REVIEW_TIMEOUT_SECONDS:-unset}"
    return 1
}

function run_review_tests() {
    log_info "开始运行审核逻辑测试..."
    local failed=0

    test_review_private_issue_auto_approves || failed=1
    test_review_public_ip_issue_requires_approval || failed=1
    test_review_domain_issue_requires_approval || failed=1
    test_review_workflow_dispatch_auto_approves || failed=1
    test_review_timeout_is_48_hours || failed=1

    log_info "审核逻辑测试完成"
    return $failed
}

if [ "$standalone" = true ]; then
    init_test_framework
    run_review_tests
    test_exit_code=$?
    show_test_results
    cleanup_test_framework
    exit $test_exit_code
fi
