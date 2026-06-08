import Foundation

// The OSC 1.0 wire format, written from the specification rather than ported from
// any library. Every value is big-endian; strings and blobs are null-padded to
// 4-byte boundaries; a packet is either a message (address + ",tags" + args) or a
// bundle ("#bundle" + time tag + size-prefixed elements).
//
// Decoding is deliberately total: any malformed or truncated datagram yields
// `nil` rather than trapping, since the bytes come straight off the network.

// MARK: - Encoding

extension OSCPacket {
    /// The packet's bytes, ready to put in a datagram.
    public func encode() -> Data {
        switch self {
        case .message(let message): return message.encode()
        case .bundle(let bundle): return bundle.encode()
        }
    }
}

extension OSCMessage {
    /// The message's OSC bytes.
    public func encode() -> Data {
        var data = Data()
        OSCCoding.writeString(address, into: &data)
        var tags = ","
        for argument in arguments { tags.append(argument.typeTag) }
        OSCCoding.writeString(tags, into: &data)
        for argument in arguments {
            switch argument {
            case .int(let value): OSCCoding.writeUInt32(UInt32(bitPattern: value), into: &data)
            case .float(let value): OSCCoding.writeUInt32(value.bitPattern, into: &data)
            case .string(let value): OSCCoding.writeString(value, into: &data)
            case .blob(let value): OSCCoding.writeBlob(value, into: &data)
            case .double(let value): OSCCoding.writeUInt64(value.bitPattern, into: &data)
            case .int64(let value): OSCCoding.writeUInt64(UInt64(bitPattern: value), into: &data)
            case .bool, .null, .impulse: break   // carried by the tag alone
            }
        }
        return data
    }
}

extension OSCBundle {
    /// The bundle's OSC bytes.
    public func encode() -> Data {
        var data = Data()
        OSCCoding.writeString("#bundle", into: &data)
        OSCCoding.writeUInt64(timeTag.raw, into: &data)
        for element in elements {
            let bytes = element.encode()
            OSCCoding.writeUInt32(UInt32(truncatingIfNeeded: bytes.count), into: &data)
            data.append(bytes)
        }
        return data
    }
}

// MARK: - Decoding

extension OSCPacket {
    /// Decodes a packet from a datagram's bytes, or `nil` if they aren't valid
    /// OSC (truncated, an unknown type tag, a missing terminator, …).
    public init?(data: Data) {
        var reader = OSCCoding.ByteReader(Array(data))
        guard let packet = OSCCoding.decodePacket(&reader) else { return nil }
        self = packet
    }
}

extension OSCMessage {
    /// Decodes a single message from a datagram, or `nil` if the bytes are a
    /// bundle or aren't valid OSC.
    public init?(data: Data) {
        guard case .message(let message) = OSCPacket(data: data) else { return nil }
        self = message
    }
}

// MARK: - Wire helpers

enum OSCCoding {

    // Strings: UTF-8 bytes, a null terminator, then null padding to a multiple of
    // four. A length already on a 4-byte boundary still gains a full 4 nulls, so
    // there is always at least one terminator.
    static func writeString(_ string: String, into data: inout Data) {
        var bytes = Array(string.utf8)
        bytes.append(0)
        while bytes.count % 4 != 0 { bytes.append(0) }
        data.append(contentsOf: bytes)
    }

    // Blobs: a big-endian int32 length, the bytes, then null padding to 4.
    static func writeBlob(_ blob: Data, into data: inout Data) {
        writeUInt32(UInt32(truncatingIfNeeded: blob.count), into: &data)
        data.append(blob)
        var padding = (4 - (blob.count % 4)) % 4
        while padding > 0 { data.append(0); padding -= 1 }
    }

