import Accelerate
import Ollin
import CoreGraphics
import CoreVideo
import Foundation
import os

/// One segmentation result: the soft `matte` and the `cutout` it makes of the
/// source image. Both are drawable `Image`s — draw them into the same rectangle
/// you drew the source into and they line up with the picture.
///
/// - `matte` is a white silhouette whose alpha is the per-pixel confidence
///   (`0…1`). Drawn as-is it's a white shape; `tint(_:)` recolors it, which is
///   how a silhouette, a drop shadow, or a colored glow comes from the same matte.
/// - `cutout` keeps the source's own pixels where the matte is on and is
///   transparent everywhere else — the person (or subject) lifted off the
///   background, ready to composite over anything.
///
/// `@unchecked Sendable`: `Image` is a class, but both images are freshly created
/// by the segmenter and handed over whole — nothing else holds or mutates them.
public struct Segmentation: @unchecked Sendable {

    /// The soft matte: white, with alpha = per-pixel confidence. At the model's
    /// resolution, not the source's — drawing it into the source's rectangle
    /// rescales it back onto the picture.
    public let matte: Image

    /// The source's pixels where the matte is on, transparent elsewhere, at the
    /// source's own resolution.
    public let cutout: Image

    init(matte: Image, cutout: Image) {
        self.matte = matte
        self.cutout = cutout
    }
}

/// The pixel work shared by the segmenters: Vision hands back a grayscale matte
/// (as a `CGImage`), and these turn it into the two drawable forms — the
/// white-alpha matte and the source cutout. Pure CPU byte work at matte/frame
/// resolution, so it's deterministic and unit-testable. The per-pixel passes go
/// through vImage, which matters more than it looks: these run per analyzed
/// frame on the analyzer thread, and the `swift run` workflow is a *debug*
/// build, where a hand-rolled byte loop over a camera frame costs ~100 ms while
/// the vectorized call stays in the low milliseconds (it was the difference
/// between ~6 and ~30 matte updates a second, live).
enum SegmentationImages {

