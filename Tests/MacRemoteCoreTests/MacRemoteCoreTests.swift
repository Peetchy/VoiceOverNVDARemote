import XCTest
@testable import MacRemoteCore
import RemoteProtocol

final class MacRemoteCoreTests: XCTestCase {
    @MainActor
    func testConnectFlowSendsHandshakeAndTracksPeers() async throws {
        let transport = MockTransport()
        let announcer = MockAnnouncer()
        let clipboard = MockClipboard()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: announcer,
            clipboard: clipboard,
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        transport.emit(.message(.init(message: .channelJoined(.init(
            channel: "room",
            clients: [.init(id: 1, connectionType: .slave)]
        )))))
        await settle()

        XCTAssertEqual(controller.snapshot.phase, .connected)
        XCTAssertEqual(controller.snapshot.peers.count, 1)
        XCTAssertEqual(transport.sentMessages.count, 2)
    }

    @MainActor
    func testAnnouncementUpdatesSnapshotAndPostsToBridge() async throws {
        let transport = MockTransport()
        let announcer = MockAnnouncer()
        let textSpeaker = MockTextSpeaker()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: announcer,
            textSpeaker: textSpeaker,
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        transport.emit(.message(.init(message: .speak(.init(sequence: [.text("focused on desktop")], priority: "high")))))
        await settle()

        XCTAssertEqual(controller.snapshot.latestAnnouncement, "focused on desktop")
        XCTAssertEqual(announcer.messages, ["focused on desktop"])
        XCTAssertTrue(textSpeaker.messages.isEmpty)
    }

    @MainActor
    func testSpeechOutputCanSwitchToTTS() async throws {
        let transport = MockTransport()
        let announcer = MockAnnouncer()
        let textSpeaker = MockTextSpeaker()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: announcer,
            textSpeaker: textSpeaker,
            clipboard: MockClipboard(),
            keyCapture: MockKeyCapture(),
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        controller.setSpeechOutputMode(.tts)
        await controller.connect(using: sampleConfiguration(role: .master))
        transport.emit(.message(.init(message: .speak(.init(sequence: [.text("run dialog")], priority: "high")))))
        await settle()

        XCTAssertEqual(controller.snapshot.speechOutputMode, .tts)
        XCTAssertEqual(textSpeaker.messages, ["run dialog"])
        XCTAssertTrue(announcer.messages.isEmpty)
    }

    @MainActor
    func testPushClipboardAndRemoteClipboardReceive() async throws {
        let transport = MockTransport()
        let clipboard = MockClipboard(value: "copy me")
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: clipboard,
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        await controller.pushClipboard()
        transport.emit(.message(.init(message: .setClipboardText(.init(text: "from windows")))))
        await settle()

        XCTAssertTrue(transport.sentMessages.contains { $0.message == .setClipboardText(.init(text: "copy me")) })
        XCTAssertEqual(clipboard.value, "from windows")
    }

    @MainActor
    func testCopyLatestTextToClipboardUsesMostRecentSpeech() async throws {
        let transport = MockTransport()
        let clipboard = MockClipboard()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            textSpeaker: MockTextSpeaker(),
            clipboard: clipboard,
            keyCapture: MockKeyCapture(),
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        transport.emit(.message(.init(message: .speak(.init(sequence: [.text("open start menu")], priority: "high")))))
        await settle()
        controller.copyLatestTextToClipboard()

        XCTAssertEqual(clipboard.value, "open start menu")
    }

