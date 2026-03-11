import AppKit
@preconcurrency import ApplicationServices
@preconcurrency import Carbon
import CoreGraphics
import Foundation
import Network
import RemoteProtocol

public struct RemoteConnectionConfiguration: Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var key: String

    public init(host: String, port: UInt16 = 6837, key: String) {
        self.host = host
        self.port = port
        self.key = key
    }
}

public enum RemoteSessionPhase: Equatable, Sendable {
    case idle
    case connecting
    case connected
    case controlling
    case failed(String)
}

public enum KeyCaptureScope: String, CaseIterable, Codable, Equatable, Sendable {
    case application = "app_only"
    case session = "whole_session"
}

public struct ToggleHotKey: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var displayName: String

    public init(keyCode: UInt32, modifiers: UInt32, displayName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }

    public static let fixedControlCommandBacktick = ToggleHotKey(
        keyCode: UInt32(kVK_ANSI_Grave),
        modifiers: UInt32(controlKey | cmdKey),
        displayName: "Control+Command+`"
    )
}

public struct RemoteAppSettings: Codable, Equatable, Sendable {
    public var keyCaptureScope: KeyCaptureScope

    public init(keyCaptureScope: KeyCaptureScope = .session) {
        self.keyCaptureScope = keyCaptureScope
    }
}

public struct RemoteEventRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date = .now, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.message = message
    }
}

public struct RemoteSessionSnapshot: Equatable, Sendable {
    public var phase: RemoteSessionPhase
    public var peers: [RemoteClientDescriptor]
    public var latestAnnouncement: String?
    public var accessibilityTrusted: Bool
    public var keyCaptureActive: Bool
    public var keyCaptureScope: KeyCaptureScope
    public var globalHotKeyDisplay: String
    public var eventLog: [RemoteEventRecord]

    public init(
        phase: RemoteSessionPhase = .idle,
        peers: [RemoteClientDescriptor] = [],
        latestAnnouncement: String? = nil,
        accessibilityTrusted: Bool = false,
        keyCaptureActive: Bool = false,
        keyCaptureScope: KeyCaptureScope = .session,
        globalHotKeyDisplay: String = "Control+Command+`",
        eventLog: [RemoteEventRecord] = []
    ) {
        self.phase = phase
        self.peers = peers
        self.latestAnnouncement = latestAnnouncement
        self.accessibilityTrusted = accessibilityTrusted
        self.keyCaptureActive = keyCaptureActive
        self.keyCaptureScope = keyCaptureScope
        self.globalHotKeyDisplay = globalHotKeyDisplay
        self.eventLog = eventLog
    }
}

public enum TransportEvent: Sendable {
    case connected
    case disconnected(String?)
    case message(RemoteEnvelope)
    case decodeFailure(String)
}

public protocol RemoteTransporting: AnyObject, Sendable {
    var onEvent: (@Sendable (TransportEvent) -> Void)? { get set }
    func connect(to configuration: RemoteConnectionConfiguration) async throws
    func send(_ envelope: RemoteEnvelope) async throws
    func disconnect() async
}

public protocol AnnouncementPosting: Sendable {
    func post(_ text: String)
}

public protocol ClipboardManaging: Sendable {
    func currentString() -> String?
    func setString(_ string: String)
}

public struct CapturedKeyEvent: Equatable, Sendable {
    public let vkCode: UInt16
    public let scanCode: UInt16?
    public let extended: Bool
    public let pressed: Bool
    public let isToggleHotKey: Bool

    public init(vkCode: UInt16, scanCode: UInt16? = nil, extended: Bool = false, pressed: Bool, isToggleHotKey: Bool = false) {
        self.vkCode = vkCode
        self.scanCode = scanCode
        self.extended = extended
        self.pressed = pressed
        self.isToggleHotKey = isToggleHotKey
    }
}

private struct ActiveRemoteKey: Hashable, Sendable {
    let vkCode: UInt16
    let extended: Bool
}

@MainActor
public protocol KeyCaptureManaging: AnyObject {
    var onKeyEvent: ((CapturedKeyEvent) -> Void)? { get set }
    func start(scope: KeyCaptureScope) -> Bool
    func stop()
}

@MainActor
public protocol AccessibilityPermissionChecking: AnyObject {
    func isTrusted(prompt: Bool) -> Bool
    func openSystemSettings()
}

