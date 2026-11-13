# 工作区交接（Custom RustDesk）

> 换工作区 / 新会话请先读本文 + [experiment-verification.md](./experiment-verification.md)（分步实验）+ [verification-rollout.md](./verification-rollout.md) + [rustdesk-stack.md](./rustdesk-stack.md)（2.13 服务端）。

## 仓库与分支

| 项 | 值 |
|----|-----|
| 本地路径 | `D:\My_Project\custom-rustdesk` |
| GitHub | `jackadam1981/Custom-Rustdesk` |
| 主开发分支 | `codex/linux-appimage-actions-test` |
| `main` | 仅含 release 清理 workflow（`99-delete_releases.yml`） |

## 当前 rollout 状态

| 项 | 状态 |
|----|------|
| `CUSTOM_VERIFIED_PATCH_IDS` | **`101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601`**（18 针白名单；全量见 [`patch-registry.md`](./patch-registry.md)） |
| **Sciter UI** | patch-lab 已验 — 501–506（logo/名/slogan/powered/about/菜单） |
| **Flutter UI** | patch-lab 已验 — 402–406（同上控件对齐） |
| 本地静态 | `bash scripts/patch-lab/step-verify-all.sh --profile baixin`（18 针） |

### Sciter 验收记录（已固化）

| Release | Run | 验收项 |
|---------|-----|--------|
| `baixin-menu-20260627-20260627-140756` | [28291552327](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/28291552327) | 首页品牌、Powered by、关于 studio-about、三点菜单（后改 **单列+滚动**，见 506） |
| `baixin-logo-only-20260621-20260627-150957` | [28293035144](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/28293035144) | logo/icon 分离：仅 logo_url 时首页品牌正常、任务栏保持上游 |

本地包：`downloads/Baixin-28291552327/`、`downloads/Baixin-28293035144/`（Sciter `x86-sciter.exe`）。

## 本轮已合并修复（2026-06-20）

**Commit**：`a30be3f` — `fix(patch-lab): branding paths, CRLF powered-by, patch fail-fast`（提交当时的旧针编号见 `patch-registry.md` 迁移表）

1. **202** — `logo-assets.sh` 通过 `CUSTOM_RUSTDESK_REPO` / `GITHUB_WORKSPACE` 解析仓库内 `branding/`；`baixin.env` 改为 `branding/logo-...` 相对路径。
2. **405** — `powered-by.sh` 用 Python + `getConnectionPageTitle` 锚点注入，兼容上游 **CRLF**（Windows patch-lab clone）。
3. **Fail-fast** — `orchestrator.sh` 每针 `|| return 1`；CI `apply_custom_source_patches || exit 1`。
4. **step-verify-all.sh** — 失败继续 + 报告文件。

## 常用命令

```bash
# Windows：Git Bash，jq 需在 PATH
export PATCH_LAB_ROOT="D:/My_Project/custom-rustdesk/.patch-lab"

# 18 针全量静态（不编译）
bash scripts/patch-lab/step-verify-all.sh --profile baixin

# 单组
bash scripts/patch-lab/run.sh --profile baixin --patch-up-to 202

# 触发 CI（push 后）
gh workflow run "Custom Rustdesk Build Workflow" --ref codex/linux-appimage-actions-test
```

## 百信 profile

`scripts/patch-lab/profiles/baixin.env` — 桌面 **api_server 可选**（当前留空）；服务端 **21114 2.1 保留转发**（看在线终端）。

## RustDesk 自建栈（2.22）

服务端与运维：**[rustdesk-stack.md](./rustdesk-stack.md)** · **[Outline Wiki](https://wiki.jackadam.top/doc/rustdesk-222-nxus8Lz4rs)**。  
**策略：** 内网 **18444** 仅 `/_admin/` 管理；**不建议 Web Client**；外网 **21114、21115–21117**（21114 明文 API 看终端）。

## CI 排错备忘

- **主 workflow 成功、子 run 红**：仅在 `use_source_branch=true` 调试开关下才会出现 `custom-build-*` 分支触发的重复 upstream 构建；macOS 可能仅 `CreateArtifact ENOTFOUND`，**Windows 编译仍成功**。
- 默认单 run：看主 run 的 `upstream-matrix` / `upstream-build` / `finish`；调试开关打开时再看 `upstream-legacy`。
- 最近成功 Release 示例：`r01-baixin-lock-20260619-173618`。

## 插针顺序（18 针白名单）

`101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601`

详见 [`patch-registry.md`](./patch-registry.md)。脚本目录：`.github/workflows/scripts/patches/`（`source-patcher.sh` 为入口）。

## 产物目录（本地，未入库）

- 旧连接针验收包（见 git 历史）— 旧编号时代的 exe/msi
- `.patch-lab/` / `.patch-lab-test/` — patch-lab 工作区，可删后重建
