# 渐进验证与固化清单

> 原则：**验证一项、固化一项**。CI 永远编译；插针深度由 rollout 开关决定。

## 两层开关（已简化）

| 层 | 文件 | 作用 |
|----|------|------|
| ~~Workflow~~ | ~~`CUSTOM_UPSTREAM_BUILD_ENABLED`~~ | **已删除** — 队列通过即 clone + 编译，不再问「编不编译」 |
| **Rollout** | `.github/verified-patches.env` | `CUSTOM_VERIFIED_PATCH_UP_TO` — 空=零针；patch-lab 通过后改为 `R01`、`R03`…（无 R02） |

Issue 字段 `patch_up_to` 仅用于**单次 CI 调试**，不要代替 `verified-patches.env` 做生产固化。

## 流程

```
patch-lab 验收 R01  →  改 verified-patches.env = "R01"  →  下次 CI 队列自动打到 R01 并编译
```

| 阶段 | patch-lab | CI |
|------|-----------|-----|
| Q0 | `run.sh --profile baixin`（零针验树） | `CUSTOM_VERIFIED_PATCH_UP_TO=""` |
| R01+ | `run.sh --patch-up-to R01` | bump env 后队列构建带 R01 |

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

验收：`patch-lab --patch-up-to R01` → bump env → CI + exe → 设置页四项预填 + 超级密码 preset 生效 → 再 R03…

- [x] **patch-lab**：`--patch-up-to R01` 12/12（含 super_password 校验）
- [x] **CI**：[27734278366](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/27734278366) success
- [x] **Release**：`r01-baixin-20260618-031444`
- [x] **exe UI**：设置页连接四项 + 超级密码（本机验证通过，2026-06-18）

### patch-lab 预跑

| ID | 本地 patch-lab | 备注 |
|----|----------------|------|
| R01 | 12/12 + exe UI | **已固化** `CUSTOM_VERIFIED_PATCH_UP_TO="R01"` |
| R03 | 曾 13/13（旧 R02 单独时） | bump R01 后按新序重验 |

每项：

1. `scripts/patch-lab/run.sh --profile baixin --patch-up-to <ID>`
2. （UI 针）`ui-skill-verify.sh`
3. 只改 `.github/verified-patches.env` 一行
4. CI 队列跑一轮确认
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
api_server:
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
