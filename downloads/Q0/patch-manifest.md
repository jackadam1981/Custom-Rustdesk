# Custom RustDesk 插针清单（16 针）

> **Q0 已固化**（2026-06-17）：Run [27700547234](https://github.com/jackadam1981/Custom-Rustdesk/actions/runs/27700547234)  
> 固化开关：`.github/verified-patches.env`  

| 序 | ID | 模块 | 上游目标 | 状态 |
|----|-----|------|----------|------|
| 1 | R01 | `patches/core/r01.sh` | `common.rs` + `config.rs`（连接五项：ID/中继/API/Key/超级密码） | **已验收** |
| 2 | R03 | `patches/core/is-custom-client.sh` | `is_custom_client()` | 待 R01 后 |
| 3 | B01 | `patches/brand/brand-files.sh` | 各平台显示名 | 未启用 |
| 4 | B02 | `patches/brand/logo-assets.sh` | logo / icon / tray | 未启用 |
| 5 | I01 | `patches/i18n/ui-strings.sh` | `cn.rs` / `en.rs` | 未启用 |
| 6 | F02 | `patches/flutter/app-name.sh` | `common.dart` | 未启用 |
| 7 | F10 | `patches/flutter/home-header.sh` | 首页 header | 未启用 |
| 8 | F11 | `patches/flutter/powered-by.sh` | Powered by | 未启用 |
| 9 | F12 | `patches/flutter/about-studio.sh` | 关于页 | 未启用 |
| 10 | S10 | `patches/sciter/home-ui.sh` | Sciter 首页 | 未启用 |
| 11 | S12 | `patches/sciter/about-studio.sh` | Sciter 关于 | 未启用 |
| 12 | S13 | `patches/sciter/config-menu-css.sh` | 配置菜单滚动 | 未启用 |
| 13 | P01 | `patches/platform/portable-workdir.sh` | 便携版目录 | 未启用 |
| 14 | P02 | `patches/platform/windows-signing.sh` | Windows 签名 | 未启用 |
| 15 | P03 | `patches/platform/msi-noop.sh` | MSI noop | 未启用 |
| 16 | P04 | `patches/platform/rust-cache-nonfatal.sh` | rust-cache | 未启用 |

## 验证顺序

`Q0` → `R01` → `R03` → … → `P04`

## 本地单针

```bash
scripts/patch-lab/run.sh --profile baixin --patch-up-to R01
```
