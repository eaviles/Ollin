import Foundation

/// How a picture's pixels spread over one channel: a count per bin, from the
/// darkest values on the left to the brightest on the right.
///
/// ```swift
/// let h = photo.histogram(of: .lightness, bins: 64)
/// for (i, n) in h.counts.enumerated() {
///     drawRect(Double(i) * 8, 400, 7, -Double(n) / Double(h.total) * 2000)
/// }
/// let floor = h.percentile(0.02), ceiling = h.percentile(0.98)   // auto levels
/// ```
///
/// Bin `i` of `n` holds the values from `i / n` up to `(i + 1) / n`, the last bin
/// taking 1 itself, so 256 bins hold one 8-bit level each.
public struct Histogram: Equatable, Sendable {
    /// What a histogram counts.
    public enum Channel: Sendable, Hashable, CaseIterable {
        /// The red component, as stored (sRGB, 0…1).
        case red
        /// The green component, as stored.
        case green
        /// The blue component, as stored.
        case blue
        /// How opaque each pixel is.
        case alpha
        /// Perceived lightness, OKLab's `l`: 0 is black, 1 is white, and equal
        /// steps look like equal steps, which a mean of the components does not.
        case lightness
    }

    /// What was counted.
    public let channel: Channel
    /// The number of pixels in each bin, darkest first.
    public let counts: [Int]
    /// The number of pixels counted: the sum of `counts`, which is every pixel
    /// of the region read.
    public let total: Int

    init(channel: Channel, counts: [Int]) {
        self.channel = channel
        self.counts = counts
        self.total = counts.reduce(0, +)
    }

    /// The value, in `0...1`, below which `fraction` of the pixels lie: 0.5 is
    /// the median, and the values at 0.02 and 0.98 are a picture's working
    /// black and white, ignoring a few stray pixels. Read between a bin's edges
    /// in proportion to its count. An empty histogram answers 0.
    public func percentile(_ fraction: Double) -> Double {
        guard total > 0, !counts.isEmpty else { return 0 }
        let target = min(max(fraction, 0), 1) * Double(total)
        let width = 1 / Double(counts.count)
        var below = 0.0
        for (i, count) in counts.enumerated() where count > 0 {
            let through = below + Double(count)
            if through >= target {
                let inside = Swift.max(target - below, 0) / Double(count)
                return min((Double(i) + inside) * width, 1)
            }
            below = through
        }
        return 1
    }
}

public extension Image {
    /// Count this picture's pixels by `channel` into `bins` equal bins, read on
    /// the CPU.
    ///
    /// The rectangle is in pixels and clamped to the picture, as in
    /// `averageColor(in:)`, and every pixel inside it counts once, so `total`
    /// is the region's pixel count. Color is read straight (alpha divided out);
    /// a fully transparent pixel has no color of its own and counts at 0 on
    /// every channel but alpha. A texture-backed image (a live feed, a layer)
    /// has no pixels on the CPU, and its histogram is empty. `bins` clamps to
    /// `1...65_536`.
    func histogram(of channel: Histogram.Channel = .lightness, bins: Int = 256,
                   in region: Rectangle? = nil) -> Histogram {
        let bins = Swift.min(Swift.max(bins, 1), 65_536)
        var counts = [Int](repeating: 0, count: bins)
        guard let pixels = premultipliedPixels(),
              let (x0, y0, x1, y1) = pixelSpan(of: region) else {
            return Histogram(channel: channel, counts: counts)
        }
        let scale = Double(bins)
        func count(_ value: Double) {
            let bin = Int(Swift.min(Swift.max(value, 0), 1) * scale)
            counts[Swift.min(bin, bins - 1)] += 1
        }
        // The lightness of an opaque pixel is a function of three bytes, so the
        // light each byte stands for is read once from a table.
        let linear = (0 ... 255).map { Color.srgbToLinear(Double($0) / 255) }
        for y in y0 ..< y1 {
            let row = y * width * 4
            for x in x0 ..< x1 {
                let i = row + x * 4
                let alpha = pixels[i + 3]
                if channel == .alpha { count(Double(alpha) / 255); continue }
                guard alpha > 0 else { count(0); continue }
                let a = Double(alpha) / 255
                switch channel {
                case .red: count(Swift.min(1, Double(pixels[i]) / 255 / a))
                case .green: count(Swift.min(1, Double(pixels[i + 1]) / 255 / a))
                case .blue: count(Swift.min(1, Double(pixels[i + 2]) / 255 / a))
                case .alpha: break
                case .lightness:
                    let lab: OKLab
                    if alpha == 255 {
                        lab = OKLab(linearRed: linear[Int(pixels[i])],
                                    green: linear[Int(pixels[i + 1])],
                                    blue: linear[Int(pixels[i + 2])])
                    } else {
                        func light(_ byte: UInt8) -> Double {
                            Color.srgbToLinear(Swift.min(1, Double(byte) / 255 / a))
                        }
                        lab = OKLab(linearRed: light(pixels[i]), green: light(pixels[i + 1]),
                                    blue: light(pixels[i + 2]))
                    }
                    count(lab.l)
                }
            }
        }
        return Histogram(channel: channel, counts: counts)
    }
}

extension Image {
    /// The whole pixels a region covers, clamped to the picture: its edges
    /// rounded outward, so a region that touches part of a pixel takes all of
    /// it. The whole picture when `region` is nil; nil when nothing is left.
    func pixelSpan(of region: Rectangle?) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        let box = region ?? Rectangle(x: 0, y: 0, width: Double(width), height: Double(height))
        let x0 = Swift.max(0, Int(box.x.rounded(.down)))
        let y0 = Swift.max(0, Int(box.y.rounded(.down)))
        let x1 = Swift.min(width, Int((box.x + box.width).rounded(.up)))
        let y1 = Swift.min(height, Int((box.y + box.height).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        return (x0, y0, x1, y1)
    }
}
