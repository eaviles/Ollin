import CryptoKit
import Foundation
import Ollin

// The protocol layer of the remote surface, kept free of sockets on purpose:
// everything here is a pure function over bytes and values, which is what the
// tests exercise. The connection layer (RemoteInspector) feeds bytes in and
// writes bytes out; nothing in this file touches the network.

// MARK: - Messages

/// One `@Param` parameter as the page sees it: identity, display metadata, the
/// control kind, the current value, and the constraint payload for its kind.
/// Values ride `ParamStored`, the same payload the hosts persist, with one
/// exception: a menu travels as its option *index* (`.number`), because the
/// page knows the display options and their order, not the enum's case names.
/// The control kind a parameter renders as on the page. Raw values are the wire
/// spelling, so the JSON the page reads is unchanged by the Swift casing.
public enum RemoteControlKind: String, Codable, Equatable, Sendable {
    case slider, stepper, toggle, menu, color, vector, vector3, rect
    case insets, range, text, swatches
}

public struct RemoteParamDescriptor: Codable, Equatable, Sendable {
    public var name: String
    public var label: String
    public var icon: String?
    public var group: String?
    public var isShown: Bool
    public var kind: RemoteControlKind
    public var value: ParamStored

    // Constraints, present per kind.
    public var lower: Double?
    public var upper: Double?
    public var step: Double?
    /// A numeric parameter declared `style: .field`: no track, value field only.
    public var isField: Bool?
    public var options: [String]?
    public var isSegmented: Bool?
    public var isPad: Bool?
    /// A swatch strip that reads as one blended band (a `Ramp`) rather than
    /// separate blocks (a `Palette`).
    public var isGradient: Bool?
    public var xLower: Double?
    public var xUpper: Double?
    public var yLower: Double?
    public var yUpper: Double?
    public var zLower: Double?
    public var zUpper: Double?
    public var wLower: Double?
    public var wUpper: Double?
    public var hLower: Double?
    public var hUpper: Double?
}

/// The wire discriminator on every message; raw values are the wire spelling.
public enum RemoteMessageKind: String, Codable, Sendable {
    case hello, update, stats, set
}

/// Server to client, once per connection: the sketch's identity and every parameter.
public struct RemoteHello: Codable, Sendable {
    public var kind = RemoteMessageKind.hello
    public var sketch: String
    public var host: String
    public var params: [RemoteParamDescriptor]
}

/// Server to client: values that changed since the last push (edits made on
/// the Mac, or by the sketch itself), plus rows whose visibility flipped.
public struct RemoteUpdate: Codable, Sendable {
    public var kind = RemoteMessageKind.update
    public var values: [String: ParamStored]
    public var shown: [String: Bool]
}

/// Server to client, a few times a second: the monitor strip.
public struct RemoteStats: Codable, Sendable {
    public var kind = RemoteMessageKind.stats
    public var fps: Double
    public var clock: Double
    public var frame: Int
}

/// Client to server: one parameter moved on the phone.
public struct RemoteSet: Codable, Sendable {
    public var kind = RemoteMessageKind.set
    public var name: String
    public var value: ParamStored
}

// MARK: - Descriptors

