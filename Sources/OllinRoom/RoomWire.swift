// RoomWire: the message format several machines share when they draw one piece.
//
// The framing follows the same discipline the phone stream uses: a fixed
// little-endian header (magic, version, kind, reserved, payload length), then a
// payload the reader decodes by kind. The transport under it already delivers
// whole messages, so the length is a check rather than a frame boundary: a
// payload that disagrees with its header is dropped instead of decoded.
//
// Everything here is a pure function over bytes and values, so the tests need no
// network at all.

import Foundation
import Ollin

/// The frame format the room speaks.
public enum RoomWire {

    /// Frame marker, "OLRM" as a little-endian `UInt32`. A frame from another
    /// application, or a corrupt one, fails this check and is dropped.
    public static let magic: UInt32 = 0x4F4C_524D

    /// Wire version. Pre-1.0 every machine in a room runs the same build, so this
    /// is not bumped per payload change. It becomes a real compatibility contract
    /// at 1.0, when one machine in a venue may be a version behind.
    public static let version: UInt8 = 1

    /// Header size: magic(4) + version(1) + kind(1) + reserved(2) + payloadLength(4).
    public static let headerByteCount = 12

    /// Upper bound on one payload, so a bad header cannot steer a huge read.
    /// A knob or a value is a few dozen bytes; the room is not a file transfer.
    public static let maxPayloadBytes = 1 << 20
}

/// What a frame carries.
public enum RoomMessageKind: UInt8, Sendable, CaseIterable {
    /// Said once at each new connection: the sender's seat and sketch name.
    case hello = 1
    /// One keyed value a sketch sent, the ordinary traffic of a room.
    case value = 2
    /// One shared `@Param` knob, as the payload the hosts persist.
    case knob = 3
    /// A clock question, sent by a follower to the peer that owns the clock.
    case clockPing = 4
    /// The clock owner's answer: the same question number, and its room time.
    case clockPong = 5
}

/// A value a sketch sends to the room.
public enum RoomValue: Sendable, Equatable {
    case number(Double)
    case integer(Int)
    case text(String)
    case flag(Bool)
    case point(Vector2)
    case color(Color)
    case bytes(Data)

    /// The tag that stands for this case on the wire.
    var tag: UInt8 {
        switch self {
        case .number: 1
        case .integer: 2
        case .text: 3
        case .flag: 4
        case .point: 5
        case .color: 6
        case .bytes: 7
        }
    }
}

public extension RoomValue {
    /// The value as a `Double`. Whole numbers and flags read as numbers, so a
    /// sketch that sends `1` and a sketch that sends `1.0` agree.
    var number: Double? {
        switch self {
        case .number(let value): value
        case .integer(let value): Double(value)
        case .flag(let value): value ? 1 : 0
        default: nil
        }
    }

    /// The value as an `Int`, rounding a number toward zero.
    var integer: Int? {
        switch self {
        case .integer(let value): value
        case .number(let value): value.isFinite ? Int(value) : nil
        case .flag(let value): value ? 1 : 0
        default: nil
        }
    }

    /// The value as text. Only text reads as text.
    var text: String? {
        if case .text(let value) = self { return value }
        return nil
    }

    /// The value as a flag. A number is true when it is not zero.
    var flag: Bool? {
        switch self {
        case .flag(let value): value
        case .number(let value): value != 0
        case .integer(let value): value != 0
        default: nil
        }
    }

    /// The value as a point.
    var point: Vector2? {
        if case .point(let value) = self { return value }
        return nil
    }

    /// The value as a color.
    var color: Color? {
        if case .color(let value) = self { return value }
        return nil
    }

    /// The value as raw bytes.
    var bytes: Data? {
        if case .bytes(let value) = self { return value }
        return nil
    }
}

/// One value that arrived from another machine.
public struct RoomMessage: Sendable, Equatable {
    /// The key the sender put the value under.
    public let key: String
    /// What arrived.
    public let value: RoomValue
    /// The name of the machine that sent it.
    public let sender: String