@MainActor
public protocol GlobalHotKeyManaging: AnyObject {
    var onToggleRequested: (() -> Void)? { get set }
    var displayName: String { get }
    func register(hotKey: ToggleHotKey)
    func unregister()
}

public protocol RemoteSettingsStoring: AnyObject, Sendable {
    func load() -> RemoteAppSettings
    func save(_ settings: RemoteAppSettings)
}

public struct VoiceOverAnnouncementBridge: AnnouncementPosting {
    public init() {}

    public func post(_ text: String) {
        Task { @MainActor in
            guard let app = NSApp else { return }
            NSAccessibility.post(
                element: app,
                notification: .announcementRequested,
                userInfo: [
                    NSAccessibility.NotificationUserInfoKey.announcement: text,
                    NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }
}

public struct SystemClipboardManager: ClipboardManaging {
    public init() {}

    public func currentString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    public func setString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

@MainActor
public final class EventTapKeyCapture: KeyCaptureManaging {
    public var onKeyEvent: ((CapturedKeyEvent) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var modifierState: [CGKeyCode: Bool] = [:]
    private var localModifierState: [UInt16: Bool] = [:]

    public init() {}

    public func start(scope: KeyCaptureScope) -> Bool {
        stop()
        switch scope {
        case .application:
            return startLocalMonitor()
        case .session:
            return startEventTap()
        }
    }

    private func startEventTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passRetained(event) }
            let capture = Unmanaged<EventTapKeyCapture>.fromOpaque(userInfo).takeUnretainedValue()
            return capture.handle(event: event, type: type)
        }
        let unmanaged = Unmanaged.passUnretained(self)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: unmanaged.toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func startLocalMonitor() -> Bool {
        guard localMonitor == nil else { return true }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard let captured = self.makeCapturedEvent(from: event) else {
                return event
            }
            self.onKeyEvent?(captured)
            return nil
        }
        return localMonitor != nil
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        runLoopSource = nil
        eventTap = nil
        self.localMonitor = nil
        modifierState.removeAll(keepingCapacity: false)
        localModifierState.removeAll(keepingCapacity: false)
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }
        guard let captured = makeCapturedEvent(from: event, type: type) else {
            return Unmanaged.passRetained(event)
        }
        onKeyEvent?(captured)
        return nil
    }

    private func makeCapturedEvent(from event: CGEvent, type: CGEventType) -> CapturedKeyEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isToggleHotKey = matchesToggleHotKey(keyCode: UInt16(keyCode), modifiers: event.flags)
        guard let mappedKey = MacVirtualKeyMapper.windowsVirtualKey(for: CGKeyCode(keyCode)) else {
            return nil
        }
        switch type {
        case .keyDown:
            return .init(vkCode: mappedKey, scanCode: MacVirtualKeyMapper.windowsScanCode(for: mappedKey), extended: MacVirtualKeyMapper.isExtended(vkCode: mappedKey), pressed: true, isToggleHotKey: isToggleHotKey)
        case .keyUp:
            return .init(vkCode: mappedKey, scanCode: MacVirtualKeyMapper.windowsScanCode(for: mappedKey), extended: MacVirtualKeyMapper.isExtended(vkCode: mappedKey), pressed: false, isToggleHotKey: isToggleHotKey)
        case .flagsChanged:
            let isPressed = event.flags.contains(MacVirtualKeyMapper.modifierFlag(for: CGKeyCode(keyCode)))
            let previous = modifierState[CGKeyCode(keyCode)] ?? false
            modifierState[CGKeyCode(keyCode)] = isPressed
            guard previous != isPressed else { return nil }
            return .init(vkCode: mappedKey, scanCode: MacVirtualKeyMapper.windowsScanCode(for: mappedKey), extended: MacVirtualKeyMapper.isExtended(vkCode: mappedKey), pressed: isPressed, isToggleHotKey: isToggleHotKey)
        default:
            return nil
        }
    }

