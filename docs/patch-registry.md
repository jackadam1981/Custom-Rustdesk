# 插针注册表（Patch ID → 页面 → UI 控件）

本文档说明 **每一根 rollout 针** 管的是哪个 **页面**、哪个 **可见 UI 控件**（或等价的数据/资源/构建项）。  
插针脚本目录：`.github/workflows/scripts/patches/`；顺序以 [`manifest.sh`](../.github/workflows/scripts/patches/manifest.sh) 为准。

UI 视觉与字号等行为规范见 [`ui-customization.md`](ui-customization.md)。本地验证：`bash scripts/patch-lab/run.sh --profile baixin --patch-up-to <ID>`。

> **2026-11 编号迁移**：旧字母编号（R/F/S/P/N）已重排为三位分层编号。旧 ID 仍可通过别名表解析（`R01`→`101` 等）；退役 ID 会明确报错。完整对照见文末「旧 → 新迁移表」。

---

## 命名约定

三位数字：**百位 = 层，十位/个位 = 顺序**；数字顺序 = 执行顺序（`SOURCE_PATCH_UP_TO` 按索引比较）。

| 段 | 层 | 说明 |
|----|----|------|
| **1xx** | 配置注入（Rust 核心） | 连接默认、客户端识别、超级密码；不直接画控件 |
| **2xx** | 品牌与壳层 | 显示名、logo/banner/icon 资源 |
| **3xx** | 文案 | i18n 键 |
| **4xx** | Flutter UI | 一针只碰 Flutter 树 |
| **5xx** | Sciter UI | 一针只碰 Sciter 树 |
| **6xx** | 平台与打包 | 便携目录、CI 工作流 |

当前 **23 个已注册 ID**，其中 **18 个在用**：

```text
101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601
```

另 5 个为占位：`102`（退役 N01）、`104`（P05，已登记、暂不启用）、`611/612/613`（退役 P02/P03/P04）。

---

## 页面与控件总览（双 UI 对照）

```text
┌─ 全局 ─────────────────────────────────────────────────────────┐
│  401  窗口标题栏 / 任务栏显示名（Flutter）                          │
│  201  Android / iOS / Linux desktop 壳层名（非 Flutter 主界面）   │
├─ 首页（左栏品牌区）──────────────────────────────────────────────┤
│  402 / 501   logo（48px）                                         │
│  403 / 502   app 名（与 logo 同行）                                │
│  404 / 503   slogan（品牌区第二行）                               │
├─ 首页（右栏 / 连接区上方）─────────────────────────────────────────┤
│  405 / 504   Powered-by（「由 xxx 提供支持」）                     │
├─ 设置 → 关于（蓝底弹窗/区域）──────────────────────────────────────┤
│  406 / 505   工作室 attribution 行（「倾情打造」）                 │
│  （上游保留 Copyright、Slogan_tip 两行，406/505 仅追加第三段）     │
├─ 首页 · 齿轮菜单（仅 Sciter）─────────────────────────────────────┤
│  506   三点/齿轮 设置菜单：单列 + 可滚动                           │
└─ 非屏幕控件：101 103 202 301 601 ─────────────────────────────────┘
```

---

## 逐针说明

### 1xx 配置注入

| ID | 页面 / 范围 | UI 或行为 | 脚本 | 主要上游文件 |
|----|-------------|-----------|------|--------------|
| **101** | 设置 → 网络 / ID；首次连接逻辑 | **非单一控件**：ID 服务器、中继、API、公钥、超级密码、锁定/隐藏网络设置（七项连接参数 + 设置页预填） | `core/r01.sh` | `src/common.rs`、`libs/hbb_common/src/config.rs` |
| **103** | 全局（是否走定制 UI 分支） | **逻辑开关** `is_custom_client()`，不画控件 | `core/is-custom-client.sh` | `src/common.rs` |
| ~~102~~ | — | **退役**（旧 N01）：常量已由 101 写入，脚本已删除 | — | — |
| ~~104~~ | — | **已登记、暂不启用**（旧 P05）：超级密码常量已由 101 写入；脚本保留 | `core/super_password.patch.sh` | `src/common.rs` |

### 2xx 品牌与壳层

