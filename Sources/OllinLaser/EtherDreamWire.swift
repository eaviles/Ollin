import Foundation
import Ollin

/// The wire format of a network laser DAC, written from its published
/// protocol. Nothing here opens a socket: these are the bytes, so they can be
/// checked against the specification a byte at a time.
///
/// Two facts run through all of it. Every multi-byte value is **little-endian**
/// (the opposite of the ILDA file's), and every command the host sends gets one
/// response back, which carries the DAC's whole status with it. That status is
/// how the host knows whether to send more points, which is the entire job of
/// keeping a laser fed.
public enum EtherDreamWire {

    /// The TCP port the DAC listens on for commands.
    public static let controlPort = 7765

    /// The UDP port the DAC announces itself on, once a second.
    public static let broadcastPort = 7654

    /// The bytes of a status block, and of the response that carries one.
    static let statusSize = 20
    static let responseSize = 22
    static let broadcastSize = 36
    static let pointSize = 18

    // MARK: Commands

    /// Ask for a status reply and nothing else.
    public static func ping() -> Data { Data([0x3F]) }             // '?'

    /// Move the DAC from idle to prepared, ready to be given points.
    public static func prepare() -> Data { Data([0x70]) }          // 'p'

    /// Start playing at `pointsPerSecond`. The low water mark the command also
    /// carries is unused by the DAC, so it goes out as zero.
    public static func begin(pointsPerSecond: Int) -> Data {
        var data = Data([0x62])                                    // 'b'
        data.append(littleEndian: UInt16(0))
        data.append(littleEndian: UInt32(clamping: pointsPerSecond))
        return data
    }

    /// Change the point rate at the next point boundary. The command byte is
    /// `0x74`: the published table names it after a letter that does not match
    /// that byte, and the byte is what the hardware reads.
    public static func queueRateChange(pointsPerSecond: Int) -> Data {
        var data = Data([0x74])
        data.append(littleEndian: UInt32(clamping: pointsPerSecond))
        return data
    }

    /// Hand over points to play. The count is capped at what one command can
    /// carry; the caller sends the rest in the next one.
    public static func write(_ points: [LaserPoint]) -> Data {
        let count = min(points.count, Int(UInt16.max))
        var data = Data([0x64])                                    // 'd'
        data.append(littleEndian: UInt16(count))
        data.reserveCapacity(3 + count * pointSize)
        for point in points.prefix(count) { data.append(encode(point)) }
        return data
    }

    /// Stop playing and return to idle, keeping the connection.
    public static func stop() -> Data { Data([0x73]) }             // 's'

    /// Stop everything now. The DAC will refuse to play again until the stop
    /// is cleared.
    public static func emergencyStop() -> Data { Data([0x00]) }

    /// Clear a stop condition.
    public static func clearEmergencyStop() -> Data { Data([0x63]) }   // 'c'

    // MARK: Points

    /// One point as the DAC's own 18 bytes: a control word, the position, and
    /// the color channels at 16 bits each.
    public static func encode(_ point: LaserPoint) -> Data {
        var data = Data(capacity: pointSize)
        data.append(littleEndian: UInt16(0))                       // control
        data.append(littleEndian: coordinate(point.position.x))
        data.append(littleEndian: coordinate(point.position.y))
        let color = point.isBlanked ? Color.black : point.color
        let r = channel(color.red), g = channel(color.green), b = channel(color.blue)
        data.append(littleEndian: r)
        data.append(littleEndian: g)
        data.append(littleEndian: b)
        // The intensity output drives projectors that modulate brightness apart
        // from color; the brightest channel is what such a projector should be
        // asked for, so the two ways of wiring a projector agree.
        data.append(littleEndian: max(r, max(g, b)))
        data.append(littleEndian: UInt16(0))                       // u1
        data.append(littleEndian: UInt16(0))                       // u2
        return data
    }

    /// A field-unit coordinate on the DAC's signed scale.
    static func coordinate(_ value: Double) -> Int16 {
        let scaled = (min(max(value, -1), 1) * 32767).rounded()
        return Int16(min(max(scaled, -32768), 32767))
    }

    /// A color channel at 16 bits.
    static func channel(_ value: Double) -> UInt16 {
        UInt16((min(max(value, 0), 1) * 65535).rounded())
    }
}

// MARK: - What comes back

/// What the DAC says about itself: the same block rides every response and
/// every announcement it broadcasts.
public struct EtherDreamStatus: Equatable, Sendable {

    /// Whether the light engine is ready, warming, cooling, or stopped.
    public enum LightEngine: UInt8, Sendable {
        case ready = 0, warmup = 1, cooldown = 2, emergencyStop = 3
    }

    /// Whether the DAC is idle, prepared, or playing.
    public enum Playback: UInt8, Sendable {
        case idle = 0, prepared = 1, playing = 2
    }

    public var protocolVersion: UInt8
    public var lightEngine: LightEngine
    public var playback: Playback
    public var source: UInt8
    public var lightEngineFlags: UInt16
    public var playbackFlags: UInt16
    public var sourceFlags: UInt16

    /// How many points the DAC still has to play. This is the number a host
    /// watches: keep it up and the picture holds, let it reach zero and the
    /// beam stops where it stood.
    public var bufferFullness: Int

    /// The rate the DAC is playing at, in points per second.
    public var pointRate: Int

    /// How many points it has played since it started.
    public var pointCount: Int

