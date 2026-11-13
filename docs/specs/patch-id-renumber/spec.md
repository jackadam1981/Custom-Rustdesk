# Spec：补丁 ID 重排（三位分段）+ 白名单放行

> 状态：**可执行**（无待确认项）。依据：已批准方案与逐文件核实。
> 分支：`chore/patch-id-renumber` → PR；不直推 main。
> 约束：manifest 与 orchestrator 及全部引用 **同一个 commit** 落地。

---

## 1. 最终决策（不再讨论）

| 项 | 决策 |
|---|---|
| 编号 | 1xx 配置注入 / 2xx 品牌壳层 / 3xx 文案 / 4xx Flutter / 5xx Sciter / 6xx 平台打包；数字顺序 = 执行顺序 |
| 退役 | N01→102、P02→611、P03→612、P04→613；删除脚本，别名表保留并报明确错误 |
| P05 | →104，保留脚本与功能，**白名单不包含**，注释「已登记、暂不启用」 |
| 合并 | 不合并 F10–F12、S10–S12；保持独立失败粒度 |
| CI 开关 | `CUSTOM_VERIFIED_PATCH_UP_TO` 删除，改为 `CUSTOM_VERIFIED_PATCH_IDS` 白名单 |
| 调试上限 | `SOURCE_PATCH_UP_TO` 保留，仅单次调试；旧 ID 自动归一化 |
| build-config | 保留 `verified_patch_up_to` 字段（写空），**新增** `verified_patch_ids`，不破坏既有消费者 |
| 文件名 | 补丁脚本文件名不改；只改 ID 与文案 |
| 退役脚本的 Legacy 影响 | 属实且已记录：P02/P04 仅在 `use_source_branch=true`（默认 false）路径生效；按批准退役 |

---

## 2. 白名单等价性证明

旧逻辑 `CUSTOM_VERIFIED_PATCH_UP_TO="P04"` 按索引放行 idx 0–21，实际调用 22 个：

```text
R01 N01 R03 B01 B02 I01 F02 F10 F11 F12 F13 F14 S10 S11 S12 S13 S14 S15 P01 P02 P03 P04
```

| 旧 ID | 实际效果 | 证据 |
|---|---|---|
| N01 | 无（自跳过） | `core/network_lock.patch.sh:15-18`；`core/r01.sh:81` 已写常量 |
| P03 | 无（`return 0`） | `platform/msi-noop.sh:1-4` |
| P02 | 默认内联路径无；Legacy 分支路径有 | `platform/windows-signing.sh:62` 改克隆树 workflow；`CustomBuildRustdesk.yml:547-548` Legacy 才执行分支树 workflow |
| P04 | 默认内联路径无；Legacy 分支路径有 | `platform/rust-cache-nonfatal.sh:2`；同上 |
| P05 | 旧逻辑未调用（idx 22） | `verified-patches.env:48` |

有效集合 18 个：

```text
R01 R03 B01 B02 I01 F02 F10 F11 F12 F13 F14 S10 S11 S12 S13 S14 S15 P01
```

新白名单 18 个，一一对应：

```text
101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601
```

**结论**：默认内联路径下，新白名单与旧 `UP_TO=P04` 的有效集合完全一致（一个不多一个不少）。N01/P03 零效果；P02/P04 仅在默认关闭的 Legacy 路径有差异，已在 `patch-registry.md` 与 PR 描述中披露。104 不入白名单，与旧逻辑一致。

---

## 3. 精确实现

### 3.1 `manifest.sh`（全文替换 L4–L64）