public enum RemoteWire {
    /// Builds the wire descriptor for one discovered parameter.
    public static func descriptor(for handle: ParamHandle) -> RemoteParamDescriptor {
        var d = RemoteParamDescriptor(
            name: handle.name, label: handle.label, icon: handle.icon,
            group: handle.group, isShown: handle.isShown, kind: .text,
            value: snapshotValue(of: handle))
        switch handle.control {
        case .slider(let s):
            d.kind = .slider
            d.lower = s.range.lowerBound; d.upper = s.range.upperBound
            d.step = s.step
            if case .field = s.style { d.isField = true }
        case .stepper(let s):
            d.kind = .stepper
            d.lower = Double(s.range.lowerBound); d.upper = Double(s.range.upperBound)
            d.step = Double(s.step)
        case .toggle:
            d.kind = .toggle
        case .menu(let m):
            d.kind = .menu
            d.options = m.options
            if case .segmented = m.style { d.isSegmented = true }
        case .colorWell:
            d.kind = .color
        case .vector(let v):
            d.kind = .vector
            if case .pad = v.style { d.isPad = true }
            d.xLower = v.xRange.lowerBound; d.xUpper = v.xRange.upperBound
            d.yLower = v.yRange.lowerBound; d.yUpper = v.yRange.upperBound
        case .vector3(let v):
            d.kind = .vector3
            d.xLower = v.xRange.lowerBound; d.xUpper = v.xRange.upperBound
            d.yLower = v.yRange.lowerBound; d.yUpper = v.yRange.upperBound
            d.zLower = v.zRange.lowerBound; d.zUpper = v.zRange.upperBound
        case .rectangle(let r):
            d.kind = .rect
            d.xLower = r.xRange.lowerBound; d.xUpper = r.xRange.upperBound
            d.yLower = r.yRange.lowerBound; d.yUpper = r.yRange.upperBound
            d.wLower = r.widthRange.lowerBound; d.wUpper = r.widthRange.upperBound
            d.hLower = r.heightRange.lowerBound; d.hUpper = r.heightRange.upperBound
        case .insets(let i):
            d.kind = .insets
            d.lower = i.edgeRange.lowerBound; d.upper = i.edgeRange.upperBound
        case .range(let r):
            d.kind = .range
            d.lower = r.outer.lowerBound; d.upper = r.outer.upperBound
            if case .field = r.style { d.isField = true }
        case .text:
            d.kind = .text
        case .swatches(let s):
            d.kind = .swatches
            d.lower = Double(s.count.lowerBound); d.upper = Double(s.count.upperBound)
            if case .gradient = s.style { d.isGradient = true }
        }
        return d
    }

    /// The current value in wire form. Every kind is its persisted payload,
    /// except a menu, which travels by index (see `RemoteParamDescriptor`).
    public static func snapshotValue(of handle: ParamHandle) -> ParamStored {
        if case .menu(let m) = handle.control { return .number(Double(m.read())) }
        return handle.param.stored
    }

    /// Applies one incoming value to its parameter. A menu index goes through the
    /// control's own setter; everything else jumps through `restore`, the same
    /// path the hosts use to re-apply persisted values. A payload of the wrong
    /// kind is ignored, exactly as `restore` promises.
    public static func apply(_ value: ParamStored, to handle: ParamHandle) {
        if case .menu(let m) = handle.control {
            guard case .number(let index) = value else { return }
            let i = Int(index.rounded())
            guard m.options.indices.contains(i) else { return }
            m.write(i)
            return
        }
        handle.param.restore(value)
    }
}

// MARK: - HTTP

public enum RemoteHTTP {
    /// A parsed request head: the method, the path, and the headers with
    /// lowercased names.
    public struct Request: Equatable, Sendable {
        public var method: String
        public var path: String
        public var headers: [String: String]
    }

    /// Finds and parses a complete request head in `bytes`. Returns the request
    /// plus how many bytes the head consumed (through the blank line), or `nil`
    /// while the head is still incomplete or malformed.
    public static func parseHead(_ bytes: [UInt8]) -> (request: Request, consumed: Int)? {
        guard let end = headEnd(bytes) else { return nil }
        guard let text = String(bytes: bytes[..<end], encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)[...]
        guard let requestLine = lines.popFirst() else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let request = Request(method: String(parts[0]), path: String(parts[1]), headers: headers)
        return (request, end + 4)
    }

    private static func headEnd(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 4 else { return nil }
        for i in 0...(bytes.count - 4)
        where bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10 {
            return i
        }
        return nil
    }

    /// Whether the request asks to switch to the WebSocket protocol.
    public static func isWebSocketUpgrade(_ request: Request) -> Bool {
        request.headers["upgrade"]?.lowercased() == "websocket"
            && request.headers["sec-websocket-key"] != nil
    }

