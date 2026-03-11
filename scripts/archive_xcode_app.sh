#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/VONVDARemote.xcodeproj"
SCHEME="${SCHEME:-VONVDARemoteApp}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/VONVDARemote.xcarchive}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-0}"

"$ROOT_DIR/scripts/generate_xcode_project.sh"

cd "$ROOT_DIR"

ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -destination "$DESTINATION"
  -archivePath "$ARCHIVE_PATH"
  archive
)

if [[ "$ALLOW_PROVISIONING_UPDATES" == "1" ]]; then
  ARGS+=(-allowProvisioningUpdates)
else
  ARGS+=(CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild "${ARGS[@]}"
