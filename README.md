# VO NVDA Remote

VO NVDA Remote is a macOS utility app that connects to the original NVDA Remote relay protocol in `control another machine` mode only.

This project is designed for VoiceOver users on macOS who need to connect to an NVDA Remote session and control a Windows machine through the public `nvdaremote` ecosystem.

## Current status

- Connects to `nvdaremote.com` over raw TLS using NVDA Remote protocol v2
- Supports master-only mode
- Supports keyboard forwarding, clipboard push, and VoiceOver announcement mapping from remote speech
- Publishes public GitHub release assets and appcast feed
- Supports app-only and whole-session key capture modes

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

Probe a relay server:

```bash
swift run RelayProbe nvdaremote.com 0871234321 6837
```

## Key capture modes

- `Whole Session`: captures keys globally with an event tap and requires Accessibility permission
- `App Only`: captures keys only while the app window is active and does not require Accessibility permission

Default stop-control key:

- `F12`

Global toggle hotkey:

- configurable in the app UI
- stored in `UserDefaults`

## Packaging

Build a release app bundle:

```bash
./scripts/build_app.sh
```

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
- uploads `VO_NVDA_Remote.dmg` and `VO_NVDA_Remote.zip`
- generates `appcast.xml`
- publishes the appcast to `gh-pages`

Release workflow file:

- [release.yml](/Users/itsawatbanlawanich/projects/vo-remote-desktop/vo-nvda-remote/.github/workflows/release.yml)

Release trigger:

```bash
git tag v0.1.2
git push origin v0.1.2
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

## Auto-update note

The app now includes Sparkle runtime support.

For in-app automatic update verification to work correctly:

- the app bundle must be built with `SUPublicEDKey`
- release archives must be signed with the matching private Ed25519 key
- the appcast must include `sparkle:edSignature`

This repository includes the required scripts and GitHub Actions wiring for that flow.
