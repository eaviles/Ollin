import Foundation
import Ollin
import Testing
@testable import OllinRemote

// Socket-free on purpose: every test here exercises the wire layer as pure
// functions (bytes in, bytes out) or the apply path through a real sketch's
// discovered knobs. Nothing opens a port; the connection plumbing is thin
// glue over these pieces.

/// A sketch wearing one knob of each family the wire carries.
private final class RemoteProbeSketch: Sketch {
    enum Palette: String, CaseIterable, ParamOption { case dawn, dusk, noir }

    @Param(0.1...4.0) var speed = 1.4
    @Param(1...12) var layers = 6
    @Param var trails = true
    @Param var palette = Palette.dusk
    @Param var accent = Color.purple
    @Param(x: 0...1, y: 0...1, style: .pad) var focus = Vector2(0.5, 0.5)
    // Module-qualified: the nested option enum above owns the bare name here.
    @Param(count: 1...8) var inks = Ollin.Palette(.red, .white, .black)
    @Param var fade = Ramp([.black, .white])
}

@MainActor @Suite struct RemoteWireTests {

    // MARK: Handshake

    @Test func theHandshakeAcceptKeyMatchesTheProtocolVector() {
        // The worked example in the WebSocket specification (RFC 6455 §1.3).
        let accept = RemoteHTTP.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ==")
        #expect(accept == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    @Test func aRequestHeadParsesAndCountsItsBytes() throws {
        let head = "GET /ws HTTP/1.1\r\nHost: mac.local:9330\r\n"
            + "Upgrade: WebSocket\r\nConnection: Upgrade\r\n"
            + "Sec-WebSocket-Key: abc123==\r\n\r\n"
        var bytes = [UInt8](head.utf8)
        let trailing: [UInt8] = [0x81, 0x00]   // frame bytes already following
        bytes.append(contentsOf: trailing)

        let parsed = try #require(RemoteHTTP.parseHead(bytes))
        #expect(parsed.request.method == "GET")
        #expect(parsed.request.path == "/ws")
        #expect(parsed.request.headers["host"] == "mac.local:9330")
        #expect(parsed.consumed == bytes.count - trailing.count)
        #expect(RemoteHTTP.isWebSocketUpgrade(parsed.request))
    }

    @Test func anIncompleteHeadWaitsForMoreBytes() {
        let partial = [UInt8]("GET / HTTP/1.1\r\nHost: x".utf8)
        #expect(RemoteHTTP.parseHead(partial) == nil)
    }

    @Test func aPlainPageRequestIsNotAnUpgrade() throws {
        let head = "GET / HTTP/1.1\r\nHost: mac.local\r\nAccept: text/html\r\n\r\n"
        let parsed = try #require(RemoteHTTP.parseHead([UInt8](head.utf8)))
        #expect(!RemoteHTTP.isWebSocketUpgrade(parsed.request))
    }

    // MARK: Frames

    @Test func aServerFrameRoundTripsThroughTheCodec() throws {
        var buffer = [UInt8](WebSocketFraming.encodeText("hello"))
        let frames = try #require(WebSocketFraming.decode(buffer: &buffer))
        #expect(frames.count == 1)
        #expect(frames[0].fin)
        #expect(frames[0].opcode == .text)
        #expect(String(bytes: frames[0].payload, encoding: .utf8) == "hello")
        #expect(buffer.isEmpty)
    }

    @Test func aMaskedClientFrameUnmasks() throws {
        let payload = [UInt8]("{\"kind\":\"set\"}".utf8)
        let mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        var bytes: [UInt8] = [0x81, 0x80 | UInt8(payload.count)]
        bytes.append(contentsOf: mask)
        for (i, byte) in payload.enumerated() { bytes.append(byte ^ mask[i % 4]) }

        var buffer = bytes
        let frames = try #require(WebSocketFraming.decode(buffer: &buffer))
        #expect(frames.count == 1)
        #expect(frames[0].payload == payload)
    }

    @Test func aFrameSplitAcrossReadsWaitsThenCompletes() throws {
        let whole = [UInt8](WebSocketFraming.encodeText("split across two reads"))
        var buffer = [UInt8](whole[..<5])
        let early = try #require(WebSocketFraming.decode(buffer: &buffer))
        #expect(early.isEmpty)
        #expect(buffer.count == 5)   // the partial frame stays buffered

        buffer.append(contentsOf: whole[5...])
        let frames = try #require(WebSocketFraming.decode(buffer: &buffer))
        #expect(frames.count == 1)
        #expect(String(bytes: frames[0].payload, encoding: .utf8) == "split across two reads")
    }

    @Test func aLongPayloadTakesTheTwoByteLengthPath() throws {
        let text = String(repeating: "x", count: 300)
        let encoded = [UInt8](WebSocketFraming.encodeText(text))
        #expect(encoded[1] == 126)   // the extended-length marker
        var buffer = encoded
        let frames = try #require(WebSocketFraming.decode(buffer: &buffer))
        #expect(frames[0].payload.count == 300)
    }

    @Test func anUnknownOpcodeDropsTheConnection() {
        var buffer: [UInt8] = [0x83, 0x00]   // opcode 0x3 is reserved
        #expect(WebSocketFraming.decode(buffer: &buffer) == nil)
    }

    // MARK: Descriptors

