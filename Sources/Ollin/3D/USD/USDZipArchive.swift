import Foundation
import Compression

/// A minimal read-only ZIP reader for `.usdz` packages, which are plain ZIPs
/// whose entries are stored uncompressed (and 64-byte aligned) by spec.
///
/// Foundation has no public ZIP container API (only the raw `Compression`
/// codecs), so this parses the central directory itself. Stored (method 0)
/// entries are the spec case; deflate (method 8) is handled too for tolerance
/// of out-of-spec packages. Every size is read from the central directory, so
/// streamed archives that zero the local-header sizes decode fine. ZIP64 is
/// out of scope.
struct USDZipArchive {

    /// One catalogued entry: where and how its bytes are stored.
    private struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [Entry]

    /// Whether `data` starts with a ZIP local-file-header signature.
    static func matches(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B
            && data[data.startIndex + 2] == 0x03 && data[data.startIndex + 3] == 0x04
    }

    /// Parse the archive's central directory.
    init(data: Data) throws {
        self.data = data
        entries = try Self.readCentralDirectory(data)
    }

    /// Entry names in central-directory order (the package's authored order).
    var entryNames: [String] { entries.map(\.name) }

    /// The decompressed bytes of the entry named exactly `name`.
    func data(named name: String) -> Data? {
        entries.first { $0.name == name }.flatMap(extract)
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ d: Data) throws -> [Entry] {
        guard let eocd = findEOCD(d) else {
            throw USDError.malformed("usdz: no end-of-central-directory record")
        }
        let count = Int(u16(d, eocd + 10))
        var offset = Int(u32(d, eocd + 16))
        var result: [Entry] = []
        result.reserveCapacity(count)

        for _ in 0..<count {
            guard offset + 46 <= d.count, u32(d, offset) == 0x0201_4b50 else { break }
            let method = u16(d, offset + 10)
            let compressedSize = Int(u32(d, offset + 20))
            let uncompressedSize = Int(u32(d, offset + 24))
            let nameLen = Int(u16(d, offset + 28))
            let extraLen = Int(u16(d, offset + 30))
            let commentLen = Int(u16(d, offset + 32))
            let localOffset = Int(u32(d, offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLen <= d.count else { break }
            let name = String(decoding: d[d.startIndex + nameStart ..< d.startIndex + nameStart + nameLen],
                              as: UTF8.self)
            result.append(Entry(name: name, method: method, compressedSize: compressedSize,
                                uncompressedSize: uncompressedSize, localHeaderOffset: localOffset))
            offset = nameStart + nameLen + extraLen + commentLen
        }
        return result
    }

    /// Scan backward for the end-of-central-directory signature, which sits
    /// within the last 64 KB (max ZIP comment length plus the 22-byte record).
    private static func findEOCD(_ d: Data) -> Int? {
        guard d.count >= 22 else { return nil }
        let lowest = max(0, d.count - 22 - 0xFFFF)
        var i = d.count - 22
        while i >= lowest {
            if u32(d, i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }

    // MARK: - Extraction

    private func extract(_ entry: Entry) -> Data? {
        let lh = entry.localHeaderOffset
        guard lh + 30 <= data.count, Self.u32(data, lh) == 0x0403_4b50 else { return nil }
        // Local-header name/extra lengths can differ from the central
        // directory's (usdz uses the extra field for its 64-byte alignment),
        // so the data offset comes from the local header.
        let nameLen = Int(Self.u16(data, lh + 26))
        let extraLen = Int(Self.u16(data, lh + 28))
        let dataStart = lh + 30 + nameLen + extraLen
        guard dataStart + entry.compressedSize <= data.count else { return nil }
        let raw = data.subdata(in: data.startIndex + dataStart ..< data.startIndex + dataStart + entry.compressedSize)

        switch entry.method {
        case 0: return raw
        case 8: return Self.inflate(raw, capacity: entry.uncompressedSize)
        default: return nil
        }
    }

    /// Inflate raw DEFLATE bytes into a buffer of the known uncompressed size.
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
        guard n == capacity else { return nil }
        return out
    }

    // MARK: - Little-endian reads

    private static func u16(_ d: Data, _ i: Int) -> UInt16 {
        let s = d.startIndex
        return UInt16(d[s + i]) | (UInt16(d[s + i + 1]) << 8)
    }

    private static func u32(_ d: Data, _ i: Int) -> UInt32 {
        let s = d.startIndex
        return UInt32(d[s + i]) | (UInt32(d[s + i + 1]) << 8)
            | (UInt32(d[s + i + 2]) << 16) | (UInt32(d[s + i + 3]) << 24)
    }
}
