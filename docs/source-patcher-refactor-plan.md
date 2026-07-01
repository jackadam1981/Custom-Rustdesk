# source-patcher.sh 工程化重构计划（历史归档）

> **已落地**：插针已拆至 `.github/workflows/scripts/patches/`。当前针 ID、页面与控件对照见 [`patch-registry.md`](patch-registry.md)。下文保留作重构过程记录。

> 目标：1600+ 行单文件 → 按 **patch ID / 函数 / MR** 三层拆分；定制逻辑只占少量文件，改一处不拖垮全局。

## 现状（约 1655 行）

| 区块 | 函数 | 行数约 | 问题 |
|------|------|--------|------|
| 工具 | `_custom_json_string` … `_custom_trace_file_match` | ~100 | 可复用，无问题 |
| Rust 核心 | `_custom_patch_common_rs` | ~155 | 独立，可保留 |
| Rust 配置 | `_custom_patch_hbb_common_config_rs` | ~120 | 独立 |
| 品牌文件 | `_custom_patch_brand_files` | ~25 | 独立 |
| Flutter 标题 | `_custom_patch_flutter_ui_app_name` | ~45 | 独立 |
| Logo 资源 | `_custom_patch_logo_assets` | ~135 | 独立 |
| Sciter 首页 | `_custom_sciter_*` + `_custom_patch_sciter_home_ui` | ~210 | 已从 UI 文本部分抽出，但仍与 orchestrator 耦合 |
| **UI 大杂烩** | `_custom_patch_custom_ui_text` | **~446** | i18n + Flutter 关于 + Sciter 关于 + Flutter 首页 + Powered by + 调用 Sciter 首页 |
| 便携目录 | `_custom_patch_portable_working_dir` | ~15 | 独立 |
| Windows 签名 | `_custom_write_*` + `_custom_patch_windows_test_signing` | ~90 | 可合并为单文件 |
| MSI / CI | `_custom_patch_msi_*` + `_custom_patch_rust_cache_*` | ~35 | 独立 |
| 客户端识别 | `_custom_patch_is_custom_client` | ~50 | 独立 |
| Sciter CSS | `_custom_patch_sciter_index_css` | ~50 | 独立 |
| About 收尾 | `_custom_patch_about_layout` | ~45 | 与 `custom_ui_text` 内 Flutter about **重复职责** |
| 入口 | `apply_custom_source_patches` | ~120 | 应瘦身为纯编排 |

**调用顺序（当前）** — 与 [`source-patcher.sh`](../.github/workflows/scripts/source-patcher.sh) 一致：

```
common_rs → hbb_common → brand_files → flutter_ui_app_name → logo_assets
→ custom_ui_text（内含 sciter_home_ui）
→ sciter_index_css → about_layout → is_custom_client
→ portable → windows_signing → msi → rust_cache
```

---

## 目标目录结构

```
.github/workflows/scripts/
├── source-patcher.sh              # 薄入口：解析 BUILD_*、写 config.json、source lib、调用 orchestrator
└── patches/
    ├── lib/
    │   ├── common.sh              # json/xml/replace/trace/bool（原 L5–101）
    │   └── sciter-brand.sh        # logo markup / brand block 纯函数（原 L585–621）
    ├── core/
    │   ├── common-rs.sh           # P-R01
    │   ├── hbb-common.sh          # P-R02
    │   └── is-custom-client.sh    # P-R03（原 is_custom_client，依赖 core 插完后 app-name builtin）
    ├── brand/
    │   ├── brand-files.sh         # P-B01 desktop/manifest 等
    │   └── logo-assets.sh         # P-B02
    ├── flutter/
    │   ├── app-name.sh            # P-F02
    │   ├── home-header.sh         # P-F10
    │   ├── powered-by.sh          # P-F11
    │   └── about-studio.sh        # P-F12（吞并 about_layout 逻辑）
    ├── sciter/
    │   ├── home-ui.sh             # P-S10 + P-S11（原 sciter_home_ui）
    │   ├── about-studio.sh        # P-S12
    │   └── config-menu-css.sh     # P-S13
    ├── i18n/
    │   └── ui-strings.sh          # P-I01 powered_by + studio 文案（cn/en）
    ├── platform/
    │   ├── portable-workdir.sh    # P-P01
    │   ├── windows-signing.sh     # P-P02
    │   ├── msi-noop.sh            # P-P03
    │   └── rust-cache-nonfatal.sh # P-P04
    └── orchestrator.sh            # apply_custom_source_patches 仅保留顺序与 gate
```

**约定**

- 每个 `patches/<area>/<name>.sh` **只 export 一个** `_custom_patch_*` 函数。
- 文件名 = patch ID 的物理落点；冻结状态仍写在个人技能 `patch-registry.md`（F10/S10…）。
- `source-patcher.sh` 保持 CI / patch-lab 的 **唯一 source 路径**（`source .../source-patcher.sh` 不变）。

---

## 函数拆分清单（旧 → 新）

