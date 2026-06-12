#!/usr/bin/env bash
set -euo pipefail
BASE_SHA="${1:?BASE_SHA is required}"
HEAD_SHA="${2:?HEAD_SHA is required}"
OUTPUT_FILE="${3:?OUTPUT_FILE is required}"
for sha in "$BASE_SHA" "$HEAD_SHA"; do
  git cat-file -e "${sha}^{commit}" 2>/dev/null || { echo "ERROR: Commit does not exist: $sha" >&2; exit 1; }
done
changed_files="$(git diff --name-only --diff-filter=ACMRT "$BASE_SHA" "$HEAD_SHA")"
components="$(printf '%s
' "$changed_files" | awk -F/ '($1=="apps"||$1=="automations"||$1=="assets")&&NF>=3{print $1"/"$2}' | sort -u)"
changed_files_json="$(if [[ -n "$changed_files" ]]; then printf '%s
' "$changed_files"|jq -R .|jq -sc .; else echo '[]'; fi)"
components_json="$(if [[ -n "$components" ]]; then printf '%s
' "$components"|jq -R .|jq -sc .; else echo '[]'; fi)"
jq -n --argjson changed_files "$changed_files_json" --argjson components "$components_json" '{changed_files:$changed_files,components:$components,has_components:($components|length>0)}' > "$OUTPUT_FILE"
jq . "$OUTPUT_FILE"
