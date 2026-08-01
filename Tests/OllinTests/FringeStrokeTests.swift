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

    /// The rendered frame as one gray value per pixel (the drawings here are
    /// black ink on white paper, so any channel will do).
    private func grays(of image: CGImage) -> (w: Int, h: Int, at: (Int, Int) -> Int) {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, { x, y in Int(bytes[(y * w + x) * 4]) })
    }

    /// Pixels lighter than the ink around them, with solid ink on all four
    /// sides. Nothing legitimate draws one: an anti-aliased edge always has
    /// paper on one side.
    private func pinholes(of image: CGImage) -> Int {
        let (w, h, gray) = grays(of: image)
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

    // MARK: One coat of ink

    /// A single corner in translucent ink, drawn thick enough that a second
    /// coat would be unmissable.
    private final class Vee: Sketch {
        var join: StrokeJoin = .miter
        var angle = 90.0
        override var canvasSize: CanvasSize { .square(512) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            stroke(Color.black.withAlpha(0.25))
            strokeWeight(40)
            strokeJoin(join)
            strokeCap(.butt)
            noFill()
            let corner = Vector2(256, 380)
            let half = angle / 2 * .pi / 180
            drawPolyline([corner + Vector2(-sin(half), -cos(half)) * 200, corner,
                          corner + Vector2(sin(half), -cos(half)) * 200], closed: false)
        }
    }

    /// A half turn in translucent ink, dense enough that the joins run into
    /// each other.
    private final class Turn: Sketch {
        var points = 120
        override var canvasSize: CanvasSize { .square(512) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            stroke(Color.black.withAlpha(0.25))
            strokeWeight(40)
            strokeJoin(.round)
            noFill()
            drawPolyline((0..<points).map { i in
                let a = Double.pi * Double(i) / Double(points - 1)
                return Vector2(256, 256) + Vector2(cos(a), sin(a)) * 150
            }, closed: false)
        }
    }

    /// On the inside of a turn the two segments' edges cross, so a segment that
    /// ends on its own perpendicular runs past the crossing and into its
    /// neighbour. Opaque ink hides that; translucent ink composites the wedge
    /// twice and the corner grows a hard darker patch, a full second coat at a
    /// right angle (224 against 197, which is 0.75 against 0.75 squared in the
    /// linear light everything composites in).
    ///
    /// The join style is in the loop because it must stay irrelevant: the join
    /// filler only ever touches the outside of the turn, so all three styles
    /// darkened identically before the segments were made to share the
    /// crossing point, and all three must stay clean now.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTranslucentCornerIsPaintedOnce() throws {
        for join in [StrokeJoin.miter, .round, .bevel] {
            for angle in [45.0, 90.0, 140.0] {
                let vee = Vee()
                vee.join = join; vee.angle = angle
                let (_, _, gray) = grays(of: try #require(OllinApp.image(of: vee)))
                // One coat, read mid-arm where nothing but the one segment covers.
                let half = angle / 2 * .pi / 180
                let arm = Vector2(256, 380) + Vector2(-sin(half), -cos(half)) * 110
                let coat = gray(Int(arm.x), Int(arm.y))
                // Nothing anywhere near the corner may be darker than that.
                var darkest = 255
                for y in 320...440 where y > 0 {
                    for x in 196...316 { darkest = min(darkest, gray(x, y)) }
                }
                #expect(darkest >= coat - 1,
                        "\(join) join at \(angle) degrees: corner \(darkest) against arm \(coat)")
            }
        }
    }

    /// The same defect spread thin. Every join on a curve overlaps its
    /// neighbour a little, always on the inside, and the wedge grows with the
    /// distance from the centerline, so the stroke used to darken as a graded
    /// band down its inner half (mean 224.6 falling to 221.5, with single
    /// pixels as low as 197). Across the band the coat is now flat.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTranslucentTurnLaysDownOneEvenCoat() throws {
        for points in [40, 120, 360] {
            let (_, _, gray) = grays(of: try #require(OllinApp.image(of: Turn())))
            // Mean and darkest at each radius across the 40pt band, sampled all
            // along the arc so an isolated speck at one join is not stepped over.
            var means: [Double] = []
            for r in stride(from: 134.0, through: 166.0, by: 4) {
                var sum = 0, darkest = 255
                let taps = 600
                for k in 0..<taps {
                    let a = Double.pi * (0.1 + 0.8 * Double(k) / Double(taps - 1))
                    let v = gray(Int((256 + cos(a) * r).rounded()), Int((256 + sin(a) * r).rounded()))
                    sum += v; darkest = min(darkest, v)
                }
                let mean = Double(sum) / Double(taps)
                means.append(mean)
                #expect(Double(darkest) >= mean - 1.5,
                        "\(points) points, radius \(r): darkest \(darkest) against mean \(mean)")
            }
            let flat = (means.max() ?? 0) - (means.min() ?? 0)
            #expect(flat <= 1, "\(points) points: coat varies by \(flat) across the band")
        }
    }
}
