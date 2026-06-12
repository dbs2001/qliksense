#!/usr/bin/env bash
set -euo pipefail
MANIFEST_FILE="${1:?MANIFEST_FILE is required}"
tag="$(jq -r '.prerelease_tag' "$MANIFEST_FILE")"; commit="$(jq -r '.source_commit' "$MANIFEST_FILE")"; git fetch origin --tags --force
if existing="$(git rev-list -n 1 "$tag" 2>/dev/null)"; then [[ "$existing" == "$commit" ]] || { echo "ERROR: Tag conflict for $tag." >&2; exit 1; }; else git tag -a "$tag" "$commit" -m "UAT prerelease $tag"; git push origin "refs/tags/$tag"; fi
