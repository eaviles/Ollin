import Foundation

/// The control packet kinds of MQTT 3.1.1, in the numbering the specification
/// gives them (the high nibble of a packet's first byte).
///
/// Only the kinds this client needs are listed. The three quality-of-service 2
/// handshake packets (PUBREC, PUBREL, PUBCOMP) have no case here: the client
/// never asks for that level, so a broker may never send one.
enum MQTTPacketKind: UInt8, Sendable {
    case connect = 1
    case connectAcknowledgement = 2
    case publish = 3
    case publishAcknowledgement = 4
    case subscribe = 8
    case subscribeAcknowledgement = 9
    case unsubscribe = 10
    case unsubscribeAcknowledgement = 11
    case ping = 12
    case pingResponse = 13
    case disconnect = 14
}

/// A whole control packet, decoded far enough for either side of the wire to act
/// on it. The client sends some of these and receives others; the test broker
/// does the reverse, which is why both directions are decoded here rather than
/// only the ones a client reads.
enum MQTTPacket: Sendable, Equatable {
    /// A client opening a session: its identifier, the session flag, the will it
    /// leaves behind, and the credentials if it has any.
    case connect(MQTTConnect)
    /// The broker's answer: whether a session was resumed, and the return code
    /// (`0` accepted, anything else refused).
    case connectAcknowledgement(sessionPresent: Bool, code: UInt8)
    /// A message on a topic, in either direction.
    case publish(MQTTPublish)
    /// The acknowledgement of a quality-of-service 1 publish.
    case publishAcknowledgement(id: UInt16)
    /// A subscription request: one or more filters, each with the level asked for.
    case subscribe(id: UInt16, filters: [(filter: String, qos: MQTTQoS)])
    /// The broker's answer: one return code per filter, in the order asked.
    case subscribeAcknowledgement(id: UInt16, codes: [UInt8])
    /// Dropping subscriptions.
    case unsubscribe(id: UInt16, filters: [String])
    /// The broker's answer to a drop.
    case unsubscribeAcknowledgement(id: UInt16)
    /// The keep-alive heartbeat a client sends when the line has gone quiet.
    case ping
    /// The broker's answer to the heartbeat.
    case pingResponse
    /// A clean goodbye. The will is discarded when the broker sees this, which
    /// is the whole difference between leaving and being cut off.
    case disconnect

    static func == (lhs: MQTTPacket, rhs: MQTTPacket) -> Bool {
        switch (lhs, rhs) {
        case (.connect(let a), .connect(let b)): return a == b
        case (.connectAcknowledgement(let a, let b), .connectAcknowledgement(let c, let d)):
            return a == c && b == d
        case (.publish(let a), .publish(let b)): return a == b
        case (.publishAcknowledgement(let a), .publishAcknowledgement(let b)): return a == b
        case (.subscribe(let a, let f), .subscribe(let b, let g)):
            return a == b && f.count == g.count && zip(f, g).allSatisfy { $0.filter == $1.filter && $0.qos == $1.qos }
        case (.subscribeAcknowledgement(let a, let f), .subscribeAcknowledgement(let b, let g)):
            return a == b && f == g
        case (.unsubscribe(let a, let f), .unsubscribe(let b, let g)): return a == b && f == g
        case (.unsubscribeAcknowledgement(let a), .unsubscribeAcknowledgement(let b)): return a == b
        case (.ping, .ping), (.pingResponse, .pingResponse), (.disconnect, .disconnect): return true
        default: return false
        }
    }
}

/// The contents of a CONNECT packet.
struct MQTTConnect: Sendable, Equatable {
    var clientID: String
    var cleanSession: Bool = true
    var keepAlive: UInt16 = 30
    var will: MQTTWill?
    var username: String?
    var password: String?
}

