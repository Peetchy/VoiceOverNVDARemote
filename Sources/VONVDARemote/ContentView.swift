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
    @State private var globalHotKey: GlobalToggleHotKeyOption = .controlShiftCommandR
    @State private var speechOutputMode: SpeechOutputMode = .voiceOver
    @State private var showingEventLog = false
    @State private var showingKeymapEditor = false

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                connectionPanel
                statusPanel
                toolsPanel
            }
            .frame(maxWidth: 360, maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 20) {
                if canShowConnectedDetails {
                    peerPanel
                } else {
                    ContentUnavailableView(
                        "No Active Session",
                        systemImage: "rectangle.connected.to.line.below",
                        description: Text("Connected peers and session details will appear after the remote session is established.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
            globalHotKey = controller.snapshot.globalToggleHotKey
            speechOutputMode = controller.snapshot.speechOutputMode
        }
        .onChange(of: controller.snapshot.phase) { oldValue, newValue in
            soundPlayer.playTransition(from: oldValue, to: newValue)
        }
        .sheet(isPresented: $showingEventLog) {
            EventLogSheet(records: controller.snapshot.eventLog)
        }
        .sheet(isPresented: $showingKeymapEditor) {
            KeymapEditorSheet(
                initialMapping: controller.snapshot.modifierMapping,
                onSave: { mapping in
                    controller.setModifierMapping(mapping)
                }
            )
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

                Text("While controlling, local key events are captured. Use the configured global toggle hotkey to return control to this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                selectionRow(
                    title: "Capture Scope",
                    value: captureScope.displayName
                ) {
                    ForEach(KeyCaptureScope.allCases, id: \.self) { scope in
                        Button(scope.displayName) {
                            captureScope = scope
                            controller.setKeyCaptureScope(scope)
                        }
                    }
                }

                selectionRow(
                    title: "Global Hotkey",
                    value: globalHotKey.displayName
                ) {
                    ForEach(GlobalToggleHotKeyOption.allCases, id: \.self) { option in
                        Button(option.displayName) {
                            globalHotKey = option
                            controller.setGlobalToggleHotKey(option)
                        }
                    }
                }

                selectionRow(
                    title: "Speech Output",
                    value: speechOutputMode.displayName
                ) {
                    ForEach(SpeechOutputMode.allCases, id: \.self) { mode in
                        Button(mode.displayName) {
                            speechOutputMode = mode
                            controller.setSpeechOutputMode(mode)
                        }
                    }
                }

                Button("Custom Keymap") {
                    showingKeymapEditor = true
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

                if canShowConnectedActions {
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

                        Button("Copy Last Text") {
                            controller.copyLatestTextToClipboard()
                        }
                        .disabled(!canCopyLatestText)

                        Button("Ping") {
                            Task {
                                await controller.sendPing()
                            }
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
                if canShowConnectedDetails {
                    Text("Peers: \(controller.snapshot.peers.count)")
                    Text("Key capture: \(controller.snapshot.keyCaptureActive ? "active" : "inactive")")
                    if controller.snapshot.keyCaptureScope == .application && controller.snapshot.keyCaptureActive {
                        Text("App-only capture is live. Keep VO NVDA Remote frontmost while sending keys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Send Ctrl+Alt+Del") {
                        Task {
                            await controller.sendCtrlAltDelete()
                        }
                    }
                    .disabled(!canUseConnectedCommands)
                } else {
                    Text("Remote actions and session details will appear after the connection is established.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toolsPanel: some View {
        GroupBox("Tools") {
            VStack(alignment: .leading, spacing: 10) {
                Button("Event Flow") {
                    showingEventLog = true
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

    private func selectionRow<MenuContent: View>(
        title: String,
        value: String,
        @ViewBuilder content: () -> MenuContent
    ) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                content()
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
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

    private var canCopyLatestText: Bool {
        canUseConnectedCommands && !(controller.snapshot.latestAnnouncement?.isEmpty ?? true)
    }

    private var canShowConnectedActions: Bool {
        isConnectedLike || controller.snapshot.phase == .connecting
    }

    private var canShowConnectedDetails: Bool {
        isConnectedLike
    }

    private var shouldShowAccessibilityWarning: Bool {
        captureScope == .session && !controller.snapshot.accessibilityTrusted
    }
}

private struct EventLogSheet: View {
    let records: [RemoteEventRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "No Events Yet",
                        systemImage: "timeline.selection",
                        description: Text("Connection progress and remote activity will appear here.")
                    )
                } else {
                    List(records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.message)
                            Text(record.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Event Flow")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

private struct KeymapEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftMapping: RemoteModifierMapping

    private let onSave: (RemoteModifierMapping) -> Void

    init(initialMapping: RemoteModifierMapping, onSave: @escaping (RemoteModifierMapping) -> Void) {
        _draftMapping = State(initialValue: initialMapping)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(KeymapSlot.allCases) { slot in
                    HStack {
                        Text(slot.displayName)
                        Spacer()
                        Menu(currentTarget(for: slot).displayName) {
                            ForEach(RemoteModifierTarget.allCases, id: \.self) { target in
                                Button(target.displayName) {
                                    setTarget(target, for: slot)
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }
            .navigationTitle("Custom Keymap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem {
                    Button("Reset Default") {
                        draftMapping = .default
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draftMapping)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func currentTarget(for slot: KeymapSlot) -> RemoteModifierTarget {
        switch slot {
        case .leftControl:
            draftMapping.leftControl
        case .rightControl:
            draftMapping.rightControl
        case .leftOption:
            draftMapping.leftOption
        case .rightOption:
            draftMapping.rightOption
        case .leftCommand:
            draftMapping.leftCommand
        case .rightCommand:
            draftMapping.rightCommand
        case .leftShift:
            draftMapping.leftShift
        case .rightShift:
            draftMapping.rightShift
        }
    }

    private func setTarget(_ target: RemoteModifierTarget, for slot: KeymapSlot) {
        switch slot {
        case .leftControl:
            draftMapping.leftControl = target
        case .rightControl:
            draftMapping.rightControl = target
        case .leftOption:
            draftMapping.leftOption = target
        case .rightOption:
            draftMapping.rightOption = target
        case .leftCommand:
            draftMapping.leftCommand = target
        case .rightCommand:
            draftMapping.rightCommand = target
        case .leftShift:
            draftMapping.leftShift = target
        case .rightShift:
            draftMapping.rightShift = target
        }
    }
}

private enum KeymapSlot: CaseIterable, Identifiable {
    case leftControl
    case rightControl
    case leftOption
    case rightOption
    case leftCommand
    case rightCommand
    case leftShift
    case rightShift

    var id: Self { self }

    var displayName: String {
        switch self {
        case .leftControl:
            "Control Left"
        case .rightControl:
            "Control Right"
        case .leftOption:
            "Option Left"
        case .rightOption:
            "Option Right"
        case .leftCommand:
            "Command Left"
        case .rightCommand:
            "Command Right"
        case .leftShift:
            "Shift Left"
        case .rightShift:
            "Shift Right"
        }
    }
}

private extension KeyCaptureScope {
    var displayName: String {
        switch self {
        case .application:
            "App Only"
        case .session:
            "Whole Session"
        }
    }
}
