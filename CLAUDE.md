# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift build                          # Compile all targets
swift test                           # Run all tests
swift test --filter MacRemoteCoreTests/testName  # Run a single test
swift run VONVDARemote               # Run the app
swift run RelayProbe [host] [key] [port]  # Test relay connectivity
swift run KeyCaptureProbe            # Test app-only key capture locally
```

Build & release scripts (in `scripts/`):
- `./scripts/build_app.sh` — builds ad-hoc signed .app bundle; reads env vars `APP_VERSION`, `APP_BUILD`, `APPCAST_URL`, `SPARKLE_PUBLIC_ED_KEY`
- `./scripts/build_dmg.sh` — packages the .app into a DMG
- `./scripts/generate_xcode_project.sh` — generates Xcode project via XcodeGen

## Architecture

VONVDARemote is a macOS VoiceOver-accessible client for the NVDA Remote relay protocol (v2). It connects to a relay server over TLS (default: `nvdaremote.com`) and forwards keyboard input, clipboard, and speech to/from a Windows machine running NVDA.

### Component map

```
VONVDARemote (SwiftUI app, macOS 14+, Swift 6.0)
  └─ App.swift / ContentView.swift — UI + Sparkle auto-update
       ↓
  RemoteSessionController          (Sources/MacRemoteCore/)
  ├─ NVDAProtocolTransport         — TLS socket, newline-delimited JSON framing
  ├─ RemoteProtocol models         (Sources/RemoteProtocol/) — envelopes, payloads
  ├─ Key capture / forwarding      — app-only or whole-session CGEvent tap
  ├─ Modifier remapping            — configurable macOS→Windows key translation
  ├─ Clipboard bridge              — push/pull via protocol
  └─ Accessibility announcements   — routes remote speech to VoiceOver or TTS
```

`WindowsCompanionContract` (`Sources/WindowsCompanionContract/`) defines the interface boundary for a future Windows add-on (announcements, keyboard forwarding, clipboard sync, presence, heartbeat).

### Protocol

Messages are newline-delimited JSON. Each message has a `type` field (`RemoteMessageType`) and a `user_id` (aliased as `id` in some versions). Key types: `client_joined`, `client_left`, `speak`, `key`, `set_clipboard`, `get_clipboard`, `channel_joined`. The transport buffers partial reads and splits on `\n`.

### Key capture modes

Two modes controlled by user preference:
- **App-only** — CGEvent tap scoped to the app process
- **Whole-session** — system-wide CGEvent tap (requires Accessibility permission)

A global toggle hotkey (F12 or Ctrl+Command+`) switches control on/off without leaving the remote session.

### Tests

- `Tests/RemoteProtocolTests/` — serialization round-trips, missing fields, unknown type handling
- `Tests/MacRemoteCoreTests/` — state machine transitions, connect flow, announcements, clipboard, key forwarding; uses mock transport (no real network)

### Release CI

`.github/workflows/release.yml` triggers on `v*` tag push: build → (optional) sign → (optional) notarize → DMG → GitHub Release → Sparkle appcast published to `gh-pages`.
