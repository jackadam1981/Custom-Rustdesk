# 插针实验验证计划（M0–M6）

> **实验验证文档**：把 16 针插针拆成 **6 次 CI 全量编译**（加 Q0 基线共 7 档），每档「patch-lab 静态 → bump env → 1 次 CI → exe 验收 → 打勾固化」。  
> Rollout 开关与总原则见 [verification-rollout.md](./verification-rollout.md)；换工作区见 [workspace-handoff.md](./workspace-handoff.md)。  
> 2.22 自建服务端见 [rustdesk-stack.md](./rustdesk-stack.md)（内网 **18444** 管理后台；**不用 Web Client**；桌面客户端验收为主）。

## 为什么分 6 步 CI，而不是 16 步

| 方式 | 次数 | 适用 |
|------|------|------|
| **16 针逐步 CI** | 16 次全平台编译 | 过慢，仅修脚本时用 |
| **本计划 M1–M6** | **6 次** CI（每组末 ID bump 一次 env） | 生产 rollout |
| **patch-lab 静态** | 16 次 upstream clone（不编译） | 触发 CI 前的门禁 |

针之间有依赖（F/S UI 依赖 R03 的 `isCustomClient()`），每组用 **`--patch-up-to` 累计**到组末 ID，不用 `--patch-only` 单独 CI。

## 验证环境与职责

| 环境 | 路径/入口 | 做什么 | 不做什么 |
|------|-----------|--------|----------|
| **GitHub Actions** | `Custom Rustdesk Build Workflow`；Issue 或 `workflow_dispatch` | 全平台 **编译**、Release、产物上传 | patch-lab 静态 |
| **2.18 编译机** | `~/custom-rustdesk`；见 [patch-lab.md](./patch-lab.md) | **patch-lab / step-verify-all**（clone 上游 + 插针 + 断言） | 不代替 GHA 编译 |
| **Windows 开发机** | 如 `D:\My_Project\custom-rustdesk` | 拉 Release / `downloads/` → **exe UI 手测** | 无 bash/jq 时不跑 patch-lab；无 `gh` 时不触发 CI |

典型顺序：**2.18 patch-lab 静态（可选门禁）→ GHA 触发 1 次 CI → Windows 本机验 exe**。

## 两层验证

```
┌─────────────────────────────────────────────────────────────┐
│ 层 1：patch-lab 静态（2.18，不编译）                          │
│   step-verify-all.sh 或 run.sh --patch-up-to <组末 ID>       │
├─────────────────────────────────────────────────────────────┤
│ 层 2：CI + exe（GitHub Actions，全平台编译）                  │
│   bump verified-patches.env → push → 1 次 CI → 2 exe + 1 msi │
└─────────────────────────────────────────────────────────────┘
```

**生产开关**：`.github/verified-patches.env` 最后一行 `CUSTOM_VERIFIED_PATCH_UP_TO`。  
Issue 字段 `patch_up_to` 仅单次 CI 调试，不代替 env 固化。

## 里程碑总表

| 档 | Milestone | bump env 到 | 累计包含针 | exe 验收重点 | 状态 |
|----|-----------|-------------|------------|--------------|------|
| M0 | Q0 基线 | `""` | 零针 | 窗口标题 RustDesk，无定制文案 | **已验收** |
| M1 | 连接 | `"R01"` | R01 | 设置页网络 4 项 + preset 超级密码 | **重验中**（env 已拉回 R01） |
| M2 | 定制判定 | `"R03"` | R01 R03 | 连接项仍正常；`isCustomClient()` 已写入 | 暂缓（待 M1 重验后再 bump） |
| M3 | 品牌 | `"B02"` | … B01 B02 | 图标/各平台显示名（MSI 仍 RustDesk） | 待做 |
| M4 | 文案 | `"I01"` | … I01 | cn/en 定制字符串 | 待做 |
| M5 | 双 UI | `"S13"` 或 `"F12"` | … F02 F10 F11 F12 S10 S12 S13 | 首页/Powered/关于（Flutter + Sciter 各验） | 待做 |
| M6 | 平台 | `"P04"` | 全部 16 针 | 便携目录、签名、MSI 路径 | 待做 |