    /// Read a status block from `data` at `offset`, or `nil` when the bytes run
    /// out or a state is one this protocol version does not define.
    public static func decode(_ data: Data, at offset: Int = 0) -> EtherDreamStatus? {
        guard data.count >= offset + EtherDreamWire.statusSize else { return nil }
        let bytes = [UInt8](data[data.startIndex + offset ..< data.startIndex + offset + EtherDreamWire.statusSize])
        guard let engine = LightEngine(rawValue: bytes[1]),
              let playback = Playback(rawValue: bytes[2]) else { return nil }
        func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
        }
        return EtherDreamStatus(protocolVersion: bytes[0], lightEngine: engine, playback: playback,
                                source: bytes[3], lightEngineFlags: u16(4), playbackFlags: u16(6),
                                sourceFlags: u16(8), bufferFullness: Int(u16(10)),
                                pointRate: Int(u32(12)), pointCount: Int(u32(16)))
    }

    /// The same 20 bytes, written out. Only a DAC sends these, so this side of
    /// the codec exists to be checked against the other one, and to stand a
    /// DAC in for itself in a test.
    func encode() -> Data {
        var data = Data(capacity: EtherDreamWire.statusSize)
        data.append(protocolVersion)
        data.append(lightEngine.rawValue)
        data.append(playback.rawValue)
        data.append(source)
        data.append(littleEndian: lightEngineFlags)
        data.append(littleEndian: playbackFlags)
        data.append(littleEndian: sourceFlags)
        data.append(littleEndian: UInt16(clamping: bufferFullness))
        data.append(littleEndian: UInt32(clamping: pointRate))
        data.append(littleEndian: UInt32(clamping: pointCount))
        return data
    }

    /// A status with nothing happening: what a DAC sitting idle reports.
    static var idle: EtherDreamStatus {
        EtherDreamStatus(protocolVersion: 0, lightEngine: .ready, playback: .idle, source: 0,
                         lightEngineFlags: 0, playbackFlags: 0, sourceFlags: 0,
                         bufferFullness: 0, pointRate: 0, pointCount: 0)
    }
}

/// One reply to one command.
public struct EtherDreamResponse: Equatable, Sendable {

    /// What the DAC made of the command.
    public enum Code: UInt8, Sendable {
        /// The command was accepted.
        case ack = 0x61              // 'a'
        /// The point buffer is full: send the same points again later.
        case full = 0x46             // 'F'
        /// The command made no sense in the DAC's current state.
        case invalid = 0x49          // 'I'
        /// The DAC is stopped and will refuse everything until it is cleared.
        case stopped = 0x21          // '!'
    }

    public var code: Code
    /// The command byte this answers.
    public var command: UInt8
    public var status: EtherDreamStatus

    /// Read a response from the head of `data`, or `nil` when it is short or
    /// carries a code this protocol does not define.
    public static func decode(_ data: Data) -> EtherDreamResponse? {
        guard data.count >= EtherDreamWire.responseSize else { return nil }
        let bytes = [UInt8](data.prefix(2))
        guard let code = Code(rawValue: bytes[0]),
              let status = EtherDreamStatus.decode(data, at: 2) else { return nil }
        return EtherDreamResponse(code: code, command: bytes[1], status: status)
    }

    /// The same 22 bytes, written out (see `EtherDreamStatus.encode`).
    func encode() -> Data {
        var data = Data(capacity: EtherDreamWire.responseSize)
        data.append(code.rawValue)
        data.append(command)
        data.append(status.encode())
        return data
    }
}

/// A DAC that announced itself on the network.
public struct EtherDreamDevice: Equatable, Sendable {

    /// The address to connect to.
    public var host: String

    /// The hardware address the announcement carried, as `00:11:22:33:44:55`.
    public var macAddress: String

    public var hardwareRevision: Int
    public var softwareRevision: Int

    /// How many points the DAC can hold. A host keeps its buffer somewhere
    /// under this and tops it up as it drains.
    public var bufferCapacity: Int

    /// The fastest point rate the DAC will accept.
    public var maximumPointRate: Int

    /// What it was doing when it announced itself.
    public var status: EtherDreamStatus

    /// Read an announcement, or `nil` when the datagram is not one.
    public static func decode(_ data: Data, host: String) -> EtherDreamDevice? {
        guard data.count >= EtherDreamWire.broadcastSize else { return nil }
        let bytes = [UInt8](data.prefix(EtherDreamWire.broadcastSize))
        func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 {
            UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
        }
        guard let status = EtherDreamStatus.decode(data, at: 16) else { return nil }
        let mac = bytes[0..<6].map { String(format: "%02x", $0) }.joined(separator: ":")
        return EtherDreamDevice(host: host, macAddress: mac,
                                hardwareRevision: Int(u16(6)), softwareRevision: Int(u16(8)),
                                bufferCapacity: Int(u16(10)), maximumPointRate: Int(u32(12)),
                                status: status)
    }

    /// The same 36 bytes, written out (see `EtherDreamStatus.encode`).
    func encode() -> Data {
        var data = Data(capacity: EtherDreamWire.broadcastSize)
        let mac = macAddress.components(separatedBy: ":").compactMap { UInt8($0, radix: 16) }
        data.append(contentsOf: (mac + Array(repeating: UInt8(0), count: 6)).prefix(6))
        data.append(littleEndian: UInt16(clamping: hardwareRevision))
        data.append(littleEndian: UInt16(clamping: softwareRevision))
        data.append(littleEndian: UInt16(clamping: bufferCapacity))
        data.append(littleEndian: UInt32(clamping: maximumPointRate))
        data.append(status.encode())
        return data
    }
}

extension Data {
    mutating func append(littleEndian value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func append(littleEndian value: Int16) {
        append(littleEndian: UInt16(bitPattern: value))
    }

    mutating func append(littleEndian value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
