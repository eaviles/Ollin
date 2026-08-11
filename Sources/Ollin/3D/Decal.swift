import Foundation

/// A projected decal: a picture stamped onto whatever 3D surfaces sit inside
/// its projection box, like a sticker, a poster, or a paint mark. Wrap an
/// image once, then place it each frame with `decal(_:at:...)`; every solid,
/// textured, or mapped mesh the box crosses receives it, composited over the
/// surface's base color before lighting, so the stamp is shaded as paint on
/// the surface (it takes the surface's own finish).
///
/// ```swift
/// let sticker = Decal(loadImage("label.png")!)!
/// decal(sticker, at: Vector3(0, 120, 0), width: 140)
/// ```
///
/// The image's transparency is honored (a round sticker stamps round), and a
/// later decal composites over an earlier one. Build one in `setup()` and
/// keep it: the initializer resamples the image's pixels once into a fixed
/// square buffer (every decal in a frame shares one texture array), which is
/// what makes the value self-contained (`Sendable`, comparable, independent
/// of the `Image` it came from); the placement's `width`/`height` restore the
/// picture's true proportions. A GPU-backed image (a video frame, a Syphon
/// feed) has no CPU pixels to read, so it fails to wrap; `snapshot()` such an
/// image first.
public struct Decal: Equatable, Sendable {

    /// The fixed side of the resampled square buffer the GPU array uses
    /// (every decal in a frame shares one texture array, so they share one
    /// size).
    static let resolution = 512

    /// `resolution × resolution` premultiplied RGBA bytes, row-major from the
    /// top, resampled from the source image at init.
    let pixels: [UInt8]
    /// A content hash computed once, so per-frame texture-cache comparisons
    /// never re-walk the buffer.
    let contentHash: Int
    /// The source image's height over its width, kept so a placement can
    /// default its `height` to the picture's true proportions.
    public let aspect: Double

    /// Wrap an image as a decal, resampling it once to the shared buffer
    /// size. Returns `nil` for a GPU-backed image with no CPU pixels.
    public init?(_ image: Image) {
        guard image.width > 0, image.height > 0,
              let source = image.premultipliedPixels() else {
            FileHandle.standardError.write(Data(
                "Ollin: Decal needs an image with CPU pixels (snapshot() a GPU-backed one first).\n".utf8))
            return nil
        }
        let side = Decal.resolution
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
        self.aspect = Double(sh) / Double(sw)
        var hasher = Hasher()
        buffer.withUnsafeBytes { hasher.combine(bytes: $0) }
        self.contentHash = hasher.finalize()
    }

    public static func == (lhs: Decal, rhs: Decal) -> Bool {
        lhs.contentHash == rhs.contentHash && lhs.pixels == rhs.pixels
    }
}
