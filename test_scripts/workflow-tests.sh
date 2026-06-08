#!/bin/bash

# 本地 workflow 结构回归测试，不触发真实 GitHub Actions。

if [ -z "$TEST_RUNNER_CALLED" ]; then
    standalone=true
    source test_scripts/framework.sh
else
    standalone=false
fi

WORKFLOW_FILE=".github/workflows/CustomBuildRustdesk.yml"
DELETE_RUNS_WORKFLOW_FILE=".github/workflows/99-delete_workflow_runs.yml"

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

function test_cleanup_queue_clears_orphan_build_lock() {
    if awk '
        /^_cleanup_queue\(\)/ { in_func=1 }
        in_func && /build_lock_holder_in_cleaned_queue/ { saw_queue_check=1 }
        in_func && /孤儿构建锁/ { saw_orphan_log=1 }
        in_func && /should_clear_build_lock=true/ && saw_queue_check { saw_clear=1 }
        in_func && /^}/ { exit((saw_queue_check && saw_orphan_log && saw_clear) ? 0 : 1) }
    ' .github/workflows/scripts/queue-manager.sh; then
        record_test_result "cleanup_queue_clears_orphan_build_lock" "PASS" "清理队列会移除不再属于队列成员的孤儿构建锁"
        return 0
    fi

    record_test_result "cleanup_queue_clears_orphan_build_lock" "FAIL" "cleanup_queue 应清理 queue=[] 但 build_locked_by 仍指向旧 run 的孤儿锁"
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

function test_queue_issue_lock_uses_ref_guard() {
    if grep -q 'REF_LOCK_PREFIX="queue-locks"' .github/workflows/scripts/queue-manager.sh &&
       grep -q '_acquire_ref_lock' .github/workflows/scripts/queue-manager.sh &&
       grep -q 'git/refs' .github/workflows/scripts/queue-manager.sh &&
       grep -q 'contents: write' .github/workflows/CustomBuildRustdesk.yml; then
        record_test_result "queue_issue_lock_uses_ref_guard" "PASS" "Issue body 更新由 Git ref 原子锁保护"
        return 0
    fi

    record_test_result "queue_issue_lock_uses_ref_guard" "FAIL" "Issue body 乐观锁不是原子 CAS，应使用 Git ref 原子锁保护"
    return 1
}

function test_manual_queue_limit_is_five() {
    if grep -q '^MANUAL_TRIGGER_LIMIT=5' .github/workflows/scripts/queue-manager.sh &&
       grep -q '手动触发：.*\$workflow_count/5' .github/workflows/scripts/issue-templates.sh; then
        record_test_result "manual_queue_limit_is_five" "PASS" "手动触发队列上限为 5"
        return 0
    fi

    record_test_result "manual_queue_limit_is_five" "FAIL" "手动触发队列上限应为 5，并与 Issue 面板显示一致"
    return 1
}

function test_source_patcher_is_invoked() {
    if grep -q 'source .github/workflows/scripts/source-patcher.sh' "$WORKFLOW_FILE" &&
       grep -q 'apply_custom_source_patches' "$WORKFLOW_FILE"; then
        record_test_result "source_patcher_is_invoked" "PASS" "构建流程会调用源码自定义 patch 脚本"
        return 0
    fi

    record_test_result "source_patcher_is_invoked" "FAIL" "Modify source code 阶段应调用 source-patcher.sh"
    return 1
}

function test_source_patcher_covers_server_key_and_brand() {
    local patcher=".github/workflows/scripts/source-patcher.sh"

    if [ -f "$patcher" ] &&
       grep -q 'custom-rendezvous-server' "$patcher" &&
       grep -q 'relay-server' "$patcher" &&
       grep -q 'api-server' "$patcher" &&
       grep -q 'BUILD_RS_PUB_KEY' "$patcher" &&
       grep -q 'flutter/android/app/src/main/res/values/strings.xml' "$patcher" &&
       grep -q 'flutter/ios/Runner/Info.plist' "$patcher" &&
       grep -q 'res/rustdesk.desktop' "$patcher" &&
       grep -q 'ProductName = "RustDesk"' "$patcher" &&
       grep -q 'libs/portable/Cargo.toml' "$patcher" &&
       grep -q 'libs/portable/src/main.rs' "$patcher" &&
       grep -q 'current_dir' "$patcher"; then
        record_test_result "source_patcher_covers_server_key_and_brand" "PASS" "源码 patch 覆盖服务器、密钥和主要品牌外观"
        return 0
    fi

    record_test_result "source_patcher_covers_server_key_and_brand" "FAIL" "源码 patch 应覆盖服务器、密钥和主要品牌外观"
    return 1
}

