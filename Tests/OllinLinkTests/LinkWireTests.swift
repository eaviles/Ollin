import Foundation
import Testing
@testable import OllinLink

/// Wire-format encode/decode: round trips over every entry, the documented
/// datagram sizes, malformed input rejected by returning `nil` (never a
/// trap), and a fixture parse of a real captured announcement, so the format
/// is pinned to what actually travels on networks, not just to itself.
@Suite
struct LinkWireTests {

    func fullPayload() -> Data {
        var payload = Data()
        LinkWire.encodeTimeline(
            LinkTimeline(tempo: LinkTempo(bpm: 128), anchorMicroBeats: 42_000_000, anchorMicros: -7),
            into: &payload
        )
        LinkWire.encodeSession(LinkNodeId(raw: 0x4142_4344_4546_4748), into: &payload)
        LinkWire.encodeStartStop(
            LinkStartStop(isPlaying: true, microBeats: 16_000_000, timestampMicros: 99),
            into: &payload
        )
        LinkWire.encodeMeasurementEndpoint(
            LinkEndpoint(address: 0xC0A8_010A, port: 54_321),
            into: &payload
        )
        return payload
    }

    @Test func fullStateRoundTrips() throws {
        let bytes = LinkWire.encodeDiscovery(
            kind: .alive, ttl: 5, sender: LinkNodeId(raw: 7), payload: fullPayload()
        )
        // The documented size of a complete IPv4 announcement.
        #expect(bytes.count == 107)

        let message = try #require(LinkWire.parseDiscovery(bytes))
        #expect(message.kind == .alive)
        #expect(message.ttl == 5)
        #expect(message.sender == LinkNodeId(raw: 7))
        let timeline = try #require(message.payload.timeline)
        #expect(timeline.tempo.wireEquals(LinkTempo(bpm: 128)))
        #expect(timeline.anchorMicroBeats == 42_000_000)
        #expect(timeline.anchorMicros == -7)
        #expect(message.payload.session == LinkNodeId(raw: 0x4142_4344_4546_4748))
        let startStop = try #require(message.payload.startStop)
        #expect(startStop == LinkStartStop(isPlaying: true, microBeats: 16_000_000, timestampMicros: 99))
        #expect(message.payload.measurementEndpoint == LinkEndpoint(address: 0xC0A8_010A, port: 54_321))
    }

