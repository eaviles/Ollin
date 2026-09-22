@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// What a user shader reads from a layer that holds data rather than a picture.
/// An explicit-size layer is exactly that many texels on every path, so a read at
/// a texel's center through `sampleAuxRaw` lands on one texel and blends nothing;
/// what decides whether the texel holds the number is how it was drawn. An image
/// of the data, one texel per value, is exact. A one-texel `drawRect` is not: its
/// anti-aliasing halo lies outside its edge, where the next texel's center is,
/// so each texel carries most of whichever neighbor was drawn after it.
@Suite(.serialized)
@MainActor
struct DataLayerReadTests {

    /// Four texels wide, one high: a mark of the asked value in each texel, read
    /// back by a combine whose output is flat over each quarter of the canvas.
    final class DataStrip: Sketch {
        var values: [Double] = [0.2, 0.5, 0.8, 1.0]
        var marks: [Bool] = [true, true, true, true]
        var asImage = false
        override var canvasSize: CanvasSize { .size(400, 100) }
        override func draw() {
            background(.black)
            let base = makeRenderTarget()
            withTarget(base) { background(.black) }   // a combine over an undrawn base is skipped
            let data = makeRenderTarget(width: 4, height: 1)
            withTarget(data) {
                background(.black)
                noStroke()
                if asImage {
                    // The bytes are the data, one texel each, drawn at native size.
                    var bytes: [UInt8] = []
                    for (i, v) in values.enumerated() {
                        let b = marks[i] ? UInt8((v * 255).rounded()) : 0
                        bytes += [b, b, b, 255]
                    }
                    if let strip = Image(width: 4, height: 1, premultipliedRGBA: bytes) {
                        drawImage(strip, 0, 0)
                    }
                } else {
                    for (i, v) in values.enumerated() where marks[i] {
                        fill(Color(red: v, green: v, blue: v))
                        drawRect(Double(i), 0, 1, 1)
                    }
                }
            }
            let read = Shader("""
            float4 shade(float2 uv, ShaderInfo info) {
                float x = (floor(uv.x * 4.0) + 0.5) / 4.0;
                return float4(linearToSrgb(sampleAuxRaw(info, float2(x, 0.5)).rgb), 1.0);
            }
            """)
            drawImage(base.combined(with: data, .shader(read)).image, 0, 0)
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The linear value each quarter of the strip reads, from the middle of the quarter.
    private func quarters(_ sketch: DataStrip) throws -> [Double] {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let d = pixels(of: image)
        return (0 ..< 4).map { q in
            let x = q * 100 + 50, y = 50
            return Color.srgbToLinear(Double(d[(y * image.width + x) * 4]) / 255)
        }
    }

    /// Drawn as an image of one texel per value, every texel reads back what it
    /// was given; drawn as one-texel rects, each texel carries most of the texel
    /// drawn after it, because a rect's anti-aliasing halo lies outside its edge
    /// and the next texel's center is half a texel away.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anImageTexelReadsExactlyAndARectTexelCarriesItsNeighbor() throws {
        let image = DataStrip()
        image.asImage = true
        for (v, r) in zip(image.values, try quarters(image)) {
            #expect(abs(Color.srgbToLinear(v) - r) < 0.01, "asked \(v), read \(r)")
        }
        let rects = DataStrip()
        let read = try quarters(rects)
        #expect(abs(Color.srgbToLinear(1.0) - read[3]) < 0.01)   // the last drawn is clean
        #expect(read[0] > Color.srgbToLinear(0.2) + 0.05)         // the others carry the next
        #expect(read[1] > Color.srgbToLinear(0.5) + 0.05)
    }

    /// A single lit texel: as an image it stays in its texel, as a rect it puts
    /// more than half its value into the texel on either side and none further.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aOneTexelMarkBleedsAsARectAndNotAsAnImage() throws {
        for asImage in [true, false] {
            let sketch = DataStrip()
            sketch.asImage = asImage
            sketch.values = [0, 1, 0, 1]
            sketch.marks = [false, true, false, false]
            let read = try quarters(sketch)
            #expect(read[1] > 0.98)
            #expect(read[3] < 0.02)
            if asImage {
                #expect(read[0] < 0.02, "the image reached the texel before: \(read[0])")
                #expect(read[2] < 0.02, "the image reached the texel after: \(read[2])")
            } else {
                #expect(read[0] > 0.5, "the rect's halo before: \(read[0])")
                #expect(read[2] > 0.5, "the rect's halo after: \(read[2])")
            }
        }
    }
}
