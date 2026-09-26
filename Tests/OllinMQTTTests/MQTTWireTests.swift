import Foundation
import Testing
@testable import OllinMQTT

/// Wire-format correctness for the hand-written MQTT 3.1.1 encoder and decoder:
/// every packet kind round-trips, the remaining-length field holds at its
/// boundaries, and malformed bytes are refused rather than trapped. No network,
/// no GPU, so these run everywhere including CI.
@Suite
struct MQTTWireTests {

    /// Encode, decode, expect the same packet back and the whole buffer consumed.
    func roundTrip(_ packet: MQTTPacket,
                   sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)) {
        let data = packet.encode()
        do {
            guard let taken = try MQTTPacket.decode(from: data) else {
                Issue.record("decode returned nothing", sourceLocation: sourceLocation)
                return
            }
            #expect(taken.consumed == data.count, sourceLocation: sourceLocation)
            #expect(taken.packet == packet, sourceLocation: sourceLocation)
        } catch {
            Issue.record("decode threw \(error)", sourceLocation: sourceLocation)
        }
    }

    @Test func everyPacketKindRoundTrips() {
        roundTrip(.connect(MQTTConnect(clientID: "ollin-test")))
        roundTrip(.connect(MQTTConnect(clientID: "ollin-test", cleanSession: false, keepAlive: 90,
                                       will: MQTTWill(topic: "sketch/status", text: "gone",
                                                      qos: .atLeastOnce, retains: true),
                                       username: "edgardo", password: "secret")))
        roundTrip(.connectAcknowledgement(sessionPresent: true, code: 0))
        roundTrip(.connectAcknowledgement(sessionPresent: false, code: 5))
        roundTrip(.publish(MQTTPublish(topic: "home/kitchen/temperature", payload: Data("21.4".utf8))))
        roundTrip(.publish(MQTTPublish(topic: "home/lamp/set", payload: Data("ON".utf8),
                                       qos: .atLeastOnce, retains: true,
                                       isDuplicate: true, id: 4242)))
        roundTrip(.publishAcknowledgement(id: 7))
        roundTrip(.subscribe(id: 1, filters: [("home/+/temperature", .atMostOnce),
                                              ("home/#", .atLeastOnce)]))
        roundTrip(.subscribeAcknowledgement(id: 1, codes: [0, 1, 0x80]))
        roundTrip(.unsubscribe(id: 2, filters: ["home/#"]))
        roundTrip(.unsubscribeAcknowledgement(id: 2))
        roundTrip(.ping)
        roundTrip(.pingResponse)
        roundTrip(.disconnect)
    }

    /// The header the specification spells out byte by byte: the packet kind in
    /// the high nibble, the protocol name as a length-prefixed "MQTT", level 4,
    /// then the flag bits in the places the standard fixes them.
    @Test func connectMatchesTheSpecifiedLayout() {
        let bytes = [UInt8](MQTTPacket.connect(MQTTConnect(clientID: "ab", keepAlive: 60)).encode())
        #expect(bytes[0] == 0x10)                       // CONNECT, flags 0
        #expect(bytes[1] == UInt8(bytes.count - 2))     // remaining length
        #expect(Array(bytes[2...7]) == [0x00, 0x04, 0x4D, 0x51, 0x54, 0x54])
        #expect(bytes[8] == 4)                          // protocol level 3.1.1
        #expect(bytes[9] == 0x02)                       // clean session only
        #expect(bytes[10] == 0 && bytes[11] == 60)      // keep alive, high byte first
        #expect(Array(bytes[12...]) == [0x00, 0x02, 0x61, 0x62])

        // Each optional piece lights its own flag bit, and the will's level rides
        // bits 3 and 4.
        let full = MQTTConnect(clientID: "x",
                               will: MQTTWill(topic: "t", text: "w", qos: .atLeastOnce, retains: true),
                               username: "u", password: "p")
        let flags = [UInt8](MQTTPacket.connect(full).encode())[9]
        #expect(flags == 0x02 | 0x04 | (1 << 3) | 0x20 | 0x40 | 0x80)
    }

    /// The low nibble of SUBSCRIBE and UNSUBSCRIBE is fixed at 0b0010 by the
    /// standard, and a broker must reject any other value. Ours does.
    @Test func subscribeCarriesTheReservedFlags() throws {
        var bytes = MQTTPacket.subscribe(id: 1, filters: [("a/#", .atMostOnce)]).encode()
        #expect(bytes[bytes.startIndex] == 0x82)
        bytes[bytes.startIndex] = 0x80
        #expect(throws: MQTTWireError.badReservedFlags) { try MQTTPacket.decode(from: bytes) }

        var unsubscribe = MQTTPacket.unsubscribe(id: 1, filters: ["a/#"]).encode()
        #expect(unsubscribe[unsubscribe.startIndex] == 0xA2)
        unsubscribe[unsubscribe.startIndex] = 0xA0
        #expect(throws: MQTTWireError.badReservedFlags) { try MQTTPacket.decode(from: unsubscribe) }
    }

    /// The remaining-length field is seven bits a byte with a continuation bit,
    /// so every power-of-128 boundary changes its width. Four bytes is the
    /// ceiling, and a fifth continuation byte is refused.
    @Test func remainingLengthHoldsAtItsBoundaries() throws {
        for (value, width) in [(0, 1), (127, 1), (128, 2), (16_383, 2),
                               (16_384, 3), (2_097_151, 3), (2_097_152, 4), (268_435_455, 4)] {
            var bytes = Data()
            bytes.appendMQTTVariable(value)
            #expect(bytes.count == width, "\(value) should take \(width) bytes")
            let read = try Data.readMQTTVariable(bytes, from: 0)
            #expect(read?.value == value)
            #expect(read?.next == width)
        }
        // A field that is still arriving reads as nothing yet, not as an error.
        #expect(try Data.readMQTTVariable(Data([0x80]), from: 0) == nil)
        // Five continuation bytes cannot be a length.
        #expect(throws: MQTTWireError.lengthTooLong) {
            try Data.readMQTTVariable(Data([0x80, 0x80, 0x80, 0x80, 0x01]), from: 0)
        }
    }

    /// Every prefix of a valid packet decodes to nothing rather than trapping or
    /// claiming a packet, which is what lets the reader keep a partial packet in
    /// its buffer until the rest of it lands.
    @Test func everyPrefixOfAPacketIsIncompleteRatherThanWrong() throws {
        let whole = MQTTPacket.publish(MQTTPublish(topic: "home/kitchen/temperature",
                                                   payload: Data("21.4".utf8),
                                                   qos: .atLeastOnce, id: 9)).encode()
        for cut in 1..<whole.count {
            let partial = whole.prefix(cut)
            #expect(try MQTTPacket.decode(from: Data(partial)) == nil, "prefix of \(cut) bytes")
        }
        // And two packets back to back come off one at a time.
        var pair = whole
        pair.append(MQTTPacket.ping.encode())
        let first = try #require(try MQTTPacket.decode(from: pair))
        #expect(first.consumed == whole.count)
        let second = try #require(try MQTTPacket.decode(from: Data(pair.dropFirst(first.consumed))))
        #expect(second.packet == .ping)
    }

    /// Malformed bytes are refused without trapping: either an error or a
    /// request for more, never a crash and never a packet claimed out of noise.
    /// The seeded sweep over every packet kind lives in `MQTTMutationTests`;
    /// these are the refusals pinned by hand.
    @Test func noiseIsRefusedWithoutTrapping() {
        // A body that claims more than it carries is incomplete, and a body that
        // is shorter than its own fields says so.
        #expect(try! MQTTPacket.decode(from: Data([0x30, 0x20, 0x00, 0x01, 0x61])) == nil)
        #expect(throws: MQTTWireError.self) {
            try MQTTPacket.decode(from: Data([0x30, 0x03, 0x00, 0x08, 0x61]))
        }
        // Packet kind 0 and the three exactly-once packets have no case here.
        #expect(throws: MQTTWireError.unknownPacketKind) {
            try MQTTPacket.decode(from: Data([0x00, 0x00]))
        }
        #expect(throws: MQTTWireError.unknownPacketKind) {
            try MQTTPacket.decode(from: Data([0x50, 0x02, 0x00, 0x01]))
        }
    }

    /// The matching table from the specification, plus the two rules that are
    /// easy to get wrong: `#` covers the parent level, and a leading wildcard
    /// never reaches the broker's own `$` namespace.
    @Test func topicFiltersMatchTheSpecifiedTable() {
        #expect(MQTTTopic.matches("sport/tennis/player1", filter: "sport/tennis/player1/#"))
        #expect(MQTTTopic.matches("sport/tennis/player1/ranking", filter: "sport/tennis/player1/#"))
        #expect(MQTTTopic.matches("sport/tennis/player1/score/wimbledon", filter: "sport/tennis/player1/#"))
        #expect(MQTTTopic.matches("sport", filter: "sport/#"))
        #expect(MQTTTopic.matches("sport/tennis/player1", filter: "sport/+/player1"))
        #expect(MQTTTopic.matches("sport/", filter: "sport/+"))
        #expect(!MQTTTopic.matches("sport", filter: "sport/+"))
        #expect(!MQTTTopic.matches("sport/tennis/player1", filter: "sport/+"))
        #expect(MQTTTopic.matches("home/kitchen/temperature", filter: "home/+/temperature"))
        #expect(!MQTTTopic.matches("home/kitchen/humidity", filter: "home/+/temperature"))
        #expect(MQTTTopic.matches("anything/at/all", filter: "#"))
        #expect(MQTTTopic.matches("home/lamp", filter: "home/lamp"))

        // The `$` namespace is the broker's own, and a wildcard at the front does
        // not reach into it.
        #expect(!MQTTTopic.matches("$SYS/broker/uptime", filter: "#"))
        #expect(!MQTTTopic.matches("$SYS/monitor/Clients", filter: "+/monitor/Clients"))
        #expect(MQTTTopic.matches("$SYS/broker/uptime", filter: "$SYS/#"))
        #expect(MQTTTopic.matches("$SYS/monitor/Clients", filter: "$SYS/monitor/+"))
    }

    /// A filter a broker would refuse never leaves the client: `#` only as a
    /// whole final level, `+` only as a whole level.
    @Test func illegalFiltersAreRefused() {
        #expect(MQTTTopic.isValidFilter("home/+/temperature"))
        #expect(MQTTTopic.isValidFilter("#"))
        #expect(MQTTTopic.isValidFilter("home/#"))
        #expect(!MQTTTopic.isValidFilter(""))
        #expect(!MQTTTopic.isValidFilter("home/#/temperature"))
        #expect(!MQTTTopic.isValidFilter("home/sport#"))
        #expect(!MQTTTopic.isValidFilter("home/+temperature"))
        #expect(!MQTTTopic.isValidFilter("home/te+mp"))
    }

    /// What the devices actually publish: a decimal reading, the words a switch
    /// uses, and a small JSON object from a bridge.
    @Test func payloadsReadTheWayDevicesWriteThem() {
        #expect(MQTTMessage(topic: "t", text: "21.4").number == 21.4)
        #expect(MQTTMessage(topic: "t", text: " 21.4\n").number == 21.4)
        #expect(MQTTMessage(topic: "t", text: "21.6").int == 22)
        #expect(MQTTMessage(topic: "t", text: "hello").number == nil)
        #expect(MQTTMessage(topic: "t", text: "ON").bool == true)
        #expect(MQTTMessage(topic: "t", text: "off").bool == false)
        #expect(MQTTMessage(topic: "t", text: "1").bool == true)
        #expect(MQTTMessage(topic: "t", text: "online").bool == true)
        #expect(MQTTMessage(topic: "t", text: "maybe").bool == nil)
        #expect(MQTTMessage(topic: "t", text: "hello").text == "hello")
        // Bytes that are not text read as nothing rather than as mojibake.
        #expect(MQTTMessage(topic: "t", payload: Data([0xFF, 0xFE])).text == nil)

        let json = MQTTMessage(topic: "t", text: #"{"temperature": 21.4, "battery": 87, "state": "ON", "linked": true, "rssi": "-62"}"#)
        #expect(json.number(named: "temperature") == 21.4)
        #expect(json.int(named: "battery") == 87)
        #expect(json.text(named: "state") == "ON")
        #expect(json.bool(named: "state") == true)
        #expect(json.bool(named: "linked") == true)
        #expect(json.number(named: "rssi") == -62)      // a number written as a string
        #expect(json.number(named: "missing") == nil)
        #expect(MQTTMessage(topic: "t", text: "21.4").number(named: "temperature") == nil)
    }

    /// A published number is plain decimal text, because that is what a device
    /// reading the topic parses. No exponent, no trailing zeros, no locale.
    @Test func numbersArePublishedAsPlainDecimals() {
        #expect(MQTTClient.format(21) == "21")
        #expect(MQTTClient.format(21.0) == "21")
        #expect(MQTTClient.format(21.4) == "21.4")
        #expect(MQTTClient.format(-0.5) == "-0.5")
        #expect(MQTTClient.format(0.000001) == "0.000001")
        #expect(MQTTClient.format(1e-9) == "0")
        #expect(MQTTClient.format(.nan) == "0")
        #expect(MQTTClient.format(.infinity) == "0")
        // And it reads back as the number it was.
        #expect(MQTTMessage(topic: "t", text: MQTTClient.format(21.4)).number == 21.4)
    }

    /// Every refusal code says what to fix, because a broker that says no says it
    /// once and the sketch has only `lastError` to go on.
    @Test func everyRefusalCodeHasWords() {
        for code in UInt8(1)...5 {
            #expect(!MQTTClient.refusal(code).isEmpty)
            #expect(!MQTTClient.refusal(code).contains("code"))
        }
        #expect(MQTTClient.refusal(9).contains("9"))
    }
}
