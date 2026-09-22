import Foundation
import Network
import Ollin
import os

// OSCQuery: the sketch's `@Param` parameters published as a namespace a control
// app browses. Three layers, like the remote surface: the namespace model
// (public, plain values), the wire (pure functions over the model, the OSC
// arguments, and the HTTP request line, which is what the tests exercise), and
// the server (an extension on the main actor over a nonisolated engine that
// owns the sockets). Nothing in the first two layers touches the network.

// MARK: - The namespace

/// One node of an OSCQuery namespace: a container of other nodes, or a method
/// (a leaf) with a type, a value, and a range. `OSCQueryServer` builds one per
/// `@Param` and serves the tree as JSON under the attribute names the protocol
/// spells (`FULL_PATH`, `TYPE`, `VALUE`, `RANGE`, `CONTENTS`, ...), which is
/// what a control app reads to build its surface.
public struct OSCQueryNode: Codable, Equatable, Sendable {
    /// The node's full OSC address, `/` for the root.
    public var fullPath: String
    /// The OSC type tags of the value a method takes, one character per
    /// argument (`f`, `i`, `T`, `s`, `r`, `ff`, ...); `nil` on a container.
    public var type: String?
    /// What a client may do: 0 nothing (a container), 1 read, 2 write, 3 both.
    public var access: Int
    /// A human-readable name for the node, the parameter's label.
    public var description: String?
    /// The current value, one item per character of `type`.
    public var value: [OSCQueryValue]?
    /// The bounds of each argument, one item per character of `type`.
    public var range: [OSCQueryRange]?
    /// The nodes below a container, by name; `nil` on a method.
    public var contents: [String: OSCQueryNode]?

    public init(fullPath: String, type: String? = nil, access: Int = 0, description: String? = nil,
                value: [OSCQueryValue]? = nil, range: [OSCQueryRange]? = nil,
                contents: [String: OSCQueryNode]? = nil) {
        self.fullPath = fullPath
        self.type = type
        self.access = access
        self.description = description
        self.value = value
        self.range = range
        self.contents = contents
    }

    enum CodingKeys: String, CodingKey {
        case fullPath = "FULL_PATH"
        case type = "TYPE"
        case access = "ACCESS"
        case description = "DESCRIPTION"
        case value = "VALUE"
        case range = "RANGE"
        case contents = "CONTENTS"
    }

    /// Whether this node holds other nodes rather than a value.
    public var isContainer: Bool { contents != nil }

    /// The node at `path` below this one (`/` is this node), or `nil`.
    public func node(at path: String) -> OSCQueryNode? {
        var current = self
        for name in path.split(separator: "/", omittingEmptySubsequences: true) {
            guard let next = current.contents?[String(name)] else { return nil }
            current = next
        }
        return current
    }

    /// Every method below this node, in address order.
    public var methods: [OSCQueryNode] {
        guard let contents else { return [self] }
        return contents.keys.sorted().flatMap { contents[$0]!.methods }
    }
}

/// One item of a node's `VALUE`: a number for the numeric tags, a string for
/// `s` (and for `r`, the color as `#RRGGBBAA`), a Boolean for `T`/`F`, or null.
public enum OSCQueryValue: Codable, Equatable, Sendable {
    case number(Double)
    case text(String)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number(let number): try container.encode(number)
        case .text(let text): try container.encode(text)
        case .bool(let flag): try container.encode(flag)
        case .null: try container.encodeNil()
        }
    }
}

/// The bounds of one argument: a numeric `min`/`max`, or the only `values` the
/// method accepts (a menu's options).
public struct OSCQueryRange: Codable, Equatable, Sendable {
    public var min: Double?
    public var max: Double?
    public var values: [String]?

    public init(min: Double? = nil, max: Double? = nil, values: [String]? = nil) {
        self.min = min
        self.max = max
        self.values = values
    }

    enum CodingKeys: String, CodingKey {
        case min = "MIN"
        case max = "MAX"
        case values = "VALS"
    }
}

/// What `?HOST_INFO` answers: who is serving, which optional attributes the
/// server speaks, and where OSC messages go.
public struct OSCQueryHostInfo: Codable, Equatable, Sendable {
    public var name: String
    public var extensions: [String: Bool]
    public var oscPort: Int?
    public var oscTransport: String

