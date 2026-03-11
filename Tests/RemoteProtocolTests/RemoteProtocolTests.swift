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
}