    private func makeCapturedEvent(from event: NSEvent) -> CapturedKeyEvent? {
        let isToggleHotKey = matchesToggleHotKey(keyCode: event.keyCode, modifiers: event.modifierFlags)
        guard let mappedKey = MacVirtualKeyMapper.windowsVirtualKey(for: CGKeyCode(event.keyCode)) else {
            return nil
        }
        switch event.type {
        case .keyDown:
            return .init(vkCode: mappedKey, scanCode: MacVirtualKeyMapper.windowsScanCode(for: mappedKey), extended: MacVirtualKeyMapper.isExtended(vkCode: mappedKey), pressed: true, isToggleHotKey: isToggleHotKey)
        case .keyUp:
            return .init(vkCode: mappedKey, scanCode: MacVirtualKeyMapper.windowsScanCode(for: mappedKey), extended: MacVirtualKeyMapper.isExtended(vkCode: mappedKey), pressed: false, isToggleHotKey: isToggleHotKey)
        case .flagsChanged:
            let isPressed = event.modifierFlags.contains(MacVirtualKeyMapper.localModifierFlag(for: event.keyCode))
            let previous = localModifierState[event.keyCode] ?? false
            localModifierState[event.keyCode] = isPressed
            guard previous != isPressed else { return nil }
            return .init(vkCode: mappedKey, scanCode: MacVirtualKeyMapper.windowsScanCode(for: mappedKey), extended: MacVirtualKeyMapper.isExtended(vkCode: mappedKey), pressed: isPressed, isToggleHotKey: isToggleHotKey)
        default:
            return nil
        }
    }

    private func matchesToggleHotKey(keyCode: UInt16, modifiers: CGEventFlags) -> Bool {
        keyCode == UInt16(kVK_ANSI_Grave)
            && modifiers.contains(.maskControl)
            && modifiers.contains(.maskCommand)
            && !modifiers.contains(.maskAlternate)
            && !modifiers.contains(.maskShift)
    }

    private func matchesToggleHotKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let filtered = modifiers.intersection([.control, .command, .option, .shift])
        return keyCode == UInt16(kVK_ANSI_Grave) && filtered == [.control, .command]
    }
}

@MainActor
public final class AccessibilityPermissionManager: AccessibilityPermissionChecking {
    public init() {}

    public func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
public final class CarbonGlobalHotKeyManager: GlobalHotKeyManaging {
    public var onToggleRequested: (() -> Void)?
    public private(set) var displayName = ToggleHotKey.fixedControlCommandBacktick.displayName

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x564F5244), id: 1)

    public init() {}

    public func register(hotKey: ToggleHotKey) {
        unregister()
        displayName = hotKey.displayName
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return noErr }
            let manager = Unmanaged<CarbonGlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.id == manager.hotKeyID.id else { return noErr }
            manager.onToggleRequested?()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

