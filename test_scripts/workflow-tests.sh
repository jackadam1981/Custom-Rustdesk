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

function test_release_all_locks_leaves_queue() {
    if awk '
        /^release_all_locks\(\)/ { in_func=1 }
        in_func && /_leave_queue/ { found=1 }
        in_func && /^}/ { exit(found ? 0 : 1) }
    ' .github/workflows/scripts/queue-manager.sh; then
        record_test_result "release_all_locks_leaves_queue" "PASS" "完成阶段释放锁时会移除当前队列项"
        return 0
    fi

    record_test_result "release_all_locks_leaves_queue" "FAIL" "release_all_locks 应调用 _leave_queue，避免成功构建残留队列项"
    return 1
}

function test_release_all_locks_skips_unowned_build_lock() {
    if awk '
        /^release_all_locks\(\)/ { in_func=1 }
        in_func && /current_build_holder/ { saw_holder=1 }
        in_func && /Skipping build lock release/ { saw_skip=1 }
        in_func && /^}/ { exit((saw_holder && saw_skip) ? 0 : 1) }
    ' .github/workflows/scripts/queue-manager.sh; then
        record_test_result "release_all_locks_skips_unowned_build_lock" "PASS" "未持有构建锁的 run 不会释放别人的锁"
        return 0
    fi

    record_test_result "release_all_locks_skips_unowned_build_lock" "FAIL" "release_all_locks 应在当前 run 未持有构建锁时跳过释放"
    return 1
}

function test_finish_queue_cleanup_is_best_effort() {
    if grep -q 'cleanup_queue || echo "⚠️ Queue cleanup skipped or failed"' .github/workflows/CustomBuildRustdesk.yml; then
        record_test_result "finish_queue_cleanup_is_best_effort" "PASS" "finish 阶段的队列清理是 best-effort"
        return 0
    fi

    record_test_result "finish_queue_cleanup_is_best_effort" "FAIL" "finish 阶段 cleanup_queue 不应因抢不到锁导致整个 finish 失败"
    return 1
}

function test_actions_ci_does_not_enable_test_mode() {
    if grep -q 'CI:-' .github/workflows/scripts/queue-manager.sh; then
        record_test_result "actions_ci_does_not_enable_test_mode" "FAIL" "GitHub Actions 默认 CI=true，不能用 CI 判断队列测试模式"
        return 1
    fi

    record_test_result "actions_ci_does_not_enable_test_mode" "PASS" "队列测试模式不会被 GitHub Actions 默认 CI=true 误触发"
    return 0
}

function test_build_lock_failure_exits_job() {
    if awk '
        /Failed to acquire build lock/ { saw_failure=1 }
        saw_failure && /exit 1/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' .github/workflows/CustomBuildRustdesk.yml; then
        record_test_result "build_lock_failure_exits_job" "PASS" "构建锁获取失败会让 wait-build-lock job 失败"
        return 0
    fi

    record_test_result "build_lock_failure_exits_job" "FAIL" "构建锁获取失败不能静默成功并跳过 build"
    return 1
}

function run_workflow_tests() {
    log_info "开始运行 workflow 结构测试..."
    local failed=0

    test_build_branch_uses_orphan_snapshot || failed=1
    test_release_all_locks_leaves_queue || failed=1
    test_release_all_locks_skips_unowned_build_lock || failed=1
    test_finish_queue_cleanup_is_best_effort || failed=1
    test_actions_ci_does_not_enable_test_mode || failed=1
    test_build_lock_failure_exits_job || failed=1

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
