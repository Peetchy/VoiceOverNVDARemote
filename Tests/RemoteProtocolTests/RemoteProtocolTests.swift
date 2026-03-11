import XCTest
@testable import RemoteProtocol

final class RemoteProtocolTests: XCTestCase {
    func testRoundTripJoinEnvelope() throws {
        let serializer = NewlineDelimitedJSONSerializer()
        let envelope = RemoteEnvelope(
            origin: 42,
            message: .join(.init(channel: "alpha", connectionType: .master))
        )

        let data = try serializer.serialize(envelope)
        let decoded = try serializer.deserialize(data)

        XCTAssertEqual(decoded, envelope)
    }

    func testSpeakEnvelopeUsesExpectedType() throws {
        let serializer = NewlineDelimitedJSONSerializer()
        let envelope = RemoteEnvelope(message: .speak(.init(sequence: [.text("Hello")], priority: "high")))

        let data = try serializer.serialize(envelope)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"type\":\"speak\""))
        XCTAssertEqual(try serializer.deserialize(data), envelope)
    }

    func testClientLeftAcceptsUserIDAlias() throws {
        let serializer = NewlineDelimitedJSONSerializer()
        let payload = #"{"type":"client_left","user_id":17}"#.data(using: .utf8)!

        let decoded = try serializer.deserialize(payload)

        XCTAssertEqual(decoded, RemoteEnvelope(message: .clientLeft(.init(clientID: 17))))
    }

    func testErrorAcceptsMissingCode() throws {
        let serializer = NewlineDelimitedJSONSerializer()
        let payload = #"{"type":"error","message":"incorrect_password"}"#.data(using: .utf8)!

        let decoded = try serializer.deserialize(payload)

        XCTAssertEqual(decoded, RemoteEnvelope(message: .error(.init(code: "error", message: "incorrect_password"))))
    }

    func testUnknownMessageTypeIsPreservedAsUnsupported() throws {
        let serializer = NewlineDelimitedJSONSerializer()
        let payload = #"{"type":"mystery_packet","value":1}"#.data(using: .utf8)!

        let decoded = try serializer.deserialize(payload)

        XCTAssertEqual(decoded, RemoteEnvelope(message: .unsupported("mystery_packet")))
    }
}
