# Custom RustDesk

通过 GitHub Actions 拉取 [RustDesk](https://github.com/rustdesk/rustdesk) 上游源码、插针定制后编译客户端。

## 仓库结构

```
.github/workflows/CustomBuildRustdesk.yml   # 主 workflow（Issue / 手动触发）
.github/workflows/flutter-build.yml         # 上游 Flutter 构建占位，供内层 workflow 调用
.github/workflows/custom-rustdesk-upstream-build.yml
.github/workflows/99-delete_issues.yml        # 辅助：批量清理 Issues
.github/workflows/99-delete_workflow_runs.yml # 辅助：批量清理 workflow runs
.github/workflows/99-generate-aes-key.yml     # 辅助：生成 ENCRYPTION_KEY
.github/workflows/scripts/source-patcher.sh # 核心：对 RustDesk 源码插针
.github/workflows/scripts/*.sh              # 触发、队列、审批、收尾等 CI 辅助脚本
.github/ISSUE_TEMPLATE/custom-build.yml     # Issue 表单触发构建
```

定制逻辑集中在 `source-patcher.sh`：改 `.rs` / `.dart` / `.tis` / `preprocess.py` 等源码，尽量不改上游 workflow。

编译由 `upstream-build` job 触发内层 `custom-rustdesk-upstream-build.yml`（RustDesk 原版 `flutter-build.yml`）完成，本仓库不再维护自编 compile job。

## 触发构建

**手动**：Actions → Custom Rustdesk Build Workflow → Run workflow

**Issue**：按 `.github/ISSUE_TEMPLATE/custom-build.yml` 填写参数后提交 Issue。

常用参数示例：

| 字段 | 示例 |
|------|------|
| customer | OneCloud |
| app_name | OneCloudDesk（**仅 UI 显示名**；MSI/安装路径/注册表仍为 RustDesk） |
| rendezvous_server | host:21116 |
| relay_server | host:21117 |
| rs_pub_key | （hbbs 公钥） |
| hide_network_settings | true |
| logo_url | 客户 Logo 图片 URL（留空则用默认 RustDesk logo） |

## Windows 测试清理

便携版/MSI 混装时，MSI 可能提示 *self-installation method*。先以管理员运行：

```powershell
# 或双击 scripts/clean-rustdesk-windows.cmd
powershell -ExecutionPolicy Bypass -File .\scripts\clean-rustdesk-windows.ps1 -Force
```

脚本会清理 `--install` 自解压残留（`Uninstall` 注册表 `WindowsInstaller=0`）、服务、用户数据与便携目录，再装 MSI。安装身份始终为 **RustDesk**（`C:\Program Files\RustDesk\`、`rustdesk.exe`）；`app_name` 只影响界面显示，不改变 MSI 产品名。

## Secrets

在仓库 Settings → Secrets 中配置 `BUILD_TOKEN`、`ENCRYPTION_KEY` 及默认构建参数（见 workflow `env` 段）。

Windows 测试签名（可选）：`ONECLOUD_WINDOWS_PFX_BASE64`、`ONECLOUD_WINDOWS_PFX_PASSWORD`。

## 测试

| 环境 | 命令 | 说明 |
|------|------|------|
| 开发机 | `bash scripts/health-check.sh` | `bash -n` + workflow 结构轻量 grep，不调用 `gh`、不跑 fixture |
| 编译机 2.18 | `bash run-tests.sh workflow-tests` | workflow 结构 + source-patcher fixture 回归（需 `jq`） |
| 编译机 2.18（可选） | `bash run-tests.sh test-queue-reset && bash run-tests.sh test-manual-trigger` | 需 Janee/gh secrets 与 `BUILD_TOKEN` |

完整 `run-tests.sh all` 含真实 workflow 触发，**不要在 Windows 开发机运行**。

Health Stack 详情见 [CLAUDE.md](CLAUDE.md)。

UI 定制范围与验收清单见 [docs/ui-customization.md](docs/ui-customization.md)。
