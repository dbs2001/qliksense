#!/usr/bin/env bash
set -euo pipefail
RELEASE_DIR="${1:?RELEASE_DIR is required}"
manifest="$RELEASE_DIR/component-manifest.json"; checksums="$RELEASE_DIR/payload-checksums.sha256"
[[ -f "$manifest" && -f "$checksums" ]] || { echo "ERROR: Release manifest/checksums missing." >&2; exit 1; }
prerelease_tag="$(jq -r '.prerelease_tag' "$manifest")"; source_commit="$(jq -r '.source_commit' "$manifest")"; git fetch origin --tags --force; tag_commit="$(git rev-list -n 1 "$prerelease_tag" 2>/dev/null || true)"; [[ "$tag_commit" == "$source_commit" ]] || { echo "ERROR: Prerelease tag verification failed." >&2; exit 1; }
while IFS= read -r asset_name; do [[ -f "$RELEASE_DIR/$asset_name" ]] || { echo "ERROR: Missing release asset: $asset_name" >&2; exit 1; }; done < <(jq -r '.artifacts[].release_asset_name' "$manifest")
( cd "$RELEASE_DIR"; sha256sum -c payload-checksums.sha256 )
