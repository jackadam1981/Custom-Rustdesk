# 补丁交付方式对照：内联 artifact（单 run） vs 临时分支（两 run）

本文只描述**仓库里实际存在的代码路径**，每条都给出文件与行号；不含推测性数字。分支方案目前由 `use_source_branch` 开关保留，默认关闭。

- 内联（当前默认）：`CustomBuildRustdesk.yml` 的 `build` job 把定制源码打包成 artifact，同一 run 的 `upstream-matrix` 复用 `flutter-build.yml`，每个 job 用 artifact 覆盖 checkout。
- 分支（旧方案）：`build` job 把定制源码推到 `custom-build-<run_id>` 孤儿分支，由 push 事件触发**另一个 run**，父 run 轮询等它结束。

---

## 1. 旧方案：临时分支补丁是怎么触发的

### 1.1 触发链（按执行顺序）

| 阶段 | 位置 | 实际动作 |
|------|------|----------|
| 生成子 workflow | [CustomBuildRustdesk.yml:527-569](../.github/workflows/CustomBuildRustdesk.yml#L527-L569) | 在 `rustdesk-source/` 里用 heredoc 写出 `.github/workflows/custom-rustdesk-upstream-build.yml`，其 `on:` 为 `push: branches: ["custom-build-*"]`，另带 `workflow_dispatch` 的 `upload-artifact`/`upload-tag` 两个输入 |
| 注入诊断 | [CustomBuildRustdesk.yml:561-563](../.github/workflows/CustomBuildRustdesk.yml#L561-L563) | 用 `perl -0pi` 直接改**分支树里的** `flutter-build.yml`，给 Android universal APK 那行加前后诊断与 60s 监控 |
| 建孤儿分支并推送 | [CustomBuildRustdesk.yml:587-616](../.github/workflows/CustomBuildRustdesk.yml#L587-L616) | `cd rustdesk-source` → `git checkout --orphan custom-build-${run_id}` → `git add -A` → `git push custom-repo custom-build-${run_id}`；输出 `branch_name` |
| 子 run 被 push 触发 | 分支树内的 `.github/workflows/custom-rustdesk-upstream-build.yml` | GitHub 读取**被 push 的 ref 里的** workflow 文件；job 只有一句 `uses: ./.github/workflows/flutter-build.yml` + `secrets: inherit` |
| 子 run 用哪份源码 | 同上 | `./` 解析到「被 dispatch 的 ref 树」= 这个孤儿分支，所以 `flutter-build.yml` 和整个 patched 源码都是分支里的那份；各 job 的 `actions/checkout` 直接拿到定制源码，**不需要 artifact** |
| 父 run 找子 run | [CustomBuildRustdesk.yml:797-814](../.github/workflows/CustomBuildRustdesk.yml#L797-L814) | `gh run list --workflow custom-rustdesk-upstream-build.yml --branch "$SOURCE_BRANCH" --limit 1 --json databaseId`，最多 30 次 × 10s |
| 父 run 等子 run | [CustomBuildRustdesk.yml:818-836](../.github/workflows/CustomBuildRustdesk.yml#L818-L836) | `gh run view <id> --json status` 每 60s 一次，上限 `6 * 60 * 60` 秒；结束后再取 `conclusion` |
| 父 run 收结果 | [CustomBuildRustdesk.yml:858-967](../.github/workflows/CustomBuildRustdesk.yml#L858-L967) | `upstream-build` job 用 `gh run view <子 id> --json jobs` 统计各平台 success/failure，写回 `platform_results` 等输出 |
| 父 run 收尾 | [CustomBuildRustdesk.yml:969-1082](../.github/workflows/CustomBuildRustdesk.yml#L969-L1082) | `finish` job 发通知、出队、释放双锁；`needs` 里包含 `upstream-legacy`，所以父 run 必须等子 run 结束后才结束 |
| 删分支 | [CustomBuildRustdesk.yml:1084-1090](../.github/workflows/CustomBuildRustdesk.yml#L1084-L1090) | `if: always()` + `gh api -X DELETE .../git/refs/heads/<branch>`；异常路径（权限、API 失败）会留下 `custom-build-*` 分支 |

补充两点事实：

- 仓库根目录也有一份 [custom-rustdesk-upstream-build.yml](../.github/workflows/custom-rustdesk-upstream-build.yml)，内容与 heredoc 基本一致（1-22 行）。真正被子 run 执行的是**被 push 进分支树的那份**；根目录这份只在默认分支上供 `workflow_dispatch` 手动用。
- 分支只能用 `run_id` 命名（`custom-build-${github.run_id}`），因为父 run 要靠 `--branch` 精确反查子 run；这也意味着同名冲突不是问题，冲突问题在别处（见 §3 的锁）。

### 1.2 `./` 解析到被 dispatch 的 ref 树，是**故意依赖**

不是巧合，也不是顺手写的：

1. 占位 workflow 是把 `uses: ./.github/workflows/flutter-build.yml` 写**进**源码树的（527-553），而不是留在本仓库；
2. 562 行的 perl 注入改的也是分支树里的 `flutter-build.yml`，如果子 run 用的是本仓库那份，这段注入等于白写；
3. 旧方案的整个收益就来自这一点：子 run 的 checkout 本身就是定制源码，省掉打包/解包，也不需要 artifact。

换句话说，分支方案等于**用 git ref 当传输层**：源码、workflow、注入内容一起进 ref，子 run 天然拿到一致的一棵树。

---

## 2. 内联方案：同一 run 内的 artifact 传递

| 阶段 | 位置 | 实际动作 |
|------|------|----------|
| 打包 | [CustomBuildRustdesk.yml:618-639](../.github/workflows/CustomBuildRustdesk.yml#L618-L639) | `rsync -a --exclude='.git' rustdesk-source/ patched-source-stage/` → `tar -czf patched-source.tar.gz` → `upload-artifact`，名字 `patched-source-${run_id}`，`include-hidden-files: true`，`retention-days: 1` |
| 为什么要 tar | 同上 627 行注释 | artifact 下载会丢文件权限位，用 tar.gz 保住可执行位 |
| 复用上游矩阵 | [CustomBuildRustdesk.yml:763-771](../.github/workflows/CustomBuildRustdesk.yml#L763-L771) | `upstream-matrix` 在**同一 run** 里 `uses: ./.github/workflows/flutter-build.yml`，`secrets: inherit` |
| 每个 job 覆盖源码 | `flutter-build.yml` 11 处 | `Restore patched source`（`download-artifact` 到 `${{ github.workspace }}`）+ `Extract patched source`（`tar -xzf ... -C .`），行号：124/130、432/438、617/623、767/773、1120/1126、1411/1417、1615/1621、1982/1988、2203/2209、2292/2298、2368/2374 |
| bridge 也要 | [bridge.yml:45-56](../.github/workflows/bridge.yml#L45-L56) | 两个 bridge matrix 项都先下载 + 解包 patched-source |
| 派生 VERSION | `flutter-build.yml` 12 处 | `Resolve VERSION from Cargo.toml` → `scripts/resolve-version.sh`；其中 [publish_unsigned:982-992](../.github/workflows/flutter-build.yml#L982-L992) 是只从 tar 里取 `./Cargo.toml` |
| 派生 vcpkg 基线 | `flutter-build.yml` 7 处 | `Resolve vcpkg commit from vcpkg.json baseline`（239、479、644、873、1153、1685、2006） |
| 清理 | [CustomBuildRustdesk.yml:1092-1104](../.github/workflows/CustomBuildRustdesk.yml#L1092-L1104) | `finish` job 用 `gh api` 删除 `patched-source-<run_id>` artifact |

---

## 3. 两条路的实际代价

| 维度 | 分支方案（两 run） | 内联方案（单 run） |
|------|--------------------|--------------------|
| **代码改动点** | 今天切回：`use_source_branch` 默认值 1 行（84-86）+ `publish_unsigned` 兼容 1 处 + 把近期 3 个修复带进分支树（见下）。**撤掉内联**则是 11×2 + 12 + 7 个步骤 + bridge 2 步 + publish 3 步，约 40 余处 | 现状即全部改动；若彻底删掉分支路径，可删约 170 行 workflow（527-569、587-616、690-717、774-836、1084-1090，以及 `source_branch` 输出与 5 处 `if`） |
| **每轮额外耗时** | 一次整棵源码树的 orphan push；一次子 run 排队/启动；找子 run 最多 30×10s，结束检测粒度 60s（最多多等 60s）。父 run 与子 run 的构建阶段不能重叠，墙钟 = 父 patching + 子全量构建 | 一次 tar.gz 上传；每个 job 多一次「下载 + 解包」。注意源码实际**传两遍**（`actions/checkout` 一遍 + artifact 一遍），但各 job 并行，墙钟只叠加单 job 那一步 |
| **失败排查难度** | 一个逻辑构建散在 2 个 run、2 套日志；父 run 只显示轮询，失败要先判断发生在父还是子，再跨 run 对时间线。子 run 的 workflow 来自分支树，看的是「那次 push 的版本」而不是当前分支 | 单个 run 一套日志，失败 job 直接可见；workflow 版本与当前分支一致 |
| **仓库是否留分支** | 会：`custom-build-*`（正常由 `if: always()` 删除，API 失败则残留）；另有队列 ref 锁 `queue-locks/*`（`REF_LOCK_PREFIX`，queue-manager.sh:19） | 不留分支；只留 1 天期的 artifact，finish 主动删 |
| **串行 / 并行** | 构建锁把全局构建串行化；且锁必须由**父 run**持有到子 run 结束（父 run 的 `needs` 含 `upstream-legacy`），所以锁的最长占用 = 父 run 等待上限 6h。子 run 本身不参与队列 | 构建锁同样全局串行，但只覆盖单 run；run 内 job 图天然并行 |
| **`./` 解析** | 故意依赖：解析到孤儿分支树，源码与 workflow 一起进 ref，省掉 artifact | 解析到当前 ref（本仓库），源码靠 artifact 覆盖 |

### 切回分支方案的真实工作量（重点）

分支树是 `git clone rustdesk/rustdesk`（`CustomBuildRustdesk.yml:473`）后只跑 `apply_custom_source_patches`，**不会**把本仓库 vendored 的 `flutter-build.yml` 复制进去（全仓 `CUSTOM_RUSTDESK_REPO` 只在 `brand/logo-assets.sh` 用）。因此切回后子 run 用的是上游 `flutter-build.yml` + 补丁脚本就地改出来的版本，以下三个近期修复**不会生效**，必须额外移植进分支树或补丁脚本：

1. i686 工具链：`--force-non-host` + `RUSTUP_TOOLCHAIN`（现只在 vendored 副本 442-462）；
2. linux aarch64 的 CMake ≥4.3 步骤（现只在 vendored 副本 1614-1630）；
3. VERSION / vcpkg 运行时派生（`resolve-version.sh`、`resolve-vcpkg-commit.sh`；`scripts/patches/` 下没有任何对应改动）。

另外 `publish_unsigned` 现在**无条件**下载 `patched-source-${run_id}`（982-986）并在分支模式下不存在该 artifact，切回时必须加分支判断、回落到 checkout 的 `./Cargo.toml`。

### `use_source_branch` 现在还在不在

在。定义在 [CustomBuildRustdesk.yml:84-86](../.github/workflows/CustomBuildRustdesk.yml#L84-L86)，默认 `false`；引用共 10 处：527、587、621、693、711、766、776、864、1093，以及 `build` job 的 `source_branch` 输出（368）。也就是说调度骨架**没有删**，切回只需打开开关 + 上述 3 处修复移植 + `publish_unsigned` 兼容，不需要重写触发/轮询逻辑。

---

## 4. 队列管理的沉没成本

### 4.1 `scripts/queue/` 8 个脚本的归属

| 脚本 | 职责 | 归属判断 | 内联方案下是否被调用（证据） |
|------|------|----------|------------------------------|
| `trigger.sh` | 解析 Issue / `workflow_dispatch` 参数、校验、回写 Issue | **issue 触发通用**（参数解析、Issue 清理，与补丁交付方式无关） | 是：[CustomBuildRustdesk.yml:131](../.github/workflows/CustomBuildRustdesk.yml#L131)、[228](../.github/workflows/CustomBuildRustdesk.yml#L228) |
| `review.sh` | 审批判定、服务器地址/参数复核、拒绝处理 | **issue 触发通用** | 是：[:204](../.github/workflows/CustomBuildRustdesk.yml#L204) |
| `issue-manager.sh` | GitHub Issue 读写、评论、关闭、权限检查 | **issue 触发通用** | 是：[:246](../.github/workflows/CustomBuildRustdesk.yml#L246)（并被 trigger/review/queue-manager 内部 source） |
| `issue-templates.sh` | 队列看板、审批/成功/失败/超时评论模板 | **队列通用**（模板服务于 Issue 流程，不涉及分支） | 是：[:244](../.github/workflows/CustomBuildRustdesk.yml#L244) |
| `debug-utils.sh` | 调试日志与 JSON 校验 | **通用基础设施** | 是：被 4 个主脚本 source（trigger.sh:6、review.sh:6、queue-manager.sh:6、finish.sh:6） |
| `encryption-utils.sh` | 参数加解密（队列数据存在 Issue #1 正文） | **队列通用** | 是：finish.sh:8；`finish` job 用它解密 build 参数 |
| `queue-manager.sh` | 入队、双锁（issue/build）、ref 锁、超期清理、构建锁获取 | **跨 run 串行化** | 是：[:297](../.github/workflows/CustomBuildRustdesk.yml#L297)（入队）、[:336](../.github/workflows/CustomBuildRustdesk.yml#L336)（取构建锁 + 清理队列）、[:994](../.github/workflows/CustomBuildRustdesk.yml#L994)（收尾释放） |
| `finish.sh` | 通知、出队、释放所有锁、版本号复位检查 | **收尾/跨 run 状态** | 是：[:993](../.github/workflows/CustomBuildRustdesk.yml#L993) |

结论（据实）：**没有一个脚本是分支方案专属**。对 `scripts/queue/` 全目录 grep `custom-build` / `source_branch` / `upstream` 均无命中；「等子 run、收子 run 结果、删分支」三件事全在 workflow（`CustomBuildRustdesk.yml` 的 `upstream-legacy` 与 `finish`），不在队列层。

时间线上队列层确实晚于分支方案出现：分支方案在 2026-06-08（`d37a240`、`6874650`），`scripts/queue/` 8 个脚本是 2026-06-17 一次性加入（`e93ad36`）。所以「当年为了分支方案多写了队列管理」这个印象，准确说法是：**分支方案让一份逻辑构建跨了两个 run，单 run 的 job 图再也无法保证「同一时间只有一份构建」，于是才需要 Issue #1 上的乐观锁做全局互斥。**

### 4.2 分支方案被队列层「加重」的那一处

`build` 锁由父 run 在 [wait-build-lock:333-357](../.github/workflows/CustomBuildRustdesk.yml#L333-L357) 获取，在 `finish` 释放（[:969-1082](../.github/workflows/CustomBuildRustdesk.yml#L969-L1082)），而 `finish.needs` 包含 `upstream-legacy`。于是：

- 分支模式下，锁的持有时间 = 父 run 等待子 run 的全部时间（上限 6h），而不是父 run 自己的构建时间；
- 父 run 超时/取消时，靠 `finish` 的 `if: always()` 兜底释放；这一步失败就直接变成「锁泄漏 → 后续构建排队到超时」；
- 队列清理 `_cleanup_queue` 需要 `gh run view` 判断队列里 run 是否还活着（queue-manager.sh:657-669），这是通用的队列卫生，但分支模式下一次任务有两个 run id，状态判断天然更绕。

### 4.3 两种选择的队列层工作量

- **切回分支方案**：队列层 **0 行改动**，能力全在；要补的是 §3 的 3 个修复移植 + `publish_unsigned` 条件，并额外承担「锁租期 = 子 run 时长」和「跨 run 排查」这两项长期成本。
- **继续内联**：队列层**不能瘦身**——issue 触发、审批、入队、双锁都还在用，8 个脚本一个都删不掉。能瘦的是 workflow 里分支专属的约 170 行（`upstream-legacy` 轮询、heredoc 生成、删分支、分支快照上传）。瘦掉之后少维护的是「两 run 的时序约定」，而不是队列脚本本身。

一句话说清这层差别：**分支方案的成本不只是多一个分支，而是多一层跨 run 调度——1 个任务散在 2 个 run、需要排队避免互相覆盖、需要外部收结果。** 实际维护代价是：锁的租期被拉长到子 run 的时长（父 run 的 6h 上限就是锁的最长占用）、失败要先分辨父/子再跨 run 对时间线、子 run 执行的是「那次 push 的」workflow 版本而不是当前分支。

---

## 5. 「每次升级都要重新拉一份官方 workflow 回来改造吗？」

### 5.1 我们这份 `flutter-build.yml` 与上游的关系

**是一次性 vendored 副本，靠人工手动同步，没有任何跟踪机制。**

| 事实 | 证据 |
|------|------|
| 文件是作为「仓内上游矩阵副本」引入的 | [README.md:9](../README.md#L9) 明确写 `# 仓内上游矩阵副本：同 run 编译 patched-source` |
| 同步方式写死为手动 | [README.md:23](../README.md#L23)：「上游矩阵副本变更需手动同步。」 |
| 引入时间 | `git log --follow` 只有 5 个提交：2026-06-08 `6874650`（引入）+ 2026-11-08 四次我们的改动（`0c2e710`、`95ee928`、`bfdc8cb`、`e243510`） |
| 没有定时 diff / 没有上游对照 CI / 没有记录同步 commit | `.github/workflows/` 下无任何 `schedule:`/`cron:`；全仓对 `rustdesk/rustdesk` 的引用只出现在克隆源码（`CustomBuildRustdesk.yml:473`）与 patch-lab，没有任何 workflow 去拉上游 `flutter-build.yml` 做比较 |
| CI 只保护「我们插的东西还在」，不发现「上游变了」 | [workflow-tests.sh:1056-1062](../test_scripts/workflow-tests.sh#L1056-L1062) 断言 `Restore patched source`/`tar -xzf`/artifact 名存在；[678-692](../test_scripts/workflow-tests.sh#L678-L692) 断言签名补丁；[1131](../test_scripts/workflow-tests.sh#L1131) 起按 job 断言。全部是「我们自己的不变量」 |

**上次同步到上游哪一版**：本地 `upstream_rustdesk/` 是 shallow clone（仅 10 个提交），HEAD 为 `eefd22b`（2026-07-26，`fix(macos): prevent remote keyboard focus leaks (#15629)`）。拿它的 `.github/workflows/flutter-build.yml` 与仓内副本逐行 diff：

- 仓内 2439 行，上游 2158 行，净增 281 行；
- 上游独有 22 行，且**全部是我们有意改掉的内容**（见 5.2 列表）；
- 也就是说：**仓内副本的基线等价于 `eefd22b`（2026-07-26）**，从 2026-06-08 引入到 07-26 之间上游这份文件没有产生需要我们合入的变更。仓库里没有记录这个同步点，以上是 diff 反推的结论；07-26 之后的上游变化本地无法测量（shallow）。

**「感知不到上游变了」确实是真问题，而且已经付过代价两次**：`VERSION: "1.4.9"` 与 `VCPKG_COMMIT_ID: "120deac..."` 都是 vendored 副本里的静态值，上游源码/打包端变了以后，我们是在**构建失败**时才发现（第四轮 appimage/sciter 找不到产物、第一轮 vcpkg `no version database entry`），不是在任何检查里发现。这两处现在已改成运行时派生（`resolve-version.sh`、`resolve-vcpkg-commit.sh`），但「上游改了矩阵/步骤」这一类变化仍然没有任何探测手段。

### 5.2 相对上游的改动面（量化）

上游 `eefd22b` → 仓内副本：**我们多 303 行、上游多 22 行，净 +281 行**。

上游独有的 22 行（均为有意反向修改，不是待合入的 drift）：

| 行数 | 内容 | 我们的处理 |
|------|------|-----------|
| 1 | 文件 BOM | 副本无 BOM |
| 9 | `VCPKG_COMMIT_ID: "120deac..."` + 8 行变更说明注释 | 删除，改由 `resolve-vcpkg-commit.sh` 运行时写 `$GITHUB_ENV` |
| 1 | `VERSION: "1.4.9"` | 删除，改由 `resolve-version.sh` 从 `Cargo.toml` 派生 |
| 7 | i686 的 `dtolnay/rust-toolchain` 块（`nightly-2023-10-13-${{ matrix.job.target }}`） | 换成 `rustup toolchain install --force-non-host` + `RUSTUP_TOOLCHAIN` |
| 8 | macOS `aarch64-apple-darwin` matrix 项 | 注释禁用（本 fork 无托管 macOS ARM runner） |

我们的插入（按 job / 步骤 / 行数）：

| 内容 | 覆盖范围 | 行数 |
|------|----------|------|
| `Restore patched source` + `Extract patched source` + `Resolve VERSION` 三连块 | 11 个 job：`build-for-windows-flutter`、`build-for-windows-sciter`、`build-for-macOS`、`build-rustdesk-ios`、`build-rustdesk-android`、`build-rustdesk-android-universal`、`build-rustdesk-linux`、`build-rustdesk-linux-sciter`、`build-appimage`、`build-flatpak`、`build-rustdesk-web` | 11 × 17 = **187** |
| `Resolve vcpkg commit from vcpkg.json baseline` | 7 个 job：`build-for-windows-flutter`、`build-for-windows-sciter`、`build-for-macOS`、`build-rustdesk-ios`、`build-rustdesk-android`、`build-rustdesk-linux`、`build-rustdesk-linux-sciter` | 7 × 5 = **35** |
| `Ensure CMake >= 4.3 for vcpkg` | 1 个 job：`build-rustdesk-linux` | **17** |
| `publish_unsigned`：checkout + 下载 `patched-src` + 只解 `./Cargo.toml` + macOS aarch64 `continue-on-error` | 1 个 job | **约 21** |
| env 注释、i686 替换净增等 | — | **约 20** |

未插的 job 只有 3 个：`generate-bridge`（其 Restore 在 [bridge.yml:45-56](../.github/workflows/bridge.yml#L45-L56)）、`build-RustDeskTempTopMostWindow`（不编译 patched 源码）、`publish_unsigned`（只需要 `Cargo.toml`）。

**锚点及失配风险**：

| 插入块 | 锚点 | 上游改名/调序时是否易失配 |
|--------|------|--------------------------|
| Restore + Extract + Resolve VERSION | 紧跟 `- name: Checkout source code`（`submodules: recursive`） | 中等。全文件共 **12** 处该步骤名：11 处需要插，`publish_unsigned` 那处是我们自己加的、**不能插**。按「名字全匹配」注入会多插一次；按「首个匹配」注入只覆盖 1/11 |
| Resolve VERSION（publish 变体） | 紧跟「只解 `Cargo.toml`」那一步 | 低。锚点本身是我们写的，属内部锚点 |
| Resolve vcpkg | 锚在 vcpkg 安装步骤之前，但相邻形态有 3 种：5 处后接 `lukka/run-vcpkg@...`、1 处（1685 附近）后接带 `if:` 的条件步骤、1 处（2006，armv7 sciter）紧跟 `Modify vcpkg.json for armv7` | 高。上游一换 action 或调整步骤顺序就失配；单靠步骤名 `Setup vcpkg with Github Actions binary cache` 也不完全统一 |
| `Ensure CMake` | 放在 `build-rustdesk-linux` 的 `Install Rust toolchain` 之后 | 低（单点） |

### 5.3 自动 re-sync 脚本可行吗

可行，形态建议是「拉取 → 按锚点插入固定片段 → 输出 diff 给人看」，不要自动提交。难点都在锚点：

1. **必须用步骤名/action 名匹配，不能用行号**；行号在上游任何一次改动后都会变（本次对比中，文件尾部两版的累计行号差已达 266 行）。
2. **必须「全量匹配 + 次数断言」**：Restore 期望 11 次、vcpkg 期望 7 次。次数对不上就失败退出，而不是静默少插——少插的表现是某个平台悄悄编译了未打补丁的源码。
3. **需要 job 白/黑名单**：`publish_unsigned` 有 `Checkout source code` 但不需要 Restore（它只要 `Cargo.toml`）；`generate-bridge` 在另一个文件里。
4. **缩进要跟随锚点**：同一段步骤在不同 job 里可能处于不同嵌套层级，按文本块插入容易缩进错位，YAML 不报错但语义变了（例如被并进上一步的 `run:`）。
5. **该文件还有别的消费者**：`scripts/patches/platform/windows-signing.sh:62`、`rust-cache-nonfatal.sh:2` 也会就地改 `flutter-build.yml`；re-sync 后要连它们一起验证（`workflow-tests.sh:678-692`）。
6. **验证链**：`bash -n` 只能查脚本；YAML 语义、`uses:`、表达式要跑 `workflow-tests.sh`，最终仍需一轮真 CI。脚本能保证「步骤插对位置」，**不能**保证「上游新增了一个也需要 patched source 的 job」——这类语义变化只能靠人。

### 5.4 这一维度上分支方案的优势（也据实写）

分支模式下，子 run 执行的 `flutter-build.yml` 来自 `git clone rustdesk/rustdesk`（[CustomBuildRustdesk.yml:473](../.github/workflows/CustomBuildRustdesk.yml#L473)）后那棵源码树，即**上游原版 + `scripts/patches` 的就地修改**（例如 `windows-signing.sh`、`rust-cache-nonfatal.sh`）。

- 上游改矩阵、增删 job、升级 action：下一次 clone 自动拿到，**workflow 侧零改动**，不需要 vendored 副本、不需要 re-sync 脚本、不会出现「副本落后于上游」；
- 代价是把定制从「编辑 workflow 文件」改成「写补丁脚本」：我们那 3 个构建修复（i686 工具链、CMake 4.3、VERSION/vcpkg 派生）目前**不在** `scripts/patches` 里，切回分支必须先补成脚本（§3 已述），否则子 run 直接丢修复；
- 补丁脚本化之后，它们和上游升级解耦——这是分支方案在长期维护上的真实优势，不应该只写它的坏处。

换句话说：**内联把「跟踪上游」变成了「维护一份 fork 副本」；分支方案天然跟踪上游，但要求所有定制都以脚本补丁形式存在。**

## 6. 结论

**按长期维护成本排，推荐继续内联：可观测的 7 周窗口（2026-06-08 → 2026-07-26）里，上游这份 `flutter-build.yml` 没有产生任何需要我们合入的差异，手动同步是低频事件；而分支方案把这份「偶发的同步成本」换成了「每轮都多一层跨 run 调度」，后者是持续成本。**

补一句对策：真正该补的不是选择哪条路，而是**感知**——加一个只读脚本（拉指定 ref 的上游 `flutter-build.yml` 与仓内副本 diff 并打印），把「上游变了」从「构建失败时才知道」变成「同步时能看到」。
