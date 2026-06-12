#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT_MANIFEST="${1:?DEPLOYMENT_MANIFEST is required}"

git fetch origin --tags --force

while IFS=$'\t' read -r tag commit; do
  if existing="$(git rev-list -n 1 "$tag" 2>/dev/null)"; then
    if [[ "$existing" != "$commit" ]]; then
      echo "ERROR: Tag $tag exists at $existing, expected $commit." >&2
      exit 1
    fi
    echo "Tag already correct: $tag"
  else
    git tag -a "$tag" "$commit" -m "UAT prerelease $tag"
    git push origin "refs/tags/$tag"
  fi
done < <(
  jq -r '.components[] | [.prerelease_tag, .source_commit] | @tsv' \
    "$DEPLOYMENT_MANIFEST"
)
