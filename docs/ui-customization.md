# Custom RustDesk UI 定制要求

本文档说明 `custom-rustdesk` 仓库对 RustDesk 客户端 **界面与品牌** 的定制范围、构建参数、插针实现与验收方法。定制逻辑集中在 [`.github/workflows/scripts/source-patcher.sh`](../.github/workflows/scripts/source-patcher.sh)。

## 概述

- **Flutter 与 Sciter 两套桌面 UI 定制内容必须一致**（布局、字号、文案、链接行为对齐；**不分版本，两套 UI 同一规范**）。
- **`app_name` 仅影响 UI 显示名**：MSI 产品名、安装路径（`C:\Program Files\RustDesk\`）、服务名与注册表卸载项 **保持 RustDesk**，保证 `scripts/clean-rustdesk-windows.ps1` 可正常清理。
- **`logo_url` 建议填写**：未填则跳过 Logo 替换，界面仍显示 RustDesk 默认 Logo。

## 双 UI 统一规范（Flutter + Sciter）

以下要求 **Flutter**（`x86_64.exe` / MSI）与 **Sciter**（`x86-sciter.exe`）**必须一致**，无单独版本差异。

### 1. 首页左上角品牌区

| 项 | 要求 |
|----|------|
| 位置 | 首页左上角 |
| 第一行 | `logo_url` 图片 + `app_name`（Logo 与名称纵向或同行，以 patch 布局为准） |
| 第一行字号 | 与「控制远程桌面」标题 **相同** |
| 第二行 | `slogan`（换行显示） |
| 第二行字号 | 比「控制远程桌面」 **小 2 号** |
| 数据来源 | `logo_url` → Logo 资源；`app_name` → `app-name`；`slogan` → `custom-slogan` |

### 2. 连接页 Powered by（两套 UI 均有）

| 项 | 要求 |
|----|------|
| 位置 | 「控制远程桌面」卡片 **上方**（Flutter：`connection_page`；Sciter：`#powered-by` 在 `card-connect` 上方） |
| 适用范围 | **Flutter 与 Sciter 均须实现**，不是 Sciter 独有 |
| 文案 | `Powered by {customer}` / 中文 `由{customer}提供支持` |
| 字号 | 与「控制远程桌面」 **相同** |
| 点击 | 打开 `customer_link`（builtin `custom-customer-link`） |

### 3. 关于页工作室署名

| 项 | 要求 |
|----|------|
| 位置 | `Slogan_tip` **下方**新增一行 |
| 文案 | `本软件由郑州熵能科技工作室为 {customer} 倾情打造` |
| 链接 | 固定 `https://zzsn.work`（**不是** `customer_link`） |
| 排版 | 各行间距与原版关于页 **保持一致** |

### 4. 超级密码（`super_password`）

| 项 | 要求 |
|----|------|
| 性质 | 连接参数之一（preset / 超级密码），与 ID/中继/API/Key 同属 **R01** 插针 |
| 互不影响 | **不修改、不覆盖、不禁用** 客户端临时密码与固定密码的生成、显示与校验逻辑 |
| 选填 | **有则插针，无则跳过**，不强制传入 |
| 行为 | 传入时写入 `HARD_SETTINGS["password"]`（preset）；未传则不插针、不回落 secret 默认值 |
| Rollout | **R01**（`patches/core/r01.sh`，与 ID/中继/API/Key 同一针） |

### 5. MSI / 安装身份（不变）

| 项 | 要求 |
|----|------|
| 安装路径 | `C:\Program Files\RustDesk\` |
| 服务名 / 进程 | RustDesk |
| MSI 产品名 | RustDesk（`_custom_patch_msi_preprocess_app_name` 为 no-op） |
| 清理脚本 | 必须能识别并清理上述路径与服务 |

## 构建参数

通过 Issue（[`.github/ISSUE_TEMPLATE/custom-build.yml`](../.github/ISSUE_TEMPLATE/custom-build.yml)）或 Actions `workflow_dispatch` 传入。

| 参数 | 作用 | 默认 / 规则 |
|------|------|-------------|
| `customer` | 客户全称；Powered by、工作室署名中的 `{customer}` | 建议必填 |
| `app_name` | **界面显示名称**（可短于 customer） | 默认 = `customer` |
| `customer_link` | Powered by 点击链接 | 默认 `https://zzsn.work` |
| `logo_url` | 客户 Logo（URL 或仓库内路径） | 空 = 不换 Logo |
| `slogan` | 首页品牌区第二行文案 | 可空 |
| `super_password` | 超级密码（见上文 §4） | **选填** |
| `hide_network_settings` | 隐藏 ID/中继菜单与网络设置项 | `false` |
| `lock_network_settings` | 锁定网络/设置 | `false` |
| `rendezvous_server` | ID 服务器 | — |
| `relay_server` | 中继服务器 | 默认同 rendezvous 主机 |
| `rs_pub_key` | hbbs 公钥 | 空则用仓库 secret `DEFAULT_RS_PUB_KEY` |
| `api_server` | API 服务器 | 可空 |