```bash
CUSTOM_PATCH_IDS=(
    101 103
    201 202
    301
    401 402 403 404 405 406
    501 502 503 504 505 506
    601
)

# 已登记、暂不启用：104 = super password（101 已写入该常量）
CUSTOM_REGISTERED_DISABLED_PATCH_IDS=(104)

_custom_normalize_patch_id() {
    case "$1" in
        101|103|201|202|301|401|402|403|404|405|406|501|502|503|504|505|506|601) echo "$1" ;;
        R01) echo 101 ;;
        R03) echo 103 ;;
        P05) echo 104 ;;
        B01) echo 201 ;;
        B02) echo 202 ;;
        I01) echo 301 ;;
        F02) echo 401 ;;
        F10) echo 402 ;;
        F11) echo 403 ;;
        F12) echo 404 ;;
        F13) echo 405 ;;
        F14) echo 406 ;;
        S10) echo 501 ;;
        S11) echo 502 ;;
        S12) echo 503 ;;
        S13) echo 504 ;;
        S14) echo 505 ;;
        S15) echo 506 ;;
        P01) echo 601 ;;
        *) return 1 ;;
    esac
}

_custom_retired_patch_hint() {
    case "$1" in
        N01) echo 102 ;;
        P02) echo 611 ;;
        P03) echo 612 ;;
        P04) echo 613 ;;
        *) return 1 ;;
    esac
}

_custom_patch_id_error() {
    local id="$1" retired
    if retired=$(_custom_retired_patch_hint "$id"); then
        echo "source-patcher: patch ID '$id' is retired (placeholder $retired); see docs/patch-registry.md" >&2
    elif [ "$id" = "P05" ] || [ "$id" = "104" ]; then
        echo "source-patcher: patch ID '104' (P05 super password) is registered but not enabled" >&2
    else
        echo "source-patcher: invalid patch ID '$id' (valid: ${CUSTOM_PATCH_IDS[*]})" >&2
    fi
}

_custom_patch_id_index() {
    local want i=0
    want=$(_custom_normalize_patch_id "$1") || return 1
    for id in "${CUSTOM_PATCH_IDS[@]}"; do
        if [ "$id" = "$want" ]; then
            echo "$i"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}

_custom_should_run_patch() {
    local id only_id w
    id=$(_custom_normalize_patch_id "$1") || return 1
    local only="${SOURCE_PATCH_ONLY:-}"
    local whitelist="${SOURCE_PATCH_WHITELIST:-}"
    local up_to="${SOURCE_PATCH_UP_TO:-}"

    if [ -n "$only" ]; then
        only_id=$(_custom_normalize_patch_id "$only") || return 1
        [ "$id" = "$only_id" ]
        return
    fi

    if [ -n "$whitelist" ]; then
        for w in $whitelist; do
            w=$(_custom_normalize_patch_id "$w") || continue
            [ "$id" = "$w" ] && return 0
        done
        return 1
    fi

    if [ -z "$up_to" ]; then
        _custom_bool_enabled "${CUSTOM_PATCH_APPLY_ALL:-false}"
        return
    fi

    local idx up_idx
    idx=$(_custom_patch_id_index "$id") || return 1
    up_idx=$(_custom_patch_id_index "$up_to") || return 1
    [ "$idx" -le "$up_idx" ]
}

_custom_validate_source_patch_up_to() {
    local id
    local up_to="${SOURCE_PATCH_UP_TO:-}"
    local only="${SOURCE_PATCH_ONLY:-}"
    local whitelist="${SOURCE_PATCH_WHITELIST:-}"

    if [ -n "$only" ] && ! _custom_patch_id_index "$only" >/dev/null; then
        _custom_patch_id_error "$only"
        return 1
    fi
    if [ -n "$up_to" ] && ! _custom_patch_id_index "$up_to" >/dev/null; then
        _custom_patch_id_error "$up_to"
        return 1
    fi
    for id in $whitelist; do
        if ! _custom_patch_id_index "$id" >/dev/null; then
            _custom_patch_id_error "$id"
            return 1
        fi
    done
    return 0
}
```

`_custom_run_patch` 保持不变。

### 3.2 `orchestrator.sh`

```bash
_custom_patch_schedule_active() {
    if [ -n "${SOURCE_PATCH_ONLY:-}" ]; then return 0; fi
    if [ -n "${SOURCE_PATCH_WHITELIST:-}" ]; then return 0; fi
    if [ -n "${SOURCE_PATCH_UP_TO:-}" ]; then return 0; fi
    _custom_bool_enabled "${CUSTOM_PATCH_APPLY_ALL:-false}"
}
```

`_custom_resolve_build_inputs` trace：

```bash
_custom_trace_value "CUSTOM_VERIFIED_PATCH_IDS" "${CUSTOM_VERIFIED_PATCH_IDS:-<empty>}"
_custom_trace_value "SOURCE_PATCH_WHITELIST(effective)" "${SOURCE_PATCH_WHITELIST:-<none>}"
```