    static func writeUInt32(_ value: UInt32, into data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    static func writeUInt64(_ value: UInt64, into data: inout Data) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    /// A bounds-checked cursor over a byte buffer. Every read returns `nil` rather
    /// than trapping when the buffer runs short.
    struct ByteReader {
        let bytes: [UInt8]
        var offset: Int = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var remaining: Int { bytes.count - offset }

        mutating func readUInt32() -> UInt32? {
            guard remaining >= 4 else { return nil }
            var value: UInt32 = 0
            for i in 0..<4 { value = (value << 8) | UInt32(bytes[offset + i]) }
            offset += 4
            return value
        }

        mutating func readUInt64() -> UInt64? {
            guard remaining >= 8 else { return nil }
            var value: UInt64 = 0
            for i in 0..<8 { value = (value << 8) | UInt64(bytes[offset + i]) }
            offset += 8
            return value
        }

        mutating func readString() -> String? {
            var end = offset
            while end < bytes.count && bytes[end] != 0 { end += 1 }
            guard end < bytes.count else { return nil }   // terminator required
            let contentLength = end - offset
            let total = contentLength + (4 - contentLength % 4)   // content + ≥1 null, padded to 4
            guard offset + total <= bytes.count else { return nil }
            let content = bytes[offset..<end]
            offset += total
            return String(decoding: content, as: UTF8.self)
        }

        mutating func readBlob() -> Data? {
            guard let size = readUInt32() else { return nil }
            let length = Int(size)
            let padding = (4 - (length % 4)) % 4
            guard length >= 0, remaining >= length + padding else { return nil }
            let slice = bytes[offset..<offset + length]
            offset += length + padding
            return Data(slice)
        }

        mutating func readBytes(_ count: Int) -> [UInt8]? {
            guard count >= 0, remaining >= count else { return nil }
            let slice = Array(bytes[offset..<offset + count])
            offset += count
            return slice
        }
    }

    static func decodePacket(_ reader: inout ByteReader) -> OSCPacket? {
        guard let head = reader.readString() else { return nil }
        if head == "#bundle" {
            return decodeBundle(&reader).map { .bundle($0) }
        }
        return decodeMessage(address: head, &reader).map { .message($0) }
    }

    private static func decodeBundle(_ reader: inout ByteReader) -> OSCBundle? {
        guard let timeRaw = reader.readUInt64() else { return nil }
        var elements: [OSCPacket] = []
        while reader.remaining > 0 {
            guard let size = reader.readUInt32(),
                  let elementBytes = reader.readBytes(Int(size)) else { return nil }
            var subReader = ByteReader(elementBytes)
            guard let element = decodePacket(&subReader) else { return nil }
            elements.append(element)
        }
        return OSCBundle(OSCTimeTag(raw: timeRaw), elements)
    }

    private static func decodeMessage(address: String, _ reader: inout ByteReader) -> OSCMessage? {
        guard let tagString = reader.readString(), tagString.first == "," else { return nil }
        var arguments: [OSCArgument] = []
        for tag in tagString.dropFirst() {
            switch tag {
            case "i":
                guard let value = reader.readUInt32() else { return nil }
                arguments.append(.int(Int32(bitPattern: value)))
            case "f":
                guard let value = reader.readUInt32() else { return nil }
                arguments.append(.float(Float(bitPattern: value)))
            case "s":
                guard let value = reader.readString() else { return nil }
                arguments.append(.string(value))
            case "b":
                guard let value = reader.readBlob() else { return nil }
                arguments.append(.blob(value))
            case "h":
                guard let value = reader.readUInt64() else { return nil }
                arguments.append(.int64(Int64(bitPattern: value)))
            case "d":
                guard let value = reader.readUInt64() else { return nil }
                arguments.append(.double(Double(bitPattern: value)))
            case "T": arguments.append(.bool(true))
            case "F": arguments.append(.bool(false))
            case "N": arguments.append(.null)
            case "I": arguments.append(.impulse)
            default: return nil   // unknown tag: its byte width is unknowable
            }
        }
        return OSCMessage(address, arguments: arguments)
    }
}
