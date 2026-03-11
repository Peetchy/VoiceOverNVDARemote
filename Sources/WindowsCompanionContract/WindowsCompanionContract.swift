import Foundation
import RemoteProtocol

public enum WindowsCompanionFeature: String, Codable, CaseIterable, Sendable {
    case announcements
    case keyboardForwarding = "keyboard_forwarding"
    case clipboardSync = "clipboard_sync"
    case channelPresence = "channel_presence"
    case heartbeat
}

public struct WindowsCompanionHandshake: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let role: RemoteRole
    public let channel: String

    public init(protocolVersion: Int, role: RemoteRole, channel: String) {
        self.protocolVersion = protocolVersion
        self.role = role
        self.channel = channel
    }
}

public struct WindowsCompanionContractSpec: Equatable, Sendable {
    public let requiredFeatures: [WindowsCompanionFeature]
    public let recommendedNextPhase: [String]
    public let notes: [String]

    public init(requiredFeatures: [WindowsCompanionFeature], recommendedNextPhase: [String], notes: [String]) {
        self.requiredFeatures = requiredFeatures
        self.recommendedNextPhase = recommendedNextPhase
        self.notes = notes
    }
}

public enum WindowsCompanionContract {
    public static let mvp = WindowsCompanionContractSpec(
        requiredFeatures: [
            .announcements,
            .keyboardForwarding,
            .clipboardSync,
            .channelPresence,
            .heartbeat,
        ],
        recommendedNextPhase: [
            "Map NVDA speech events into announcement payloads.",
            "Translate remote key events into InputGesture execution on Windows.",
            "Add certificate pinning parity with relay fingerprints.",
        ],
        notes: [
            "This contract intentionally narrows MVP scope compared to full NVDA Remote compatibility.",
            "The Windows add-on can preserve protocol translation internally without leaking NVDA-specific objects to macOS.",
        ]
    )

    public static func handshake(
        role: RemoteRole,
        channel: String
    ) -> WindowsCompanionHandshake {
        WindowsCompanionHandshake(
            protocolVersion: remoteProtocolVersion,
            role: role,
            channel: channel
        )
    }
}
