import Foundation

/// An sACN (ANSI E1.31) data packet: one universe of DMX data wrapped in the
/// ACN root, framing, and DMP layers, written from the published standard.
///
/// Everything on the wire is big-endian. Decoding is total: a malformed
/// datagram, a wrong layer vector, or a truncated payload returns `nil`,
/// never a trap. Synchronization and universe-discovery packets are other
/// vectors and simply decode as `nil` here.
public struct SACNDataPacket: Equatable, Sendable {

    /// The standard ACN UDP port, multicast and (by default) unicast.
    public static let port = 5568

    /// The 12-byte ACN packet identifier ("ASC-E1.17" and three nulls).
    static let acnIdentifier: [UInt8] = [
        0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37, 0x00, 0x00, 0x00,
    ]

    static let rootVector: UInt32 = 0x0000_0004      // VECTOR_ROOT_E131_DATA
    static let framingVector: UInt32 = 0x0000_0002   // VECTOR_E131_DATA_PACKET
    static let dmpVector: UInt8 = 0x02               // VECTOR_DMP_SET_PROPERTY

    /// The universe number, 1 to 63999.
    public var universe: Int

    /// The DMX channel data, up to 512 slots (the START code rides separately).
    public var channels: [UInt8]

    /// The DMX START code ahead of the slots; 0 is ordinary dimmer data.
    public var startCode: UInt8

    /// Per-universe packet counter, wrapping through the full byte.
    public var sequence: UInt8

    /// Source priority 0 to 200 (100 default); receivers seeing several
    /// sources on one universe take the highest.
    public var priority: UInt8

    /// The human-readable name of the source, up to 63 bytes of UTF-8.
    public var sourceName: String

    /// The sender's stable component identifier.
    public var cid: UUID

    /// Preview data is for visualizers and must not drive live output.
    public var isPreview: Bool

    /// A source's goodbye: three packets with this bit end a stream without
    /// waiting for the receiver's timeout.
    public var isTerminated: Bool

    /// Whether receivers may leave a synchronized state on their own when
    /// synchronization packets stop arriving.
    public var forcesSynchronization: Bool

    /// The universe synchronization packets arrive on; 0 means unsynchronized.
    public var synchronizationAddress: Int

    public init(
        universe: Int,
        channels: [UInt8],
        sequence: UInt8 = 0,
        priority: UInt8 = 100,
        sourceName: String = "Ollin",
        cid: UUID = UUID(),
        startCode: UInt8 = 0,
        isPreview: Bool = false,
        isTerminated: Bool = false,
        forcesSynchronization: Bool = false,
        synchronizationAddress: Int = 0
    ) {
        self.universe = universe
        self.channels = channels
        self.sequence = sequence
        self.priority = priority
        self.sourceName = sourceName
        self.cid = cid
        self.startCode = startCode
        self.isPreview = isPreview
        self.isTerminated = isTerminated
        self.forcesSynchronization = forcesSynchronization
        self.synchronizationAddress = synchronizationAddress
    }

    /// The IPv4 multicast group a universe's data travels on:
    /// `239.255.<high byte>.<low byte>` of the universe number.
    public static func multicastGroup(universe: Int) -> String {
        "239.255.\((universe >> 8) & 0xFF).\(universe & 0xFF)"
    }

    /// The packet as wire bytes.
    public func encode() -> Data {
        let slots = Array(channels.prefix(512))
        let total = 126 + slots.count

        var bytes = [UInt8]()
        bytes.reserveCapacity(total)

        // Root layer.
        appendUInt16(&bytes, 0x0010)                       // preamble size
        appendUInt16(&bytes, 0x0000)                       // post-amble size
        bytes.append(contentsOf: Self.acnIdentifier)
        appendFlagsLength(&bytes, total - 16)
        appendUInt32(&bytes, Self.rootVector)
        withUnsafeBytes(of: cid.uuid) { bytes.append(contentsOf: $0) }

        // Framing layer.
        appendFlagsLength(&bytes, total - 38)
        appendUInt32(&bytes, Self.framingVector)
        var name = Array(sourceName.utf8.prefix(63))
        name.append(contentsOf: repeatElement(0, count: 64 - name.count))
        bytes.append(contentsOf: name)
        bytes.append(min(priority, 200))
        appendUInt16(&bytes, UInt16(clamping: synchronizationAddress))
        bytes.append(sequence)
        var options: UInt8 = 0
        if isPreview { options |= 1 << 7 }
        if isTerminated { options |= 1 << 6 }
        if forcesSynchronization { options |= 1 << 5 }
        bytes.append(options)
        appendUInt16(&bytes, UInt16(clamping: universe))

        // DMP layer.
        appendFlagsLength(&bytes, total - 115)
        bytes.append(Self.dmpVector)
        bytes.append(0xA1)                                 // address & data type
        appendUInt16(&bytes, 0x0000)                       // first property address
        appendUInt16(&bytes, 0x0001)                       // address increment
        appendUInt16(&bytes, UInt16(1 + slots.count))      // property value count
        bytes.append(startCode)
        bytes.append(contentsOf: slots)
        return Data(bytes)
    }

    /// Decodes a datagram, or returns `nil` for anything that isn't a
    /// well-formed E1.31 data packet.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 126 else { return nil }
        guard readUInt16(bytes, 0) == 0x0010, readUInt16(bytes, 2) == 0x0000 else { return nil }
        guard Array(bytes[4..<16]) == Self.acnIdentifier else { return nil }
        guard readUInt32(bytes, 18) == Self.rootVector else { return nil }
        guard readUInt32(bytes, 40) == Self.framingVector else { return nil }
        guard bytes[117] == Self.dmpVector, bytes[118] == 0xA1 else { return nil }
        guard readUInt16(bytes, 119) == 0x0000, readUInt16(bytes, 121) == 0x0001 else { return nil }
        let count = Int(readUInt16(bytes, 123))
        guard count >= 1, count <= 513, bytes.count >= 125 + count else { return nil }

        var uuid = uuid_t(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &uuid) { $0.copyBytes(from: bytes[22..<38]) }
        cid = UUID(uuid: uuid)
        let nameBytes = bytes[44..<108].prefix { $0 != 0 }
        sourceName = String(decoding: nameBytes, as: UTF8.self)
        priority = bytes[108]
        synchronizationAddress = Int(readUInt16(bytes, 109))
        sequence = bytes[111]
        isPreview = bytes[112] & (1 << 7) != 0
        isTerminated = bytes[112] & (1 << 6) != 0
        forcesSynchronization = bytes[112] & (1 << 5) != 0
        universe = Int(readUInt16(bytes, 113))
        startCode = bytes[125]
        channels = Array(bytes[126..<(125 + count)])
    }
}

// The E1.31 length fields carry 0x7 in the top four bits and the layer's
// length (from its own flags field to the end of what it wraps) in the low 12.
private func appendFlagsLength(_ bytes: inout [UInt8], _ length: Int) {
    appendUInt16(&bytes, 0x7000 | UInt16(length & 0x0FFF))
}

private func appendUInt16(_ bytes: inout [UInt8], _ value: UInt16) {
    bytes.append(UInt8(value >> 8))
    bytes.append(UInt8(value & 0xFF))
}

private func appendUInt32(_ bytes: inout [UInt8], _ value: UInt32) {
    bytes.append(UInt8((value >> 24) & 0xFF))
    bytes.append(UInt8((value >> 16) & 0xFF))
    bytes.append(UInt8((value >> 8) & 0xFF))
    bytes.append(UInt8(value & 0xFF))
}

private func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
}

private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
        | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
}
