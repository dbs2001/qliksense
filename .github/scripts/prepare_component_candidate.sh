#!/usr/bin/env bash
set -euo pipefail

COMPONENT_JSON="${1:?COMPONENT_JSON is required}"
SOURCE_COMMIT="${2:?SOURCE_COMMIT is required}"
OUTPUT_ROOT="${3:?OUTPUT_ROOT is required}"

component_key="$(jq -r '.component_key' <<< "$COMPONENT_JSON")"
component_type="$(jq -r '.component_type' <<< "$COMPONENT_JSON")"
component_path="$(jq -r '.component_path' <<< "$COMPONENT_JSON")"
base_version="$(jq -r '.base_version' <<< "$COMPONENT_JSON")"
rc_number="$(jq -r '.rc_number' <<< "$COMPONENT_JSON")"
prerelease_tag="$(jq -r '.prerelease_tag' <<< "$COMPONENT_JSON")"
stable_tag="$(jq -r '.stable_tag' <<< "$COMPONENT_JSON")"
artifacts="$(jq -c '.artifacts' <<< "$COMPONENT_JSON")"

candidate_name="prepared-${component_key}-v${base_version}-rc.${rc_number}"
candidate_dir="$OUTPUT_ROOT/$candidate_name"
payload_dir="$candidate_dir/payload"

mkdir -p "$payload_dir"

artifact_entries='[]'

while IFS= read -r artifact; do
  source="$component_path/$artifact"
  encoded_path="${artifact//\//__}"
  release_asset_name="${component_key}--payload--${encoded_path}"
  target="$payload_dir/$release_asset_name"

  cp "$source" "$target"

  item="$(
    jq -n \
      --arg source_path "$artifact" \
      --arg release_asset_name "$release_asset_name" \
      '{source_path: $source_path, release_asset_name: $release_asset_name}'
  )"
  artifact_entries="$(jq --argjson item "$item" '. + [$item]' <<< "$artifact_entries")"
done < <(jq -r '.[]' <<< "$artifacts")

cp "$component_path/meta.json" "$candidate_dir/${component_key}--meta.json"

jq -n \
  --arg component_type "$component_type" \
  --arg component_key "$component_key" \
  --arg base_version "$base_version" \
  --argjson rc_number "$rc_number" \
  --arg prerelease_tag "$prerelease_tag" \
  --arg stable_tag "$stable_tag" \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg meta_asset_name "${component_key}--meta.json" \
  --argjson artifacts "$artifact_entries" \
  '{
    component_type: $component_type,
    component_key: $component_key,
    base_version: $base_version,
    rc_number: $rc_number,
    prerelease_tag: $prerelease_tag,
    stable_tag: $stable_tag,
    source_commit: $source_commit,
    meta_asset_name: $meta_asset_name,
    artifacts: $artifacts
  }' > "$candidate_dir/${component_key}--component-manifest.json"

echo "$candidate_name"
