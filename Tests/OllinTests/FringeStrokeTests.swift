import CoreGraphics
import Testing
@testable import Ollin

/// Rendered checks on the fringe stroke expander's seams.
///
/// A pixel snapshot cannot cover this. The defect is a handful of single pixels
/// out of a million, so a whole-frame mean difference averages it into nothing,
/// and the pixels move whenever the stroke weight shifts by half a point. What
/// pins it is the property itself: inside a solid band of ink there is no such
/// thing as a lighter pixel.
@Suite
@MainActor
struct FringeStrokeTests {

    private final class Ring: Sketch {
        var weight = 26.0
        var points = 181
        var radius = 75.0
        var join: StrokeJoin = .miter
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            stroke(.black)
            strokeWeight(weight)
            strokeJoin(join)
            noFill()
            let pts = (0..<points).map { i -> Vector2 in
                let a = 2 * Double.pi * Double(i) / Double(points)
                return Vector2(128, 128) + Vector2(cos(a), sin(a)) * radius
            }
            drawPolyline(pts, closed: true)
        }
    }

    /// Pixels lighter than the ink around them, with solid ink on all four
    /// sides. Nothing legitimate draws one: an anti-aliased edge always has
    /// paper on one side.
    private func pinholes(of image: CGImage) -> Int {
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
        var count = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) where gray(x, y) > 20 {
                if gray(x - 1, y) < 10, gray(x + 1, y) < 10,
                   gray(x, y - 1) < 10, gray(x, y + 1) < 10 { count += 1 }
            }
        }
        return count
    }

    /// Every join fans out from the path vertex, so the core band carries a
    /// point on the centerline for that fan to meet. Without it the fan's apex
    /// lands mid-edge, and the T-junction that makes leaks a hairline the
    /// rasterizer resolves differently on each side: isolated pixels of about
    /// six-eighths coverage, buried inside solid ink.
    ///
    /// Curvature and weight both matter, hence the spread. A crack appears or
    /// not depending on where the seam falls against the sub-pixel grid, so any
    /// single configuration is a coin flip; the set is what makes this reliable.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStrokedCurveHasNoHolesInIt() throws {
        for join in [StrokeJoin.miter, .round, .bevel] {
            for points in [181, 360] {
                for weight in [14.0, 26.0, 33.7] {
                    let ring = Ring()
                    ring.join = join; ring.points = points; ring.weight = weight
                    let image = try #require(OllinApp.image(of: ring))
                    let holes = pinholes(of: image)
                    #expect(holes == 0, "\(holes) pinholes: \(join) join, \(points) points, weight \(weight)")
                }
            }
        }
    }
}
