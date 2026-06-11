#!/usr/bin/env bash

set -euo pipefail

BASE_SHA="${1:?BASE_SHA is required}"
DETECTION_FILE="${2:?Detection JSON file is required}"
OUTPUT_FILE="${3:-validated-components.json}"

echo "=================================================="
echo "Validate changed components"
echo "Base SHA:      $BASE_SHA"
echo "Detection:     $DETECTION_FILE"
echo "Validation out: $OUTPUT_FILE"
echo "=================================================="

if [[ ! -f "$DETECTION_FILE" ]]; then
    echo "ERROR: Detection file does not exist: $DETECTION_FILE"
    exit 1
fi

if ! jq empty "$DETECTION_FILE" >/dev/null 2>&1; then
    echo "ERROR: Detection file contains invalid JSON."
    exit 1
fi

if ! git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
    echo "ERROR: Base commit does not exist: $BASE_SHA"
    exit 1
fi

COMPONENT_COUNT="$(jq '.components | length' "$DETECTION_FILE")"

if [[ "$COMPONENT_COUNT" -eq 0 ]]; then
    EMPTY_RESULT='{
      "has_components": false,
      "components": [],
      "matrix": {
        "include": []
      }
    }'

    mkdir -p "$(dirname "$OUTPUT_FILE")"
    printf '%s\n' "$EMPTY_RESULT" > "$OUTPUT_FILE"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo 'matrix={"include":[]}' >> "$GITHUB_OUTPUT"
        echo "has_components=false" >> "$GITHUB_OUTPUT"
    fi

    echo "No deployable components require validation."
    exit 0
fi

ERROR_COUNT=0
VALIDATED_COMPONENTS='[]'

declare -A SEEN_COMPONENT_KEYS

