# Tasks：补丁 ID 重排

> 对应 [`spec.md`](./spec.md)。状态：**实现完成；验证受本机工具链限制（缺 jq / Python / gh），待 2.18 编译机或补齐工具后跑完**。
> 约束：T1–T5 的实现必须在**同一个 commit** 内完成；不得先合 manifest 再合 orchestrator。

## T0 — 分支与预检（只读基线）

- [x] `git checkout -b chore/patch-id-renumber`
- [x] 修改 `scripts/patch-lab/step-verify-all.sh` 的 `ids=(...)`，补上 `N01`、`P05`（旧 23 个）
- [ ] 运行 `bash scripts/patch-lab/step-verify-all.sh --profile baixin`，保存报告到 `PATCH_LAB_ROOT/step-verify-all-report-before.txt`（本机缺 jq/Python，且需 18 次上游 clone，未执行）
- [ ] 记录基线：23/23 PASS 或贴失败原始日志（同上）

**完成判据**：旧编号下全量锚点/幂等基线可复现；报告路径记录在 PR 描述。

## T1 — manifest 注册表

文件：`.github/workflows/scripts/patches/manifest.sh`

- [x] `CUSTOM_PATCH_IDS` 改为 18 个新 ID（101 103 201 202 301 401–406 501–506 601）
- [x] 新增 `CUSTOM_REGISTERED_DISABLED_PATCH_IDS=(104)` 与注释「已登记、暂不启用」
- [x] 新增 `_custom_normalize_patch_id`（旧→新，含 `P05→104`）
- [x] 新增 `_custom_retired_patch_hint`（N01→102、P02→611、P03→612、P04→613）
- [x] 新增 `_custom_patch_id_error`（退役/未启用/非法三类明确报错）
- [x] `_custom_patch_id_index` 先归一化
- [x] `_custom_should_run_patch` 支持 `SOURCE_PATCH_WHITELIST`，优先级 ONLY → 白名单 → UP_TO → APPLY_ALL
- [x] `_custom_validate_source_patch_up_to` 校验白名单，退役 ID fail-loud

## T2 — orchestrator 调度

文件：`.github/workflows/scripts/patches/orchestrator.sh`

- [x] `_custom_patch_schedule_active` 识别白名单
- [x] `apply_custom_source_patches` 从 `CUSTOM_VERIFIED_PATCH_IDS` 导出 `SOURCE_PATCH_WHITELIST`
- [x] 18 个 `_custom_run_patch` 改新 ID；删除 N01/P02/P03/P04 调用；不调用 104
- [x] `_custom_write_build_config_json`：`verified_patch_up_to` 固定写空，新增 `verified_patch_ids`
- [x] trace 字段同步

## T3 — rollout 白名单

文件：`.github/verified-patches.env`

- [x] `CUSTOM_VERIFIED_PATCH_UP_TO` 删除
- [x] `CUSTOM_VERIFIED_PATCH_IDS="101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601"`
- [x] 表格重写 23 行；102/104/611/612/613 标注退役/未启用
- [x] 本地命令示例改新 ID

## T4 — 装载与退役脚本

- [x] `load.sh` 删除 4 个退役脚本的 source 行，保留 `super_password.patch.sh`
- [x] 删除 `core/network_lock.patch.sh`、`platform/windows-signing.sh`、`platform/msi-noop.sh`、`platform/rust-cache-nonfatal.sh`

## T5 — 脚本自引用

- [x] 所有补丁脚本注释/日志/`SystemExit` 的旧 ID 改新 ID
- [x] 交叉引用同步（r01 的 F13→405、logo-assets 的 F10→402、sciter 的 B02→202 等）
- [x] marker：`CUSTOM_RUSTDESK_S10_ICON_PROBE` → `CUSTOM_RUSTDESK_501_ICON_PROBE`（脚本 + verify.sh）
- [x] 不改脚本文件名

## T6 — CI workflow

- [x] `CustomBuildRustdesk.yml` 输入说明示例改新 ID
- [x] 加载 env 步骤输出/判断 `CUSTOM_VERIFIED_PATCH_IDS`
- [x] 应用步骤：`patch_up_to` → UP_TO；否则白名单 → `SOURCE_PATCH_WHITELIST`
- [x] `test_scripts/CustomBuildRustdesk.yml` 同步同样修改

## T7 — 本地工具链

