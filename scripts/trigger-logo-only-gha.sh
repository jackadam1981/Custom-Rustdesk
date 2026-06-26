#!/usr/bin/env bash
# Trigger logo-only build: only logo_url, no banner/icon
set -euo pipefail

REPO="${GITHUB_REPO:-jackadam1981/Custom-Rustdesk}"
REF="${GITHUB_REF:-codex/linux-appimage-actions-test}"
TAG="${1:-logo-only-test-$(date +%Y%m%d-%H%M%S)}"

gh workflow run "Custom Rustdesk Build Workflow" \
  --repo "$REPO" \
  --ref "$REF" \
  -f tag="$TAG" \
  -f customer="LogoOnly Test" \
  -f app_name=LogoOnly \
  -f email=admin@example.com \
  -f customer_link=https://rustdesk.jackadam.top \
  -f banner_url= \
  -f logo_url=logo.png \
  -f icon_url= \
  -f super_password= \
  -f slogan= \
  -f rendezvous_server=rustdesk.jackadam.top:21116 \
  -f relay_server=rustdesk.jackadam.top:21117 \
  -f rs_pub_key=dhaec8XvCtBVV3dHcTR3Fl7UzAwEFFvxGIWUBDJUyCI= \
  -f api_server= \
  -f lock_network_settings=false \
  -f hide_network_settings=false

echo "trigger-logo-only-gha: dispatched tag=$TAG ref=$REF"
sleep 8
run_id=$(gh run list --repo "$REPO" --workflow "Custom Rustdesk Build Workflow" --limit 1 --json databaseId --jq '.[0].databaseId')
echo "Run: https://github.com/$REPO/actions/runs/$run_id"
