_custom_json_string() {
    jq -Rn --arg v "${1:-}" '$v'
}

_custom_xml_escape() {
    printf '%s' "${1:-}" |
        sed -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g' \
            -e 's/"/\&quot;/g' \
            -e "s/'/\&apos;/g"
}

_custom_replace_file() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"

    if [ -f "$file" ]; then
        perl -0pi -e "s{$pattern}{$replacement}g" "$file"
    fi
}

_custom_replace_file_once() {
    local file="$1"
    local pattern="$2"
    local replacement="$3"

    if [ -f "$file" ]; then
        perl -0pi -e "s{$pattern}{$replacement}" "$file"
    fi
}

_custom_address_host() {
    local address="${1:-}"
    address="${address#*://}"
    address="${address%%/*}"

    if [[ "$address" =~ ^\[([^]]+)\](:[0-9]+)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "$address" =~ ^([^:]+):[0-9]+$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    echo "$address"
}

_custom_trace_value() {
    local name="$1"
    local value="${2:-}"

    if [ -z "$value" ]; then
        echo "source-patcher-trace: $name=<empty>"
    else
        echo "source-patcher-trace: $name=$value"
    fi
}

_custom_bool_enabled() {
    case "${1:-false}" in
        true|TRUE|True|1|yes|YES|y|Y|on|ON)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_custom_patch_debug_enabled() {
    _custom_bool_enabled "${CUSTOM_SOURCE_PATCH_DEBUG:-${BUILD_SOURCE_PATCH_DEBUG:-false}}"
}

_custom_trace_file_match() {
    local phase="$1"
    local file="$2"
    local label="$3"
    local pattern="$4"

    if ! _custom_patch_debug_enabled; then
        return 0
    fi

    echo "source-patcher-trace: [$phase] $file :: $label"
    if [ ! -f "$file" ]; then
        echo "source-patcher-trace: [$phase] $file missing"
        return 0
    fi

    if ! grep -nE "$pattern" "$file" | head -20; then
        echo "source-patcher-trace: [$phase] no match for $label"
    fi
}
