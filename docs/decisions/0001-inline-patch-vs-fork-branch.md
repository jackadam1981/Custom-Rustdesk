# ADR-0001：内联补丁（B）取代 fork 分支方案（A）

- **状态**：已采纳（Accepted）
- **日期**：2026-11-13
- **决策范围**：定制 RustDesk 客户端的补丁交付方式与 CI 归属
- **相关文档**：[patch-registry.md](../patch-registry.md)、[patch-delivery-inline-vs-branch.md](../patch-delivery-inline-vs-branch.md)、[verification-rollout.md](../verification-rollout.md)、[patch-id-renumber-plan.md](../patch-id-renumber-plan.md)

---

## 1. 背景

历史上先后试过两条路，但**此前没有形成过正式决策**：仓库里没有 `docs/decisions/` 目录，也没有任何 ADR。现状是演进出来的，而不是当初选定的。可核实的事实是：

- 早期走**方案 A**：clone 上游源码 → 在源码树里打补丁 → 开 `custom-build-<run_id>` 孤儿分支推到本仓库（`custom-repo`）→ 由该分支的 push 事件触发**另一个 run**，用上游原版 `flutter-build.yml` 出包。
- 后来改成**方案 B**：仍在 clone 的源码树里打补丁，但不再建分支，而是把定制源码打成 artifact，由**本仓库同一 run** 的矩阵 job 覆盖 checkout 后编译；CI 编排由本仓库自己维护。

