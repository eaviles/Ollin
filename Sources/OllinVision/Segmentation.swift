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
/// resolution, so it's deterministic and unit-testable.
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

    /// The white-alpha matte: every pixel white with alpha = the matte's gray
    /// level — premultiplied, so the bytes are `(m, m, m, m)`.
    static func matteCGImage(from matte: CGImage) -> CGImage? {
        guard let gray = grayBytes(from: matte, width: matte.width, height: matte.height) else {
            return nil
        }
        var rgba = [UInt8](repeating: 0, count: gray.count * 4)
        rgba.withUnsafeMutableBufferPointer { out in
            for i in 0..<gray.count {
                let m = gray[i]
                let j = i * 4
                out[j] = m; out[j + 1] = m; out[j + 2] = m; out[j + 3] = m
            }
        }
        return makeRGBA(rgba, width: matte.width, height: matte.height)
    }

    /// The cutout: `frame`'s pixels scaled by the matte (rescaled to the frame),
    /// transparent where the matte is off. Premultiplied, so every channel
    /// scales by the matte value.
    static func cutoutCGImage(frame: CGImage, matte: CGImage) -> CGImage? {
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
        rgba.withUnsafeMutableBufferPointer { out in
            mask.withUnsafeBufferPointer { mask in
                for i in 0..<mask.count {
                    let m = Int(mask[i])
                    guard m < 255 else { continue }
                    let j = i * 4
                    out[j]     = UInt8(Int(out[j])     * m / 255)
                    out[j + 1] = UInt8(Int(out[j + 1]) * m / 255)
                    out[j + 2] = UInt8(Int(out[j + 2]) * m / 255)
                    out[j + 3] = UInt8(Int(out[j + 3]) * m / 255)
                }
            }
        }
        return makeRGBA(rgba, width: width, height: height)
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
            let p = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                let row = y * bytesPerRow
                for x in 0..<width { gray[y * width + x] = p[row + x] }
            }
        case kCVPixelFormatType_OneComponent32Float:
            let p = base.assumingMemoryBound(to: Float.self)
            let floatsPerRow = bytesPerRow / MemoryLayout<Float>.stride
            for y in 0..<height {
                let row = y * floatsPerRow
                for x in 0..<width {
                    gray[y * width + x] = UInt8(min(max(p[row + x], 0), 1) * 255 + 0.5)
                }
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

    private static func makeRGBA(_ buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}

/// Wraps a published `CGImage` into a drawable `Image` lazily, keeping the
/// wrapper while the frame doesn't change — the same cache `Camera.frame` keeps,
/// so repeated reads (within one draw and across draws until the next analysis)
/// reuse the cached GPU texture instead of re-uploading it every call.
final class ImageWrapCache: @unchecked Sendable {

    private struct State {
        var image: Image?
        var id: ObjectIdentifier?
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())

    func image(for cgImage: CGImage?) -> Image? {
        lock.withLockUnchecked { state in
            guard let cgImage else {
                state.image = nil
                state.id = nil
                return nil
            }
            let id = ObjectIdentifier(cgImage)
            if state.id == id, let image = state.image { return image }
            let image = Image(cgImage: cgImage)
            state.image = image
            state.id = id
            return image
        }
    }
}