    /// A real captured announcement (a public protocol dissection's dump):
    /// 75 BPM, the sender as its own session founder, endpoint 10.0.1.33.
    @Test func parsesACapturedAnnouncement() throws {
        let hex = """
            5f 61 73 64 70 5f 76 01 01 05 00 00 52 7b 46 27 \
            65 45 53 3a 74 6d 6c 6e 00 00 00 18 00 00 00 00 \
            00 0c 35 00 00 00 00 00 4f 14 99 30 00 00 00 00 \
            06 2c 36 f4 73 65 73 73 00 00 00 08 52 7b 46 27 \
            65 45 53 3a 6d 65 70 34 00 00 00 06 0a 00 01 21 \
            fa f4
            """
        let bytes = Data(hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
        #expect(bytes.count == 0x52)

        let message = try #require(LinkWire.parseDiscovery(bytes))
        #expect(message.kind == .alive)
        #expect(message.ttl == 5)
        #expect(message.sender == LinkNodeId(raw: 0x527B_4627_6545_533A))
        let timeline = try #require(message.payload.timeline)
        #expect(timeline.tempo.wire == 800_000)   // 0x0c3500 µs per beat
        #expect(timeline.tempo.bpm == 75)
        #expect(timeline.anchorMicroBeats == 0x4F14_9930)
        #expect(timeline.anchorMicros == 0x062C_36F4)
        // The sender founded its own session.
        #expect(message.payload.session == message.sender)
        let endpoint = try #require(message.payload.measurementEndpoint)
        #expect(endpoint.description == "10.0.1.33:64244")
        #expect(message.payload.startStop == nil)
    }

    /// The captured farewell: the same header, kind 3, an empty payload.
    @Test func parsesACapturedFarewell() throws {
        let hex = "5f 61 73 64 70 5f 76 01 03 00 00 00 23 66 75 58 5e 6b 28 2d"
        let bytes = Data(hex.split(separator: " ").compactMap { UInt8($0, radix: 16) })
        let message = try #require(LinkWire.parseDiscovery(bytes))
        #expect(message.kind == .byeBye)
        #expect(message.ttl == 0)
        #expect(message.sender == LinkNodeId(raw: 0x2366_7558_5E6B_282D))
        #expect(message.payload == LinkPayload())
    }

    @Test func rejectsBadHeaderGroupKindAndTruncation() {
        let good = LinkWire.encodeDiscovery(kind: .alive, ttl: 5, sender: LinkNodeId(raw: 1), payload: fullPayload())

        var badHeader = good
        badHeader[0] = UInt8(ascii: "X")
        #expect(LinkWire.parseDiscovery(badHeader) == nil)

        var badGroup = good
        badGroup[11] = 1
        #expect(LinkWire.parseDiscovery(badGroup) == nil)

        var badKind = good
        badKind[8] = 9
        #expect(LinkWire.parseDiscovery(badKind) == nil)

        #expect(LinkWire.parseDiscovery(good.prefix(15)) == nil)
    }

    @Test func payloadEdgeCases() throws {
        // An unknown key is skipped over its declared size.
        var bytes = Data()
        bytes.linkAppendBE(LinkWire.fourCC("zzzz"))
        bytes.linkAppendBE(UInt32(3))
        bytes.append(contentsOf: [1, 2, 3])
        LinkWire.encodeSession(LinkNodeId(raw: 11), into: &bytes)
        let payload = try #require(LinkWire.parsePayload([UInt8](bytes)[0...]))
        #expect(payload.session == LinkNodeId(raw: 11))

        // A declared size overrunning the datagram is malformed.
        var overrun = Data()
        overrun.linkAppendBE(LinkPayloadKey.session)
        overrun.linkAppendBE(UInt32(100))
        overrun.append(contentsOf: [UInt8](repeating: 0, count: 8))
        #expect(LinkWire.parsePayload([UInt8](overrun)[0...]) == nil)

        // A truncated entry header is malformed.
        var truncated = Data()
        truncated.linkAppendBE(LinkPayloadKey.session)
        truncated.append(0)
        #expect(LinkWire.parsePayload([UInt8](truncated)[0...]) == nil)

        // A known key at an unexpected size is skipped, not adopted.
        var wrongSize = Data()
        wrongSize.linkAppendBE(LinkPayloadKey.session)
        wrongSize.linkAppendBE(UInt32(4))
        wrongSize.append(contentsOf: [9, 9, 9, 9])
        let skipped = try #require(LinkWire.parsePayload([UInt8](wrongSize)[0...]))
        #expect(skipped.session == nil)
    }

    @Test func measurementRoundTrips() throws {
        var body = Data()
        LinkWire.encodeMicros(LinkPayloadKey.hostTime, 1_234, into: &body)
        let ping = LinkWire.encodeMeasurement(kind: .ping, payload: body)
        let parsed = try #require(LinkWire.parseMeasurement(ping))
        #expect(parsed.kind == .ping)
        #expect(parsed.payload == body)

        // The pong echoes the ping payload verbatim after its own entries.
        var pongBody = Data()
        LinkWire.encodeSession(LinkNodeId(raw: 3), into: &pongBody)
        LinkWire.encodeMicros(LinkPayloadKey.ghostTime, 55, into: &pongBody)
        pongBody.append(body)
        let pong = LinkWire.encodeMeasurement(kind: .pong, payload: pongBody)
        let entries = try #require(LinkWire.parsePayload([UInt8](LinkWire.parseMeasurement(pong)!.payload)[0...]))
        #expect(entries.session == LinkNodeId(raw: 3))
        #expect(entries.ghostTimeMicros == 55)
        #expect(entries.hostTimeMicros == 1_234)

        #expect(LinkWire.parseMeasurement(Data("_nope_v1".utf8) + Data([1])) == nil)
    }
}
