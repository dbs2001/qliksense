#!/usr/bin/env bash
set -euo pipefail

RELEASE_DIR="${1:?RELEASE_DIR is required}"
DEPLOYMENT_MANIFEST="$RELEASE_DIR/deployment-manifest.json"

[[ -f "$DEPLOYMENT_MANIFEST" ]] || {
  echo "ERROR: deployment-manifest.json not found." >&2
  exit 1
}

while IFS= read -r component; do
  component_key="$(jq -r '.component_key' <<< "$component")"
  prerelease_tag="$(jq -r '.prerelease_tag' <<< "$component")"
  expected_commit="$(jq -r '.source_commit' <<< "$component")"

  tag_commit="$(git rev-list -n 1 "$prerelease_tag" 2>/dev/null || true)"
  [[ "$tag_commit" == "$expected_commit" ]] || {
    echo "ERROR: RC tag verification failed for $prerelease_tag." >&2
    exit 1
  }

  checksum_asset="${component_key}--payload-checksums.sha256"
  [[ -f "$RELEASE_DIR/$checksum_asset" ]] || {
    echo "ERROR: Missing checksum asset: $checksum_asset" >&2
    exit 1
  }

  while IFS= read -r release_asset_name; do
    [[ -f "$RELEASE_DIR/$release_asset_name" ]] || {
      echo "ERROR: Missing payload asset: $release_asset_name" >&2
      exit 1
    }
  done < <(jq -r '.artifacts[].release_asset_name' <<< "$component")

  (
    cd "$RELEASE_DIR"
    sha256sum -c "$checksum_asset"
  )
done < <(jq -c '.components[]' "$DEPLOYMENT_MANIFEST")

echo "Release assets verified successfully."