    public init(name: String, extensions: [String: Bool], oscPort: Int?, oscTransport: String = "UDP") {
        self.name = name
        self.extensions = extensions
        self.oscPort = oscPort
        self.oscTransport = oscTransport
    }

    enum CodingKeys: String, CodingKey {
        case name = "NAME"
        case extensions = "EXTENSIONS"
        case oscPort = "OSC_PORT"
        case oscTransport = "OSC_TRANSPORT"
    }
}

// MARK: - The wire

/// The protocol layer, kept free of sockets on purpose: the namespace built from
/// a sketch's parameters, an OSC message read against a leaf, a value written
/// through a parameter's own control, and the answer to one HTTP request.
enum OSCQueryWire {

    /// What a leaf takes, kept beside its address so an incoming message can be
    /// read on the network queue without touching the parameter.
    enum Leaf: Equatable, Sendable {
        case slider, stepper, toggle, menu([String]), color
        case vector, vector3, rectangle, insets, range, text
        /// One color of a palette or ramp, by its position in the strip.
        case swatch(Int)
    }

    /// Where an address leads: the parameter, and what the leaf takes.
    struct Route: Equatable, Sendable {
        let name: String
        let leaf: Leaf
    }

    /// The attributes every leaf carries, spelled the way `HOST_INFO` lists them.
    static let extensions: [String: Bool] = [
        "ACCESS": true, "VALUE": true, "RANGE": true, "DESCRIPTION": true,
        "TAGS": false, "EXTENDED_TYPE": false, "UNIT": false, "CRITICAL": false,
        "CLIPMODE": false, "LISTEN": false, "PATH_CHANGED": false, "PATH_RENAMED": false,
        "PATH_ADDED": false, "PATH_REMOVED": false, "HTML": false, "ECHO": false,
    ]

    // MARK: Building the namespace

    /// The whole tree for a sketch's parameters: ungrouped parameters at the
    /// root, each group a container named after it, plus every address's route.
    static func namespace(for handles: [ParamHandle], sketchName: String)
        -> (root: OSCQueryNode, routes: [String: Route]) {
        var root = OSCQueryNode(fullPath: "/", description: sketchName, contents: [:])
        var routes: [String: Route] = [:]
        for handle in handles {
            let container = handle.group.map(containerName)
            let path = "/" + (container.map { $0 + "/" } ?? "") + handle.name
            let (node, leafRoutes) = leaf(for: handle, at: path)
            routes.merge(leafRoutes) { _, new in new }
            if let container, let group = handle.group {
                var folder = root.contents?[container]
                    ?? OSCQueryNode(fullPath: "/" + container, description: group, contents: [:])
                folder.contents?[handle.name] = node
                root.contents?[container] = folder
            } else {
                root.contents?[handle.name] = node
            }
        }
        return (root, routes)
    }

    /// A group name as an address segment: letters, digits, `_`, `-`, and `.`
    /// survive, anything else (a space, the characters OSC reserves) becomes
    /// one underscore.
    static func containerName(_ group: String) -> String {
        var out = ""
        var pendingUnderscore = false
        for scalar in group.unicodeScalars {
            let keeps = CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" || scalar == "."
            if keeps {
                if pendingUnderscore { out.append("_"); pendingUnderscore = false }
                out.unicodeScalars.append(scalar)
            } else if !out.isEmpty {
                pendingUnderscore = true
            }
        }
        return out.isEmpty ? "group" : out
    }

