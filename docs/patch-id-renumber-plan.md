# 补丁 ID 重排方案

> 状态：**方案，未改任何代码**。执行需用户确认。
> 依据：`manifest.sh`、`orchestrator.sh`、git 历史（首版 `355103a` 2026-06-16、`b963668` 2026-06-18、`7e6aa62` 2026-07-01）。
> 相关文档：[customization-architecture.md](customization-architecture.md)（现状详解）、[patch-registry.md](patch-registry.md)（旧编号表）。

---

## 1. 现状诊断：空号从哪来

### 1.1 三类来源，都有据可查

| 空号 | 类型 | 证据 |
|---|---|---|
| **R02** | **确实存在过，后被合并** | 首版 manifest（`355103a`，2026-06-16）为 `R01 R02 R03`；`b963668`（2026-06-18，`refactor(patcher): merge connection patches into r01.sh`）把 `core/hbb-common.sh` 删掉并入 `r01.sh`，从此 R02 消失 |
| **F03–F09** | **从未存在**，是预留段 | 首版 manifest 即为 `F02 F10 F11 F12`。编号约定是"02 = 壳层/窗口，10+ = 首页组"，03–09 留给其它界面但一直没用 |
| **S01–S09** | **从未存在**，同上 | 首版为 `S10 S12 S13`，S10+ 直接对齐 Flutter 的 F10+ 语义 |
| **F11、S11 曾缺** | 后来补齐 | 2026-07-01 `7e6aa62` 把 `flutter/home-header.sh` 拆成 F10/F11/F12，把 `sciter/home-ui.sh` 改名为 `powered-by.sh`，同时补上 S11/S14/S15、F13/F14 |
| **N01、P0x** | 各自另起编号体系 | N = network lock（单针自成一体）；P = platform（P01–P05 从 01 顺排，但里面有 2 个死针、2 个改错目标） |

### 1.2 现有编号的四个实际问题