/// The contents of a PUBLISH packet, in either direction.
struct MQTTPublish: Sendable, Equatable {
    var topic: String
    var payload: Data
    var qos: MQTTQoS = .atMostOnce
    var retains: Bool = false
    /// Set on a packet the sender is sending a second time, so the receiver knows
    /// it may already have seen it.
    var isDuplicate: Bool = false
    /// Present only above quality of service 0, where the packet is acknowledged.
    var id: UInt16?
}

// MARK: - Encoding

extension MQTTPacket {

    /// The bytes of this packet, fixed header included.
    func encode() -> Data {
        switch self {
        case .connect(let connect):
            var body = Data()
            body.appendMQTTString("MQTT")
            body.append(4)                       // protocol level: 3.1.1
            var flags: UInt8 = 0
            if connect.cleanSession { flags |= 0x02 }
            if let will = connect.will {
                flags |= 0x04
                flags |= UInt8(will.qos.rawValue) << 3
                if will.retains { flags |= 0x20 }
            }
            if connect.password != nil { flags |= 0x40 }
            if connect.username != nil { flags |= 0x80 }
            body.append(flags)
            body.appendMQTTBig(connect.keepAlive)
            body.appendMQTTString(connect.clientID)
            if let will = connect.will {
                body.appendMQTTString(will.topic)
                body.appendMQTTData(will.payload)
            }
            if let username = connect.username { body.appendMQTTString(username) }
            if let password = connect.password { body.appendMQTTString(password) }
            return MQTTPacket.frame(.connect, flags: 0, body: body)

        case .connectAcknowledgement(let sessionPresent, let code):
            return MQTTPacket.frame(.connectAcknowledgement, flags: 0,
                                    body: Data([sessionPresent ? 1 : 0, code]))

        case .publish(let publish):
            var header: UInt8 = UInt8(publish.qos.rawValue) << 1
            if publish.retains { header |= 0x01 }
            if publish.isDuplicate { header |= 0x08 }
            var body = Data()
            body.appendMQTTString(publish.topic)
            if publish.qos != .atMostOnce { body.appendMQTTBig(publish.id ?? 1) }
            body.append(publish.payload)
            return MQTTPacket.frame(.publish, flags: header, body: body)

        case .publishAcknowledgement(let id):
            var body = Data()
            body.appendMQTTBig(id)
            return MQTTPacket.frame(.publishAcknowledgement, flags: 0, body: body)

        case .subscribe(let id, let filters):
            var body = Data()
            body.appendMQTTBig(id)
            for entry in filters {
                body.appendMQTTString(entry.filter)
                body.append(UInt8(entry.qos.rawValue))
            }
            // The specification fixes the low nibble of a SUBSCRIBE at 0b0010, and
            // a broker must treat any other value as a protocol error.
            return MQTTPacket.frame(.subscribe, flags: 0x02, body: body)

        case .subscribeAcknowledgement(let id, let codes):
            var body = Data()
            body.appendMQTTBig(id)
            body.append(contentsOf: codes)
            return MQTTPacket.frame(.subscribeAcknowledgement, flags: 0, body: body)

        case .unsubscribe(let id, let filters):
            var body = Data()
            body.appendMQTTBig(id)
            for filter in filters { body.appendMQTTString(filter) }
            return MQTTPacket.frame(.unsubscribe, flags: 0x02, body: body)

        case .unsubscribeAcknowledgement(let id):
            var body = Data()
            body.appendMQTTBig(id)
            return MQTTPacket.frame(.unsubscribeAcknowledgement, flags: 0, body: body)

        case .ping: return MQTTPacket.frame(.ping, flags: 0, body: Data())
        case .pingResponse: return MQTTPacket.frame(.pingResponse, flags: 0, body: Data())
        case .disconnect: return MQTTPacket.frame(.disconnect, flags: 0, body: Data())
        }
    }

    private static func frame(_ kind: MQTTPacketKind, flags: UInt8, body: Data) -> Data {
        var out = Data([kind.rawValue << 4 | (flags & 0x0F)])
        out.appendMQTTVariable(body.count)
        out.append(body)
        return out
    }
}

