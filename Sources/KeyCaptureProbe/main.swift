import AppKit
import Foundation
import MacRemoteCore
import RemoteProtocol

private final class ProbeTransport: RemoteTransporting, @unchecked Sendable {
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
}

@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private let transport = ProbeTransport()
    private lazy var controller = RemoteSessionController(
        transport: transport,
        announcer: SilentAnnouncer(),
        clipboard: SilentClipboard()
    )
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Key Capture Probe"
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        Task { @MainActor in
            controller.setKeyCaptureScope(.application)
            await controller.connect(host: "localhost", key: "probe")
            try? await Task.sleep(nanoseconds: 200_000_000)
            controller.toggleControl()
            try? await Task.sleep(nanoseconds: 200_000_000)
            injectKeySequence()
            try? await Task.sleep(nanoseconds: 500_000_000)
            finish()
        }
    }

    private func injectKeySequence() {
        guard let window else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        let down = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )
        let up = NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: timestamp + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )
        if let down {
            NSApp.sendEvent(down)
        }
        if let up {
            NSApp.sendEvent(up)
        }
    }

    private func finish() {
        let keyMessages = transport.sentMessages.compactMap { envelope -> KeyPayload? in
            if case let .key(payload) = envelope.message {
                return payload
            }
            return nil
        }
        print("phase=\(controller.snapshot.phase)")
        print("key_capture_active=\(controller.snapshot.keyCaptureActive)")
        let recentEvents = controller.snapshot.eventLog.prefix(5).map { $0.message }.joined(separator: " | ")
        print("event_log_top=\(recentEvents)")
        for payload in keyMessages {
            print("key vk=\(payload.vkCode) scan=\(payload.scanCode.map(String.init) ?? "nil") extended=\(payload.extended) pressed=\(payload.pressed)")
        }
        exit(keyMessages.count >= 2 ? 0 : 1)
    }
}

private struct SilentAnnouncer: AnnouncementPosting {
    func post(_ text: String) {}
}

private final class SilentClipboard: ClipboardManaging, @unchecked Sendable {
    func currentString() -> String? { nil }
    func setString(_ string: String) {}
}

private let app = NSApplication.shared
private let delegate = ProbeDelegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
