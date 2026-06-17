# 渐进验证与固化清单

> 原则：**验证一项、固化一项**。不要同时改队列和多个插针。

## 单一开关

| 文件 | 作用 |
|------|------|
| `.github/verified-patches.env` | `CUSTOM_VERIFIED_PATCH_UP_TO` — 空=原版上游；验证通过后改为 `R01`、`R02`… |
| `.github/workflows/CustomBuildRustdesk.yml` | `CUSTOM_UPSTREAM_BUILD_ENABLED=true` — 队列 + clone + 上游编译 |

Issue 字段 `patch_up_to` 仅用于**单次调试**，不要代替 `verified-patches.env` 做固化。

## 验证顺序

### 阶段 0 — 队列基线（当前目标）

- [ ] **Q0** Issue 触发 → 审批 → 入队 → 拿 build 锁 → clone **零针**上游 → push → upstream workflow 成功
- 本地：`bash run-tests.sh workflow-tests`（fixture 仍用 `CUSTOM_PATCH_APPLY_ALL` 测全针逻辑）
- 固化：保持 `CUSTOM_VERIFIED_PATCH_UP_TO=""`

### 阶段 1 — 核心 / 服务器（R01–R03）

| ID | 验证 | 固化值 |
|----|------|--------|
| R01 | patch-lab `--patch-up-to R01` + CI 队列一轮 | `CUSTOM_VERIFIED_PATCH_UP_TO="R01"` |
| R02 | 同上 R02 | `"R02"` |
| R03 | 同上 R03 | `"R03"` |

### 阶段 2 — 品牌 / 文案（B01–B02, I01）

| ID | 验证 | 固化值 |
|----|------|--------|
| B01 | patch-lab + ui-skill-verify | `"B01"` |
| B02 | 需 banner_url + icon_url | `"B02"` |
| I01 | 文案 grep | `"I01"` |

### 阶段 3 — Flutter UI（F02, F10–F12）

逐项 `--patch-up-to Fxx`，2.18 上 `ui-skill-verify.sh`。

### 阶段 4 — Sciter UI（S10, S12, S13）

同上；S13 重点测低分辨率配置菜单滚动。

### 阶段 5 — 平台 / CI（P01–P04）

P02 签名需 secrets；其余以 workflow 日志为准。

## 推荐命令

```bash
# 本地单针
scripts/patch-lab/run.sh --profile baixin --patch-up-to R01

# 本地 UI 技能检查（在已 patch 的上游树）
bash scripts/patch-lab/ui-skill-verify.sh

# 结构回归
bash run-tests.sh workflow-tests
```

## 固化流程（每项）

1. patch-lab 通过  
2. （UI 针）`ui-skill-verify` 通过  
3. CI 队列跑一轮（`patch_up_to` 留空，只靠 `verified-patches.env`）  
4. 上游产物抽检  
5. 提交：只改 `verified-patches.env` 一行 + 本清单打勾  

规范详情：[Outline 插针规范](https://wiki.jackadam.top/doc/custom-rustdesk-cWWhzjEHzb)
