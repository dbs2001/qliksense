#!/usr/bin/env bash
set -euo pipefail

CANDIDATE_DIR="${1:?CANDIDATE_DIR is required}"

[[ -d "$CANDIDATE_DIR/payload" ]] || {
  echo "ERROR: Missing payload directory in $CANDIDATE_DIR" >&2
  exit 1
}

checksum_file="$CANDIDATE_DIR/payload-checksums.sha256"

(
  cd "$CANDIDATE_DIR/payload"
  find . -maxdepth 1 -type f -printf '%f\0' |
    sort -z |
    xargs -0 sha256sum
) > "$checksum_file"

component_key="$(
  jq -r '.component_key' "$CANDIDATE_DIR"/*--component-manifest.json
)"
mv "$checksum_file" "$CANDIDATE_DIR/${component_key}--payload-checksums.sha256"