`_custom_write_build_config_json`：保留 `verified_patch_up_to`（空），新增：

```bash
--arg verified_patch_ids "${CUSTOM_VERIFIED_PATCH_IDS:-}" \
...
verified_patch_ids: $verified_patch_ids,
```

`apply_custom_source_patches` 开头：

```bash
if [ -z "${SOURCE_PATCH_UP_TO:-}" ] && [ -z "${SOURCE_PATCH_WHITELIST:-}" ] \
   && [ -n "${CUSTOM_VERIFIED_PATCH_IDS:-}" ]; then
    export SOURCE_PATCH_WHITELIST="$CUSTOM_VERIFIED_PATCH_IDS"
fi
```

调度段（删除 N01/P02/P03/P04）：

```bash
_custom_run_patch 101 _custom_patch_r01 || return 1
_custom_run_patch 103 _custom_patch_is_custom_client || return 1

_custom_run_patch 201 _custom_patch_brand_files || return 1
_custom_run_patch 202 _custom_patch_logo_assets || return 1
_custom_run_patch 301 _custom_patch_i18n_ui_strings || return 1

_custom_run_patch 401 _custom_patch_flutter_ui_app_name || return 1
_custom_run_patch 402 _custom_patch_flutter_home_logo || return 1
_custom_run_patch 403 _custom_patch_flutter_home_title || return 1
_custom_run_patch 404 _custom_patch_flutter_home_slogan || return 1
_custom_run_patch 405 _custom_patch_flutter_powered_by || return 1
_custom_run_patch 406 _custom_patch_flutter_about_studio || return 1

_custom_run_patch 501 _custom_patch_sciter_home_logo || return 1
_custom_run_patch 502 _custom_patch_sciter_home_title || return 1
_custom_run_patch 503 _custom_patch_sciter_home_slogan || return 1
_custom_run_patch 504 _custom_patch_sciter_powered_by || return 1
_custom_run_patch 505 _custom_patch_sciter_about_studio || return 1
_custom_run_patch 506 _custom_patch_sciter_index_css || return 1

_custom_run_patch 601 _custom_patch_portable_working_dir || return 1
```

### 3.3 `verified-patches.env`

```bash
CUSTOM_VERIFIED_PATCH_IDS="101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601"
# 104 = super password：已登记、暂不启用（101 已写常量）
```

表格 23 行：18 在用按顺序；102/104/611/612/613 单列「退役/未启用」。

### 3.4 `load.sh`

删除 4 行 `source`：

```text
core/network_lock.patch.sh
platform/windows-signing.sh
platform/msi-noop.sh
platform/rust-cache-nonfatal.sh
```

保留 `core/super_password.patch.sh`（104）。

### 3.5 CI 工作流

`CustomBuildRustdesk.yml`：

```yaml
# L81
description: 'Debug: cap patches at ID (103/503/506…); empty = verified-patches.env'
```

```bash
# L380 起
echo "CUSTOM_VERIFIED_PATCH_IDS=${CUSTOM_VERIFIED_PATCH_IDS:-}" >> "$GITHUB_ENV"
if [ -z "${CUSTOM_VERIFIED_PATCH_IDS:-}" ]; then
  echo "📦 Rollout gate: vanilla upstream (zero patches)"
else
  echo "📌 Rollout gate: verified patch whitelist = ${CUSTOM_VERIFIED_PATCH_IDS}"
fi
```

```bash
# L517 起
elif [ -n "${CUSTOM_VERIFIED_PATCH_IDS:-}" ]; then
  export SOURCE_PATCH_WHITELIST="$CUSTOM_VERIFIED_PATCH_IDS"
  echo "📌 Verified rollout: SOURCE_PATCH_WHITELIST=$SOURCE_PATCH_WHITELIST"
```

`test_scripts/CustomBuildRustdesk.yml` 做同样三处修改。

### 3.6 工具链

