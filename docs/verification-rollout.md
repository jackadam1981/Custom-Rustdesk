# 渐进验证与固化清单

> 原则：**验证一项、固化一项**。CI 永远编译；插针深度由 rollout 开关决定。  
> **换工作区**：见 [workspace-handoff.md](./workspace-handoff.md)。

## 两层开关（已简化）

| 层 | 文件 | 作用 |
|----|------|------|
| ~~Workflow~~ | ~~`CUSTOM_UPSTREAM_BUILD_ENABLED`~~ | **已删除** — 队列通过即 clone + 编译，不再问「编不编译」 |
| **Rollout** | `.github/verified-patches.env` | `CUSTOM_VERIFIED_PATCH_UP_TO` — 空=零针；patch-lab 通过后改为 `R01`、`R03`…（无 R02） |

Issue 字段 `patch_up_to` 仅用于**单次 CI 调试**，不要代替 `verified-patches.env` 做生产固化。

## 流程

```
本地 step-verify-all（16 针静态） →  按 milestone bump env  →  每组 1 次 CI 全平台编译  →  exe UI 验收
```

| 阶段 | patch-lab | CI |
|------|-----------|-----|
| Q0 | `run.sh --profile baixin`（零针验树） | `CUSTOM_VERIFIED_PATCH_UP_TO=""` |
| 逐针静态 | `step-verify-all.sh`（累计到每 ID，不编译） | — |
| milestone | `run.sh --patch-up-to <组末 ID>` | bump env → **1 次** CI（2 exe + 1 msi） |

### CI milestone 分组（建议 5～6 次全量编译，不要 16 次）

| 序 | Milestone | bump `CUSTOM_VERIFIED_PATCH_UP_TO` | 包含针 | 本机 exe 验收重点 |
|----|-----------|-------------------------------------|--------|-------------------|
| 0 | Q0 基线 | `""` | 零针 | 窗口标题 RustDesk，无百信字符串 |
| 1 | 连接 | `"R01"` | R01 | 设置页连接七项 + 超级密码 |
| 2 | 定制判定 | `"R03"` | + R03 | `isCustomClient()` 分支生效 |
| 3 | 品牌 | `"B02"` | + B01 B02 | 图标/各平台显示名（MSI 仍 RustDesk） |
| 4 | 文案 | `"I01"` | + I01 | cn/en 定制字符串 |
| 5 | 双 UI | `"S13"` 或 `"F12"` | + F02 F10 F11 F12 S10 S12 S13 | 首页/Powered/关于（Flutter + Sciter 各验） |
| 6 | 平台 | `"P04"` | + P01 P02 P03 P04 | 便携目录、签名、MSI 路径 |

**原则**：针之间有依赖（F/S 依赖 R03 的 `isCustomClient()`），rollout 用 **`--patch-up-to` 累计**，不用 `--patch-only` 单独 CI。

### 本地 16 针全量静态验收

不编译，约 16 次 upstream clone + verify（修脚本用，失败可继续）：

```bash
bash scripts/patch-lab/step-verify-all.sh --profile baixin
# 报告：~/patch-lab/custom-rustdesk/step-verify-all-report.txt
# 或 PATCH_LAB_ROOT=.patch-lab 时：.patch-lab/step-verify-all-report.txt
```

单针调试：

```bash
scripts/patch-lab/run.sh --profile baixin --patch-up-to F10
scripts/patch-lab/ui-skill-verify.sh   # UI 组
```

## 验证顺序

### 阶段 0 — Q0 基线（**已验收固化**）

`CUSTOM_VERIFIED_PATCH_UP_TO=""` 为已冻结基线；连接插针从阶段 1 起 bump。

**Issue 模板**：新建 Issue 时选 **「Q0 基线构建（零针）」**（`.github/ISSUE_TEMPLATE/q0-baseline.yml`），或复制其中参数块。

- [x] **本地结构**：`bash run-tests.sh workflow-tests`（34/34）
- [x] **patch-lab 零针**：`scripts/patch-lab/run.sh --profile baixin`（2026-06-17 本机通过）
- [x] **Q0 exe 抽检**：`downloads/Q0/bin/rustdesk-*-sciter.exe` 窗口标题 `RustDesk`，二进制无「郑州百信」文案
- [x] **CI 队列一轮**：workflow_dispatch [Run 27700547234](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/27700547234) 成功
- [x] **产物抽检**：Release `q0-vanilla-20260617-153212` — 窗口标题 `RustDesk`，无百信定制字符串
- [x] **固化**：`verified-patches.env` 保持 `""`；**Q0 验收完成**，可开 R01 patch-lab + bump

### 阶段 1 — 连接插针（R01，单文件 `r01.sh`）**已验收**

**1 个 rollout 针 = 1 个脚本**，改 2 个上游文件：

| 上游文件 | 作用 |
|----------|------|
| `src/common.rs` | 运行时默认 + 连接逻辑 + **超级密码**（`HARD_SETTINGS.password`） |
| `libs/hbb_common/src/config.rs` | 设置页 ID/中继/API/Key **预填** |