    /// The matte's gray levels as one byte per pixel at `width`×`height`,
    /// redrawn through a one-component context — which both normalizes whatever
    /// form Vision handed back (its matte `CGImage` arrives gray-expanded to
    /// RGB) and rescales when the target size differs from the matte's.
    static func grayBytes(from matte: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(matte, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drew ? bytes : nil
    }

    /// The white-alpha matte as premultiplied RGBA8 bytes: every pixel white
    /// with alpha = the matte's gray level — premultiplied, so the bytes are
    /// `(m, m, m, m)`.
    static func matteRGBABytes(from matte: CGImage) -> [UInt8]? {
        guard let gray = grayBytes(from: matte, width: matte.width, height: matte.height) else {
            return nil
        }
        return expandGrayToRGBA(gray, width: matte.width, height: matte.height)
    }

    /// `gray` broadcast into interleaved `(m, m, m, m)` RGBA — one vImage
    /// planar→interleaved convert with the same plane feeding all four channels.
    private static func expandGrayToRGBA(_ gray: [UInt8], width: Int, height: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: gray.count * 4)
        gray.withUnsafeBufferPointer { plane in
            rgba.withUnsafeMutableBytes { out in
                var src = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: plane.baseAddress),
                    height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width)
                var dest = vImage_Buffer(
                    data: out.baseAddress,
                    height: vImagePixelCount(height), width: vImagePixelCount(width),
                    rowBytes: width * 4)
                vImageConvert_Planar8toARGB8888(&src, &src, &src, &src, &dest,
                                                vImage_Flags(kvImageNoFlags))
            }
        }
        return rgba
    }

    /// The matte as a drawable `Image`, built straight over the bytes so its GPU
    /// texture uploads directly — no CGImage round-trip, no draw-side rebuild.
    static func matteImage(from matte: CGImage) -> Image? {
        guard let bytes = grayBytes(from: matte, width: matte.width, height: matte.height) else {
            return nil
        }
        return matteImage(fromGray: bytes, width: matte.width, height: matte.height)
    }

    /// The same white-alpha matte built from an already-extracted gray plane —
    /// for a caller that keeps the gray bytes around for its own reads (the
    /// model tracker's value queries) and shouldn't pay the extraction twice.
    static func matteImage(fromGray gray: [UInt8], width: Int, height: Int) -> Image? {
        Image(width: width, height: height,
              premultipliedRGBA: expandGrayToRGBA(gray, width: width, height: height))
    }

    /// The cutout as premultiplied RGBA8 bytes: `frame`'s pixels scaled by the
    /// matte (rescaled to the frame), transparent where the matte is off.
    /// Premultiplied, so every channel scales by the matte value.
    static func cutoutRGBABytes(frame: CGImage, matte: CGImage) -> [UInt8]? {
        let width = frame.width, height = frame.height
        guard let mask = grayBytes(from: matte, width: width, height: height) else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drew = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }
        // Scale every channel by the mask: expand the mask to the same
        // interleaved layout, then treat each RGBA row as one wide plane and
        // premultiply it against the expanded mask — a single vectorized pass.
        let maskRGBA = expandGrayToRGBA(mask, width: width, height: height)
        rgba.withUnsafeMutableBytes { data in
            maskRGBA.withUnsafeBytes { alpha in
                var src = vImage_Buffer(
                    data: data.baseAddress,
                    height: vImagePixelCount(height), width: vImagePixelCount(width * 4),
                    rowBytes: width * 4)
                var alphaBuffer = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: alpha.baseAddress),
                    height: vImagePixelCount(height), width: vImagePixelCount(width * 4),
                    rowBytes: width * 4)
                vImagePremultiplyData_Planar8(&src, &alphaBuffer, &src,
                                              vImage_Flags(kvImageNoFlags))
            }
        }
        return rgba
    }

    /// The cutout as a drawable `Image`, built straight over the bytes like
    /// `matteImage`.
    static func cutoutImage(frame: CGImage, matte: CGImage) -> Image? {
        guard let bytes = cutoutRGBABytes(frame: frame, matte: matte) else { return nil }
        return Image(width: frame.width, height: frame.height, premultipliedRGBA: bytes)
    }

    /// A grayscale `CGImage` from a Vision mask `CVPixelBuffer` — the soft masks
    /// its generators hand back arrive as one-component 8-bit or 32-bit float
    /// (`0…1`); anything else returns `nil`.
    static func grayCGImage(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }
        var gray = [UInt8](repeating: 0, count: width * height)
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_OneComponent8:
            gray.withUnsafeMutableBytes { out in
                var src = vImage_Buffer(data: base, height: vImagePixelCount(height),
                                        width: vImagePixelCount(width), rowBytes: bytesPerRow)
                var dest = vImage_Buffer(data: out.baseAddress, height: vImagePixelCount(height),
                                         width: vImagePixelCount(width), rowBytes: width)
                vImageCopyBuffer(&src, &dest, 1, vImage_Flags(kvImageNoFlags))
            }
        case kCVPixelFormatType_OneComponent32Float:
            gray.withUnsafeMutableBytes { out in
                var src = vImage_Buffer(data: base, height: vImagePixelCount(height),
                                        width: vImagePixelCount(width), rowBytes: bytesPerRow)
                var dest = vImage_Buffer(data: out.baseAddress, height: vImagePixelCount(height),
                                         width: vImagePixelCount(width), rowBytes: width)
                // Clamps to 0…1 and scales to 0…255, the vectorized form of the
                // per-pixel `min(max(v, 0), 1) * 255` convert.
                vImageConvert_PlanarFtoPlanar8(&src, &dest, 1, 0, vImage_Flags(kvImageNoFlags))
            }
        default:
            return nil
        }
        guard let provider = CGDataProvider(data: Data(gray) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

}
