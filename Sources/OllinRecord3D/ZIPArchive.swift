import Foundation
import Compression

/// A minimal read-only ZIP reader — enough to pull named entries out of a
/// `.r3d` recording, which is a plain ZIP holding a `metadata` file and a
/// directory of per-frame images.
///
/// Foundation has no public ZIP container API (only the raw `Compression`
/// codecs), so this parses the archive's central directory itself and inflates
/// each entry's bytes. It handles the two methods ZIP files actually use —
/// **stored** (method 0) and **deflate** (method 8, decompressed via
/// `Compression`'s raw-deflate codec) — and reads every size from the central
/// directory, so streamed archives that zero the local-header sizes (a data
/// descriptor) decode fine. ZIP64 is out of scope; a recording never reaches
/// 4 GB.
struct ZIPArchive {

    /// One cataloged entry: its name and where/how its bytes are stored.
    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let bytes: [UInt8]
    private let entries: [String: Entry]

    /// Parse the archive's central directory. Throws `Record3DError.notAnArchive`
    /// if the end-of-central-directory record can't be found.
    init(data: Data) throws {
        bytes = [UInt8](data)
        entries = try Self.readCentralDirectory(bytes)
    }

    /// The names of every entry in the archive.
    var entryNames: [String] { Array(entries.keys) }

    /// The decompressed bytes of the entry named `name` (an exact match, or the
    /// first entry whose path ends in `/name`), or `nil` if absent or undecodable.
    func data(named name: String) -> Data? {
        guard let entry = entries[name]
                ?? entries.first(where: { $0.key == name || $0.key.hasSuffix("/" + name) })?.value
        else { return nil }
        return extract(entry)
    }

    /// Whether an entry named exactly `name` exists.
    func contains(_ name: String) -> Bool { entries[name] != nil }

    // MARK: - Central directory

    private static func readCentralDirectory(_ b: [UInt8]) throws -> [String: Entry] {
        guard let eocd = findEOCD(b) else { throw Record3DError.notAnArchive }
        let count = Int(u16(b, eocd + 10))
        var offset = Int(u32(b, eocd + 16))
        var result: [String: Entry] = [:]
        result.reserveCapacity(count)

        for _ in 0..<count {
            guard offset + 46 <= b.count, u32(b, offset) == 0x0201_4b50 else { break }
            let method = u16(b, offset + 10)
            let compressedSize = Int(u32(b, offset + 20))
            let uncompressedSize = Int(u32(b, offset + 24))
            let nameLen = Int(u16(b, offset + 28))
            let extraLen = Int(u16(b, offset + 30))
            let commentLen = Int(u16(b, offset + 32))
            let localOffset = Int(u32(b, offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLen <= b.count else { break }
            let name = String(decoding: b[nameStart..<nameStart + nameLen], as: UTF8.self)
            result[name] = Entry(method: method, compressedSize: compressedSize,
                                 uncompressedSize: uncompressedSize, localHeaderOffset: localOffset)
            offset = nameStart + nameLen + extraLen + commentLen
        }
        return result
    }

    /// Scan backward for the end-of-central-directory signature (`PK\u{05}\u{06}`),
    /// which sits within the last 64 KB (the max ZIP comment length plus the
    /// 22-byte record).
    private static func findEOCD(_ b: [UInt8]) -> Int? {
        guard b.count >= 22 else { return nil }
        let lowest = max(0, b.count - 22 - 0xFFFF)
        var i = b.count - 22
        while i >= lowest {
            if b[i] == 0x50, b[i + 1] == 0x4B, b[i + 2] == 0x05, b[i + 3] == 0x06 { return i }
            i -= 1
        }
        return nil
    }

    // MARK: - Extraction

    private func extract(_ entry: Entry) -> Data? {
        let lh = entry.localHeaderOffset
        guard lh + 30 <= bytes.count, Self.u32(bytes, lh) == 0x0403_4b50 else { return nil }
        // Local-header name/extra lengths can differ from the central directory's,
        // so the data offset is computed from the local header.
        let nameLen = Int(Self.u16(bytes, lh + 26))
        let extraLen = Int(Self.u16(bytes, lh + 28))
        let dataStart = lh + 30 + nameLen + extraLen
        guard dataStart + entry.compressedSize <= bytes.count else { return nil }
        let raw = Data(bytes[dataStart..<dataStart + entry.compressedSize])

        switch entry.method {
        case 0: return raw                                       // stored
        case 8: return Self.inflate(raw, capacity: entry.uncompressedSize)  // deflate
        default: return nil
        }
    }

    /// Inflate raw DEFLATE `data` (ZIP method 8) into a buffer of `capacity` bytes
    /// (the entry's known uncompressed size).
    private static func inflate(_ data: Data, capacity: Int) -> Data? {
        guard capacity > 0 else { return Data() }
        var out = Data(count: capacity)
        let n = out.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, capacity, srcBase, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        if n != out.count { out.removeSubrange(n..<out.count) }
        return out
    }

    // MARK: - Little-endian reads

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}
