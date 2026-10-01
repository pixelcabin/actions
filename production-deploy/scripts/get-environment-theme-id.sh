#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ENVIRONMENT_TARGET:-}" ]]; then
  echo "ENVIRONMENT_TARGET is required"
  exit 1
fi

THEME_ID=$(awk -v env="environments.${ENVIRONMENT_TARGET}" '
  $0 == "[" env "]" { capture=1; next }
  $0 ~ /^\[/ { capture=0 }
  capture && /^theme[[:space:]]*=/ { gsub(/[^0-9]/, ""); print; exit }
' shopify.theme.toml)

if [[ -z "$THEME_ID" ]]; then
  echo "No theme id in shopify.theme.toml for environment ${ENVIRONMENT_TARGET}"
  exit 1
fi

echo "theme-id=${THEME_ID}" >> "$GITHUB_OUTPUT"
