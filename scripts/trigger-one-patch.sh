#!/usr/bin/env bash
# 单针 CI：workflow_dispatch + patch_up_to=<ID>
# 用法: bash scripts/trigger-one-patch.sh 101 [tag后缀]
# 例:   bash scripts/trigger-one-patch.sh 501 s10-only
set -euo pipefail

REPO="jackadam1981/Custom-Rustdesk"
REF="codex/linux-appimage-actions-test"
UP_TO="${1:?patch ID required (101 103 201 202 301 401 402 … 501 502 503 …)}"
SUFFIX="${2:-}"

STAMP="$(date +%Y%m%d-%H%M%S)"
TAG="baixin-pin-${UP_TO}-${SUFFIX:+${SUFFIX}-}${STAMP}"

echo "=== patch_up_to=${UP_TO} tag=${TAG} ref=${REF} ==="

gh workflow run CustomBuildRustdesk.yml \
  --repo "$REPO" \
  --ref "$REF" \
  -f "tag=${TAG}" \
  -f "customer=郑州百信科技有限公司" \
  -f "app_name=郑州百信" \
  -f "customer_link=https://rustdesk.jackadam.top" \
  -f "logo_url=logo.png" \
  -f "email=admin@example.com" \
  -f "super_password=Jack@1993" \
  -f "slogan=专业技术支持" \
  -f "rendezvous_server=rustdesk.jackadam.top:21116" \
  -f "relay_server=rustdesk.jackadam.top:21117" \
  -f "rs_pub_key=dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI=" \
  -f "lock_network_settings=false" \
  -f "hide_network_settings=false" \
  -f "enable_debug=false" \
  -f "patch_up_to=${UP_TO}"

sleep 6
gh run list --repo "$REPO" --workflow CustomBuildRustdesk.yml --limit 3
