#!/usr/bin/env bash
set -euo pipefail
MANIFEST_FILE="${1:?MANIFEST_FILE is required}"
stable_tag="$(jq -r '.stable_tag' "$MANIFEST_FILE")"; prerelease_tag="$(jq -r '.prerelease_tag' "$MANIFEST_FILE")"; source_commit="$(jq -r '.source_commit' "$MANIFEST_FILE")"; git fetch origin --tags --force; rc_commit="$(git rev-list -n 1 "$prerelease_tag" 2>/dev/null || true)"; [[ "$rc_commit" == "$source_commit" ]] || { echo "ERROR: RC tag mismatch." >&2; exit 1; }
if existing="$(git rev-list -n 1 "$stable_tag" 2>/dev/null)"; then [[ "$existing" == "$source_commit" ]] || { echo "ERROR: Stable tag conflict." >&2; exit 1; }; else git tag -a "$stable_tag" "$source_commit" -m "Production release $stable_tag"; git push origin "refs/tags/$stable_tag"; fi
