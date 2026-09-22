import Foundation
import Testing
import Ollin
import OllinMutation
@testable import OllinOSC

/// OSC packets and bundles, the TUIO surface that reads them, and the OSCQuery
/// namespace's two doors (a message read against a leaf, an HTTP request read
/// against the tree), under the mutation harness. Every decoded value is also
/// read every way a sketch can read it, since a reader that narrows a number
/// is as much on the wire as the decoder before it.
@Suite struct OSCMutationTests {

    static let messages: [OSCMessage] = [
        OSCMessage("/light", .float(0.8), .int(3), .string("on"), .bool(true)),
        OSCMessage("/every", .int(-42), .float(0.5), .string("héllo wörld"), .blob(Data([1, 2, 3, 4, 5])),
                   .double(1e10), .int64(-7), .bool(false), .null, .impulse,
                   .color(Color(red: 1, green: 0.5, blue: 0, alpha: 1))),
        OSCMessage("/"),
    ]

    static func packetSeeds() -> [[UInt8]] {
        var seeds = messages.map { [UInt8]($0.encode()) }
        let inner = OSCBundle(.immediate, [.message(messages[1])])
        let bundle = OSCBundle(OSCTimeTag(raw: 0x1234_5678_9ABC_DEF0),
                               [.message(messages[0]), .bundle(inner), .message(messages[2])])
        seeds.append([UInt8](bundle.encode()))
        return seeds
    }

    static func tuioSeeds() -> [[UInt8]] {
        let frame: [OSCMessage] = [
            OSCMessage("/tuio/2Dcur", .string("source"), .string("Probe@10.0.0.1")),
            OSCMessage("/tuio/2Dcur", .string("set"), .int(12), .float(0.5), .float(0.25), .float(0), .float(0.1), .float(0.02)),
            OSCMessage("/tuio/2Dcur", .string("set"), .int(13), .float(0.75), .float(0.5)),
            OSCMessage("/tuio/2Dcur", .string("alive"), .int(12), .int(13)),
            OSCMessage("/tuio/2Dcur", .string("fseq"), .int(4218)),
            OSCMessage("/tuio/2Dobj", .string("set"), .int(3), .int(7), .float(0.5), .float(0.5), .float(1.2),
                       .float(0), .float(0), .float(0), .float(0), .float(0)),
            OSCMessage("/tuio/2Dobj", .string("alive"), .int(3)),
            OSCMessage("/tuio/2Dobj", .string("fseq"), .int(4218)),
            OSCMessage("/tuio/2Dblb", .string("set"), .int(5), .float(0.2), .float(0.3), .float(0.1),
                       .float(0.05), .float(0.08), .float(0.004)),
            OSCMessage("/tuio/2Dblb", .string("alive"), .int(5)),
            OSCMessage("/tuio/2Dblb", .string("fseq"), .int(4219)),
        ]
        var seeds = frame.map { [UInt8]($0.encode()) }
        seeds.append([UInt8](OSCBundle(.immediate, messages: Array(frame[1...4])).encode()))
        return seeds
    }

    /// Every argument, every way a sketch reads one.
    static func read(_ packet: OSCPacket) {
        switch packet {
        case .message(let message):
            for argument in message.arguments {
                _ = argument.number
                _ = argument.int
                _ = argument.text
                _ = argument.bool
                _ = argument.color
            }
        case .bundle(let bundle):
            bundle.elements.forEach(read)
        }
    }

    @Test func packetsAndBundles() {
        let report = MutationRun.run("osc-packet", seeds: Self.packetSeeds(), count: 600) { bytes in
            guard let packet = OSCPacket(data: Data(bytes)) else { return false }
            Self.read(packet)
            _ = packet.encode()
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.decoded > 0)
    }