    @MainActor
    func testToggleControlStartsKeyCaptureAndForwardsKeys() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x41, scanCode: 0, pressed: true))
        keyCapture.emit(.init(vkCode: 0x41, scanCode: 0, pressed: false))
        await settle()

        XCTAssertEqual(controller.snapshot.phase, .controlling)
        XCTAssertTrue(controller.snapshot.keyCaptureActive)
        XCTAssertEqual(keyCapture.startCallCount, 1)
        XCTAssertEqual(keyCapture.startedScopes, [.session])
        XCTAssertTrue(transport.sentMessages.contains { $0.message == .key(.init(vkCode: 0x41, scanCode: 0, extended: false, pressed: true)) })
        XCTAssertTrue(transport.sentMessages.contains { $0.message == .key(.init(vkCode: 0x41, scanCode: 0, extended: false, pressed: false)) })
    }

    @MainActor
    func testF12StillForwardsWhileControlling() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x7B, scanCode: 0x58, pressed: true))
        keyCapture.emit(.init(vkCode: 0x7B, scanCode: 0x58, pressed: false))
        await settle()

        XCTAssertEqual(controller.snapshot.phase, .controlling)
        XCTAssertTrue(controller.snapshot.keyCaptureActive)
        XCTAssertTrue(transport.sentMessages.contains { $0.message == .key(.init(vkCode: 0x7B, scanCode: 0x58, extended: false, pressed: true)) })
        XCTAssertTrue(transport.sentMessages.contains { $0.message == .key(.init(vkCode: 0x7B, scanCode: 0x58, extended: false, pressed: false)) })
    }

    @MainActor
    func testToggleControlRequiresAccessibilityPermission() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: false)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()

        XCTAssertEqual(controller.snapshot.phase, .connected)
        XCTAssertFalse(controller.snapshot.accessibilityTrusted)
        XCTAssertFalse(controller.snapshot.keyCaptureActive)
        XCTAssertEqual(keyCapture.startCallCount, 0)
    }

    @MainActor
    func testRefreshPermissionUpdatesSnapshot() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: false)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        XCTAssertFalse(controller.snapshot.accessibilityTrusted)
        permissionChecker.isTrustedValue = true
        controller.refreshAccessibilityPermission()

        XCTAssertTrue(controller.snapshot.accessibilityTrusted)
    }

    @MainActor
    func testApplicationScopeCanControlWithoutAccessibilityPermission() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: false)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        controller.setKeyCaptureScope(.application)
        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        await settle()

        XCTAssertEqual(controller.snapshot.phase, .controlling)
        XCTAssertTrue(controller.snapshot.keyCaptureActive)
        XCTAssertEqual(keyCapture.startedScopes, [.application])
    }

    @MainActor
    func testGlobalHotKeyTogglesControl() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        hotKeyManager.trigger()
        await settle()
        hotKeyManager.trigger()
        await settle()

        XCTAssertEqual(hotKeyManager.registerCallCount, 1)
        XCTAssertEqual(controller.snapshot.phase, .connected)
        XCTAssertEqual(keyCapture.startCallCount, 1)
        XCTAssertEqual(keyCapture.stopCallCount, 1)
    }

    @MainActor
    func testSettingsPersistenceUpdatesScopeAndDefaults() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: settingsStore
        )

        controller.setKeyCaptureScope(.application)

        XCTAssertEqual(settingsStore.savedSettings.last?.keyCaptureScope, .application)
        XCTAssertEqual(hotKeyManager.registeredHotKeys.last, GlobalToggleHotKeyOption.controlShiftCommandR.hotKey)
        XCTAssertEqual(controller.snapshot.globalHotKeyDisplay, GlobalToggleHotKeyOption.controlShiftCommandR.displayName)
        XCTAssertEqual(controller.snapshot.modifierMapping, .default)
    }

    @MainActor
    func testGlobalHotKeySelectionPersistsAndReRegisters() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        controller.setGlobalToggleHotKey(.controlShiftCommandR)

        XCTAssertEqual(controller.snapshot.globalToggleHotKey, .controlShiftCommandR)
        XCTAssertEqual(controller.snapshot.globalHotKeyDisplay, "F12")
        XCTAssertEqual(keyCapture.lastKeyboardRouting?.toggleHotKey.displayName, "F12")
    }

    @MainActor
    func testControlModeChangesAreAnnouncedViaVoiceOverBridge() async throws {
        let transport = MockTransport()
        let announcer = MockAnnouncer()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: announcer,
            textSpeaker: MockTextSpeaker(),
            clipboard: MockClipboard(),
            keyCapture: MockKeyCapture(),
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        await settle()
        controller.toggleControl()
        await settle()

        XCTAssertTrue(announcer.messages.contains("Controlling remote machine"))
        XCTAssertTrue(announcer.messages.contains("Controlling local machine"))
    }

    @MainActor
    func testCustomModifierMappingPersistsAndUpdatesKeyboardRouting() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let mapping = RemoteModifierMapping(rightOption: .rightWindows)
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        controller.setModifierMapping(mapping)

        XCTAssertEqual(controller.snapshot.modifierMapping, mapping)
        XCTAssertEqual(keyCapture.lastKeyboardRouting?.modifierMapping, mapping)
    }

    @MainActor
    func testStopControlReleasesPressedRemoteKeys() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: permissionChecker,
            globalHotKeyManager: hotKeyManager,
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0xA2, scanCode: 0x1D, pressed: true))
        keyCapture.emit(.init(vkCode: 0x43, scanCode: 0x2E, pressed: true))
        keyCapture.emit(.init(vkCode: 0x43, scanCode: 0x2E, pressed: false))
        await settle()
        controller.toggleControl()
        await settle()

        XCTAssertTrue(transport.sentMessages.contains { envelope in
            if case let .key(payload) = envelope.message {
                return payload.vkCode == 0xA2 && payload.pressed == false
            }
            return false
        })
    }

    func testMacModifierMappingMatchesRequestedLayout() {
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 55), 0xA4)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 54), 0xA5)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 58), 0x5B)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 61), 0x5D)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 59), 0xA2)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 62), 0xA3)
    }

    func testFunctionKeyMappingMatchesWindowsFunctionKeys() {
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 122), 0x70)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 120), 0x71)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 99), 0x72)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 118), 0x73)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 96), 0x74)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 97), 0x75)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 98), 0x76)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 100), 0x77)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 101), 0x78)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 109), 0x79)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 103), 0x7A)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 111), 0x7B)
        XCTAssertEqual(MacVirtualKeyMapper.windowsScanCode(for: 0x7A), 0x57)
        XCTAssertEqual(MacVirtualKeyMapper.windowsScanCode(for: 0x7B), 0x58)
    }

    func testPlainF12MatchesToggleHotKeyButCapsLockF12DoesNot() {
        let hotKey = GlobalToggleHotKeyOption.controlShiftCommandR.hotKey
        let keyCode = UInt16(hotKey.keyCode)
        XCTAssertTrue(hotKey.matches(keyCode: keyCode, modifiers: NSEvent.ModifierFlags()))
        XCTAssertFalse(hotKey.matches(keyCode: keyCode, modifiers: [.capsLock]))
        XCTAssertFalse(hotKey.matches(keyCode: keyCode, modifiers: [.shift]))
    }

    @MainActor
    func testNVDALaptopGestureCorpusMatchesDocumentedChordRouting() async throws {
        for gesture in nvdaLaptopGestureCorpus {
            try await assertDocumentedGesture(gesture)
        }
    }

    @MainActor
    func testNVDADesktopGestureCorpusMatchesDocumentedChordRouting() async throws {
        for gesture in nvdaDesktopGestureCorpus {
            try await assertDocumentedGesture(gesture)
        }
    }

    @MainActor
    func testCapturedToggleHotKeyStopsControlWithoutForwarding() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0xC0, scanCode: 0x29, pressed: true, isToggleHotKey: true))
        await settle()

        XCTAssertEqual(controller.snapshot.phase, .connected)
        XCTAssertFalse(controller.snapshot.keyCaptureActive)
        XCTAssertFalse(transport.sentMessages.contains { envelope in
            if case let .key(payload) = envelope.message {
                return payload.vkCode == 0xC0 && payload.pressed
            }
            return false
        })
    }

    @MainActor
    func testModifierChordFlushesAsSingleSequence() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: true))
        keyCapture.emit(.init(vkCode: 0x09, scanCode: 0x0F, pressed: true))
        keyCapture.emit(.init(vkCode: 0x09, scanCode: 0x0F, pressed: false))
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: false))
        await settle()

        let keyMessages = transport.sentMessages.compactMap { envelope -> KeyPayload? in
            if case let .key(payload) = envelope.message {
                return payload
            }
            return nil
        }

        XCTAssertEqual(keyMessages.suffix(4), [
            .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: true),
            .init(vkCode: 0x09, scanCode: 0x0F, extended: false, pressed: true),
            .init(vkCode: 0x09, scanCode: 0x0F, extended: false, pressed: false),
            .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: false),
        ])
    }

    @MainActor
    func testCtrlCChordFlushesAsSingleSequence() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0xA2, scanCode: 0x1D, pressed: true))
        keyCapture.emit(.init(vkCode: 0x43, scanCode: 0x2E, pressed: true))
        keyCapture.emit(.init(vkCode: 0x43, scanCode: 0x2E, pressed: false))
        keyCapture.emit(.init(vkCode: 0xA2, scanCode: 0x1D, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: true),
                .init(vkCode: 0x43, scanCode: 0x2E, extended: false, pressed: true),
                .init(vkCode: 0x43, scanCode: 0x2E, extended: false, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testWindowsRChordFlushesAsSingleSequence() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true))
        keyCapture.emit(.init(vkCode: 0x52, scanCode: 0x13, pressed: true))
        keyCapture.emit(.init(vkCode: 0x52, scanCode: 0x13, pressed: false))
        keyCapture.emit(.init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true),
                .init(vkCode: 0x52, scanCode: 0x13, extended: false, pressed: true),
                .init(vkCode: 0x52, scanCode: 0x13, extended: false, pressed: false),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false),
            ]
        )
    }

    @MainActor
    func testShiftTabChordFlushesAsSingleSequence() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0xA0, scanCode: 0x2A, pressed: true))
        keyCapture.emit(.init(vkCode: 0x09, scanCode: 0x0F, pressed: true))
        keyCapture.emit(.init(vkCode: 0x09, scanCode: 0x0F, pressed: false))
        keyCapture.emit(.init(vkCode: 0xA0, scanCode: 0x2A, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0xA0, scanCode: 0x2A, extended: false, pressed: true),
                .init(vkCode: 0x09, scanCode: 0x0F, extended: false, pressed: true),
                .init(vkCode: 0x09, scanCode: 0x0F, extended: false, pressed: false),
                .init(vkCode: 0xA0, scanCode: 0x2A, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCtrlAltDeleteChordFlushesAsSingleSequence() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0xA2, scanCode: 0x1D, pressed: true))
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: true))
        keyCapture.emit(.init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: true))
        keyCapture.emit(.init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: false))
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: false))
        keyCapture.emit(.init(vkCode: 0xA2, scanCode: 0x1D, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: true),
                .init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: true),
                .init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testStandaloneModifierTapStillSendsPressAndRelease() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: true))
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockChordAutoReleasesAfterPrimaryKey() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x14, scanCode: 0x3A, pressed: true))
        keyCapture.emit(.init(vkCode: 0x54, scanCode: 0x14, pressed: true))
        keyCapture.emit(.init(vkCode: 0x54, scanCode: 0x14, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0x54, scanCode: 0x14, extended: false, pressed: true),
                .init(vkCode: 0x54, scanCode: 0x14, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockStandaloneTapStillReleases() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x14, scanCode: 0x3A, pressed: true))
        keyCapture.emit(.init(vkCode: 0x14, scanCode: 0x3A, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockCtrlVChordReleasesCapsLockButKeepsControlScopedToChord() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x14, scanCode: 0x3A, pressed: true))
        keyCapture.emit(.init(vkCode: 0xA2, scanCode: 0x1D, pressed: true))
        keyCapture.emit(.init(vkCode: 0x56, scanCode: 0x2F, pressed: true))
        keyCapture.emit(.init(vkCode: 0x56, scanCode: 0x2F, pressed: false))
        keyCapture.emit(.init(vkCode: 0xA2, scanCode: 0x1D, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: true),
                .init(vkCode: 0x56, scanCode: 0x2F, extended: false, pressed: true),
                .init(vkCode: 0x56, scanCode: 0x2F, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockAltTabChordReleasesCapsLockButKeepsAltScopedToChord() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x14, scanCode: 0x3A, pressed: true))
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: true))
        keyCapture.emit(.init(vkCode: 0x09, scanCode: 0x0F, pressed: true))
        keyCapture.emit(.init(vkCode: 0x09, scanCode: 0x0F, pressed: false))
        keyCapture.emit(.init(vkCode: 0xA4, scanCode: 0x38, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: true),
                .init(vkCode: 0x09, scanCode: 0x0F, extended: false, pressed: true),
                .init(vkCode: 0x09, scanCode: 0x0F, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockWindowsArrowChordReleasesCapsLockButKeepsWindowsScopedToChord() async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        keyCapture.emit(.init(vkCode: 0x14, scanCode: 0x3A, pressed: true))
        keyCapture.emit(.init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true))
        keyCapture.emit(.init(vkCode: 0x25, scanCode: 0x4B, extended: true, pressed: true))
        keyCapture.emit(.init(vkCode: 0x25, scanCode: 0x4B, extended: true, pressed: false))
        keyCapture.emit(.init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false))
        await settle()

        assertTrailingKeySequence(
            transport.sentMessages,
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true),
                .init(vkCode: 0x25, scanCode: 0x4B, extended: true, pressed: true),
                .init(vkCode: 0x25, scanCode: 0x4B, extended: true, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockCtrlAltVChordPreservesModifierOrderAndReleasesCapsLockAfterPrimaryKey() async throws {
        try await assertCapturedChord(
            [
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: true),
                .init(vkCode: 0xA2, scanCode: 0x1D, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, pressed: true),
                .init(vkCode: 0x56, scanCode: 0x2F, pressed: true),
                .init(vkCode: 0x56, scanCode: 0x2F, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, pressed: false),
            ],
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: true),
                .init(vkCode: 0x56, scanCode: 0x2F, extended: false, pressed: true),
                .init(vkCode: 0x56, scanCode: 0x2F, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockCtrlWindowsArrowChordPreservesModifierOrderAndReleasesCapsLockAfterPrimaryKey() async throws {
        try await assertCapturedChord(
            [
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: true),
                .init(vkCode: 0xA2, scanCode: 0x1D, pressed: true),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true),
                .init(vkCode: 0x27, scanCode: 0x4D, extended: true, pressed: true),
                .init(vkCode: 0x27, scanCode: 0x4D, extended: true, pressed: false),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, pressed: false),
            ],
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: true),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true),
                .init(vkCode: 0x27, scanCode: 0x4D, extended: true, pressed: true),
                .init(vkCode: 0x27, scanCode: 0x4D, extended: true, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockAltWindowsArrowChordPreservesModifierOrderAndReleasesCapsLockAfterPrimaryKey() async throws {
        try await assertCapturedChord(
            [
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, pressed: true),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true),
                .init(vkCode: 0x28, scanCode: 0x50, extended: true, pressed: true),
                .init(vkCode: 0x28, scanCode: 0x50, extended: true, pressed: false),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, pressed: false),
            ],
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: true),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: true),
                .init(vkCode: 0x28, scanCode: 0x50, extended: true, pressed: true),
                .init(vkCode: 0x28, scanCode: 0x50, extended: true, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0x5B, scanCode: 0x5B, extended: true, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testCapsLockCtrlAltDeleteChordPreservesModifierOrderAndReleasesCapsLockAfterPrimaryKey() async throws {
        try await assertCapturedChord(
            [
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: true),
                .init(vkCode: 0xA2, scanCode: 0x1D, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, pressed: true),
                .init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: true),
                .init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, pressed: false),
            ],
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: true),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: true),
                .init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: true),
                .init(vkCode: 0x2E, scanCode: 0x53, extended: true, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0xA4, scanCode: 0x38, extended: false, pressed: false),
                .init(vkCode: 0xA2, scanCode: 0x1D, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testHoldingCapsLockAcrossMultipleFunctionKeysReappliesNVDAModifierPerChord() async throws {
        try await assertCapturedChord(
            [
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: true),
                .init(vkCode: 0x70, scanCode: 0x3B, pressed: true),
                .init(vkCode: 0x70, scanCode: 0x3B, pressed: false),
                .init(vkCode: 0x71, scanCode: 0x3C, pressed: true),
                .init(vkCode: 0x71, scanCode: 0x3C, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: false),
            ],
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0x70, scanCode: 0x3B, extended: false, pressed: true),
                .init(vkCode: 0x70, scanCode: 0x3B, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0x71, scanCode: 0x3C, extended: false, pressed: true),
                .init(vkCode: 0x71, scanCode: 0x3C, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testHoldingCapsLockAcrossMultipleNumberKeysReappliesNVDAModifierPerChord() async throws {
        try await assertCapturedChord(
            [
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: true),
                .init(vkCode: 0x31, scanCode: 0x02, pressed: true),
                .init(vkCode: 0x31, scanCode: 0x02, pressed: false),
                .init(vkCode: 0x32, scanCode: 0x03, pressed: true),
                .init(vkCode: 0x32, scanCode: 0x03, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, pressed: false),
            ],
            expected: [
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0x31, scanCode: 0x02, extended: false, pressed: true),
                .init(vkCode: 0x31, scanCode: 0x02, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: true),
                .init(vkCode: 0x32, scanCode: 0x03, extended: false, pressed: true),
                .init(vkCode: 0x32, scanCode: 0x03, extended: false, pressed: false),
                .init(vkCode: 0x14, scanCode: 0x3A, extended: false, pressed: false),
            ]
        )
    }

    @MainActor
    func testDecodeFailureDoesNotDisconnectSession() async throws {
        let transport = MockTransport()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: MockKeyCapture(),
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        transport.emit(.decodeFailure("Protocol decode failed: missing field"))
        await settle()

        XCTAssertEqual(controller.snapshot.phase, .connected)
        XCTAssertTrue(controller.snapshot.eventLog.contains { $0.message.contains("Protocol decode failed") })
    }

    private func sampleConfiguration(role: RemoteRole) -> RemoteConnectionConfiguration {
        RemoteConnectionConfiguration(
            host: "localhost",
            port: 6837,
            key: "room"
        )
    }

    @MainActor
    private func settle() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func assertTrailingKeySequence(
        _ envelopes: [RemoteEnvelope],
        expected: [KeyPayload],
        label: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let keyMessages = envelopes.compactMap { envelope -> KeyPayload? in
            if case let .key(payload) = envelope.message {
                return payload
            }
            return nil
        }
        XCTAssertEqual(
            Array(keyMessages.suffix(expected.count)),
            expected,
            label.map { "Gesture: \($0)" } ?? "",
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertCapturedChord(
        _ events: [CapturedKeyEvent],
        expected: [KeyPayload],
        label: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let transport = MockTransport()
        let keyCapture = MockKeyCapture()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: MockAnnouncer(),
            clipboard: MockClipboard(),
            keyCapture: keyCapture,
            permissionChecker: MockPermissionChecker(isTrusted: true),
            globalHotKeyManager: MockGlobalHotKeyManager(),
            settingsStore: MockSettingsStore()
        )

        await controller.connect(using: sampleConfiguration(role: .master))
        await settle()
        controller.toggleControl()
        for event in events {
            keyCapture.emit(event)
        }
        await settle()

        assertTrailingKeySequence(transport.sentMessages, expected: expected, label: label, file: file, line: line)
    }

    @MainActor
    private func assertDocumentedGesture(
        _ gesture: DocumentedNVDAGesture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await assertCapturedChord(
            documentedGestureEvents(for: gesture),
            expected: documentedGestureExpectedSequence(for: gesture),
            label: gesture.name,
            file: file,
            line: line
        )
    }
}

