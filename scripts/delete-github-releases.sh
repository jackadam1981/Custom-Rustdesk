#!/usr/bin/env bash
# Delete GitHub Releases by retention policy (count + age). Default: dry-run.
#
# GitHub Actions: .github/workflows/99-delete_releases.yml
#
# Policy (newest first):
#   - Always keep newest KEEP_LAST releases.
#   - Among the rest, also keep any created within KEEP_DAYS (if KEEP_DAYS > 0).
#   - Delete everything else; git tags removed with --cleanup-tag by default.
#
# Examples:
#   scripts/delete-github-releases.sh --keep-last 3 --keep-days 7
#   scripts/delete-github-releases.sh --keep-last 3 --keep-days 0 --execute -y
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

repo=""
execute=false
assume_yes=false
keep_last=3
keep_days=7
cleanup_tag=true
limit=1000

usage() {
    cat <<'EOF'
Usage: scripts/delete-github-releases.sh [OPTIONS]

Retention (releases sorted newest-first):
  --keep-last N          Always keep N newest (default: 3)
  --keep-days D          Also keep releases newer than D days beyond top N (default: 7; 0=off)

Execution:
  --execute              Delete (default: dry-run list only)
  -y, --yes              Skip confirmation with --execute
  --no-cleanup-tag       Do not delete git tag (default: delete tag)

Repo:
  --repo OWNER/REPO      Default: git origin or jackadam1981/Custom-Rustdesk
  --limit N              Max releases to scan (default: 1000)
  -h, --help             Show help
EOF
}

default_repo() {
    if git -C "$ROOT" remote get-url origin &>/dev/null; then
        local url
        url="$(git -C "$ROOT" remote get-url origin)"
        if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
            echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
            return 0
        fi
    fi
    echo "jackadam1981/Custom-Rustdesk"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)
            repo="$2"
            shift 2
            ;;
        --execute)
            execute=true
            shift
            ;;
        -y|--yes)
            assume_yes=true
            shift
            ;;
        --keep-last)
            keep_last="$2"
            shift 2
            ;;
        --keep-days|--older-than)
            keep_days="$2"
            shift 2
            ;;
        --cleanup-tag)
            cleanup_tag=true
            shift
            ;;
        --no-cleanup-tag)
            cleanup_tag=false
            shift
            ;;
        --limit)
            limit="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "delete-github-releases: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$repo" ]; then
    repo="$(default_repo)"
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "delete-github-releases: gh CLI not found" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "delete-github-releases: jq not found" >&2
    exit 1
fi

if ! [[ "$keep_last" =~ ^[0-9]+$ ]] || [ "$keep_last" -lt 0 ]; then
    echo "delete-github-releases: --keep-last must be a non-negative integer" >&2
    exit 1
fi

if ! [[ "$keep_days" =~ ^[0-9]+$ ]]; then
    echo "delete-github-releases: --keep-days must be a non-negative integer" >&2
    exit 1
fi

within_keep_days() {
    local created_at="$1"
    if [ "$keep_days" -le 0 ]; then
        return 1
    fi
    local cutoff
    cutoff="$(date -u -d "-${keep_days} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${keep_days}"d +%Y-%m-%dT%H:%M:%SZ)"
    [[ "$created_at" > "$cutoff" ]]
}

mapfile -t rows < <(
    gh release list --repo "$repo" --limit "$limit" --json tagName,createdAt \
        | jq -r '.[] | "\(.tagName)\t\(.createdAt)"'
)

if [ "${#rows[@]}" -eq 0 ]; then
    echo "delete-github-releases: no releases in $repo"
    exit 0
fi

declare -a candidates=()
declare -a candidate_dates=()
declare -a kept=()

idx=0
for row in "${rows[@]}"; do
    tag="${row%%$'\t'*}"
    created_at="${row#*$'\t'}"
    created_at="${created_at//$'\r'/}"
    created_at="${created_at//$'\n'/}"

    if [ "$idx" -lt "$keep_last" ]; then
        kept+=("$tag (top $keep_last)")
        idx=$((idx + 1))
        continue
    fi

    if within_keep_days "$created_at"; then
        kept+=("$tag (within ${keep_days}d)")
        idx=$((idx + 1))
        continue
    fi

    candidates+=("$tag")
    candidate_dates+=("$created_at")
    idx=$((idx + 1))
done

echo "delete-github-releases: repo=$repo"
echo "delete-github-releases: policy=keep-last $keep_last, keep-days $keep_days, cleanup-tag=$cleanup_tag"
echo "delete-github-releases: mode=$([ "$execute" = true ] && echo EXECUTE || echo DRY-RUN)"
echo "delete-github-releases: scanned=${#rows[@]} kept=${#kept[@]} delete=${#candidates[@]}"

if [ "${#kept[@]}" -gt 0 ]; then
    echo "Kept:"
    for k in "${kept[@]}"; do
        echo "  + $k"
    done
fi

if [ "${#candidates[@]}" -eq 0 ]; then
    echo "delete-github-releases: nothing to delete"
    exit 0
fi

echo "Delete candidates:"
for i in "${!candidates[@]}"; do
    echo "  - ${candidates[$i]}  (${candidate_dates[$i]})"
done

if [ "$execute" != true ]; then
    echo
    echo "Dry-run. Re-run with --execute -y to delete."
    exit 0
fi

if [ "$assume_yes" != true ]; then
    read -r -p "Delete ${#candidates[@]} release(s) and tag(s)? [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 1 ;;
    esac
fi

delete_flags=(--repo "$repo" --yes)
if [ "$cleanup_tag" = true ]; then
    delete_flags+=(--cleanup-tag)
fi

failed=0
for tag in "${candidates[@]}"; do
    echo "Deleting: $tag"
    if ! gh release delete "$tag" "${delete_flags[@]}"; then
        echo "FAIL: $tag" >&2
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    echo "delete-github-releases: completed with errors" >&2
    exit 1
fi

echo "delete-github-releases: done (${#candidates[@]} deleted)"
