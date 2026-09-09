import CoreGraphics
import Foundation

public extension Image {
    /// A copy of this image at `width` by `height` pixels, resampled with
    /// high-quality interpolation. The way to make a small working copy of a
    /// large picture before handing it to something that reads every pixel: a
    /// stipple, a dither, a mosaic, a string-art winding. Setup-time work, so
    /// keep the result rather than resizing in `draw()`.
    ///
    /// Reads the CPU pixels, so it applies to a picture decoded from a file or
    /// authored pixel by pixel; an image wrapping a live texture or a layer has
    /// no CPU pixels and comes back as a blank of the requested size.
    func resized(width newWidth: Int, height newHeight: Int) -> Image {
        let w = max(1, newWidth), h = max(1, newHeight)
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Image(width: w, height: h)
        }
        context.interpolationQuality = .high
        context.draw(currentCGImage(), in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = context.makeImage() else { return Image(width: w, height: h) }
        return Image(cgImage: scaled)
    }

    /// A copy of the `width` by `height` pixels starting at `x`, `y`, measured
    /// from the top-left corner. The companion to `resized(width:height:)`: that
    /// one changes how big a picture is, this one changes what is in it. Taking
    /// a shape out of a picture is what a square photograph needs before it can
    /// stand in for a wide one, and what cutting a picture into tiles is made
    /// of.
    ///
    /// The rectangle is clamped to the picture, so a crop that runs off an edge
    /// comes back smaller rather than empty, and one entirely outside comes back
    /// as a single pixel. Reads the CPU pixels, so an image wrapping a live
    /// texture or a layer comes back blank.
    func cropped(x: Int, y: Int, width cropWidth: Int, height cropHeight: Int) -> Image {
        let left = min(max(0, x), self.width - 1)
        let top = min(max(0, y), self.height - 1)
        let w = max(1, min(cropWidth, self.width - left))
        let h = max(1, min(cropHeight, self.height - top))
        guard let piece = currentCGImage().cropping(to: CGRect(x: left, y: top, width: w, height: h)) else {
            return Image(width: w, height: h)
        }
        return Image(cgImage: piece)
    }

    /// The largest centered rectangle of this picture with the given shape, as a
    /// copy. `aspect` is width over height, so `16.0 / 9` takes a wide slice out
    /// of a square and `1` takes a square out of anything. Nothing is scaled:
    /// the picture keeps its own pixels, and only what falls outside the shape
    /// is dropped.
    func cropped(toAspect aspect: Double) -> Image {
        guard aspect > 0 else { return self }
        let full = Double(width) / Double(height)
        let w = full > aspect ? Int((Double(height) * aspect).rounded()) : width
        let h = full > aspect ? height : Int((Double(width) / aspect).rounded())
        return cropped(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
}
