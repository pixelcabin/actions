#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f package.json ]]; then
  echo "version=" >> "$GITHUB_OUTPUT"
  exit 0
fi

VERSION=$(jq -r '.version // empty' package.json)
echo "version=${VERSION}" >> "$GITHUB_OUTPUT"
