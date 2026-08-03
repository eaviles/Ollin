import Foundation

/// A light cookie (a *gobo*, in stage terms): an image a spot light projects,
/// so the light lands patterned rather than plain. A window frame, a leaf
/// canopy, a logo cut from a metal disc, a color gel: draw or load the image,
/// wrap it once, and hand it to the light.
///
/// ```swift
/// let gobo = LightCookie(loadImage("blinds.png")!)!
/// spotLight(.white, at: eye, direction: aim, cookie: gobo)
/// ```
///
/// The image is mapped so its edges land at the spot's outer cone: a wider
/// cone projects the same picture larger. Its color multiplies the light
/// (black blocks, white passes, color tints like a gel), with transparency
/// composited over black, and the light's `roll` spins it about the beam.
/// Build one in `setup()` and keep it: the initializer resamples the image's
/// pixels once into a fixed-size buffer, which is what makes the value
/// self-contained (`Sendable`, comparable, and independent of the `Image`
/// it came from). A GPU-backed image (a video frame, a Syphon feed) has no
/// CPU pixels to read, so it fails to wrap; `snapshot()` such an image first.
public struct LightCookie: Equatable, Sendable {

    /// The fixed side of the resampled square buffer the GPU array uses
    /// (every cookie in a frame shares one texture array, so they share
    /// one size).
    static let resolution = 512

    /// `resolution × resolution` premultiplied RGBA bytes, row-major from the
    /// top, resampled from the source image at init.
    let pixels: [UInt8]
    /// A content hash computed once, so per-frame texture-cache comparisons
    /// never re-walk the buffer.
    let contentHash: Int

    /// Wrap an image as a cookie, resampling it once to the shared buffer
    /// size. Returns `nil` for a GPU-backed image with no CPU pixels.
    public init?(_ image: Image) {
        guard image.width > 0, image.height > 0,
              let source = image.premultipliedPixels() else {
            FileHandle.standardError.write(Data(
                "Ollin: LightCookie needs an image with CPU pixels (snapshot() a GPU-backed one first).\n".utf8))
            return nil
        }
        let side = LightCookie.resolution
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let sw = image.width, sh = image.height
        for row in 0 ..< side {
            // Bilinear resample at texel centers; clamp the source reads.
            let sy = (Double(row) + 0.5) / Double(side) * Double(sh) - 0.5
            let y0 = min(max(Int(sy.rounded(.down)), 0), sh - 1)
            let y1 = min(y0 + 1, sh - 1)
            let fy = min(max(sy - Double(y0), 0), 1)
            for col in 0 ..< side {
                let sx = (Double(col) + 0.5) / Double(side) * Double(sw) - 0.5
                let x0 = min(max(Int(sx.rounded(.down)), 0), sw - 1)
                let x1 = min(x0 + 1, sw - 1)
                let fx = min(max(sx - Double(x0), 0), 1)
                let i00 = (y0 * sw + x0) * 4, i10 = (y0 * sw + x1) * 4
                let i01 = (y1 * sw + x0) * 4, i11 = (y1 * sw + x1) * 4
                let out = (row * side + col) * 4
                for c in 0 ..< 4 {
                    let top = Double(source[i00 + c]) + (Double(source[i10 + c]) - Double(source[i00 + c])) * fx
                    let bottom = Double(source[i01 + c]) + (Double(source[i11 + c]) - Double(source[i01 + c])) * fx
                    buffer[out + c] = UInt8(max(0, min(255, (top + (bottom - top) * fy).rounded())))
                }
            }
        }
        self.pixels = buffer
        var hasher = Hasher()
        buffer.withUnsafeBytes { hasher.combine(bytes: $0) }
        self.contentHash = hasher.finalize()
    }

    public static func == (lhs: LightCookie, rhs: LightCookie) -> Bool {
        lhs.contentHash == rhs.contentHash && lhs.pixels == rhs.pixels
    }
}