public final class UserDefaultsRemoteSettingsStore: RemoteSettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard, key: String = "vo_nvda_remote_settings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> RemoteAppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? decoder.decode(RemoteAppSettings.self, from: data) else {
            return RemoteAppSettings()
        }
        return settings
    }

    public func save(_ settings: RemoteAppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

enum MacVirtualKeyMapper {
    private static let mapping: [CGKeyCode: UInt16] = [
        0: 0x41, 1: 0x53, 2: 0x44, 3: 0x46, 4: 0x48, 5: 0x47,
        6: 0x5A, 7: 0x58, 8: 0x43, 9: 0x56, 11: 0x42, 12: 0x51,
        13: 0x57, 14: 0x45, 15: 0x52, 16: 0x59, 17: 0x54, 18: 0x31,
        19: 0x32, 20: 0x33, 21: 0x34, 22: 0x36, 23: 0x35, 24: 0xBB,
        25: 0x39, 26: 0x37, 27: 0xBD, 28: 0x38, 29: 0x30, 30: 0xDD,
        31: 0x4F, 32: 0x55, 33: 0xDB, 34: 0x49, 35: 0x50, 36: 0x0D, 37: 0x4C,
        38: 0x4A, 39: 0xDE, 40: 0x4B, 41: 0xBA, 42: 0xDC, 43: 0xBC,
        44: 0xBF, 45: 0x4E, 46: 0x4D, 47: 0xBE, 48: 0x09, 49: 0x20, 50: 0xC0,
        51: 0x08, 53: 0x1B, 54: 0xA5, 55: 0xA4, 56: 0xA0, 57: 0x14, 58: 0x5B,
        59: 0xA2, 60: 0xA1, 61: 0x5C, 62: 0xA3, 65: 0x6E,
        67: 0x6A, 69: 0x6B, 71: 0x90, 75: 0x6F, 76: 0x0D, 78: 0x6D,
        79: 0x7C, 80: 0x7D, 81: 0x6C, 82: 0x60, 83: 0x61, 84: 0x62, 85: 0x63, 86: 0x64,
        87: 0x65, 88: 0x66, 89: 0x67, 91: 0x68, 92: 0x69, 96: 0x74,
        97: 0x75, 98: 0x76, 99: 0x72, 100: 0x77, 101: 0x78, 103: 0x7A,
        109: 0x79, 111: 0x7B, 115: 0x24, 116: 0x21, 117: 0x2E, 118: 0x73, 119: 0x23,
        120: 0x71, 121: 0x22, 122: 0x70, 123: 0x25, 124: 0x27, 125: 0x28,
        126: 0x26
    ]

    private static let windowsScanCodes: [UInt16: UInt16] = [
        0x08: 0x0E, 0x09: 0x0F, 0x0D: 0x1C, 0x14: 0x3A, 0x1B: 0x01, 0x20: 0x39,
        0x21: 0x49, 0x22: 0x51, 0x23: 0x4F, 0x24: 0x47, 0x25: 0x4B, 0x26: 0x48,
        0x27: 0x4D, 0x28: 0x50, 0x2E: 0x53, 0x30: 0x0B, 0x31: 0x02, 0x32: 0x03,
        0x33: 0x04, 0x34: 0x05, 0x35: 0x06, 0x36: 0x07, 0x37: 0x08, 0x38: 0x09,
        0x39: 0x0A, 0x41: 0x1E, 0x42: 0x30, 0x43: 0x2E, 0x44: 0x20, 0x45: 0x12,
        0x46: 0x21, 0x47: 0x22, 0x48: 0x23, 0x49: 0x17, 0x4A: 0x24, 0x4B: 0x25,
        0x4C: 0x26, 0x4D: 0x32, 0x4E: 0x31, 0x4F: 0x18, 0x50: 0x19, 0x51: 0x10,
        0x52: 0x13, 0x53: 0x1F, 0x54: 0x14, 0x55: 0x16, 0x56: 0x2F, 0x57: 0x11,
        0x58: 0x2D, 0x59: 0x15, 0x5A: 0x2C, 0x5B: 0x5B, 0x5C: 0x5C,
        0x60: 0x52, 0x61: 0x4F, 0x62: 0x50, 0x63: 0x51, 0x64: 0x4B, 0x65: 0x4C,
        0x66: 0x4D, 0x67: 0x47, 0x68: 0x48, 0x69: 0x49, 0x6A: 0x37, 0x6B: 0x4E,
        0x6C: 0x1C, 0x6D: 0x4A, 0x6E: 0x53, 0x6F: 0x35,
        0x70: 0x3B, 0x71: 0x3C, 0x72: 0x3D, 0x73: 0x3E, 0x74: 0x3F, 0x75: 0x40, 0x76: 0x41, 0x77: 0x42,
        0x78: 0x43, 0x79: 0x44, 0x7A: 0x57, 0x7B: 0x58, 0x7C: 0x46, 0x7D: 0x53,
        0x90: 0x45, 0xA0: 0x2A, 0xA1: 0x36, 0xA2: 0x1D, 0xA3: 0x1D, 0xA4: 0x38, 0xA5: 0x38,
        0xBA: 0x27, 0xBB: 0x0D, 0xBC: 0x33, 0xBD: 0x0C, 0xBE: 0x34, 0xBF: 0x35,
        0xC0: 0x29, 0xDB: 0x1A, 0xDC: 0x2B, 0xDD: 0x1B, 0xDE: 0x28
    ]

    static func windowsVirtualKey(for keyCode: CGKeyCode) -> UInt16? {
        mapping[keyCode]
    }

    static func windowsScanCode(for vkCode: UInt16) -> UInt16? {
        windowsScanCodes[vkCode]
    }

    static func modifierFlag(for keyCode: CGKeyCode) -> CGEventFlags {
        switch keyCode {
        case 54, 55:
            return .maskCommand
        case 56, 60:
            return .maskShift
        case 58, 61:
            return .maskAlternate
        case 59, 62:
            return .maskControl
        case 57:
            return .maskAlphaShift
        default:
            return []
        }
    }

    static func localModifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 54, 55:
            return .command
        case 56, 60:
            return .shift
        case 58, 61:
            return .option
        case 59, 62:
            return .control
        case 57:
            return .capsLock
        default:
            return []
        }
    }

    static func isExtended(vkCode: UInt16) -> Bool {
        switch vkCode {
        case 0x5C, 0xA3, 0xA5, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2D, 0x2E, 0x6F:
            return true
        default:
            return false
        }
    }
}

