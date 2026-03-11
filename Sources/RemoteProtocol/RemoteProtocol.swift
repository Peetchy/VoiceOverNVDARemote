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
    case generateKey = "generate_key"
    case key
    case speak
    case cancel
    case pauseSpeech = "pause_speech"
    case tone
    case wave
    case sendSAS = "send_SAS"
    case index
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
    case generateKey(String?)
    case key(KeyPayload)
    case speak(SpeakPayload)
    case cancel
    case pauseSpeech(Bool)
    case tone(hz: Double, length: Double, left: Double, right: Double)
    case wave(fileName: String, asynchronous: Bool)
    case sendSAS
    case index(Int?)
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
    case unsupported(String)
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
        case key
        case index
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
        let type = try container.decode(String.self, forKey: .type)
        let origin = try container.decodeIfPresent(Int.self, forKey: .origin)
        self.origin = origin
        switch type {
        case RemoteMessageType.protocolVersion.rawValue:
            self.message = .protocolVersion(.init(version: try container.decode(Int.self, forKey: .version)))
        case RemoteMessageType.join.rawValue:
            self.message = .join(.init(
                channel: try container.decode(String.self, forKey: .channel),
                connectionType: try container.decode(RemoteRole.self, forKey: .connectionType)
            ))
        case RemoteMessageType.channelJoined.rawValue:
            self.message = .channelJoined(.init(
                channel: try container.decode(String.self, forKey: .channel),
                clients: try container.decodeIfPresent([RemoteClientDescriptor].self, forKey: .clients) ?? []
            ))
        case RemoteMessageType.clientJoined.rawValue:
            self.message = .clientJoined(.init(client: try container.decode(RemoteClientDescriptor.self, forKey: .client)))
        case RemoteMessageType.clientLeft.rawValue:
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
        case RemoteMessageType.generateKey.rawValue:
            self.message = .generateKey(try container.decodeIfPresent(String.self, forKey: .key))
        case RemoteMessageType.key.rawValue:
            self.message = .key(.init(
                vkCode: try container.decode(UInt16.self, forKey: .vkCode),
                scanCode: try container.decodeIfPresent(UInt16.self, forKey: .scanCode),
                extended: try container.decode(Bool.self, forKey: .extended),
                pressed: try container.decode(Bool.self, forKey: .pressed)
            ))
        case RemoteMessageType.speak.rawValue:
            self.message = .speak(.init(
                sequence: try container.decode([SpeechSequenceItem].self, forKey: .sequence),
                priority: try container.decodeIfPresent(String.self, forKey: .priority) ?? "normal"
            ))
        case RemoteMessageType.cancel.rawValue:
            self.message = .cancel
        case RemoteMessageType.pauseSpeech.rawValue:
            self.message = .pauseSpeech(try container.decode(Bool.self, forKey: .switchValue))
        case RemoteMessageType.tone.rawValue:
            self.message = .tone(
                hz: try container.decode(Double.self, forKey: .hz),
                length: try container.decode(Double.self, forKey: .length),
                left: try container.decode(Double.self, forKey: .left),
                right: try container.decode(Double.self, forKey: .right)
            )
        case RemoteMessageType.wave.rawValue:
            self.message = .wave(
                fileName: try container.decode(String.self, forKey: .fileName),
                asynchronous: try container.decodeIfPresent(Bool.self, forKey: .asynchronous) ?? false
            )
        case RemoteMessageType.sendSAS.rawValue:
            self.message = .sendSAS
        case RemoteMessageType.index.rawValue:
            self.message = .index(try container.decodeIfPresent(Int.self, forKey: .index))
        case RemoteMessageType.display.rawValue:
            self.message = .display(cells: try container.decode([Int].self, forKey: .cells))
        case RemoteMessageType.brailleInput.rawValue:
            self.message = .brailleInput(
                dots: try container.decodeIfPresent(Int.self, forKey: .dots),
                space: try container.decodeIfPresent(Bool.self, forKey: .space),
                routingIndex: try container.decodeIfPresent(Int.self, forKey: .routingIndex)
            )
        case RemoteMessageType.setBrailleInfo.rawValue:
            self.message = .setBrailleInfo(
                name: try container.decode(String.self, forKey: .name),
                numCells: try container.decode(Int.self, forKey: .numCells)
            )
        case RemoteMessageType.setDisplaySize.rawValue:
            self.message = .setDisplaySize(sizes: try container.decode([Int].self, forKey: .sizes))
        case RemoteMessageType.setClipboardText.rawValue:
            self.message = .setClipboardText(.init(text: try container.decode(String.self, forKey: .text)))
        case RemoteMessageType.motd.rawValue:
            self.message = .motd(.init(
                motd: try container.decode(String.self, forKey: .motd),
                forceDisplay: try container.decodeIfPresent(Bool.self, forKey: .forceDisplay) ?? false
            ))
        case RemoteMessageType.versionMismatch.rawValue:
            self.message = .versionMismatch
        case RemoteMessageType.ping.rawValue:
            self.message = .ping(.init())
        case RemoteMessageType.error.rawValue:
            self.message = .error(try ErrorPayload(from: decoder))
        case RemoteMessageType.nvdaNotConnected.rawValue:
            self.message = .nvdaNotConnected
        default:
            self.message = .unsupported(type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch message {
        case .protocolVersion:
            try container.encode(RemoteMessageType.protocolVersion.rawValue, forKey: .type)
        case .join:
            try container.encode(RemoteMessageType.join.rawValue, forKey: .type)
        case .channelJoined:
            try container.encode(RemoteMessageType.channelJoined.rawValue, forKey: .type)
        case .clientJoined:
            try container.encode(RemoteMessageType.clientJoined.rawValue, forKey: .type)
        case .clientLeft:
            try container.encode(RemoteMessageType.clientLeft.rawValue, forKey: .type)
        case .generateKey:
            try container.encode(RemoteMessageType.generateKey.rawValue, forKey: .type)
        case .key:
            try container.encode(RemoteMessageType.key.rawValue, forKey: .type)
        case .speak:
            try container.encode(RemoteMessageType.speak.rawValue, forKey: .type)
        case .cancel:
            try container.encode(RemoteMessageType.cancel.rawValue, forKey: .type)
        case .pauseSpeech:
            try container.encode(RemoteMessageType.pauseSpeech.rawValue, forKey: .type)
        case .tone:
            try container.encode(RemoteMessageType.tone.rawValue, forKey: .type)
        case .wave:
            try container.encode(RemoteMessageType.wave.rawValue, forKey: .type)
        case .sendSAS:
            try container.encode(RemoteMessageType.sendSAS.rawValue, forKey: .type)
        case .index:
            try container.encode(RemoteMessageType.index.rawValue, forKey: .type)
        case .display:
            try container.encode(RemoteMessageType.display.rawValue, forKey: .type)
        case .brailleInput:
            try container.encode(RemoteMessageType.brailleInput.rawValue, forKey: .type)
        case .setBrailleInfo:
            try container.encode(RemoteMessageType.setBrailleInfo.rawValue, forKey: .type)
        case .setDisplaySize:
            try container.encode(RemoteMessageType.setDisplaySize.rawValue, forKey: .type)
        case .setClipboardText:
            try container.encode(RemoteMessageType.setClipboardText.rawValue, forKey: .type)
        case .motd:
            try container.encode(RemoteMessageType.motd.rawValue, forKey: .type)
        case .versionMismatch:
            try container.encode(RemoteMessageType.versionMismatch.rawValue, forKey: .type)
        case .ping:
            try container.encode(RemoteMessageType.ping.rawValue, forKey: .type)
        case .error:
            try container.encode(RemoteMessageType.error.rawValue, forKey: .type)
        case .nvdaNotConnected:
            try container.encode(RemoteMessageType.nvdaNotConnected.rawValue, forKey: .type)
        case let .unsupported(type):
            try container.encode(type, forKey: .type)
        }
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
        case let .generateKey(key):
            try container.encodeIfPresent(key, forKey: .key)
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
        case let .index(index):
            try container.encodeIfPresent(index, forKey: .index)
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
        case .unsupported:
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
        do {
            return try decoder.decode(RemoteEnvelope.self, from: Data(trimmed))
        } catch {
            return try RemoteEnvelope.makeLossy(from: Data(trimmed))
        }
    }
}

