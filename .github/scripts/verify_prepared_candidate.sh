#!/usr/bin/env bash
set -euo pipefail
CANDIDATE_DIR="${1:?CANDIDATE_DIR is required}"
[[ -f "$CANDIDATE_DIR/component-manifest.json" && -f "$CANDIDATE_DIR/payload-checksums.sha256" ]] || { echo "ERROR: Candidate manifest/checksums missing." >&2; exit 1; }
( cd "$CANDIDATE_DIR/payload"; sha256sum -c ../payload-checksums.sha256 )