function test_source_patcher_applies_to_fixture_tree() {
    local patcher=".github/workflows/scripts/source-patcher.sh"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    mkdir -p "$tmp_dir/src" \
        "$tmp_dir/src/lang" \
        "$tmp_dir/flutter/android/app/src/main/res/values" \
        "$tmp_dir/flutter/ios/Runner" \
        "$tmp_dir/libs/portable/src" \
        "$tmp_dir/.github/workflows/scripts" \
        "$tmp_dir/res"

    cat > "$tmp_dir/src/common.rs" <<'EOF'
pub fn load_custom_client() {
    println!("load");
}

fn read_custom_client_advanced_settings() {}
EOF
    cat > "$tmp_dir/flutter/android/app/src/main/res/values/strings.xml" <<'EOF'
<resources>
    <string name="app_name">RustDesk</string>
</resources>
EOF
    cat > "$tmp_dir/flutter/ios/Runner/Info.plist" <<'EOF'
<plist><dict>
    <key>CFBundleDisplayName</key>
    <string>RustDesk</string>
    <key>CFBundleName</key>
    <string>RustDesk</string>
</dict></plist>
EOF
    cat > "$tmp_dir/res/rustdesk.desktop" <<'EOF'
Name=RustDesk
Comment=Remote desktop
Name=Open a New Window
EOF
    cat > "$tmp_dir/src/lang/cn.rs" <<'EOF'
pub static T: &[(&str, &str)] = &[
    ("powered_by_me", "由 RustDesk 提供支持"),
];
EOF
    cat > "$tmp_dir/src/lang/en.rs" <<'EOF'
pub static T: &[(&str, &str)] = &[
    ("powered_by_me", "Powered by RustDesk"),
];
EOF
    cat > "$tmp_dir/libs/portable/src/main.rs" <<'EOF'
use std::{path::PathBuf, process::Command};

fn execute(path: PathBuf, args: Vec<String>, _ui: bool) {
    let mut cmd = Command::new(path);
    cmd.args(args);
    let _child = cmd.spawn();
}
EOF
    cat > "$tmp_dir/Cargo.toml" <<'EOF'
[package]
description = "RustDesk Remote Desktop"

[package.metadata.winres]
ProductName = "RustDesk"
FileDescription = "RustDesk Remote Desktop"
EOF
    cat > "$tmp_dir/libs/portable/Cargo.toml" <<'EOF'
[package]
description = "RustDesk Remote Desktop"

[package.metadata.winres]
ProductName = "RustDesk"
FileDescription = "RustDesk Remote Desktop"
EOF
    cat > "$tmp_dir/.github/workflows/flutter-build.yml" <<'EOF'
env:
  UPLOAD_ARTIFACT: "${{ inputs.upload-artifact }}"
  SIGN_BASE_URL: "${{ secrets.SIGN_BASE_URL }}-2"

jobs:
  build-for-windows-flutter:
    steps:
      - name: Sign rustdesk files
        if: env.UPLOAD_ARTIFACT == 'true' && env.SIGN_BASE_URL != '-2'
        shell: bash
        run: |
          BASE_URL=${{ env.SIGN_BASE_URL }} SECRET_KEY=${{ secrets.SIGN_SECRET_KEY }} python3 res/job.py sign_files ./rustdesk/
      - name: Sign rustdesk self-extracted file
        if: env.UPLOAD_ARTIFACT == 'true' && env.SIGN_BASE_URL != '-2'
        shell: bash
        run: |
          BASE_URL=${{ env.SIGN_BASE_URL }} SECRET_KEY=${{ secrets.SIGN_SECRET_KEY }} python3 res/job.py sign_files ./SignOutput
  build-for-windows-sciter:
    steps:
      - name: Sign rustdesk files
        if: env.UPLOAD_ARTIFACT == 'true' && env.SIGN_BASE_URL != '-2'
        shell: bash
        run: |
          BASE_URL=${{ env.SIGN_BASE_URL }} SECRET_KEY=${{ secrets.SIGN_SECRET_KEY }} python3 res/job.py sign_files ./Release/
      - name: Sign rustdesk self-extracted file
        if: env.UPLOAD_ARTIFACT == 'true' && env.SIGN_BASE_URL != '-2'
        shell: bash
        run: |
          BASE_URL=${{ env.SIGN_BASE_URL }} SECRET_KEY=${{ secrets.SIGN_SECRET_KEY }} python3 res/job.py sign_files ./SignOutput/
EOF

    if (
        set -e
        export BUILD_CUSTOMER="FixtureDesk"
        export BUILD_CUSTOMER_LINK="https://fixture.example"
        export BUILD_SLOGAN="Fixture Slogan"
        export BUILD_RENDEZVOUS_SERVER="192.168.2.22:21117"
        export BUILD_RS_PUB_KEY="fixture-public-key"
        export BUILD_API_SERVER="http://192.168.2.22:21114"
        source "$patcher"
        cd "$tmp_dir"
        apply_custom_source_patches
        grep -q 'FixtureDesk' custom-build-config.json
        grep -q '"rendezvous_server": "192.168.2.22:21117"' custom-build-config.json
        grep -q '"custom_rendezvous_server": "192.168.2.22"' custom-build-config.json
        grep -q '"relay_server": "192.168.2.22"' custom-build-config.json
        grep -q 'custom-rendezvous-server' src/common.rs
        grep -q '("relay-server", CUSTOM_RELAY_SERVER)' src/common.rs
        ! grep -q 'HARD_SETTINGS' src/common.rs
        ! grep -q 'disable-settings' src/common.rs
        grep -q 'const CUSTOM_RENDEZVOUS_SERVER: &str = "192.168.2.22";' src/common.rs
        grep -q 'const CUSTOM_RELAY_SERVER: &str = "192.168.2.22";' src/common.rs
        ! grep -q '("custom-rendezvous-server", "192.168.2.22:21117")' src/common.rs
        grep -q 'fixture-public-key' src/common.rs
        grep -q '<string name="app_name">FixtureDesk</string>' flutter/android/app/src/main/res/values/strings.xml
        grep -q '<string>FixtureDesk</string>' flutter/ios/Runner/Info.plist
        grep -q 'Name=FixtureDesk' res/rustdesk.desktop
        grep -q 'Name=Open a New Window' res/rustdesk.desktop
        grep -q 'description = "FixtureDesk Remote Desktop"' Cargo.toml
        grep -q 'ProductName = "FixtureDesk"' Cargo.toml
        grep -q 'FileDescription = "FixtureDesk Remote Desktop"' Cargo.toml
        grep -q 'description = "FixtureDesk Remote Desktop"' libs/portable/Cargo.toml
        grep -q 'ProductName = "FixtureDesk"' libs/portable/Cargo.toml
        grep -q 'FileDescription = "FixtureDesk Remote Desktop"' libs/portable/Cargo.toml
        grep -q '由 FixtureDesk 提供支持' src/lang/cn.rs
        grep -q 'Powered by FixtureDesk' src/lang/en.rs
        grep -q 'let current_dir = path.parent().map(|dir| dir.to_path_buf());' libs/portable/src/main.rs
        grep -q 'cmd.current_dir' libs/portable/src/main.rs
        ! grep -q 'cmd.args(args);.*path.parent' libs/portable/src/main.rs
        grep -q 'ONECLOUD_WINDOWS_SIGNING_ENABLED' .github/workflows/flutter-build.yml
        grep -q "env.ONECLOUD_WINDOWS_SIGNING_ENABLED == 'true'" .github/workflows/flutter-build.yml
        grep -q 'ONECLOUD_WINDOWS_PFX_BASE64: ${{ secrets.ONECLOUD_WINDOWS_PFX_BASE64 }}' .github/workflows/flutter-build.yml
        grep -q 'ONECLOUD_WINDOWS_PFX_PASSWORD: ${{ secrets.ONECLOUD_WINDOWS_PFX_PASSWORD }}' .github/workflows/flutter-build.yml
        grep -q 'onecloud-windows-sign.ps1 -Path ./rustdesk' .github/workflows/flutter-build.yml
        grep -q 'onecloud-windows-sign.ps1 -Path ./Release' .github/workflows/flutter-build.yml
        grep -q 'onecloud-windows-sign.ps1 -Path ./SignOutput' .github/workflows/flutter-build.yml
        grep -q 'signtool.exe' .github/workflows/scripts/onecloud-windows-sign.ps1
        grep -q 'Code Signing' .github/workflows/scripts/onecloud-windows-sign.ps1
        grep -q '/sha1 $cert.Thumbprint' .github/workflows/scripts/onecloud-windows-sign.ps1
    ); then
        rm -rf "$tmp_dir"
        record_test_result "source_patcher_applies_to_fixture_tree" "PASS" "源码 patch 脚本可修改 fixture 源码树"
        return 0
    fi

    rm -rf "$tmp_dir"
    record_test_result "source_patcher_applies_to_fixture_tree" "FAIL" "源码 patch 脚本未正确修改 fixture 源码树"
    return 1
}

