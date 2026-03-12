# VO NVDA Remote

VO NVDA Remote is a macOS utility app that connects to the original NVDA Remote relay protocol in `control another machine` mode only.

This project is designed for VoiceOver users on macOS who need to connect to an NVDA Remote session and control a Windows machine through the public `nvdaremote` ecosystem.

## Developer

- Itsawat Banlawanich
- Email: peet.itsawat@gmail.com

## Current status

- Connects to `nvdaremote.com` over raw TLS using NVDA Remote protocol v2
- Supports master-only mode
- Supports keyboard forwarding, clipboard push, and VoiceOver announcement mapping from remote speech
- Supports configurable global toggle hotkeys
- Supports custom left/right modifier remapping for remote key input
- Publishes public GitHub release assets and appcast feed
- Supports app-only and whole-session key capture modes

## How to use

1. Launch the app.
2. Enter the relay `Host`, `Port`, and `Session Key`.
3. Press `Connect`.
4. After the session is connected, press `Start Control` to begin sending keyboard input to the Windows machine.
5. Press `F12` to stop controlling and return the keyboard to the Mac.

Before the session connects, the app intentionally hides controls and details that only apply to an active remote session.

## Main window

The connection panel currently includes:

- `Host`, `Port`, and `Session Key`
- `Connect` / `Disconnect`
- `Capture Scope`
- `Global Hotkey`
- `Speech Output`
- `Custom Keymap`

After connecting, the host and port are still shown, but the session key is hidden.

Remote-only controls that appear after connection:

- `Start Control` / `Stop Control`
- `Send F11`
- `Push Clipboard`
- `Copy Last Text`
- `Ping`
- `Send Ctrl+Alt+Del`

Session-only detail panels that appear after connection:

- `Connected Peers`
- live session details in `Session State`

## Project structure

- `Sources/RemoteProtocol`: NVDA Remote protocol models and serializer
- `Sources/MacRemoteCore`: transport, session controller, key capture, settings, permissions
- `Sources/VONVDARemote`: SwiftUI macOS app
- `Sources/RelayProbe`: command-line probe for testing relay connectivity
- `Tests/`: protocol and session tests
- `scripts/`: build, release, signing, notarization, appcast, DMG tooling
- `docs/`: architecture, packaging, and release notes

## Development

Requirements:

- macOS 14+
- Xcode 16+
- Swift 6
- XcodeGen 2.45+ for regenerating the Xcode project

Build:

```bash
swift build
```

Run tests:

```bash
swift test
```

Run the app in development:

```bash
swift run VONVDARemote
```

Generate the Xcode project:

```bash
./scripts/generate_xcode_project.sh
```

Build the Xcode app target without signing:

```bash
./scripts/build_xcode_app.sh
```

Archive and export a Developer ID signed app:

```bash
export DEVELOPMENT_TEAM="9P4236SF25"
export CODESIGN_IDENTITY="Developer ID Application: Your Name (9P4236SF25)"
./scripts/export_developer_id_app.sh
```

Probe a relay server:

```bash
swift run RelayProbe nvdaremote.com 0871234321 6837
```

Probe app-only key capture locally:

```bash
swift run KeyCaptureProbe
```

## Key capture modes

- `Whole Session`: captures keys globally with an event tap and requires Accessibility permission
- `App Only`: captures keys only while the app window is active and does not require Accessibility permission

If `Whole Session` is selected and Accessibility access is missing, the app exposes controls to refresh permission state or open the relevant macOS settings page.

Default stop-control key:

- `F12`

## Global toggle hotkey

The toggle hotkey is configurable from the main window. Current options:

- `Control+Command+\``
- `F12`

This hotkey toggles remote control mode while the app is running.
Default selection: `F12`.

## Speech output

Remote speech output can be routed to either:

- `VoiceOver`
- `TTS`

This setting changes how incoming NVDA speech is presented on macOS, without changing the relay protocol itself.

For the best experience with `VoiceOver` output, allow VoiceOver to be controlled by scripts in VoiceOver Utility so the app can reliably interact with VoiceOver during use.

## Recommended VoiceOver setup

Create a dedicated VoiceOver activity for `VO NVDA Remote` in VoiceOver Utility and use that activity when working with the app.

คำแนะนำภาษาไทย:

- สร้าง VoiceOver activity แยกสำหรับ `VO NVDA Remote`
- ใช้ activity นี้เฉพาะตอนใช้งานแอป `VO NVDA Remote`
- ตั้ง `VoiceOver modifier keys` ให้เป็น `Control + Option` เท่านั้น
- ปิด `Announce when the Caps Lock key is pressed`

