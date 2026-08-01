import CoreGraphics
@testable import Ollin

/// Reading a rendered frame as coats of translucent ink.
///
/// A stroke is expanded segment by segment, so consecutive segments have to end
/// on the point where their inner edges cross. Overshooting paints the inside of
/// every turn twice; stopping short leaves a hairline. Both are invisible in
/// opaque ink and unmissable in translucent ink, and both are per join, so on a
/// curve they repeat every few pixels.
///
/// What makes them testable is that one even coat lays down a single value and
/// every anti-aliased pixel is *lighter* than it, being partial coverage over
/// paper. So darker-than-coat means a second coat, and lighter-than-coat with
/// ink on all four sides means a hairline, and neither can be confused with an
/// edge. A whole-frame difference cannot do this: the pixels are few and sit in
/// a band around an edge, which is exactly where a mean diff has no resolution.
struct InkProbe {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    /// The ink value covering the most pixels. The present pass dithers, so one
    /// coat straddles two 8-bit levels and the thresholds below leave room for
    /// the mode's neighbour.
    let coat: Int
    /// How many pixels carry that coat, for a probe to check it found the mark.
    let coatArea: Int

    /// `paperBelow` is the darkest value still counted as paper, so the paper the
    /// drawing sits on is excluded from the histogram.
    init(_ image: CGImage, inkDarkerThan paperBelow: Int) {
        let w = image.width, h = image.height
        width = w
        height = h
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        raw.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        bytes = raw
        var histogram: [Int: Int] = [:]
        for i in stride(from: 0, to: w * h * 4, by: 4) where Int(raw[i]) < paperBelow {
            histogram[Int(raw[i]), default: 0] += 1
        }
        let mode = histogram.max { $0.value < $1.value }
        coat = mode?.key ?? 0
        coatArea = mode?.value ?? 0
    }

    func gray(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4]) }

    /// Pixels darker than one coat: ink laid down a second time.
    var paintedTwice: Int { paintedTwice(ignoring: []) }

    /// The same count with some discs left out, for a path that genuinely folds
    /// over itself somewhere known. Where the crossing would fall outside a
    /// neighbouring segment the ends stay square and overlap, which is the
    /// documented fallback, so a corner between a long edge and a finely sampled
    /// curve is expected to double up.
    func paintedTwice(ignoring discs: [(center: Vector2, radius: Double)]) -> Int {
        var count = 0
        for y in 0..<height {
            for x in 0..<width where gray(x, y) < coat - 5 {
                let p = Vector2(Double(x), Double(y))
                if discs.contains(where: { (p - $0.center).length <= $0.radius }) { continue }
                count += 1
            }
        }
        return count
    }

    /// Pixels lighter than one coat with ink on all four sides: a hairline
    /// buried inside the mark, which no edge can produce.
    var hairlines: Int {
        var count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) where gray(x, y) > coat + 4 {
                if gray(x - 1, y) <= coat, gray(x + 1, y) <= coat,
                   gray(x, y - 1) <= coat, gray(x, y + 1) <= coat { count += 1 }
            }
        }
        return count
    }
}
