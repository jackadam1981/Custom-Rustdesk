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
       grep -q '_custom_patch_brand_files' "$patcher" &&
       grep -q '_custom_patch_portable_working_dir' "$patcher" &&
       grep -q 'libs/portable/src/main.rs' "$patcher" &&
       grep -q '_custom_patch_msi_preprocess_app_name' "$patcher" &&
       grep -q 'UI-only; MSI keeps RustDesk' "$patcher" &&
       grep -q 'current_dir' "$patcher"; then
        record_test_result "source_patcher_covers_server_key_and_brand" "PASS" "源码 patch 覆盖服务器、密钥和主要品牌外观"
        return 0
    fi

    record_test_result "source_patcher_covers_server_key_and_brand" "FAIL" "源码 patch 应覆盖服务器、密钥和主要品牌外观"
    return 1
}

function test_source_patch_debug_switch_is_wired() {
    local patcher=".github/workflows/scripts/source-patcher.sh"
    local trigger=".github/workflows/scripts/trigger.sh"

    if grep -q 'source_patch_debug:' "$WORKFLOW_FILE" &&
       grep -q 'BUILD_SOURCE_PATCH_DEBUG' "$WORKFLOW_FILE" &&
       grep -q 'source_patch_debug' "$trigger" &&
       grep -q 'SOURCE_PATCH_DEBUG' "$trigger" &&
       grep -q 'export BUILD_SOURCE_PATCH_DEBUG' "$WORKFLOW_FILE" &&
       grep -q 'BUILD_SOURCE_PATCH_DEBUG' "$patcher" &&
       grep -q 'detailed before/after source diagnostics enabled' "$patcher" &&
       grep -q 'detailed before/after source diagnostics disabled' "$patcher" &&
       grep -q '_custom_patch_debug_enabled' "$patcher"; then
        record_test_result "source_patch_debug_switch_is_wired" "PASS" "source_patch_debug reaches source-patcher diagnostics"
        return 0
    fi

    record_test_result "source_patch_debug_switch_is_wired" "FAIL" "source_patch_debug should flow from trigger params to source-patcher.sh"
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
        "$tmp_dir/libs/hbb_common/src" \
        "$tmp_dir/libs/portable/src" \
        "$tmp_dir/.github/workflows/scripts" \
        "$tmp_dir/res"

    cat > "$tmp_dir/src/common.rs" <<'EOF'
pub fn load_custom_client() {
    println!("load");
}

pub fn get_custom_rendezvous_server(custom: String) -> String {
    if !custom.is_empty() {
        return custom;
    }
    "".to_owned()
}

pub fn get_api_server(api: String, custom: String) -> String {
    if !api.is_empty() {
        return api.to_owned();
    }
    custom
}

fn read_custom_client_advanced_settings() {}
EOF
    cat > "$tmp_dir/libs/hbb_common/src/config.rs" <<'EOF'
use std::collections::HashMap;

pub struct Config;

impl Config {
    pub fn get_rendezvous_servers() -> Vec<String> {
        let s = Self::get_option("custom-rendezvous-server");
        if !s.is_empty() {
            return vec![s];
        }
        return vec!["rs-ny.rustdesk.com".to_string()];
    }

    pub fn get_options() -> HashMap<String, String> {
        let mut res = DEFAULT_SETTINGS.read().unwrap().clone();
        res.extend(CONFIG2.read().unwrap().options.clone());
        res.extend(OVERWRITE_SETTINGS.read().unwrap().clone());
        res
    }

    pub fn get_option(k: &str) -> String {
        get_or(
            &OVERWRITE_SETTINGS,
            &CONFIG2.read().unwrap().options,
            &DEFAULT_SETTINGS,
            k,
        )
        .unwrap_or_default()
    }
}
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
    mkdir -p "$tmp_dir/flutter/lib/desktop/pages" "$tmp_dir/flutter/lib" "$tmp_dir/src/ui"
    cat > "$tmp_dir/flutter/lib/desktop/pages/desktop_home_page.dart" <<'EOF'
final children = <Widget>[
  if (bind.isCustomClient())
    Align(
      alignment: Alignment.center,
      child: loadPowered(context),
    ),
  Align(
    alignment: Alignment.center,
    child: loadLogo(),
  ),
  buildTip(context),
];
Widget buildTip(BuildContext context) {
  return Column(
    children: [
      Text(
        translate("desk_tip"),
        overflow: TextOverflow.clip,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
EOF
    cat > "$tmp_dir/flutter/lib/desktop/pages/connection_page.dart" <<'EOF'
  Widget build(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Column(
      children: [
        Expanded(
            child: Column(
          children: [
            Row(
              children: [
                Flexible(child: _buildRemoteIDTextField(context)),
              ],
            ).marginOnly(top: 22),
          ],
        ).paddingOnly(left: 12.0)),
      ],
    );
  }
EOF
    cat > "$tmp_dir/flutter/lib/desktop/pages/desktop_setting_page.dart" <<'EOF'
                        children: [
                          Text(
                            translate('Slogan_tip'),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          )
                        ],
EOF
    cat > "$tmp_dir/flutter/lib/common.dart" <<'EOF'
Widget loadPowered(BuildContext context) {
  if (bind.mainGetBuildinOption(key: "hide-powered-by-me") == 'Y') {
    return SizedBox.shrink();
  }
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: () {
        launchUrl(Uri.parse('https://rustdesk.com'));
      },
      child: Opacity(
          opacity: 0.5,
          child: Text(
            translate("powered_by_me"),
            overflow: TextOverflow.clip,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 9, decoration: TextDecoration.underline),
          )),
    ),
  ).marginOnly(top: 6);
}
EOF
    cat > "$tmp_dir/src/ui/index.tis" <<'EOF'
{is_custom_client && handler.get_builtin_option("hide-powered-by-me") != "Y" ? <div .link #powered-by style="opacity:0.5;font-size:0.8em;text-decoration:underline">{translate('powered_by_me')}</div> : ""}
<div .lighter-text>{outgoing_only ? translate('outgoing_only_desk_tip') : translate('desk_tip')}</div>
{!incoming_only && <div .right-pane>
                    <div .right-content>
                        <div .card-connect>
            <div .title>{translate('Control Remote Desktop')}</div>
        </div>
    </div>
</div>}
event click $(#powered-by) {
    handler.open_url("https://rustdesk.com");
}
function showAbout() {
    msgbox("about", "About", "<div><p style='font-weight: bold'>" + translate("Slogan_tip") + "</p>\
            </div>", "", function(el) {}, 400, 400);
}
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
    mkdir -p "$tmp_dir/res/msi"
    cat > "$tmp_dir/res/msi/preprocess.py" <<'EOF'
#!/usr/bin/env python3
import json
import sys
import shutil
from pathlib import Path


def make_parser():
    import argparse
    parser = argparse.ArgumentParser(description="Msi preprocess script.")
    parser.add_argument(
        "-d",
        "--dist-dir",
        type=str,
        default="../../rustdesk",
        help="The dist directory to install.",
    )
    parser.add_argument(
        "--arp",
        action="store_true",
        help="Is ARPSYSTEMCOMPONENT",
        default=False,
    )
    parser.add_argument(
        "--app-name", type=str, default="RustDesk", help="The app name."
    )
    return parser


if __name__ == "__main__":
    parser = make_parser()
    args = parser.parse_args()

    app_name = args.app_name
    dist_dir = Path(sys.argv[0]).parent.joinpath(args.dist_dir).resolve()
EOF
    cat > "$tmp_dir/.github/workflows/flutter-build.yml" <<'EOF'
env:
  UPLOAD_ARTIFACT: "${{ inputs.upload-artifact }}"
  SIGN_BASE_URL: "${{ secrets.SIGN_BASE_URL }}-2"

jobs:
  build-for-windows-flutter:
    steps:
      - uses: Swatinem/rust-cache@e18b497796c12c097a38f9edb9d0641fb99eee32 # v2
        with:
          prefix-key: fixture-windows-flutter
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
      - name: Build msi
        if: env.UPLOAD_ARTIFACT == 'true'
        run: |
          pushd ./res/msi
          python preprocess.py --arp -d ../../rustdesk
          nuget restore msi.sln
          msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
  build-for-windows-sciter:
    steps:
      - uses: Swatinem/rust-cache@v2
        with:
          prefix-key: fixture-windows-sciter
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
        export BUILD_APP_NAME="FixtureApp"
        export BUILD_CUSTOMER="FixtureCustomer"
        export BUILD_CUSTOMER_LINK="https://fixture.example"
        export BUILD_SLOGAN="Fixture Slogan"
        export BUILD_RENDEZVOUS_SERVER="192.168.2.22:21117"
        export BUILD_RS_PUB_KEY="fixture-public-key"
        export BUILD_API_SERVER="http://192.168.2.22:21114"
        export BUILD_SOURCE_PATCH_DEBUG="true"
        source "$patcher"
        cd "$tmp_dir"
        apply_custom_source_patches
        grep -q '"app_name": "FixtureApp"' custom-build-config.json
        grep -q '"customer": "FixtureCustomer"' custom-build-config.json
        grep -q '"logo_url": ""' custom-build-config.json
        grep -q '"rendezvous_server": "192.168.2.22:21117"' custom-build-config.json
        grep -q '"custom_rendezvous_server": "192.168.2.22"' custom-build-config.json
        grep -q '"relay_server": "192.168.2.22"' custom-build-config.json
        grep -q '"source_patch_debug": true' custom-build-config.json
        grep -q 'custom-rendezvous-server' src/common.rs
        grep -q 'rendezvous-servers' src/common.rs
        grep -q '("relay-server", CUSTOM_RELAY_SERVER)' src/common.rs
        grep -q '("register-device", CUSTOM_REGISTER_DEVICE)' src/common.rs
        grep -q 'const CUSTOM_REGISTER_DEVICE: &str = "";' src/common.rs
        ! grep -q 'CUSTOM_BUILD_DEFAULTS_ONCE' src/common.rs
        ! grep -q 'call_once' src/common.rs
        grep -q 'let custom = if custom.is_empty()' src/common.rs
        grep -q 'config::Config::get_option("custom-rendezvous-server")' src/common.rs
        grep -q 'config::Config::get_option("register-device") == "N"' src/common.rs
        grep -q 'return "".to_owned();' src/common.rs
        grep -q 'config::Config::set_options(runtime_settings)' src/common.rs
        ! grep -q 'HARD_SETTINGS' src/common.rs
        ! grep -q 'disable-settings' src/common.rs
        grep -q 'const CUSTOM_RENDEZVOUS_SERVER: &str = "192.168.2.22";' src/common.rs
        grep -q 'const CUSTOM_RELAY_SERVER: &str = "192.168.2.22";' src/common.rs
        ! grep -q '("custom-rendezvous-server", "192.168.2.22:21117")' src/common.rs
        grep -q 'fixture-public-key' src/common.rs
        grep -q 'custom_build_default_option' libs/hbb_common/src/config.rs
        grep -q 'custom_build_default_options' libs/hbb_common/src/config.rs
        grep -q 'const CUSTOM_RENDEZVOUS_SERVER: &str = "192.168.2.22";' libs/hbb_common/src/config.rs
        grep -q '"custom-rendezvous-server" | "rendezvous-servers" => CUSTOM_RENDEZVOUS_SERVER' libs/hbb_common/src/config.rs
        grep -q '"key" => CUSTOM_RS_PUB_KEY' libs/hbb_common/src/config.rs
        grep -q 'res.extend(custom_build_default_options());' libs/hbb_common/src/config.rs
        grep -q 'or_else(|| custom_build_default_option(k).map(|v| v.to_owned()))' libs/hbb_common/src/config.rs
        grep -q 'custom_build_default_option("custom-rendezvous-server")' libs/hbb_common/src/config.rs
        grep -q '<string name="app_name">FixtureApp</string>' flutter/android/app/src/main/res/values/strings.xml
        grep -q '<string>FixtureApp</string>' flutter/ios/Runner/Info.plist
        grep -q 'Name=FixtureApp' res/rustdesk.desktop
        grep -q 'Name=Open a New Window' res/rustdesk.desktop
        grep -q '"customer_link": "https://fixture.example"' custom-build-config.json
        grep -q 'description = "FixtureApp Remote Desktop"' Cargo.toml
        grep -q 'ProductName = "FixtureApp"' Cargo.toml
        grep -q 'FileDescription = "FixtureApp Remote Desktop"' Cargo.toml
        grep -q 'description = "FixtureApp Remote Desktop"' libs/portable/Cargo.toml
        grep -q 'ProductName = "FixtureApp"' libs/portable/Cargo.toml
        grep -q 'FileDescription = "FixtureApp Remote Desktop"' libs/portable/Cargo.toml
        grep -q '由FixtureCustomer提供支持' src/lang/cn.rs
        grep -q 'Powered by FixtureCustomer' src/lang/en.rs
        grep -q 'custom-customer-name' src/common.rs
        grep -q 'custom-customer-name' libs/hbb_common/src/config.rs
        grep -q 'CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION' flutter/lib/desktop/pages/desktop_setting_page.dart
        grep -q "translate('custom_studio_attribution')" flutter/lib/desktop/pages/desktop_setting_page.dart
        grep -q 'custom-customer-link' flutter/lib/desktop/pages/desktop_setting_page.dart
        grep -q 'studio-about' src/ui/index.tis
        grep -q 'translate("custom_studio_attribution")' src/ui/index.tis
        grep -q 'custom-customer-link' src/ui/index.tis
        grep -q 'CUSTOM_RUSTDESK_HOME_HEADER' flutter/lib/desktop/pages/desktop_home_page.dart
        grep -q 'custom-customer-name' flutter/lib/desktop/pages/desktop_home_page.dart
        grep -q 'CUSTOM_RUSTDESK_HOME_POWERED' flutter/lib/desktop/pages/connection_page.dart
        grep -q 'CUSTOM_RUSTDESK_POWERED_LINK' flutter/lib/common.dart
        grep -q 'custom-rd-home-header' src/ui/index.tis
        grep -q 'custom-rd-home-powered' src/ui/index.tis
        grep -q 'custom-customer-name' src/ui/index.tis
        grep -q 'fontSize: 14' flutter/lib/common.dart
        grep -q 'Colors.black' flutter/lib/common.dart
        grep -q 'color:#000;font-size:1.15em' src/ui/index.tis
        grep -q 'SizedBox(height: 12)' flutter/lib/desktop/pages/desktop_setting_page.dart
        ! grep -q 'CUSTOM_RUSTDESK_HOME_POWERED' flutter/lib/desktop/pages/desktop_home_page.dart
        python3 - src/ui/index.tis <<'PY'
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "custom-rd-home-powered"
card = "<div .card-connect>"
if text.find(marker) == -1 or text.find(card) == -1 or text.find(marker) > text.find(card):
    raise SystemExit(1)
PY
        python3 - src/ui/index.tis <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8")
if "studio-about" not in text:
    raise SystemExit(1)
if not re.search(
    r'translate\("Slogan_tip"\).*studio-about',
    text,
    re.DOTALL,
):
    raise SystemExit(1)
PY
        ! grep -q 'SizedBox.shrink()' flutter/lib/desktop/pages/desktop_home_page.dart
        grep -q 'else ...\[' flutter/lib/desktop/pages/desktop_home_page.dart
        grep -q 'https://rustdesk.com' flutter/lib/common.dart
        grep -q 'https://rustdesk.com' src/ui/index.tis
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
        ! grep -q 'CUSTOM_RUSTDESK_MSI_APP_NAME' res/msi/preprocess.py
        ! grep -q '_custom_rustdesk_build_app_name' res/msi/preprocess.py
        grep -q 'app_name = args.app_name' res/msi/preprocess.py
        grep -q 'python preprocess.py --arp -d ../../rustdesk' .github/workflows/flutter-build.yml
        ! grep -q 'msi-preprocess-prep.py' .github/workflows/flutter-build.yml
        ! grep -q 'target-msi-app-name.txt' .github/workflows/flutter-build.yml
        grep -A1 'Swatinem/rust-cache@e18b497796c12c097a38f9edb9d0641fb99eee32' .github/workflows/flutter-build.yml | grep -q 'continue-on-error: true'
        grep -A1 'Swatinem/rust-cache@v2' .github/workflows/flutter-build.yml | grep -q 'continue-on-error: true'
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

function test_hide_network_settings_is_wired() {
    local patcher=".github/workflows/scripts/source-patcher.sh"
    local trigger=".github/workflows/scripts/trigger.sh"

    if grep -q 'hide_network_settings:' "$WORKFLOW_FILE" &&
       grep -q 'BUILD_HIDE_NETWORK_SETTINGS' "$WORKFLOW_FILE" &&
       grep -q 'hide_network_settings' "$trigger" &&
       grep -q 'HIDE_NETWORK_SETTINGS' "$trigger" &&
       grep -q 'BUILD_HIDE_NETWORK_SETTINGS' "$patcher" &&
       grep -q 'hide-server-settings' "$patcher" &&
       grep -q 'hide-network-settings' "$patcher"; then
        record_test_result "hide_network_settings_is_wired" "PASS" "hide_network_settings 从 Issue 变量贯通到源码 patch"
        return 0
    fi

    record_test_result "hide_network_settings_is_wired" "FAIL" "hide_network_settings 应贯通 trigger、workflow 与 source-patcher"
    return 1
}

function test_source_patcher_hide_network_settings_writes_builtin_flags() {
    local patcher=".github/workflows/scripts/source-patcher.sh"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    mkdir -p "$tmp_dir/src" "$tmp_dir/libs/hbb_common/src" "$tmp_dir/.github/workflows/scripts"
    cat > "$tmp_dir/src/common.rs" <<'EOF'
pub fn load_custom_client() {
}

pub fn get_custom_rendezvous_server(custom: String) -> String {
    custom
}

pub fn get_api_server(api: String, custom: String) -> String {
    api
}

fn read_custom_client_advanced_settings() {}
EOF
    cat > "$tmp_dir/libs/hbb_common/src/config.rs" <<'EOF'
impl Config {
    pub fn get_options() -> HashMap<String, String> {
        HashMap::new()
    }

    pub fn get_option(k: &str) -> String {
        String::new()
    }

    pub fn get_rendezvous_servers() -> Vec<String> {
        vec![]
    }
}
EOF
    cat > "$tmp_dir/.github/workflows/flutter-build.yml" <<'EOF'
env:
  UPLOAD_ARTIFACT: "${{ inputs.upload-artifact }}"
EOF

    if (
        set -e
        export BUILD_APP_NAME="FixtureApp"
        export BUILD_CUSTOMER="FixtureCustomer"
        export BUILD_RENDEZVOUS_SERVER="192.168.2.22:21117"
        export BUILD_RS_PUB_KEY="fixture-public-key"
        export BUILD_HIDE_NETWORK_SETTINGS="true"
        source "$patcher"
        cd "$tmp_dir"
        apply_custom_source_patches
        grep -q 'hide-server-settings' src/common.rs
        grep -q 'hide-network-settings' src/common.rs
        grep -q 'const CUSTOM_HIDE_NETWORK_SETTINGS: &str = "Y";' src/common.rs
        grep -q '"hide-server-settings" | "hide-network-settings"' libs/hbb_common/src/config.rs
    ); then
        rm -rf "$tmp_dir"
        record_test_result "source_patcher_hide_network_settings_writes_builtin_flags" "PASS" "hide_network_settings=true 写入 hide-server/network-settings"
        return 0
    fi

    rm -rf "$tmp_dir"
    record_test_result "source_patcher_hide_network_settings_writes_builtin_flags" "FAIL" "hide_network_settings=true 应写入内置 hide-server/network-settings"
    return 1
}

function test_source_patcher_lock_network_settings_matches_historical_defaults() {
    local patcher=".github/workflows/scripts/source-patcher.sh"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    mkdir -p "$tmp_dir/src" "$tmp_dir/.github/workflows/scripts"
    cat > "$tmp_dir/src/common.rs" <<'EOF'
pub fn load_custom_client() {
}

pub fn get_custom_rendezvous_server(custom: String) -> String {
    custom
}

pub fn get_api_server(api: String, custom: String) -> String {
    if !api.is_empty() {
        return api.to_owned();
    }
    custom
}

fn read_custom_client_advanced_settings() {}
EOF
    cat > "$tmp_dir/.github/workflows/flutter-build.yml" <<'EOF'
env:
  UPLOAD_ARTIFACT: "${{ inputs.upload-artifact }}"
  SIGN_BASE_URL: "${{ secrets.SIGN_BASE_URL }}-2"
EOF

    if (
        set -e
        export BUILD_LOCK_NETWORK_SETTINGS="true"
        export BUILD_CUSTOMER="FixtureDesk"
        export BUILD_RENDEZVOUS_SERVER="192.168.2.22:21117"
        export BUILD_RS_PUB_KEY="fixture-public-key"
        source "$patcher"
        cd "$tmp_dir"
        apply_custom_source_patches
        grep -q '"lock_network_settings": true' custom-build-config.json
        grep -q 'HARD_SETTINGS' src/common.rs
        grep -q 'disable-settings' src/common.rs
        grep -q 'custom-rendezvous-server' src/common.rs
        grep -q 'rendezvous-servers' src/common.rs
        grep -q '("relay-server", CUSTOM_RELAY_SERVER)' src/common.rs
        grep -q '("register-device", CUSTOM_REGISTER_DEVICE)' src/common.rs
        grep -q 'const CUSTOM_REGISTER_DEVICE: &str = "N";' src/common.rs
        ! grep -q 'CUSTOM_BUILD_DEFAULTS_ONCE' src/common.rs
        ! grep -q 'call_once' src/common.rs
        grep -q 'let custom = if custom.is_empty()' src/common.rs
        grep -q 'config::Config::get_option("register-device") == "N"' src/common.rs
        grep -q 'config::Config::set_options(runtime_settings)' src/common.rs
        grep -q '("key", CUSTOM_RS_PUB_KEY)' src/common.rs
    ); then
        rm -rf "$tmp_dir"
        record_test_result "source_patcher_lock_network_settings_matches_historical_defaults" "PASS" "lock_network_settings 恢复历史可就绪的 hard settings 定制"
        return 0
    fi

    rm -rf "$tmp_dir"
    record_test_result "source_patcher_lock_network_settings_matches_historical_defaults" "FAIL" "lock_network_settings=true 应写入 HARD_SETTINGS 和 disable-settings"
    return 1
}

function test_issue_params_preserve_issue_supplied_patch_variables() {
    local trigger=".github/workflows/scripts/trigger.sh"
    local event_data
    event_data=$(jq -c -n --arg body $'tag: issue-custom\nemail: admin@example.com\ncustomer: OneCloud\napp_name: OneCloudDesk\ncustomer_link: https://rustdesk.jackadam.top\nlogo_url: https://assets.example.com/logo.png\nsuper_password: password123\nslogan: Powered by OneCloud Desk\nrendezvous_server: rustdesk.jackadam.top:21116\nrelay_server: rustdesk.jackadam.top:21117\nrs_pub_key: dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI=\napi_server: \nlock_network_settings: true\nhide_network_settings: true\nsource_patch_debug: true' '{issue:{number:123, body:$body}}')

    if (
        set -e
        source "$trigger"
        extracted="$(trigger_manager extract-issue "$event_data")"
        echo "$extracted" | grep -q 'APP_NAME="OneCloudDesk"'
        echo "$extracted" | grep -q 'CUSTOMER="OneCloud"'
        echo "$extracted" | grep -q 'LOGO_URL="https://assets.example.com/logo.png"'
        echo "$extracted" | grep -q 'RELAY_SERVER="rustdesk.jackadam.top:21117"'
        echo "$extracted" | grep -q 'RS_PUB_KEY="dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI="'
        echo "$extracted" | grep -q 'SLOGAN="Powered by OneCloud Desk"'
        echo "$extracted" | grep -q 'LOCK_NETWORK_SETTINGS="true"'
        echo "$extracted" | grep -q 'HIDE_NETWORK_SETTINGS="true"'
        echo "$extracted" | grep -q 'SOURCE_PATCH_DEBUG="true"'
    ); then
        record_test_result "issue_params_preserve_issue_supplied_patch_variables" "PASS" "Issue 变量保留完整 key、空格和网络锁定项"
        return 0
    fi

    record_test_result "issue_params_preserve_issue_supplied_patch_variables" "FAIL" "Issue 参数解析不应截断 rs_pub_key、slogan、lock_network_settings 或 hide_network_settings"
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
       ! grep -q '^  compile-client:' "$WORKFLOW_FILE" &&
       grep -q 'finish:' "$WORKFLOW_FILE" &&
       grep -Fq 'needs: [trigger, review, join-queue, wait-build-lock, build, upstream-build]' "$WORKFLOW_FILE"; then
        record_test_result "workflow_builds_real_client_artifact" "PASS" "workflow 通过 custom source 分支触发 RustDesk 原版 workflow 编译客户端产物"
        return 0
    fi

    record_test_result "workflow_builds_real_client_artifact" "FAIL" "workflow 应通过 custom source 分支触发 RustDesk 原版 workflow，而不是继续自编 compile-client"
    return 1
}

function test_upstream_build_uses_platform_result_summary() {
    if grep -q 'upstream_platform_conclusion' "$WORKFLOW_FILE" &&
       grep -q 'platform_results' "$WORKFLOW_FILE" &&
       grep -q 'gh run watch "$upstream_run_id" --repo "${{ github.repository }}" --interval 60 || true' "$WORKFLOW_FILE" &&
       grep -q 'gh run view "$upstream_run_id" --repo "${{ github.repository }}" --json jobs' "$WORKFLOW_FILE" &&
       grep -q 'def platform($name):' "$WORKFLOW_FILE" &&
       grep -q 'partial_success' "$WORKFLOW_FILE" &&
       grep -q 'Some target platforms failed: $platform_results' "$WORKFLOW_FILE"; then
        record_test_result "upstream_build_uses_platform_result_summary" "PASS" "外层汇总按目标平台判定内层原版 workflow 结果"
        return 0
    fi

    record_test_result "upstream_build_uses_platform_result_summary" "FAIL" "外层不应因内层原版 workflow 的非目标平台失败而直接判整轮失败"
    return 1
}

function test_upstream_android_universal_apk_has_diagnostics_injection() {
    if grep -q 'Injecting diagnostics for upstream Android universal APK build' "$WORKFLOW_FILE" &&
       grep -q -- '--target-platform android-arm64,android-arm,android-x64' "$WORKFLOW_FILE" &&
       grep -q 'Android universal APK diagnostics before build' "$WORKFLOW_FILE" &&
       grep -q 'Android universal APK monitor' "$WORKFLOW_FILE" &&
       grep -q 'android/app/src/main/jniLibs' "$WORKFLOW_FILE" &&
       grep -q 'ps -eo pid,ppid,%cpu,%mem,rss,vsz,comm --sort=-rss' "$WORKFLOW_FILE" &&
       grep -q 'build/app/outputs/flutter-apk' "$WORKFLOW_FILE"; then
        record_test_result "upstream_android_universal_apk_has_diagnostics_injection" "PASS" "inner upstream workflow injects diagnostics for Android universal APK only"
        return 0
    fi

    record_test_result "upstream_android_universal_apk_has_diagnostics_injection" "FAIL" "Android universal APK should get resource diagnostics without replacing per-ABI APK builds"
    return 1
}

function test_linux_build_uses_official_sciter_flow() {
    if ! grep -q 'python3 ./res/inline-sciter.py' "$WORKFLOW_FILE" &&
       ! grep -q 'Build Linux AppImage' "$WORKFLOW_FILE" &&
       ! grep -q '^  compile-client:' "$WORKFLOW_FILE" &&
       grep -q '^  upstream-build:' "$WORKFLOW_FILE" &&
       grep -q 'custom-rustdesk-upstream-build.yml' "$WORKFLOW_FILE"; then
        record_test_result "linux_build_uses_official_sciter_flow" "PASS" "Linux 编译改由 upstream flutter-build 承担，外层 workflow 不再自编 Sciter/AppImage"
        return 0
    fi

    record_test_result "linux_build_uses_official_sciter_flow" "FAIL" "外层 workflow 不应再内联 Linux Sciter/AppImage 编译"
    return 1
}

function test_windows_build_uses_official_sciter_inline_resources() {
    if ! grep -q "runner.os == 'Windows'" "$WORKFLOW_FILE" &&
       ! grep -q 'VCPKG_DEFAULT_HOST_TRIPLET' "$WORKFLOW_FILE" &&
       ! grep -q '^  compile-client:' "$WORKFLOW_FILE" &&
       grep -q '^  upstream-build:' "$WORKFLOW_FILE" &&
       grep -q 'uses: ./.github/workflows/flutter-build.yml' .github/workflows/custom-rustdesk-upstream-build.yml; then
        record_test_result "windows_build_uses_official_sciter_inline_resources" "PASS" "Windows 编译改由 upstream flutter-build 承担，外层 workflow 不再内联 Sciter 资源"
        return 0
    fi

    record_test_result "windows_build_uses_official_sciter_inline_resources" "FAIL" "外层 workflow 不应再内联 Windows Sciter/vcpkg 编译"
    return 1
}

function test_windows_release_outputs_single_exe_and_msi() {
    if ! grep -q 'Build Windows single-file executable' "$WORKFLOW_FILE" &&
       ! grep -q 'Build Windows MSI' "$WORKFLOW_FILE" &&
       ! grep -q 'Copy-Item -Path $sourceExe -Destination $msiExe -Force' "$WORKFLOW_FILE" &&
       ! grep -q 'msi-preprocess-prep.py' "$WORKFLOW_FILE" &&
       ! grep -q 'target-msi-app-name.txt' "$WORKFLOW_FILE" &&
       grep -q '^  upstream-build:' "$WORKFLOW_FILE" &&
       grep -q 'uses: ./.github/workflows/flutter-build.yml' .github/workflows/custom-rustdesk-upstream-build.yml; then
        record_test_result "windows_release_outputs_single_exe_and_msi" "PASS" "Windows exe/MSI 由 upstream flutter-build 承担，外层 workflow 不做 PowerShell MSI 插针"
        return 0
    fi

    record_test_result "windows_release_outputs_single_exe_and_msi" "FAIL" "Windows 应通过 upstream flutter-build 生成 exe/MSI，外层 workflow 不应改写 MSI 流程"
    return 1
}

function test_workflow_builds_android_apk_artifact() {
    if ! grep -q '^  compile-android:' "$WORKFLOW_FILE" &&
       grep -q '^  upstream-build:' "$WORKFLOW_FILE" &&
       grep -q 'custom-rustdesk-upstream-build.yml' "$WORKFLOW_FILE" &&
       grep -q 'Injecting diagnostics for upstream Android universal APK build' "$WORKFLOW_FILE" &&
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
    test_source_patch_debug_switch_is_wired || failed=1
    test_hide_network_settings_is_wired || failed=1
    test_source_patcher_applies_to_fixture_tree || failed=1
    test_source_patcher_hide_network_settings_writes_builtin_flags || failed=1
    test_source_patcher_lock_network_settings_matches_historical_defaults || failed=1
    test_issue_params_preserve_issue_supplied_patch_variables || failed=1
    test_api_server_is_optional_for_plain_hbbs_hbbr || failed=1
    test_build_job_uses_trigger_data_for_parameters || failed=1
    test_build_job_does_not_export_trigger_data_env || failed=1
    test_build_uploads_patched_source_artifact || failed=1
    test_workflow_builds_real_client_artifact || failed=1
    test_upstream_build_uses_platform_result_summary || failed=1
    test_upstream_android_universal_apk_has_diagnostics_injection || failed=1
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