    @Test func aTangibleSurface() {
        let surface = TUIOReceiver(port: 0)   // never started; fed by hand
        let frame = Rectangle(x: 0, y: 0, width: 1080, height: 1080)
        let report = MutationRun.run("tuio", seeds: Self.tuioSeeds(), count: 500) { bytes in
            guard let packet = OSCPacket(data: Data(bytes)) else { return false }
            surface.receive(packet)
            for touch in surface.cursors { _ = touch.position(in: frame) }
            for piece in surface.objects { _ = piece.position(in: frame) }
            for blob in surface.blobs { _ = blob.bounds(in: frame) }
            _ = surface.framesReceived
            _ = surface.sourceName
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    static let leaves: [OSCQueryWire.Leaf] = [
        .slider, .stepper, .toggle, .menu(["Dawn", "Dusk", "Noir"]), .color, .swatch(1),
        .vector, .vector3, .rectangle, .insets, .range, .text,
    ]

    @Test func aMessageReadAgainstEveryLeaf() {
        let report = MutationRun.run("oscquery-message", seeds: Self.packetSeeds() + Self.tuioSeeds(), count: 400) { bytes in
            guard case .message(let message)? = OSCPacket(data: Data(bytes)) else { return false }
            for leaf in Self.leaves { _ = OSCQueryWire.payload(message.arguments, for: leaf) }
            return true
        }
        #expect(report.decoded > 0, "\(report)")
    }

    @Test func aRequestAgainstTheNamespace() {
        let radius = OSCQueryNode(fullPath: "/shape/radius", type: "f", access: 3, description: "Radius",
                                  value: [.number(120)], range: [OSCQueryRange(min: 20, max: 400)])
        let shape = OSCQueryNode(fullPath: "/shape", contents: ["radius": radius])
        let root = OSCQueryNode(fullPath: "/", contents: ["shape": shape])
        let info = OSCQueryHostInfo(name: "Probe", extensions: ["VALUE": true, "RANGE": true], oscPort: 9000)
        let requests = [
            "GET /?HOST_INFO HTTP/1.1\r\nHost: mac.local:8080\r\nAccept: application/json\r\n\r\n",
            "GET /shape/radius?VALUE HTTP/1.1\r\nAccept: */*\r\n\r\n",
            "GET /%73hape/radius?RANGE HTTP/1.1\r\n\r\n",
            "GET / HTTP/1.1\r\nConnection: close\r\n\r\n",
            "POST /shape HTTP/1.1\r\nContent-Length: 2\r\n\r\n{}",
        ]
        let report = MutationRun.run("oscquery-request", seeds: requests.map { Array($0.utf8) }, count: 400) { bytes in
            guard let (head, consumed) = HTTPRequestHead.parse(bytes) else { return false }
            _ = consumed
            let response = OSCQueryWire.response(to: head.path, root: root, hostInfo: info)
            _ = OSCQueryWire.httpBytes(response)
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    /// The values the message route can hand a control, applied to a real
    /// sketch's parameters. A stepper and a menu narrow a number to an index,
    /// and the numbers here are the ones that narrowing is wrong at.
    @MainActor @Test func extremeValuesAppliedToEveryControl() {
        let sketch = OSCProbeSketch()
        let values: [ParamStored] = [
            .number(.nan), .number(.infinity), .number(-.infinity), .number(1e300), .number(-1e300),
            .number(9.3e18), .number(-9.3e18), .number(4_294_967_296), .number(-0.0), .number(2.5),
        ]
        for handle in sketch.parameters() {
            for value in values {
                OSCQueryWire.apply(value, to: handle, leaf: .slider)
                OSCQueryWire.apply(value, to: handle, leaf: .swatch(0))
            }
        }
        for argument in [OSCArgument.float(.nan), .float(.infinity), .double(1e300), .double(-.infinity), .int64(.max)] {
            for leaf in Self.leaves {
                if let payload = OSCQueryWire.payload([argument], for: leaf) {
                    for handle in sketch.parameters() { OSCQueryWire.apply(payload, to: handle, leaf: leaf) }
                }
            }
        }
        #expect(sketch.count >= 1 && sketch.count <= 12)
    }
}

private final class OSCProbeSketch: Sketch {
    enum Mood: String, CaseIterable, ParamOption { case dawn, dusk, noir }
    @Param(20...400) var radius = 120.0
    @Param(1...12) var count = 6
    @Param var spin = true
    @Param var mood = Mood.dusk
    @Param(count: 1...8) var inks = Palette(.red, .white, .black)
}
