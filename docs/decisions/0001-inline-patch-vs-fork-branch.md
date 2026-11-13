# ADR-0001：定制 RustDesk 的补丁交付方式（修订：A 为当前实现）

- **状态**：已修订（Amended，2026-11-14）。原文（2026-11-13）结论是「采纳方案 B（内联补丁 + 同 run 编译）」。经与 main 逐行核对，**main 实际执行的是方案 A（孤儿分支 + 上游原版编译脚本）**，本文按「改文档对齐代码」修订：主体描述 main 的真实行为，当初选择 B 的理由作为**历史决策记录**保留。
- **日期**：2026-11-13（原决策）／2026-11-14（修订）
- **决策范围**：定制 RustDesk 客户端的补丁交付方式与 CI 归属
- **相关文档**：[patch-registry.md](../patch-registry.md)、[patch-delivery-inline-vs-branch.md](../patch-delivery-inline-vs-branch.md)、[verification-rollout.md](../verification-rollout.md)、[patch-id-renumber-plan.md](../patch-id-renumber-plan.md)、[ADR-0002：A/B 未来工作量对比](./0002-ab-workload-estimate.md)

---

## 1. 现状：main 实际执行方案 A

### 1.1 job 链与数据流

`CustomBuildRustdesk.yml` 的 job 依次为：`trigger` → `review` → `join-queue` → `wait-build-lock` → `build` → `upstream-build` → `finish`（无同 run 的编译矩阵）。

