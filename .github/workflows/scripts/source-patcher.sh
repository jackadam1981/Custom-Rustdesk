#!/bin/bash
# Applies custom RustDesk source patches inside a cloned rustdesk source tree.
# CI 按 verified-patches.env rollout；patch-lab 用于本地验收后再 bump rollout。
# Thin entry — logic lives under patches/.
#
# Incremental apply (patch-lab / local debug):
#   SOURCE_PATCH_ONLY=F10 apply_custom_source_patches
#   SOURCE_PATCH_UP_TO=F10 apply_custom_source_patches

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=patches/load.sh
source "$SCRIPT_DIR/patches/load.sh"

if [ "${1:-}" = "--only" ] && [ -n "${2:-}" ]; then
    export SOURCE_PATCH_ONLY="$2"
elif [ "${1:-}" = "--up-to" ] && [ -n "${2:-}" ]; then
    export SOURCE_PATCH_UP_TO="$2"
fi
