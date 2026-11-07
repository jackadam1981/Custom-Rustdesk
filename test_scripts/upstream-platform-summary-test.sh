#!/bin/bash
# Local regression for upstream-build platform aggregation (in_progress vs failed).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/debug-356028.log"

platform_summary_from_jobs() {
  echo "$1" | jq -r '
    def platform($name):
      ($name | ascii_downcase) as $n |
      if ($n | test("android|linux-android")) then "android"
      elif ($n | test("ios|apple-ios")) then "ios"
      elif ($n | test("windows|pc-windows")) then "windows"
      elif ($n | test("macos|apple-darwin|darwin")) then "macos"
      elif ($n | test("linux")) then "linux"
      else "other" end;
    def is_auxiliary($name):
      ($name | ascii_downcase) as $n |
      ($n | test("temptopmostwindow|tempwindow|generate-bridge|generate_bridge|bridge-artifact"));
    def is_primary($name): (is_auxiliary($name) | not);
    def is_pending($j):
      ($j.status == "in_progress" or $j.status == "queued" or $j.status == "waiting"
       or $j.status == "requested" or $j.status == "pending"
       or ($j.conclusion == null) or ($j.conclusion == ""));
    def is_success($j): ($j.conclusion == "success");
    def is_failed($j):
      (is_pending($j) | not) and (is_success($j) | not)
      and ($j.conclusion != "skipped") and ($j.conclusion != "neutral")
      and ($j.conclusion != "cancelled");
    [
      .jobs[]
      | select(.conclusion != "skipped")
      | select(is_primary(.name))
      | {name, status, conclusion, platform: platform(.name)}
      | select(.platform != "other")
    ] as $jobs |
    ["windows","linux","macos","android","ios"] as $platforms |
    [
      $platforms[] as $p |
      ($jobs | map(select(.platform == $p))) as $pjobs |
      select(($pjobs | length) > 0) |
      {
        platform: $p,
        total: ($pjobs | length),
        success: ($pjobs | map(select(is_success(.))) | length),
        pending: ($pjobs | map(select(is_pending(.))) | length),
        failed: ($pjobs | map(select(is_failed(.))) | length),
        failed_jobs: ($pjobs | map(select(is_failed(.)) | .name) | join(" | "))
      }
      | .status = (
          if .pending > 0 then "pending"
          elif .success > 0 then "success"
          else "failure" end
        )
    ]
    | .[] | [.platform, .status, ("success=" + (.success|tostring)), ("failed=" + (.failed|tostring)), ("pending=" + (.pending|tostring)), .failed_jobs] | @tsv
  '
}

debug_log() {
  local hypothesis_id="$1" message="$2" data="$3"
  printf '%s\n' "{\"sessionId\":\"356028\",\"hypothesisId\":\"$hypothesis_id\",\"location\":\"upstream-platform-summary-test.sh\",\"message\":\"$message\",\"data\":$data,\"timestamp\":$(date +%s000)}" >> "$LOG_FILE"
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if ! printf '%s\n' "$haystack" | grep -Fq "$needle"; then
    echo "FAIL: $label (missing: $needle)"
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if printf '%s\n' "$haystack" | grep -Fq "$needle"; then
    echo "FAIL: $label (unexpected: $needle)"
    exit 1
  fi
}

# Simulates run 28438077410 premature snapshot: x86_64 still in_progress.
in_progress_jobs='{
  "jobs": [
    {"name":"run-upstream-flutter-build / i686-pc-windows-msvc (windows-2022)","status":"completed","conclusion":"success"},
    {"name":"run-upstream-flutter-build / build-RustDeskTempTopMostWindow (windows-2022, x64) / build-RustDeskTempTopMostWindow","status":"completed","conclusion":"success"},
    {"name":"run-upstream-flutter-build / x86_64-pc-windows-msvc","status":"in_progress","conclusion":null},
    {"name":"run-upstream-flutter-build / aarch64-pc-windows-msvc","status":"in_progress","conclusion":null}
  ]
}'

completed_jobs='{
  "jobs": [
    {"name":"run-upstream-flutter-build / i686-pc-windows-msvc (windows-2022)","status":"completed","conclusion":"success"},
    {"name":"run-upstream-flutter-build / x86_64-pc-windows-msvc","status":"completed","conclusion":"success"},
    {"name":"run-upstream-flutter-build / build-rustdesk-windows-sciter x86-pc-windows-msvc","status":"completed","conclusion":"success"}
  ]
}'

summary_in_progress="$(platform_summary_from_jobs "$in_progress_jobs")"
summary_completed="$(platform_summary_from_jobs "$completed_jobs")"

debug_log "C" "in_progress snapshot" "$(printf '%s' "$summary_in_progress" | jq -Rs '{summary:.}')"
debug_log "C" "completed snapshot" "$(printf '%s' "$summary_completed" | jq -Rs '{summary:.}')"

assert_contains "$summary_in_progress" $'windows\tpending\t' "in_progress primary job should mark platform pending"
assert_not_contains "$summary_in_progress" $'windows\tfailure\t' "in_progress primary job must not count as platform failure"

auxiliary_only='{
  "jobs": [
    {"name":"run-upstream-flutter-build / build-RustDeskTempTopMostWindow (windows-2022, x64) / build-RustDeskTempTopMostWindow","status":"completed","conclusion":"success"},
    {"name":"run-upstream-flutter-build / build-RustDeskTempTopMostWindow (windows-11-arm, ARM64) / build-RustDeskTempTopMostWindow","status":"completed","conclusion":"success"}
  ]
}'
summary_aux="$(platform_summary_from_jobs "$auxiliary_only")"
if printf '%s\n' "$summary_aux" | grep -Fq 'windows'; then
  echo "FAIL: auxiliary-only jobs should not define windows platform"
  exit 1
fi

success_count="$(printf '%s\n' "$summary_completed" | awk -F '\t' 'NF && $2=="success"{count++} END{print count+0}')"
if [ "$success_count" -lt 1 ]; then
  echo "FAIL: completed snapshot should have at least one successful platform (got $success_count)"
  exit 1
fi

echo "PASS: upstream platform summary distinguishes pending vs failed"
echo "$summary_in_progress"
echo "---"
echo "$summary_completed"