| Patch ID | 新文件 | 新函数 | 从何处迁出 |
|----------|--------|--------|------------|
| — | `lib/common.sh` | `_custom_json_string` 等 8 个 | L5–101 |
| — | `lib/sciter-brand.sh` | `_custom_sciter_logo_img_markup` 等 3 个 | L585–621 |
| P-R01 | `core/common-rs.sh` | `_custom_patch_common_rs` | 原样搬迁 |
| P-R02 | `core/hbb-common.sh` | `_custom_patch_hbb_common_config_rs` | 原样搬迁 |
| P-R03 | `core/is-custom-client.sh` | `_custom_patch_is_custom_client` | 原样搬迁；**调用顺序移到 hbb_common 之后、UI 之前** |
| P-B01 | `brand/brand-files.sh` | `_custom_patch_brand_files` | 原样搬迁 |
| P-B02 | `brand/logo-assets.sh` | `_custom_patch_logo_assets` | 原样搬迁 |
| P-I01 | `i18n/ui-strings.sh` | `_custom_patch_i18n_ui_strings` | **新建** ← `custom_ui_text` L810–821 |
| P-F02 | `flutter/app-name.sh` | `_custom_patch_flutter_ui_app_name` | 原样搬迁 |
| P-F10 | `flutter/home-header.sh` | `_custom_patch_flutter_home_header` | **新建** ← `custom_ui_text` L980–1078 |
| P-F11 | `flutter/powered-by.sh` | `_custom_patch_flutter_powered_by` | **新建** ← `custom_ui_text` L1065–1237 |
| P-F12 | `flutter/about-studio.sh` | `_custom_patch_flutter_about_studio` | **新建** ← `custom_ui_text` L823–922 + **`about_layout` 合并** |
| P-S10/S11 | `sciter/home-ui.sh` | `_custom_patch_sciter_home_ui` | 原函数 + 从 `custom_ui_text` 末尾移除嵌套调用 |
| P-S12 | `sciter/about-studio.sh` | `_custom_patch_sciter_about_studio` | **新建** ← `custom_ui_text` L924–978 |
| P-S13 | `sciter/config-menu-css.sh` | `_custom_patch_sciter_index_css` | 原样搬迁 |
| P-P01 | `platform/portable-workdir.sh` | `_custom_patch_portable_working_dir` | 原样搬迁 |
| P-P02 | `platform/windows-signing.sh` | `_custom_patch_windows_test_signing` + `_custom_write_windows_sign_script` | 合并 |
| P-P03 | `platform/msi-noop.sh` | `_custom_patch_msi_preprocess_app_name` | 原样搬迁 |
| P-P04 | `platform/rust-cache-nonfatal.sh` | `_custom_patch_rust_cache_nonfatal` | 原样搬迁 |
| — | `orchestrator.sh` | `apply_custom_source_patches` | 仅编排 + 写 `custom-build-config.json` |

**删除**：`_custom_patch_custom_ui_text`、`_custom_patch_about_layout`（职责由上述函数承接）。

---

## 新 orchestrator 调用顺序

```bash
# patches/orchestrator.sh（apply_custom_source_patches 主体）

_custom_write_build_config_json   # 从入口迁出的 jq 块

# Core & identity（先写 builtin，再改 UI）
_custom_patch_common_rs
_custom_patch_hbb_common_config_rs
_custom_patch_is_custom_client      # 比现顺序提前：UI 插针依赖 isCustomClient 语义

# Brand & assets
_custom_patch_brand_files
_custom_patch_logo_assets

# i18n 文案（Powered by / studio 翻译键）
_custom_patch_i18n_ui_strings

# Flutter UI（单面单函数）
_custom_patch_flutter_ui_app_name
_custom_patch_flutter_home_header
_custom_patch_flutter_powered_by
_custom_patch_flutter_about_studio

# Sciter UI
_custom_patch_sciter_home_ui
_custom_patch_sciter_about_studio
_custom_patch_sciter_index_css

# Platform / CI 辅助
_custom_patch_portable_working_dir
_custom_patch_windows_test_signing
_custom_patch_msi_preprocess_app_name
_custom_patch_rust_cache_nonfatal
```

---

## MR 顺序（逐个合并，禁止打包）

每个 MR：**只动计划内的文件** + 对应 `verify.sh` / `workflow-tests` 断言 + patch-lab 全绿。