插针 ID 与脚本对照：`.github/verified-patches.env` 注释表，或 [downloads/Q0/patch-manifest.md](../downloads/Q0/patch-manifest.md)。

## 每档标准操作（5 步）

1. **patch-lab 静态**：`bash scripts/patch-lab/run.sh --profile baixin --patch-up-to <组末ID>`（或全量 `step-verify-all.sh`）
2. **（M5）UI 技能**：`bash scripts/patch-lab/ui-skill-verify.sh`
3. **bump env**：只改 `.github/verified-patches.env` 最后一行
4. **1 次 CI**：push → `gh workflow run` 或 Issue 队列；下载 2 exe + 1 msi
5. **打勾固化**：在本文件对应 M 档 checklist 记录 run URL / Release 名

---

## M0 — Q0 基线（零针）**已验收**

- [x] workflow-tests（结构回归）
- [x] patch-lab 零针：`run.sh --profile baixin`
- [x] CI：[Run 27700547234](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/27700547234)
- [x] Release：`q0-vanilla-20260617-153212`
- [x] exe：窗口标题 `RustDesk`，无百信定制字符串
- [x] env：`CUSTOM_VERIFIED_PATCH_UP_TO=""` 已固化

Issue 模板：`.github/ISSUE_TEMPLATE/q0-baseline.yml`

---

## M1 — 连接（R01）**重验中**

脚本：`patches/core/r01.sh` → `src/common.rs` + `libs/hbb_common/src/config.rs`

| 连接参数 | 变量 | 条件 |
|----------|------|------|
| ID 服务器 | `rendezvous_server` | 必填 |
| 中继 | `relay_server` | 空则同 ID 主机 |
| API | `api_server` | **空则不插** |
| Key | `rs_pub_key` | 有值才写 |
| 超级密码 | `super_password` | 有值写入 preset；无则跳过 |
| 锁定网络/设置 | `lock_network_settings` | `true` → HARD_SETTINGS |
| 隐藏网络设置 | `hide_network_settings` | `true` → 隐藏网络菜单 |

**exe 手测（设置 → 网络）**：ID、中继、**API**、Key 四项预填 + preset 超级密码（R01 共 7 参数，见上表）。

> **教训**：`downloads/R01-27751270327/` 旧包可能未含 API——GHA 触发时若未传 `api_server` 且仓库 secret `DEFAULT_API_SERVER` 为空，R01 **不会插 API**。重验必须显式传 `api_server`（见下文 § M1 重验三步）。

### M1 重验三步（GHA + 2.18 + Windows）

**① 2.18 patch-lab 静态**（不编译；CI 前/后可跑）

```bash
cd ~/custom-rustdesk && git pull

# 单档 R01（含 api_server 断言，profile 见 baixin.env）
bash scripts/patch-lab/run.sh --profile baixin --patch-up-to R01 --verify-up-to R01

# 可选：16 针全量
PATCH_LAB_ROOT=~/patch-lab/custom-rustdesk \
  bash scripts/patch-lab/step-verify-all.sh --profile baixin
```

**② GitHub Actions 触发编译**（针深度 = `.github/verified-patches.env` 当前 `"R01"`；Issue **不要**用 `patch_up_to` 代替 env）

- **Issue 队列（推荐）**：Issues → New →「RustDesk 定制构建」→ 粘贴 [`test_scripts/fixtures/baixin-r01-issue-body.txt`](../test_scripts/fixtures/baixin-r01-issue-body.txt) 全文（含 `api_server: http://rustdesk.jackadam.top:21114`）。
- **2.18 手动 dispatch**：