| 文件 | 改动 |
|---|---|
| `step-verify-all.sh` | 预检 `ids=(<旧 23 个含 N01 P05>)`；重排后 `ids=(101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601)` |
| `run.sh` | L30/31 示例 `402`；L38 新 18 个顺序串；L193 `verify_up_to="601"` |
| `verify.sh` | 16 处 `verify_from` → 新 ID；`CUSTOM_RUSTDESK_S10_ICON_PROBE` → `CUSTOM_RUSTDESK_501_ICON_PROBE` |
| `source-patcher.sh` | L7/8 示例 `--only 402`、`--up-to 402` |
| `trigger-one-patch.sh` | 用法/示例改新 ID |
| `profiles/baixin-hide.env`、`baixin-lock.env` | `R01` → `101` |
| `test_scripts/workflow-tests.sh` | `^CUSTOM_VERIFIED_PATCH_IDS=`；`export CUSTOM_VERIFIED_PATCH_IDS=""` |
| `test_scripts/fixtures/issue-params-body.txt` | `patch_up_to: 103` |
| `q0-baseline.yml` | `CUSTOM_VERIFIED_PATCH_IDS=""`；`需 R01+` → `需 101 起` |
| `.cursor/rules/custom-rustdesk-handoff.mdc` | 开关、顺序、`B02`/`F11` 示例 |

### 3.7 补丁脚本自引用（只改 ID/文案/marker）

| 脚本 | 旧→新 |
|---|---|
| `core/r01.sh` | 首行 R01→101；L110 F13→405 |
| `core/super_password.patch.sh` | R01→101、P05→104 |
| `brand/logo-assets.sh` | F10→402（2 处） |
| `lib/sciter-brand.sh` | S10→501 |
| `flutter/home-logo.sh` | F10→402、B02→202（9 处） |
| `flutter/home-title.sh` | F11→403、F10→402（8 处） |
| `flutter/home-slogan.sh` | F12→404、F10/F11→402/403（6 处） |
| `flutter/about-studio.sh` | F14→406 |
| `sciter/home-logo.sh` | S10→501、B02→202、marker→`CUSTOM_RUSTDESK_501_ICON_PROBE`（17 处） |
| `sciter/home-title.sh` | S11→502、S10→501（6 处） |
| `sciter/home-slogan.sh` | S12→503、S10/S11→501/502（6 处） |
| `sciter/powered-by.sh` | S13→504、S10–S12→501–503（7 处） |

### 3.8 文档

| 文件 | 处理 |
|---|---|
| `docs/patch-registry.md` | 全表重写；新增旧→新迁移表；退役段含 Legacy caveat |
| `docs/verification-rollout.md` | 白名单；16→18 |
| `docs/experiment-verification.md` | 计数/表格 ID 更新；run 号保留 |
| `docs/workspace-handoff.md` | 当前开关值 |
| `docs/ui-customization.md`、`docs/source-patcher-refactor-plan.md`、`docs/rustdesk-stack.md` | 按映射替换 |
| `docs/customization-architecture.md`、`customization-architecture-simple.md` | 工作区文档同步更新；**不纳入**本次 commit |
| `docs/patch-id-renumber-plan.md` | 保持原样（迁移表，grep 例外） |
| `docs/patch-diff/**` | 生成物，不入库、不参与 grep 清零 |
| `README.md`、`CLAUDE.md` | 若含针数/ID 则同步；已 grep 确认当前无 ID 引用 |

---

## 4. 全量变更文件清单（commit 内容）

