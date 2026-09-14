import Foundation
import Testing
import Ollin
@testable import OllinOSC

// The namespace, the wire, and the apply path, socket-free: the tree built
// from a real sketch's parameters, one HTTP request answered as bytes, and
// messages handed to the server the way the receiver would hand them. The one
// test that opens a port sends UDP over loopback, as the OSC suite already
// does; the TCP side is pure functions and is never bound here.

/// A sketch wearing one parameter of each family the namespace carries.
private final class QueryProbeSketch: Sketch {
    enum Mood: String, CaseIterable, ParamOption { case dawn, dusk, noir }

    @Param(20...400) var radius = 120.0
    @Param(1...12) var count = 6
    @Param var spin = true
    @Param var mood = Mood.dusk
    @Param var tint = Color(red: 1, green: 0.2, blue: 0, alpha: 1)
    @Param(x: 0...1, y: 0...1, style: .pad, group: "Field") var focus = Vector2(0.5, 0.5)
    @Param(x: -1...1, y: -1...1, z: -1...1, group: "Field") var wind = Vector3(0, 0, 0)
    @Param(in: 0...1, group: "Look & Feel") var fade = 0.2...0.8
    @Param(group: "Look & Feel") var caption = "hello"
    @Param(count: 1...8, group: "Look & Feel") var inks = Palette(.red, .white, .black)
}

@MainActor @Suite struct OSCQueryTests {

    private func served() -> (sketch: QueryProbeSketch, server: OSCQueryServer) {
        let sketch = QueryProbeSketch()
        let server = OSCQueryServer(port: 0, name: "Probe")
        server.advertises = false
        server.discover(sketch)
        return (sketch, server)
    }

    // MARK: The namespace

    @Test func everyParameterHasANodeWithItsTypeValueAndRange() throws {
        let (_, server) = served()
        let root = server.namespace()
        #expect(root.fullPath == "/")
        #expect(root.description == "Probe")

        let radius = try #require(root.node(at: "/radius"))
        #expect(radius.type == "f")
        #expect(radius.access == 3)
        #expect(radius.value == [.number(120)])
        #expect(radius.range == [OSCQueryRange(min: 20, max: 400)])
        #expect(radius.description == "Radius")

        let count = try #require(root.node(at: "/count"))
        #expect(count.type == "i")
        #expect(count.value == [.number(6)])
        #expect(count.range == [OSCQueryRange(min: 1, max: 12)])

        let spin = try #require(root.node(at: "/spin"))
        #expect(spin.type == "T")
        #expect(spin.value == [.bool(true)])

        let mood = try #require(root.node(at: "/mood"))
        #expect(mood.type == "s")
        #expect(mood.value == [.text("Dusk")])
        #expect(mood.range == [OSCQueryRange(values: ["Dawn", "Dusk", "Noir"])])

        let tint = try #require(root.node(at: "/tint"))
        #expect(tint.type == "r")
        #expect(tint.value == [.text("#FF3300FF")])

        let focus = try #require(root.node(at: "/Field/focus"))
        #expect(focus.type == "ff")
        #expect(focus.value == [.number(0.5), .number(0.5)])
        #expect(focus.range == [OSCQueryRange(min: 0, max: 1), OSCQueryRange(min: 0, max: 1)])

        let wind = try #require(root.node(at: "/Field/wind"))
        #expect(wind.type == "fff")
        #expect(wind.range?.count == 3)

        let fade = try #require(root.node(at: "/Look_Feel/fade"))
        #expect(fade.type == "ff")
        #expect(fade.value == [.number(0.2), .number(0.8)])

        let caption = try #require(root.node(at: "/Look_Feel/caption"))
        #expect(caption.type == "s")
        #expect(caption.value == [.text("hello")])
        #expect(caption.range == nil)
    }

    @Test func aGroupIsAContainerNamedAfterIt() throws {
        let (_, server) = served()
        let root = server.namespace()
        let field = try #require(root.node(at: "/Field"))
        #expect(field.isContainer)
        #expect(field.access == 0)
        #expect(field.type == nil)
        #expect(field.description == "Field")
        #expect(Set(field.contents?.keys.map { $0 } ?? []) == ["focus", "wind"])
        // A name with characters an address cannot carry is spelled with one
        // underscore in their place, and the container still says the real one.
        let look = try #require(root.node(at: "/Look_Feel"))
        #expect(look.description == "Look & Feel")
        #expect(OSCQueryWire.containerName("Look & Feel") == "Look_Feel")
        #expect(OSCQueryWire.containerName("a/b c") == "a_b_c")
        #expect(OSCQueryWire.containerName("   ") == "group")
    }

