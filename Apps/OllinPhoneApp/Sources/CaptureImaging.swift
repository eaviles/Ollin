import Foundation
import Accelerate
import CoreVideo
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Pixel-buffer helpers shared by the capture streamers — stride-aware copies out of
// a `CVPixelBuffer`, a planar downscale, and the camera-frame JPEG encode. Kept in
// one place so the depth and segmentation streamers don't each carry their own copy.

/// Copy a `DepthFloat32` pixel buffer into a row-major `[Float]`, honoring the
/// buffer's row stride (usually padded past `width × 4`).
func floatPixels(_ buffer: CVPixelBuffer) -> (w: Int, h: Int, data: [Float])? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    var out = [Float](repeating: 0, count: w * h)
    out.withUnsafeMutableBytes { dst in
        guard let dstBase = dst.baseAddress else { return }
        for row in 0..<h {
            memcpy(dstBase.advanced(by: row * w * 4), base.advanced(by: row * stride), w * 4)
        }
    }
    return (w, h, out)
}

/// Copy a `OneComponent8` pixel buffer into a row-major `[UInt8]`, honoring the row
/// stride. The depth confidence map and the segmentation matte both arrive this way.
func bytePixels(_ buffer: CVPixelBuffer) -> (w: Int, h: Int, data: [UInt8])? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
    guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    var out = [UInt8](repeating: 0, count: w * h)
    out.withUnsafeMutableBytes { dst in
        guard let dstBase = dst.baseAddress else { return }
        for row in 0..<h {
            memcpy(dstBase.advanced(by: row * w), base.advanced(by: row * stride), w)
        }
    }
    return (w, h, out)
}

/// Downscale a row-major gray plane so its longest side is at most `maxDimension`,
/// preserving aspect (a no-op when it already fits). A `vImageScale_Planar8` pass.
/// Used to bound the segmentation matte's payload — it's a soft mask the Mac
/// rescales onto the color anyway.
func downscalePlane(_ plane: [UInt8], width: Int, height: Int,
                    maxDimension: Int) -> (w: Int, h: Int, data: [UInt8]) {
    let longest = max(width, height)
    guard longest > maxDimension, width > 0, height > 0 else { return (width, height, plane) }
    let scale = Double(maxDimension) / Double(longest)
    let dw = max(1, Int((Double(width) * scale).rounded()))
    let dh = max(1, Int((Double(height) * scale).rounded()))
    var src = plane
    var dst = [UInt8](repeating: 0, count: dw * dh)
    let ok = src.withUnsafeMutableBytes { srcRaw -> Bool in
        dst.withUnsafeMutableBytes { dstRaw -> Bool in
            var input = vImage_Buffer(data: srcRaw.baseAddress, height: vImagePixelCount(height),
                                      width: vImagePixelCount(width), rowBytes: width)
            var output = vImage_Buffer(data: dstRaw.baseAddress, height: vImagePixelCount(dh),
                                       width: vImagePixelCount(dw), rowBytes: dw)
            return vImageScale_Planar8(&input, &output, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
    }
    return ok ? (dw, dh, dst) : (width, height, plane)
}

/// Convert a captured YCbCr frame to a downscaled JPEG, in the camera-native
/// orientation (no rotation — depth/matte, intrinsics, and color must share one
/// frame so the unprojection / matte line up). `maxDimension` bounds the longest
/// side; `quality` is the JPEG compression quality (`0…1`).
func cameraJPEG(from pixelBuffer: CVPixelBuffer, context: CIContext,
                maxDimension: Int, quality: CGFloat) -> Data? {
    var ci = CIImage(cvPixelBuffer: pixelBuffer)
    let longest = max(ci.extent.width, ci.extent.height)
    if longest > CGFloat(maxDimension) {
        let s = CGFloat(maxDimension) / longest
        ci = ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
    }
    guard let cg = context.createCGImage(ci, from: ci.extent) else { return nil }

    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}