插针完成后生成 `custom-build-config.json`，可作为产物审计依据。

## 插针顺序（Rollout）

R01（`r01.sh`）一次处理连接五项：`common.rs` 含超级密码 preset + `config.rs` 设置页预填。其后按 manifest 顺序 R03 → B01 → …

旧版 monolith 顺序（已拆分为独立针）：
3. `_custom_patch_brand_files`
4. `_custom_patch_flutter_ui_app_name`
5. `_custom_patch_logo_assets`（仅当 `logo_url` 非空）
6. `_custom_patch_custom_ui_text`（文案、Powered by、关于页、Flutter/Sciter 首页）
7. `_custom_patch_portable_working_dir`
8. `_custom_patch_windows_test_signing`
9. `_custom_patch_msi_preprocess_app_name` — **no-op**
10. `_custom_patch_rust_cache_nonfatal`

## 各 UI 面实现对照

### Flutter

| 区域 | 文件 / 标记 |
|------|-------------|
| 窗口标题 | `common.dart` → `app-name` |
| 首页品牌区 | `desktop_home_page.dart` → `CUSTOM_RUSTDESK_HOME_HEADER` |
| Powered by | `connection_page.dart`（「控制远程桌面」上方） |
| 关于页 | `desktop_setting_page.dart` → `CUSTOM_RUSTDESK_STUDIO_ATTRIBUTION` |
| Powered by 样式 | `common.dart` → `loadPowered` |

### Sciter

| 区域 | 选择器 / 标记 |
|------|---------------|
| 首页品牌区 | `#custom-brand` |
| Powered by | `#powered-by`（「控制远程桌面」/`card-connect` 上方，与 Flutter 对齐） |
| 关于页 | `studio-about` |

### 移动 / 桌面壳子

- Android：`strings.xml`、`AndroidManifest`
- iOS：`Info.plist`
- Linux：`.desktop` `Name=`

## 参考配置

### 郑州百信（测试用例）

```yaml
customer: 郑州百信科技有限公司
app_name: 郑州百信
customer_link: https://rustdesk.jackadam.top
logo_url: https://raw.githubusercontent.com/rustdesk/rustdesk/refs/heads/master/res/128x128.png
slogan: 科技提高效率
rendezvous_server: rustdesk.jackadam.top:21116
relay_server: rustdesk.jackadam.top:21117
rs_pub_key: <hbbs 公钥>
hide_network_settings: false
lock_network_settings: false
super_password: Jack@1993   # 选填；不传则跳过插针
```

构建标签示例：`baixin-test-20260615`

### OneCloud（历史参考）

```yaml
customer: OneCloud
app_name: OneCloudDesk
customer_link: https://rustdesk.jackadam.top
logo_url:
slogan: Powered by OneCloud Desk
rendezvous_server: rustdesk.jackadam.top:21116
relay_server: rustdesk.jackadam.top:21117
hide_network_settings: true
lock_network_settings: true
# super_password 可省略
```

## 验收清单

### 首页品牌区（Flutter + Sciter）

- [ ] 左上角显示 Logo + `app_name`
- [ ] `app_name` 字号 = 「控制远程桌面」
- [ ] 换行显示 `slogan`，字号小 2 号

### 连接页 Powered by（Flutter + Sciter）

- [ ] **两套 UI** 均在「控制远程桌面」上方显示 Powered by `{customer}`
- [ ] 字号 = 「控制远程桌面」
- [ ] 点击打开 `customer_link`

### 关于页（Flutter + Sciter）

- [ ] `Slogan_tip` 下方：「本软件由郑州熵能科技工作室为 {customer} 倾情打造」
- [ ] 链接为 `https://zzsn.work`
- [ ] 行间距与原版一致

### MSI / 清理

- [ ] 安装路径 `C:\Program Files\RustDesk\`
- [ ] `clean-rustdesk-windows.ps1 -Force` 可完整清理

### 超级密码（若传入）

- [ ] 超级密码可独立用于连接验证
- [ ] **临时密码、固定密码仍照常可用**，未被 super_password 插针影响
- [ ] 未传 `super_password` 时构建正常、无插针副作用

## 测试前准备

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\clean-rustdesk-windows.ps1 -Force
```

或双击 `scripts/clean-rustdesk-windows.cmd`。

## 常见问题

| 现象 | 可能原因 |
|------|----------|
| Flutter / Sciter 表现不一致 | 只 patch 了一套 UI 或未分别验收 |
| 某套 UI 缺少 Powered by | 应两套均有，检查 connection_page / `#powered-by` |
| Logo 仍是 RustDesk | `logo_url` 未填或下载失败 |
| 服务器地址不对 | 旧 `%APPDATA%\RustDesk` 配置未清理 |
| 关于页链接跳到 customer_link | 关于页应固定 `https://zzsn.work`；Powered by 仍用 `customer_link` |

## 相关文档

- [README.md](../README.md)
- [CLAUDE.md](../CLAUDE.md)
- Outline：[Custom RustDesk UI 定制要求](https://wiki.jackadam.top/doc/custom-rustdesk-ui-dRM122vA4Y)
