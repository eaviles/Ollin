import Foundation
#if canImport(Compression)
import Compression
#endif

/// A minimal ZIP writer, the counterpart of the reader `.usdz` packages are
/// opened with.
///
/// It writes what a package format needs and nothing else: one flat list of
/// entries, no directories of their own, no ZIP64, no encryption. Each entry is
/// deflated when that makes it smaller and stored when it does not, both of
/// which every reader handles.
///
/// Output is deterministic. Timestamps are fixed rather than taken from the
/// clock, so writing the same content twice gives the same bytes, and a
/// generated model can be compared or committed like any other artifact.
enum ZipWriter {

    /// The entries packed into one archive, in the order given.
    static func package(_ entries: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var directory = Data()
        var offsets: [Int] = []

        for entry in entries {
            offsets.append(output.count)
            let name = Array(entry.name.utf8)
            let crc = crc32(entry.data)
            let stored = deflate(entry.data)
            let method: UInt16 = stored == nil ? 0 : 8
            let payload = stored ?? entry.data

            output.append(littleEndian: UInt32(0x0403_4b50))   // local file header
            output.append(littleEndian: UInt16(20))            // version needed
            output.append(littleEndian: UInt16(0))             // flags
            output.append(littleEndian: method)
            output.append(littleEndian: Self.time)
            output.append(littleEndian: Self.date)
            output.append(littleEndian: crc)
            output.append(littleEndian: UInt32(payload.count))
            output.append(littleEndian: UInt32(entry.data.count))
            output.append(littleEndian: UInt16(name.count))
            output.append(littleEndian: UInt16(0))             // extra length
            output.append(contentsOf: name)
            output.append(payload)

            directory.append(littleEndian: UInt32(0x0201_4b50))  // central directory
            directory.append(littleEndian: UInt16(20))           // version made by
            directory.append(littleEndian: UInt16(20))           // version needed
            directory.append(littleEndian: UInt16(0))            // flags
            directory.append(littleEndian: method)
            directory.append(littleEndian: Self.time)
            directory.append(littleEndian: Self.date)
            directory.append(littleEndian: crc)
            directory.append(littleEndian: UInt32(payload.count))
            directory.append(littleEndian: UInt32(entry.data.count))
            directory.append(littleEndian: UInt16(name.count))
            directory.append(littleEndian: UInt16(0))            // extra length
            directory.append(littleEndian: UInt16(0))            // comment length
            directory.append(littleEndian: UInt16(0))            // starting disk
            directory.append(littleEndian: UInt16(0))            // internal attributes
            directory.append(littleEndian: UInt32(0))            // external attributes
            directory.append(littleEndian: UInt32(offsets[offsets.count - 1]))
            directory.append(contentsOf: name)
        }

        let directoryOffset = output.count
        output.append(directory)
        output.append(littleEndian: UInt32(0x0605_4b50))          // end of central directory
        output.append(littleEndian: UInt16(0))                    // this disk
        output.append(littleEndian: UInt16(0))                    // disk the directory starts on
        output.append(littleEndian: UInt16(entries.count))
        output.append(littleEndian: UInt16(entries.count))
        output.append(littleEndian: UInt32(directory.count))
        output.append(littleEndian: UInt32(directoryOffset))
        output.append(littleEndian: UInt16(0))                    // comment length
        return output
    }

    /// Midnight on 1 January 1980, the earliest a ZIP can express, packed the
    /// way the format wants it. Fixed so the output stays reproducible.
    private static let time: UInt16 = 0
    private static let date: UInt16 = (1 << 5) | 1

    /// `data` as raw DEFLATE, or `nil` when compressing does not pay (which the
    /// encoder reports by declining to fit inside a buffer the same size as its
    /// input). The caller then stores it instead.
    private static func deflate(_ data: Data) -> Data? {
        #if canImport(Compression)
        guard !data.isEmpty else { return nil }
        var out = Data(count: data.count)
        let n = out.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, data.count, srcBase, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0, n < data.count else { return nil }
        return out.prefix(n)
        #else
        return nil
        #endif
    }

    /// The CRC-32 a ZIP entry carries, built from the standard reflected table.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = {
        (0 ..< 256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0 ..< 8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