| ID | 页面 / 范围 | UI 或行为 | 脚本 | 说明 |
|----|-------------|-----------|------|------|
| **201** | 安装壳层 | 应用 **显示名**（Android `app_name`、iOS `CFBundleDisplayName`、`.desktop` `Name=`） | `brand/brand-files.sh` | 不改 Windows MSI 产品名（仍为 RustDesk） |
| **202** | 素材库（多页面消费） | **非布局针**：生成 `flutter/assets/logo.png`、`res/logo.png`、banner、ico 等 | `brand/logo-assets.sh` | 402/501 依赖 `logo.png`；`icon_url` 影响 Tab/托盘 |

### 3xx 文案

| ID | 页面 / 范围 | UI 或行为 | 脚本 | 说明 |
|----|-------------|-----------|------|------|
| **301** | 多页面（Powered-by、关于） | **文案键**：`powered_by_me`、`custom_studio_attribution`（cn/en） | `i18n/ui-strings.sh` | 405/504、406/505 通过 `translate()` 引用 |

### 4xx Flutter UI

| ID | 页面 | UI 控件 | 脚本 | 上游文件 | Marker / 识别 |
|----|------|---------|------|----------|---------------|
| **401** | 全局 | **窗口标题**（标题栏显示 `app-name`） | `flutter/app-name.sh` | `flutter/lib/common.dart` `getWindowName` | `CUSTOM_RUSTDESK_UI_APP_NAME` |
| **402** | **首页** · 左栏品牌区 | **Logo**（48px，`Image.memory` base64） | `flutter/home-logo.sh` | `flutter/lib/desktop/pages/desktop_home_page.dart` | `CUSTOM_RUSTDESK_HOME_ICON` |
| **403** | **首页** · 左栏品牌区 | **App 名**（与 logo 同一 `Row`） | `flutter/home-title.sh` | 同上 | `), // CUSTOM_RUSTDESK_HOME_TITLE` |
| **404** | **首页** · 左栏品牌区 | **Slogan**（品牌区第二行） | `flutter/home-slogan.sh` | 同上 | `CUSTOM_RUSTDESK_HOME_SLOGAN` |
| **405** | **首页** · 右侧连接卡片上方 | **Powered-by** 一行（位置 + `loadPowered` 样式 + 客户链接） | `flutter/powered-by.sh` | `connection_page.dart`、`common.dart` | `CUSTOM_RUSTDESK_HOME_POWERED`、`CUSTOM_RUSTDESK_POWERED_STYLE` |
| **406** | **设置 → 关于** · 蓝底区域 | **工作室行**（Copyright / Slogan 下游追加；含 `zzsn.work` 链接行为） | `flutter/about-studio.sh` | `flutter/lib/desktop/pages/desktop_setting_page.dart` | `CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION` |

**Flutter 首页品牌区依赖顺序：** 202 → 402 → 403 → 404（后针依赖前针 scaffold）。

### 5xx Sciter UI

| ID | 页面 | UI 控件 | 脚本 | 上游文件 | Marker / 识别 |
|----|------|---------|------|----------|---------------|
| **501** | **首页** · 左栏 `#custom-brand` | **Logo**（48px，`img.custom-rd-home-logo`） | `sciter/home-logo.sh` | `src/ui/index.tis` | `CUSTOM_RUSTDESK_SCITER_HOME_LOGO` |
| **502** | **首页** · 左栏品牌区 | **App 名**（`.title`，与 logo 同行） | `sciter/home-title.sh` | 同上 | `CUSTOM_RUSTDESK_SCITER_HOME_TITLE` |
| **503** | **首页** · 左栏品牌区 | **Slogan**（`.custom-rd-home-slogan`） | `sciter/home-slogan.sh` | 同上 | `custom-rd-home-slogan` |
| **504** | **首页** · 右栏 `#card-connect` **上方** | **Powered-by**（`#powered-by.custom-rd-home-powered` + 点击 `custom-customer-link`） | `sciter/powered-by.sh` | 同上 | `custom-rd-home-powered` |
| **505** | **关于** 弹窗（About） | **工作室行**（`studio-about`，在 `Slogan_tip` 下）+ 弹窗高度 | `sciter/about-studio.sh` | 同上 | `studio-about`、`CUSTOM_RUSTDESK_ABOUT_HEIGHT` |
| **506** | **首页** · 右上角 **齿轮/三点菜单** | **设置菜单** 单列可滚动（非首页主内容区） | `sciter/config-menu-css.sh` | `src/ui/index.css`、`index.tis`（还原 popup） | `CUSTOM_RUSTDESK_CONFIG_MENU_FLOW` |