function test_source_patcher_can_skip_for_upstream_baseline() {
    local patcher=".github/workflows/scripts/source-patcher.sh"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    mkdir -p "$tmp_dir/src" "$tmp_dir/.github/workflows/scripts"
    cat > "$tmp_dir/src/common.rs" <<'EOF'
fn read_custom_client_advanced_settings() {}
pub fn load_custom_client() {
}
EOF

    if (
        set -e
        export BUILD_SOURCE_PATCH_MODE="upstream"
        source "$patcher"
        cd "$tmp_dir"
        apply_custom_source_patches
        grep -q '"skipped": true' custom-build-config.json
        ! grep -q 'CUSTOM_RUSTDESK_PATCH_START' src/common.rs
    ); then
        rm -rf "$tmp_dir"
        record_test_result "source_patcher_can_skip_for_upstream_baseline" "PASS" "源码 patch 支持 upstream 原版基线跳过"
        return 0
    fi

    rm -rf "$tmp_dir"
    record_test_result "source_patcher_can_skip_for_upstream_baseline" "FAIL" "upstream 原版基线模式不应修改源码"
    return 1
}

function test_api_server_is_optional_for_plain_hbbs_hbbr() {
    if grep -q "description: 'API服务地址（可选，没有 API 服务时留空）'" "$WORKFLOW_FILE" &&
       awk '
        /api_server:/ { in_api=1 }
        in_api && /required: false/ { found=1 }
        in_api && /^      [a-z_]+:/ && !/api_server:/ { in_api=0 }
        END { exit(found ? 0 : 1) }
       ' "$WORKFLOW_FILE" &&
       ! grep -q '\[ -z "$api_server" \].*api_server is required' .github/workflows/scripts/trigger.sh; then
        record_test_result "api_server_is_optional_for_plain_hbbs_hbbr" "PASS" "没有 API 服务的 hbbs/hbbr 构建允许 api_server 留空"
        return 0
    fi

    record_test_result "api_server_is_optional_for_plain_hbbs_hbbr" "FAIL" "api_server 应为可选，避免纯 hbbs/hbbr 服务器被迫写入不可达 API"
    return 1
}

