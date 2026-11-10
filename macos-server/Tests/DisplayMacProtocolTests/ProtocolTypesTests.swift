import XCTest
@testable import DisplayMacProtocol

final class ProtocolTypesTests: XCTestCase {

    func testClientHelloRoundTripWithDeviceName() {
        let original = ClientHello(
            displayWidth: 2560,
            displayHeight: 1600,
            maxRefreshRate: 120,
            dpi: 320,
            codecMask: VideoCodec.hevc.rawValue,
            flags: 0x03,
            deviceName: "Galaxy Tab S9"
        )

        let payload = original.serializePayload()
        let decoded = ClientHello(from: payload)

        XCTAssertEqual(decoded, original)
    }

    func testClientHelloRejectsOutOfBoundsDimensions() {
        let invalid = ClientHello(
            displayWidth: 100,
            displayHeight: 100,
            maxRefreshRate: 120,
            dpi: 280
        )

        XCTAssertNil(ClientHello(from: invalid.serializePayload()))
        XCTAssertNil(ClientHello(from: Data([0x01, 0x02])))
    }

    func testClientHelloSanitizesControlCharacters() {
        let dirty = ClientHello(
            displayWidth: 1920,
            displayHeight: 1080,
            maxRefreshRate: 60,
            dpi: 264,
            deviceName: "Test\n\r\tTablet"
        )
        let decoded = ClientHello(from: dirty.serializePayload())
        XCTAssertEqual(decoded?.deviceName, "TestTablet")
    }

    func testServerConfigSerializationMatchesWireLayout() {
        let config = ServerConfig(
            selectedCodec: .hevc,
            activeFps: 120,
            streamWidth: 2960,
            streamHeight: 1848,
            targetBitrateKbps: 60_000
        )

        let bytes = config.serialize()
        XCTAssertEqual(bytes.count, 14)
        XCTAssertEqual(bytes[0], VideoCodec.hevc.rawValue)
        XCTAssertEqual(bytes[1], 120)
        XCTAssertEqual(bytes.readUInt32BE(at: 2), 2960)
        XCTAssertEqual(bytes.readUInt32BE(at: 6), 1848)
        XCTAssertEqual(bytes.readUInt32BE(at: 10), 60_000)
    }

    func testStylusPacketParsesBigEndianFloats() {
        var payload = Data()
        payload.append(StylusAction.move)
        payload.append(0x01)
        payload.appendUInt32BE(Float(0.25).bitPattern)
        payload.appendUInt32BE(Float(0.75).bitPattern)
        payload.appendUInt32BE(Float(0.5).bitPattern)
        payload.appendUInt32BE(Float(0.125).bitPattern)

        let packet = StylusPacket(from: payload)
        XCTAssertNotNil(packet)
        XCTAssertEqual(packet?.action, StylusAction.move)
        XCTAssertEqual(packet?.buttons, 0x01)
        XCTAssertEqual(packet!.normalizedX, 0.25, accuracy: 0.0001)
        XCTAssertEqual(packet!.normalizedY, 0.75, accuracy: 0.0001)
        XCTAssertEqual(packet!.pressure, 0.5, accuracy: 0.0001)
        XCTAssertEqual(packet!.tilt, 0.125, accuracy: 0.0001)
    }

    func testTouchPacketParsesBigEndianFloats() {
        var payload = Data()
        payload.append(TouchAction.scroll)
        payload.append(TouchPhase.changed)
        payload.appendUInt32BE(Float(0.5).bitPattern)
        payload.appendUInt32BE(Float(0.5).bitPattern)
        payload.appendUInt32BE(Float(-12.5).bitPattern)
        payload.appendUInt32BE(Float(24.0).bitPattern)

        let packet = TouchPacket(from: payload)
        XCTAssertNotNil(packet)
        XCTAssertEqual(packet?.action, TouchAction.scroll)
        XCTAssertEqual(packet?.phase, TouchPhase.changed)
        XCTAssertEqual(packet!.deltaX, -12.5, accuracy: 0.0001)
        XCTAssertEqual(packet!.deltaY, 24.0, accuracy: 0.0001)
    }
}
