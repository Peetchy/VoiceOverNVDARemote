import MacRemoteCore
@preconcurrency import ApplicationServices
import RemoteProtocol
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: RemoteSessionController

    @State private var host = "nvdaremote.com"
    @State private var port = "6837"
    @State private var key = ""
    @State private var captureScope: KeyCaptureScope = .session
    @State private var globalHotKey: GlobalToggleHotKeyOption = .controlShiftCommandR
    @State private var speechOutputMode: SpeechOutputMode = .voiceOver
    @State private var showingEventLog = false
    @State private var showingKeymapEditor = false
    @State private var showingCalibration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusBanner

                if isConnectedLike {
                    commandsSection
                } else {
                    connectionSection
                }

                if shouldShowAccessibilityWarning {
                    accessibilityWarning
                }

                settingsSection
                toolsSection
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            captureScope = controller.snapshot.keyCaptureScope
            globalHotKey = controller.snapshot.globalToggleHotKey
            speechOutputMode = controller.snapshot.speechOutputMode
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

    // MARK: - Status

    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.title2.weight(.semibold))
                    Text(statusDetail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if isConnectedLike {
                HStack(spacing: 12) {
                    Button {
                        controller.toggleControl()
                    } label: {
                        Label(controlButtonTitle, systemImage: isControlling ? "stop.fill" : "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isControlling ? .orange : .accentColor)
                    .keyboardShortcut(.defaultAction)

                    Button(role: .destructive) {
                        Task { await controller.disconnect() }
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
        }
        .padding(18)
        .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(statusColor.opacity(0.35)))
    }

    // MARK: - Sections

    private var connectionSection: some View {
        section("Connection") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Host").gridColumnAlignment(.trailing).accessibilityHidden(true)
                    TextField("Host", text: $host)
                        .labelsHidden()
                }
                GridRow {
                    Text("Port").accessibilityHidden(true)
                    TextField("Port", text: $port)
                        .labelsHidden()
                        .frame(maxWidth: 120)
                }
                GridRow {
                    Text("Session Key").accessibilityHidden(true)
                    SecureField("Session Key", text: $key)
                        .labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(controller.snapshot.phase == .connecting)

            Button {
                Task { await controller.connect(host: host, port: UInt16(port) ?? 6837, key: key) }
            } label: {
                Label(connectionButtonTitle, systemImage: "network")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(controller.snapshot.phase == .connecting || key.isEmpty)
        }
    }

    private var commandsSection: some View {
        section("Send to Remote Computer") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                // Plain F12 is the default local control toggle, so it cannot be typed through.
                commandButton("Send F12", systemImage: "f.cursive") {
                    Task {
                        await controller.sendRemoteKey(vkCode: 0x7B, scanCode: 0x58, extended: false, pressed: true)
                        await controller.sendRemoteKey(vkCode: 0x7B, scanCode: 0x58, extended: false, pressed: false)
                    }
                }
                commandButton("Send Ctrl+Alt+Del", systemImage: "lock.shield") {
                    Task { await controller.sendCtrlAltDelete() }
                }
                commandButton("Push Clipboard", systemImage: "doc.on.clipboard") {
                    Task { await controller.pushClipboard() }
                }
                commandButton("Copy Last Text", systemImage: "text.quote") {
                    controller.copyLatestTextToClipboard()
                }
                .disabled(!canCopyLatestText)
                commandButton("Ping", systemImage: "dot.radiowaves.left.and.right") {
                    Task { await controller.sendPing() }
                }
            }
        }
    }

    private var accessibilityWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Whole Session needs Accessibility access before it can capture keys.", systemImage: "hand.raised.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            HStack {
                Button("Open Settings") {
                    controller.openAccessibilitySettings()
                }
                Button("Refresh Access") {
                    controller.refreshAccessibilityPermission()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var settingsSection: some View {
        section("Settings") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                settingRow("Capture Scope") {
                    Picker("Capture Scope", selection: $captureScope) {
                        ForEach(KeyCaptureScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .onChange(of: captureScope) { _, scope in
                        controller.setKeyCaptureScope(scope)
                    }
                    .disabled(isControlling)
                }
                settingRow("Control Toggle Hotkey") {
                    Picker("Control Toggle Hotkey", selection: $globalHotKey) {
                        ForEach(GlobalToggleHotKeyOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .onChange(of: globalHotKey) { _, option in
                        controller.setGlobalToggleHotKey(option)
                    }
                }
                settingRow("Speech Output") {
                    Picker("Speech Output", selection: $speechOutputMode) {
                        ForEach(SpeechOutputMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .onChange(of: speechOutputMode) { _, mode in
                        controller.setSpeechOutputMode(mode)
                    }
                }
            }

            Button {
                showingKeymapEditor = true
            } label: {
                Label("Custom Keymap…", systemImage: "keyboard.badge.ellipsis")
            }
        }
    }

    private var toolsSection: some View {
        section("Tools") {
            HStack(spacing: 10) {
                Button {
                    showingEventLog = true
                } label: {
                    Label("Event Flow", systemImage: "list.bullet.rectangle")
                }
                Button {
                    showingCalibration = true
                } label: {
                    Label("Calibration", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        GridRow {
            Text(title)
                .gridColumnAlignment(.trailing)
                .accessibilityHidden(true)
            control()
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
        }
    }

    private func commandButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.large)
    }

    // MARK: - State

    private var statusTitle: String {
        switch controller.snapshot.phase {
        case .idle:
            "Not Connected"
        case .connecting:
            "Connecting…"
        case .connected:
            hasRemoteComputer ? "Using This Mac" : "Waiting for Remote Computer"
        case .controlling:
            "Controlling Remote Computer"
        case .failed:
            "Connection Failed"
        }
    }

    private var statusDetail: String {
        let hotkey = controller.snapshot.globalHotKeyDisplay
        switch controller.snapshot.phase {
        case .idle:
            return "Enter the relay details below, then connect."
        case .connecting:
            return "Connecting to \(host):\(port)."
        case .connected:
            if hasRemoteComputer {
                return "Connected to \(remoteComputerDescription) via \(host):\(port). Press \(hotkey) or Start Control to control it."
            }
            return "Connected to \(host):\(port). The remote NVDA has not joined the session yet."
        case .controlling:
            if controller.snapshot.keyCaptureScope == .application {
                return "Keys go to \(remoteComputerDescription) while this window is in front. Press \(hotkey) to return to this Mac."
            }
            return "All keys go to \(remoteComputerDescription). Press \(hotkey) to return to this Mac."
        case let .failed(message):
            return message
        }
    }

    private var remoteComputerDescription: String {
        let peers = controller.snapshot.peers
        switch peers.count {
        case 0:
            return "the remote computer"
        case 1:
            return "remote computer \(String(peers[0].id))"
        default:
            return "\(peers.count) remote computers"
        }
    }

    private var statusSymbol: String {
        switch controller.snapshot.phase {
        case .idle:
            "desktopcomputer"
        case .connecting:
            "arrow.triangle.2.circlepath"
        case .connected:
            hasRemoteComputer ? "checkmark.circle.fill" : "hourglass"
        case .controlling:
            "keyboard.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch controller.snapshot.phase {
        case .idle:
            .gray
        case .connecting:
            .orange
        case .connected:
            hasRemoteComputer ? .blue : .orange
        case .controlling:
            .green
        case .failed:
            .red
        }
    }

    private var hasRemoteComputer: Bool {
        !controller.snapshot.peers.isEmpty
    }

    private var isControlling: Bool {
        controller.snapshot.phase == .controlling
    }

    private var controlButtonTitle: String {
        isControlling ? "Stop Control" : "Start Control"
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
        controller.snapshot.phase == .connecting ? "Connecting…" : "Connect"
    }

    private var canCopyLatestText: Bool {
        !(controller.snapshot.latestAnnouncement?.isEmpty ?? true)
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