**Sciter 首页品牌区依赖顺序：** 202 → 501 → 502 → 503；504 要求左栏品牌块内 **不得** 再含 `#powered-by`。

### 6xx 平台 / 构建

| ID | 页面 | 说明 | 脚本 |
|----|------|------|------|
| **601** | — | 便携版工作目录 | `platform/portable-workdir.sh` |
| ~~611~~ | — | **退役**（旧 P02）：Windows 测试签名；仅 Legacy 分支路径曾生效，脚本已删除 | — |
| ~~612~~ | — | **退役**（旧 P03）：MSI 预处理 app 名（空实现），脚本已删除 | — |
| ~~613~~ | — | **退役**（旧 P04）：Rust cache 失败非致命；仅 Legacy 分支路径曾生效，脚本已删除 | — |

> **Legacy 路径说明**：611/613 修改的是克隆树内的 `.github/workflows/flutter-build.yml`。默认内联交付不使用该文件；仅 `use_source_branch=true`（默认 false）的旧分支路径会执行它。因此退役对默认生产路径无行为变化。

---

## 同一逻辑控件对照

| 逻辑控件 | Flutter | Sciter |
|----------|---------|--------|
| 窗口/壳层显示名 | 401 | 201（壳层） |
| 首页 logo | 402 | 501 |
| 首页 app 名 | 403 | 502 |
| 首页 slogan | 404 | 503 |
| Powered-by | 405 | 504 |
| 关于工作室行 | 406 | 505 |
| 齿轮设置菜单 | — | 506 |

---

## Rollout 顺序（完整）

```text
101 → 103 → 201 → 202 → 301
→ 401 → 402 → 403 → 404 → 405 → 406
→ 501 → 502 → 503 → 504 → 505 → 506
→ 601
```

开关：`.github/verified-patches.env` 中 `CUSTOM_VERIFIED_PATCH_IDS`（空 = 零针；当前为 18 个在用 ID）。  
调试：`patch_up_to`（`SOURCE_PATCH_UP_TO`）仍可用新 ID 或旧别名；`104` 已登记但不可调度。

---

## 旧 → 新迁移表

| 旧 ID | 新 ID | 状态 |
|-------|-------|------|
| R01 | 101 | 在用 |
| N01 | 102 | 退役 |
| R03 | 103 | 在用 |
| P05 | 104 | 已登记、暂不启用 |
| B01 | 201 | 在用 |
| B02 | 202 | 在用 |
| I01 | 301 | 在用 |
| F02 | 401 | 在用 |
| F10 | 402 | 在用 |
| F11 | 403 | 在用 |
| F12 | 404 | 在用 |
| F13 | 405 | 在用 |
| F14 | 406 | 在用 |
| S10 | 501 | 在用 |
| S11 | 502 | 在用 |
| S12 | 503 | 在用 |
| S13 | 504 | 在用 |
| S14 | 505 | 在用 |
| S15 | 506 | 在用 |
| P01 | 601 | 在用 |
| P02 | 611 | 退役 |
| P03 | 612 | 退役 |
| P04 | 613 | 退役 |

更早的 UI 针重编号：原 **F11→F13**、**F12→F14**、**S10 大包→S10–S13**、**S12→S14**、**S13→S15**；随后统一迁入本表。

---

## 辅助模块（非 rollout ID）

| 路径 | 作用 |
|------|------|
| `patches/lib/common.sh` | json/xml/replace/trace 工具 |
| `patches/lib/sciter-brand.sh` | 501–503 用 markup 片段生成（logo/title/slogan 字符串） |
| `patches/load.sh` | 按依赖顺序 `source` 各针 |
| `patches/orchestrator.sh` | 解析 `BUILD_*`、按 ID 调度各 `_custom_patch_*` |

---

## 相关文档

- [`ui-customization.md`](ui-customization.md) — 双 UI 视觉规范与 BUILD 参数
- [`patch-lab.md`](patch-lab.md) — 本地 clone → 插针 → 静态验证
- [`verification-rollout.md`](verification-rollout.md) — milestone bump 与 CI rollout