extension RemoteEnvelope {
    static func makeLossy(from data: Data) throws -> RemoteEnvelope {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return try makeLossy(from: dictionary)
    }

    private static func makeLossy(from dictionary: [String: Any]) throws -> RemoteEnvelope {
        let origin = anyInt(dictionary["origin"])
        let type = anyString(dictionary["type"]) ?? "unknown"

        let message: RemoteMessage
        switch type {
        case RemoteMessageType.protocolVersion.rawValue:
            message = .protocolVersion(.init(version: anyInt(dictionary["version"]) ?? remoteProtocolVersion))
        case RemoteMessageType.join.rawValue:
            message = .join(.init(
                channel: anyString(dictionary["channel"]) ?? "",
                connectionType: RemoteRole(rawValue: anyString(dictionary["connection_type"]) ?? "") ?? .master
            ))
        case RemoteMessageType.channelJoined.rawValue:
            let clients = (dictionary["clients"] as? [Any] ?? []).compactMap(anyClientDescriptor)
            message = .channelJoined(.init(channel: anyString(dictionary["channel"]) ?? "", clients: clients))
        case RemoteMessageType.clientJoined.rawValue:
            message = .clientJoined(.init(client: anyClientDescriptor(dictionary["client"]) ?? .init(id: anyInt(dictionary["user_id"]) ?? -1, connectionType: .slave)))
        case RemoteMessageType.clientLeft.rawValue:
            let clientID = anyInt(dictionary["client_id"]) ?? anyInt(dictionary["user_id"]) ?? anyInt(dictionary["client"]) ?? -1
            message = .clientLeft(.init(clientID: clientID))
        case RemoteMessageType.generateKey.rawValue:
            message = .generateKey(anyString(dictionary["key"]))
        case RemoteMessageType.key.rawValue:
            message = .key(.init(
                vkCode: UInt16(anyInt(dictionary["vk_code"]) ?? 0),
                scanCode: anyInt(dictionary["scan_code"]).map(UInt16.init),
                extended: anyBool(dictionary["extended"]) ?? false,
                pressed: anyBool(dictionary["pressed"]) ?? false
            ))
        case RemoteMessageType.speak.rawValue:
            let sequence = (dictionary["sequence"] as? [Any] ?? []).compactMap(anySpeechSequenceItem)
            message = .speak(.init(sequence: sequence, priority: anyString(dictionary["priority"]) ?? "normal"))
        case RemoteMessageType.cancel.rawValue:
            message = .cancel
        case RemoteMessageType.pauseSpeech.rawValue:
            message = .pauseSpeech(anyBool(dictionary["switch"]) ?? false)
        case RemoteMessageType.tone.rawValue:
            message = .tone(
                hz: anyDouble(dictionary["hz"]) ?? 0,
                length: anyDouble(dictionary["length"]) ?? 0,
                left: anyDouble(dictionary["left"]) ?? 0,
                right: anyDouble(dictionary["right"]) ?? 0
            )
        case RemoteMessageType.wave.rawValue:
            message = .wave(
                fileName: anyString(dictionary["fileName"]) ?? "",
                asynchronous: anyBool(dictionary["asynchronous"]) ?? false
            )
        case RemoteMessageType.sendSAS.rawValue:
            message = .sendSAS
        case RemoteMessageType.index.rawValue:
            message = .index(anyInt(dictionary["index"]))
        case RemoteMessageType.display.rawValue:
            message = .display(cells: (dictionary["cells"] as? [Any] ?? []).compactMap(anyInt))
        case RemoteMessageType.brailleInput.rawValue:
            message = .brailleInput(
                dots: anyInt(dictionary["dots"]),
                space: anyBool(dictionary["space"]),
                routingIndex: anyInt(dictionary["routingIndex"])
            )
        case RemoteMessageType.setBrailleInfo.rawValue:
            message = .setBrailleInfo(
                name: anyString(dictionary["name"]) ?? "",
                numCells: anyInt(dictionary["numCells"]) ?? 0
            )
        case RemoteMessageType.setDisplaySize.rawValue:
            message = .setDisplaySize(sizes: (dictionary["sizes"] as? [Any] ?? []).compactMap(anyInt))
        case RemoteMessageType.setClipboardText.rawValue:
            message = .setClipboardText(.init(text: anyString(dictionary["text"]) ?? ""))
        case RemoteMessageType.motd.rawValue:
            message = .motd(.init(
                motd: anyString(dictionary["motd"]) ?? "",
                forceDisplay: anyBool(dictionary["force_display"]) ?? false
            ))
        case RemoteMessageType.versionMismatch.rawValue:
            message = .versionMismatch
        case RemoteMessageType.ping.rawValue:
            message = .ping(.init())
        case RemoteMessageType.error.rawValue:
            message = .error(.init(
                code: anyString(dictionary["code"]) ?? "error",
                message: anyString(dictionary["message"]) ?? ""
            ))
        case RemoteMessageType.nvdaNotConnected.rawValue:
            message = .nvdaNotConnected
        default:
            message = .unsupported(type)
        }
        return .init(origin: origin, message: message)
    }
}

private func anyString(_ value: Any?) -> String? {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return nil
}

private func anyInt(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
}

private func anyDouble(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? NSNumber { return value.doubleValue }
    if let value = value as? String { return Double(value) }
    return nil
}

private func anyBool(_ value: Any?) -> Bool? {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String {
        switch value.lowercased() {
        case "true", "1": return true
        case "false", "0": return false
        default: return nil
        }
    }
    return nil
}

private func anyClientDescriptor(_ value: Any?) -> RemoteClientDescriptor? {
    guard let dictionary = value as? [String: Any] else { return nil }
    guard let id = anyInt(dictionary["id"]) else { return nil }
    let role = RemoteRole(rawValue: anyString(dictionary["connection_type"]) ?? "") ?? .slave
    return .init(id: id, connectionType: role)
}

private func anySpeechSequenceItem(_ value: Any?) -> SpeechSequenceItem? {
    if let text = value as? String {
        return .text(text)
    }
    if let array = value as? [Any], let name = anyString(array.first) {
        return .command(name: name)
    }
    return nil
}