    @Test func aStripOfColorsIsAContainerOfColorMethods() throws {
        let (_, server) = served()
        let inks = try #require(server.namespace().node(at: "/Look_Feel/inks"))
        #expect(inks.isContainer)
        #expect(inks.description == "Inks, 3 colors")
        let first = try #require(inks.node(at: "0"))
        #expect(first.type == "r")
        #expect(first.access == 3)
        #expect(first.value == [.text("#FF0000FF")])
        #expect(first.fullPath == "/Look_Feel/inks/0")
        #expect(inks.methods.count == 3)
    }

    @Test func theTreeSpellsTheProtocolsAttributeNames() throws {
        let (_, server) = served()
        let response = OSCQueryWire.response(to: "/radius", root: server.namespace(),
                                             hostInfo: OSCQueryHostInfo(name: "Probe", extensions: [:], oscPort: 9000))
        let text = String(decoding: try #require(response.body), as: UTF8.self)
        #expect(text == #"{"ACCESS":3,"DESCRIPTION":"Radius","FULL_PATH":"/radius","RANGE":[{"MAX":400,"MIN":20}],"TYPE":"f","VALUE":[120]}"#)
        // And it reads back into the same model.
        let decoded = try JSONDecoder().decode(OSCQueryNode.self, from: try #require(response.body))
        #expect(decoded == server.namespace().node(at: "/radius"))
    }

    // MARK: Answering requests

    private var hostInfo: OSCQueryHostInfo {
        OSCQueryHostInfo(name: "Probe", extensions: OSCQueryWire.extensions, oscPort: 9000)
    }

    @Test func theRootAnswersWithTheWholeTree() throws {
        let (_, server) = served()
        let response = OSCQueryWire.response(to: "/", root: server.namespace(), hostInfo: hostInfo)
        #expect(response.status == 200)
        let root = try JSONDecoder().decode(OSCQueryNode.self, from: try #require(response.body))
        #expect(root.node(at: "/Field/focus")?.type == "ff")
        // A container answers with its subtree only.
        let field = OSCQueryWire.response(to: "/Field", root: server.namespace(), hostInfo: hostInfo)
        let subtree = try JSONDecoder().decode(OSCQueryNode.self, from: try #require(field.body))
        #expect(subtree.fullPath == "/Field")
        #expect(subtree.node(at: "/radius") == nil)
    }

    @Test func oneAttributeAnswersAlone() throws {
        let (_, server) = served()
        let root = server.namespace()
        let value = OSCQueryWire.response(to: "/count?VALUE", root: root, hostInfo: hostInfo)
        #expect(value.status == 200)
        #expect(String(decoding: try #require(value.body), as: UTF8.self) == #"{"VALUE":[6]}"#)
        let type = OSCQueryWire.response(to: "/count?type", root: root, hostInfo: hostInfo)
        #expect(String(decoding: try #require(type.body), as: UTF8.self) == #"{"TYPE":"i"}"#)
        let range = OSCQueryWire.response(to: "/mood?RANGE", root: root, hostInfo: hostInfo)
        #expect(String(decoding: try #require(range.body), as: UTF8.self) == #"{"RANGE":[{"VALS":["Dawn","Dusk","Noir"]}]}"#)
    }

    @Test func theStatusCodesFollowTheProtocol() {
        let (_, server) = served()
        let root = server.namespace()
        #expect(OSCQueryWire.response(to: "/nope", root: root, hostInfo: hostInfo).status == 404)
        #expect(OSCQueryWire.response(to: "/Field/nope?VALUE", root: root, hostInfo: hostInfo).status == 404)
        // An attribute the node does not carry: no content.
        let missing = OSCQueryWire.response(to: "/Look_Feel/caption?RANGE", root: root, hostInfo: hostInfo)
        #expect(missing.status == 204)
        #expect(missing.body == nil)
        // An attribute the server does not speak: a bad request.
        #expect(OSCQueryWire.response(to: "/radius?TAGS", root: root, hostInfo: hostInfo).status == 400)
        #expect(OSCQueryWire.response(to: "/radius?listen", root: root, hostInfo: hostInfo).status == 400)
        // A trailing slash and a percent-encoded path both land.
        #expect(OSCQueryWire.response(to: "/Field/", root: root, hostInfo: hostInfo).status == 200)
        #expect(OSCQueryWire.response(to: "/Look%5FFeel/fade", root: root, hostInfo: hostInfo).status == 200)
    }

    @Test func hostInfoSaysWhoServesAndWhereMessagesGo() throws {
        let (_, server) = served()
        let response = OSCQueryWire.response(to: "/?HOST_INFO", root: server.namespace(), hostInfo: hostInfo)
        #expect(response.status == 200)
        let info = try JSONDecoder().decode(OSCQueryHostInfo.self, from: try #require(response.body))
        #expect(info.name == "Probe")
        #expect(info.oscPort == 9000)
        #expect(info.oscTransport == "UDP")
        #expect(info.extensions["VALUE"] == true)
        #expect(info.extensions["RANGE"] == true)
        #expect(info.extensions["LISTEN"] == false)
        let text = String(decoding: try #require(response.body), as: UTF8.self)
        #expect(text.contains(#""OSC_PORT":9000"#))
        #expect(text.contains(#""OSC_TRANSPORT":"UDP""#))
    }

    @Test func theResponseIsWholeHTTP() throws {
        let body = Data(#"{"VALUE":[6]}"#.utf8)
        let bytes = OSCQueryWire.httpBytes(OSCQueryWire.Response(status: 200, body: body))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json; charset=utf-8\r\n"))
        #expect(text.contains("Content-Length: \(body.count)\r\n"))
        #expect(text.contains("Access-Control-Allow-Origin: *\r\n"))
        #expect(text.contains("Connection: close\r\n\r\n"))
        #expect(text.hasSuffix(#"{"VALUE":[6]}"#))
        let empty = String(decoding: OSCQueryWire.httpBytes(OSCQueryWire.Response(status: 204, body: nil)), as: UTF8.self)
        #expect(empty.hasPrefix("HTTP/1.1 204 No Content\r\n"))
        #expect(empty.contains("Content-Length: 0\r\n"))
    }

    // MARK: Reading a message

    @Test func aMessageIsReadAgainstWhatTheLeafTakes() {
        #expect(OSCQueryWire.payload([.float(200)], for: .slider) == .number(200))
        #expect(OSCQueryWire.payload([.int(200)], for: .slider) == .number(200))
        #expect(OSCQueryWire.payload([.string("no")], for: .slider) == nil)
        #expect(OSCQueryWire.payload([.float(4.6)], for: .stepper) == .number(5))
        #expect(OSCQueryWire.payload([.bool(false)], for: .toggle) == .boolean(false))
        #expect(OSCQueryWire.payload([.int(1)], for: .toggle) == .boolean(true))
        #expect(OSCQueryWire.payload([.string("Noir")], for: .menu(["Dawn", "Dusk", "Noir"])) == .number(2))
        #expect(OSCQueryWire.payload([.int(1)], for: .menu(["Dawn", "Dusk", "Noir"])) == .number(1))
        #expect(OSCQueryWire.payload([.string("Storm")], for: .menu(["Dawn", "Dusk", "Noir"])) == nil)
        #expect(OSCQueryWire.payload([.color(Color(red: 0, green: 1, blue: 0, alpha: 1))], for: .color)
                == .color(red: 0, green: 1, blue: 0, alpha: 1))
        #expect(OSCQueryWire.payload([.string("#00FF00")], for: .color) == .color(red: 0, green: 1, blue: 0, alpha: 1))
        #expect(OSCQueryWire.payload([.string("00FF0080")], for: .color)
                == .color(red: 0, green: 1, blue: 0, alpha: 128.0 / 255))
        #expect(OSCQueryWire.payload([.string("#12345")], for: .color) == nil)
        #expect(OSCQueryWire.payload([.float(0.25), .float(0.75)], for: .vector) == .vector(x: 0.25, y: 0.75))
        #expect(OSCQueryWire.payload([.float(0.25)], for: .vector) == nil)
        #expect(OSCQueryWire.payload([.float(1), .float(2), .float(3)], for: .vector3) == .vector3(x: 1, y: 2, z: 3))
        #expect(OSCQueryWire.payload([.float(1), .float(2), .float(3), .float(4)], for: .rectangle)
                == .rectangle(x: 1, y: 2, width: 3, height: 4))
        #expect(OSCQueryWire.payload([.float(1), .float(2), .float(3), .float(4)], for: .insets)
                == .insets(top: 1, right: 2, bottom: 3, left: 4))
        // A range arrives in either order and is kept the right way round.
        #expect(OSCQueryWire.payload([.float(0.75), .float(0.25)], for: .range) == .range(lower: 0.25, upper: 0.75))
        #expect(OSCQueryWire.payload([.string("hi")], for: .text) == .text("hi"))
        #expect(OSCQueryWire.payload([.color(Color.black)], for: .swatch(1)) == .color(red: 0, green: 0, blue: 0, alpha: 1))
    }

    // MARK: The apply path, end to end without a socket

    @Test func messagesLandOnTheNextBeforeDraw() {
        let (sketch, server) = served()
        server.receive(OSCMessage("/radius", .float(200)))
        server.receive(OSCMessage("/count", .int(9)))
        server.receive(OSCMessage("/spin", .bool(false)))
        server.receive(OSCMessage("/mood", .string("Noir")))
        server.receive(OSCMessage("/tint", .color(Color(red: 0, green: 0, blue: 1, alpha: 1))))
        server.receive(OSCMessage("/Field/focus", .float(0.25), .float(0.75)))
        server.receive(OSCMessage("/Field/wind", .float(0.5), .float(-0.5), .float(1)))
        server.receive(OSCMessage("/Look_Feel/fade", .float(0.25), .float(0.5)))
        server.receive(OSCMessage("/Look_Feel/caption", .string("moved")))
        server.receive(OSCMessage("/Look_Feel/inks/1", .color(Color(red: 0, green: 1, blue: 0, alpha: 1))))
        #expect(sketch.radius == 120)   // nothing lands until the frame boundary

        server.beforeDraw(sketch)
        #expect(sketch.radius == 200)
        #expect(sketch.count == 9)
        #expect(sketch.spin == false)
        #expect(sketch.mood == .noir)
        #expect(sketch.tint == Color(red: 0, green: 0, blue: 1, alpha: 1))
        #expect(sketch.focus == Vector2(0.25, 0.75))
        #expect(sketch.wind == Vector3(0.5, -0.5, 1))
        #expect(sketch.fade == 0.25...0.5)
        #expect(sketch.caption == "moved")
        #expect(sketch.inks.colors.count == 3)
        #expect(sketch.inks.colors[1] == Color(red: 0, green: 1, blue: 0, alpha: 1))
        #expect(sketch.inks.colors[0] == .red)
    }

    @Test func aValueOutsideTheRangeIsClampedAndAWrongKindIsIgnored() {
        let (sketch, server) = served()
        server.receive(OSCMessage("/radius", .float(1000)))
        server.receive(OSCMessage("/count", .string("nine")))
        server.receive(OSCMessage("/nowhere", .float(1)))
        server.receive(OSCMessage("/Field/focus", .float(0.5)))   // one number short
        server.beforeDraw(sketch)
        #expect(sketch.radius == 400)
        #expect(sketch.count == 6)
        #expect(sketch.focus == Vector2(0.5, 0.5))
    }

    @Test func theTreeFollowsTheValuesWhenRebuilt() {
        let (sketch, server) = served()
        sketch.radius = 300
        sketch.mood = .dawn
        #expect(server.namespace().node(at: "/radius")?.value == [.number(120)])
        server.discover(sketch)   // what the frame tick does every quarter second
        #expect(server.namespace().node(at: "/radius")?.value == [.number(300)])
        #expect(server.namespace().node(at: "/mood")?.value == [.text("Dawn")])
    }

    // MARK: Over the wire

    struct Timeout: Error {}

    /// Polls `probe` until it returns a value or the timeout elapses; the probe
    /// runs before the clock is read, so a late wakeup still sees an answer
    /// that already arrived.
    func waitFor<T>(timeout: Double = 3.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    @Test func aDatagramOverLoopbackSetsTheParameter() async throws {
        let sketch = QueryProbeSketch()
        let server = OSCQueryServer(port: 0, name: "Probe")
        server.advertises = false
        server.setup(sketch)
        defer { server.stop() }

        let port = try await waitFor { server.receiver.boundPort }
        let sender = OSCSender(host: "127.0.0.1", port: port)
        defer { sender.close() }
        // Resend until one lands: the first datagram on a fresh UDP flow can be lost.
        _ = try await waitFor {
            sender.send("/radius", .float(250))
            server.beforeDraw(sketch)
            return sketch.radius == 250 ? true : nil
        }
        #expect(sketch.radius == 250)
        // The HTTP side reports its port too, without being asked anything.
        _ = try await waitFor { server.boundPort }
        #expect(server.url?.hasPrefix("http://") == true)
    }
}