    /// The accept token for a client key, per the WebSocket handshake: the key
    /// concatenated with the protocol's fixed GUID, SHA-1 hashed, base64.
    public static func acceptKey(for clientKey: String) -> String {
        let joined = clientKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data(joined.utf8))
        return Data(digest).base64EncodedString()
    }

    /// The 101 response completing the WebSocket handshake.
    public static func upgradeResponse(accept: String) -> Data {
        Data(("HTTP/1.1 101 Switching Protocols\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Accept: \(accept)\r\n\r\n").utf8)
    }

    /// A 200 carrying the control page.
    public static func pageResponse(html: Data) -> Data {
        var head = Data(("HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.count)\r\n"
            + "Cache-Control: no-store\r\n"
            + "Connection: close\r\n\r\n").utf8)
        head.append(html)
        return head
    }

    /// A 404 for any path that is not the page or the socket.
    public static func notFound() -> Data {
        Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
    }
}

// MARK: - WebSocket frames

public enum WebSocketFraming {
    public enum Opcode: UInt8, Sendable {
        case continuation = 0x0
        case text = 0x1
        case binary = 0x2
        case close = 0x8
        case ping = 0x9
        case pong = 0xA
    }

    public struct Frame: Equatable, Sendable {
        public var fin: Bool
        public var opcode: Opcode
        public var payload: [UInt8]
        public init(fin: Bool, opcode: Opcode, payload: [UInt8]) {
            self.fin = fin; self.opcode = opcode; self.payload = payload
        }
    }

    /// Encodes one server-to-client frame (servers never mask).
    public static func encode(_ opcode: Opcode, payload: [UInt8]) -> Data {
        var out: [UInt8] = [0x80 | opcode.rawValue]
        let n = payload.count
        if n < 126 {
            out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(126)
            out.append(UInt8(n >> 8)); out.append(UInt8(n & 0xFF))
        } else {
            out.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                out.append(UInt8((UInt64(n) >> UInt64(shift)) & 0xFF))
            }
        }
        out.append(contentsOf: payload)
        return Data(out)
    }

    public static func encodeText(_ text: String) -> Data {
        encode(.text, payload: [UInt8](text.utf8))
    }

    /// Drains every complete frame at the front of `buffer`, unmasking client
    /// payloads, and removes the consumed bytes. Bytes of a frame still in
    /// flight stay in the buffer for the next call. Returns `nil` on a
    /// malformed frame (an unknown opcode), telling the caller to drop the
    /// connection.
    public static func decode(buffer: inout [UInt8]) -> [Frame]? {
        var frames: [Frame] = []
        var start = 0
        while buffer.count - start >= 2 {
            let b0 = buffer[start], b1 = buffer[start + 1]
            guard let opcode = Opcode(rawValue: b0 & 0x0F) else { return nil }
            let fin = b0 & 0x80 != 0
            let masked = b1 & 0x80 != 0
            var length = Int(b1 & 0x7F)
            var offset = start + 2
            if length == 126 {
                guard buffer.count - offset >= 2 else { break }
                length = Int(buffer[offset]) << 8 | Int(buffer[offset + 1])
                offset += 2
            } else if length == 127 {
                guard buffer.count - offset >= 8 else { break }
                var wide: UInt64 = 0
                for i in 0..<8 { wide = wide << 8 | UInt64(buffer[offset + i]) }
                guard let narrow = Int(exactly: wide) else { return nil }
                length = narrow
                offset += 8
            }
            let maskLength = masked ? 4 : 0
            guard buffer.count - offset >= maskLength + length else { break }
            var payload = [UInt8](buffer[(offset + maskLength)..<(offset + maskLength + length)])
            if masked {
                let mask = [UInt8](buffer[offset..<(offset + 4)])
                for i in payload.indices { payload[i] ^= mask[i % 4] }
            }
            frames.append(Frame(fin: fin, opcode: opcode, payload: payload))
            start = offset + maskLength + length
        }
        buffer.removeFirst(start)
        return frames
    }
}
