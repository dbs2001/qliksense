#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT_MANIFEST="${1:?DEPLOYMENT_MANIFEST is required}"

git fetch origin --tags --force

while IFS=$'\t' read -r stable_tag prerelease_tag expected_commit; do
  rc_commit="$(git rev-list -n 1 "$prerelease_tag" 2>/dev/null || true)"
  [[ "$rc_commit" == "$expected_commit" ]] || {
    echo "ERROR: RC tag $prerelease_tag does not point to $expected_commit." >&2
    exit 1
  }

  if existing="$(git rev-list -n 1 "$stable_tag" 2>/dev/null)"; then
    if [[ "$existing" != "$expected_commit" ]]; then
      echo "ERROR: Stable tag $stable_tag exists at another commit." >&2
      exit 1
    fi
    echo "Stable tag already correct: $stable_tag"
  else
    git tag -a "$stable_tag" "$expected_commit" -m "Production release $stable_tag"
    git push origin "refs/tags/$stable_tag"
  fi
done < <(
  jq -r '.components[] |
    [.stable_tag, .prerelease_tag, .source_commit] | @tsv' \
    "$DEPLOYMENT_MANIFEST"
)
