#!/usr/bin/env bash
set -euo pipefail

PLAN_FILE="${1:?PLAN_FILE is required}"
DOWNLOAD_ROOT="${2:?DOWNLOAD_ROOT is required}"
OUTPUT_MANIFEST="${3:?OUTPUT_MANIFEST is required}"

expected="$(jq '.components | length' "$PLAN_FILE")"
actual="$(find "$DOWNLOAD_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"

if [[ "$expected" != "$actual" ]]; then
  echo "ERROR: Expected $expected prepared candidates, found $actual." >&2
  exit 1
fi

components='[]'

for candidate_dir in "$DOWNLOAD_ROOT"/*; do
  [[ -d "$candidate_dir" ]] || continue

  manifest="$(find "$candidate_dir" -maxdepth 1 -name '*--component-manifest.json' -print -quit)"
  checksums="$(find "$candidate_dir" -maxdepth 1 -name '*--payload-checksums.sha256' -print -quit)"

  [[ -f "$manifest" && -f "$checksums" ]] || {
    echo "ERROR: Candidate is missing manifest/checksums: $candidate_dir" >&2
    exit 1
  }

  (
    cd "$candidate_dir/payload"
    sha256sum -c "../$(basename "$checksums")"
  )

  component="$(jq -c '.' "$manifest")"
  components="$(jq --argjson item "$component" '. + [$item]' <<< "$components")"
done

jq -n \
  --arg deployment_id "uat-${GITHUB_RUN_ID:-local}" \
  --arg environment "UAT" \
  --arg source_commit "${GITHUB_SHA:-unknown}" \
  --arg workflow_run_id "${GITHUB_RUN_ID:-unknown}" \
  --arg source_branch "${GITHUB_REF_NAME:-unknown}" \
  --arg generated_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --argjson components "$components" \
  '{
    deployment_id: $deployment_id,
    environment: $environment,
    source_commit: $source_commit,
    workflow_run_id: $workflow_run_id,
    source_branch: $source_branch,
    generated_at: $generated_at,
    components: $components
  }' > "$OUTPUT_MANIFEST"

jq . "$OUTPUT_MANIFEST"