// MARK: - Decoding

extension MQTTPacket {

    /// Pulls one packet off the front of `bytes`, returning it with the number of
    /// bytes consumed, or `nil` while the packet is still incomplete.
    ///
    /// Throws `MQTTWireError` when the bytes cannot be a packet at all, which is
    /// the difference the reader acts on: incomplete means wait for more, invalid
    /// means drop the connection. Nothing here traps on malformed input.
    static func decode(from bytes: Data) throws -> (packet: MQTTPacket, consumed: Int)? {
        guard let first = bytes.first else { return nil }
        guard let kind = MQTTPacketKind(rawValue: first >> 4) else { throw MQTTWireError.unknownPacketKind }
        let flags = first & 0x0F
        guard let length = try Data.readMQTTVariable(bytes, from: 1) else { return nil }
        let start = length.next
        let end = start + length.value
        guard bytes.count >= end else { return nil }
        let body = Data(bytes[(bytes.startIndex + start)..<(bytes.startIndex + end)])
        var reader = MQTTReader(body)

        let packet: MQTTPacket
        switch kind {
        case .connect:
            guard try reader.string() == "MQTT" else { throw MQTTWireError.badProtocolName }
            let level = try reader.byte()
            guard level == 4 else { throw MQTTWireError.badProtocolLevel }
            let connectFlags = try reader.byte()
            let keepAlive = try reader.big()
            var connect = MQTTConnect(clientID: try reader.string(),
                                      cleanSession: connectFlags & 0x02 != 0,
                                      keepAlive: keepAlive)
            if connectFlags & 0x04 != 0 {
                let topic = try reader.string()
                let payload = try reader.data()
                let qos = MQTTQoS(rawValue: Int((connectFlags >> 3) & 0x03)) ?? .atMostOnce
                connect.will = MQTTWill(topic: topic, payload: payload,
                                        qos: qos, retains: connectFlags & 0x20 != 0)
            }
            if connectFlags & 0x80 != 0 { connect.username = try reader.string() }
            if connectFlags & 0x40 != 0 { connect.password = try reader.string() }
            packet = .connect(connect)

        case .connectAcknowledgement:
            let present = try reader.byte()
            let code = try reader.byte()
            packet = .connectAcknowledgement(sessionPresent: present & 0x01 != 0, code: code)

        case .publish:
            guard let qos = MQTTQoS(rawValue: Int((flags >> 1) & 0x03)) else {
                throw MQTTWireError.unsupportedQoS
            }
            let topic = try reader.string()
            let id: UInt16? = qos == .atMostOnce ? nil : try reader.big()
            packet = .publish(MQTTPublish(topic: topic, payload: reader.rest(), qos: qos,
                                          retains: flags & 0x01 != 0,
                                          isDuplicate: flags & 0x08 != 0, id: id))

        case .publishAcknowledgement:
            packet = .publishAcknowledgement(id: try reader.big())

        case .subscribe:
            guard flags == 0x02 else { throw MQTTWireError.badReservedFlags }
            let id = try reader.big()
            var filters: [(filter: String, qos: MQTTQoS)] = []
            while !reader.isAtEnd {
                let filter = try reader.string()
                guard let qos = MQTTQoS(rawValue: Int(try reader.byte() & 0x03)) else {
                    throw MQTTWireError.unsupportedQoS
                }
                filters.append((filter, qos))
            }
            guard !filters.isEmpty else { throw MQTTWireError.emptyPayload }
            packet = .subscribe(id: id, filters: filters)

        case .subscribeAcknowledgement:
            let id = try reader.big()
            packet = .subscribeAcknowledgement(id: id, codes: [UInt8](reader.rest()))

        case .unsubscribe:
            guard flags == 0x02 else { throw MQTTWireError.badReservedFlags }
            let id = try reader.big()
            var filters: [String] = []
            while !reader.isAtEnd { filters.append(try reader.string()) }
            guard !filters.isEmpty else { throw MQTTWireError.emptyPayload }
            packet = .unsubscribe(id: id, filters: filters)

        case .unsubscribeAcknowledgement:
            packet = .unsubscribeAcknowledgement(id: try reader.big())

        case .ping: packet = .ping
        case .pingResponse: packet = .pingResponse
        case .disconnect: packet = .disconnect
        }
        return (packet, end)
    }
}

