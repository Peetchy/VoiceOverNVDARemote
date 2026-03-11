#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/VO NVDA Remote.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at: $APP_PATH" >&2
  exit 1
fi

: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate name}"

codesign --force --deep --options runtime --timestamp \
  --sign "$CODESIGN_IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Signed app: $APP_PATH"