การตั้งค่านี้ช่วยลดปัญหาปุ่ม `Caps Lock` ชนกันระหว่างปุ่ม NVDA key ของเครื่อง Windows ปลายทาง กับการใช้งาน VoiceOver บนเครื่อง Mac

Setup steps:

1. Open `VoiceOver Utility` on macOS.
2. Go to the `Activities` category.
3. Create a new activity named `VO NVDA Remote`.
4. Configure the activity so it is used with `VO NVDA Remote`.
5. In that activity, set `VoiceOver modifier keys` to `Control + Option` only.
6. In that activity, turn `Announce when the Caps Lock key is pressed` off.
7. Save the activity and activate it before starting a remote control session.

Recommended activity settings:

- Set `VoiceOver modifier keys` to `Control + Option` only
- Turn `Announce when the Caps Lock key is pressed` off

This avoids conflicts between the NVDA key (`Caps Lock`) used by the remote Windows machine and the local VoiceOver key on macOS.

## Custom keymap

The `Custom Keymap` button opens a sheet for configuring how Mac modifier keys are sent to the remote Windows machine.

Configurable source keys:

- `Control Left`
- `Control Right`
- `Option Left`
- `Option Right`
- `Command Left`
- `Command Right`
- `Shift Left`
- `Shift Right`

Available target keys:

- `Left Ctrl`
- `Right Ctrl`
- `Left Alt`
- `Right Alt`
- `Left Shift`
- `Right Shift`
- `Left Windows`
- `Right Windows`
- `Application`

Default mapping:

- `Control Left` -> `Left Ctrl`
- `Control Right` -> `Right Ctrl`
- `Option Left` -> `Left Windows`
- `Option Right` -> `Application`
- `Command Left` -> `Left Alt`
- `Command Right` -> `Right Alt`
- `Shift Left` -> `Left Shift`
- `Shift Right` -> `Right Shift`

## Event flow

The app keeps an internal event log for:

- connection progress
- relay transport events
- remote speech and announcement updates
- clipboard activity
- captured and forwarded key activity

The `Event Flow` button in the `Tools` section opens this log in a separate sheet instead of showing it in the main window by default.

## Notes

- When control switches between the local Mac and the remote Windows machine, VoiceOver announces the mode change.
- `Copy Last Text` copies the most recent remote speech text received by the app to the clipboard.

## Packaging

Build a release app bundle:

```bash
./scripts/build_app.sh
```

This script produces an ad-hoc signed `.app` bundle using `codesign --sign -`.

Build a DMG:

```bash
./scripts/build_dmg.sh
```

Useful docs:

- [docs/packaging.md](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/docs/packaging.md)
- [docs/releases.md](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/docs/releases.md)

## GitHub release pipeline

The repository includes a GitHub Actions workflow that:

- builds the app on tag push
- creates a public GitHub Release
- uploads `VO_NVDA_Remote.dmg`
- deletes older GitHub releases and their tags after publishing the current one
- generates `appcast.xml`
- publishes the appcast to `gh-pages`

Release workflow file:

- [release.yml](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/.github/workflows/release.yml)

Release trigger:

```bash
git tag v0.1.1
git push origin v0.1.1
```

## Public URLs

- Releases: [github.com/Peetchy/VoiceOverNVDARemote/releases](https://github.com/Peetchy/VoiceOverNVDARemote/releases)
- Appcast: [peetchy.github.io/VoiceOverNVDARemote/appcast.xml](https://peetchy.github.io/VoiceOverNVDARemote/appcast.xml)

## Signing and notarization

Optional scripts are included for signed public builds:

- `./scripts/sign_app.sh`
- `./scripts/notarize_app.sh`

Required secrets/variables are described in [docs/releases.md](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/docs/releases.md)

Unsigned builds are ad-hoc signed so the bundle is structurally valid, but public downloads still need Developer ID signing and notarization if you want Gatekeeper to open them normally on other Macs.

The repository now also includes an Xcode app project at [VONVDARemote.xcodeproj](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/VONVDARemote.xcodeproj) for archive/distribution flows. On this machine, command-line export is still blocked by Apple account access because `xcodebuild` currently reports no usable team account for automatic signing.

## Auto-update note

The app now includes Sparkle runtime support.

For in-app automatic update verification to work correctly:

- the app bundle must be built with `SUPublicEDKey`
- release archives must be signed with the matching private Ed25519 key
- the appcast must include `sparkle:edSignature`

This repository includes the required scripts and GitHub Actions wiring for that flow.

## License

This repository is licensed under the GNU General Public License v2. See [LICENSE](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/LICENSE).
