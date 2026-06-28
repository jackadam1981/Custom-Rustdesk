# 渐进验证与固化清单

> 原则：**验证一项、固化一项**。CI 永远编译；插针深度由 rollout 开关决定。  
> **换工作区**：见 [workspace-handoff.md](./workspace-handoff.md)。  
> **分步实验验证（M0–M6、6 次 CI）**：见 **[experiment-verification.md](./experiment-verification.md)**。

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

### CI milestone 分组

**6 次 CI + Q0 基线** 的分档表、每档 checklist 与当前进度 → **[experiment-verification.md](./experiment-verification.md)**（实验验证文档）。

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

## 验证进度

M0–M6 分档 checklist、16 针静态表、每档 5 步操作 → **[experiment-verification.md](./experiment-verification.md)**。

**当前**：rollout **`"S13"`**；**Sciter UI 已固化**（2026-06-28）；Flutter M5 仍待 exe 验收。

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
