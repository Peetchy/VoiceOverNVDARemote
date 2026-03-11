import Foundation

public let remoteProtocolVersion = 2

public enum RemoteRole: String, Codable, CaseIterable, Sendable {
    case master
    case slave
}

public enum RemoteMessageType: String, Codable, CaseIterable, Sendable {
    case protocolVersion = "protocol_version"
    case join
    case channelJoined = "channel_joined"
    case clientJoined = "client_joined"
    case clientLeft = "client_left"
    case key
    case speak
    case cancel
    case pauseSpeech = "pause_speech"
    case tone
    case wave
    case sendSAS = "send_SAS"
    case display
    case brailleInput = "braille_input"
    case setBrailleInfo = "set_braille_info"
    case setDisplaySize = "set_display_size"
    case setClipboardText = "set_clipboard_text"
    case motd
    case versionMismatch = "version_mismatch"
    case ping
    case error
    case nvdaNotConnected = "nvda_not_connected"
}

public struct RemoteClientDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let connectionType: RemoteRole

    public init(id: Int, connectionType: RemoteRole) {
        self.id = id
        self.connectionType = connectionType
    }
}

public struct ProtocolVersionPayload: Codable, Equatable, Sendable {
    public let version: Int

    public init(version: Int) {
        self.version = version
    }
}

public struct JoinPayload: Codable, Equatable, Sendable {
    public let channel: String
    public let connectionType: RemoteRole

    public init(channel: String, connectionType: RemoteRole) {
        self.channel = channel
        self.connectionType = connectionType
    }
}

public struct ChannelJoinedPayload: Codable, Equatable, Sendable {
    public let channel: String
    public let clients: [RemoteClientDescriptor]

    public init(channel: String, clients: [RemoteClientDescriptor]) {
        self.channel = channel
        self.clients = clients
    }
}

public struct ClientJoinedPayload: Codable, Equatable, Sendable {
    public let client: RemoteClientDescriptor

    public init(client: RemoteClientDescriptor) {
        self.client = client
    }
}

public struct ClientLeftPayload: Codable, Equatable, Sendable {
    public let clientID: Int

    public init(clientID: Int) {
        self.clientID = clientID
    }
}

public struct KeyPayload: Codable, Equatable, Sendable {
    public let vkCode: UInt16
    public let scanCode: UInt16?
    public let extended: Bool
    public let pressed: Bool

    public init(vkCode: UInt16, scanCode: UInt16? = nil, extended: Bool, pressed: Bool) {
        self.vkCode = vkCode
        self.scanCode = scanCode
        self.extended = extended
        self.pressed = pressed
    }
}

public enum SpeechSequenceItem: Equatable, Sendable {
    case text(String)
    case command(name: String)
}

extension SpeechSequenceItem: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        let command = try container.decode([JSONValue].self)
        if case let .string(name) = command.first {
            self = .command(name: name)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported speak sequence item")
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(text):
            try container.encode(text)
        case let .command(name):
            try container.encode([JSONValue.string(name), .object([:])])
        }
    }
}

public enum JSONValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct SpeakPayload: Codable, Equatable, Sendable {
    public let sequence: [SpeechSequenceItem]
    public let priority: String

    public init(sequence: [SpeechSequenceItem], priority: String) {
        self.sequence = sequence
        self.priority = priority
    }
}

public struct ClipboardPayload: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct PingPayload: Codable, Equatable, Sendable {
    public init() {}
}

public struct ErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

extension ErrorPayload {
    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decodeIfPresent(String.self, forKey: .code) ?? "error"
        self.message = try container.decode(String.self, forKey: .message)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(message, forKey: .message)
    }
}

public struct MotdPayload: Codable, Equatable, Sendable {
    public let motd: String
    public let forceDisplay: Bool

    public init(motd: String, forceDisplay: Bool = false) {
        self.motd = motd
        self.forceDisplay = forceDisplay
    }
}

public enum RemoteMessage: Equatable, Sendable {
    case protocolVersion(ProtocolVersionPayload)
    case join(JoinPayload)
    case channelJoined(ChannelJoinedPayload)
    case clientJoined(ClientJoinedPayload)
    case clientLeft(ClientLeftPayload)
    case key(KeyPayload)
    case speak(SpeakPayload)
    case cancel
    case pauseSpeech(Bool)
    case tone(hz: Double, length: Double, left: Double, right: Double)
    case wave(fileName: String, asynchronous: Bool)
    case sendSAS
    case display(cells: [Int])
    case brailleInput(dots: Int?, space: Bool?, routingIndex: Int?)
    case setBrailleInfo(name: String, numCells: Int)
    case setDisplaySize(sizes: [Int])
    case setClipboardText(ClipboardPayload)
    case motd(MotdPayload)
    case versionMismatch
    case ping(PingPayload)
    case error(ErrorPayload)
    case nvdaNotConnected