private struct DocumentedNVDAGesture {
    let name: String
    let requiresNVDA: Bool
    let modifiers: [DocumentedGestureKey]
    let primary: DocumentedGestureKey

    init(name: String, requiresNVDA: Bool = true, modifiers: [DocumentedGestureKey], primary: DocumentedGestureKey) {
        self.name = name
        self.requiresNVDA = requiresNVDA
        self.modifiers = modifiers
        self.primary = primary
    }
}

private struct DocumentedGestureKey: Hashable {
    let vkCode: UInt16
    let extended: Bool

    init(_ vkCode: UInt16, extended: Bool? = nil) {
        self.vkCode = vkCode
        self.extended = extended ?? MacVirtualKeyMapper.isExtended(vkCode: vkCode)
    }

    var scanCode: UInt16 {
        MacVirtualKeyMapper.windowsScanCode(for: vkCode) ?? 0
    }

    var pressedEvent: CapturedKeyEvent {
        .init(vkCode: vkCode, scanCode: scanCode, extended: extended, pressed: true)
    }

    var releasedEvent: CapturedKeyEvent {
        .init(vkCode: vkCode, scanCode: scanCode, extended: extended, pressed: false)
    }

    var pressedPayload: KeyPayload {
        .init(vkCode: vkCode, scanCode: scanCode, extended: extended, pressed: true)
    }

