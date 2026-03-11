import MacRemoteCore
import RemoteProtocol
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: RemoteSessionController
    @StateObject private var soundPlayer = SessionSoundPlayer()

    @State private var host = "nvdaremote.com"
    @State private var port = "6837"
    @State private var key = "0871234321"
    @State private var captureScope: KeyCaptureScope = .session

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
        }
        .onChange(of: controller.snapshot.phase) { oldValue, newValue in
            soundPlayer.playTransition(from: oldValue, to: newValue)
        }
    }

    private var connectionPanel: some View {
        GroupBox("Connection") {
            VStack(alignment: .leading, spacing: 12) {
                if connectionInputsEnabled {
                    TextField("Host", text: $host)
                    TextField("Port", text: $port)
                    SecureField("Session Key", text: $key)
                } else {
                    Text("Connected to \(host):\(port)")
                        .font(.headline)
                    Text("Session key is hidden while connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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

                if shouldShowAccessibilityWarning {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Whole Session needs Accessibility access before it can capture keys.", systemImage: "hand.raised.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        HStack {
                            Button("Refresh Access") {
                                controller.refreshAccessibilityPermission()
                            }
                            Button("Open Settings") {
                                controller.openAccessibilitySettings()
                            }
                        }
                    }
                }

                Button(connectionButtonTitle) {
                    Task {
                        if isConnectedLike {
                            await controller.disconnect()
                        } else {
                            await controller.connect(host: host, port: UInt16(port) ?? 6837, key: key)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .tint(isConnectedLike ? .red : .accentColor)
                .buttonStyle(.borderedProminent)

                HStack {
                    Button(controlButtonTitle) {
                        controller.toggleControl()
                    }
                    .disabled(!canToggleControl)
                    Button("Send F11") {
                        Task {
                            await controller.sendRemoteKey(vkCode: 0x7A, scanCode: 0x57, extended: false, pressed: true)
                            await controller.sendRemoteKey(vkCode: 0x7A, scanCode: 0x57, extended: false, pressed: false)
                        }
                    }
                    .disabled(!canUseConnectedCommands)
                    Button("Push Clipboard") {
                        Task {
                            await controller.pushClipboard()
                        }
                    }
                    .disabled(!canUseConnectedCommands)
                    Button("Ping") {
                        Task {
                            await controller.sendPing()
                        }
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private var statusPanel: some View {
        GroupBox("Session State") {
            VStack(alignment: .leading, spacing: 8) {
                Text(phaseLabel)
                    .font(.title3.weight(.semibold))
                Text("Peers: \(controller.snapshot.peers.count)")
                Text("Key capture: \(controller.snapshot.keyCaptureActive ? "active" : "inactive")")
                if controller.snapshot.keyCaptureScope == .application && controller.snapshot.keyCaptureActive {
                    Text("App-only capture is live. Keep VO NVDA Remote frontmost while sending keys.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Latest announcement: \(controller.snapshot.latestAnnouncement ?? "None")")
                    .lineLimit(3)
                Button("Send Ctrl+Alt+Del") {
                    Task {
                        await controller.sendCtrlAltDelete()
                    }
                }
                .disabled(!canUseConnectedCommands)
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

    private var isConnectedLike: Bool {
        switch controller.snapshot.phase {
        case .connected, .controlling:
            return true
        case .idle, .connecting, .failed:
            return false
        }
    }

    private var connectionButtonTitle: String {
        switch controller.snapshot.phase {
        case .connecting:
            return "Connecting..."
        case .connected, .controlling:
            return "Disconnect"
        case .idle, .failed:
            return "Connect"
        }
    }

    private var connectionInputsEnabled: Bool {
        !isConnectedLike && controller.snapshot.phase != .connecting
    }

    private var canToggleControl: Bool {
        switch controller.snapshot.phase {
        case .connected, .controlling:
            return true
        case .idle, .connecting, .failed:
            return false
        }
    }

    private var canUseConnectedCommands: Bool {
        isConnectedLike
    }

    private var shouldShowAccessibilityWarning: Bool {
        captureScope == .session && !controller.snapshot.accessibilityTrusted
    }
}