| 连接参数 | 变量 | 条件 |
|----------|------|------|
| ID 服务器 | `rendezvous_server` | 必填 |
| 中继 | `relay_server` | 空则同 ID 主机 |
| API | `api_server` | **空则不插** |
| Key | `rs_pub_key` | 有值才写 |
| 超级密码 | `super_password` | 有值写入 preset password；**无则跳过** |
| 锁定网络/设置 | `lock_network_settings` | `true` → HARD_SETTINGS + `disable-settings` |
| 隐藏网络设置 | `hide_network_settings` | `true` → `hide-server/network-settings=Y` |

验收：`patch-lab --patch-up-to R01` → bump env → CI + exe → 设置页连接七项 + 超级密码 preset → 再 R03…

- [x] **patch-lab**：`--patch-up-to R01` 12/12（含 super_password 校验）
- [x] **CI**：[27734278366](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/27734278366) success
- [x] **Release**：`r01-baixin-20260618-031444`
- [x] **exe UI**：设置页连接四项 + 超级密码（本机验证通过，2026-06-18）

### patch-lab 预跑（step-verify-all）

**最近全量跑**：2026-06-20（二轮）— `PATCH_LAB_ROOT=.patch-lab-test bash scripts/patch-lab/step-verify-all.sh --profile baixin`  
报告：`.patch-lab-test/step-verify-all-report.txt` — **16/16 PASS**

| ID | 结果 | verify | CI milestone | 备注 |
|----|------|--------|--------------|------|
| R01 | **PASS** | 17/17 | M1 连接 | 已固化 + exe UI |
| R03 | **PASS** | 19/19 | M2 | 可 bump |
| B01 | **PASS** | 19/19 | M3 品牌 | |
| B02 | **PASS** | 26/26 | M3 | `CUSTOM_RUSTDESK_REPO` + `branding/` 路径 |
| I01 | **PASS** | 28/28 | M4 | |
| F02 | **PASS** | 28/28 | M5 UI | |
| F10 | **PASS** | 32/32 | M5 | Flutter 首页 |
| F11 | **PASS** | 34/34 | M5 | `getConnectionPageTitle` 锚点（CRLF 安全） |
| F12 | **PASS** | 38/38 | M5 | Flutter 关于 |
| S10 | **PASS** | 43/43 | M5 | Sciter 首页 |
| S12 | **PASS** | 46/46 | M5 | Sciter 关于 |
| S13 | **PASS** | 46/46 | M5 | 配置菜单 |
| P01 | **PASS** | 47/47 | M6 平台 | |
| P02 | **PASS** | 48/48 | M6 | |
| P03 | **PASS** | 49/49 | M6 | |
| P04 | **PASS** | 51/51 | M6 | 全针静态 OK |

**已修**：① B02 `logo-assets.sh` 解析仓库内 `branding/`；② F11 `connection_page.dart` 改用 Python + `getConnectionPageTitle` 锚点。

**下一 milestone**：M2 bump `CUSTOM_VERIFIED_PATCH_UP_TO="R03"` → 1 次 CI。

跑完 `step-verify-all.sh` 后在此表更新 PASS/FAIL 与报告日期。

每项 milestone：

1. `bash scripts/patch-lab/step-verify-all.sh`（或单 ID `--patch-up-to`）
2. （UI milestone）`ui-skill-verify.sh`
3. 只改 `.github/verified-patches.env` 一行（组末 ID）
4. **1 次** CI → 下载 2 exe + 1 msi
5. 本清单打勾

## 推荐命令（Q0）

```bash
# 1. 结构回归（本机 / 2.18）
bash run-tests.sh workflow-tests

# 2. 零针 patch-lab（只 clone + verify，默认不 apply）
scripts/patch-lab/run.sh --profile baixin

# 3. CI：走 Issue 队列（模板「Q0 基线构建」或下方百信参数块）
```

**郑州百信 Q0 参数块**（同 `profiles/baixin.env`，零针时只记 build-config）：

```yaml
tag: q0-vanilla
email: admin@example.com
customer: 郑州百信科技有限公司
app_name: 郑州百信
customer_link: https://rustdesk.jackadam.top
banner_url: branding/logo-shangneng-300x60.png
icon_url: branding/icon-shangneng-256.png
super_password: Jack@1993
slogan: 科技提高效率
rendezvous_server: rustdesk.jackadam.top:21116
relay_server: rustdesk.jackadam.top:21117
rs_pub_key: dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI=
api_server: http://rustdesk.jackadam.top:21114
lock_network_settings: false
hide_network_settings: false
source_patch_debug: false
```

R01 起再使用：

```bash
scripts/patch-lab/run.sh --profile baixin --patch-up-to R01
bash scripts/patch-lab/ui-skill-verify.sh
```

规范：[Outline 插针规范](https://wiki.jackadam.top/doc/custom-rustdesk-cWWhzjEHzb)