    var releasedPayload: KeyPayload {
        .init(vkCode: vkCode, scanCode: scanCode, extended: extended, pressed: false)
    }
}

private func documentedGestureEvents(for gesture: DocumentedNVDAGesture) -> [CapturedKeyEvent] {
    var events: [CapturedKeyEvent] = []
    if gesture.requiresNVDA {
        events.append(capsLockKey.pressedEvent)
    }
    events.append(contentsOf: gesture.modifiers.map(\.pressedEvent))
    events.append(gesture.primary.pressedEvent)
    events.append(gesture.primary.releasedEvent)
    for modifier in gesture.modifiers.reversed() {
        events.append(modifier.releasedEvent)
    }
    if gesture.requiresNVDA {
        events.append(capsLockKey.releasedEvent)
    }
    return events
}

private func documentedGestureExpectedSequence(for gesture: DocumentedNVDAGesture) -> [KeyPayload] {
    var payloads: [KeyPayload] = []
    if gesture.requiresNVDA {
        payloads.append(capsLockKey.pressedPayload)
    }
    payloads.append(contentsOf: gesture.modifiers.map(\.pressedPayload))
    payloads.append(gesture.primary.pressedPayload)
    payloads.append(gesture.primary.releasedPayload)
    if gesture.requiresNVDA {
        payloads.append(capsLockKey.releasedPayload)
    }
    payloads.append(contentsOf: gesture.modifiers.reversed().map(\.releasedPayload))
    return payloads
}

