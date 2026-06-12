#!/usr/bin/env bash
set -euo pipefail

DETECTION_FILE="${1:?DETECTION_FILE is required}"
VALIDATION_FILE="${2:?VALIDATION_FILE is required}"
OUTPUT_FILE="${3:?OUTPUT_FILE is required}"

git fetch origin --tags --force

changed_files="$(jq -c '.changed_files' "$DETECTION_FILE")"
matrix='[]'

while IFS= read -r component; do
  component_path="$(jq -r '.component_path' <<< "$component")"
  component_key="$(jq -r '.component_key' <<< "$component")"
  component_type="$(jq -r '.component_type' <<< "$component")"
  version="$(jq -r '.version' <<< "$component")"
  artifacts="$(jq -c '.artifacts' <<< "$component")"

  # Deploy only when at least one declared native artifact changed.
  artifact_changed=false
  while IFS= read -r artifact; do
    full_path="$component_path/$artifact"
    if jq -e --arg path "$full_path" 'index($path) != null' <<< "$changed_files" >/dev/null; then
      artifact_changed=true
      break
    fi
  done < <(jq -r '.[]' <<< "$artifacts")

  if [[ "$artifact_changed" != "true" ]]; then
    echo "Skipping $component_key: no declared native artifact changed."
    continue
  fi

  tag_namespace="${component_path%%/*}"
  stable_tag="${tag_namespace}/${component_key}/v${version}"

  if git rev-parse -q --verify "refs/tags/$stable_tag" >/dev/null; then
    echo "ERROR: Stable tag already exists: $stable_tag" >&2
    echo "Bump meta.json.version before creating another UAT candidate." >&2
    exit 1
  fi

  max_rc=0
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    rc="${tag##*-rc.}"
    if [[ "$rc" =~ ^[0-9]+$ ]] && (( rc > max_rc )); then
      max_rc="$rc"
    fi
  done < <(git tag -l "${stable_tag}-rc.*")

  rc_number=$((max_rc + 1))
  prerelease_tag="${stable_tag}-rc.${rc_number}"

  entry="$(
    jq -n \
      --arg component_type "$component_type" \
      --arg component_key "$component_key" \
      --arg component_path "$component_path" \
      --arg base_version "$version" \
      --argjson rc_number "$rc_number" \
      --arg prerelease_tag "$prerelease_tag" \
      --arg stable_tag "$stable_tag" \
      --argjson artifacts "$artifacts" \
      '{
        component_type: $component_type,
        component_key: $component_key,
        component_path: $component_path,
        base_version: $base_version,
        rc_number: $rc_number,
        prerelease_tag: $prerelease_tag,
        stable_tag: $stable_tag,
        artifacts: $artifacts
      }'
  )"

  matrix="$(jq --argjson item "$entry" '. + [$item]' <<< "$matrix")"
done < <(jq -c '.components[]' "$VALIDATION_FILE")

jq -n \
  --argjson components "$matrix" \
  '{
    has_components: ($components | length > 0),
    components: $components,
    matrix: {include: $components}
  }' > "$OUTPUT_FILE"

echo "Prerelease plan:"
jq . "$OUTPUT_FILE"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "has_components=$(jq -r '.has_components' "$OUTPUT_FILE")" >> "$GITHUB_OUTPUT"
  echo "matrix=$(jq -c '.matrix' "$OUTPUT_FILE")" >> "$GITHUB_OUTPUT"
  echo "components=$(jq -c '.components' "$OUTPUT_FILE")" >> "$GITHUB_OUTPUT"
fi