while IFS= read -r COMPONENT_PATH; do

    [[ -z "$COMPONENT_PATH" ]] && continue

    echo
    echo "--------------------------------------------------"
    echo "Component path: $COMPONENT_PATH"

    META_FILE="$COMPONENT_PATH/meta.json"
    VERSION_FILE="$COMPONENT_PATH/VERSION"

    if [[ ! -d "$COMPONENT_PATH" ]]; then
        echo "ERROR: Component directory does not exist: $COMPONENT_PATH"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    if [[ ! -f "$META_FILE" ]]; then
        echo "ERROR: Missing metadata file: $META_FILE"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    if [[ ! -f "$VERSION_FILE" ]]; then
        echo "ERROR: Missing VERSION file: $VERSION_FILE"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    if ! jq empty "$META_FILE" >/dev/null 2>&1; then
        echo "ERROR: Invalid JSON in $META_FILE"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    COMPONENT_KEY="$(jq -r '.component_key // empty' "$META_FILE")"
    DISPLAY_NAME="$(jq -r '.display_name // empty' "$META_FILE")"

    if [[ -z "$COMPONENT_KEY" ]]; then
        echo "ERROR: component_key is missing in $META_FILE"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    if [[ ! "$COMPONENT_KEY" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "ERROR: Invalid component_key: $COMPONENT_KEY"
        echo "       Allowed characters: letters, numbers, dot, underscore, hyphen"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    if [[ -n "${SEEN_COMPONENT_KEYS[$COMPONENT_KEY]:-}" ]]; then
        echo "ERROR: Duplicate component_key detected: $COMPONENT_KEY"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    SEEN_COMPONENT_KEYS["$COMPONENT_KEY"]=1

    if [[ -z "$DISPLAY_NAME" ]]; then
        echo "ERROR: display_name is missing in $META_FILE"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi

    if ! jq -e '.artifacts | type == "array" and length > 0' \
        "$META_FILE" >/dev/null 2>&1; then

        echo "ERROR: artifacts must be a non-empty JSON array in $META_FILE"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    CURRENT_VERSION="$(
        tr -d '[:space:]' < "$VERSION_FILE"
    )"

    if [[ ! "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: VERSION must use MAJOR.MINOR.PATCH."
        echo "       Current value: $CURRENT_VERSION"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        continue
    fi

    PREVIOUS_VERSION="new-component"

    if git cat-file -e "${BASE_SHA}:${VERSION_FILE}" 2>/dev/null; then

        PREVIOUS_VERSION="$(
            git show "${BASE_SHA}:${VERSION_FILE}" |
            tr -d '[:space:]'
        )"

        if [[ ! "$PREVIOUS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "ERROR: Previous VERSION is invalid: $PREVIOUS_VERSION"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
        fi

        if [[ "$CURRENT_VERSION" == "$PREVIOUS_VERSION" ]]; then
            echo "ERROR: Component changed but VERSION was not increased."
            echo "       Previous: $PREVIOUS_VERSION"
            echo "       Current:  $CURRENT_VERSION"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
        fi

        HIGHEST_VERSION="$(
            printf '%s\n%s\n' \
                "$PREVIOUS_VERSION" \
                "$CURRENT_VERSION" |
            sort -V |
            tail -n 1
        )"

        if [[ "$HIGHEST_VERSION" != "$CURRENT_VERSION" ]]; then
            echo "ERROR: Component VERSION was decreased."
            echo "       Previous: $PREVIOUS_VERSION"
            echo "       Current:  $CURRENT_VERSION"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
        fi
    fi

    ARTIFACTS_JSON="$(jq -c '.artifacts' "$META_FILE")"

    while IFS= read -r ARTIFACT; do

        if [[ "$ARTIFACT" == /* ]]; then
            echo "ERROR: Artifact must use a component-relative path: $ARTIFACT"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
        fi

        if [[ "$ARTIFACT" == *".."* ]]; then
            echo "ERROR: Artifact path must not contain '..': $ARTIFACT"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
        fi

        ARTIFACT_PATH="$COMPONENT_PATH/$ARTIFACT"

        if [[ ! -f "$ARTIFACT_PATH" ]]; then
            echo "ERROR: Declared artifact does not exist: $ARTIFACT_PATH"
            ERROR_COUNT=$((ERROR_COUNT + 1))
        fi

    done < <(jq -r '.artifacts[]' "$META_FILE")

    COMPONENT_TYPE="$(cut -d/ -f1 <<< "$COMPONENT_PATH")"

    case "$COMPONENT_TYPE" in
        apps)
            COMPONENT_TYPE="qlik_app"
            ;;
        automations)
            COMPONENT_TYPE="automation"
            ;;
        assets)
            COMPONENT_TYPE="asset_bundle"
            ;;
        *)
            echo "ERROR: Unsupported component category: $COMPONENT_TYPE"
            ERROR_COUNT=$((ERROR_COUNT + 1))
            continue
            ;;
    esac

    echo "Component key:    $COMPONENT_KEY"
    echo "Display name:     $DISPLAY_NAME"
    echo "Component type:   $COMPONENT_TYPE"
    echo "Previous version: $PREVIOUS_VERSION"
    echo "Current version:  $CURRENT_VERSION"
    echo "Artifacts:        $ARTIFACTS_JSON"

    COMPONENT_ENTRY="$(
        jq -n \
            --arg component_key "$COMPONENT_KEY" \
            --arg display_name "$DISPLAY_NAME" \
            --arg component_type "$COMPONENT_TYPE" \
            --arg component_path "$COMPONENT_PATH" \
            --arg previous_version "$PREVIOUS_VERSION" \
            --arg version "$CURRENT_VERSION" \
            --argjson artifacts "$ARTIFACTS_JSON" \
            '{
                component_key: $component_key,
                display_name: $display_name,
                component_type: $component_type,
                component_path: $component_path,
                previous_version: $previous_version,
                version: $version,
                artifacts: $artifacts
            }'
    )"

    VALIDATED_COMPONENTS="$(
        jq \
            --argjson component "$COMPONENT_ENTRY" \
            '. + [$component]' \
            <<< "$VALIDATED_COMPONENTS"
    )"

done < <(jq -r '.components[]' "$DETECTION_FILE")

echo
echo "=================================================="

if [[ "$ERROR_COUNT" -gt 0 ]]; then
    echo "Validation failed with $ERROR_COUNT error(s)."
    exit 1
fi

RESULT="$(
    jq -n \
        --argjson components "$VALIDATED_COMPONENTS" \
        '{
            has_components: ($components | length > 0),
            components: $components,
            matrix: {
                include: $components
            }
        }'
)"

mkdir -p "$(dirname "$OUTPUT_FILE")"

printf '%s\n' "$RESULT" > "$OUTPUT_FILE"

echo "Validation successful."
echo
echo "Validated components:"
jq . "$OUTPUT_FILE"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "matrix=$(jq -c '.matrix' "$OUTPUT_FILE")" >> "$GITHUB_OUTPUT"
    echo "components=$(jq -c '.components' "$OUTPUT_FILE")" >> "$GITHUB_OUTPUT"
    echo "has_components=true" >> "$GITHUB_OUTPUT"
fi