function test_build_job_uses_trigger_data_for_parameters() {
    if grep -q 'name: trigger-data-${{ github.run_id }}' "$WORKFLOW_FILE" &&
       grep -q 'cat "$RUNNER_TEMP/trigger-data/trigger-data.json"' "$WORKFLOW_FILE" &&
       grep -q 'cat "$GITHUB_EVENT_PATH"' "$WORKFLOW_FILE"; then
        record_test_result "build_job_uses_trigger_data_for_parameters" "PASS" "build 阶段通过 artifact 使用标准化 trigger_data 参数"
        return 0
    fi

    record_test_result "build_job_uses_trigger_data_for_parameters" "FAIL" "build 阶段应使用标准化 trigger_data，避免 Issue 触发丢参数"
    return 1
}

function test_build_job_does_not_export_trigger_data_env() {
    if ! grep -Fq 'TRIGGER_DATA: ${{ needs.trigger.outputs.trigger_data }}' "$WORKFLOW_FILE" &&
       ! grep -Fq '${{ needs.trigger.outputs.trigger_data }}' "$WORKFLOW_FILE" &&
       ! grep -q 'toJSON(github.event)' "$WORKFLOW_FILE" &&
       ! grep -q 'DEBUG: trigger_data' "$WORKFLOW_FILE" &&
       ! grep -q 'DEBUG_ENABLED: true' "$WORKFLOW_FILE" &&
       ! grep -q 'TRIGGER_DATA 前100字符' "$WORKFLOW_FILE"; then
        record_test_result "build_job_does_not_export_trigger_data_env" "PASS" "workflow 不再把完整事件或 trigger_data 注入脚本文本/日志预览"
        return 0
    fi

    record_test_result "build_job_does_not_export_trigger_data_env" "FAIL" "完整事件和 trigger_data 不应通过表达式注入脚本文本或打印预览"
    return 1
}

