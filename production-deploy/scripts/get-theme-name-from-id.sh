#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ENVIRONMENT_TARGET:-}" ]]; then
  echo "ENVIRONMENT_TARGET is required"
  exit 1
fi

if [[ -z "${THEME_ID:-}" ]]; then
  echo "THEME_ID is required"
  exit 1
fi

RAW=$(shopify theme list -e="$ENVIRONMENT_TARGET" --id="$THEME_ID" --json 2>/dev/null || true)
JSON=$(printf '%s\n' "$RAW" | sed -n '/^[[:space:]]*[[{]/,$p')
THEME_NAME=$(printf '%s\n' "$JSON" | jq -r 'if type == "array" then .[0].name else .name end' 2>/dev/null || true)

if [[ -z "$THEME_NAME" || "$THEME_NAME" == "null" ]]; then
  echo "No theme named for id ${THEME_ID} in environment ${ENVIRONMENT_TARGET}"
  exit 1
fi

echo "theme-name=${THEME_NAME}" >> "$GITHUB_OUTPUT"
