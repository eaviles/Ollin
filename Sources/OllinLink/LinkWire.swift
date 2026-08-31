import Foundation

/// Eight random bytes naming a node for the life of one `start()`. A session
/// is named by the id of its founding node. Wire order is lexicographic over
/// the bytes, which equals numeric order of the big-endian value held here.
struct LinkNodeId: Hashable, Comparable, CustomStringConvertible {
    var raw: UInt64

    static func random() -> LinkNodeId {
        LinkNodeId(raw: UInt64.random(in: .min ... .max))
    }

    static func < (a: LinkNodeId, b: LinkNodeId) -> Bool { a.raw < b.raw }

    var description: String { String(format: "%016llx", raw) }
}

/// An IPv4 address and port. `address` holds the four wire bytes as one
/// big-endian-ordered number, so `10.0.1.33` is `0x0A00_0121`.
struct LinkEndpoint: Hashable, CustomStringConvertible {
    var address: UInt32
    var port: UInt16

    var description: String {
        let a = (address >> 24) & 255, b = (address >> 16) & 255
        let c = (address >> 8) & 255, d = address & 255
        return "\(a).\(b).\(c).\(d):\(port)"
    }
}

/// The parsed entries of one datagram payload. Every field is optional
/// because the payload is a sequence of tagged entries: unknown keys are
/// skipped over their declared size, a known key with an unexpected size is
/// skipped the same way, and a missing entry leaves its field `nil`.
struct LinkPayload: Equatable {
    /// The session timeline, in the ghost clock frame.
    var timeline: LinkTimeline?
    var session: LinkNodeId?
    var startStop: LinkStartStop?
    var measurementEndpoint: LinkEndpoint?
    var hostTimeMicros: Int64?
    var ghostTimeMicros: Int64?
    var previousGhostTimeMicros: Int64?
}

enum LinkPayloadKey {
    static let timeline = LinkWire.fourCC("tmln")
    static let session = LinkWire.fourCC("sess")
    static let startStop = LinkWire.fourCC("stst")
    static let measurementEndpoint = LinkWire.fourCC("mep4")
    static let hostTime = LinkWire.fourCC("__ht")
    static let ghostTime = LinkWire.fourCC("__gt")
    static let previousGhostTime = LinkWire.fourCC("_pgt")
}

/// Discovery message types; the raw values are the wire bytes.
enum LinkDiscoveryKind: UInt8 {
    case alive = 1
    case response = 2
    case byeBye = 3
}

struct LinkDiscoveryMessage {
    var kind: LinkDiscoveryKind
    /// Seconds this announcement stays valid for; peers expire past it.
    var ttl: UInt8
    var sender: LinkNodeId
    var payload: LinkPayload
}

/// Measurement message types; the raw values are the wire bytes.
enum LinkMeasurementKind: UInt8 {
    case ping = 1
    case pong = 2
}

/// Encoding and parsing for the two datagram families: discovery (`_asdp_`,
/// over the multicast group) and measurement (`_link_`, unicast ping/pong).
/// Both share one payload format: `key(u32 BE) | size(u32 BE) | value`
/// entries, all integers big-endian. Parsers are total: anything malformed
/// returns `nil` (the datagram is ignored), never a trap.
enum LinkWire {
    static let discoveryHeader: [UInt8] = Array("_asdp_v".utf8) + [1]
    static let measurementHeader: [UInt8] = Array("_link_v".utf8) + [1]

    /// Encoders must stay under 512 bytes; a full IPv4 state message is 107.
    static let maxDatagram = 511