    public init(key: String, value: RoomValue, sender: String) {
        self.key = key
        self.value = value
        self.sender = sender
    }

    /// The value as a number, if it reads as one.
    public var number: Double? { value.number }
    /// The value as a whole number, if it reads as one.
    public var integer: Int? { value.integer }
    /// The value as text, if it is text.
    public var text: String? { value.text }
    /// The value as a flag, if it reads as one.
    public var flag: Bool? { value.flag }
    /// The value as a point, if it is a point.
    public var point: Vector2? { value.point }
    /// The value as a color, if it is a color.
    public var color: Color? { value.color }
    /// The value as raw bytes, if it is bytes.
    public var bytes: Data? { value.bytes }
}

// MARK: - Framing

public extension RoomWire {

    /// Wraps a payload in the frame header.
    static func frame(_ kind: RoomMessageKind, _ payload: [UInt8]) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(headerByteCount + payload.count)
        appendLittleEndian(magic, to: &bytes)
        bytes.append(version)
        bytes.append(kind.rawValue)
        bytes.append(0)
        bytes.append(0)
        appendLittleEndian(UInt32(payload.count), to: &bytes)
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    /// Reads a frame header and returns the payload with it, or `nil` when the
    /// bytes are not a frame this version understands. Never traps: a truncated
    /// or foreign message is simply not a frame.
    static func unframe(_ data: Data) -> (kind: RoomMessageKind, payload: [UInt8])? {
        // Copied into an array so the indices start at zero. A `Data` handed back
        // by a network callback is often a slice, whose first index is not zero,
        // and reading a slice as if it were zero based is the classic way to
        // decode the wrong bytes.
        let bytes = [UInt8](data)
        guard bytes.count >= headerByteCount else { return nil }
        guard readLittleEndian(UInt32.self, from: bytes, at: 0) == magic else { return nil }
        guard bytes[4] == version else { return nil }
        guard let kind = RoomMessageKind(rawValue: bytes[5]) else { return nil }
        let length = Int(readLittleEndian(UInt32.self, from: bytes, at: 8))
        guard length <= maxPayloadBytes else { return nil }
        guard bytes.count == headerByteCount + length else { return nil }
        return (kind, Array(bytes[headerByteCount...]))
    }
}

// MARK: - Payloads

public extension RoomWire {

    /// A keyed value, ready to send.
    static func encodeValue(key: String, value: RoomValue) -> Data {
        var payload: [UInt8] = []
        appendString(key, to: &payload)
        payload.append(value.tag)
        switch value {
        case .number(let number):
            appendDouble(number, to: &payload)
        case .integer(let integer):
            appendLittleEndian(UInt64(bitPattern: Int64(integer)), to: &payload)
        case .text(let text):
            appendString(text, to: &payload)
        case .flag(let flag):
            payload.append(flag ? 1 : 0)
        case .point(let point):
            appendDouble(point.x, to: &payload)
            appendDouble(point.y, to: &payload)
        case .color(let color):
            appendDouble(color.red, to: &payload)
            appendDouble(color.green, to: &payload)
            appendDouble(color.blue, to: &payload)
            appendDouble(color.alpha, to: &payload)
        case .bytes(let data):
            appendLittleEndian(UInt32(data.count), to: &payload)
            payload.append(contentsOf: [UInt8](data))
        }
        return frame(.value, payload)
    }

    /// The key and value inside a `.value` payload, or `nil` when it is malformed.
    static func decodeValue(_ payload: [UInt8]) -> (key: String, value: RoomValue)? {
        var reader = ByteReader(payload)
        guard let key = reader.string(), let tag = reader.byte() else { return nil }
        switch tag {
        case 1:
            guard let number = reader.double() else { return nil }
            return (key, .number(number))
        case 2:
            guard let raw = reader.unsigned64() else { return nil }
            return (key, .integer(Int(Int64(bitPattern: raw))))
        case 3:
            guard let text = reader.string() else { return nil }
            return (key, .text(text))
        case 4:
            guard let flag = reader.byte() else { return nil }
            return (key, .flag(flag != 0))
        case 5:
            guard let x = reader.double(), let y = reader.double() else { return nil }
            return (key, .point(Vector2(x, y)))
        case 6:
            guard let red = reader.double(), let green = reader.double(),
                  let blue = reader.double(), let alpha = reader.double() else { return nil }
            return (key, .color(Color(red: red, green: green, blue: blue, alpha: alpha)))
        case 7:
            guard let count = reader.unsigned32(), let bytes = reader.take(Int(count)) else { return nil }
            return (key, .bytes(Data(bytes)))
        default:
            return nil
        }
    }

