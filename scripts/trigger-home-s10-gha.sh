#!/usr/bin/env bash
# M5 首页 S10：Flutter 48px 图标 + Sciter 左上角品牌区；仅 icon_url，不换托盘/任务栏。
set -euo pipefail

REPO="${GITHUB_REPO:-jackadam1981/Custom-Rustdesk}"
REF="${GITHUB_REF:-codex/linux-appimage-actions-test}"

gh workflow run "Custom Rustdesk Build Workflow" \
  --repo "$REPO" \
  --ref "$REF" \
  -f tag=home-s10-test \
  -f customer="郑州百信科技有限公司" \
  -f app_name="郑州百信" \
  -f email=admin@example.com \
  -f customer_link=https://rustdesk.jackadam.top \
  -f banner_url= \
  -f icon_url=logo.png \
  -f super_password='Jack@1993' \
  -f slogan= \
  -f rendezvous_server=rustdesk.jackadam.top:21116 \
  -f relay_server=rustdesk.jackadam.top:21117 \
  -f rs_pub_key=dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI= \
  -f lock_network_settings=false \
  -f hide_network_settings=false

echo "trigger-home-s10-gha: dispatched (verified-patches.env 须已为 S10)"
sleep 8
run_id=$(gh run list --repo "$REPO" --workflow "Custom Rustdesk Build Workflow" --limit 1 --json databaseId --jq '.[0].databaseId')
echo "Latest run: https://github.com/$REPO/actions/runs/$run_id"
