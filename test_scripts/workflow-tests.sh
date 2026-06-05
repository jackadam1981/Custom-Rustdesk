#!/bin/bash

# 本地 workflow 结构回归测试，不触发真实 GitHub Actions。

if [ -z "$TEST_RUNNER_CALLED" ]; then
    standalone=true
    source test_scripts/framework.sh
else
    standalone=false
fi

WORKFLOW_FILE=".github/workflows/CustomBuildRustdesk.yml"

function test_build_branch_uses_orphan_snapshot() {
    if grep -q 'git checkout --orphan custom-build-${{ github.run_id }}' "$WORKFLOW_FILE" &&
       grep -q 'git add -A' "$WORKFLOW_FILE" &&
       ! grep -q 'git checkout -b custom-build-${{ github.run_id }}' "$WORKFLOW_FILE"; then
        record_test_result "build_branch_uses_orphan_snapshot" "PASS" "构建分支使用无父提交快照，避免推送 RustDesk 上游历史"
        return 0
    fi

    record_test_result "build_branch_uses_orphan_snapshot" "FAIL" "构建分支应使用 orphan snapshot，而不是从 RustDesk 历史创建普通分支"
    return 1
}

function run_workflow_tests() {
    log_info "开始运行 workflow 结构测试..."
    local failed=0

    test_build_branch_uses_orphan_snapshot || failed=1

    log_info "workflow 结构测试完成"
    return $failed
}

if [ "$standalone" = true ]; then
    init_test_framework
    run_workflow_tests
    test_exit_code=$?
    show_test_results
    cleanup_test_framework
    exit $test_exit_code
fi
