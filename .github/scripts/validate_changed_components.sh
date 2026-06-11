#!/usr/bin/env bash

set -euo pipefail

BASE_REF="${1:-main}"
COMPONENT_ROOT="trunk-prototype"

echo "=================================================="
echo "Validating changed components"
echo "Base reference: origin/${BASE_REF}"
echo "Head commit:    ${GITHUB_SHA:-HEAD}"
echo "=================================================="

# Find files changed between the PR branch and its common ancestor with main.
CHANGED_FILES="$(
  git diff --name-only "origin/${BASE_REF}...HEAD"
)"

echo
echo "Changed files:"
if [[ -n "${CHANGED_FILES}" ]]; then
  printf '%s\n' "${CHANGED_FILES}"
else
  echo "(none)"
fi

# Derive component folders:
# qliksense/apps/app1/file      -> qliksense/apps/app1
# qliksense/assets/mappings/x   -> qliksense/assets/mappings
CHANGED_COMPONENTS="$(
  printf '%s\n' "${CHANGED_FILES}" |
  awk -F/ '
    $1 == "qliksense" &&
    ($2 == "apps" || $2 == "automations" || $2 == "assets") &&
    NF >= 4 {
      print $1 "/" $2 "/" $3
    }
  ' |
  sort -u
)"

echo
echo "Changed components:"
if [[ -n "${CHANGED_COMPONENTS}" ]]; then
  printf '%s\n' "${CHANGED_COMPONENTS}"
else
  echo "(none)"
  echo "No deployable component changes detected."
  exit 0
fi

ERROR_COUNT=0
COMPONENT_JSON='[]'

while IFS= read -r COMPONENT_PATH; do
  [[ -z "${COMPONENT_PATH}" ]] && continue

  echo
  echo "--------------------------------------------------"
  echo "Component: ${COMPONENT_PATH}"

  META_FILE="${COMPONENT_PATH}/meta.json"
  VERSION_FILE="${COMPONENT_PATH}/VERSION"

  # Required files
  if [[ ! -f "${META_FILE}" ]]; then
    echo "ERROR: Missing ${META_FILE}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    continue
  fi

  if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "ERROR: Missing ${VERSION_FILE}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    continue
  fi

  # Validate JSON syntax
  if ! jq empty "${META_FILE}" >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON in ${META_FILE}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    continue
  fi

  COMPONENT_KEY="$(jq -r '.component_key // empty' "${META_FILE}")"
  DISPLAY_NAME="$(jq -r '.display_name // empty' "${META_FILE}")"
  ARTIFACT_COUNT="$(jq '.artifacts | length' "${META_FILE}" 2>/dev/null || echo 0)"

  if [[ -z "${COMPONENT_KEY}" ]]; then
    echo "ERROR: component_key is missing in ${META_FILE}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi

  if [[ -z "${DISPLAY_NAME}" ]]; then
    echo "ERROR: display_name is missing in ${META_FILE}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi

  if [[ "${ARTIFACT_COUNT}" -eq 0 ]]; then
    echo "ERROR: artifacts must contain at least one file"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi

  # Current version
  CURRENT_VERSION="$(
    tr -d '[:space:]' < "${VERSION_FILE}"
  )"

  if [[ ! "${CURRENT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: VERSION must use MAJOR.MINOR.PATCH: ${CURRENT_VERSION}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
    continue
  fi

  # Read the previous version from the PR base.
  if git cat-file -e "origin/${BASE_REF}:${VERSION_FILE}" 2>/dev/null; then
    PREVIOUS_VERSION="$(
      git show "origin/${BASE_REF}:${VERSION_FILE}" |
      tr -d '[:space:]'
    )"

    if [[ "${CURRENT_VERSION}" == "${PREVIOUS_VERSION}" ]]; then
      echo "ERROR: Component changed but VERSION was not increased."
      echo "       Previous: ${PREVIOUS_VERSION}"
      echo "       Current:  ${CURRENT_VERSION}"
      ERROR_COUNT=$((ERROR_COUNT + 1))
      continue
    fi

    # Compare versions using sort -V.
    HIGHEST_VERSION="$(
      printf '%s\n%s\n' "${PREVIOUS_VERSION}" "${CURRENT_VERSION}" |
      sort -V |
      tail -n 1
    )"

    if [[ "${HIGHEST_VERSION}" != "${CURRENT_VERSION}" ]]; then
      echo "ERROR: VERSION was decreased."
      echo "       Previous: ${PREVIOUS_VERSION}"
      echo "       Current:  ${CURRENT_VERSION}"
      ERROR_COUNT=$((ERROR_COUNT + 1))
      continue
    fi
  else
    PREVIOUS_VERSION="new component"
  fi

  # Validate artifact declarations.
  while IFS= read -r ARTIFACT; do
    if [[ ! -f "${COMPONENT_PATH}/${ARTIFACT}" ]]; then
      echo "ERROR: Declared artifact does not exist: ${ARTIFACT}"
      ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
  done < <(jq -r '.artifacts[]' "${META_FILE}")

  COMPONENT_TYPE="$(cut -d/ -f2 <<< "${COMPONENT_PATH}")"

  echo "Component key:    ${COMPONENT_KEY}"
  echo "Component type:   ${COMPONENT_TYPE}"
  echo "Previous version: ${PREVIOUS_VERSION}"
  echo "Current version:  ${CURRENT_VERSION}"
  echo "Status:           validated"

  COMPONENT_ENTRY="$(
    jq -n \
      --arg component_key "${COMPONENT_KEY}" \
      --arg component_type "${COMPONENT_TYPE}" \
      --arg component_path "${COMPONENT_PATH}" \
      --arg version "${CURRENT_VERSION}" \
      '{
        component_key: $component_key,
        component_type: $component_type,
        component_path: $component_path,
        version: $version
      }'
  )"

  COMPONENT_JSON="$(
    jq \
      --argjson entry "${COMPONENT_ENTRY}" \
      '. + [$entry]' \
      <<< "${COMPONENT_JSON}"
  )"

done <<< "${CHANGED_COMPONENTS}"

echo
echo "=================================================="

if [[ "${ERROR_COUNT}" -gt 0 ]]; then
  echo "Validation failed with ${ERROR_COUNT} error(s)."
  exit 1
fi

echo "Validation successful."
echo "Changed component matrix:"
echo "${COMPONENT_JSON}" | jq .

# Make compact JSON available to later workflow steps.
COMPACT_JSON="$(jq -c . <<< "${COMPONENT_JSON}")"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "components=${COMPACT_JSON}" >> "${GITHUB_OUTPUT}"
  echo "has_components=true" >> "${GITHUB_OUTPUT}"
fi