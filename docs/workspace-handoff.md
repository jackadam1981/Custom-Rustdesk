# 工作区交接（Custom RustDesk）

> 换工作区 / 新会话请先读本文 + [experiment-verification.md](./experiment-verification.md)（分步实验）+ [verification-rollout.md](./verification-rollout.md) + [rustdesk-stack.md](./rustdesk-stack.md)（2.22 服务端）。

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
| `CUSTOM_VERIFIED_PATCH_UP_TO` | **`"S10"`**（M5 首页：Flutter 48px + Sciter S10，2026-06-21） |
| 本地 16 针静态 | **16/16 PASS**（2026-06-20，`.patch-lab-test/step-verify-all-report.txt`） |
| R01 CI + exe UI | 已验收（Run 27751270327 等）；**当前重验 R01** |
| M2 R03 | **暂缓** — env 已拉回 R01 |
| 下一 milestone | 重验 R01 通过后 → 再 bump `"R03"`（M2） |

## 本轮已合并修复（2026-06-20）

**Commit**：`a30be3f` — `fix(patch-lab): B02 branding paths, F11 CRLF powered-by, patch fail-fast`

1. **B02** — `logo-assets.sh` 通过 `CUSTOM_RUSTDESK_REPO` / `GITHUB_WORKSPACE` 解析仓库内 `branding/`；`baixin.env` 改为 `branding/logo-...` 相对路径。
2. **F11** — `powered-by.sh` 用 Python + `getConnectionPageTitle` 锚点注入，兼容上游 **CRLF**（Windows patch-lab clone）。
3. **Fail-fast** — `orchestrator.sh` 每针 `|| return 1`；CI `apply_custom_source_patches || exit 1`。
4. **step-verify-all.sh** — 失败继续 + 报告文件。

## 常用命令

```bash
# Windows：Git Bash，jq 需在 PATH
export PATCH_LAB_ROOT="D:/My_Project/custom-rustdesk/.patch-lab"

# 16 针全量静态（不编译）
bash scripts/patch-lab/step-verify-all.sh --profile baixin

# 单组
bash scripts/patch-lab/run.sh --profile baixin --patch-up-to B02

# 触发 CI（push 后）
gh workflow run "Custom Rustdesk Build Workflow" --ref codex/linux-appimage-actions-test
```

## 百信 profile

`scripts/patch-lab/profiles/baixin.env` — 桌面 **api_server 可选**（当前留空）；服务端 **21114 2.1 保留转发**（看在线终端）。

## RustDesk 自建栈（2.22）

服务端与运维：**[rustdesk-stack.md](./rustdesk-stack.md)** · **[Outline Wiki](https://wiki.jackadam.top/doc/rustdesk-222-nxus8Lz4rs)**。  
**策略：** 内网 **18444** 仅 `/_admin/` 管理；**不建议 Web Client**；外网 **21114、21115–21117**（21114 明文 API 看终端）。

## CI 排错备忘

- **主 workflow 成功、子 run 红**：`custom-build-*` 分支触发的重复 upstream 构建；macOS 可能仅 `CreateArtifact ENOTFOUND`，**Windows 编译仍成功**。
- 看 **主 run** 的 `upstream-build` / `finish`，不要只看 `Custom build for …` 子 run。
- 最近成功 Release 示例：`r01-baixin-lock-20260619-173618`。

## 插针顺序（无 R02）

`R01 R03 B01 B02 I01 F02 F10 F11 F12 S10 S12 S13 P01 P02 P03 P04`

脚本目录：`.github/workflows/scripts/patches/`（`source-patcher.sh` 为入口）。

## 产物目录（本地，未入库）

- `downloads/R01-27751270327/` — R01 验收 exe/msi
- `.patch-lab/` / `.patch-lab-test/` — patch-lab 工作区，可删后重建
