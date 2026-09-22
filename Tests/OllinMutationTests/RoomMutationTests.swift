import Foundation
import Testing
import Ollin
import OllinMutation
@testable import OllinRoom

/// The room's frames, every kind and every value tag, under the mutation
/// harness, each decoded value read every way a sketch reads one and each
/// parameter payload restored into the two numeric parameter types.
@Suite struct RoomMutationTests {

    static func seeds() -> [[UInt8]] {
        let values: [RoomValue] = [
            .number(21.5), .int(-3), .text("héllo"), .bool(true), .point(Vector2(1, 2)),
            .color(Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)), .bytes(Data([1, 2, 3])),
        ]
        var seeds = values.map { [UInt8](RoomWire.encodeValue(key: "level", value: $0)) }
        seeds.append([UInt8](RoomWire.encodeHello(seat: 2, sketchName: "Wall")))
        seeds.append([UInt8](RoomWire.encodeHello(seat: nil, sketchName: "")))
        if let parameter = RoomWire.encodeParameter(name: "radius", stored: .number(120), turnedAt: 12.5) {
            seeds.append([UInt8](parameter))
        }
        if let parameter = RoomWire.encodeParameter(name: "tint", stored: .color(red: 1, green: 0.5, blue: 0, alpha: 1),
                                                    turnedAt: 1) {
            seeds.append([UInt8](parameter))
        }
        seeds.append([UInt8](RoomWire.encodeClockPing(id: 7)))
        seeds.append([UInt8](RoomWire.encodeClockPong(id: 7, roomTime: 3.25)))
        return seeds
    }

    @Test func everyFrameKind() {
        let report = MutationRun.run("room", seeds: Self.seeds(), count: 600) { bytes in
            guard let (kind, payload) = RoomWire.unframe(Data(bytes)) else { return false }
            switch kind {
            case .value:
                guard let (key, value) = RoomWire.decodeValue(payload) else { return false }
                _ = key
                _ = value.number
                _ = value.int
                _ = value.text
                _ = value.bool
                _ = value.point
                _ = value.color
                _ = value.bytes
                _ = RoomMessage(key: key, value: value, sender: "peer").int
                return true
            case .hello:
                return RoomWire.decodeHello(payload) != nil
            case .parameter:
                guard let (name, turnedAt, stored) = RoomWire.decodeParameter(payload) else { return false }
                _ = name
                _ = turnedAt
                _ = Int.restored(stored)
                _ = Double.restored(stored)
                return true
            case .clockPing:
                return RoomWire.decodeClockPing(payload) != nil
            case .clockPong:
                return RoomWire.decodeClockPong(payload) != nil
            }
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    @Test func aNumberTooLargeForAnIntReadsAsNone() {
        #expect(RoomValue.number(1e300).int == nil)
        #expect(RoomValue.number(-1e300).int == nil)
        #expect(RoomValue.number(.nan).int == nil)
        #expect(RoomValue.number(12.9).int == 12)
        #expect(Int.restored(.number(1e300)) == nil)
        #expect(Int.restored(.number(.infinity)) == nil)
        #expect(Int.restored(.number(12.6)) == 13)
    }
}
