# Packaging

Build a release `.app` bundle:

```bash
./scripts/build_app.sh
```

Output:

```text
dist/VO NVDA Remote.app
```

Build a DMG:

```bash
./scripts/build_dmg.sh
```

Generate the Xcode project:

```bash
./scripts/generate_xcode_project.sh
```

Build the Xcode app target without signing:

```bash
./scripts/build_xcode_app.sh
```

Archive the Xcode app target:

```bash
./scripts/archive_xcode_app.sh
```

Archive and export a Developer ID signed app:

```bash
export DEVELOPMENT_TEAM="9P4236SF25"
export CODESIGN_IDENTITY="Developer ID Application: Your Name (9P4236SF25)"
./scripts/export_developer_id_app.sh
```

Output:

```text
dist/VO_NVDA_Remote.dmg
```

Generate Sparkle update keys:

```bash
./scripts/generate_sparkle_keys.sh
```

Sign an update archive manually:

```bash
export SPARKLE_PRIVATE_ED_KEY="$(cat keys/sparkle_ed25519_private.pem)"
./scripts/sign_sparkle_update.sh dist/VO_NVDA_Remote.dmg
```

Notes:

- First launch may require granting Accessibility access if you use `Whole Session` key capture.
- `App Only` capture works without Accessibility permission but only while the app window is active.
- `build_app.sh` applies an ad-hoc signature so the bundle is structurally valid for local use.
- For public distribution on other Macs, use Developer ID signing and notarization or Gatekeeper may still block the app.
- `archive_xcode_app.sh` can switch to Apple portal access with `ALLOW_PROVISIONING_UPDATES=1`, but on this machine `xcodebuild` still reports no usable account for team `9P4236SF25`.
- `export_developer_id_app.sh` is the preferred path once a real `Developer ID Application` certificate is installed on the machine.

## Sign

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./scripts/sign_app.sh
```

## Notarize

```bash
export APPLE_ID="name@example.com"
export TEAM_ID="TEAMID"
export APP_PASSWORD="app-specific-password"
./scripts/notarize_app.sh
```

Notes:

- Sign before notarizing.
- The notarization script zips `dist/VO NVDA Remote.app`, submits it with `notarytool`, then staples the ticket.
- These scripts assume you already have a valid Developer ID certificate installed in your keychain.

## Appcast

Generate an appcast/update feed scaffold:

```bash
export APPCAST_VERSION="0.1.1"
export APPCAST_BUILD="1"
export APPCAST_URL="https://example.com/VO_NVDA_Remote.dmg"
export APPCAST_LENGTH="12345678"
export APPCAST_SIGNATURE=""
./scripts/generate_appcast.sh
```

If you want the bundle to carry a feed URL, set `APPCAST_URL` before `./scripts/build_app.sh`.
If you want in-app Sparkle update verification to work, set `SPARKLE_PUBLIC_ED_KEY` before `./scripts/build_app.sh`.