    @Test func descriptorsCarryEachKindsConstraints() throws {
        let sketch = RemoteProbeSketch()
        let byName = Dictionary(uniqueKeysWithValues:
            sketch.parameters().map { ($0.name, RemoteWire.descriptor(for: $0)) })

        let speed = try #require(byName["speed"])
        #expect(speed.kind == .slider)
        #expect(speed.lower == 0.1)
        #expect(speed.upper == 4.0)
        #expect(speed.value == .number(1.4))

        let layers = try #require(byName["layers"])
        #expect(layers.kind == .stepper)
        #expect(layers.value == .number(6))

        #expect(byName["trails"]?.kind == .toggle)
        #expect(byName["accent"]?.kind == .color)

        let palette = try #require(byName["palette"])
        #expect(palette.kind == .menu)
        #expect(palette.options == ["Dawn", "Dusk", "Noir"])
        #expect(palette.value == .number(1))   // by index on the wire

        let focus = try #require(byName["focus"])
        #expect(focus.kind == .vector)
        #expect(focus.isPad == true)
        #expect(focus.xUpper == 1)

        let inks = try #require(byName["inks"])
        #expect(inks.kind == .swatches)
        #expect(inks.isGradient == nil)          // blocks, not a band
        #expect(inks.lower == 1 && inks.upper == 8)

        let fade = try #require(byName["fade"])
        #expect(fade.kind == .swatches)
        #expect(fade.isGradient == true)
    }

    @Test func aStripOfColorsTravelsBothWays() throws {
        let sketch = RemoteProbeSketch()
        let handle = try #require(sketch.parameters().first { $0.name == "inks" })

        // Out: the page reads the colors and their places from the payload.
        let text = String(decoding: try JSONEncoder().encode(RemoteWire.snapshotValue(of: handle)),
                          as: UTF8.self)
        #expect(text.contains(#""stops""#))
        #expect(text.contains(#""position":0.5"#))
        #expect(!text.contains(#""space""#))       // a palette names no space

        // In: the exact JSON shape the page sends after a tap on a chip.
        let stops = #"[{"position":0,"red":0,"green":0,"blue":1,"alpha":1},"#
            + #"{"position":1,"red":0,"green":1,"blue":0,"alpha":1}]"#
        let json = #"{"kind":"set","name":"inks","value":{"colors":{"stops":"#
            + stops + #","space":null}}}"#
        let set = try JSONDecoder().decode(RemoteSet.self, from: Data(json.utf8))
        RemoteWire.apply(set.value, to: handle)
        #expect(sketch.inks.colors == [.blue, .green])

        // The same payload with the space left out reads the same way, so the
        // page may send either shape.
        let bare = #"{"kind":"set","name":"inks","value":{"colors":{"stops":"# + stops + #"}}}"#
        let second = try JSONDecoder().decode(RemoteSet.self, from: Data(bare.utf8))
        #expect(second.value == set.value)
    }

    @Test func aMenuTravelsByIndexBothWays() throws {
        let sketch = RemoteProbeSketch()
        let handle = try #require(sketch.parameters().first { $0.name == "palette" })
        RemoteWire.apply(.number(2), to: handle)
        #expect(sketch.palette == .noir)
        #expect(RemoteWire.snapshotValue(of: handle) == .number(2))
        RemoteWire.apply(.number(99), to: handle)   // out of range, ignored
        #expect(sketch.palette == .noir)
    }

    @Test func applyIgnoresAPayloadOfTheWrongKind() throws {
        let sketch = RemoteProbeSketch()
        let handle = try #require(sketch.parameters().first { $0.name == "speed" })
        RemoteWire.apply(.boolean(true), to: handle)
        #expect(sketch.speed == 1.4)
        RemoteWire.apply(.number(2.5), to: handle)
        #expect(sketch.speed == 2.5)
    }

    // MARK: Messages

    @Test func aSetMessageFromThePageDecodes() throws {
        // The exact JSON shape the page sends.
        let json = #"{"kind":"set","name":"speed","value":{"number":{"_0":2.5}}}"#
        let set = try JSONDecoder().decode(RemoteSet.self, from: Data(json.utf8))
        #expect(set.name == "speed")
        #expect(set.value == .number(2.5))
    }

    @Test func aHelloCarriesTheSketchAndItsKnobs() throws {
        let sketch = RemoteProbeSketch()
        let hello = RemoteHello(sketch: "RemoteProbeSketch", host: "mac.local",
                                params: sketch.parameters().map(RemoteWire.descriptor(for:)))
        let text = String(decoding: try JSONEncoder().encode(hello), as: UTF8.self)
        #expect(text.contains(#""kind":"hello""#))
        #expect(text.contains(#""sketch":"RemoteProbeSketch""#))
        #expect(text.contains(#""name":"speed""#))
    }

    // MARK: The apply path, end to end without a socket

    @Test func queuedValuesApplyOnTheNextBeforeDraw() {
        let sketch = RemoteProbeSketch()
        let remote = RemoteInspector(port: 0)
        remote.discover(sketch)

        remote.enqueue("speed", .number(3.25))
        remote.enqueue("trails", .boolean(false))
        remote.enqueue("focus", .vector(x: 0.25, y: 0.75))
        #expect(sketch.speed == 1.4)   // nothing lands until the frame boundary

        remote.beforeDraw(sketch)
        #expect(sketch.speed == 3.25)
        #expect(sketch.trails == false)
        #expect(sketch.focus == Vector2(0.25, 0.75))
    }
}
