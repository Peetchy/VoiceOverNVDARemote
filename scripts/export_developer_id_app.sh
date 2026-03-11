#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/VONVDARemote.xcodeproj"
SCHEME="${SCHEME:-VONVDARemoteApp}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT_DIR/dist/VONVDARemote-DeveloperID.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-$ROOT_DIR/dist/developer-id-export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$ROOT_DIR/XcodeSupport/DeveloperIDExportOptions.plist}"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer Team ID}"
: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application certificate name}"

"$ROOT_DIR/scripts/generate_xcode_project.sh"
mkdir -p "$ROOT_DIR/dist"

cd "$ROOT_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  archive

rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

echo "Developer ID export created at: $EXPORT_PATH"
