import MacRemoteCore
@preconcurrency import ApplicationServices
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
    @State private var showingCalibration = false

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
        .sheet(isPresented: $showingCalibration) {
            KeyCalibrationSheet(controller: controller)
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
                Button("Calibration") {
                    showingCalibration = true
                }
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

private struct KeyCalibrationSheet: View {
    @ObservedObject var controller: RemoteSessionController
    @Environment(\.dismiss) private var dismiss

    @StateObject private var monitor = CalibrationEventTapMonitor()
    @State private var isListening = false
    @State private var modifierState: [UInt16: Bool] = [:]
    @State private var records: [CalibrationRecord] = []
    @State private var normalizedRecords: [CalibrationRecord] = []
    @State private var lastAnnouncement = "No keys captured yet"
    @State private var lastNormalizedAnnouncement = "No normalized detection yet"
    @State private var logicalCapsLockArmed = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Press combos such as Caps Lock plus T, Caps Lock plus F12, or plain F12. The app will announce what it detects and keep a short event log below.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(isListening ? "Stop Listening" : "Start Listening") {
                        if isListening {
                            stopListening(announce: true)
                        } else {
                            startListening(announce: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Speak Instructions") {
                        announce("Calibration ready. Press your test combo now.")
                    }

                    Button("Clear Log") {
                        records.removeAll(keepingCapacity: false)
                        normalizedRecords.removeAll(keepingCapacity: false)
                        logicalCapsLockArmed = false
                        lastAnnouncement = "Log cleared"
                        lastNormalizedAnnouncement = "Log cleared"
                    }

                    Button("Copy Log") {
                        copyLogToClipboard()
                    }
                    .disabled(records.isEmpty)
                }

                if !controller.snapshot.accessibilityTrusted {
                    Label("Global key capture for calibration works best after granting Accessibility access.", systemImage: "hand.raised.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                GroupBox("Latest Detection") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Raw: \(lastAnnouncement)")
                        Text("Normalized: \(lastNormalizedAnnouncement)")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Recent Key Events") {
                    if records.isEmpty {
                        ContentUnavailableView(
                            "Waiting For Input",
                            systemImage: "keyboard",
                            description: Text("Start listening, then press key combinations while this window stays frontmost.")
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

                GroupBox("Normalized Event Log") {
                    if normalizedRecords.isEmpty {
                        ContentUnavailableView(
                            "Waiting For Normalized Input",
                            systemImage: "waveform.path.ecg",
                            description: Text("Normalized detections appear here after the app applies the same Caps Lock interpretation used by the controller.")
                        )
                    } else {
                        List(normalizedRecords) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.message)
                                Text(record.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .navigationTitle("Key Calibration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 500)
        .onAppear {
            monitor.onEvent = { event in
                handle(event)
            }
            startListening(announce: true)
        }
        .onDisappear {
            stopListening(announce: false)
            monitor.onEvent = nil
        }
    }

    private func startListening(announce: Bool) {
        guard !isListening else {
            if announce {
                self.announce("Calibration is already listening.")
            }
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.keyWindow ?? NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
        }
        isListening = monitor.start()
        if announce {
            self.announce(isListening ? "Calibration ready. Press your test combo now." : "Calibration could not start. Grant Accessibility access and try again.")
        }
    }

    private func stopListening(announce: Bool) {
        monitor.stop()
        modifierState.removeAll(keepingCapacity: false)
        logicalCapsLockArmed = false
        isListening = false
        if announce {
            self.announce("Calibration stopped.")
        }
    }

    private func handle(_ event: CalibrationKeyEvent) {
        switch event.type {
        case .flagsChanged:
            handleFlagsChanged(event)
        case .keyDown:
            guard !event.isRepeat else { return }
            handleKeyDown(event)
        case .keyUp:
            handleKeyUp(event)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CalibrationKeyEvent) {
        guard let flag = modifierFlag(for: event.keyCode), let name = keyName(for: event) else { return }
        let isPressed = event.flags.contains(flag)
        let previous = modifierState[event.keyCode] ?? false
        guard previous != isPressed else { return }
        modifierState[event.keyCode] = isPressed
        let phrase = "\(name) \(isPressed ? "down" : "up")"
        record(phrase, announce: phrase)
        if event.keyCode == 57 {
            logicalCapsLockArmed = true
            recordNormalized("Caps Lock armed", announce: nil)
        }
    }

    private func handleKeyDown(_ event: CalibrationKeyEvent) {
        guard let name = keyName(for: event) else { return }
        let modifiers = activeModifierNames()
        let phrase = modifiers.isEmpty ? name : (modifiers + [name]).joined(separator: " plus ")
        record("down: \(phrase)", announce: phrase)

        let normalizedModifiers = normalizedModifierNames()
        let normalizedPhrase = normalizedModifiers.isEmpty ? name : (normalizedModifiers + [name]).joined(separator: " plus ")
        recordNormalized("down: \(normalizedPhrase)", announce: nil)
    }

    private func handleKeyUp(_ event: CalibrationKeyEvent) {
        guard let name = keyName(for: event) else { return }
        record("up: \(name)", announce: nil)
        recordNormalized("up: \(name)", announce: nil)
        if !isModifierKey(event.keyCode) {
            logicalCapsLockArmed = false
        }
    }

    private func activeModifierNames() -> [String] {
        modifierState
            .filter { $0.value }
            .keys
            .sorted()
            .compactMap { keyName(forKeyCode: $0) }
    }

    private func normalizedModifierNames() -> [String] {
        var names = activeModifierNames().filter { $0 != "Caps Lock" }
        if logicalCapsLockArmed {
            names.insert("Caps Lock", at: 0)
        }
        return names
    }

    private func keyName(for event: CalibrationKeyEvent) -> String? {
        keyName(forKeyCode: event.keyCode, characters: event.characters)
    }

    private func keyName(forKeyCode keyCode: UInt16, characters: String? = nil) -> String? {
        switch keyCode {
        case 57:
            return "Caps Lock"
        case 56, 60:
            return "Shift"
        case 59, 62:
            return "Control"
        case 58, 61:
            return "Option"
        case 55, 54:
            return "Command"
        case 48:
            return "Tab"
        case 36:
            return "Return"
        case 51:
            return "Delete"
        case 117:
            return "Forward Delete"
        case 53:
            return "Escape"
        case 122:
            return "F1"
        case 120:
            return "F2"
        case 99:
            return "F3"
        case 118:
            return "F4"
        case 96:
            return "F5"
        case 97:
            return "F6"
        case 98:
            return "F7"
        case 100:
            return "F8"
        case 101:
            return "F9"
        case 109:
            return "F10"
        case 103:
            return "F11"
        case 111:
            return "F12"
        case 123:
            return "Left Arrow"
        case 124:
            return "Right Arrow"
        case 125:
            return "Down Arrow"
        case 126:
            return "Up Arrow"
        default:
            if let characters, let scalar = characters.trimmingCharacters(in: .whitespacesAndNewlines).first {
                return String(scalar).uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private func modifierFlag(for keyCode: UInt16) -> CGEventFlags? {
        switch keyCode {
        case 57:
            return .maskAlphaShift
        case 56, 60:
            return .maskShift
        case 59, 62:
            return .maskControl
        case 58, 61:
            return .maskAlternate
        case 55, 54:
            return .maskCommand
        default:
            return nil
        }
    }

    private func isModifierKey(_ keyCode: UInt16) -> Bool {
        modifierFlag(for: keyCode) != nil
    }

    private func record(_ message: String, announce: String?) {
        lastAnnouncement = announce ?? message
        records.insert(.init(message: message), at: 0)
        records = Array(records.prefix(40))
        if let announce {
            self.announce(announce)
        }
    }

    private func recordNormalized(_ message: String, announce: String?) {
        lastNormalizedAnnouncement = announce ?? message
        normalizedRecords.insert(.init(message: message), at: 0)
        normalizedRecords = Array(normalizedRecords.prefix(40))
        if let announce {
            self.announce(announce)
        }
    }

    private func announce(_ text: String) {
        controller.speakDiagnostic(text)
    }

    private func copyLogToClipboard() {
        let rawLines = records.map { record in
            let time = record.timestamp.formatted(date: .omitted, time: .standard)
            return "raw: \(record.message) \(time)"
        }
        let normalizedLines = normalizedRecords.map { record in
            let time = record.timestamp.formatted(date: .omitted, time: .standard)
            return "normalized: \(record.message) \(time)"
        }
        let payload = (rawLines + normalizedLines).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        announce("Calibration log copied.")
    }
}

private struct CalibrationRecord: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
}

private struct CalibrationKeyEvent: Equatable {
    let type: CGEventType
    let keyCode: UInt16
    let flags: CGEventFlags
    let characters: String?
    let isRepeat: Bool
}

@MainActor
private final class CalibrationEventTapMonitor: ObservableObject {
    var onEvent: ((CalibrationKeyEvent) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fallbackGlobalMonitor: Any?
    private var lastSignature: CalibrationEventSignature?

    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<CalibrationEventTapMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.handle(event: event, type: type)
            return Unmanaged.passUnretained(event)
        }
        let unmanaged = Unmanaged.passUnretained(self)
        if let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: unmanaged.toOpaque()
        ) {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.tap = tap
            self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }

        fallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleFallback(event)
        }
        return fallbackGlobalMonitor != nil
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let fallbackGlobalMonitor {
            NSEvent.removeMonitor(fallbackGlobalMonitor)
        }
        tap = nil
        source = nil
        fallbackGlobalMonitor = nil
        lastSignature = nil
    }

    private func handle(event: CGEvent, type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let signature = CalibrationEventSignature(type: type.rawValue, keyCode: keyCode, timestampBucket: Int(event.timestamp / 10_000_000))
        guard signature != lastSignature else { return }
        lastSignature = signature
        let payload = CalibrationKeyEvent(
            type: type,
            keyCode: keyCode,
            flags: event.flags,
            characters: nil,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
        onEvent?(payload)
    }

    private func handleFallback(_ event: NSEvent) {
        let type: CGEventType
        switch event.type {
        case .keyDown:
            type = .keyDown
        case .keyUp:
            type = .keyUp
        case .flagsChanged:
            type = .flagsChanged
        default:
            return
        }
        let signature = CalibrationEventSignature(type: type.rawValue, keyCode: event.keyCode, timestampBucket: Int(event.timestamp * 100))
        guard signature != lastSignature else { return }
        lastSignature = signature
        let payload = CalibrationKeyEvent(
            type: type,
            keyCode: event.keyCode,
            flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)),
            characters: event.charactersIgnoringModifiers,
            isRepeat: event.isARepeat
        )
        onEvent?(payload)
    }
}

private struct CalibrationEventSignature: Equatable {
    let type: UInt32
    let keyCode: UInt16
    let timestampBucket: Int
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