```bash
cd ~/custom-rustdesk && git pull

gh workflow run "Custom Rustdesk Build Workflow" \
  --ref codex/linux-appimage-actions-test \
  -f tag=r01-baixin-api \
  -f customer="郑州百信科技有限公司" \
  -f app_name="郑州百信" \
  -f email=admin@example.com \
  -f customer_link=https://rustdesk.jackadam.top \
  -f banner_url= \
  -f icon_url=logo.png \
  -f super_password='Jack@1993' \
  -f slogan=科技提高效率 \
  -f rendezvous_server=rustdesk.jackadam.top:21116 \
  -f relay_server=rustdesk.jackadam.top:21117 \
  -f rs_pub_key=dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI= \
  -f api_server=http://rustdesk.jackadam.top:21114 \
  -f lock_network_settings=false \
  -f hide_network_settings=false
```

CI 成功看**主 run** 的 `upstream-build` / `finish`（勿只看 macOS ENOTFOUND 子 job）。

**③ Windows 本机 exe 验收**

- 从 Release 下载，或放到 `downloads/R01-<run_id>/`（例：旧目录 `downloads/R01-27751270327/` 仅作参考，**重验用新 run 产物**）。
- 便携版混装 MSI 前：`scripts/clean-rustdesk-windows.ps1 -Force`（管理员）。
- 检查：设置 → 网络 **ID / 中继 / API / Key** + preset 超级密码 `Jack@1993`；临时/固定密码仍正常。

### M1 checklist

