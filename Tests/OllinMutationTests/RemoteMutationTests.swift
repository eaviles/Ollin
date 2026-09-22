import Foundation
import Testing
import Ollin
import OllinMutation
@testable import OllinRemote

/// The remote surface's wire, under the mutation harness: the HTTP request
/// head the two small servers share, the WebSocket frames a phone sends, the
/// `set` message inside them, and the apply path at the numbers narrowing is
/// wrong at.
@Suite struct RemoteMutationTests {

    static let heads = [
        "GET / HTTP/1.1\r\nHost: mac.local:8080\r\nAccept: text/html\r\n\r\n",
        "GET /socket HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n",
        "POST /set HTTP/1.1\r\nContent-Length: 14\r\n\r\n{\"kind\":\"set\"}",
        "GET /a b HTTP/1.1\r\n:\r\nx:\r\n\r\n",
    ]

    @Test func requestHeads() {
        let report = MutationRun.run("http-head", seeds: Self.heads.map { Array($0.utf8) }, count: 500) { bytes in
            guard let (request, consumed) = RemoteHTTP.parseHead(bytes) else { return false }
            _ = consumed
            if RemoteHTTP.isWebSocketUpgrade(request) {
                _ = RemoteHTTP.upgradeResponse(accept: RemoteHTTP.acceptKey(for: request.headers["sec-websocket-key"] ?? ""))
            }
            _ = RemoteHTTP.notFound()
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    /// A client frame as a browser sends one: masked, at each of the three
    /// length forms.
    static func masked(_ opcode: WebSocketFraming.Opcode, payload: [UInt8], mask: [UInt8],
                       lengthForm: Int? = nil) -> [UInt8] {
        var out: [UInt8] = [0x80 | opcode.rawValue]
        let n = payload.count
        let form = lengthForm ?? (n < 126 ? 0 : n <= 0xFFFF ? 126 : 127)
        if form == 0 {
            out.append(0x80 | UInt8(n))
        } else if form == 126 {
            out.append(0x80 | 126)
            out.append(UInt8(n >> 8))
            out.append(UInt8(n & 0xFF))
        } else {
            out.append(0x80 | 127)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((UInt64(n) >> UInt64(shift)) & 0xFF))
            }
        }
        out.append(contentsOf: mask)
        for (index, byte) in payload.enumerated() { out.append(byte ^ mask[index % 4]) }
        return out
    }

    static func frameSeeds() -> [[UInt8]] {
        let set = #"{"kind":"set","name":"radius","value":{"number":140.5}}"#
        let menu = #"{"kind":"set","name":"mood","value":{"number":2}}"#
        return [
            [UInt8](WebSocketFraming.encodeText(set)),
            masked(.text, payload: Array(set.utf8), mask: [1, 2, 3, 4]),
            masked(.text, payload: Array(menu.utf8), mask: [0, 0, 0, 0]),
            masked(.binary, payload: [UInt8](repeating: 7, count: 300), mask: [9, 8, 7, 6]),
            [UInt8](WebSocketFraming.encode(.ping, payload: [1, 2, 3])) + [UInt8](WebSocketFraming.encode(.close, payload: [3, 0xE8])),
            // The eight-byte length form on a small frame, which a sender may write.
            masked(.text, payload: Array(menu.utf8), mask: [5, 6, 7, 8], lengthForm: 127),
        ]
    }

    static func decodeFrames(_ bytes: [UInt8]) -> Bool {
        var buffer = bytes
        guard let frames = WebSocketFraming.decode(buffer: &buffer) else { return false }
        for frame in frames where frame.opcode == .text {
            if let set = try? JSONDecoder().decode(RemoteSet.self, from: Data(frame.payload)) {
                _ = Int.restored(set.value)
                _ = Double.restored(set.value)
            }
        }
        return !frames.isEmpty
    }

    @Test func webSocketFramesAndTheSetInsideThem() {
        let report = MutationRun.run("websocket", seeds: Self.frameSeeds(), count: 400, decode: Self.decodeFrames)
        #expect(report.seedsRefused.isEmpty, "\(report)")
        // A frame past 65,535 bytes, which the eight-byte form exists for; too
        // large to sweep every field of, so only the random edits run over it.
        let large = MutationRun.run("websocket-large",
                                    seeds: [Self.masked(.text, payload: [UInt8](repeating: 0x20, count: 70_000), mask: [0, 0, 0, 1])],
                                    count: 100, sweeps: false, decode: Self.decodeFrames)
        #expect(large.seedsRefused.isEmpty, "\(large)")
    }

    @MainActor @Test func extremeValuesAppliedToEveryParameter() {
        let sketch = RemoteProbeSketch()
        let values: [ParamStored] = [
            .number(.nan), .number(.infinity), .number(-.infinity), .number(1e300), .number(-1e300),
            .number(9.3e18), .number(-9.3e18), .number(4_294_967_296), .number(-0.0), .number(2.5),
            .boolean(true), .text("1e300"),
        ]
        for handle in sketch.parameters() {
            for value in values { RemoteWire.apply(value, to: handle) }
            _ = RemoteWire.descriptor(for: handle)
            _ = RemoteWire.snapshotValue(of: handle)
        }
        let sets = ["1e300", "-1e300", "1e400", "9223372036854775808", "2.5", "-0"].map {
            #"{"kind":"set","name":"count","value":{"number":"# + $0 + "}}"
        }
        for json in sets {
            guard let set = try? JSONDecoder().decode(RemoteSet.self, from: Data(json.utf8)) else { continue }
            for handle in sketch.parameters() where handle.name == set.name { RemoteWire.apply(set.value, to: handle) }
        }
        #expect(sketch.count >= 1 && sketch.count <= 12)
        #expect(sketch.mood == .dusk || sketch.mood == .noir || sketch.mood == .dawn)
    }
}

private final class RemoteProbeSketch: Sketch {
    enum Mood: String, CaseIterable, ParamOption { case dawn, dusk, noir }
    @Param(20...400) var radius = 120.0
    @Param(1...12) var count = 6
    @Param var spin = true
    @Param var mood = Mood.dusk
    @Param(count: 1...8) var inks = Palette(.red, .white, .black)
}