    /// The greeting a machine says at every new connection.
    static func encodeHello(seat: Int?, sketchName: String) -> Data {
        var payload: [UInt8] = []
        appendLittleEndian(UInt32(bitPattern: Int32(seat.map { Int32(clamping: $0) } ?? -1)), to: &payload)
        appendString(sketchName, to: &payload)
        return frame(.hello, payload)
    }

    /// The seat and sketch name inside a `.hello` payload.
    static func decodeHello(_ payload: [UInt8]) -> (seat: Int?, sketchName: String)? {
        var reader = ByteReader(payload)
        guard let raw = reader.unsigned32(), let name = reader.string() else { return nil }
        let seat = Int32(bitPattern: raw)
        return (seat < 0 ? nil : Int(seat), name)
    }

    /// One shared knob: its property name, when it was turned by the room's own
    /// clock, and the payload the hosts persist.
    ///
    /// The time is what settles an argument. Two people turning the same knob on
    /// two machines in the same second would otherwise end up looking at
    /// different values forever, each having taken the other's and stopped. With
    /// the time on it, the later turn wins on every machine.
    static func encodeKnob(name: String, stored: ParamStored, turnedAt: Double) -> Data? {
        guard let encoded = try? JSONEncoder().encode(stored) else { return nil }
        var payload: [UInt8] = []
        appendString(name, to: &payload)
        appendDouble(turnedAt, to: &payload)
        appendLittleEndian(UInt32(encoded.count), to: &payload)
        payload.append(contentsOf: [UInt8](encoded))
        return frame(.knob, payload)
    }

    /// The knob name, when it was turned, and its value inside a `.knob` payload.
    static func decodeKnob(_ payload: [UInt8]) -> (name: String, turnedAt: Double, stored: ParamStored)? {
        var reader = ByteReader(payload)
        guard let name = reader.string(), let turnedAt = reader.double(), let count = reader.unsigned32(),
              let bytes = reader.take(Int(count)),
              let stored = try? JSONDecoder().decode(ParamStored.self, from: Data(bytes)) else { return nil }
        return (name, turnedAt, stored)
    }

    /// A clock question, numbered so its answer can be matched to it.
    static func encodeClockPing(id: UInt32) -> Data {
        var payload: [UInt8] = []
        appendLittleEndian(id, to: &payload)
        return frame(.clockPing, payload)
    }

    /// The question number inside a `.clockPing` payload.
    static func decodeClockPing(_ payload: [UInt8]) -> UInt32? {
        var reader = ByteReader(payload)
        return reader.unsigned32()
    }

    /// The clock owner's answer: the question number and the owner's room time.
    static func encodeClockPong(id: UInt32, roomTime: Double) -> Data {
        var payload: [UInt8] = []
        appendLittleEndian(id, to: &payload)
        appendDouble(roomTime, to: &payload)
        return frame(.clockPong, payload)
    }

    /// The question number and room time inside a `.clockPong` payload.
    static func decodeClockPong(_ payload: [UInt8]) -> (id: UInt32, roomTime: Double)? {
        var reader = ByteReader(payload)
        guard let id = reader.unsigned32(), let time = reader.double() else { return nil }
        return (id, time)
    }
}

// MARK: - Names

public extension RoomWire {

