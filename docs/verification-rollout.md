# 渐进验证与固化清单

> 原则：**验证一项、固化一项**。CI 永远编译；插针深度由 rollout 开关决定。

## 两层开关（已简化）

| 层 | 文件 | 作用 |
|----|------|------|
| ~~Workflow~~ | ~~`CUSTOM_UPSTREAM_BUILD_ENABLED`~~ | **已删除** — 队列通过即 clone + 编译，不再问「编不编译」 |
| **Rollout** | `.github/verified-patches.env` | `CUSTOM_VERIFIED_PATCH_UP_TO` — 空=零针；patch-lab 通过后改为 `R01`、`R02`… |

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

### 阶段 0 — Q0 基线（**当前目标，未验收**）

保持 `CUSTOM_VERIFIED_PATCH_UP_TO=""`，**禁止** bump 到 R01，直到下面全部打勾。

**Issue 模板**：新建 Issue 时选 **「Q0 基线构建（零针）」**（`.github/ISSUE_TEMPLATE/q0-baseline.yml`），或复制其中参数块。

- [x] **本地结构**：`bash run-tests.sh workflow-tests`（34/34）
- [x] **patch-lab 零针**：`scripts/patch-lab/run.sh --profile baixin`（2026-06-17 本机通过）
- [x] **Q0 exe 抽检**：`downloads/Q0/bin/rustdesk-*-sciter.exe` 窗口标题 `RustDesk`，二进制无「郑州百信」文案
- [ ] **CI 队列一轮**：Issue（百信 Q0 模板）→ 审批 → upstream 成功
- [ ] **产物抽检**：当次 Release exe/msi 确认为原版
- [ ] **固化**：`verified-patches.env` 保持 `""` 直至 CI Q0 打勾

### patch-lab 预跑（待 CI 固化前）

| ID | 本地 patch-lab | 备注 |
|----|----------------|------|
| R01 | 通过 9/9 | 待 Q0 CI 后再 bump env |
| R02 | 通过 11/11 | |
| R03 | 通过 13/13 | 核心组 R01–R03 patch-lab 完毕 |

> 说明：`downloads/Q0/` 里若有旧产物，仅代表历史试跑；以**本轮** workflow + 本地 patch-lab 通过为准。

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