private let capsLockKey = DocumentedGestureKey(0x14, extended: false)
private let shiftKey = DocumentedGestureKey(0xA0, extended: false)
private let controlKey = DocumentedGestureKey(0xA2, extended: false)
private let altKey = DocumentedGestureKey(0xA4, extended: false)
private let numpad1Key = DocumentedGestureKey(0x61, extended: false)
private let numpad2Key = DocumentedGestureKey(0x62, extended: false)
private let numpad3Key = DocumentedGestureKey(0x63, extended: false)
private let numpad4Key = DocumentedGestureKey(0x64, extended: false)
private let numpad5Key = DocumentedGestureKey(0x65, extended: false)
private let numpad6Key = DocumentedGestureKey(0x66, extended: false)
private let numpad7Key = DocumentedGestureKey(0x67, extended: false)
private let numpad8Key = DocumentedGestureKey(0x68, extended: false)
private let numpad9Key = DocumentedGestureKey(0x69, extended: false)
private let numpadMinusKey = DocumentedGestureKey(0x6D, extended: false)
private let numpadPlusKey = DocumentedGestureKey(0x6B, extended: false)
private let numpadDivideKey = DocumentedGestureKey(0x6F, extended: true)
private let numpadMultiplyKey = DocumentedGestureKey(0x6A, extended: false)
private let numpadDeleteKey = DocumentedGestureKey(0x6E, extended: false)
private let numpadEnterKey = DocumentedGestureKey(0x0D, extended: true)

