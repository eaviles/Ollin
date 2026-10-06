import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The bytes of a synthetic RGBD stream frame, for the two suites that read
/// the frame: the decoder's own tests and the mutation harness.
///
/// A frame on the wire is a 104-byte little-endian header (a magic word, the
/// four body sizes at offsets 40 to 52, the intrinsics at 60 to 72, a rotation
/// at 76 to 88, and a translation at 92 to 100), then a JPEG, an LZFSE depth
/// map, and an LZFSE confidence map. Everything here is built on the spot, so
/// no binary fixture is committed.
package enum Record3DFrameBytes {

    /// The header, with the body sizes given and the camera where the tests
    /// have always put it unless a test says otherwise.
    package static func header(rgb: Int, depth: Int, conf: Int, misc: Int,
                               fx: Double = 5.5, fy: Double = 5.5, cx: Double = 4, cy: Double = 3,
                               quat: (Float, Float, Float, Float) = (0, 0, 0, 1),
                               trans: (Float, Float, Float) = (0.1, 0.2, 0.3)) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: 104)
        func u32(_ off: Int, _ v: UInt32) {
            h[off] = UInt8(v & 0xFF); h[off + 1] = UInt8((v >> 8) & 0xFF)
            h[off + 2] = UInt8((v >> 16) & 0xFF); h[off + 3] = UInt8((v >> 24) & 0xFF)
        }
        func f32(_ off: Int, _ v: Float) { u32(off, v.bitPattern) }
        u32(0, 0x0100_0000)                       // magic
        u32(40, UInt32(rgb)); u32(44, UInt32(depth)); u32(48, UInt32(conf)); u32(52, UInt32(misc))
        f32(60, Float(fx)); f32(64, Float(fy)); f32(68, Float(cx)); f32(72, Float(cy))
        f32(76, quat.0); f32(80, quat.1); f32(84, quat.2); f32(88, quat.3)
        f32(92, trans.0); f32(96, trans.1); f32(100, trans.2)
        return h
    }

    /// A JPEG of one flat color at the size given.
    package static func jpeg(width: Int, height: Int) -> [UInt8] {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return [UInt8](data as Data)
    }

    /// `bytes` compressed the way the stream compresses its maps.
    package static func lzfse(_ bytes: [UInt8]) -> [UInt8] {
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
}
