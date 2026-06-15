import Foundation
import Compression

/// Decompression and byte-reading helpers shared by the recorded (`.r3d` file)
/// and live (USB stream) paths — both carry the same LZFSE-compressed float32
/// depth.
enum Record3DCodec {

    /// Decompress an LZFSE blob (the depth and confidence buffers) into raw bytes.
    static func lzfseDecompress(_ src: Data) -> Data? {
        guard !src.isEmpty else { return nil }
        let capacity = max(8 * 1024 * 1024, src.count * 16)
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return src.withUnsafeBytes { s -> Int in
                guard let sBase = s.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstBase, capacity, sBase, src.count,
                                                 nil, COMPRESSION_LZFSE)
            }
        }
        guard written > 0 else { return nil }
        out.removeSubrange(written..<out.count)
        return out
    }

    /// Reinterpret little-endian float32 `data` as `[Float]` (via an aligned copy,
    /// so there's no alignment assumption on the source).
    static func floats(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.stride
        guard count > 0 else { return [] }
        var floats = [Float](repeating: 0, count: count)
        _ = floats.withUnsafeMutableBytes { data.copyBytes(to: $0, count: count * 4) }
        return floats
    }
}
