# Patch Lab（2.18 编译机）

在 **192.168.2.18** 上对 **真实 RustDesk 上游源码** 做「干净 clone → 插针 → 静态验证」，与 CI `build` job 路径一致。全绿后再 `git push` 并 `gh workflow run` 触发编译（约 1 小时+）。

## 原则

- 每次测试前 **丢弃** 上次上游树，重新 `git clone rustdesk/rustdesk@master`
- 仅修改 `custom-rustdesk` 仓库内的 `source-patcher.sh`，不在上游树手工改文件
- Patch Lab **不编译** Rust/Flutter（太慢）；编译仍交给 GitHub Actions

## 目录布局

| 路径 | 说明 |
|------|------|
| `~/custom-rustdesk` | 本仓库 checkout |
| `~/patch-lab/custom-rustdesk/upstream/rustdesk-source` | 临时上游 clone（成功后删除） |
| `~/patch-lab/custom-rustdesk/out/` | 验证报告与关键插针文件快照 |

可通过 `PATCH_LAB_ROOT` 覆盖工作根目录。

## 依赖（2.18）

```bash
command -v git bash jq python3 perl curl
python3 -c "import PIL"   # pip3 install Pillow
```

## 常用命令

```bash
cd ~/custom-rustdesk
git pull

# 清理 upstream + out（推荐每次跑之前）
bash scripts/patch-lab/clean.sh

# 完整插针验证（默认郑州百信 profile）
bash run-tests.sh patch-lab

# 或直接
bash scripts/patch-lab/run.sh --profile baixin

# 失败保留上游树排查
bash scripts/patch-lab/run.sh --keep-on-fail
```

### 清理选项

```bash
bash scripts/patch-lab/clean.sh          # 仅删 upstream/ + out/
bash scripts/patch-lab/clean.sh --all    # 删除整个 PATCH_LAB_ROOT
```

## Profile

| 文件 | 用途 |
|------|------|
| [`scripts/patch-lab/profiles/baixin.env`](../scripts/patch-lab/profiles/baixin.env) | 郑州百信测试参数 |
| [`scripts/patch-lab/profiles/onecloud.env`](../scripts/patch-lab/profiles/onecloud.env) | OneCloud 参考 |

自定义：`bash scripts/patch-lab/run.sh --env-file /path/to/custom.env`

## 验证内容

[`scripts/patch-lab/verify.sh`](../scripts/patch-lab/verify.sh) 检查：

- `custom-build-config.json` 与 profile 一致
- Rust 核心插针（服务器、super_password、MSI 身份）
- Flutter / Sciter UI 标记（首页、slogan、Powered by、关于页 `zzsn.work`）
- `is_custom_client()` 使用 `app-name` builtin（`CUSTOM_RUSTDESK_IS_CUSTOM_CLIENT`）
- 关于页行距标记（`CUSTOM_RUSTDESK_ABOUT_LINE_HEIGHT`）

报告：`~/patch-lab/custom-rustdesk/out/verify-report.txt`

## 推荐门禁顺序

1. 开发机：`bash scripts/health-check.sh`（bash -n + 结构）
2. 2.18：`bash run-tests.sh workflow-tests`（fixture 回归）
3. 2.18：`bash run-tests.sh patch-lab`（真实上游）
4. commit + push + `gh workflow run`（全量编译）
5. Windows 抽测 exe / sciter UI

## 失败排查

- 查看 `out/verify-report.txt` 中 FAIL 项
- 使用 `--keep-on-fail` 保留 `upstream/rustdesk-source` 在 2.18 上 grep 对比
- 开启插针诊断：`BUILD_SOURCE_PATCH_DEBUG=true` 写入 profile

## 相关文档

- [UI 定制要求](ui-customization.md)
- [README.md](../README.md)
