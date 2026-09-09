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
}
