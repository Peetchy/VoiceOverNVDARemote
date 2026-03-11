import MacRemoteCore
import RemoteProtocol
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: RemoteSessionController
    @ObservedObject var sparkleController: SparkleController

    @State private var host = "nvdaremote.com"
    @State private var port = "6837"
    @State private var key = "0871234321"
    @State private var captureScope: KeyCaptureScope = .session
    @State private var toggleHotKey: ToggleHotKey = .controlOptionCommandR
    @State private var isRecordingHotKey = false
    @State private var hotKeyMonitor: Any?

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                connectionPanel
                statusPanel
            }
            .frame(maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 20) {
                peerPanel
                announcementPanel
                eventPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(red: 0.94, green: 0.95, blue: 0.91), Color(red: 0.83, green: 0.88, blue: 0.81)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            captureScope = controller.snapshot.keyCaptureScope
            toggleHotKey = ToggleHotKey.presets.first(where: { $0.displayName == controller.snapshot.globalHotKeyDisplay }) ?? .controlOptionCommandR
        }
        .onDisappear {
            stopHotKeyRecording()
        }
    }

    private var connectionPanel: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Host", text: $host)
                TextField("Port", text: $port)
                SecureField("Session Key", text: $key)
                Text("Mode: control another machine")
                    .foregroundStyle(.secondary)
                Text("While controlling, local key events are captured. Press F12 to return control to this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Global toggle hotkey: \(controller.snapshot.globalHotKeyDisplay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Capture Scope", selection: $captureScope) {
                    Text("Whole Session").tag(KeyCaptureScope.session)
                    Text("App Only").tag(KeyCaptureScope.application)
                }
                .pickerStyle(.segmented)
                .onChange(of: captureScope) { _, newValue in
                    controller.setKeyCaptureScope(newValue)
                }
                Picker("Toggle Hotkey", selection: $toggleHotKey) {
                    ForEach(ToggleHotKey.presets, id: \.displayName) { hotKey in
                        Text(hotKey.displayName).tag(hotKey)
                    }
                }
                .onChange(of: toggleHotKey) { _, newValue in
                    controller.setGlobalHotKey(newValue)
                }
                HStack {
                    Button(isRecordingHotKey ? "Press New Hotkey..." : "Record Hotkey") {
                        if isRecordingHotKey {
                            stopHotKeyRecording()
                        } else {
                            startHotKeyRecording()
                        }
                    }
                    Text(controller.snapshot.globalHotKeyDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Circle()
                        .fill(controller.snapshot.accessibilityTrusted ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    Text(permissionLabel)
                        .font(.caption)
                    Spacer()
                    Button("Refresh") {
                        controller.refreshAccessibilityPermission()
                    }
                    Button("Open Settings") {
                        controller.openAccessibilitySettings()
                    }
                }

                HStack {
                    Button("Connect") {
                        Task {
                            await controller.connect(host: host, port: UInt16(port) ?? 6837, key: key)
                        }
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Disconnect") {
                        Task {
                            await controller.disconnect()
                        }
                    }
                }

                HStack {
                    Button(controlButtonTitle) {
                        controller.toggleControl()
                    }
                    Button("Send F11") {
                        Task {
                            await controller.sendKey(vkCode: 122, scanCode: 87, extended: false, pressed: true)
                            await controller.sendKey(vkCode: 122, scanCode: 87, extended: false, pressed: false)
                        }
                    }
                    Button("Push Clipboard") {
                        Task {
                            await controller.pushClipboard()
                        }
                    }
                    Button("Ping") {
                        Task {
                            await controller.sendPing()
                        }
                    }
                    Button("Check for Updates") {
                        sparkleController.checkForUpdates()
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private var permissionLabel: String {
        if captureScope == .application {
            return "App-only capture does not require Accessibility permission"
        }
        return controller.snapshot.accessibilityTrusted ? "Accessibility permission granted" : "Accessibility permission required"
    }

    private var statusPanel: some View {
        GroupBox("Session State") {
            VStack(alignment: .leading, spacing: 8) {
                Text(phaseLabel)
                    .font(.title3.weight(.semibold))
                Text("Peers: \(controller.snapshot.peers.count)")
                Text("Key capture: \(controller.snapshot.keyCaptureActive ? "active" : "inactive")")
                Text("Latest announcement: \(controller.snapshot.latestAnnouncement ?? "None")")
                    .lineLimit(3)
                Button("Send Ctrl+Alt+Del") {
                    Task {
                        await controller.sendCtrlAltDelete()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var peerPanel: some View {
        GroupBox("Connected Peers") {
            List(controller.snapshot.peers) { peer in
                HStack {
                    Text("Client \(peer.id)")
                    Spacer()
                    Text(peer.connectionType.rawValue)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var announcementPanel: some View {
        GroupBox("VoiceOver Announcements") {
            VStack(alignment: .leading, spacing: 8) {
                Text(controller.snapshot.latestAnnouncement ?? "Waiting for remote speech feedback")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("NVDA speech mapped to VoiceOver announcement")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        }
    }

    private var eventPanel: some View {
        GroupBox("Event Flow") {
            List(controller.snapshot.eventLog) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.message)
                    Text(record.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var phaseLabel: String {
        switch controller.snapshot.phase {
        case .idle:
            "Idle"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected as master"
        case .controlling:
            "Controlling remote machine"
        case let .failed(message):
            "Failed: \(message)"
        }
    }

    private var controlButtonTitle: String {
        switch controller.snapshot.phase {
        case .controlling:
            "Stop Control"
        default:
            "Start Control"
        }
    }

    private func startHotKeyRecording() {
        stopHotKeyRecording()
        isRecordingHotKey = true
        hotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecordingHotKey else { return event }
            if let hotKey = ToggleHotKey.make(keyCode: event.keyCode, modifiers: event.modifierFlags) {
                toggleHotKey = hotKey
                controller.setGlobalHotKey(hotKey)
            }
            stopHotKeyRecording()
            return nil
        }
    }

    private func stopHotKeyRecording() {
        isRecordingHotKey = false
        if let hotKeyMonitor {
            NSEvent.removeMonitor(hotKeyMonitor)
            self.hotKeyMonitor = nil
        }
    }
}
