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
        let keyCapture = MockKeyCapture()
        let permissionChecker = MockPermissionChecker(isTrusted: true)
        let hotKeyManager = MockGlobalHotKeyManager()
        let settingsStore = MockSettingsStore()
        let controller = RemoteSessionController(
            transport: transport,
            announcer: announcer,
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
    func testStopControlShortcutDisablesCaptureWithoutSendingShortcut() async throws {
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
        keyCapture.emit(.init(vkCode: 0x7B, scanCode: 123, pressed: true))
        await settle()

        XCTAssertEqual(controller.snapshot.phase, .connected)
        XCTAssertFalse(controller.snapshot.keyCaptureActive)
        XCTAssertEqual(keyCapture.stopCallCount, 1)
        XCTAssertFalse(transport.sentMessages.contains { envelope in
            if case let .key(payload) = envelope.message {
                return payload.vkCode == 0x7B && payload.pressed
            }
            return false
        })
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
    func testSettingsPersistenceUpdatesScopeOnly() async throws {
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
        XCTAssertEqual(hotKeyManager.registeredHotKeys.last, .fixedControlCommandBacktick)
        XCTAssertEqual(controller.snapshot.globalHotKeyDisplay, ToggleHotKey.fixedControlCommandBacktick.displayName)
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
        keyCapture.emit(.init(vkCode: 0x41, scanCode: 0x1E, pressed: true))
        await settle()
        controller.toggleControl()
        await settle()

        XCTAssertTrue(transport.sentMessages.contains { envelope in
            if case let .key(payload) = envelope.message {
                return payload.vkCode == 0x41 && payload.pressed == false
            }
            return false
        })
    }

    func testMacModifierMappingMatchesRequestedLayout() {
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 55), 0xA4)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 54), 0xA5)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 58), 0x5B)
        XCTAssertEqual(MacVirtualKeyMapper.windowsVirtualKey(for: 61), 0x5C)
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

    private func assertTrailingKeySequence(_ envelopes: [RemoteEnvelope], expected: [KeyPayload], file: StaticString = #filePath, line: UInt = #line) {
        let keyMessages = envelopes.compactMap { envelope -> KeyPayload? in
            if case let .key(payload) = envelope.message {
                return payload
            }
            return nil
        }
        XCTAssertEqual(Array(keyMessages.suffix(expected.count)), expected, file: file, line: line)
    }
}

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
    var startResult = true

    func start(scope: KeyCaptureScope) -> Bool {
        startCallCount += 1
        startedScopes.append(scope)
        return startResult
    }

    func stop() {
        stopCallCount += 1
    }

    func emit(_ event: CapturedKeyEvent) {
        onKeyEvent?(event)
    }
}

@MainActor
private final class MockGlobalHotKeyManager: GlobalHotKeyManaging {
    var onToggleRequested: (() -> Void)?
    private(set) var displayName = ToggleHotKey.fixedControlCommandBacktick.displayName
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
