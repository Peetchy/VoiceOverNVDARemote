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
    func testSettingsPersistenceUpdatesScopeAndHotKey() async throws {
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
        controller.setGlobalHotKey(.controlOptionCommandT)

        XCTAssertEqual(settingsStore.savedSettings.last?.keyCaptureScope, .application)
        XCTAssertEqual(settingsStore.savedSettings.last?.toggleHotKey, .controlOptionCommandT)
        XCTAssertEqual(hotKeyManager.registeredHotKeys.last, .controlOptionCommandT)
        XCTAssertEqual(controller.snapshot.globalHotKeyDisplay, ToggleHotKey.controlOptionCommandT.displayName)
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
}

private final class MockTransport: RemoteTransporting, @unchecked Sendable {
    var onEvent: (@Sendable (TransportEvent) -> Void)?
    private(set) var sentMessages: [RemoteEnvelope] = []

    func connect(to configuration: RemoteConnectionConfiguration) async throws {
        onEvent?(.connected)
    }

    func send(_ envelope: RemoteEnvelope) async throws {
        sentMessages.append(envelope)
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
    private(set) var displayName = ToggleHotKey.controlOptionCommandR.displayName
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