方案 A 的代码路径至今仍以 `use_source_branch` 调试开关保留，**默认关闭**（[CustomBuildRustdesk.yml#L84-L88](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L84-L88)）。默认走的是方案 B。

---

## 2. 两个方案

### 2.1 方案 A：fork / 临时分支 + 上游原版编译脚本

**做法**

1. 在克隆树里完成插针；
2. `git checkout --orphan custom-build-${run_id}` → `git add -A` → `git push custom-repo`；
3. 子 run 由 `push: branches: ["custom-build-*"]` 触发，直接执行分支树里的上游 `flutter-build.yml`；
4. 父 run 用 `gh run list/view` 轮询子 run，汇总各平台结果，最后删分支。

**优点**

- 子 run 的 checkout 本身就是定制源码，源码 / workflow / 注入内容随 ref 一起传递，不需要 artifact；
- 可以完全复用上游原版编译脚本，定制侧几乎不碰编译流程。

**缺点**

- **跨两个 run**：父 run 必须轮询、等待、汇总，失败面变大；单次构建时长被拉长。
- **依赖 git ref 当传输层**：孤儿分支与 `queue-locks/*` 锁 ref 都会在仓库留下自动分支；删除失败（权限 / API 异常）会残留 `custom-build-*`。
- **上游一改就 rebase**：为了让补丁命中上游 `flutter-build.yml` 等文件，需要持续跟进上游结构。

**当前残留证据**

- 开关与代码仍在：`use_source_branch`（默认 `false`）、`upstream-legacy` job、`git checkout --orphan custom-build-${run_id}`、`git push custom-repo`、`--branch "$SOURCE_BRANCH"` 反查子 run（[CustomBuildRustdesk.yml#L587-L616](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L587-L616)、[#L774-L801](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L774-L801)）。
- 自动分支名：`custom-build-<run_id>` 与 `queue-locks/*`（`REF_LOCK_PREFIX="queue-locks"`，[queue-manager.sh#L19](file:///d:/My_Project/custom-rustdesk/.github/workflows/scripts/queue/queue-manager.sh#L19)）。
- 根目录仍保留一份 `custom-rustdesk-upstream-build.yml`，供 `workflow_dispatch` 手动使用（真正被子 run 执行的是孤儿分支树里那份）。
- **P02 / P04 是方案 A 的直系痕迹**：它们直接在克隆树里改上游 `.github/workflows/flutter-build.yml`（测试签名、`continue-on-error` 容错）。这两针只有在 `use_source_branch=true` 的分支路径才真正影响执行；**默认内联路径下对构建无效**。在 2026-11 的 ID 重排中已退役，脚本删除，占位编号为 611 / 613（见 [patch-registry.md](../patch-registry.md#旧--新迁移表)）。

### 2.2 方案 B：克隆树内联补丁 + 本仓库自维护 CI（当前默认）

**做法**

1. `build` job clone 上游 → 在克隆树里执行 `source-patcher.sh` → 上传 `patched-source` artifact；
2. 同一 run 的 `upstream-matrix` 复用仓内 `flutter-build.yml`，每个 job 用 artifact 覆盖 checkout；
3. 补丁以 ID 注册表 + 白名单控制：当前 **18 个生效 ID**、1 个「已登记、暂不启用」（104）、4 个退役占位（102/611/612/613），合计 23 个注册位；实际补丁模块脚本 **19 个**（18 生效 + `super_password`）。

**优点**

- 单 run 内完成「补丁 → 编译 → 产物」，没有父子 run 轮询；
- 不依赖临时分支当传输层，仓库不残留 `custom-build-*`；
- 补丁按 ID 拆分，失败粒度细，patch-lab 可逐针做锚点与幂等验证；
- 多客户 profile 共用一个仓库（当前 5 份：`baixin`、`baixin-hide`、`baixin-lock`、`logo-only`、`onecloud`），换客户只换参数。

**缺点**

- 需要本仓库维护 CI 编排与上游 `flutter-build.yml` 的同步；
- 补丁是对上游源码的文本注入，上游结构变化仍会导致锚点失效（因此必须把「静默跳过」改成 fail，见 §4）。

---

## 3. 决策

**采纳方案 B（克隆树内联补丁 + 本仓库自维护 CI），方案 A 仅作为默认关闭的调试开关保留，不再作为交付路径。**

理由：

1. **多客户 profile 共用一个仓库**：5 份 profile 通过参数区分客户，不需要「一客户一 fork 分支」。
2. **补丁体系已有存量投入**：ID 注册表、白名单、逐针校验（`scripts/patch-lab/`）与 18 针 rollout 都是围绕内联方案建立的，切换到 fork 分支等于推倒重来。
3. **方案 A 的 rebase 成本随客户数增长**：每个分支都要跟随上游 `flutter-build.yml` 的结构变化；客户越多，维护面越大。内联方案只维护一份补丁与一份 CI。

---

## 4. 代价与必要补救（必须补，不是可选）

采纳 B 的同时，明确承认三项债务：

1. **锁上游 commit**：当前 CI 固定的是**分支**而不是 commit —— `RUSTDESK_REPO=rustdesk/rustdesk`、`RUSTDESK_BRANCH=master`，并 `git clone --depth 1 --branch master`（[CustomBuildRustdesk.yml#L102-L103](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L102-L103)、[#L473](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L473)）。上游 master 随时前进，补丁命中率不可复现。**补救：改为固定 commit SHA（或 tag），并记录该 SHA。**
2. **目标文件缺失必须 fail**：现状存在「锚点找不到就 skip」的路径（例如 `is_custom_client anchor not found ... skipping`）。内联方案下这会静默产出「看起来成功、实际没定制」的包。**补救：把静默跳过改成明确报错并终止该补丁。**
3. **用 `concurrency` 替掉 issue 队列与分支锁**：现在靠 Issue #1 队列 + `queue-locks/*` git ref 锁做串行化（[queue-manager.sh](file:///d:/My_Project/custom-rustdesk/.github/workflows/scripts/queue/queue-manager.sh)），复杂度高、失败面大。**补救：在 workflow 顶层加 `concurrency`，由 GitHub 原生串行化；`group` 名待设计。**

---

## 5. 事实边界

### 已核实（本次逐文件核对）

- `.github/workflows/` 下共 **9 个** workflow；**没有任何 workflow 配置顶层 `concurrency:` 键**（精确匹配 `^\s*concurrency\s*:` 无结果）。
- `CustomBuildRustdesk.yml` 的触发动作为 `issues: types: [opened]` 与 `workflow_dispatch`；方案 A 的子 run 走分支树内 `push: branches: ["custom-build-*"]`。
- 上游未锁 commit：`RUSTDESK_BRANCH: 'master'` + `--depth 1`。
- 方案 A 路径受 `use_source_branch`（默认 `false`）门控；P02/P04 只在该路径下改上游 workflow，默认内联路径不执行。
- 补丁注册位与脚本数见 §2.2（23 / 18 / 19），profile 5 份。

### 待核实

- **`concurrency` 的目标 `group` 名、以及是否需要在 job 级别再分层**：尚未设计，本文不写具体值。
- **方案 A 在 `use_source_branch=true` 下是否真的产出过与内联路径不同的包**：未做对照构建，本文只说「默认路径无效」，不断言 legacy 路径的实际产出差异。
- **上游 commit 锁的具体 SHA / 升级节奏**：尚未选定。
- **「目标文件缺失就静默跳过」的完整清单**：只确认了 `is_custom_client` 一例，其余补丁需逐针审计后才能给出全量列表。

---

## 6. 何时重新评估

出现以下任一情况时重新打开本 ADR：

1. **客户数量**增长到「一份 profile 不够用、需要按客户隔离补丁分支」的程度；
2. **上游结构变化**导致补丁锚点大面积失效，单次升级成本超过可接受范围；
3. **补丁维护成本**（逐针审计 + 每客户回归）超过切换到 fork 分支的 rebase 成本；
4. GitHub Actions 的 `concurrency` 或其他原生能力发生变化，使方案 A 的「跨 run 传输源码」不再有吸引力。