/// What can be wrong with bytes that claim to be a control packet. Every one of
/// these is fatal to the connection rather than to the process.
enum MQTTWireError: Error, Sendable, Equatable {
    case unknownPacketKind
    case badProtocolName
    case badProtocolLevel
    case badReservedFlags
    case unsupportedQoS
    case emptyPayload
    case truncated
    /// A remaining-length field that ran past its four bytes.
    case lengthTooLong
}

/// A cursor over a packet body. Every read checks the bound first, so a short
/// body throws instead of reading off the end.
private struct MQTTReader {
    private let bytes: Data
    private var offset: Int

    init(_ bytes: Data) {
        self.bytes = bytes
        self.offset = 0
    }

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw MQTTWireError.truncated }
        defer { offset += 1 }
        return bytes[bytes.startIndex + offset]
    }

    mutating func big() throws -> UInt16 {
        let high = try byte(), low = try byte()
        return UInt16(high) << 8 | UInt16(low)
    }

    mutating func data() throws -> Data {
        let count = Int(try big())
        guard offset + count <= bytes.count else { throw MQTTWireError.truncated }
        defer { offset += count }
        return Data(bytes[(bytes.startIndex + offset)..<(bytes.startIndex + offset + count)])
    }

    mutating func string() throws -> String {
        let raw = try data()
        guard let text = String(data: raw, encoding: .utf8) else { throw MQTTWireError.truncated }
        return text
    }

    mutating func rest() -> Data {
        defer { offset = bytes.count }
        return Data(bytes[(bytes.startIndex + offset)...])
    }
}

// MARK: - The primitives the format is built from

extension Data {

    /// Appends a length-prefixed UTF-8 string, the only string encoding MQTT has.
    mutating func appendMQTTString(_ text: String) {
        appendMQTTData(Data(text.utf8))
    }

    /// Appends a two-byte length followed by the bytes themselves.
    mutating func appendMQTTData(_ payload: Data) {
        appendMQTTBig(UInt16(clamping: payload.count))
        append(payload)
    }

    /// Appends a 16-bit value most significant byte first, which is the order
    /// every fixed-width field in MQTT uses.
    mutating func appendMQTTBig(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xFF))
    }

    /// Appends a remaining-length field: seven bits of value per byte, the high
    /// bit saying another byte follows. Four bytes is the ceiling the format
    /// fixes, so the largest packet body is 268,435,455 bytes.
    mutating func appendMQTTVariable(_ value: Int) {
        var remaining = Swift.max(0, value)
        repeat {
            var digit = UInt8(remaining % 128)
            remaining /= 128
            if remaining > 0 { digit |= 0x80 }
            append(digit)
        } while remaining > 0
    }

    /// Reads a remaining-length field starting at `start`, returning its value and
    /// the offset just past it, or `nil` while the field is still incomplete.
    static func readMQTTVariable(_ bytes: Data, from start: Int) throws -> (value: Int, next: Int)? {
        var value = 0
        var multiplier = 1
        var index = start
        for _ in 0..<4 {
            guard index < bytes.count else { return nil }
            let digit = bytes[bytes.startIndex + index]
            index += 1
            value += Int(digit & 0x7F) * multiplier
            if digit & 0x80 == 0 { return (value, index) }
            multiplier *= 128
        }
        throw MQTTWireError.lengthTooLong
    }
}