function test_build_uploads_patched_source_artifact() {
    if grep -q 'name: patched-source-${{ github.run_id }}' "$WORKFLOW_FILE" &&
       grep -q 'path: rustdesk-source' "$WORKFLOW_FILE" &&
       grep -q 'source_branch: ${{ steps.commit-repo.outputs.branch_name }}' "$WORKFLOW_FILE" &&
       grep -q 'custom-rustdesk-upstream-build.yml' "$WORKFLOW_FILE" &&
       grep -q 'uses: ./.github/workflows/flutter-build.yml' .github/workflows/custom-rustdesk-upstream-build.yml &&
       grep -Fq "github.event_name == 'workflow_dispatch' && inputs.upload-artifact || true" .github/workflows/custom-rustdesk-upstream-build.yml &&
       grep -Fq "github.event_name == 'workflow_dispatch' && inputs.upload-tag || 'custom'" .github/workflows/custom-rustdesk-upstream-build.yml &&
       grep -Fq "upload-artifact: __CUSTOM_UPLOAD_ARTIFACT_EXPR__" "$WORKFLOW_FILE" &&
       grep -Fq "upload_artifact_expr=" "$WORKFLOW_FILE" &&
       grep -Fq 'CUSTOM_UPLOAD_ARTIFACT_EXPR="$upload_artifact_expr"' "$WORKFLOW_FILE" &&
       grep -Fq 'perl -0pi -e' "$WORKFLOW_FILE" &&
       grep -q 'RustDesk Upstream Flutter Build Placeholder' .github/workflows/flutter-build.yml &&
       grep -q 'steps.record-artifact.outputs.download_url' "$WORKFLOW_FILE" &&
       grep -q 'actions: write' "$WORKFLOW_FILE" &&
       grep -q 'Delete trigger data artifact' "$WORKFLOW_FILE" &&
       grep -q 'Delete custom source branch' "$WORKFLOW_FILE" &&
       grep -q 'trigger-data-${{ github.run_id }}' "$WORKFLOW_FILE" &&
       ! grep -q 'https://api.github.com/repos/$RUSTDESK_REPO/dispatches' "$WORKFLOW_FILE"; then
        record_test_result "build_uploads_patched_source_artifact" "PASS" "build 阶段上传已定制源码 artifact，不再触发无权限的官方仓库 dispatch"
        return 0
    fi

    record_test_result "build_uploads_patched_source_artifact" "FAIL" "build 阶段应上传已定制源码 artifact，并避免触发 rustdesk/rustdesk dispatch"
    return 1
}

