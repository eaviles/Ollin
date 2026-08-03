import Foundation
import Compression

/// The two low-level codecs the usdc crate format layers its sections and
/// compressed arrays over: a chunked LZ4 wrapper and a delta/varint integer
/// coding. Both are reimplemented from the format's published structure.
enum USDLZ4 {

    /// Decompress a crate LZ4 blob. Section blobs state their decompressed
    /// size, so `exact` demands it; integer-coded working buffers only bound
    /// theirs (narrow varints shorten the stream), so they pass `exact: false`
    /// and `capacity` is the worst case.
    ///
    /// The wrapper is one leading chunk-count byte: 0 means the rest is a
    /// single raw LZ4 block; n > 0 means n chunks, each a little-endian
    /// `int32` size followed by that many bytes of raw LZ4 block (used only
    /// past ~2 GB per block). Blocks are the standard LZ4 block format, which
    /// Apple Compression decodes as `COMPRESSION_LZ4_RAW`.
    static func decompress(_ data: Data, capacity: Int, exact: Bool = true) throws -> Data {
        guard let first = data.first else {
            guard capacity == 0 || !exact else { throw USDError.malformed("usdc: empty LZ4 blob") }
            return Data()
        }
        let chunks = Int(first)
        var out = Data()
        if chunks == 0 {
            out = try decodeBlock(data.dropFirst(), capacity: capacity)
        } else {
            out.reserveCapacity(capacity)
            var rest = data.dropFirst()
            for _ in 0..<chunks {
                guard rest.count >= 4 else { throw USDError.malformed("usdc: truncated LZ4 chunk") }
                let size = rest.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
                rest = rest.dropFirst(4)
                guard size >= 0, rest.count >= size else {
                    throw USDError.malformed("usdc: bad LZ4 chunk size")
                }
                out += try decodeBlock(rest.prefix(size), capacity: capacity - out.count)
                rest = rest.dropFirst(size)
            }
        }
        guard !exact || out.count == capacity else {
            throw USDError.malformed("usdc: LZ4 output size mismatch")
        }
        return out
    }

    private static func decodeBlock(_ block: Data, capacity: Int) throws -> Data {
        guard capacity > 0 else { return Data() }
        var out = Data(count: capacity)
        let n = out.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return block.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, capacity, srcBase, block.count,
                                                 nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard n > 0, n <= capacity else { throw USDError.malformed("usdc: LZ4 block decode failed") }
        return out.count == n ? out : out.prefix(n)
    }
}

/// The crate's integer coding: a running sum of deltas, each delta either a
/// shared "common" value or an explicit little-endian signed integer whose
/// width a 2-bit code stream selects (the first integer of each group of four
/// sits in the code byte's low bits). The coded buffer travels LZ4-wrapped.
enum USDIntegerCoding {

    /// Decode `count` 32-bit integers from an LZ4-wrapped coded blob.
    /// Code widths: 0 = the common delta, 1 = int8, 2 = int16, 3 = int32.
    static func decodeInt32(_ data: Data, count: Int) throws -> [Int32] {
        guard count > 0 else { return [] }
        let codesStart = 4
        let vintStart = codesStart + (2 * count + 7) / 8
        let workSize = vintStart + 4 * count
        let buf = try USDLZ4.decompress(data, capacity: workSize, exact: false)
        return try buf.withUnsafeBytes { raw -> [Int32] in
            guard raw.count >= vintStart else { throw USDError.malformed("usdc: short integer blob") }
            let common = raw.loadUnaligned(as: Int32.self)
            var out = [Int32](repeating: 0, count: count)
            var prev: Int32 = 0
            var vint = vintStart
            for i in 0..<count {
                let code = (raw[codesStart + i / 4] >> UInt8(2 * (i % 4))) & 3
                let delta: Int32
                switch code {
                case 0: delta = common
                case 1:
                    guard vint + 1 <= raw.count else { throw USDError.malformed("usdc: integer stream over-read") }
                    delta = Int32(Int8(bitPattern: raw[vint])); vint += 1
                case 2:
                    guard vint + 2 <= raw.count else { throw USDError.malformed("usdc: integer stream over-read") }
                    delta = Int32(raw.loadUnaligned(fromByteOffset: vint, as: Int16.self)); vint += 2
                default:
                    guard vint + 4 <= raw.count else { throw USDError.malformed("usdc: integer stream over-read") }
                    delta = raw.loadUnaligned(fromByteOffset: vint, as: Int32.self); vint += 4
                }
                prev = prev &+ delta
                out[i] = prev
            }
            return out
        }
    }

    /// Decode `count` 64-bit integers. Code widths here are wider than the
    /// 32-bit variant's: 1 = int16, 2 = int32, 3 = int64.
    static func decodeInt64(_ data: Data, count: Int) throws -> [Int64] {
        guard count > 0 else { return [] }
        let codesStart = 8
        let vintStart = codesStart + (2 * count + 7) / 8
        let workSize = vintStart + 8 * count
        let buf = try USDLZ4.decompress(data, capacity: workSize, exact: false)
        return try buf.withUnsafeBytes { raw -> [Int64] in
            guard raw.count >= vintStart else { throw USDError.malformed("usdc: short integer blob") }
            let common = raw.loadUnaligned(as: Int64.self)
            var out = [Int64](repeating: 0, count: count)
            var prev: Int64 = 0
            var vint = vintStart
            for i in 0..<count {
                let code = (raw[codesStart + i / 4] >> UInt8(2 * (i % 4))) & 3
                let delta: Int64
                switch code {
                case 0: delta = common
                case 1:
                    guard vint + 2 <= raw.count else { throw USDError.malformed("usdc: integer stream over-read") }
                    delta = Int64(raw.loadUnaligned(fromByteOffset: vint, as: Int16.self)); vint += 2
                case 2:
                    guard vint + 4 <= raw.count else { throw USDError.malformed("usdc: integer stream over-read") }
                    delta = Int64(raw.loadUnaligned(fromByteOffset: vint, as: Int32.self)); vint += 4
                default:
                    guard vint + 8 <= raw.count else { throw USDError.malformed("usdc: integer stream over-read") }
                    delta = raw.loadUnaligned(fromByteOffset: vint, as: Int64.self); vint += 8
                }
                prev = prev &+ delta
                out[i] = prev
            }
            return out
        }
    }
}