    /// The node for one parameter, read through its control, plus the route of
    /// every address it answers to (one, or one per color for a swatch strip).
    static func leaf(for handle: ParamHandle, at path: String) -> (OSCQueryNode, [String: Route]) {
        var node = OSCQueryNode(fullPath: path, access: 3, description: handle.label)
        var routes: [String: Route] = [:]
        func route(_ leaf: Leaf, at address: String) {
            routes[address] = Route(name: handle.name, leaf: leaf)
        }
        func span(_ range: ClosedRange<Double>) -> OSCQueryRange {
            OSCQueryRange(min: range.lowerBound, max: range.upperBound)
        }
        switch handle.control {
        case .slider(let s):
            node.type = "f"
            node.value = [.number(s.read())]
            node.range = [span(s.range)]
            route(.slider, at: path)
        case .stepper(let s):
            node.type = "i"
            node.value = [.number(Double(s.read()))]
            node.range = [OSCQueryRange(min: Double(s.range.lowerBound), max: Double(s.range.upperBound))]
            route(.stepper, at: path)
        case .toggle(let t):
            node.type = "T"
            node.value = [.bool(t.read())]
            route(.toggle, at: path)
        case .menu(let m):
            node.type = "s"
            let index = m.read()
            node.value = [.text(m.options.indices.contains(index) ? m.options[index] : "")]
            node.range = [OSCQueryRange(values: m.options)]
            route(.menu(m.options), at: path)
        case .colorWell(let c):
            node.type = "r"
            node.value = [.text(hex(c.read()))]
            route(.color, at: path)
        case .vector(let v):
            node.type = "ff"
            let value = v.read()
            node.value = [.number(value.x), .number(value.y)]
            node.range = [span(v.xRange), span(v.yRange)]
            route(.vector, at: path)
        case .vector3(let v):
            node.type = "fff"
            let value = v.read()
            node.value = [.number(value.x), .number(value.y), .number(value.z)]
            node.range = [span(v.xRange), span(v.yRange), span(v.zRange)]
            route(.vector3, at: path)
        case .rectangle(let r):
            node.type = "ffff"
            let value = r.read()
            node.value = [.number(value.x), .number(value.y), .number(value.width), .number(value.height)]
            node.range = [span(r.xRange), span(r.yRange), span(r.widthRange), span(r.heightRange)]
            route(.rectangle, at: path)
        case .insets(let i):
            node.type = "ffff"
            let value = i.read()
            node.value = [.number(value.top), .number(value.right), .number(value.bottom), .number(value.left)]
            node.range = Array(repeating: span(i.edgeRange), count: 4)
            route(.insets, at: path)
        case .range(let r):
            node.type = "ff"
            let value = r.read()
            node.value = [.number(value.lowerBound), .number(value.upperBound)]
            node.range = [span(r.outer), span(r.outer)]
            route(.range, at: path)
        case .text(let t):
            node.type = "s"
            node.value = [.text(t.read())]
            route(.text, at: path)
        case .swatches(let s):
            // A strip is a container of its colors, one method each, so a
            // client that knows nothing about palettes still gets color wells.
            let stops = s.read()
            node.access = 0
            node.description = "\(handle.label), \(stops.count) colors"
            var colors: [String: OSCQueryNode] = [:]
            for (index, stop) in stops.enumerated() {
                let address = path + "/\(index)"
                colors["\(index)"] = OSCQueryNode(fullPath: address, type: "r", access: 3,
                                                  description: "\(handle.label) \(index + 1)",
                                                  value: [.text(hex(stop.color))])
                route(.swatch(index), at: address)
            }
            node.contents = colors
        }
        return (node, routes)
    }

    // MARK: Colors on the wire

    /// A color as the `#RRGGBBAA` string the `r` type reads as in JSON.
    static func hex(_ color: Color) -> String {
        func byte(_ component: Double) -> Int { Int(Swift.min(255, Swift.max(0, (component * 255).rounded()))) }
        return String(format: "#%02X%02X%02X%02X", byte(color.red), byte(color.green), byte(color.blue), byte(color.alpha))
    }

    /// A color from `#RRGGBB` or `#RRGGBBAA` (the `#` optional), or `nil`.
    static func color(fromHex text: String) -> Color? {
        var digits = Substring(text)
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        guard digits.count == 6 || digits.count == 8, let packed = UInt32(digits, radix: 16) else { return nil }
        let full = digits.count == 6 ? packed << 8 | 0xFF : packed
        return OSCCoding.unpackColor(full)
    }

    // MARK: Reading a message