function test_workflow_builds_real_client_artifact() {
    if grep -q '^  upstream-build:' "$WORKFLOW_FILE" &&
       grep -q 'push:' .github/workflows/custom-rustdesk-upstream-build.yml &&
       grep -Fq '"custom-build-*"' .github/workflows/custom-rustdesk-upstream-build.yml &&
       grep -q -- '--workflow custom-rustdesk-upstream-build.yml' "$WORKFLOW_FILE" &&
       grep -q -- '--branch "$SOURCE_BRANCH"' "$WORKFLOW_FILE" &&
       ! grep -q 'gh workflow run custom-rustdesk-upstream-build.yml' "$WORKFLOW_FILE" &&
       grep -q 'gh run watch "$upstream_run_id"' "$WORKFLOW_FILE" &&
       grep -Fq 'upstream_run_url=https://github.com/${{ github.repository }}/actions/runs/$upstream_run_id' "$WORKFLOW_FILE" &&
       grep -q '^  compile-client:' "$WORKFLOW_FILE" &&
       grep -q "if: false && needs.build.result == 'success'" "$WORKFLOW_FILE" &&
       grep -q 'finish:' "$WORKFLOW_FILE" &&
       grep -Fq 'needs: [trigger, review, join-queue, wait-build-lock, build, upstream-build]' "$WORKFLOW_FILE"; then
        record_test_result "workflow_builds_real_client_artifact" "PASS" "workflow 通过 custom source 分支触发 RustDesk 原版 workflow 编译客户端产物"
        return 0
    fi

    record_test_result "workflow_builds_real_client_artifact" "FAIL" "workflow 应通过 custom source 分支触发 RustDesk 原版 workflow，而不是继续自编 compile-client"
    return 1
}

function test_linux_build_uses_official_sciter_flow() {
    if grep -q 'python3 ./res/inline-sciter.py' "$WORKFLOW_FILE" &&
       grep -q 'export USE_AOM_391=1' "$WORKFLOW_FILE" &&
       grep -q 'cargo build --locked --features inline,hwcodec,unix-file-copy-paste --release --bins --target "${{ matrix.client.target }}" --jobs 1' "$WORKFLOW_FILE" &&
       grep -q 'Release/libsciter-gtk.so' "$WORKFLOW_FILE" &&
       grep -q 'chmod 755 res/DEBIAN/preinst res/DEBIAN/postinst res/DEBIAN/prerm res/DEBIAN/postrm' "$WORKFLOW_FILE" &&
       grep -q 'python3 ./build.py --package ./Release' "$WORKFLOW_FILE" &&
       grep -q 'libarchive-tools' "$WORKFLOW_FILE" &&
       grep -q 'libfuse2' "$WORKFLOW_FILE" &&
       grep -q 'python3-pip' "$WORKFLOW_FILE" &&
       grep -q 'Build Linux AppImage' "$WORKFLOW_FILE" &&
       grep -q "find . .. -maxdepth 1" "$WORKFLOW_FILE" &&
       grep -q "find . rustdesk-source -maxdepth 1" "$WORKFLOW_FILE" &&
       grep -q "rustdesk.deb" "$WORKFLOW_FILE" &&
       grep -q 'appimage/rustdesk.deb' "$WORKFLOW_FILE" &&
       grep -Fq "s#tar -xvf ./data.tar.xz#bsdtar -xf ./data.tar.*#" "$WORKFLOW_FILE" &&
       grep -q 'git+https://github.com/rustdesk-org/appimage-builder.git' "$WORKFLOW_FILE" &&
       grep -q 'appimage-builder --skip-tests --recipe ./AppImageBuilder-x86_64.yml' "$WORKFLOW_FILE" &&
       grep -Fq "find rustdesk-source/appimage -maxdepth 1 -name 'rustdesk-*.AppImage'" "$WORKFLOW_FILE" &&
       grep -q 'DEB_ARCH=amd64' "$WORKFLOW_FILE"; then
        record_test_result "linux_build_uses_official_sciter_flow" "PASS" "Linux 使用官方 Sciter inline/deb 打包路径"
        return 0
    fi

    record_test_result "linux_build_uses_official_sciter_flow" "FAIL" "Linux 应使用官方 Sciter inline、libsciter-gtk 和 python3 build.py --package 流程"
    return 1
}

