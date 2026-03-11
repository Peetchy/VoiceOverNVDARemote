#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/VO NVDA Remote.app}"
DMG_PATH="${2:-$ROOT_DIR/dist/VO_NVDA_Remote.dmg}"
VOLUME_NAME="${VOLUME_NAME:-VO NVDA Remote}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found at: $APP_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$TMP_DIR/"
ln -s /Applications "$TMP_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$TMP_DIR" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "Created DMG at: $DMG_PATH"
