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
| app_name | OneCloudDesk |
| rendezvous_server | host:21116 |
| relay_server | host:21117 |
| rs_pub_key | （hbbs 公钥） |
| hide_network_settings | true |

## Secrets

在仓库 Settings → Secrets 中配置 `BUILD_TOKEN`、`ENCRYPTION_KEY` 及默认构建参数（见 workflow `env` 段）。

Windows 测试签名（可选）：`ONECLOUD_WINDOWS_PFX_BASE64`、`ONECLOUD_WINDOWS_PFX_PASSWORD`。