private let nvdaLaptopGestureCorpus: [DocumentedNVDAGesture] = [
    .init(name: "NVDA+n", modifiers: [], primary: .init(0x4E)),
    .init(name: "NVDA+1", modifiers: [], primary: .init(0x31)),
    .init(name: "NVDA+q", modifiers: [], primary: .init(0x51)),
    .init(name: "NVDA+f2", modifiers: [], primary: .init(0x71)),
    .init(name: "NVDA+shift+s", modifiers: [shiftKey], primary: .init(0x53)),
    .init(name: "NVDA+f12", modifiers: [], primary: .init(0x7B)),
    .init(name: "NVDA+shift+b", modifiers: [shiftKey], primary: .init(0x42)),
    .init(name: "NVDA+c", modifiers: [], primary: .init(0x43)),
    .init(name: "NVDA+s", modifiers: [], primary: .init(0x53)),
    .init(name: "NVDA+tab", modifiers: [], primary: .init(0x09)),
    .init(name: "NVDA+t", modifiers: [], primary: .init(0x54)),
    .init(name: "NVDA+b", modifiers: [], primary: .init(0x42)),
    .init(name: "NVDA+end", modifiers: [], primary: .init(0x23)),
    .init(name: "NVDA+control+shift+.", modifiers: [controlKey, shiftKey], primary: .init(0xBE)),
    .init(name: "NVDA+downArrow", modifiers: [], primary: .init(0x28)),
    .init(name: "NVDA+a", modifiers: [], primary: .init(0x41)),
    .init(name: "NVDA+upArrow", modifiers: [], primary: .init(0x26)),
    .init(name: "NVDA+l", modifiers: [], primary: .init(0x4C)),
    .init(name: "NVDA+shift+upArrow", modifiers: [shiftKey], primary: .init(0x26)),
    .init(name: "NVDA+f", modifiers: [], primary: .init(0x46)),
    .init(name: "NVDA+k", modifiers: [], primary: .init(0x4B)),
    .init(name: "NVDA+delete", modifiers: [], primary: .init(0x2E)),
    .init(name: "NVDA+control+alt+downArrow", modifiers: [controlKey, altKey], primary: .init(0x28)),
    .init(name: "NVDA+control+alt+rightArrow", modifiers: [controlKey, altKey], primary: .init(0x27)),
    .init(name: "NVDA+control+alt+upArrow", modifiers: [controlKey, altKey], primary: .init(0x26)),
    .init(name: "NVDA+control+alt+leftArrow", modifiers: [controlKey, altKey], primary: .init(0x25)),
    .init(name: "NVDA+shift+o", modifiers: [shiftKey], primary: .init(0x4F)),
    .init(name: "NVDA+shift+leftArrow", modifiers: [shiftKey], primary: .init(0x25)),
    .init(name: "NVDA+shift+[", modifiers: [shiftKey], primary: .init(0xDB)),
    .init(name: "NVDA+shift+rightArrow", modifiers: [shiftKey], primary: .init(0x27)),
    .init(name: "NVDA+shift+]", modifiers: [shiftKey], primary: .init(0xDD)),
    .init(name: "NVDA+shift+downArrow", modifiers: [shiftKey], primary: .init(0x28)),
    .init(name: "NVDA+backspace", modifiers: [], primary: .init(0x08)),
    .init(name: "NVDA+enter", modifiers: [], primary: .init(0x0D)),
    .init(name: "NVDA+shift+backspace", modifiers: [shiftKey], primary: .init(0x08)),
    .init(name: "NVDA+shift+delete", modifiers: [shiftKey], primary: .init(0x2E)),
    .init(name: "NVDA+control+home", modifiers: [controlKey], primary: .init(0x24)),
    .init(name: "NVDA+shift+.", modifiers: [shiftKey], primary: .init(0xBE)),
    .init(name: "NVDA+control+end", modifiers: [controlKey], primary: .init(0x23)),
    .init(name: "NVDA+control+leftArrow", modifiers: [controlKey], primary: .init(0x25)),
    .init(name: "NVDA+control+.", modifiers: [controlKey], primary: .init(0xBE)),
    .init(name: "NVDA+control+rightArrow", modifiers: [controlKey], primary: .init(0x27)),
    .init(name: "NVDA+home", modifiers: [], primary: .init(0x24)),
    .init(name: "NVDA+leftArrow", modifiers: [], primary: .init(0x25)),
    .init(name: "NVDA+.", modifiers: [], primary: .init(0xBE)),
    .init(name: "NVDA+rightArrow", modifiers: [], primary: .init(0x27)),
    .init(name: "NVDA+pageUp", modifiers: [], primary: .init(0x21)),
    .init(name: "NVDA+shift+pageUp", modifiers: [shiftKey], primary: .init(0x21)),
    .init(name: "NVDA+pageDown", modifiers: [], primary: .init(0x22)),
    .init(name: "NVDA+shift+pageDown", modifiers: [shiftKey], primary: .init(0x22)),
    .init(name: "NVDA+alt+home", modifiers: [altKey], primary: .init(0x24)),
    .init(name: "NVDA+alt+end", modifiers: [altKey], primary: .init(0x23)),
    .init(name: "NVDA+shift+a", modifiers: [shiftKey], primary: .init(0x41)),
    .init(name: "NVDA+f9", modifiers: [], primary: .init(0x78)),
    .init(name: "NVDA+f10", modifiers: [], primary: .init(0x79)),
    .init(name: "NVDA+shift+f9", modifiers: [shiftKey], primary: .init(0x78)),
    .init(name: "NVDA+shift+f", modifiers: [shiftKey], primary: .init(0x46)),
    .init(name: "NVDA+[", modifiers: [], primary: .init(0xDB)),
    .init(name: "NVDA+control+[", modifiers: [controlKey], primary: .init(0xDB)),
    .init(name: "NVDA+]", modifiers: [], primary: .init(0xDD)),
    .init(name: "NVDA+control+]", modifiers: [controlKey], primary: .init(0xDD)),
    .init(name: "NVDA+space", modifiers: [], primary: .init(0x20)),
    .init(name: "NVDA+f5", modifiers: [], primary: .init(0x74)),
    .init(name: "NVDA+control+f", modifiers: [controlKey], primary: .init(0x46)),
    .init(name: "NVDA+f3", modifiers: [], primary: .init(0x72)),
    .init(name: "NVDA+shift+f3", modifiers: [shiftKey], primary: .init(0x72)),
    .init(name: "NVDA+f7", modifiers: [], primary: .init(0x76)),
    .init(name: "NVDA+control+space", modifiers: [controlKey], primary: .init(0x20)),
    .init(name: "NVDA+shift+f10", modifiers: [shiftKey], primary: .init(0x79)),
    .init(name: "NVDA+alt+m", modifiers: [altKey], primary: .init(0x4D)),
    .init(name: "NVDA+control+escape", modifiers: [controlKey], primary: .init(0x1B)),
    .init(name: "NVDA+shift+c", modifiers: [shiftKey], primary: .init(0x43)),
    .init(name: "NVDA+shift+r", modifiers: [shiftKey], primary: .init(0x52)),
    .init(name: "NVDA+control+1", modifiers: [controlKey], primary: .init(0x31)),
    .init(name: "NVDA+control+2", modifiers: [controlKey], primary: .init(0x32)),
    .init(name: "NVDA+control+3", modifiers: [controlKey], primary: .init(0x33)),
    .init(name: "NVDA+control+4", modifiers: [controlKey], primary: .init(0x34)),
    .init(name: "NVDA+control+g", modifiers: [controlKey], primary: .init(0x47)),
    .init(name: "NVDA+control+v", modifiers: [controlKey], primary: .init(0x56)),
    .init(name: "NVDA+p", modifiers: [], primary: .init(0x50)),
    .init(name: "NVDA+control+s", modifiers: [controlKey], primary: .init(0x53)),
    .init(name: "NVDA+control+pageUp", modifiers: [controlKey], primary: .init(0x21)),
    .init(name: "NVDA+control+downArrow", modifiers: [controlKey], primary: .init(0x28)),
    .init(name: "NVDA+control+pageDown", modifiers: [controlKey], primary: .init(0x22)),
    .init(name: "NVDA+alt+t", modifiers: [altKey], primary: .init(0x54)),
    .init(name: "NVDA+control+t", modifiers: [controlKey], primary: .init(0x54)),
    .init(name: "NVDA+control+a", modifiers: [controlKey], primary: .init(0x41)),
    .init(name: "NVDA+control+u", modifiers: [controlKey], primary: .init(0x55)),
    .init(name: "NVDA+shift+d", modifiers: [shiftKey], primary: .init(0x44)),
    .init(name: "NVDA+alt+s", modifiers: [altKey], primary: .init(0x53)),
    .init(name: "NVDA+control+k", modifiers: [controlKey], primary: .init(0x4B)),
    .init(name: "NVDA+2", modifiers: [], primary: .init(0x32)),
    .init(name: "NVDA+3", modifiers: [], primary: .init(0x33)),
    .init(name: "NVDA+4", modifiers: [], primary: .init(0x34)),
    .init(name: "NVDA+control+m", modifiers: [controlKey], primary: .init(0x4D)),
    .init(name: "NVDA+m", modifiers: [], primary: .init(0x4D)),
    .init(name: "NVDA+7", modifiers: [], primary: .init(0x37)),
    .init(name: "NVDA+6", modifiers: [], primary: .init(0x36)),
    .init(name: "NVDA+control+o", modifiers: [controlKey], primary: .init(0x4F)),
    .init(name: "NVDA+u", modifiers: [], primary: .init(0x55)),
    .init(name: "NVDA+5", modifiers: [], primary: .init(0x35)),
    .init(name: "NVDA+control+b", modifiers: [controlKey], primary: .init(0x42)),
    .init(name: "NVDA+v", modifiers: [], primary: .init(0x56)),
    .init(name: "NVDA+control+d", modifiers: [controlKey], primary: .init(0x44)),
    .init(name: "NVDA+control+c", modifiers: [controlKey], primary: .init(0x43)),
    .init(name: "NVDA+control+r", modifiers: [controlKey], primary: .init(0x52)),
    .init(name: "NVDA+alt+r", modifiers: [altKey], primary: .init(0x52)),
    .init(name: "NVDA+alt+tab", modifiers: [altKey], primary: .init(0x09)),
    .init(name: "NVDA+f1", modifiers: [], primary: .init(0x70)),
    .init(name: "NVDA+control+shift+f1", modifiers: [controlKey, shiftKey], primary: .init(0x70)),
    .init(name: "NVDA+control+f3", modifiers: [controlKey], primary: .init(0x72)),
    .init(name: "NVDA+control+f1", modifiers: [controlKey], primary: .init(0x70)),
]

