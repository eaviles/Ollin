import Foundation

/// An ArtDmx packet: one universe of DMX data in Art-Net's wire format,
/// written from the published Art-Net 4 specification.
///
/// The universe number is Art-Net's 15-bit Port-Address (net, sub-net, and
/// universe switches packed into one number, 1 to 32767; 0 exists but the
/// spec deprecates it). Decoding is total: a malformed datagram returns `nil`,
/// never a trap, and unknown opcodes are simply not this packet.
public struct ArtDMXPacket: Equatable, Sendable {

    /// The one UDP port Art-Net uses, source and destination (0x1936).
    public static let port = 6454

    /// The OpOutput / ArtDmx opcode.
    static let opCode: UInt16 = 0x5000

    /// The protocol revision this implementation writes.
    static let protocolVersion: UInt8 = 14

    /// The 8-byte packet ID that opens every Art-Net packet ("Art-Net\0").
    static let id: [UInt8] = [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00]

    /// The 15-bit Port-Address the data is for.
    public var universe: Int

    /// Per-universe packet counter, 1 to 255 wrapping; 0 means sequencing is
    /// disabled and the receiver takes packets as they come.
    public var sequence: UInt8

    /// The physical input port the data came from; 0 for generated data.
    public var physical: UInt8

    /// The DMX channel data, 1 to 512 bytes (padded to an even length on the
    /// wire, as the spec asks).
    public var channels: [UInt8]

    public init(universe: Int, channels: [UInt8], sequence: UInt8 = 0, physical: UInt8 = 0) {
        self.universe = universe
        self.channels = channels
        self.sequence = sequence
        self.physical = physical
    }

    /// The packet as wire bytes.
    public func encode() -> Data {
        var payload = Array(channels.prefix(512))
        if payload.isEmpty { payload = [0, 0] }
        if payload.count % 2 != 0 { payload.append(0) }

        var bytes = [UInt8]()
        bytes.reserveCapacity(18 + payload.count)
        bytes.append(contentsOf: Self.id)
        // OpCode goes low byte first; the protocol revision high byte first.
        bytes.append(UInt8(Self.opCode & 0xFF))
        bytes.append(UInt8(Self.opCode >> 8))
        bytes.append(0)
        bytes.append(Self.protocolVersion)
        bytes.append(sequence)
        bytes.append(physical)
        bytes.append(UInt8(universe & 0xFF))          // SubUni: low byte of the Port-Address
        bytes.append(UInt8((universe >> 8) & 0x7F))   // Net: top 7 bits
        bytes.append(UInt8(payload.count >> 8))       // Length, high byte first
        bytes.append(UInt8(payload.count & 0xFF))
        bytes.append(contentsOf: payload)
        return Data(bytes)
    }

    /// Decodes a datagram, or returns `nil` for anything that isn't a
    /// well-formed ArtDmx packet.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 18 else { return nil }
        guard Array(bytes[0..<8]) == Self.id else { return nil }
        let opCode = UInt16(bytes[8]) | (UInt16(bytes[9]) << 8)
        guard opCode == Self.opCode else { return nil }
        let length = Int(bytes[16]) << 8 | Int(bytes[17])
        guard length >= 1, length <= 512, bytes.count >= 18 + length else { return nil }
        sequence = bytes[12]
        physical = bytes[13]
        universe = Int(bytes[14]) | (Int(bytes[15] & 0x7F) << 8)
        channels = Array(bytes[18..<(18 + length)])
    }
}
