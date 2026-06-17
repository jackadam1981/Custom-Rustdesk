# Patch ID registry — one ID = one module = one MR gate.
# Order matches apply_custom_source_patches.

CUSTOM_PATCH_IDS=(
    R01 R02 R03
    B01 B02
    I01
    F02 F10 F11 F12
    S10 S12 S13
    P01 P02 P03 P04
)

_custom_patch_id_index() {
    local want="$1"
    local i=0
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
    local id="$1"
    local only="${SOURCE_PATCH_ONLY:-}"
    local up_to="${SOURCE_PATCH_UP_TO:-}"

    if [ -n "$only" ]; then
        [ "$id" = "$only" ]
        return
    fi

    if [ -z "$up_to" ]; then
        # patch-lab 全量回归显式传 CUSTOM_PATCH_APPLY_ALL=true；CI 默认空 = 零针
        _custom_bool_enabled "${CUSTOM_PATCH_APPLY_ALL:-false}"
        return
    fi

    local idx up_idx
    idx=$(_custom_patch_id_index "$id") || return 1
    up_idx=$(_custom_patch_id_index "$up_to") || return 1
    [ "$idx" -le "$up_idx" ]
}

_custom_run_patch() {
    local id="$1"
    shift
    if ! _custom_should_run_patch "$id"; then
        return 0
    fi
    echo "source-patcher: [$id] $*"
    "$@"
}