    /// The value an incoming message carries for a leaf, in the parameter's own
    /// persisted form, or `nil` when the arguments do not fit. A number is read
    /// across every numeric tag, a menu takes its option's name or its index,
    /// and a color takes the `r` type or a hex string.
    static func payload(_ arguments: [OSCArgument], for leaf: Leaf) -> ParamStored? {
        let numbers = arguments.compactMap(\.number)
        func number(_ index: Int) -> Double? { numbers.indices.contains(index) ? numbers[index] : nil }
        switch leaf {
        case .slider:
            return number(0).map { .number($0) }
        case .stepper:
            return number(0).map { .number($0.rounded()) }
        case .toggle:
            return arguments.first?.bool.map { .boolean($0) }
        case .menu(let options):
            if let name = arguments.first?.text {
                return options.firstIndex(of: name).map { .number(Double($0)) }
            }
            return number(0).map { .number($0.rounded()) }
        case .color, .swatch:
            if let color = arguments.first?.color { return stored(color) }
            return arguments.first?.text.flatMap(color(fromHex:)).map(stored)
        case .vector:
            guard let x = number(0), let y = number(1) else { return nil }
            return .vector(x: x, y: y)
        case .vector3:
            guard let x = number(0), let y = number(1), let z = number(2) else { return nil }
            return .vector3(x: x, y: y, z: z)
        case .rectangle:
            guard let x = number(0), let y = number(1), let w = number(2), let h = number(3) else { return nil }
            return .rectangle(x: x, y: y, width: w, height: h)
        case .insets:
            guard let t = number(0), let r = number(1), let b = number(2), let l = number(3) else { return nil }
            return .insets(top: t, right: r, bottom: b, left: l)
        case .range:
            guard let lower = number(0), let upper = number(1) else { return nil }
            return .range(lower: Swift.min(lower, upper), upper: Swift.max(lower, upper))
        case .text:
            return arguments.first?.text.map { .text($0) }
        }
    }

