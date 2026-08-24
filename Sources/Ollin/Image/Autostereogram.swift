import Foundation

/// A picture that hides a shape in its own repetition: cross or relax your eyes
/// until two neighboring repeats fall on one another, and the shape stands up out
/// of the page.
///
/// The trick is one rule. A flat background repeats at a fixed spacing, so the two
/// eyes pair up the same pattern and read it at the depth that spacing stands for.
/// **Move two paired pixels a little closer together and the pair reads as nearer.**
/// So a depth map becomes a picture by shortening the repeat wherever the shape is
/// closer, and the surface that comes out is not drawn at all. It is the depth the
/// eyes work out from the pairing.
///
/// ```swift
/// let hidden = autostereogram(of: depthMap, pattern: nil, seed: 4)
/// drawImage(hidden, in: bounds, fit: .contain)
/// ```
///
/// Read it by looking *through* the picture, as if at something behind the screen,
/// until the repeats double up. Some people find crossing their eyes easier, which
/// reads the same picture inside out: what should stand up sinks instead.
public struct Autostereogram: Sendable {
    /// How far apart, in pixels, the pattern repeats at the far plane. A wider
    /// repeat is easier on the eyes and holds less detail. About a sixth of the
    /// picture's width is the usual choice, and around 100 to 140 pixels suits a
    /// screen at arm's length.
    public var repeatWidth: Int
    /// How much nearer the closest part of the shape sits, as a fraction of the
    /// repeat. The repeat shortens by this much where the depth map is white.
    /// Past about a third the two eyes cannot pair the picture at all.
    public var relief: Double
    /// Whether white in the depth map means near (the default) or far.
    public var whiteIsNear: Bool

    public init(repeatWidth: Int = 120, relief: Double = 0.22, whiteIsNear: Bool = true) {
        self.repeatWidth = Swift.max(8, repeatWidth)
        self.relief = Swift.max(0, Swift.min(0.9, relief))
        self.whiteIsNear = whiteIsNear
    }
}

public extension Image {
    /// Hide this picture's *depth* inside a repeating pattern.
    ///
    /// This picture is read as the depth map: how bright a pixel is says how near
    /// that part of the shape sits. Draw the shape in white on black (or hand a
    /// rendered depth buffer straight in) and the result is the picture to look
    /// through.
    ///
    /// - Parameters:
    ///   - settings: the repeat spacing and how much relief to give the shape.
    ///   - pattern: the tile to repeat, or nil for seeded color noise, which is
    ///     what the classic pictures use because it pairs unambiguously.
    ///   - seed: the seed behind that noise, so the same seed makes the same
    ///     picture.
    ///
    /// The picture is built column by column, left to right, and every column
    /// takes its color from the column one repeat to its left. The leftmost repeat
    /// is the only free choice, which is why the pattern only has to be one repeat
    /// wide.
    func autostereogram(_ settings: Autostereogram = Autostereogram(),
                        pattern: Image? = nil, seed: Int = 0) -> Image? {
        guard let depth = premultipliedPixels() else {
            print("Ollin: autostereogram needs CPU pixels; a texture-backed image has none. "
                + "Read a frame through its snapshot first.")
            return nil
        }
        let width = self.width, height = self.height
        guard width > settings.repeatWidth, height > 0 else { return nil }

        // The one repeat of pattern every column is copied from. Noise pairs best,
        // since a repeated feature has to be unmistakable to lock onto.
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let tilePixels = pattern?.premultipliedPixels()
        let tileWidth = pattern?.width ?? 0
        let tileHeight = pattern?.height ?? 0

        var out = [UInt8](repeating: 0, count: width * height * 4)
        var sameAs = [Int](repeating: 0, count: width)

        for y in 0 ..< height {
            // Which columns of this row must end up the same color. Every column
            // starts out standing for itself.
            for x in 0 ..< width { sameAs[x] = x }

            for x in 0 ..< width {
                let brightness = depthLevel(depth, x: x, y: y, width: width,
                                            whiteIsNear: settings.whiteIsNear)
                // Nearer means a shorter repeat, which is the whole trick.
                let separation = Int((Double(settings.repeatWidth)
                    * (1 - settings.relief * brightness)).rounded())
                let left = x - separation / 2
                let right = left + separation
                guard left >= 0, right < width else { continue }

                // Join the two columns, following each to whatever it already
                // stands for, so a chain of pairings stays consistent.
                var a = left, b = right
                while sameAs[a] != a { a = sameAs[a] }
                while sameAs[b] != b { b = sameAs[b] }
                if a != b { sameAs[Swift.max(a, b)] = Swift.min(a, b) }
            }

            for x in 0 ..< width {
                var root = x
                while sameAs[root] != root { root = sameAs[root] }
                let i = (y * width + x) * 4
                if root == x {
                    // A free column: take the pattern, or roll a color.
                    if let tilePixels, tileWidth > 0, tileHeight > 0 {
                        let tx = x % tileWidth, ty = y % tileHeight
                        let j = (ty * tileWidth + tx) * 4
                        out[i] = tilePixels[j]
                        out[i + 1] = tilePixels[j + 1]
                        out[i + 2] = tilePixels[j + 2]
                        out[i + 3] = tilePixels[j + 3]
                    } else {
                        out[i] = UInt8(rng.next() % 256)
                        out[i + 1] = UInt8(rng.next() % 256)
                        out[i + 2] = UInt8(rng.next() % 256)
                        out[i + 3] = 255
                    }
                } else {
                    let j = (y * width + root) * 4
                    out[i] = out[j]
                    out[i + 1] = out[j + 1]
                    out[i + 2] = out[j + 2]
                    out[i + 3] = out[j + 3]
                }
            }
        }
        return Image(width: width, height: height, premultipliedRGBA: out)
    }
}

/// The depth at a pixel, 0 for far and 1 for near, read in linear light so a ramp
/// in the map is a ramp in the relief.
private func depthLevel(_ pixels: [UInt8], x: Int, y: Int, width: Int,
                        whiteIsNear: Bool) -> Double {
    let i = (y * width + x) * 4
    let a = Double(pixels[i + 3]) / 255
    guard a > 0 else { return whiteIsNear ? 0 : 1 }
    let r = Color.srgbToLinear(Double(pixels[i]) / 255 / a)
    let g = Color.srgbToLinear(Double(pixels[i + 1]) / 255 / a)
    let b = Color.srgbToLinear(Double(pixels[i + 2]) / 255 / a)
    let level = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return whiteIsNear ? level : 1 - level
}

public extension Sketch {
    /// Hide `depth`'s relief inside a repeating pattern and draw the result.
    func drawAutostereogram(of depth: Image, in rect: Rectangle? = nil,
                            settings: Autostereogram = Autostereogram(),
                            pattern: Image? = nil, seed: Int = 0) {
        guard let hidden = depth.autostereogram(settings, pattern: pattern, seed: seed) else { return }
        drawImage(hidden, in: rect ?? canvasRectangle, fit: .contain)
    }
}
