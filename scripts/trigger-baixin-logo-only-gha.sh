#!/usr/bin/env bash
# 百信 profile：logo 定制；icon_url 空 → 默认 branding/icon-rustdesk.png
set -euo pipefail

REPO="${GITHUB_REPO:-jackadam1981/Custom-Rustdesk}"
REF="${GITHUB_REF:-codex/linux-appimage-actions-test}"
TAG="${1:-baixin-logo-only-$(date +%Y%m%d-%H%M%S)}"

gh workflow run "Custom Rustdesk Build Workflow" \
  --repo "$REPO" \
  --ref "$REF" \
  -f tag="$TAG" \
  -f customer="郑州百信科技有限公司" \
  -f app_name="郑州百信" \
  -f email=admin@example.com \
  -f customer_link=https://rustdesk.jackadam.top \
  -f banner_url= \
  -f logo_url=logo.png \
  -f icon_url= \
  -f super_password='Jack@1993' \
  -f slogan=科技提高效率 \
  -f rendezvous_server=rustdesk.jackadam.top:21116 \
  -f relay_server=rustdesk.jackadam.top:21117 \
  -f rs_pub_key=dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI= \
  -f api_server= \
  -f lock_network_settings=false \
  -f hide_network_settings=false

echo "trigger-baixin-logo-only-gha: dispatched tag=$TAG ref=$REF"
sleep 8
run_id=$(gh run list --repo "$REPO" --workflow "Custom Rustdesk Build Workflow" --limit 1 --json databaseId --jq '.[0].databaseId')
echo "Run: https://github.com/$REPO/actions/runs/$run_id"
