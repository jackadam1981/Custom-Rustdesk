# 插针注册表（Patch ID → 页面 → UI 控件）

本文档说明 **每一根 rollout 针** 管的是哪个 **页面**、哪个 **可见 UI 控件**（或等价的数据/资源/构建项）。  
插针脚本目录：`.github/workflows/scripts/patches/`；顺序以 [`manifest.sh`](../.github/workflows/scripts/patches/manifest.sh) 为准。

UI 视觉与字号等行为规范见 [`ui-customization.md`](ui-customization.md)。本地验证：`bash scripts/patch-lab/run.sh --profile baixin --patch-up-to <ID>`。

---

## 命名约定

| 前缀 | 含义 | 与 UI 关系 |
|------|------|------------|
| **R** | Rust 核心（连接默认、客户端识别） | 不直接改控件；影响设置页预填、网络菜单可见性等 |
| **B** | 品牌壳层 / 图片资源 | 为 UI 提供显示名与 `logo.png` 等素材 |
| **I** | i18n 文案 | 为 UI 提供 `translate(...)` 字符串 |
| **F** | Flutter 桌面 UI | 一针只碰 Flutter 树 |
| **S** | Sciter 桌面 UI | 一针只碰 Sciter 树 |
| **P** | 平台 / CI 构建 | 一般不是屏幕控件 |

**F 与 S 的顺号相同 = 同一逻辑控件**（例如 F10 与 S10 都是「首页 logo」）。  
Flutter 无对应控件时只保留 S 针（如 S15）；Sciter 无对应时不占 S 号。

当前共 **22 针**：`R01 R03 B01 B02 I01 F02 F10–F14 S10–S15 P01–P04`（**无 R02**）。

---

## 页面与控件总览（双 UI 对照）

```text
┌─ 全局 ─────────────────────────────────────────────────────────┐
│  F02  窗口标题栏 / 任务栏显示名（Flutter）                          │
│  B01  Android / iOS / Linux desktop 壳层名（非 Flutter 主界面）   │
├─ 首页（左栏品牌区）──────────────────────────────────────────────┤
│  F10 / S10   logo（48px）                                         │
│  F11 / S11   app 名（与 logo 同行）                                │
│  F12 / S12   slogan（品牌区第二行）                                │
├─ 首页（右栏 / 连接区上方）─────────────────────────────────────────┤
│  F13 / S13   Powered-by（「由 xxx 提供支持」）                      │
├─ 设置 → 关于（蓝底弹窗/区域）──────────────────────────────────────┤
│  F14 / S14   工作室 attribution 行（「倾情打造」）                  │
│  （上游保留 Copyright、Slogan_tip 两行，F14/S14 仅追加第三段）       │
├─ 首页 · 齿轮菜单（仅 Sciter）─────────────────────────────────────┤
│  S15   三点/齿轮 设置菜单：单列 + 可滚动                           │
└─ 非屏幕控件：R01 R03 B02 I01 P01–P04 ─────────────────────────────┘
```

---

## 逐针说明

### 核心（R）

| ID | 页面 / 范围 | UI 或行为 | 脚本 | 主要上游文件 |
|----|-------------|-----------|------|--------------|
| **R01** | 设置 → 网络 / ID；首次连接逻辑 | **非单一控件**：ID 服务器、中继、API、公钥、超级密码、锁定/隐藏网络设置（七项连接参数 + 设置页预填） | `core/r01.sh` | `src/common.rs`、`libs/hbb_common/src/config.rs` |
| **R03** | 全局（是否走定制 UI 分支） | **逻辑开关** `is_custom_client()`，不画控件 | `core/is-custom-client.sh` | `src/common.rs` |

---

### 品牌与文案（B / I）

| ID | 页面 / 范围 | UI 或行为 | 脚本 | 说明 |
|----|-------------|-----------|------|------|
| **B01** | 安装壳层 | 应用 **显示名**（Android `app_name`、iOS `CFBundleDisplayName`、`.desktop` `Name=`） | `brand/brand-files.sh` | 不改 Windows MSI 产品名（仍为 RustDesk） |
| **B02** | 素材库（多页面消费） | **非布局针**：生成 `flutter/assets/logo.png`、`res/logo.png`、banner、ico 等 | `brand/logo-assets.sh` | F10/S10 依赖 `logo.png`；`icon_url` 影响 Tab/托盘 |
| **I01** | 多页面（Powered-by、关于） | **文案键**：`powered_by_me`、`custom_studio_attribution`（cn/en） | `i18n/ui-strings.sh` | F13/S13、F14/S14 通过 `translate()` 引用 |

---

### Flutter UI（F）

