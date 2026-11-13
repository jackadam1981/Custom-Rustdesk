# Patch ID registry — one ID = one module = one MR gate.
# Order matches apply_custom_source_patches.
#
# 1xx 配置注入 / 2xx 品牌壳层 / 3xx 文案 / 4xx Flutter / 5xx Sciter / 6xx 平台打包
# 数字顺序 = 执行顺序；SOURCE_PATCH_UP_TO 仍按本数组的索引比较。

CUSTOM_PATCH_IDS=(
    101 103
    201 202
    301
    401 402 403 404 405 406
    501 502 503 504 505 506
    601
)

# 已登记、暂不启用：104 = super password（101 已写入该常量，单独运行会自跳过）
CUSTOM_REGISTERED_DISABLED_PATCH_IDS=(104)

# 旧 ID → 新 ID（兼容历史 issue / profile / 本地命令）
_custom_normalize_patch_id() {
    case "$1" in
        101|103|201|202|301|401|402|403|404|405|406|501|502|503|504|505|506|601)
            echo "$1"
            ;;
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

# 退役 ID → 占位编号（脚本已删除；解析时明确报错，不静默跳过）
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
    local id="$1"
    local retired
    if retired=$(_custom_retired_patch_hint "$id"); then
        echo "source-patcher: patch ID '$id' is retired (placeholder $retired); see docs/patch-registry.md" >&2
    elif [ "$id" = "P05" ] || [ "$id" = "104" ]; then
        echo "source-patcher: patch ID '104' (P05 super password) is registered but not enabled" >&2
    else
        echo "source-patcher: invalid patch ID '$id' (valid: ${CUSTOM_PATCH_IDS[*]})" >&2
    fi
}

_custom_patch_id_index() {
    local want
    local i=0
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
    local id only_id
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
        local w
        for w in $whitelist; do
            w=$(_custom_normalize_patch_id "$w") || continue
            [ "$id" = "$w" ] && return 0
        done
        return 1
    fi

    if [ -z "$up_to" ]; then
        # patch-lab 全量回归显式传 CUSTOM_PATCH_APPLY_ALL=true；CI 默认空 = 零针
        _custom_bool_enabled "${CUSTOM_PATCH_APPLY_ALL:-false}"
        return
    fi

    local idx up_idx
    idx=$(_custom_patch_id_index "$id") || return 1
    up_idx=$(_custom_patch_id_index "$up_to") || return 1
    # 纯判断：只做 idx <= up_idx 的比较，不再回调 _custom_run_patch（否则递归）
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

_custom_run_patch() {
    local id="$1"
    shift
    if ! _custom_should_run_patch "$id"; then
        return 0
    fi
    echo "source-patcher: [$id] $*"
    if ! "$@"; then
        echo "source-patcher: [$id] FAILED" >&2
        return 1
    fi
}