- [x] `step-verify-all.sh` 列表改为 18 个新 ID（预检补项已在 T0）
- [x] `run.sh` 帮助示例、ID 顺序串、`verify_up_to="601"`
- [x] `verify.sh` 16 处 `verify_from`、注释、marker
- [x] `source-patcher.sh` 用法示例
- [x] `trigger-one-patch.sh` 用法/示例
- [x] `profiles/baixin-{hide,lock}.env` 注释

## T8 — 测试与 fixtures

- [x] `test_scripts/workflow-tests.sh`：`^CUSTOM_VERIFIED_PATCH_IDS=`、变量名、消息
- [x] `test_scripts/workflow-tests.sh`：删除已退役 no-op 的断言，改为负向断言
- [x] `test_scripts/fixtures/issue-params-body.txt`：`patch_up_to: 103`
- [x] 其他测试/fixtures 中旧 ID 按映射替换

## T9 — 表单与规则

- [x] `q0-baseline.yml`：白名单变量名、「需 101 起」
- [x] `custom-build.yml`：`patch_up_to` 说明
- [x] `.cursor/rules/custom-rustdesk-handoff.mdc`：开关、顺序、示例

## T10 — 文档

- [x] `docs/patch-registry.md` 全表重写 + 迁移对照表 + Legacy caveat
- [x] `docs/verification-rollout.md`（白名单、18 针）
- [x] `docs/experiment-verification.md`（计数与表格；保留 run 号）
- [x] `docs/workspace-handoff.md`
- [x] `docs/ui-customization.md`、`docs/source-patcher-refactor-plan.md`、`docs/rustdesk-stack.md`
- [ ] `docs/customization-architecture.md`、`customization-architecture-simple.md`（按 spec：工作区同步、不纳入本 commit，未改）
- [x] `docs/patch-id-renumber-plan.md` 保持原样（grep 例外）
- [x] `docs/patch-diff/**` 不入库、不参与清零

## T11 — 验证（严格按序）

- [ ] `step-verify-all.sh`：18/18 PASS（阻塞：缺 jq/Python，且需 18 次上游 clone）
- [ ] `run-tests.sh workflow-tests` + `utils-tests`：全 PASS（workflow-tests 28 项中 26 项 PASS，2 项因缺 jq/Python 失败；utils-tests 需 gh）
- [ ] 全量白名单执行：18 条 `[ID]` 日志、无 FAILED（离线调度模拟 18 条顺序正确；真实插针需 jq/Python）
- [ ] 幂等双跑：第二次全部 skip/already applied（阻塞，同上）
- [x] 旧 ID grep 清零（仅 alias 表 `manifest.sh`、`verified-patches.env` 与 `patch-registry.md` 迁移表例外）
- [x] 白名单集合断言 = §3.3
- [x] 退役 ID 报错断言（N01/P02/P03/P04/104/P05）

## T12 — 提交与 PR

- [ ] 单 commit：manifest + orchestrator + 全部引用 + 文档 + 删除文件
- [ ] push `chore/patch-id-renumber`
- [ ] 开 PR 到 main；描述含等价性证明、改动文件清单、验证输出
- [x] **不直推 main**

## T13 — 合并后完整构建（依赖 merge 权限）

- [ ] 按 issue 模板新建构建 issue（issue #1 队列），`patch_up_to` 留空；记录 issue 号
- [ ] 记录 run 号
- [ ] 日志核对 18 个新 ID、无退役 ID、无静默 skip、无被吞错误
- [ ] 新旧 ID 日志对照映射表，指出任何残留旧 ID
- [ ] 产物清单：各平台 artifact / release 资产、命名、版本号
- [ ] 失败时贴失败步骤与错误原文

**完成判据**：触发里程碑（issue + run）与构建结果里程碑（每补丁结果 + 产物清单）各上报一次。

---

## 阻塞说明（本机环境）

- `jq`：未安装（`jq: command not found`）。`verify.sh`、`lib/common.sh`、`orchestrator.sh` 的 build-config 都依赖它。
- `python3`：只有 Windows Store 占位（`Python was not found ...`）；`.venv` 指向失效的 `C:\Users\jacka\...\Python312\python.exe`。`202` 的 Pillow 与 `verify.sh` 的 PNG/Dart 检查依赖它。
- `gh`：未安装；`queue-manager.sh`、`utils-tests` 与 PR 创建都依赖它。
- `git` 到 GitHub 可通（`git ls-remote https://github.com/rustdesk/rustdesk.git HEAD` 返回 `e7bacd0…`），但 `curl` 直连 GitHub 超时。
- `step-verify-all.sh` 每针都会 `clean.sh` + 完整 clone 上游，属 2.18 编译机任务，本机不适合跑 18 轮。