| MR | 标题 | 内容 | 验证门禁 |
|----|------|------|----------|
| **MR-00** | `chore(patcher): scaffold patches/ layout` | 建目录；`source-patcher.sh` 末尾 `source patches/lib/*.sh`；**函数仍留原文件 copy**，双路径 0 行为变化 | `bash -n` + `workflow-tests` + patch-lab 39/39 |
| **MR-01** | `refactor(patcher): extract lib/common.sh` | 工具函数迁出；原处改为 source | 同上 |
| **MR-02** | `refactor(patcher): extract core/*` | P-R01–R03 三文件 | verify 核心段 |
| **MR-03** | `refactor(patcher): extract brand/*` | P-B01–B02 | verify logo 段 |
| **MR-04** | `refactor(patcher): extract i18n P-I01` | 从 `custom_ui_text` 拆 `_custom_patch_i18n_ui_strings` | cn/en powered + studio 键 |
| **MR-05** | `refactor(patcher): extract flutter P-F02` | `app-name.sh` | F02 |
| **MR-06** | `refactor(patcher): extract flutter P-F10` | `home-header.sh` | F10 + **dart analyze** |
| **MR-07** | `refactor(patcher): extract flutter P-F11` | `powered-by.sh` | F11 |
| **MR-08** | `refactor(patcher): extract flutter P-F12` | `about-studio.sh`，删 `about_layout` | F12 |
| **MR-09** | `refactor(patcher): extract sciter P-S10/S11` | `sciter/home-ui.sh` + `lib/sciter-brand.sh` | S1–S2 ui-review |
| **MR-10** | `refactor(patcher): extract sciter P-S12` | `sciter/about-studio.sh` | S3 about 部分 |
| **MR-11** | `refactor(patcher): extract sciter P-S13` | `config-menu-css.sh` | S3 menu 部分 |
| **MR-12** | `refactor(patcher): extract platform/*` | P-P01–P04 | workflow-tests signing 段 |
| **MR-13** | `refactor(patcher): thin entry + delete monolith body` | `orchestrator.sh`；`source-patcher.sh` ≤80 行；**删除** `_custom_patch_custom_ui_text` | 全量 patch-lab + ui-review 13/13 + workflow-tests |
| **MR-14** | `feat(verify): per-patch verify targets` | `verify.sh --only F10` / `scripts/patches/verify/F10.sh` | 文档更新 |

> **UI 功能修复**（非纯搬迁）只允许在 **MR-06 及之后**、且 **一个 MR 只改一个 patch ID 的行为**。MR-00–05 禁止改插针逻辑。

---

## 每个 MR 的本地检查（2.18）

```bash
cd ~/custom-rustdesk && git pull
bash scripts/patch-lab/clean.sh
bash scripts/patch-lab/run.sh --profile baixin
bash test_scripts/workflow-tests.sh   # 或 run-tests.sh 子集
# Flutter MR（06+）额外：
cd ~/patch-lab/.../flutter && dart analyze lib/desktop/pages/desktop_home_page.dart ...
```

Windows 运行时签收：**仅当 MR 含 UI 行为变更**（非 MR-00–05 纯搬迁）时，在合并前抽测对应 exe。

---

## source-patcher.sh 瘦身后形态（目标）

```bash
#!/bin/bash
# Applies custom RustDesk source patches inside the cloned rustdesk source tree.

PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/patches" && pwd)"

# shellcheck source=patches/lib/common.sh
source "$PATCH_DIR/lib/common.sh"
# … source 各模块（或由 orchestrator 统一 source）

apply_custom_source_patches() {
  # BUILD_* → CUSTOM_* 归一化（保留在入口或 orchestrator 顶部）
  source "$PATCH_DIR/orchestrator.sh"
  _custom_apply_all_patches
}
```

CI / patch-lab **继续** `source .github/workflows/scripts/source-patcher.sh`，无需改 workflow。

---

## verify 工程化（MR-14）

```
scripts/patch-lab/verify/
├── all.sh          # 现有 verify.sh 薄包装
├── core.sh         # P-R*
├── flutter-F10.sh
├── flutter-F11.sh
├── sciter-S10.sh
└── ...
```

`run.sh` 默认跑 `all.sh`；开发单面时：`verify.sh --only F10`。

---

## 风险与规避

| 风险 | 规避 |
|------|------|
| 双份函数定义（搬迁过渡期） | MR-00–12 每步迁完即删原函数，不长期并存 |
| `source` 顺序错误 | orchestrator 单文件顺序即文档；单元测试 fixture 不变 |
| 纯搬迁 MR 仍触发 UI 回归 | MR-00–05 **禁止**改 perl/python 插针体 |
| Bash 3 / Windows checkout | 继续 bash + perl + python3，与 CI 一致 |

---

## 与 UI 技能的关系

| 技能 registry ID | 重构后物理文件 |
|------------------|----------------|
| F10 | `patches/flutter/home-header.sh` |
| F11 | `patches/flutter/powered-by.sh` |
| F12 | `patches/flutter/about-studio.sh` |
| S10/S11 | `patches/sciter/home-ui.sh` |
| S12 | `patches/sciter/about-studio.sh` |
| S13 | `patches/sciter/config-menu-css.sh` |

改 UI 时：**只打开对应文件** + 技能里的 verify 命令。

---

## 建议执行顺序（本周）

1. 评审本文档 → 确认 MR-00 可开 branch `refactor/patcher-scaffold`
2. 连做 **MR-00 → MR-03**（无 UI 行为变化，1–2 天）
3. **MR-04 → MR-11** 按表逐个 PR（每个含 patch-lab 截图/报告）
4. **MR-13** 删 monolith 前必须 ui-review 13/13
5. 冻结表（个人技能 `patch-registry.md`）随 MR 更新 🔒 状态

---

## 相关文档

- [UI 定制要求](ui-customization.md)
- [Patch Lab](patch-lab.md)
- 个人技能：`~/.cursor/skills/custom-rustdesk-flutter-ui/`、`custom-rustdesk-sciter-ui/`
