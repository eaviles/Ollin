import Foundation
import Testing
import OllinMutation
@testable import OllinMQTT

/// Every MQTT control packet kind, the remaining-length field on its own, and
/// the payload readings a sketch makes of a published message, under the
/// mutation harness.
@Suite struct MQTTMutationTests {

    static func seeds() -> [[UInt8]] {
        let will = MQTTWill(topic: "sketch/status", text: "gone", qos: .atLeastOnce, retains: true)
        let packets: [MQTTPacket] = [
            .connect(MQTTConnect(clientID: "ollin-1", cleanSession: true, keepAlive: 30,
                                 will: will, username: "user", password: "pass")),
            .connect(MQTTConnect(clientID: "")),
            .connectAcknowledgement(sessionPresent: true, code: 0),
            .publish(MQTTPublish(topic: "home/kitchen/temp", payload: Data("21.4\n".utf8))),
            .publish(MQTTPublish(topic: "home/lamp",
                                 payload: Data(#"{"state":"ON","level":"12","brightness":200,"ok":true}"#.utf8),
                                 qos: .atLeastOnce, retains: true, isDuplicate: true, id: 7)),
            .publishAcknowledgement(id: 7),
            .subscribe(id: 2, filters: [("home/#", .atMostOnce), ("+/lamp", .atLeastOnce)]),
            .subscribeAcknowledgement(id: 2, codes: [0, 1]),
            .unsubscribe(id: 3, filters: ["home/#"]),
            .unsubscribeAcknowledgement(id: 3),
            .ping, .pingResponse, .disconnect,
        ]
        return packets.map { [UInt8]($0.encode()) }
    }

    @Test func everyPacketKindAndItsReadings() {
        let report = MutationRun.run("mqtt", seeds: Self.seeds(), count: 600) { bytes in
            let data = Data(bytes)
            _ = try Data.readMQTTVariable(data, from: 0)
            guard let (packet, consumed) = try MQTTPacket.decode(from: data) else { return false }
            _ = consumed
            switch packet {
            case .publish(let publish):
                let message = MQTTMessage(topic: publish.topic, payload: publish.payload, qos: publish.qos,
                                          isRetained: publish.retains, isDuplicate: publish.isDuplicate)
                _ = message.text
                _ = message.number
                _ = message.int
                _ = message.bool
                for key in ["state", "level", "brightness", "ok"] {
                    _ = message.text(named: key)
                    _ = message.number(named: key)
                    _ = message.int(named: key)
                    _ = message.bool(named: key)
                }
                _ = MQTTTopic.matches(publish.topic, filter: "home/+/#")
                _ = MQTTTopic.isValidFilter(publish.topic)
            case .subscribe(_, let filters):
                for entry in filters {
                    _ = MQTTTopic.isValidFilter(entry.filter)
                    _ = MQTTTopic.matches("home/lamp", filter: entry.filter)
                }
            case .unsubscribe(_, let filters):
                for filter in filters { _ = MQTTTopic.isValidFilter(filter) }
            default:
                break
            }
            _ = packet.encode()
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.threw > 0)
    }

    /// The remaining-length field alone: one to four bytes, the continuation
    /// bit set or not, and everything the extremes write into it.
    @Test func theRemainingLengthField() {
        var seeds: [[UInt8]] = []
        for value in [0, 1, 127, 128, 16_383, 16_384, 2_097_151, 2_097_152, 268_435_455] {
            var data = Data()
            data.appendMQTTVariable(value)
            seeds.append([UInt8](data))
        }
        let report = MutationRun.run("mqtt-varint", seeds: seeds, count: 300) { bytes in
            try Data.readMQTTVariable(Data(bytes), from: 0) != nil
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    /// The payload readings at the numbers a text reader is wrong at, by hand.
    @Test func aPayloadTooLargeForAnIntIsNotOne() {
        for text in ["1e300", "-1e300", "9223372036854775808", "nan", "inf", "1e400", "99999999999999999999"] {
            let message = MQTTMessage(topic: "t", text: text)
            _ = message.int
            _ = message.number
            _ = MQTTMessage(topic: "t", text: #"{"v":"# + text + "}").int(named: "v")
            _ = MQTTMessage(topic: "t", text: #"{"v":""# + text + #""}"#).int(named: "v")
        }
        #expect(MQTTMessage(topic: "t", text: "1e300").int == nil)
        #expect(MQTTMessage(topic: "t", text: "12.6").int == 13)
        #expect(MQTTMessage(topic: "t", text: #"{"v":1e300}"#).int(named: "v") == nil)
    }
}
