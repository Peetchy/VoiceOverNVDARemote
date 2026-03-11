#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="VO NVDA Remote"
EXECUTABLE_NAME="VONVDARemote"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
APPCAST_URL="${APPCAST_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
APP_DIR="$ROOT_DIR/dist/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

swift build -c release --product "$EXECUTABLE_NAME"
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$FRAMEWORKS_DIR"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"

if [[ -d "$BUILD_DIR/Sparkle.framework" ]]; then
  cp -R "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>VONVDARemote</string>
    <key>CFBundleIdentifier</key>
    <string>com.vo-nvda-remote.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VO NVDA Remote</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>__APP_VERSION__</string>
    <key>CFBundleVersion</key>
    <string>__APP_BUILD__</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>VO NVDA Remote uses accessibility features to capture keyboard input for remote control.</string>
    <key>NSHumanReadableCopyright</key>
    <string>VO NVDA Remote</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

perl -0pi -e "s/__APP_VERSION__/${APP_VERSION}/g; s/__APP_BUILD__/${APP_BUILD}/g" "$CONTENTS_DIR/Info.plist"

if [[ -n "$APPCAST_URL" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $APPCAST_URL" "$CONTENTS_DIR/Info.plist"
fi

if [[ -n "$SPARKLE_PUBLIC_ED_KEY" ]]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_ED_KEY" "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$CONTENTS_DIR/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool true" "$CONTENTS_DIR/Info.plist"
fi

touch "$CONTENTS_DIR/PkgInfo"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

# Produce a valid bundle signature even when no Developer ID certificate is configured.
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Created app bundle at: $APP_DIR"
