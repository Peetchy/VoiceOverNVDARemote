#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/VONVDARemote.xcodeproj"
SCHEME="${SCHEME:-VONVDARemoteApp}"
DESTINATION="${DESTINATION:-platform=macOS}"

"$ROOT_DIR/scripts/generate_xcode_project.sh"

cd "$ROOT_DIR"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build