1. `build` job：`git clone --depth 1 --branch master` 上游 → 执行 `source-patcher.sh` 插针 → 在克隆树里生成子 workflow `custom-rustdesk-upstream-build.yml`（其中 `upload-tag` 被替换成本次的 `BUILD_TAG`，如 `verify-<sha>-<timestamp>`）→ **无条件** `git checkout --orphan custom-build-<run_id>` → `git add -A` → `git commit` → `git push custom-repo`（[CustomBuildRustdesk.yml#L573-L604](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L573-L604)）。
2. 该分支的 push 事件触发子 run（workflow `custom-rustdesk-upstream-build.yml`，`on: push: branches: ["custom-build-*"]`），子 run 直接执行孤儿分支树里的**上游原版** `flutter-build.yml`，各平台 job 并行编译并发布到同一个 Release tag。
3. `upstream-build` job：用 `gh run list --workflow custom-rustdesk-upstream-build.yml --branch "$SOURCE_BRANCH"` 反查子 run → 轮询到结束 → 失败时用 `gh run rerun --failed` 只补跑失败 job（最多 2 次，2026-11-14 新增，[#L744-L824](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L744-L824)）→ 汇总各平台结果。
4. `finish` job：`gh api -X DELETE .../git/refs/heads/${{ needs.build.outputs.source_branch }}` 删除孤儿分支（[#L1036](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L1036)），并清理队列锁与 issue 队列。

### 1.2 与旧版 ADR 说法不符的事实

- **不存在 `use_source_branch`**：全文 0 处；`git log -S"use_source_branch"` 在本文件历史上也是 0 次——旧版 ADR 说「方案 A 已降级为默认关闭的调试开关」与代码不符。
- **不存在同 run 的内联编译矩阵**：`git log -S"upstream-matrix"` 为 0 次；当前 job 列表里也没有对应 job。
- **`patched-source` artifact 仍然上传，但没有消费方**：`build` job 会上传 `patched-source-<run_id>`（[#L675-L690](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L675-L690)），全仓检索不到下载该 artifact 的步骤，目前只起留存/审计作用，不参与编译。
- **根目录的 `.github/workflows/custom-rustdesk-upstream-build.yml`** 只在 `workflow_dispatch` 手动触发时使用；子 run 实际执行的是 `build` job 在孤儿分支树里生成的同名文件。

---

## 2. 两个方案（定义保留，B 标注为「当前未实现」）

### 2.1 方案 A：孤儿分支 + 上游原版编译脚本（**当前实现**）

**做法**：见 §1.1。

**优点**

- 子 run 的 checkout 就是定制源码，源码 / workflow / 注入内容随 ref 一起传递，不需要 artifact；
- 完全复用上游原版编译脚本，定制侧几乎不碰编译流程。

**缺点**

- **跨两个 run**：父 run 必须轮询、等待、汇总，失败面变大；
- **依赖 git ref 当传输层**：仓库会留下 `custom-build-*` 自动分支与 `queue-locks/*` 锁 ref，清理失败即残留；
- 上游结构变化需要持续跟进（补丁锚点 + 生成子 workflow 的 sed/perl 注入）。

### 2.2 方案 B：克隆树内联补丁 + 本仓库自维护 CI（**当前 main 未实现**）

**做法（历史设计）**：

1. `build` job clone 上游 → 插针 → 上传 `patched-source` artifact；
2. 同一 run 的编译矩阵 job 复用仓内 `flutter-build.yml`，用 artifact 覆盖 checkout 后编译；
3. 补丁以 ID 注册表 + 白名单控制（当前 18 个生效 ID、1 个「已登记、暂不启用」104、4 个退役占位 102/611/612/613，合计 23 个注册位；补丁模块脚本 19 个）。

**优点（当初的选择理由，见 §3）**

- 单 run 内完成「补丁 → 编译 → 产物」，无父子 run 轮询；
- 不依赖临时分支当传输层，仓库不残留 `custom-build-*`；
- 补丁按 ID 拆分，失败粒度细，patch-lab 可逐针做锚点与幂等验证；
- 多客户 profile 共用一个仓库（当前 5 份：`baixin`、`baixin-hide`、`baixin-lock`、`logo-only`、`onecloud`）。

**缺点**

- 需要本仓库维护 CI 编排与上游 `flutter-build.yml` 的同步；
- 补丁是对上游源码的文本注入，上游结构变化仍会导致锚点失效（必须把「静默跳过」改成 fail）。

> 说明：补丁体系（ID 注册表、白名单、patch-lab、5 份 profile）**与 A/B 选择无关**，在两种方案下都保留；差别只在「编译发生在同一 run 的矩阵里，还是由孤儿分支触发的子 run 里」。

---

## 3. 历史决策记录：2026-11-13 为什么写的是「采纳 B」

原文理由（保留，作为当时的判断，不代表当前实现）：

1. **多客户 profile 共用一个仓库**：5 份 profile 通过参数区分客户，不需要「一客户一 fork 分支」。
2. **补丁体系已有存量投入**：ID 注册表、白名单、逐针校验（`scripts/patch-lab/`）与 18 针 rollout 都是围绕内联方案建立的，切到 fork 分支等于推倒重来。
3. **方案 A 的 rebase 成本随客户数增长**：每个分支都要跟随上游 `flutter-build.yml` 的结构变化；客户越多，维护面越大。

这三点在今天仍然成立为**评估性理由**（详见 ADR-0002），但它们描述的是「应该选什么」，不是「代码现在是什么」。

---

## 4. 何时、因何改成了 A

从 git 历史可核实的演进：

| 日期 | commit | 事件 |
|------|--------|------|
| 2026-06-05 | `6fc508b` | 引入方案 B 的雏形：「Upload patched source artifact instead of remote dispatch」 |
| 2026-06-05 | `2a9cc67` | **改回 A**：把定制源码以「孤儿快照分支」推到本仓库。原因写在 commit message 里：直接推送带 `rustdesk/rustdesk` 上游父历史的分支，GitHub 在 Actions unpack 阶段会拒绝 |
| 2026-06-08 | `d37a240` | 编译 job 改为 checkout 定制分支：「Checkout custom source branch for compile jobs」 |
| 2026-06-18 | `8495b9e` | 加固 trigger 解析与补丁 rollout 校验；同 run 内联编译路径此时已不存在 |

**结论**：自 2026-06-18 起，main 的补丁交付路径只有方案 A。2026-11-13 写 ADR 时假设的「B 默认、A 由 `use_source_branch` 保留」在本仓库历史中从未成立。

---

## 5. 代价与必要补救

当前 A 路径下的三项债务（与原文一致，按实际路径校对）：

1. **锁上游 commit**：CI 固定的是分支而不是 commit —— `RUSTDESK_REPO=rustdesk/rustdesk`、`RUSTDESK_BRANCH=master`，`git clone --depth 1 --branch master`（[#L466](file:///d:/My_Project/custom-rustdesk/.github/workflows/CustomBuildRustdesk.yml#L466)）。上游 master 随时前进，补丁命中率不可复现。**补救：改为固定 commit SHA（或 tag），并记录该 SHA。**
2. **目标文件缺失必须 fail**：现状仍有「锚点找不到就 skip」的路径。A 路径下这会静默产出「看起来成功、实际没定制」的包。**补救：把静默跳过改成明确报错并终止该补丁。**
3. **队列与分支锁的复杂度**：串行化靠 Issue #1 队列 + `queue-locks/*` git ref 锁（[queue-manager.sh](file:///d:/My_Project/custom-rustdesk/.github/workflows/scripts/queue/queue-manager.sh)），而 A 路径又额外引入 `custom-build-*` 分支的创建/删除。**补救：评估用 workflow 顶层 `concurrency` 替代自建锁，减少「分支删除失败 → 残留 / rerun 无法解析 ref」这类问题。**

---

## 6. 事实边界

### 已核实（2026-11-14，逐文件 + git 历史核对）

- `build` job 无条件创建孤儿分支并 push（L573-604）；`upstream-build` 用 `--branch "$SOURCE_BRANCH"` 反查子 run（L744-764）；`finish` 用 git refs API 删除该分支（L1036）。
- `use_source_branch`、`upstream-matrix` 在本文件历史中 `git log -S` 均为 0 次。
- 没有任何 workflow 配置顶层 `concurrency:` 键。
- `patched-source` artifact 只有上传、没有下载方。
- 子 run 的 `upload-tag` 由父 run 的 `BUILD_TAG` 注入，多平台并发发布到同一个 Release tag；2026-11-13 曾因 Releases API 500 导致单个平台资产缺失（已由 `rerun --failed` 补跑机制覆盖）。

### 待核实

- **`concurrency` 的目标 `group` 名、以及是否需要在 job 级别再分层**：尚未设计。
- **上游 commit 锁的具体 SHA / 升级节奏**：尚未选定。
- **「目标文件缺失就静默跳过」的完整清单**：只确认了 `is_custom_client` 一例。

---

## 7. 何时重新评估

出现以下任一情况时重新打开本 ADR：

1. **客户数量**增长到「一份 profile 不够用、需要按客户隔离补丁分支」的程度；
2. **上游结构变化**导致补丁锚点大面积失效，单次升级成本超过可接受范围；
3. **补丁维护成本**（逐针审计 + 每客户回归）超过切换到 fork 分支的 rebase 成本；
4. GitHub Actions 的 `concurrency` 或其他原生能力发生变化，使 A 的「跨 run 传输源码」不再有吸引力；
5. **子 run 的失败面持续扩大**（例如多平台并发发布冲突频繁），需要考虑把编译搬回同一 run。

> 各变量（客户数量、上游活跃度、workflow 变更频率）的量化阈值与结论翻转点见 [ADR-0002](./0002-ab-workload-estimate.md)。该文状态为「评估中」，其估算结论以「B 为默认」为假设，**已被本文 §1 的事实修正**，仅作工作量参考。