    private static func stored(_ color: Color) -> ParamStored {
        .color(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    // MARK: Writing a value

    /// Applies one value through the parameter's own control, the path an
    /// inspector drag takes, so smoothing and clamping behave as they do there.
    /// A payload of the wrong kind for the control is ignored.
    static func apply(_ payload: ParamStored, to handle: ParamHandle, leaf: Leaf) {
        switch (handle.control, payload) {
        case (.slider(let s), .number(let v)): s.write(v)
        case (.stepper(let s), .number(let v)):
            // A number that is not finite, or too large to be a step, is not a
            // value for a stepper, and is ignored like a payload of the wrong kind.
            if let i = v.int(rounded: .toNearestOrAwayFromZero) { s.write(i) }
        case (.toggle(let t), .boolean(let v)): t.write(v)
        case (.menu(let m), .number(let index)):
            if let i = index.int(rounded: .toNearestOrAwayFromZero), m.options.indices.contains(i) { m.write(i) }
        case (.colorWell(let c), .color(let r, let g, let b, let a)):
            c.write(Color(red: r, green: g, blue: b, alpha: a))
        case (.vector(let v), .vector(let x, let y)): v.write(Vector2(x, y))
        case (.vector3(let v), .vector3(let x, let y, let z)): v.write(Vector3(x, y, z))
        case (.rectangle(let r), .rectangle(let x, let y, let w, let h)):
            r.write(Rectangle(x: x, y: y, width: w, height: h))
        case (.insets(let i), .insets(let t, let r, let b, let l)):
            i.write(Insets(top: t, right: r, bottom: b, left: l))
        case (.range(let r), .range(let lower, let upper)): r.write(lower...upper)
        case (.text(let t), .text(let v)): t.write(v)
        case (.swatches(let s), .color(let r, let g, let b, let a)):
            guard case .swatch(let index) = leaf else { return }
            var stops = s.read()
            guard stops.indices.contains(index) else { return }
            stops[index].color = Color(red: r, green: g, blue: b, alpha: a)
            s.write(stops)
        default:
            break
        }
    }

    // MARK: Answering a request

    struct Response: Equatable {
        var status: Int
        var body: Data?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// One attribute of a node as its own JSON object, `{"VALUE": [...]}`.
    private struct Attribute<Value: Encodable>: Encodable {
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        let name: String
        let value: Value
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(value, forKey: Key(stringValue: name))
        }
    }

    /// The answer to one `GET`: the tree or a subtree, one attribute of a node,
    /// or the host information. A missing node is 404, an attribute the node
    /// does not carry is 204, and an attribute the server does not speak is 400.
    static func response(to target: String, root: OSCQueryNode, hostInfo: OSCQueryHostInfo) -> Response {
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var path = String(parts[0]).removingPercentEncoding ?? String(parts[0])
        if path.isEmpty { path = "/" }
        let query = parts.count > 1 ? String(parts[1]).uppercased() : nil
        if query == "HOST_INFO" { return json(hostInfo) }
        guard let node = root.node(at: path) else { return Response(status: 404, body: nil) }
        guard let query else { return json(node) }
        switch query {
        case "FULL_PATH": return json(Attribute(name: query, value: node.fullPath))
        case "ACCESS": return json(Attribute(name: query, value: node.access))
        case "CONTENTS": return node.contents.map { json(Attribute(name: query, value: $0)) } ?? empty
        case "TYPE": return node.type.map { json(Attribute(name: query, value: $0)) } ?? empty
        case "VALUE": return node.value.map { json(Attribute(name: query, value: $0)) } ?? empty
        case "RANGE": return node.range.map { json(Attribute(name: query, value: $0)) } ?? empty
        case "DESCRIPTION": return node.description.map { json(Attribute(name: query, value: $0)) } ?? empty
        default: return Response(status: 400, body: nil)
        }
    }

    private static var empty: Response { Response(status: 204, body: nil) }

    private static func json(_ value: some Encodable) -> Response {
        Response(status: 200, body: try? encoder.encode(value))
    }

    /// The response as HTTP/1.1 bytes, closed after the body.
    static func httpBytes(_ response: Response) -> Data {
        let reasons = [200: "OK", 204: "No Content", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"]
        var head = "HTTP/1.1 \(response.status) \(reasons[response.status] ?? "")\r\n"
        if let body = response.body {
            head += "Content-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\n"
        } else {
            head += "Content-Length: 0\r\n"
        }
        head += "Access-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        if let body = response.body { data.append(body) }
        return data
    }
}

// MARK: - The server

/// Publishes the sketch's `@Param` parameters as an OSCQuery namespace, so a
/// control app that speaks the protocol finds the sketch on the network, reads
/// what it takes, and builds its own controls, with no address typed by hand.
/// Register it on the extension seam:
///
/// ```swift
/// import OllinOSC
///
/// @Param(20...400, group: "Shape") var radius = 120.0
/// @Param var tint = Color.orange
///
/// override func setup() {
///     extend(OSCQueryServer())
/// }
/// ```
///
/// One port number serves both halves: the namespace over HTTP on TCP (the
/// tree as JSON at `http://your-mac.local:9000/`), and the values over OSC on
/// UDP at the same number, where `/Shape/radius 200.0` sets the radius and
/// `/tint` takes a color. Both are advertised on the local network under the
/// sketch's name, as `_oscjson._tcp` and `_osc._udp`, which is how an app's
/// browse list finds them. Values land on the main thread between frames,
/// through the same control the inspector's own drag uses, so a parameter's
/// smoothing and clamping apply as they do there.
///
/// Anyone on the network who has the address can move the parameters while
/// the server is up, so treat it as a studio and venue tool.
public final class OSCQueryServer: SketchExtension {

    private let engine: OSCQueryEngine
    private let givenName: String?

    // Main-actor state, only ever touched from the sketch's loop.
    private var handles: [ParamHandle] = []
    private var handlesByName: [String: ParamHandle] = [:]
    private var lastRefresh: Double = 0
    private var announced = false

    // MARK: Lifecycle

    /// Creates a server on `port` (`9000` by default): the namespace over TCP
    /// and the OSC values over UDP, both at that number. Pass `0` to let the
    /// system pick both (read them back from `boundPort` and
    /// `receiver.boundPort`). `name` is what the network shows; the sketch's
    /// type name when `nil`.
    public convenience init(port: Int = 9000, name: String? = nil) {
        self.init(receiver: OSCReceiver(port: port), port: port, name: name)
    }

    /// Serves the namespace beside a receiver the sketch already reads, so its
    /// own `messages()` and `number(_:)` keep working while the parameters
    /// take theirs. The namespace listens on `port`, the receiver's own port
    /// number when `nil`.
    public init(receiver: OSCReceiver, port: Int? = nil, name: String? = nil) {
        self.receiver = receiver
        self.givenName = name
        engine = OSCQueryEngine(receiver: receiver, httpPort: UInt16(clamping: port ?? receiver.requestedPort))
    }

    deinit {
        engine.shutdown()
    }

    /// The receiver the values arrive on. Read it for any address outside the
    /// namespace, the way a bare `OSCReceiver` is read.
    public let receiver: OSCReceiver

    /// The name the namespace is advertised and served under, once running.
    public var name: String? { engine.currentName() }

    /// The TCP port the namespace answers on, once the listener is up.
    public var boundPort: Int? { engine.boundPort }

    /// The address of the namespace, once the listener is up.
    public var url: String? {
        guard let port = engine.boundPort else { return nil }
        return "http://\(ProcessInfo.processInfo.hostName):\(port)"
    }

    /// Whether the namespace is being advertised on the local network. On by
    /// default; off keeps the ports open and the name to yourself.
    public var advertises: Bool {
        get { engine.advertises }
        set { engine.advertises = newValue }
    }

    /// The namespace as last served: the tree a client sees right now.
    public func namespace() -> OSCQueryNode { engine.currentRoot() }

    /// Stops serving and closes both ports. `deinit` calls it, so a reload that
    /// builds a fresh sketch (and a fresh extension) releases them on its own.
    public func stop() {
        engine.shutdown()
    }

    // MARK: Extension hooks

    public func setup(_ sketch: Sketch) {
        discover(sketch)
        engine.start(name: givenName ?? String(describing: type(of: sketch)))
    }

    /// The socket-free half of `setup`: parameter discovery and the first
    /// namespace. Split out so tests can drive the paths with no listener.
    func discover(_ sketch: Sketch) {
        handles = sketch.parameters()
        handlesByName = [:]
        for handle in handles { handlesByName[handle.name] = handle }
        refresh(sketchName: givenName ?? String(describing: type(of: sketch)))
    }

    /// Reads one message as a client would send it. The receiver is its only
    /// production caller; tests use it to stand in for a control app.
    nonisolated func receive(_ message: OSCMessage) {
        engine.route(message)
    }

    public func beforeDraw(_ sketch: Sketch) {
        for (route, payload) in engine.drainPending() {
            guard let handle = handlesByName[route.name] else { continue }
            OSCQueryWire.apply(payload, to: handle, leaf: route.leaf)
        }
    }

    public func afterFrame(_ sketch: Sketch, _ info: FrameInfo) {
        announceIfReady()
        let now = sketch.time
        guard now - lastRefresh >= 0.25 || now < lastRefresh else { return }
        lastRefresh = now
        refresh(sketchName: givenName ?? String(describing: type(of: sketch)))
    }

    private func refresh(sketchName: String) {
        let (root, routes) = OSCQueryWire.namespace(for: handles, sketchName: sketchName)
        engine.replace(root: root, routes: routes)
    }

    private func announceIfReady() {
        guard !announced, let url, let oscPort = receiver.boundPort else { return }
        announced = true
        print("OSCQuery: \(url) (OSC on port \(oscPort))")
    }
}

// MARK: - The engine

/// The socket side, deliberately outside the main actor: the OSC receiver's
/// messages read against the routes, one TCP listener answering the namespace,
/// and the Bonjour names. Everything shared with the extension crosses through
/// a lock.
final class OSCQueryEngine: @unchecked Sendable {

    private final class Link: @unchecked Sendable {
        let connection: NWConnection
        var buffer: [UInt8] = []
        init(_ connection: NWConnection) { self.connection = connection }
    }

    let receiver: OSCReceiver
    private let httpPort: UInt16
    private let queue = DispatchQueue(label: "com.ollin.osc.query")
    private let listenerStore = OSAllocatedUnfairLock<NWListener?>(uncheckedState: nil)
    private let resolvedPort = OSAllocatedUnfairLock<UInt16?>(initialState: nil)
    private let links = OSAllocatedUnfairLock<[ObjectIdentifier: Link]>(uncheckedState: [:])
    private let nameStore = OSAllocatedUnfairLock<String?>(initialState: nil)
    private let advertisesStore = OSAllocatedUnfairLock(initialState: true)
    private let root = OSAllocatedUnfairLock(initialState: OSCQueryNode(fullPath: "/", contents: [:]))
    private let routes = OSAllocatedUnfairLock<[String: OSCQueryWire.Route]>(initialState: [:])
    private let pending = OSAllocatedUnfairLock<[(route: OSCQueryWire.Route, payload: ParamStored)]>(initialState: [])

    init(receiver: OSCReceiver, httpPort: UInt16) {
        self.receiver = receiver
        self.httpPort = httpPort
        receiver.observe { [weak self] message in self?.route(message) }
    }

    deinit {
        shutdown()
    }

    var boundPort: Int? { resolvedPort.withLock { $0.map(Int.init) } }

    var advertises: Bool {
        get { advertisesStore.withLock { $0 } }
        set { advertisesStore.withLock { $0 = newValue } }
    }

    func currentName() -> String? { nameStore.withLock { $0 } }
    func currentRoot() -> OSCQueryNode { root.withLock { $0 } }

    func hostInfo() -> OSCQueryHostInfo {
        OSCQueryHostInfo(name: currentName() ?? "", extensions: OSCQueryWire.extensions,
                         oscPort: receiver.boundPort)
    }

    // MARK: Handoffs with the extension

    func replace(root fresh: OSCQueryNode, routes freshRoutes: [String: OSCQueryWire.Route]) {
        root.withLock { $0 = fresh }
        routes.withLock { $0 = freshRoutes }
    }

    func drainPending() -> [(route: OSCQueryWire.Route, payload: ParamStored)] {
        pending.withLock { held in
            let drained = held
            held.removeAll()
            return drained
        }
    }

    /// Reads one message on the network queue: the route says what the leaf
    /// takes, the payload is worked out here, and the write waits for the
    /// frame boundary.
    func route(_ message: OSCMessage) {
        guard let hit = routes.withLock({ $0[message.address] }),
              let payload = OSCQueryWire.payload(message.arguments, for: hit.leaf) else { return }
        pending.withLock { $0.append((hit, payload)) }
    }

    // MARK: Lifecycle

    func start(name: String) {
        nameStore.withLock { $0 = name }
        let advertises = self.advertises
        if advertises, !receiver.isRunning { receiver.serviceName = name }
        do {
            try receiver.start()
        } catch {
            print("OSCQuery: could not open the OSC port \(receiver.requestedPort): \(error)")
        }

        let alreadyRunning = listenerStore.withLock { $0 != nil }
        guard !alreadyRunning else { return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            if httpPort == 0 {
                listener = try NWListener(using: parameters)
            } else {
                guard let port = NWEndpoint.Port(rawValue: httpPort) else { return }
                listener = try NWListener(using: parameters, on: port)
            }
        } catch {
            print("OSCQuery: could not open port \(httpPort): \(error)")
            return
        }
        if advertises {
            listener.service = NWListener.Service(name: name, type: "_oscjson._tcp")
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.resolvedPort.withLock { $0 = listener.port?.rawValue }
            case .failed(let error):
                print("OSCQuery: the listener failed: \(error)")
            case .waiting(let error):
                print("OSCQuery: waiting to open the port: \(error)")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.adopt(connection)
        }
        listenerStore.withLock { $0 = listener }
        listener.start(queue: queue)
    }

    func shutdown() {
        listenerStore.withLock { listener in
            listener?.cancel()
            listener = nil
        }
        resolvedPort.withLock { $0 = nil }
        links.withLock { all in
            for link in all.values { link.connection.cancel() }
            all.removeAll()
        }
        receiver.stop()
    }

    // MARK: Connections

    private func adopt(_ connection: NWConnection) {
        let link = Link(connection)
        links.withLock { $0[ObjectIdentifier(link)] = link }
        connection.stateUpdateHandler = { [weak self, weak link] state in
            switch state {
            case .failed, .cancelled:
                guard let link else { return }
                self?.links.withLock { $0[ObjectIdentifier(link)] = nil }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: link)
    }

    private func receive(on link: Link) {
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self, weak link] data, _, isComplete, error in
            guard let self, let link else { return }
            if let data, !data.isEmpty {
                link.buffer.append(contentsOf: data)
                if self.answer(link) { return }
            }
            if isComplete || error != nil {
                self.drop(link)
            } else {
                self.receive(on: link)
            }
        }
    }

    private func drop(_ link: Link) {
        link.connection.cancel()
        links.withLock { $0[ObjectIdentifier(link)] = nil }
    }

    /// Answers once the head is whole, then closes; `false` while it is not.
    private func answer(_ link: Link) -> Bool {
        guard let (head, _) = HTTPRequestHead.parse(link.buffer) else { return false }
        let response: OSCQueryWire.Response
        if head.method == "GET" {
            response = OSCQueryWire.response(to: head.path, root: currentRoot(), hostInfo: hostInfo())
        } else {
            response = OSCQueryWire.Response(status: 405, body: nil)
        }
        link.connection.send(content: OSCQueryWire.httpBytes(response),
                             completion: .contentProcessed { [weak self, weak link] _ in
                                 guard let self, let link else { return }
                                 self.drop(link)
                             })
        return true
    }
}