function test_windows_build_uses_official_sciter_inline_resources() {
    if grep -q "runner.os == 'Windows'" "$WORKFLOW_FILE" &&
       grep -q 'VCPKG_DEFAULT_HOST_TRIPLET: ${{ matrix.client.vcpkg-triplet }}' "$WORKFLOW_FILE" &&
       grep -q 'python3 res/inline-sciter.py' "$WORKFLOW_FILE" &&
       grep -q 'cargo build --locked --features inline,vram,hwcodec --release --bins --target "${{ matrix.client.target }}"' "$WORKFLOW_FILE" &&
       grep -q 'mkdir -p Release' "$WORKFLOW_FILE" &&
       grep -q 'sciter.dll' "$WORKFLOW_FILE" &&
       grep -q 'raw.githubusercontent.com/c-smile/sciter-sdk/master/bin.win/x64/sciter.dll' "$WORKFLOW_FILE" &&
       ! grep -q 'cp -R rustdesk-source/src/ui rustdesk-source/windows-dist/src/' "$WORKFLOW_FILE"; then
        record_test_result "windows_build_uses_official_sciter_inline_resources" "PASS" "Windows 使用官方 inline Sciter/vcpkg 构建方式，避免运行时 src/ui 白屏"
        return 0
    fi

    record_test_result "windows_build_uses_official_sciter_inline_resources" "FAIL" "Windows 应参考官方 Actions 使用 inline Sciter 和 VCPKG_DEFAULT_HOST_TRIPLET"
    return 1
}

function test_windows_release_outputs_single_exe_and_msi() {
    if grep -q 'Build Windows single-file executable' "$WORKFLOW_FILE" &&
       grep -q 'libs/portable' "$WORKFLOW_FILE" &&
       grep -q 'python3 ./generate.py -f ../../Release/ -o . -e ../../Release/rustdesk.exe' "$WORKFLOW_FILE" &&
       grep -q 'rustdesk-portable-packer.exe' "$WORKFLOW_FILE" &&
       grep -q 'find ../../target -name rustdesk-portable-packer.exe' "$WORKFLOW_FILE" &&
       grep -q 'Add MSBuild to PATH' "$WORKFLOW_FILE" &&
       grep -q 'Build Windows MSI' "$WORKFLOW_FILE" &&
       grep -q 'ConvertFrom-Json' "$WORKFLOW_FILE" &&
       grep -q 'Copy-Item -Path $sourceExe -Destination $msiExe -Force' "$WORKFLOW_FILE" &&
       grep -q 'Remove-Item -Path $sourceExe -Force' "$WORKFLOW_FILE" &&
       grep -q 'python preprocess.py --arp -d ../../Release --app-name "$appName"' "$WORKFLOW_FILE" &&
       grep -q 'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }' "$WORKFLOW_FILE" &&
       grep -q 'msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10' "$WORKFLOW_FILE" &&
       grep -q 'Package.msi' "$WORKFLOW_FILE" &&
       grep -q 'rustdesk-client-${{ matrix.client.name }}-${{ github.run_id }}.exe' "$WORKFLOW_FILE" &&
       grep -q 'rustdesk-client-${{ matrix.client.name }}-${{ github.run_id }}.msi' "$WORKFLOW_FILE"; then
        record_test_result "windows_release_outputs_single_exe_and_msi" "PASS" "Windows 发行产物包含单文件 exe 和 MSI"
        return 0
    fi

    record_test_result "windows_release_outputs_single_exe_and_msi" "FAIL" "Windows 应使用 RustDesk portable/MSI 链路生成单文件 exe 和 MSI"
    return 1
}

