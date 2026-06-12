#!/usr/bin/env bash
set -euo pipefail
DETECTION_FILE="${1:?DETECTION_FILE is required}"
OUTPUT_FILE="${2:?OUTPUT_FILE is required}"
jq empty "$DETECTION_FILE" >/dev/null
validated='[]'; errors=0
while IFS= read -r component_path; do
  [[ -n "$component_path" ]] || continue
  meta_file="$component_path/meta.json"
  if [[ ! -f "$meta_file" ]]; then echo "ERROR: Missing $meta_file" >&2; errors=$((errors+1)); continue; fi
  if ! jq empty "$meta_file" >/dev/null 2>&1; then echo "ERROR: Invalid JSON in $meta_file" >&2; errors=$((errors+1)); continue; fi
  component_key="$(jq -r '.component_key // empty' "$meta_file")"
  display_name="$(jq -r '.display_name // .component_key // empty' "$meta_file")"
  version="$(jq -r '.version // empty' "$meta_file")"
  if [[ ! "$component_key" =~ ^[A-Za-z0-9._-]+$ ]]; then echo "ERROR: Invalid component_key in $meta_file" >&2; errors=$((errors+1)); fi
  folder_name="${component_path##*/}"
  if [[ "$component_key" != "$folder_name" ]]; then echo "ERROR: component_key '$component_key' must match folder '$folder_name'." >&2; errors=$((errors+1)); fi
  if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then echo "ERROR: version must use MAJOR.MINOR.PATCH in $meta_file" >&2; errors=$((errors+1)); fi
  if ! jq -e '.artifacts|type=="array" and length>0' "$meta_file" >/dev/null; then echo "ERROR: artifacts must be a non-empty array in $meta_file" >&2; errors=$((errors+1)); continue; fi
  while IFS= read -r artifact; do
    if [[ "$artifact" == /* || "$artifact" == *".."* ]]; then echo "ERROR: Unsafe artifact path '$artifact' in $meta_file" >&2; errors=$((errors+1));
    elif [[ ! -f "$component_path/$artifact" ]]; then echo "ERROR: Missing declared artifact: $component_path/$artifact" >&2; errors=$((errors+1)); fi
  done < <(jq -r '.artifacts[]' "$meta_file")
  case "${component_path%%/*}" in apps) component_type='app';; automations) component_type='automation';; assets) component_type='asset';; *) echo "ERROR: Unsupported category." >&2; errors=$((errors+1)); continue;; esac
  entry="$(jq -n --arg component_type "$component_type" --arg component_key "$component_key" --arg display_name "$display_name" --arg component_path "$component_path" --arg version "$version" --argjson artifacts "$(jq -c '.artifacts' "$meta_file")" '{component_type:$component_type,component_key:$component_key,display_name:$display_name,component_path:$component_path,version:$version,artifacts:$artifacts}')"
  validated="$(jq --argjson item "$entry" '.+[$item]' <<< "$validated")"
done < <(jq -r '.components[]' "$DETECTION_FILE")
if ((errors>0)); then echo "Validation failed with $errors error(s)." >&2; exit 1; fi
jq -n --argjson components "$validated" '{has_components:($components|length>0),components:$components}' > "$OUTPUT_FILE"
jq . "$OUTPUT_FILE"