private let nvdaDesktopGestureCorpus: [DocumentedNVDAGesture] = [
    .init(name: "NVDA+numpadDelete", modifiers: [], primary: numpadDeleteKey),
    .init(name: "NVDA+numpad5", modifiers: [], primary: numpad5Key),
    .init(name: "NVDA+numpad8", modifiers: [], primary: numpad8Key),
    .init(name: "NVDA+numpad4", modifiers: [], primary: numpad4Key),
    .init(name: "NVDA+numpad9", modifiers: [], primary: numpad9Key),
    .init(name: "NVDA+numpad6", modifiers: [], primary: numpad6Key),
    .init(name: "NVDA+numpad3", modifiers: [], primary: numpad3Key),
    .init(name: "NVDA+numpad2", modifiers: [], primary: numpad2Key),
    .init(name: "NVDA+numpadMinus", modifiers: [], primary: numpadMinusKey),
    .init(name: "NVDA+numpadEnter", modifiers: [], primary: numpadEnterKey),
    .init(name: "NVDA+shift+numpadMinus", modifiers: [shiftKey], primary: numpadMinusKey),
    .init(name: "NVDA+shift+numpadDelete", modifiers: [shiftKey], primary: numpadDeleteKey),
    .init(name: "NVDA+numpad7", modifiers: [], primary: numpad7Key),
    .init(name: "NVDA+numpad1", modifiers: [], primary: numpad1Key),
    .init(name: "NVDA+numpadDivide", modifiers: [], primary: numpadDivideKey),
    .init(name: "NVDA+numpadMultiply", modifiers: [], primary: numpadMultiplyKey),
    .init(name: "shift+numpad2", requiresNVDA: false, modifiers: [shiftKey], primary: numpad2Key),
    .init(name: "shift+numpad7", requiresNVDA: false, modifiers: [shiftKey], primary: numpad7Key),
    .init(name: "numpad7", requiresNVDA: false, modifiers: [], primary: numpad7Key),
    .init(name: "numpad8", requiresNVDA: false, modifiers: [], primary: numpad8Key),
    .init(name: "numpad9", requiresNVDA: false, modifiers: [], primary: numpad9Key),
    .init(name: "shift+numpad9", requiresNVDA: false, modifiers: [shiftKey], primary: numpad9Key),
    .init(name: "numpad4", requiresNVDA: false, modifiers: [], primary: numpad4Key),
    .init(name: "numpad5", requiresNVDA: false, modifiers: [], primary: numpad5Key),
    .init(name: "numpad6", requiresNVDA: false, modifiers: [], primary: numpad6Key),
    .init(name: "shift+numpad1", requiresNVDA: false, modifiers: [shiftKey], primary: numpad1Key),
    .init(name: "numpad1", requiresNVDA: false, modifiers: [], primary: numpad1Key),
    .init(name: "numpad2", requiresNVDA: false, modifiers: [], primary: numpad2Key),
    .init(name: "numpad3", requiresNVDA: false, modifiers: [], primary: numpad3Key),
    .init(name: "shift+numpad3", requiresNVDA: false, modifiers: [shiftKey], primary: numpad3Key),
    .init(name: "numpadPlus", requiresNVDA: false, modifiers: [], primary: numpadPlusKey),
    .init(name: "numpadDivide", requiresNVDA: false, modifiers: [], primary: numpadDivideKey),
    .init(name: "shift+numpadDivide", requiresNVDA: false, modifiers: [shiftKey], primary: numpadDivideKey),
    .init(name: "numpadMultiply", requiresNVDA: false, modifiers: [], primary: numpadMultiplyKey),
    .init(name: "shift+numpadMultiply", requiresNVDA: false, modifiers: [shiftKey], primary: numpadMultiplyKey),
]