function test_workflow_builds_android_apk_artifact() {
    if grep -q '^  compile-android:' "$WORKFLOW_FILE" &&
       grep -q "if: false && needs.build.result == 'success'" "$WORKFLOW_FILE" &&
       grep -q '^  upstream-build:' "$WORKFLOW_FILE" &&
       grep -q 'custom-rustdesk-upstream-build.yml' "$WORKFLOW_FILE" &&
       grep -q 'target: aarch64-linux-android' "$WORKFLOW_FILE" &&
       grep -q 'abi: arm64-v8a' "$WORKFLOW_FILE" &&
       grep -q 'flutter-target-platform: android-arm64' "$WORKFLOW_FILE" &&
       grep -q 'uses: subosito/flutter-action@v2' "$WORKFLOW_FILE" &&
       grep -q 'uses: nttld/setup-ndk@v1' "$WORKFLOW_FILE" &&
       grep -q 'chmod +x ./flutter/build_android_deps.sh ./flutter/ndk_arm64.sh' "$WORKFLOW_FILE" &&
       grep -q 'cargo install flutter_rust_bridge_codegen --version ${{ env.FLUTTER_RUST_BRIDGE_VERSION }} --features "uuid" --locked' "$WORKFLOW_FILE" &&
       grep -q 'flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart --c-output ./flutter/macos/Runner/bridge_generated.h' "$WORKFLOW_FILE" &&
       grep -q 'cp ./flutter/macos/Runner/bridge_generated.h ./flutter/ios/Runner/bridge_generated.h' "$WORKFLOW_FILE" &&
       ! grep -q 'extended_text: 14.0.0/extended_text: 13.0.0' "$WORKFLOW_FILE" &&
       grep -q 'cargo install cargo-ndk --version ${{ env.CARGO_NDK_VERSION }} --locked' "$WORKFLOW_FILE" &&
       grep -q './flutter/ndk_arm64.sh' "$WORKFLOW_FILE" &&
       grep -q 'liblibrustdesk.so' "$WORKFLOW_FILE" &&
       grep -q 'flutter build apk --release --target-platform "${{ matrix.android.flutter-target-platform }}" --split-per-abi' "$WORKFLOW_FILE" &&
       grep -q 'name: rustdesk-client-android-${{ matrix.android.name }}-${{ github.run_id }}' "$WORKFLOW_FILE" &&
       grep -Fq 'needs: [trigger, review, join-queue, wait-build-lock, build, upstream-build]' "$WORKFLOW_FILE"; then
        record_test_result "workflow_builds_android_apk_artifact" "PASS" "Android 构建改由定制源码分支上的 RustDesk 原版 workflow 承担，旧自编 job 已关闭"
        return 0
    fi

    record_test_result "workflow_builds_android_apk_artifact" "FAIL" "Android 构建应由 upstream-build 承担，finish 应等待 upstream-build"
    return 1
}

function test_delete_runs_counter_not_in_pipeline_subshell() {
    if awk '
        /DELETED=0/ { in_delete=1 }
        in_delete && /\|[[:space:]]*while[[:space:]]+read/ { bad=1 }
        in_delete && /while[[:space:]]+read/ { saw_loop=1 }
        in_delete && /done[[:space:]]*< <\(/ { saw_process_substitution=1 }
        in_delete && /删除完成：成功/ { saw_summary=1 }
        END { exit((!bad && saw_loop && saw_process_substitution && saw_summary) ? 0 : 1) }
    ' "$DELETE_RUNS_WORKFLOW_FILE"; then
        record_test_result "delete_runs_counter_not_in_pipeline_subshell" "PASS" "删除 runs 的成功/失败计数不会丢在管道子 shell 中"
        return 0
    fi

    record_test_result "delete_runs_counter_not_in_pipeline_subshell" "FAIL" "删除 runs 的 while 循环不能挂在管道后，否则 DELETED/FAILED 计数不会回写"
    return 1
}

function run_workflow_tests() {
    log_info "开始运行 workflow 结构测试..."
    local failed=0

    test_build_branch_uses_orphan_snapshot || failed=1
    test_release_all_locks_leaves_queue || failed=1
    test_release_all_locks_skips_unowned_build_lock || failed=1
    test_cleanup_queue_clears_orphan_build_lock || failed=1
    test_finish_queue_cleanup_is_best_effort || failed=1
    test_actions_ci_does_not_enable_test_mode || failed=1
    test_build_lock_failure_exits_job || failed=1
    test_queue_issue_lock_uses_ref_guard || failed=1
    test_manual_queue_limit_is_five || failed=1
    test_source_patcher_is_invoked || failed=1
    test_source_patcher_covers_server_key_and_brand || failed=1
    test_source_patcher_applies_to_fixture_tree || failed=1
    test_source_patcher_can_skip_for_upstream_baseline || failed=1
    test_api_server_is_optional_for_plain_hbbs_hbbr || failed=1
    test_build_job_uses_trigger_data_for_parameters || failed=1
    test_build_job_does_not_export_trigger_data_env || failed=1
    test_build_uploads_patched_source_artifact || failed=1
    test_workflow_builds_real_client_artifact || failed=1
    test_linux_build_uses_official_sciter_flow || failed=1
    test_windows_build_uses_official_sciter_inline_resources || failed=1
    test_windows_release_outputs_single_exe_and_msi || failed=1
    test_workflow_builds_android_apk_artifact || failed=1
    test_delete_runs_counter_not_in_pipeline_subshell || failed=1

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
