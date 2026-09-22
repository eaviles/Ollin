import Compression
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import OllinMutation
@testable import OllinRecord3D

/// The Record3D USB stream frame (a 104-byte header, then a JPEG, an LZFSE
/// depth map, and a confidence map) under the mutation harness, the header
/// and the body decoded as the reader thread decodes them.
@Suite struct Record3DMutationTests {

    static let colorWidth = 8, colorHeight = 6

    static func header(rgb: Int, depth: Int, conf: Int, misc: Int) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 104)
        func u32(_ off: Int, _ v: UInt32) {
            h[off] = UInt8(v & 0xFF); h[off + 1] = UInt8((v >> 8) & 0xFF)
            h[off + 2] = UInt8((v >> 16) & 0xFF); h[off + 3] = UInt8((v >> 24) & 0xFF)
        }
        func f32(_ off: Int, _ v: Float) { u32(off, v.bitPattern) }
        u32(0, 0x0100_0000)
        u32(40, UInt32(rgb)); u32(44, UInt32(depth)); u32(48, UInt32(conf)); u32(52, UInt32(misc))
        f32(60, 5.5); f32(64, 5.5); f32(68, 4); f32(72, 3)
        f32(76, 0); f32(80, 0); f32(84, 0); f32(88, 1)
        f32(92, 0.1); f32(96, 0.2); f32(100, 0.3)
        return h
    }

    static func jpeg() -> [UInt8] {
        let context = CGContext(data: nil, width: colorWidth, height: colorHeight, bitsPerComponent: 8,
                                bytesPerRow: colorWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: colorWidth, height: colorHeight))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return [UInt8](data as Data)
    }

    static func lzfse(_ bytes: [UInt8]) -> [UInt8] {
        let capacity = bytes.count * 2 + 4096
        var out = [UInt8](repeating: 0, count: capacity)
        let written = out.withUnsafeMutableBufferPointer { dst in
            bytes.withUnsafeBufferPointer { src in
                compression_encode_buffer(dst.baseAddress!, capacity, src.baseAddress!, bytes.count,
                                          nil, COMPRESSION_LZFSE)
            }
        }
        return Array(out.prefix(written))
    }

    static func seeds() -> [[UInt8]] {
        let depth: [Float] = (0..<48).map { 0.5 + Float($0) * 0.01 }
        var depthBytes: [UInt8] = []
        for value in depth { withUnsafeBytes(of: value.bitPattern.littleEndian) { depthBytes.append(contentsOf: $0) } }
        let confidence = [UInt8](repeating: 2, count: 48)
        let color = jpeg()
        let depthBlob = lzfse(depthBytes), confidenceBlob = lzfse(confidence)
        let whole = header(rgb: color.count, depth: depthBlob.count, conf: confidenceBlob.count, misc: 2)
            + color + depthBlob + confidenceBlob + [0x7B, 0x7D]
        let bare = header(rgb: color.count, depth: depthBlob.count, conf: 0, misc: 0) + color + depthBlob
        return [whole, bare]
    }

    @Test func aStreamFrame() {
        let report = MutationRun.run("record3d-stream", seeds: Self.seeds(), count: 500) { bytes in
            let data = Data(bytes)
            guard let header = Record3DFrameHeader.parse(data) else { return false }
            let body = data.count > Record3DFrameHeader.byteCount ? data.dropFirst(Record3DFrameHeader.byteCount) : Data()
            guard let box = decodeRecord3DFrame(header: header, body: Data(body), sequence: 1) else { return false }
            _ = box.depthWidth * box.depthHeight
            _ = box.intrinsics
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    @Test func theCodecAlone() {
        let seeds = [Self.lzfse([UInt8](repeating: 9, count: 200)), Self.lzfse(Array(0..<255)), Self.jpeg()]
        let report = MutationRun.run("record3d-codec", seeds: seeds, count: 400) { bytes in
            let data = Data(bytes)
            let inflated = Record3DCodec.lzfseDecompress(data)
            if let inflated { _ = Record3DCodec.floats(from: inflated) }
            _ = Record3DCodec.floats(from: data)
            return inflated != nil
        }
        #expect(report.cases > 0, "\(report)")
    }
}