private final class MockTransport: RemoteTransporting, @unchecked Sendable {
    var onEvent: (@Sendable (TransportEvent) -> Void)?
    private let lock = NSLock()
    private var storage: [RemoteEnvelope] = []

    var sentMessages: [RemoteEnvelope] {
        lock.withLock { storage }
    }

    func connect(to configuration: RemoteConnectionConfiguration) async throws {
        onEvent?(.connected)
    }

    func send(_ envelope: RemoteEnvelope) async throws {
        lock.withLock {
            storage.append(envelope)
        }
    }

    func disconnect() async {
        onEvent?(.disconnected(nil))
    }

    func emit(_ event: TransportEvent) {
        onEvent?(event)
    }
}

@MainActor
private final class MockKeyCapture: KeyCaptureManaging {
    var onKeyEvent: ((CapturedKeyEvent) -> Void)?
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var startedScopes: [KeyCaptureScope] = []
    private(set) var lastKeyboardRouting: KeyboardRoutingConfiguration?
    var startResult = true

    func start(scope: KeyCaptureScope) -> Bool {
        startCallCount += 1
        startedScopes.append(scope)
        return startResult
    }

    func stop() {
        stopCallCount += 1
    }

    func updateKeyboardRouting(_ configuration: KeyboardRoutingConfiguration) {
        lastKeyboardRouting = configuration
    }

    func emit(_ event: CapturedKeyEvent) {
        onKeyEvent?(event)
    }
}

@MainActor
private final class MockGlobalHotKeyManager: GlobalHotKeyManaging {
    var onToggleRequested: (() -> Void)?
    private(set) var displayName = GlobalToggleHotKeyOption.controlShiftCommandR.displayName
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var registeredHotKeys: [ToggleHotKey] = []

    func register(hotKey: ToggleHotKey) {
        registerCallCount += 1
        registeredHotKeys.append(hotKey)
        displayName = hotKey.displayName
    }

    func unregister() {
        unregisterCallCount += 1
    }

    func trigger() {
        onToggleRequested?()
    }
}

private final class MockSettingsStore: RemoteSettingsStoring, @unchecked Sendable {
    var current = RemoteAppSettings()
    private(set) var savedSettings: [RemoteAppSettings] = []

    func load() -> RemoteAppSettings {
        current
    }

    func save(_ settings: RemoteAppSettings) {
        current = settings
        savedSettings.append(settings)
    }
}

@MainActor
private final class MockPermissionChecker: AccessibilityPermissionChecking {
    var isTrustedValue: Bool
    private(set) var promptRequests: [Bool] = []
    private(set) var openSettingsCallCount = 0

    init(isTrusted: Bool) {
        self.isTrustedValue = isTrusted
    }

    func isTrusted(prompt: Bool) -> Bool {
        promptRequests.append(prompt)
        return isTrustedValue
    }

    func openSystemSettings() {
        openSettingsCallCount += 1
    }
}

private struct MockAnnouncer: AnnouncementPosting {
    private let storage: Storage

    init(storage: Storage = Storage()) {
        self.storage = storage
    }

    var messages: [String] {
        storage.messages
    }

    func post(_ text: String) {
        storage.messages.append(text)
    }

    final class Storage: @unchecked Sendable {
        var messages: [String] = []
    }
}

@MainActor
private final class MockTextSpeaker: TextSpeaking {
    private(set) var messages: [String] = []
    private(set) var stopCallCount = 0

    func speak(_ text: String) {
        messages.append(text)
    }

    func stop() {
        stopCallCount += 1
    }
}

private final class MockClipboard: ClipboardManaging, @unchecked Sendable {
    var value: String?

    init(value: String? = nil) {
        self.value = value
    }

    func currentString() -> String? {
        value
    }

    func setString(_ string: String) {
        value = string
    }
}