    static func fourCC(_ text: String) -> UInt32 {
        precondition(text.utf8.count == 4)
        return text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    // MARK: Payload

    static func encodeTimeline(_ timeline: LinkTimeline, into data: inout Data) {
        data.linkAppendBE(LinkPayloadKey.timeline)
        data.linkAppendBE(UInt32(24))
        data.linkAppendBE(timeline.tempo.wire)
        data.linkAppendBE(timeline.anchorMicroBeats)
        data.linkAppendBE(timeline.anchorMicros)
    }

    static func encodeSession(_ session: LinkNodeId, into data: inout Data) {
        data.linkAppendBE(LinkPayloadKey.session)
        data.linkAppendBE(UInt32(8))
        data.linkAppendBE(session.raw)
    }

    static func encodeStartStop(_ startStop: LinkStartStop, into data: inout Data) {
        data.linkAppendBE(LinkPayloadKey.startStop)
        data.linkAppendBE(UInt32(17))
        data.append(startStop.isPlaying ? 1 : 0)
        data.linkAppendBE(startStop.microBeats)
        data.linkAppendBE(startStop.timestampMicros)
    }

    static func encodeMeasurementEndpoint(_ endpoint: LinkEndpoint, into data: inout Data) {
        data.linkAppendBE(LinkPayloadKey.measurementEndpoint)
        data.linkAppendBE(UInt32(6))
        data.linkAppendBE(endpoint.address)
        data.linkAppendBE(endpoint.port)
    }

    static func encodeMicros(_ key: UInt32, _ micros: Int64, into data: inout Data) {
        data.linkAppendBE(key)
        data.linkAppendBE(UInt32(8))
        data.linkAppendBE(micros)
    }

    /// Parses a payload region. `nil` means malformed: a truncated entry
    /// header, or a declared size overrunning the datagram.
    static func parsePayload(_ bytes: ArraySlice<UInt8>) -> LinkPayload? {
        var payload = LinkPayload()
        var reader = LinkByteReader(bytes)
        while reader.remaining > 0 {
            guard let key = reader.u32BE(), let size = reader.u32BE(),
                  let value = reader.take(Int(size)) else { return nil }
            var entry = LinkByteReader(value)
            switch (key, size) {
            case (LinkPayloadKey.timeline, 24):
                if let tempo = entry.i64BE(), let beat = entry.i64BE(), let time = entry.i64BE() {
                    payload.timeline = LinkTimeline(
                        tempo: LinkTempo(wire: tempo),
                        anchorMicroBeats: beat,
                        anchorMicros: time
                    )
                }
            case (LinkPayloadKey.session, 8):
                if let raw = entry.u64BE() { payload.session = LinkNodeId(raw: raw) }
            case (LinkPayloadKey.startStop, 17):
                if let flag = entry.u8(), let beats = entry.i64BE(), let stamp = entry.i64BE() {
                    payload.startStop = LinkStartStop(
                        isPlaying: flag != 0,
                        microBeats: beats,
                        timestampMicros: stamp
                    )
                }
            case (LinkPayloadKey.measurementEndpoint, 6):
                if let address = entry.u32BE(), let port = entry.u16BE() {
                    payload.measurementEndpoint = LinkEndpoint(address: address, port: port)
                }
            case (LinkPayloadKey.hostTime, 8):
                payload.hostTimeMicros = entry.i64BE()
            case (LinkPayloadKey.ghostTime, 8):
                payload.ghostTimeMicros = entry.i64BE()
            case (LinkPayloadKey.previousGhostTime, 8):
                payload.previousGhostTimeMicros = entry.i64BE()
            default:
                break   // unknown key, or a known key at an unexpected size: skip
            }
        }
        return payload
    }

    // MARK: Discovery datagrams

    /// Header layout: 8 magic bytes, kind, ttl, a group id (two bytes, zero in
    /// this protocol version), then the 8-byte sender id and the payload.
    static func encodeDiscovery(kind: LinkDiscoveryKind, ttl: UInt8, sender: LinkNodeId, payload: Data) -> Data {
        var data = Data(capacity: 20 + payload.count)
        data.append(contentsOf: discoveryHeader)
        data.append(kind.rawValue)
        data.append(ttl)
        data.linkAppendBE(UInt16(0))
        data.linkAppendBE(sender.raw)
        data.append(payload)
        assert(data.count <= maxDatagram)
        return data
    }

    /// `nil` means ignore: wrong header, unknown kind, a group id this
    /// version does not speak, or a malformed payload.
    static func parseDiscovery(_ data: Data) -> LinkDiscoveryMessage? {
        let bytes = [UInt8](data)
        guard bytes.count >= 20, Array(bytes[0..<8]) == discoveryHeader,
              let kind = LinkDiscoveryKind(rawValue: bytes[8]) else { return nil }
        let ttl = bytes[9]
        guard bytes[10] == 0, bytes[11] == 0 else { return nil }
        var reader = LinkByteReader(bytes[12...])
        guard let sender = reader.u64BE(),
              let payload = parsePayload(bytes[20...]) else { return nil }
        return LinkDiscoveryMessage(kind: kind, ttl: ttl, sender: LinkNodeId(raw: sender), payload: payload)
    }

    // MARK: Measurement datagrams

    static func encodeMeasurement(kind: LinkMeasurementKind, payload: Data) -> Data {
        var data = Data(capacity: 9 + payload.count)
        data.append(contentsOf: measurementHeader)
        data.append(kind.rawValue)
        data.append(payload)
        assert(data.count <= maxDatagram)
        return data
    }

    /// Returns the kind and the raw payload bytes (the pong must echo the
    /// ping's payload verbatim, so the bytes stay bytes here).
    static func parseMeasurement(_ data: Data) -> (kind: LinkMeasurementKind, payload: Data)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 9, Array(bytes[0..<8]) == measurementHeader,
              let kind = LinkMeasurementKind(rawValue: bytes[8]) else { return nil }
        return (kind, Data(bytes[9...]))
    }
}

/// A cursor over payload bytes; every read is bounds-checked and returns
/// `nil` past the end.
struct LinkByteReader {
    private let bytes: [UInt8]
    private var offset: Int

    init(_ slice: ArraySlice<UInt8>) {
        bytes = Array(slice)
        offset = 0
    }

    var remaining: Int { bytes.count - offset }

    mutating func u8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, remaining >= count else { return nil }
        defer { offset += count }
        return bytes[offset ..< offset + count]
    }

    mutating func u16BE() -> UInt16? {
        guard let raw = take(2) else { return nil }
        return raw.reduce(0) { ($0 << 8) | UInt16($1) }
    }

    mutating func u32BE() -> UInt32? {
        guard let raw = take(4) else { return nil }
        return raw.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    mutating func u64BE() -> UInt64? {
        guard let raw = take(8) else { return nil }
        return raw.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    mutating func i64BE() -> Int64? {
        u64BE().map(Int64.init(bitPattern:))
    }
}

extension Data {
    mutating func linkAppendBE(_ value: UInt16) {
        append(UInt8(value >> 8)); append(UInt8(value & 255))
    }

    mutating func linkAppendBE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func linkAppendBE(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func linkAppendBE(_ value: Int64) {
        linkAppendBE(UInt64(bitPattern: value))
    }
}