    public var type: RemoteMessageType {
        switch self {
        case .protocolVersion: .protocolVersion
        case .join: .join
        case .channelJoined: .channelJoined
        case .clientJoined: .clientJoined
        case .clientLeft: .clientLeft
        case .key: .key
        case .speak: .speak
        case .cancel: .cancel
        case .pauseSpeech: .pauseSpeech
        case .tone: .tone
        case .wave: .wave
        case .sendSAS: .sendSAS
        case .display: .display
        case .brailleInput: .brailleInput
        case .setBrailleInfo: .setBrailleInfo
        case .setDisplaySize: .setDisplaySize
        case .setClipboardText: .setClipboardText
        case .motd: .motd
        case .versionMismatch: .versionMismatch
        case .ping: .ping
        case .error: .error
        case .nvdaNotConnected: .nvdaNotConnected
        }
    }
}

public struct RemoteEnvelope: Equatable, Sendable {
    public let origin: Int?
    public let message: RemoteMessage

    public init(origin: Int? = nil, message: RemoteMessage) {
        self.origin = origin
        self.message = message
    }
}

extension RemoteEnvelope: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case origin
        case version
        case channel
        case userID = "user_id"
        case userIDs = "user_ids"
        case connectionType = "connection_type"
        case clients
        case client
        case clientID = "client_id"
        case vkCode = "vk_code"
        case scanCode = "scan_code"
        case extended
        case pressed
        case sequence
        case text
        case priority
        case switchValue = "switch"
        case hz
        case length
        case left
        case right
        case fileName
        case asynchronous
        case cells
        case dots
        case space
        case routingIndex
        case name
        case numCells
        case sizes
        case motd
        case forceDisplay = "force_display"
        case code
        case message
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(RemoteMessageType.self, forKey: .type)
        let origin = try container.decodeIfPresent(Int.self, forKey: .origin)
        self.origin = origin
        switch type {
        case .protocolVersion:
            self.message = .protocolVersion(.init(version: try container.decode(Int.self, forKey: .version)))
        case .join:
            self.message = .join(.init(
                channel: try container.decode(String.self, forKey: .channel),
                connectionType: try container.decode(RemoteRole.self, forKey: .connectionType)
            ))
        case .channelJoined:
            self.message = .channelJoined(.init(
                channel: try container.decode(String.self, forKey: .channel),
                clients: try container.decodeIfPresent([RemoteClientDescriptor].self, forKey: .clients) ?? []
            ))
        case .clientJoined:
            self.message = .clientJoined(.init(client: try container.decode(RemoteClientDescriptor.self, forKey: .client)))
        case .clientLeft:
            let clientID = try container.decodeIfPresent(Int.self, forKey: .clientID)
                ?? container.decodeIfPresent(Int.self, forKey: .userID)
                ?? container.decodeIfPresent(Int.self, forKey: .client)
            guard let clientID else {
                throw DecodingError.keyNotFound(
                    CodingKeys.clientID,
                    .init(codingPath: decoder.codingPath, debugDescription: "Missing client identifier")
                )
            }
            self.message = .clientLeft(.init(clientID: clientID))
        case .key:
            self.message = .key(.init(
                vkCode: try container.decode(UInt16.self, forKey: .vkCode),
                scanCode: try container.decodeIfPresent(UInt16.self, forKey: .scanCode),
                extended: try container.decode(Bool.self, forKey: .extended),
                pressed: try container.decode(Bool.self, forKey: .pressed)
            ))
        case .speak:
            self.message = .speak(.init(
                sequence: try container.decode([SpeechSequenceItem].self, forKey: .sequence),
                priority: try container.decodeIfPresent(String.self, forKey: .priority) ?? "normal"
            ))
        case .cancel:
            self.message = .cancel
        case .pauseSpeech:
            self.message = .pauseSpeech(try container.decode(Bool.self, forKey: .switchValue))
        case .tone:
            self.message = .tone(
                hz: try container.decode(Double.self, forKey: .hz),
                length: try container.decode(Double.self, forKey: .length),
                left: try container.decode(Double.self, forKey: .left),
                right: try container.decode(Double.self, forKey: .right)
            )
        case .wave:
            self.message = .wave(
                fileName: try container.decode(String.self, forKey: .fileName),
                asynchronous: try container.decodeIfPresent(Bool.self, forKey: .asynchronous) ?? false
            )
        case .sendSAS:
            self.message = .sendSAS
        case .display:
            self.message = .display(cells: try container.decode([Int].self, forKey: .cells))
        case .brailleInput:
            self.message = .brailleInput(
                dots: try container.decodeIfPresent(Int.self, forKey: .dots),
                space: try container.decodeIfPresent(Bool.self, forKey: .space),
                routingIndex: try container.decodeIfPresent(Int.self, forKey: .routingIndex)
            )
        case .setBrailleInfo:
            self.message = .setBrailleInfo(
                name: try container.decode(String.self, forKey: .name),
                numCells: try container.decode(Int.self, forKey: .numCells)
            )
        case .setDisplaySize:
            self.message = .setDisplaySize(sizes: try container.decode([Int].self, forKey: .sizes))
        case .setClipboardText:
            self.message = .setClipboardText(.init(text: try container.decode(String.self, forKey: .text)))
        case .motd:
            self.message = .motd(.init(
                motd: try container.decode(String.self, forKey: .motd),
                forceDisplay: try container.decodeIfPresent(Bool.self, forKey: .forceDisplay) ?? false
            ))
        case .versionMismatch:
            self.message = .versionMismatch
        case .ping:
            self.message = .ping(.init())
        case .error:
            self.message = .error(try ErrorPayload(from: decoder))
        case .nvdaNotConnected:
            self.message = .nvdaNotConnected
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message.type, forKey: .type)
        try container.encodeIfPresent(origin, forKey: .origin)
        switch message {
        case let .protocolVersion(payload):
            try container.encode(payload.version, forKey: .version)
        case let .join(payload):
            try container.encode(payload.channel, forKey: .channel)
            try container.encode(payload.connectionType, forKey: .connectionType)
        case let .channelJoined(payload):
            try container.encode(payload.channel, forKey: .channel)
            try container.encode(payload.clients, forKey: .clients)
        case let .clientJoined(payload):
            try container.encode(payload.client, forKey: .client)
        case let .clientLeft(payload):
            try container.encode(payload.clientID, forKey: .clientID)
        case let .key(payload):
            try container.encode(payload.vkCode, forKey: .vkCode)
            try container.encodeIfPresent(payload.scanCode, forKey: .scanCode)
            try container.encode(payload.extended, forKey: .extended)
            try container.encode(payload.pressed, forKey: .pressed)
        case let .speak(payload):
            try container.encode(payload.sequence, forKey: .sequence)
            try container.encode(payload.priority, forKey: .priority)
        case .cancel:
            break
        case let .pauseSpeech(switchValue):
            try container.encode(switchValue, forKey: .switchValue)
        case let .tone(hz, length, left, right):
            try container.encode(hz, forKey: .hz)
            try container.encode(length, forKey: .length)
            try container.encode(left, forKey: .left)
            try container.encode(right, forKey: .right)
        case let .wave(fileName, asynchronous):
            try container.encode(fileName, forKey: .fileName)
            try container.encode(asynchronous, forKey: .asynchronous)
        case .sendSAS:
            break
        case let .display(cells):
            try container.encode(cells, forKey: .cells)
        case let .brailleInput(dots, space, routingIndex):
            try container.encodeIfPresent(dots, forKey: .dots)
            try container.encodeIfPresent(space, forKey: .space)
            try container.encodeIfPresent(routingIndex, forKey: .routingIndex)
        case let .setBrailleInfo(name, numCells):
            try container.encode(name, forKey: .name)
            try container.encode(numCells, forKey: .numCells)
        case let .setDisplaySize(sizes):
            try container.encode(sizes, forKey: .sizes)
        case let .setClipboardText(payload):
            try container.encode(payload.text, forKey: .text)
        case let .motd(payload):
            try container.encode(payload.motd, forKey: .motd)
            try container.encode(payload.forceDisplay, forKey: .forceDisplay)
        case .versionMismatch:
            break
        case .ping:
            break
        case let .error(payload):
            try container.encode(payload.code, forKey: .code)
            try container.encode(payload.message, forKey: .message)
        case .nvdaNotConnected:
            break
        }
    }
}

public struct NewlineDelimitedJSONSerializer: Sendable {
    public let encoder: JSONEncoder
    public let decoder: JSONDecoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        self.encoder = encoder
        self.decoder = decoder
    }

    public func serialize(_ envelope: RemoteEnvelope) throws -> Data {
        try encoder.encode(envelope) + Data([0x0A])
    }

    public func deserialize(_ data: Data) throws -> RemoteEnvelope {
        let trimmed = data.last == 0x0A ? data.dropLast() : data[...]
        return try decoder.decode(RemoteEnvelope.self, from: Data(trimmed))
    }
}