1. **字母段不表示层级**：R 混了"连接参数"和"客户端判定"，P 混了"Rust 库改动"和"CI 工作流改动"。
2. **数字不连续且无规律**：F02 → F10 → F13 是三个不同年代加的，外人无法从编号判断先后或归属。
3. **顺序即语义被隐藏**：`CUSTOM_VERIFIED_PATCH_UP_TO` 是按**索引**放行，但 ID 本身看不出谁在第几位。
4. **两处硬编码列表已经漂移**：[step-verify-all.sh#L52](file:///d:/My_Project/custom-rustdesk/scripts/patch-lab/step-verify-all.sh#L52) 只列了 20 个（缺 N01、P05），[run.sh#L38](file:///d:/My_Project/custom-rustdesk/scripts/patch-lab/run.sh#L38) 列了 23 个 —— 同一套 ID 在仓内已经有两个版本。

---

## 2. 新编号方案

### 2.1 规则

- **三位数字**：百位 = 层，十位 = 子组，个位 = 序号。
- **数字顺序 = 执行顺序**，这样 `UP_TO` 的"前缀语义"与"索引语义"继续一致。
- 每段 **01–09 为在用位，10–19 为预留位**，新增不用重排。
- 无字母后缀，避免"R/F/S/P"含义重叠。

| 段 | 层 | 说明 | 执行时机 |
|---|---|---|---|
| **1xx** | 配置注入（Rust 核心） | 往 `common.rs` / `hbb_common` / `lang` 写常量与默认值 | 最先 |
| **2xx** | 品牌与壳层 | 资源生成、安装身份（manifest/plist/desktop） | 早于 UI |
| **3xx** | 文案 | i18n 键 | 早于 UI |
| **4xx** | Flutter UI | 主界面 | 中 |
| **5xx** | Sciter UI | 32 位兜底界面 | 中 |
| **6xx** | 平台与打包 | Rust 平台库、CI 工作流 | 最后 |

> 1xx 内的执行顺序必须保持 `101 → 103 → 104`：R01 先写常量与 builtin，后续针才有锚点和值可读。

### 2.2 顺序一致性

新编号序列与当前编排顺序**逐位对应**，因此：

- `_custom_should_run_patch` 的索引比较逻辑**不用改**；
- `UP_TO="601"` 天然等于"全部启用"；
- 唯一变化是**索引基数从 23 变 18**（退役 5 个后），所有既有 `UP_TO` 字符串都要迁移（见 §5）。

---

## 3. 完整映射表（23 → 新编号）

| 旧 ID | 新 ID | 状态 | 脚本 | 目标上游文件 | 作用 |
|---|---|---|---|---|---|
| R01 | **101** | 在用 | `core/r01.sh` | `src/common.rs`、`libs/hbb_common/src/config.rs` | 连接参数/开关/客户信息注入（核心） |
| N01 | ~~102~~ | **退役**（占位保留） | `core/network_lock.patch.sh` | `src/common.rs` | 已被 101 的常量覆盖，永远跳过 |
| R03 | **103** | 在用 | `core/is-custom-client.sh` | `src/common.rs` | `is_custom_client()` 判定扩展 |
| P05 | ~~104~~ | **退役**（占位保留） | `core/super_password.patch.sh` | `src/common.rs` | 超密码，101 已实现且本针自跳过 |
| B01 | **201** | 在用 | `brand/brand-files.sh` | `AndroidManifest.xml`、`strings.xml`、`Info.plist`、`*.desktop` | 壳层显示名 |
| B02 | **202** | 在用 | `brand/logo-assets.sh` | `res/*`、`flutter/assets/*`、mipmap、AppIcon | logo/banner/icon 资源生成 |
| I01 | **301** | 在用 | `i18n/ui-strings.sh` | `src/lang/cn.rs`、`en.rs` | 文案键 |
| F02 | **401** | 在用 | `flutter/app-name.sh` | `flutter/lib/common.dart` | 窗口标题 |
| F10 | **402** | 在用 | `flutter/home-logo.sh` | `desktop_home_page.dart` | 首页 logo |
| F11 | **403** | 在用 | `flutter/home-title.sh` | 同上 | 首页标题 |
| F12 | **404** | 在用 | `flutter/home-slogan.sh` | 同上 | 首页 slogan |
| F13 | **405** | 在用 | `flutter/powered-by.sh` | `connection_page.dart`、`common.dart` | 连接页 Powered-by |
| F14 | **406** | 在用 | `flutter/about-studio.sh` | `desktop_setting_page.dart` | 关于页工作室行 |
| S10 | **501** | 在用 | `sciter/home-logo.sh` | `src/ui/index.tis`、`src/ui.rs`、`res/icon.png` | Sciter 首页 logo + icon handler |
| S11 | **502** | 在用 | `sciter/home-title.sh` | `src/ui/index.tis` | Sciter 首页标题 |
| S12 | **503** | 在用 | `sciter/home-slogan.sh` | `src/ui/index.tis` | Sciter 首页 slogan |
| S13 | **504** | 在用 | `sciter/powered-by.sh` | `src/ui/index.tis` | Sciter 连接页署名 |
| S14 | **505** | 在用 | `sciter/about-studio.sh` | `src/ui/index.tis` | Sciter 关于弹窗 |
| S15 | **506** | 在用 | `sciter/config-menu-css.sh` | `src/ui/index.css`、`index.tis` | 齿轮菜单样式 |
| P01 | **601** | 在用 | `platform/portable-workdir.sh` | `libs/portable/src/main.rs` | 便携版工作目录 |
| P02 | ~~611~~ | **退役**（占位保留） | `platform/windows-signing.sh` | 克隆树内 `.github/workflows/flutter-build.yml` | 测试签名，对真实构建无效 |
| P03 | ~~612~~ | **退役**（占位保留） | `platform/msi-noop.sh` | 无 | 空实现 |
| P04 | ~~613~~ | **退役**（占位保留） | `platform/rust-cache-nonfatal.sh` | 克隆树内 `.github/workflows/flutter-build.yml` | cache 容错，对真实构建无效 |

**结果**：23 → **18 个在用编号**，缺口集中在 102/104/611/612/613 五个占位（未来若恢复，无需再重排）。

**可选合并**（与编号方案兼容，不影响上表）：F10+F11+F12 → `402`、S10+S11+S12 → `501`，则总数 **14**，403/404/502/503 转为预留。

---

## 4. 影响面清单

### 4.1 必改（不改就断）

| # | 文件 | 位置 | 要改什么 |
|---|---|---|---|
| 1 | `.github/workflows/scripts/patches/manifest.sh` | L4–L11 | `CUSTOM_PATCH_IDS` 数组整体替换 + 新增别名表 |
| 2 | 同文件 | L49–L64 | `_custom_validate_source_patch_up_to` 的错误提示文案（示例 ID 变旧） |
| 3 | `.github/workflows/scripts/patches/orchestrator.sh` | L159–L186 | 23 次 `_custom_run_patch <ID>` 改为新 ID（顺序不变） |
| 4 | `.github/workflows/scripts/patches/load.sh` | 全文 | 无需改（按文件 source，不含 ID），仅确认注释 |
| 5 | `.github/verified-patches.env` | L16 示例、L44 注释、**L48 值** | `CUSTOM_VERIFIED_PATCH_UP_TO` 从 `P04` 改 `601`；L1–L42 的 21 行表格整体重写为新编号 |

### 4.2 补丁脚本内的自引用（marker / 日志 / 报错文案）

| 文件 | 需要改的地方 |
|---|---|
| `core/network_lock.patch.sh`、`core/super_password.patch.sh` | 退役后在 manifest 移除；脚本内日志含旧 ID（如保留则改为 102/104） |
| `core/r01.sh`、`core/is-custom-client.sh` | 日志与 marker 注释中的 `R01`/`R03` |
| `brand/logo-assets.sh`、`lib/sciter-brand.sh` | 错误文案里的 `B02` 等 |
| `flutter/about-studio.sh`、`home-logo.sh`、`home-title.sh`、`home-slogan.sh`、`powered-by.sh`、`app-name.sh` | 各脚本首部注释与 `raise SystemExit("... F10 ...")` 类文案 |
| `sciter/home-logo.sh`、`home-title.sh`、`home-slogan.sh`、`powered-by.sh`、`about-studio.sh`、`config-menu-css.sh` | 同上 |
| `platform/*.sh` | 退役 3 个；`portable-workdir.sh` 注释里的 P01 |

> 建议：脚本**文件名不改**（`r01.sh` 等），只改 ID 与文案。文件名不是契约，改名会让 git 历史与文档链接失效，收益为零。

### 4.3 CI 与本地工具

| # | 文件 | 位置 | 要改什么 |
|---|---|---|---|
| 6 | `.github/workflows/CustomBuildRustdesk.yml` | L80–L83 | `patch_up_to` 输入说明里的示例 `(R03/S12/S15…)` |
| 7 | 同文件 | L513–L519 | 无需改逻辑；日志会打印新 ID，确认可读 |
| 8 | `scripts/patch-lab/run.sh` | L30–L31、**L38**、**L193** | 帮助文案的示例 ID；L38 的 23 个 ID 顺序串；L193 的 `verify_up_to="P04"` |
| 9 | `scripts/patch-lab/step-verify-all.sh` | **L52** | 硬编码 ID 列表（当前 20 个，缺 N01/P05）改为新编号并补齐 |
| 10 | `scripts/patch-lab/verify.sh` | L162 | `verify_from F10` 改为新 ID |
| 11 | `.github/workflows/scripts/source-patcher.sh` | L10–L18 | `--only` / `--up-to` 的用法示例与校验调用 |

### 4.4 表单、测试、文档

| # | 文件 | 位置 | 要改什么 |
|---|---|---|---|
| 12 | `.github/ISSUE_TEMPLATE/custom-build.yml` | L32 | 文案里 `patch_up_to` 的说明（用户可能手填 ID） |
| 13 | `.github/ISSUE_TEMPLATE/q0-baseline.yml` | L11、L30 | `CUSTOM_VERIFIED_PATCH_UP_TO=""` 与 `patch_up_to` 的说明（值本身是空，不用改逻辑） |
| 14 | `run-tests.sh` + `test_scripts/*.sh` + `test_scripts/fixtures/*` | 全量 grep | 用例断言里的 ID（如 `workflow-tests.sh` 对 `CUSTOM_VERIFIED_PATCH_UP_TO` 的期望值）；fixtures 里触发体若含 ID 需同步 |
| 15 | `docs/patch-registry.md` | 全文 | 21 行旧表 → 新表（并补 N01/P05 说明） |
| 16 | `docs/ui-customization.md` | L104–L127 | "补丁 ID"列 |
| 17 | `docs/experiment-verification.md` | 台账各条 | 历史记录建议**保留旧 ID 并加注新 ID**，不要改写历史结论 |
| 18 | `docs/verification-rollout.md`、`docs/patch-lab.md`、`docs/workspace-handoff.md`、`docs/gitea-migration-plan.md`、`docs/repo-slimming-plan.md`、`docs/customization-architecture*.md` | 全量 grep | 提及 ID 处 |
| 19 | `.cursor/rules/custom-rustdesk-handoff.mdc`、`CLAUDE.md`、`README.md` | 全量 grep | 交接说明里的 ID |
| 20 | `scripts/patch-lab/profiles/*.env` | 5 个 profile | 当前未见 `patch_up_to` 字段，确认无 ID 后跳过 |

### 4.5 只读、无需改

- **git 历史与 commit message**：不改写（`rebase`/`filter-repo` 会破坏迁移验收口径）。
- **历史 tag**：tag 名形如 `ui-vm-20261111a`，不含补丁 ID，无需处理。
- **历史 Release / Issue 正文**：保留旧 ID，在映射表里可查即可。

---

## 5. 兼容与迁移

### 5.1 别名表（推荐）

在 `manifest.sh` 顶部加一张静态映射，解析统一走它：

```
CUSTOM_PATCH_ID_ALIASES=(
    "R01=101" "R03=103" "B01=201" "B02=202" "I01=301"
    "F02=401" "F10=402" "F11=403" "F12=404" "F13=405" "F14=406"
    "S10=501" "S11=502" "S12=503" "S13=504" "S14=505" "S15=506"
    "P01=601"
    "N01=102" "P05=104" "P02=611" "P03=612" "P04=613"
)
```

解析顺序：`参数 → 别名归一 → 校验是否在 CUSTOM_PATCH_IDS → 比较索引`。

- 命中别名时打印 `⚠️ 旧 ID N01 已改为 102（已退役）`；
- 归一后指向退役 ID → **直接报错**，不要静默忽略（否则有人以为打了针）；
- 未知 ID → 沿用现有 fail-loud 行为。

### 5.2 旧值迁移

| 旧 `UP_TO` | 新值 | 备注 |
|---|---|---|
| `""`（零针） | `""` 不变 | Q0 基线不受影响 |
| `R01` | `101` | |
| `S15` / `P04`（全量） | `601` | 旧值都指向"最后一个在用针"，语义等价 |
| `F10` / `S10` 等切片值 | 查 §3 表 | 若指向退役 ID（如 `P02`）→ 报错并人工确认 |

> 别名只解决"字符串还能识别"，**不解决索引语义**：把 `F10` 归一成 `402` 后，放行范围会自然包含 101/201/301 等前置针——这与旧行为一致（旧 `F10` 也放行 R01…F02）。这一致性是新编号保持执行顺序的直接收益。

### 5.3 是否改成白名单（可选）

彻底摆脱索引依赖：`CUSTOM_VERIFIED_PATCH_UP_TO` 改为 `CUSTOM_VERIFIED_PATCHES="101,103,201,..."` 白名单，保留 `UP_TO` 作为兼容入口。代价是 manifest 多一层解析，收益是以后插针/删针不再影响放行语义。**建议与本次重排一起做，否则下次增删又要迁移一次。**

---

## 6. 风险与执行

### 6.1 风险

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| 1 | **上限开关语义被破坏**：`UP_TO` 存的是索引，任一 ID 增删都会漂移 | **高** | 一次性完成重排；别名表 + 迁移表；建议顺带换白名单 |
| 2 | 有人从旧笔记/secret/Issue 里填旧 ID | 中 | 别名表兼容；退役 ID 报错而非跳过 |
| 3 | `step-verify-all.sh` 的 ID 列表本就少 2 个，重排时容易照抄错的 | 中 | 以 `manifest.sh` 为唯一真源，脚本里改成从 manifest 读取而非硬编码 |
| 4 | 文档/测试里的 ID 漏改，CI 绿但本地工具报错 | 中 | §4 清单逐项 grep 清零；`git grep -E "\b(R0[1-3]|F1[0-4]|S1[0-5]|P0[1-5])\b"` 只允许出现在映射表与历史文档 |
| 5 | 历史 tag / Release 说明与新编号对不上 | 低 | 保留 `docs/patch-registry.md` 的新旧对照表；不改写历史 |
| 6 | 分批改导致"半新半旧"编号共存 | 中 | 必须**一次性一个 commit 完成**；分批只在"改代码 → 改文档 → 改测试"之间，不能跨越 manifest 与 orchestrator |
| 7 | 合并（可选）导致失败爆炸半径变大 | 中 | 与重排**分两个 commit**，先重排验证通过再合并 |

### 6.2 执行顺序（一次性）

1. 改 `manifest.sh`：新数组 + 别名表 + 解析函数；
2. 改 `orchestrator.sh` 的 23 次调用（顺序不动）；
3. 改 `verified-patches.env` 的值与表格；
4. 改 6 个补丁脚本内的日志/marker 文案（含 4 个退役脚本的处置）；
5. 改本地工具：`run.sh` L38/L193、`step-verify-all.sh` L52、`verify.sh` L162；
6. 改 CI 说明与 Issue 表单文案；
7. 改测试断言与 fixtures；
8. 改文档（registry 表 + 各文档 ID 引用）；
9. 全量 grep 收敛；
10. 验证（下节）通过后合入。

### 6.3 验证方式

| 验证 | 命令 | 覆盖什么 |
|---|---|---|
| 语法 | `bash -n` 全部改动脚本 | 语法错 |
| CI 逻辑 | `bash run-tests.sh` | manifest 校验、up_to 解析、workflow 断言 |
| **逐针锚点 + 幂等** | `scripts/patch-lab/step-verify-all.sh --profile baixin` | 每个 ID 前缀跑一次 + 对应 `PATCH_VERIFY_UP_TO` 断言，**这是唯一能覆盖全部补丁的检查**；执行前必须先把 L52 的列表改成新编号，否则会漏测 |
| 全量 | `SOURCE_PATCH_UP_TO=601 scripts/patch-lab/run.sh --profile baixin` 后 `verify.sh` | 全针叠加后无冲突、界面断言通过 |
| 幂等双跑 | 同一 profile 连续 apply 两次 | 第二次应全部命中 marker 跳过 |
| 残留扫描 | `git grep -n -E "\b(R0[1-3]|B0[12]|I01|F0[1-9]|F1[0-4]|S1[0-5]|P0[1-5])\b"` | 只允许出现在别名表与历史文档 |

---

## 7. 待确认

1. 是否采用 **101–6xx 三段数字** 方案（对比：保留字母前缀只做顺排）；
2. 是否同期退役 5 个死针（N01/P05/P02/P03/P04）→ 决定是 18 还是 23 个在用编号；
3. 是否同期做 F10–F12、S10–S12 合并 → 决定是 18 还是 14；
4. 是否把 `UP_TO` 换成白名单（建议是）；
5. 退役补丁脚本是删除还是保留占位（建议删除，需要的化从 git 历史取回）。