| ID | 页面 | UI 控件 | 脚本 | 上游文件 | Marker / 识别 |
|----|------|---------|------|----------|---------------|
| **F02** | 全局 | **窗口标题**（标题栏显示 `app-name`） | `flutter/app-name.sh` | `flutter/lib/common.dart` `getWindowName` | `CUSTOM_RUSTDESK_UI_APP_NAME` |
| **F10** | **首页** · 左栏品牌区 | **Logo**（48px，`Image.memory` base64） | `flutter/home-logo.sh` | `flutter/lib/desktop/pages/desktop_home_page.dart` | `CUSTOM_RUSTDESK_HOME_ICON` |
| **F11** | **首页** · 左栏品牌区 | **App 名**（与 logo 同一 `Row`） | `flutter/home-title.sh` | 同上 | `), // CUSTOM_RUSTDESK_HOME_TITLE` |
| **F12** | **首页** · 左栏品牌区 | **Slogan**（品牌区第二行） | `flutter/home-slogan.sh` | 同上 | `CUSTOM_RUSTDESK_HOME_SLOGAN` |
| **F13** | **首页** · 右侧连接卡片上方 | **Powered-by** 一行（位置 + `loadPowered` 样式 + 客户链接） | `flutter/powered-by.sh` | `connection_page.dart`、`common.dart` | `CUSTOM_RUSTDESK_HOME_POWERED`、`CUSTOM_RUSTDESK_POWERED_STYLE` |
| **F14** | **设置 → 关于** · 蓝底区域 | **工作室行**（Copyright / Slogan 下游追加；含 `zzsn.work` 链接行为） | `flutter/about-studio.sh` | `flutter/lib/desktop/pages/desktop_setting_page.dart` | `CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION` |

**Flutter 首页品牌区依赖顺序：** B02 → F10 → F11 → F12（后针依赖前针 scaffold）。

---

### Sciter UI（S）

| ID | 页面 | UI 控件 | 脚本 | 上游文件 | Marker / 识别 |
|----|------|---------|------|----------|---------------|
| **S10** | **首页** · 左栏 `#custom-brand` | **Logo**（48px，`img.custom-rd-home-logo`） | `sciter/home-logo.sh` | `src/ui/index.tis` | `CUSTOM_RUSTDESK_SCITER_HOME_LOGO` |
| **S11** | **首页** · 左栏品牌区 | **App 名**（`.title`，与 logo 同行） | `sciter/home-title.sh` | 同上 | `CUSTOM_RUSTDESK_SCITER_HOME_TITLE` |
| **S12** | **首页** · 左栏品牌区 | **Slogan**（`.custom-rd-home-slogan`） | `sciter/home-slogan.sh` | 同上 | `custom-rd-home-slogan` |
| **S13** | **首页** · 右栏 `#card-connect` **上方** | **Powered-by**（`#powered-by.custom-rd-home-powered` + 点击 `custom-customer-link`） | `sciter/powered-by.sh` | 同上 | `custom-rd-home-powered` |
| **S14** | **关于** 弹窗（About） | **工作室行**（`studio-about`，在 `Slogan_tip` 下）+ 弹窗高度 | `sciter/about-studio.sh` | 同上 | `studio-about`、`CUSTOM_RUSTDESK_ABOUT_HEIGHT` |
| **S15** | **首页** · 右上角 **齿轮/三点菜单** | **设置菜单** 单列可滚动（非首页主内容区） | `sciter/config-menu-css.sh` | `src/ui/index.css`、`index.tis`（还原 popup） | `CUSTOM_RUSTDESK_CONFIG_MENU_FLOW` |

**Sciter 首页品牌区依赖顺序：** B02 → S10 → S11 → S12；S13 要求左栏品牌块内 **不得** 再含 `#powered-by`。

---

### 平台 / 构建（P）

| ID | 页面 | 说明 | 脚本 |
|----|------|------|------|
| **P01** | — | 便携版工作目录 | `platform/portable-workdir.sh` |
| **P02** | — | Windows 测试签名 | `platform/windows-signing.sh` |
| **P03** | — | MSI 预处理 app 名（noop/占位） | `platform/msi-noop.sh` |
| **P04** | — | Rust cache 失败非致命 | `platform/rust-cache-nonfatal.sh` |

---

## F ↔ S 同号速查

| 顺号 | 逻辑控件 | Flutter | Sciter |
|------|----------|---------|--------|
| 02 | 窗口/壳层显示名 | F02 | —（Sciter 读 builtin `app-name`） |
| 10 | 首页 logo | F10 | S10 |
| 11 | 首页 app 名 | F11 | S11 |
| 12 | 首页 slogan | F12 | S12 |
| 13 | Powered-by | F13 | S13 |
| 14 | 关于工作室行 | F14 | S14 |
| 15 | 齿轮设置菜单 | — | S15 |

---

## Rollout 顺序（完整）

```text
R01 → R03 → B01 → B02 → I01
→ F02 → F10 → F11 → F12 → F13 → F14
→ S10 → S11 → S12 → S13 → S14 → S15
→ P01 → P02 → P03 → P04
```

开关：`.github/verified-patches.env` 中 `CUSTOM_VERIFIED_PATCH_UP_TO`（空 = 零针）。  
旧编号迁移：原 **F11→F13**、**F12→F14**、**S10 大包→S10–S13**、**S12→S14**、**S13→S15**。

---

## 辅助模块（非 rollout ID）

| 路径 | 作用 |
|------|------|
| `patches/lib/common.sh` | json/xml/replace/trace 工具 |
| `patches/lib/sciter-brand.sh` | S10–S12 用 markup 片段生成（logo/title/slogan 字符串） |
| `patches/load.sh` | 按依赖顺序 `source` 各针 |
| `patches/orchestrator.sh` | 解析 `BUILD_*`、按 ID 调度各 `_custom_patch_*` |

---

## 相关文档

- [`ui-customization.md`](ui-customization.md) — 双 UI 视觉规范与 BUILD 参数
- [`patch-lab.md`](patch-lab.md) — 本地 clone → 插针 → 静态验证
- [`verification-rollout.md`](verification-rollout.md) — milestone bump 与 CI rollout
