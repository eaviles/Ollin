import CoreGraphics
import Foundation
@testable import Ollin

// MARK: - Reading a rendered frame

/// The bytes of a rendered frame: RGBA, eight bits a channel, premultiplied,
/// rows from the top, so pixel `(x, y)` starts at `(y * width + x) * 4`.
///
/// Every drawing probe reads its frame through this one readback. The frame
/// `OllinApp.image(of:)` hands back is an 8-bit device-RGB image, and drawing
/// that into a device-RGB or an sRGB context gives the same bytes (measured
/// 2026-10-06 over a full ramp, no byte differs), so the color space named
/// here is a formality and no probe needs its own copy of these lines.
func pixels(of image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { raw in
        guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return bytes
}

/// A rendered frame read back once, with its size kept beside the bytes, for a
/// probe that addresses pixels by position.
struct Pixels {
    let bytes: [UInt8]
    let width: Int
    let height: Int

    init(_ image: CGImage) {
        bytes = pixels(of: image)
        width = image.width
        height = image.height
    }

    /// The red channel at `(x, y)`, which on a gray picture is its gray.
    func gray(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4]) }

    /// Channel `c` (0 red, 1 green, 2 blue, 3 alpha) at `(x, y)`.
    func channel(_ c: Int, _ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4 + c]) }
}

/// An sRGB byte as linear light, 0...1: the transfer curve undone, which is
/// where light adds and where every energy claim in the probes is measured.
func linear(_ byte: UInt8) -> Double {
    let v = Double(byte) / 255
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
}

// MARK: - Reading ink

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
    /// the mode's neighbor.
    let coat: Int
    /// How many pixels carry that coat, for a probe to check it found the mark.
    let coatArea: Int

    /// `paperBelow` is the darkest value still counted as paper, so the paper the
    /// drawing sits on is excluded from the histogram.
    init(_ image: CGImage, inkDarkerThan paperBelow: Int) {
        let w = image.width, h = image.height
        width = w
        height = h
        let raw = pixels(of: image)
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
    /// neighboring segment the ends stay square and overlap, which is the
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
