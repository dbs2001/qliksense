#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:?ENVIRONMENT is required}"
COMPONENT_TYPE="${2:?COMPONENT_TYPE is required}"
COMPONENT_KEY="${3:?COMPONENT_KEY is required}"
ARTIFACT_PATH="${4:?ARTIFACT_PATH is required}"

[[ -f "$ARTIFACT_PATH" ]] || {
  echo "ERROR: Artifact does not exist: $ARTIFACT_PATH" >&2
  exit 1
}

echo "=================================================="
echo "SIMULATED QLIK DEPLOYMENT"
echo "Environment:    $ENVIRONMENT"
echo "Component type: $COMPONENT_TYPE"
echo "Component key:  $COMPONENT_KEY"
echo "Artifact:       $ARTIFACT_PATH"
echo "Status:         SUCCESS"
echo "=================================================="