public final class NVDAProtocolTransport: NSObject, RemoteTransporting, @unchecked Sendable {
    public var onEvent: (@Sendable (TransportEvent) -> Void)?

    private let serializer: NewlineDelimitedJSONSerializer
    private let queue = DispatchQueue(label: "vo-nvda-remote.transport")
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    public init(serializer: NewlineDelimitedJSONSerializer = .init()) {
        self.serializer = serializer
    }

    public func connect(to configuration: RemoteConnectionConfiguration) async throws {
        let host = NWEndpoint.Host(configuration.host)
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw NSError(domain: "NVDAProtocolTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid port"])
        }
        let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options())
        let connection = NWConnection(host: host, port: port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onEvent?(.connected)
                self.receiveLoop()
            case let .failed(error):
                self.onEvent?(.disconnected(error.localizedDescription))
            case let .waiting(error):
                self.onEvent?(.disconnected(error.localizedDescription))
            case .cancelled:
                self.onEvent?(.disconnected(nil))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    public func send(_ envelope: RemoteEnvelope) async throws {
        guard let connection else {
            throw NSError(domain: "NVDAProtocolTransport", code: 2, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        let payload = try serializer.serialize(envelope)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: payload, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: false)
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.drainBuffer()
            }
            if let error {
                self.onEvent?(.disconnected(error.localizedDescription))
                return
            }
            if isComplete {
                self.onEvent?(.disconnected(nil))
                return
            }
            self.receiveLoop()
        }
    }

    private func drainBuffer() {
        while let newlineIndex = receiveBuffer.firstIndex(of: 0x0A) {
            let line = receiveBuffer.prefix(upTo: newlineIndex)
            receiveBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            do {
                let envelope = try serializer.deserialize(Data(line))
                onEvent?(.message(envelope))
            } catch {
                let payload = String(decoding: line.prefix(256), as: UTF8.self)
                onEvent?(.decodeFailure("Protocol decode failed: \(error.localizedDescription). Payload: \(payload)"))
            }
        }
    }
}

@MainActor
public final class RemoteSessionController: ObservableObject {
    @Published public private(set) var snapshot = RemoteSessionSnapshot()
    @Published public private(set) var activeConfiguration: RemoteConnectionConfiguration?

    private let transport: RemoteTransporting
    private let announcer: AnnouncementPosting
    private let clipboard: ClipboardManaging
    private let keyCapture: KeyCaptureManaging
    private let permissionChecker: AccessibilityPermissionChecking
    private let globalHotKeyManager: GlobalHotKeyManaging
    private let settingsStore: RemoteSettingsStoring
    private var settings: RemoteAppSettings
    private let stopControlKey: UInt16 = 0x7B
    private var activeRemoteKeys: Set<ActiveRemoteKey> = []
    private var pendingModifierEvents: [CapturedKeyEvent] = []
    private var queuedCapturedEvents: [CapturedKeyEvent] = []
    private var isProcessingCapturedEvents = false

