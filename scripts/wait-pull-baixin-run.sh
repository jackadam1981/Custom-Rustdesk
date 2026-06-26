#!/usr/bin/env bash
# Poll GHA run until release ready, then download Windows exes to local downloads/.
set -euo pipefail

export PATH="/c/Users/jacka/AppData/Local/Microsoft/WinGet/Packages/jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe:$PATH"

RUN_ID="${1:?usage: wait-pull-baixin-run.sh <run_id> [dest_dir]}"
DEST="${2:-/d/My_Project/custom-rustdesk/downloads/Baixin-${RUN_ID}}"
REPO="${GITHUB_REPO:-jackadam1981/Custom-Rustdesk}"
TAG="${3:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa_k3s_2.18}"
SSH_HOST="${SSH_HOST:-jack@192.168.2.18}"
POLL_SEC="${POLL_SEC:-300}"
MAX_WAIT_SEC="${MAX_WAIT_SEC:-7200}"

mkdir -p "$DEST"
echo "wait-pull: run=$RUN_ID dest=$DEST poll=${POLL_SEC}s max=${MAX_WAIT_SEC}s"

deadline=$((SECONDS + MAX_WAIT_SEC))
release_tag=""
release_url=""

while (( SECONDS < deadline )); do
  json=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_HOST" \
    "gh run view $RUN_ID --repo $REPO --json status,conclusion,jobs 2>/dev/null" || true)
  status=$(echo "$json" | jq -r '.status // "unknown"')
  conclusion=$(echo "$json" | jq -r '.conclusion // ""')
  upstream=$(echo "$json" | jq -r '[.jobs[]? | select(.name=="upstream-build") | .conclusion][0] // ""')
  finish=$(echo "$json" | jq -r '[.jobs[]? | select(.name=="finish") | .conclusion][0] // ""')

  echo "$(date -Iseconds) status=$status conclusion=$conclusion upstream=$upstream finish=$finish"

  if [[ "$finish" == "success" ]]; then
    break
  fi
  if [[ "$conclusion" == "failure" || "$conclusion" == "cancelled" ]]; then
    echo "wait-pull: main run failed ($conclusion)" >&2
    exit 1
  fi
  sleep "$POLL_SEC"
done

if [[ "$finish" != "success" ]]; then
  echo "wait-pull: timed out waiting for finish job" >&2
  exit 1
fi

if [[ -z "$TAG" ]]; then
  TAG=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_HOST" \
    "gh run view $RUN_ID --repo $REPO --log 2>/dev/null | rg -o 'logo-only-test|baixin-ui-[0-9]+|r01-baixin[^ ]*' | tail -1" || true)
fi

# Discover latest baixin-ui release if tag unknown
if [[ -z "$TAG" ]]; then
  TAG=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_HOST" \
    "gh release list --repo $REPO --limit 10 --json tagName,publishedAt --jq '[.[] | select(.tagName|test(\"baixin-ui\"))][0].tagName'")
fi

if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  echo "wait-pull: could not resolve release tag; check run $RUN_ID manually" >&2
  exit 1
fi

release_url="https://github.com/$REPO/releases/tag/$TAG"
echo "wait-pull: release tag=$TAG"

remote="/tmp/baixin-pull-${RUN_ID}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_HOST" bash -s <<EOF
set -euo pipefail
mkdir -p "$remote"
cd "$remote"
rm -f rustdesk-1.4.8-x86_64.exe rustdesk-1.4.8-x86-sciter.exe rustdesk-1.4.8-x86_64.msi 2>/dev/null || true
for f in rustdesk-1.4.8-x86_64.exe rustdesk-1.4.8-x86-sciter.exe rustdesk-1.4.8-x86_64.msi; do
  echo "Downloading \$f ..."
  gh release download "$TAG" --repo $REPO -D "$remote" -p "\$f" || wget -q -O "\$f" "https://github.com/$REPO/releases/download/$TAG/\$f"
done
ls -lh "$remote"
EOF

scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  "${SSH_HOST}:${remote}/rustdesk-1.4.8-x86_64.exe" \
  "${SSH_HOST}:${remote}/rustdesk-1.4.8-x86-sciter.exe" \
  "$DEST/" 2>/dev/null || true

# MSI optional (often fails on CDN)
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
  "${SSH_HOST}:${remote}/rustdesk-1.4.8-x86_64.msi" \
  "$DEST/" 2>/dev/null || true

cat > "$DEST/build-info.json" <<JSON
{
  "run_id": "$RUN_ID",
  "run_url": "https://github.com/$REPO/actions/runs/$RUN_ID",
  "release_tag": "$TAG",
  "release_url": "$release_url",
  "trigger_tag": "baixin-ui-20260626",
  "customer": "郑州百信科技有限公司",
  "app_name": "郑州百信",
  "slogan": "科技提高效率",
  "head_sha": "e880dce",
  "downloaded_at": "$(date -Iseconds)"
}
JSON

ls -lh "$DEST"
echo "wait-pull: done -> $DEST"
