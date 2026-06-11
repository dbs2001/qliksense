#!/usr/bin/env bash

set -euo pipefail

BASE_SHA="${1:?BASE_SHA is required}"
HEAD_SHA="${2:?HEAD_SHA is required}"
OUTPUT_FILE="${3:-changed-components.json}"

echo "=================================================="
echo "Detect changed components"
echo "Base SHA: $BASE_SHA"
echo "Head SHA: $HEAD_SHA"
echo "=================================================="

if ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
    echo "ERROR: Base commit does not exist: $BASE_SHA"
    exit 1
fi

if ! git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null; then
    echo "ERROR: Head commit does not exist: $HEAD_SHA"
    exit 1
fi

CHANGED_FILES="$(
    git diff \
        --name-only \
        --diff-filter=ACMRT \
        "$BASE_SHA" \
        "$HEAD_SHA"
)"

echo
echo "Changed files:"

if [[ -n "$CHANGED_FILES" ]]; then
    printf '%s\n' "$CHANGED_FILES"
else
    echo "(none)"
fi

# Expected component layout:
#
# apps/<component>/...
# automations/<component>/...
# assets/<component>/...
#
# The first two path segments identify the component.
CHANGED_COMPONENTS="$(
    printf '%s\n' "$CHANGED_FILES" |
    awk -F/ '
        ($1 == "apps" || $1 == "automations" || $1 == "assets") &&
        NF >= 3 {
            print $1 "/" $2
        }
    ' |
    sort -u
)"

# Files directly under apps/, automations/, or assets/ cannot be mapped
# to an independently deployable component.
UNMAPPED_FILES="$(
    printf '%s\n' "$CHANGED_FILES" |
    awk -F/ '
        ($1 == "apps" || $1 == "automations" || $1 == "assets") &&
        NF < 3 {
            print
        }
    ' |
    sort -u
)"

if [[ -n "$UNMAPPED_FILES" ]]; then
    echo
    echo "ERROR: The following files are not inside a component folder:"
    printf '%s\n' "$UNMAPPED_FILES"
    echo
    echo "Expected structure:"
    echo "  apps/<component>/..."
    echo "  automations/<component>/..."
    echo "  assets/<component>/..."
    exit 1
fi

echo
echo "Changed components:"

if [[ -n "$CHANGED_COMPONENTS" ]]; then
    printf '%s\n' "$CHANGED_COMPONENTS"
else
    echo "(none)"
fi

CHANGED_FILES_JSON="$(
    if [[ -n "$CHANGED_FILES" ]]; then
        printf '%s\n' "$CHANGED_FILES" |
        jq -R . |
        jq -sc .
    else
        echo '[]'
    fi
)"

COMPONENTS_JSON="$(
    if [[ -n "$CHANGED_COMPONENTS" ]]; then
        printf '%s\n' "$CHANGED_COMPONENTS" |
        jq -R . |
        jq -sc .
    else
        echo '[]'
    fi
)"

HAS_COMPONENTS="false"

if [[ "$(jq 'length' <<< "$COMPONENTS_JSON")" -gt 0 ]]; then
    HAS_COMPONENTS="true"
fi

RESULT="$(
    jq -n \
        --argjson changed_files "$CHANGED_FILES_JSON" \
        --argjson components "$COMPONENTS_JSON" \
        --argjson has_components "$HAS_COMPONENTS" \
        '{
            changed_files: $changed_files,
            components: $components,
            has_components: $has_components
        }'
)"

mkdir -p "$(dirname "$OUTPUT_FILE")"

printf '%s\n' "$RESULT" > "$OUTPUT_FILE"

echo
echo "Detection result:"
jq . "$OUTPUT_FILE"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "components=$(jq -c '.components' "$OUTPUT_FILE")" >> "$GITHUB_OUTPUT"
    echo "has_components=$HAS_COMPONENTS" >> "$GITHUB_OUTPUT"
fi