```text
修改：
  .github/workflows/scripts/patches/manifest.sh
  .github/workflows/scripts/patches/orchestrator.sh
  .github/workflows/scripts/patches/load.sh
  .github/verified-patches.env
  .github/workflows/CustomBuildRustdesk.yml
  .github/workflows/scripts/source-patcher.sh
  .github/workflows/scripts/patches/core/r01.sh
  .github/workflows/scripts/patches/core/super_password.patch.sh
  .github/workflows/scripts/patches/brand/logo-assets.sh
  .github/workflows/scripts/patches/lib/sciter-brand.sh
  .github/workflows/scripts/patches/flutter/{home-logo,home-title,home-slogan,about-studio}.sh
  .github/workflows/scripts/patches/sciter/{home-logo,home-title,home-slogan,powered-by}.sh
  .github/ISSUE_TEMPLATE/q0-baseline.yml
  .cursor/rules/custom-rustdesk-handoff.mdc
  scripts/patch-lab/{run.sh,verify.sh,step-verify-all.sh}
  scripts/patch-lab/profiles/{baixin-hide.env,baixin-lock.env}
  scripts/trigger-one-patch.sh
  test_scripts/workflow-tests.sh
  test_scripts/CustomBuildRustdesk.yml
  test_scripts/fixtures/issue-params-body.txt
  docs/{patch-registry,verification-rollout,experiment-verification,workspace-handoff,ui-customization,source-patcher-refactor-plan,rustdesk-stack}.md
  docs/specs/patch-id-renumber/{spec.md,tasks.md}

删除：
  .github/workflows/scripts/patches/core/network_lock.patch.sh
  .github/workflows/scripts/patches/platform/windows-signing.sh
  .github/workflows/scripts/patches/platform/msi-noop.sh
  .github/workflows/scripts/patches/platform/rust-cache-nonfatal.sh

不纳入 commit（工作区同步）：
  docs/customization-architecture.md
  docs/customization-architecture-simple.md
  scripts/patch-lab/step-diff-all.sh
  scripts/trigger-sciter-bisect.sh
```

---

## 5. 验证（严格按序，失败即停并贴原文）

```bash
# 0) 语法
bash -n .github/workflows/scripts/patches/{manifest,orchestrator,load}.sh
for f in .github/workflows/scripts/patches/*/*.sh; do bash -n "$f"; done

# 1) 锚点与幂等全量（预检 23 针 → 重排后 18 针）
bash scripts/patch-lab/step-verify-all.sh --profile baixin

# 2) 结构回归
bash run-tests.sh workflow-tests
bash run-tests.sh utils-tests

# 3) 全量白名单执行（fresh clone）
export CUSTOM_VERIFIED_PATCH_IDS="101 103 201 202 301 401 402 403 404 405 406 501 502 503 504 505 506 601"
# 断言日志中出现 18 条 [ID]，且无 FAILED

# 4) 幂等双跑（同一棵树）
#    第二次 18 条均为 already applied / skip，无二次注入

# 5) 旧 ID 清零（仅迁移表例外）
git grep -nE '\b(R01|N01|R03|B01|B02|I01|F02|F1[0-4]|S1[0-5]|P0[1-5])\b'

# 6) 白名单集合断言
#    解析 verified-patches.env，排序后与 §2 的 18 个逐一相等

# 7) 退役报错
SOURCE_PATCH_ONLY=N01  # 非零 + retired 提示
SOURCE_PATCH_ONLY=P02  # 非零 + retired 提示
SOURCE_PATCH_ONLY=104  # 非零 + registered but not enabled
```

`patch-lab` 依赖网络与 Linux/bash；若本机不可运行，保留 upstream 树并贴原始错误，不伪造 PASS。

---

## 6. 提交、PR、合并后构建

1. 单 commit；message：

```text
chore(patches): renumber patch IDs to layered 3-digit scheme

- 23 registry IDs -> 101/103/201/202/301/401-406/501-506/601
- retire N01/P02/P03/P04 (102/611/612/613); P05 -> 104 registered, disabled
- replace CUSTOM_VERIFIED_PATCH_UP_TO with CUSTOM_VERIFIED_PATCH_IDS whitelist
- sync workflow, patch-lab, tests, forms, docs
```

2. push `chore/patch-id-renumber`，开 PR（不直推 main）。
3. **合并后**（需要 merge 权限）：
   - 用 Issue 模板新建构建 issue（issue #1 为队列），`patch_up_to` 留空；
   - 记录 **issue 号 + run 号**；
   - 日志断言：18 条新 ID、无 102/104/611/612/613、无 FAILED、无静默 skip；
   - 日志中不得出现旧 ID；
   - 列出各平台 artifact / release 资产、命名、版本号；
   - 失败贴失败步骤与错误原文。
4. 若无法合并/无 `gh` 权限：停在「PR 就绪」，明确报告阻塞原因。

---

## 7. 回滚

单 commit revert；无数据迁移、无运行时状态。Legacy 路径如需恢复 P02/P04，从 git 历史取回脚本并占用 611/613。
