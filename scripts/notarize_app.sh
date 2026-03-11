#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/VO NVDA Remote.app}"
ZIP_PATH="$ROOT_DIR/dist/VO_NVDA_Remote.zip"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at: $APP_PATH" >&2
  exit 1
fi

: "${APPLE_ID:?Set APPLE_ID to your Apple account email}"
: "${TEAM_ID:?Set TEAM_ID to your Apple Developer Team ID}"
: "${APP_PASSWORD:?Set APP_PASSWORD to an app-specific password}"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

xcrun notarytool submit "$ZIP_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
echo "Notarized app: $APP_PATH"