    public init(
        transport: RemoteTransporting,
        announcer: AnnouncementPosting = VoiceOverAnnouncementBridge(),
        clipboard: ClipboardManaging = SystemClipboardManager(),
        keyCapture: KeyCaptureManaging = EventTapKeyCapture(),
        permissionChecker: AccessibilityPermissionChecking = AccessibilityPermissionManager(),
        globalHotKeyManager: GlobalHotKeyManaging = CarbonGlobalHotKeyManager(),
        settingsStore: RemoteSettingsStoring = UserDefaultsRemoteSettingsStore()
    ) {
        self.transport = transport
        self.announcer = announcer
        self.clipboard = clipboard
        self.keyCapture = keyCapture
        self.permissionChecker = permissionChecker
        self.globalHotKeyManager = globalHotKeyManager
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.snapshot.accessibilityTrusted = permissionChecker.isTrusted(prompt: false)
        self.snapshot.keyCaptureScope = self.settings.keyCaptureScope
        self.snapshot.globalHotKeyDisplay = ToggleHotKey.fixedControlCommandBacktick.displayName
        transport.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handle(event: event)
            }
        }
        keyCapture.onKeyEvent = { [weak self] event in
            self?.enqueueCapturedKeyEvent(event)
        }
        globalHotKeyManager.onToggleRequested = { [weak self] in
            self?.toggleControl()
        }
        globalHotKeyManager.register(hotKey: .fixedControlCommandBacktick)
    }

    public func refreshAccessibilityPermission(prompt: Bool = false) {
        snapshot.accessibilityTrusted = permissionChecker.isTrusted(prompt: prompt)
        appendEvent(snapshot.accessibilityTrusted ? "Accessibility permission granted" : "Accessibility permission missing")
    }

    public func openAccessibilitySettings() {
        permissionChecker.openSystemSettings()
        appendEvent("Opened Accessibility settings")
    }

    public func setKeyCaptureScope(_ scope: KeyCaptureScope) {
        settings.keyCaptureScope = scope
        settingsStore.save(settings)
        snapshot.keyCaptureScope = scope
        appendEvent("Key capture scope set to \(scope.rawValue)")
    }

    public func connect(host: String, port: UInt16 = 6837, key: String) async {
        await connect(using: .init(host: host, port: port, key: key))
    }

    public func connect(using configuration: RemoteConnectionConfiguration) async {
        activeConfiguration = configuration
        snapshot.phase = .connecting
        appendEvent("Connecting to \(configuration.host):\(configuration.port)")
        do {
            try await transport.connect(to: configuration)
        } catch {
            snapshot.phase = .failed(error.localizedDescription)
            appendEvent("Connection failed: \(error.localizedDescription)")
        }
    }

    public func disconnect() async {
        stopControllingLocally(reason: nil)
        pendingModifierEvents.removeAll(keepingCapacity: false)
        queuedCapturedEvents.removeAll(keepingCapacity: false)
        await releaseActiveRemoteKeys()
        await transport.disconnect()
        activeConfiguration = nil
        snapshot.phase = .idle
        snapshot.peers = []
        appendEvent("Disconnected")
    }

    public func toggleControl() {
        switch snapshot.phase {
        case .connected:
            if snapshot.keyCaptureScope == .session {
                let trusted = permissionChecker.isTrusted(prompt: true)
                snapshot.accessibilityTrusted = trusted
                guard trusted else {
                    appendEvent("Accessibility permission is required before controlling whole session")
                    return
                }
            } else {
                prepareApplicationCaptureEnvironment()
            }
            snapshot.phase = .controlling
            snapshot.keyCaptureActive = keyCapture.start(scope: snapshot.keyCaptureScope)
            guard snapshot.keyCaptureActive else {
                snapshot.phase = .connected
                appendEvent("Unable to start key capture")
                return
            }
            appendEvent("Controlling remote machine")
        case .controlling:
            stopControllingLocally(reason: "Controlling local machine")
            pendingModifierEvents.removeAll(keepingCapacity: false)
            Task {
                await releaseActiveRemoteKeys()
            }
        case .idle, .connecting, .failed:
            appendEvent("Connect before enabling control")
        }
    }

    public func pushClipboard() async {
        guard let text = clipboard.currentString(), !text.isEmpty else {
            appendEvent("Clipboard is empty")
            return
        }
        do {
            try await transport.send(.init(message: .setClipboardText(.init(text: text))))
            appendEvent("Clipboard pushed")
        } catch {
            appendEvent("Clipboard push failed: \(error.localizedDescription)")
        }
    }

    public func sendKey(vkCode: UInt16, scanCode: UInt16? = nil, extended: Bool = false, pressed: Bool = true) async {
        guard case .controlling = snapshot.phase else {
            appendEvent("Ignoring key send while not controlling")
            return
        }
        await sendRemoteKey(vkCode: vkCode, scanCode: scanCode, extended: extended, pressed: pressed)
    }

    public func sendRemoteKey(vkCode: UInt16, scanCode: UInt16? = nil, extended: Bool = false, pressed: Bool = true) async {
        guard snapshot.phase == .connected || snapshot.phase == .controlling else {
            appendEvent("Ignoring remote key send while disconnected")
            return
        }
        do {
            try await transport.send(.init(message: .key(.init(vkCode: vkCode, scanCode: scanCode, extended: extended, pressed: pressed))))
            if snapshot.phase == .controlling {
                trackRemoteKeyState(vkCode: vkCode, extended: extended, pressed: pressed)
            }
            appendEvent("Sent key \(vkCode)")
        } catch {
            appendEvent("Key send failed: \(error.localizedDescription)")
        }
    }

    public func sendCtrlAltDelete() async {
        do {
            try await transport.send(.init(message: .sendSAS))
            appendEvent("Sent secure attention sequence")
        } catch {
            appendEvent("SAS send failed: \(error.localizedDescription)")
        }
    }

    public func sendPing() async {
        do {
            try await transport.send(.init(message: .ping(.init())))
            appendEvent("Ping sent")
        } catch {
            appendEvent("Ping failed: \(error.localizedDescription)")
        }
    }

    private func handle(event: TransportEvent) {
        switch event {
        case .connected:
            guard let configuration = activeConfiguration else { return }
            snapshot.phase = .connected
            appendEvent("TLS socket connected")
            Task {
                try? await transport.send(.init(message: .protocolVersion(.init(version: remoteProtocolVersion))))
                try? await transport.send(.init(message: .join(.init(channel: configuration.key, connectionType: .master))))
            }
        case let .disconnected(reason):
            if let reason, !reason.isEmpty {
                snapshot.phase = .failed(reason)
                appendEvent("Transport disconnected: \(reason)")
            } else {
                snapshot.phase = .idle
                appendEvent("Transport disconnected")
            }
        case let .decodeFailure(message):
            appendEvent(message)
        case let .message(envelope):
            handle(message: envelope)
        }
    }

    private func handle(message envelope: RemoteEnvelope) {
        switch envelope.message {
        case let .channelJoined(payload):
            snapshot.peers = payload.clients.filter { $0.connectionType == .slave }
            appendEvent("Joined channel \(payload.channel)")
        case let .clientJoined(payload):
            if payload.client.connectionType == .slave {
                snapshot.peers.append(payload.client)
                appendEvent("Remote machine joined: \(payload.client.id)")
            }
        case let .clientLeft(payload):
            snapshot.peers.removeAll { $0.id == payload.clientID }
            appendEvent("Client \(payload.clientID) left")
        case let .speak(payload):
            let text = payload.sequence.compactMap { item -> String? in
                if case let .text(text) = item {
                    return text
                }
                return nil
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                snapshot.latestAnnouncement = text
                announcer.post(text)
                appendEvent("Speech: \(text)")
            }
        case .cancel:
            snapshot.latestAnnouncement = nil
            appendEvent("Speech cancelled")
        case let .pauseSpeech(isPaused):
            appendEvent(isPaused ? "Remote speech paused" : "Remote speech resumed")
        case let .tone(hz, length, _, _):
            appendEvent("Tone \(Int(hz))Hz for \(Int(length))ms")
        case let .wave(fileName, _):
            appendEvent("Wave cue: \(fileName)")
        case let .display(cells):
            appendEvent("Braille cells received: \(cells.count)")
        case let .setBrailleInfo(name, numCells):
            appendEvent("Braille display \(name) size \(numCells)")
        case let .setDisplaySize(sizes):
            appendEvent("Display sizes: \(sizes.map(String.init).joined(separator: ", "))")
        case let .setClipboardText(payload):
            clipboard.setString(payload.text)
            appendEvent("Clipboard updated from remote")
        case let .motd(payload):
            appendEvent("MOTD: \(payload.motd)")
        case .versionMismatch:
            snapshot.phase = .failed("Protocol version mismatch")
            appendEvent("Protocol version mismatch")
        case .nvdaNotConnected:
            snapshot.phase = .failed("Remote NVDA not connected")
            appendEvent("Remote NVDA not connected")
        case .ping:
            appendEvent("Heartbeat received")
        case let .error(payload):
            snapshot.phase = .failed(payload.message)
            appendEvent("Remote error [\(payload.code)]: \(payload.message)")
        case let .unsupported(type):
            appendEvent("Ignored unsupported relay message: \(type)")
        case .protocolVersion, .join, .key, .sendSAS, .brailleInput, .generateKey, .index:
            break
        }
    }

    private func enqueueCapturedKeyEvent(_ event: CapturedKeyEvent) {
        queuedCapturedEvents.append(event)
        guard !isProcessingCapturedEvents else { return }
        isProcessingCapturedEvents = true
        Task { @MainActor in
            await processCapturedEventQueue()
        }
    }

    private func processCapturedEventQueue() async {
        while !queuedCapturedEvents.isEmpty {
            let event = queuedCapturedEvents.removeFirst()
            await handleCapturedKeyEvent(event)
        }
        isProcessingCapturedEvents = false
    }

    private func handleCapturedKeyEvent(_ event: CapturedKeyEvent) async {
        guard case .controlling = snapshot.phase else { return }
        if event.isToggleHotKey, event.pressed {
            stopControllingLocally(reason: "Controlling local machine")
            pendingModifierEvents.removeAll(keepingCapacity: false)
            await releaseActiveRemoteKeys()
            return
        }
        if event.vkCode == stopControlKey, event.pressed {
            stopControllingLocally(reason: "Controlling local machine")
            pendingModifierEvents.removeAll(keepingCapacity: false)
            await releaseActiveRemoteKeys()
            return
        }
        if isBufferedModifier(event.vkCode) {
            await handleBufferedModifierEvent(event)
            return
        }
        if event.pressed {
            await flushPendingModifierEvents()
        }
        appendEvent("Captured key \(event.vkCode) \(event.pressed ? "down" : "up")")
        await sendRemoteKey(vkCode: event.vkCode, scanCode: event.scanCode, extended: event.extended, pressed: event.pressed)
    }

    private func trackRemoteKeyState(vkCode: UInt16, extended: Bool, pressed: Bool) {
        let key = ActiveRemoteKey(vkCode: vkCode, extended: extended)
        if pressed {
            activeRemoteKeys.insert(key)
        } else {
            activeRemoteKeys.remove(key)
        }
    }

    private func stopControllingLocally(reason: String?) {
        keyCapture.stop()
        snapshot.keyCaptureActive = false
        if case .controlling = snapshot.phase {
            snapshot.phase = .connected
        }
        if let reason {
            appendEvent(reason)
        }
    }

    private func releaseActiveRemoteKeys() async {
        let keysToRelease = activeRemoteKeys
        activeRemoteKeys.removeAll(keepingCapacity: true)
        guard !keysToRelease.isEmpty else { return }
        for key in keysToRelease {
            do {
                try await transport.send(.init(message: .key(.init(vkCode: key.vkCode, scanCode: nil, extended: key.extended, pressed: false))))
            } catch {
                appendEvent("Key release failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleBufferedModifierEvent(_ event: CapturedKeyEvent) async {
        let key = ActiveRemoteKey(vkCode: event.vkCode, extended: event.extended)
        if event.pressed {
            if !pendingModifierEvents.contains(where: { $0.vkCode == event.vkCode && $0.extended == event.extended }) &&
                !activeRemoteKeys.contains(key) {
                pendingModifierEvents.append(event)
            }
            return
        }
        if let index = pendingModifierEvents.firstIndex(where: { $0.vkCode == event.vkCode && $0.extended == event.extended }) {
            let pending = pendingModifierEvents.remove(at: index)
            appendEvent("Captured key \(pending.vkCode) down")
            await sendRemoteKey(vkCode: pending.vkCode, scanCode: pending.scanCode, extended: pending.extended, pressed: true)
            appendEvent("Captured key \(event.vkCode) up")
            await sendRemoteKey(vkCode: event.vkCode, scanCode: event.scanCode, extended: event.extended, pressed: false)
            return
        }
        appendEvent("Captured key \(event.vkCode) up")
        await sendRemoteKey(vkCode: event.vkCode, scanCode: event.scanCode, extended: event.extended, pressed: false)
    }

    private func flushPendingModifierEvents() async {
        let pending = pendingModifierEvents
        pendingModifierEvents.removeAll(keepingCapacity: true)
        for event in pending {
            appendEvent("Captured key \(event.vkCode) down")
            await sendRemoteKey(vkCode: event.vkCode, scanCode: event.scanCode, extended: event.extended, pressed: true)
        }
    }

    private func isBufferedModifier(_ vkCode: UInt16) -> Bool {
        switch vkCode {
        case 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C:
            return true
        default:
            return false
        }
    }

    private func prepareApplicationCaptureEnvironment() {
        guard let app = NSApp else {
            appendEvent("App-only capture armed")
            return
        }
        app.activate(ignoringOtherApps: true)
        if let window = app.keyWindow ?? app.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
        }
        appendEvent("App-only capture armed on active VO NVDA Remote window")
    }

    private func appendEvent(_ message: String) {
        snapshot.eventLog.insert(.init(message: message), at: 0)
        snapshot.eventLog = Array(snapshot.eventLog.prefix(50))
    }
}