- [x] patch-lab：`--patch-up-to R01` 17/17（历史；重验可在 2.18 再跑）
- [x] env：`"R01"`（2026-06-21 自 R03 拉回）
- [ ] **2.18 重验 patch-lab**（含 API 断言）：日期 ___________
- [ ] **GHA CI**：[Run 27889612169](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/27889612169)（2026-06-21，`r01-baixin-api`，含 `api_server`）
- [ ] **Release**：[`r01-baixin-api-20260621-012501`](https://github.com/jackadam1981/Custom-Rustdesk/releases/tag/r01-baixin-api-20260621-012501) → 本地 `downloads/R01-27889612169/`
- [ ] **Windows exe**：网络 4 项 + API + preset 超级密码

---

## M2 — 定制判定（R03）**暂缓**

脚本：`patches/core/is-custom-client.sh` → `is_custom_client()` 增加 `app-name` / `custom-customer-name` builtin 判定。

- [x] patch-lab：`--patch-up-to R03` 19/19（step-verify-all 2026-06-20）
- [ ] env bump：`"R03"`（M1 重验通过后再 bump）
- [ ] CI：___________
- [ ] Release：___________
- [ ] exe：连接项与 M1 一致；产物源码含 `CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT`（UI 可见变化在 M5）

---

## M3 — 品牌（B02）**待做**

累计针：R01 R03 B01 B02。组末 bump：`"B02"`。

- [ ] patch-lab：`--patch-up-to B02`（verify 26/26）
- [ ] env bump：`"B02"`
- [ ] CI：run URL ___________
- [ ] Release：___________
- [ ] exe：托盘/应用图标、各平台显示名；MSI 安装路径仍为 `RustDesk`

依赖：`branding/` 目录 + `CUSTOM_RUSTDESK_REPO` / `GITHUB_WORKSPACE`（B02 已修）。

---

## M4 — 文案（I01）**待做**

累计针：… I01。组末 bump：`"I01"`。

- [ ] patch-lab：`--patch-up-to I01`（verify 28/28）
- [ ] env bump：`"I01"`
- [ ] CI / Release / exe：cn/en 定制字符串（Powered by、关于页署名等键）

---

## M5 — 双 UI（S13 或 F12）**进行中**

累计针：… F02 F10 F11 F12 S10 S12 S13。组末 bump：`"S13"` 或 `"F12"`（取组内最大 ID 即可）。

- [x] patch-lab：`--patch-up-to S13`
- [x] **ui-skill-verify.sh**（Sciter S1–S3 PASS）
- [x] env bump：`"S13"`
- [ ] CI / Release / exe — **Flutter**：
  - [ ] Flutter：首页 header、Powered by、关于页
  - [x] Sciter：首页 `#custom-brand`、Powered by、关于页 — **已固化 2026-06-28**
  - [x] Sciter：ID 三点配置菜单两列 + 80vh 滚动 — Run [28291552327](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/28291552327)
  - [ ] F11 锚点 `getConnectionPageTitle`（CRLF 安全，勿用纯 LF perl 锚）
  - [ ] F10 `loadIcon`：Tab 小图标与 logo 分离（见 `patches/flutter/home-logo.sh`）

---

## M6 — 平台（P04）**待做**

累计针：全部 16 针。组末 bump：`"P04"`。

- [ ] patch-lab：`--patch-up-to P04`（verify 51/51）
- [ ] env bump：`"P04"`
- [ ] CI / Release / exe：便携版工作目录、Windows 测试签名、MSI noop、rust-cache 非致命

---

## patch-lab 16 针静态预跑（CI 前门禁）

不编译；修脚本时用；失败可继续（`step-verify-all.sh`）或单档 `--patch-up-to`。

```bash
# 2.18 推荐
export PATCH_LAB_ROOT=~/patch-lab/custom-rustdesk   # 或 .patch-lab-test
bash scripts/patch-lab/step-verify-all.sh --profile baixin
```

**最近全量**：2026-06-20 — `PATCH_LAB_ROOT=.patch-lab-test` — **16/16 PASS**  
报告：`.patch-lab-test/step-verify-all-report.txt`

| ID | 静态 | verify | 归属 CI 档 | 备注 |
|----|------|--------|------------|------|
| R01 | PASS | 17/17 | M1 | 已固化 |
| R03 | PASS | 19/19 | M2 | |
| B01 | PASS | 19/19 | M3 | |
| B02 | PASS | 26/26 | M3 | branding 路径 |
| I01 | PASS | 28/28 | M4 | |
| F02 | PASS | 28/28 | M5 | |
| F10 | PASS | 32/32 | M5 | Flutter 首页 |
| F11 | PASS | 34/34 | M5 | CRLF 安全 |
| F12 | PASS | 38/38 | M5 | Flutter 关于 |
| S10 | PASS | 43/43 | M5 | Sciter 首页 — **已固化** |
| S12 | PASS | 46/46 | M5 | Sciter 关于 — **已固化** |
| S13 | PASS | 46/46 | M5 | 配置菜单 — **已固化** |
| P01 | PASS | 47/47 | M6 | |
| P02 | PASS | 48/48 | M6 | |
| P03 | PASS | 49/49 | M6 | |
| P04 | PASS | 51/51 | M6 | 全针 OK |

## 百信 profile 与 CI 触发

- **patch-lab profile**：`scripts/patch-lab/profiles/baixin.env`（含 `BUILD_API_SERVER`）
- **Issue 参数块（R01 重验）**：[`test_scripts/fixtures/baixin-r01-issue-body.txt`](../test_scripts/fixtures/baixin-r01-issue-body.txt)
- **GHA / 2.18 / Windows 分工**：见上文 § [验证环境与职责](#验证环境与职责)、§ [M1 重验三步](#m1-重验三步gha--218--windows)

```bash
# 2.18：单档预跑（例 M3 前）
bash scripts/patch-lab/run.sh --profile baixin --patch-up-to B02

# 2.18：GHA 触发（须带 api_server；用 gh workflow dispatch 或 Issue 队列）
```

CI 排错：主 run 的 `upstream-build` / `finish` 为准；macOS 可能仅制品上传 ENOTFOUND，Windows 编译仍可能成功。

## 相关文档

| 文档 | 内容 |
|------|------|
| [verification-rollout.md](./verification-rollout.md) | Rollout 开关、总流程、Q0 参数块 |
| [patch-lab.md](./patch-lab.md) | 2.18 patch-lab 操作手册 |
| [ui-customization.md](./ui-customization.md) | UI 验收清单（M5） |
| [Outline 插针规范](https://wiki.jackadam.top/doc/custom-rustdesk-cWWhzjEHzb) | 规范原文 |
