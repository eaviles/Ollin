import CoreGraphics
import Testing
@testable import Ollin

/// Rendered checks on the tessellated stroke path, which outline-font glyphs
/// are the only remaining customer of (every other stroke goes through the
/// fringe expander, covered by `FringeStrokeTests`).
///
/// Both paths expand a path segment by segment, so both have to end consecutive
/// segments on the point where their inner edges cross. Getting that wrong is
/// invisible in opaque ink and unmissable in translucent ink, and it is a per
/// join defect, so on a glyph's flattened curves it repeats every few pixels.
@Suite
@MainActor
struct GlyphStrokeTests {

    /// One letter with no self-overlapping contours, stroked in translucent ink
    /// thick enough that a second coat would be obvious.
    private final class Letter: Sketch {
        var join: StrokeJoin = .round
        override var canvasSize: CanvasSize { .square(512) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            noFill()
            stroke(Color.black.withAlpha(0.25))
            strokeWeight(16)
            strokeJoin(join)
            textFont(OutlineFont.systemBold)
            textSize(340)
            textAlign(.center, .middle)
            drawText("o", 256, 256)
        }
    }

    /// One even coat of translucent ink lays down exactly one value, and every
    /// anti-aliased pixel is *lighter* than it (partial coverage over paper).
    /// That makes both failure modes crisp to test for and immune to being
    /// confused with anti-aliasing.
    ///
    /// A segment that ends on its own perpendicular overshoots into its neighbour
    /// and paints the inside of every turn twice, so pixels appear *darker* than
    /// the coat, a comb of dark ticks along each curve. Fanning the join filler
    /// from the path vertex once the ends bend to the shared crossing leaves a
    /// T-junction instead, whose hairline shows as the same comb in pale: pixels
    /// *lighter* than the coat with ink on every side.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTranslucentGlyphOutlineIsAnEvenCoat() throws {
        for join in [StrokeJoin.round, .miter, .bevel] {
            let letter = Letter()
            letter.join = join
            let image = try #require(OllinApp.image(of: letter))
            let w = image.width, h = image.height
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { raw in
                let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                    bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            func gray(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * w + x) * 4]) }

            // The coat is whatever ink value covers the most pixels.
            var histogram: [Int: Int] = [:]
            for i in stride(from: 0, to: w * h * 4, by: 4) where Int(bytes[i]) < 250 {
                histogram[Int(bytes[i]), default: 0] += 1
            }
            // The present pass dithers, so one coat straddles two 8-bit levels.
            // Take the mode, and give the thresholds below room for its neighbour.
            let coat = try #require(histogram.max { $0.value < $1.value }?.key)
            #expect(histogram[coat]! > 5_000, "\(join): probe missed the glyph")

            var twice = 0, pale = 0
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) {
                    let v = gray(x, y)
                    if v < coat - 5 { twice += 1 }
                    // Ink on all four sides, so not an outside edge.
                    if v > coat + 4, gray(x - 1, y) <= coat, gray(x + 1, y) <= coat,
                       gray(x, y - 1) <= coat, gray(x, y + 1) <= coat { pale += 1 }
                }
            }
            #expect(twice == 0, "\(join): \(twice) pixels painted twice (coat \(coat))")
            #expect(pale == 0, "\(join): \(pale) pixels of hairline inside the ink")
        }
    }
}