    /// Turns a room name into a service name the local network can advertise.
    ///
    /// The rules are the system's, not ours: at most 15 characters, lowercase
    /// letters, digits and hyphens only, and at least one letter. So the name is
    /// lowercased, anything else becomes a hyphen, and it is carried under an
    /// `ollin-` prefix so two different applications on one network cannot answer
    /// each other. A name too long to fit keeps its first five characters and
    /// takes four more from a hash of the whole name, so "wall left of stage" and
    /// "wall right of stage" stay different rooms.
    static func serviceType(for name: String) -> String {
        let prefix = "ollin-"
        let budget = 15 - prefix.count
        var cleaned = ""
        var lastWasHyphen = false
        for scalar in name.lowercased().unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                cleaned.unicodeScalars.append(scalar)
                lastWasHyphen = false
            } else if !cleaned.isEmpty && !lastWasHyphen {
                cleaned.append("-")
                lastWasHyphen = true
            }
        }
        while cleaned.hasSuffix("-") { cleaned.removeLast() }
        if cleaned.isEmpty { return prefix + "room" }
        if cleaned.count <= budget { return prefix + cleaned }
        var head = String(cleaned.prefix(budget - 4))
        while head.hasSuffix("-") { head.removeLast() }
        // The hash is taken over the cleaned name, not the one typed, so two
        // spellings of one room name ("Sala Grande" and "sala grande") still
        // reach the same room.
        return prefix + head + hash(cleaned)
    }

    /// A four-character hash of a name, used to keep two long room names apart.
    static func hash(_ text: String) -> String {
        var value: UInt32 = 2_166_136_261
        for byte in Array(text.utf8) {
            value ^= UInt32(byte)
            value = value &* 16_777_619
        }
        let short = UInt16(truncatingIfNeeded: value ^ (value >> 16))
        return String(format: "%04x", short)
    }

    /// The name this machine goes by in the room: the computer's name, plus a few
    /// characters that keep two sketches on one Mac apart. Capped well under the
    /// 63 bytes the system allows.
    static func peerName(host: String, suffix: String) -> String {
        var base = host
        if let dot = base.firstIndex(of: ".") { base = String(base[..<dot]) }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "ollin" }
        if base.count > 40 { base = String(base.prefix(40)) }
        return suffix.isEmpty ? base : base + "-" + suffix
    }
}

// MARK: - Bytes

/// Reads a payload one field at a time, and answers `nil` the moment the bytes
/// run out. Every decoder above goes through it, which is why a short or
/// corrupt payload is dropped rather than trapping.
struct ByteReader {
    private let bytes: [UInt8]
    private var index: Int = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func byte() -> UInt8? {
        guard index < bytes.count else { return nil }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, index + count <= bytes.count else { return nil }
        defer { index += count }
        return bytes[index..<(index + count)]
    }

    mutating func unsigned32() -> UInt32? {
        guard let slice = take(4) else { return nil }
        return readLittleEndian(UInt32.self, from: Array(slice), at: 0)
    }

    mutating func unsigned64() -> UInt64? {
        guard let slice = take(8) else { return nil }
        return readLittleEndian(UInt64.self, from: Array(slice), at: 0)
    }

    mutating func double() -> Double? {
        guard let raw = unsigned64() else { return nil }
        return Double(bitPattern: raw)
    }

    mutating func string() -> String? {
        guard let count = unsigned32(), let slice = take(Int(count)) else { return nil }
        return String(decoding: slice, as: UTF8.self)
    }
}

func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
}

func appendDouble(_ value: Double, to bytes: inout [UInt8]) {
    appendLittleEndian(value.bitPattern, to: &bytes)
}

func appendString(_ text: String, to bytes: inout [UInt8]) {
    let utf8 = Array(text.utf8)
    appendLittleEndian(UInt32(utf8.count), to: &bytes)
    bytes.append(contentsOf: utf8)
}

func readLittleEndian<T: FixedWidthInteger>(_ type: T.Type, from bytes: [UInt8], at offset: Int) -> T {
    var value: T = 0
    for step in 0..<MemoryLayout<T>.size {
        value |= T(bytes[offset + step]) << (8 * step)
    }
    return value
}
