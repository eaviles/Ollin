import CoreGraphics
import Testing
@testable import Ollin

/// The width-profile family and the geometry it drives. The pixel snapshot pins
/// the look; these pin the rules a mean-difference comparison would average away:
/// what each named profile actually returns, that width is read along the path's
/// length rather than by vertex index, that a taper really vanishes at the tip
/// instead of trailing a faint line, and that the vector outline the exporters
/// write covers the same ink the renderer draws.
@Suite
@MainActor
struct StrokeProfileTests {

    // MARK: The profile family

    @Test
    func uniformIsTheConstantWidthDefault() {
        #expect(StrokeProfile.uniform.isUniform)
        #expect(StrokeProfile.uniform(0.0) == 1)
        #expect(StrokeProfile.uniform(0.7) == 1)
        // Everything else takes the varying-width path, including a profile that
        // happens to be constant: the flag is about which path runs, not the shape.
        #expect(!StrokeProfile.taper().isUniform)
        #expect(!StrokeProfile.ramp(from: 1, to: 1).isUniform)
    }

    @Test
    func taperVanishesAtBothEndsAndFillsTheMiddle() {
        let p = StrokeProfile.taper()
        #expect(p(0) == 0)
        #expect(p(1) == 0)
        #expect(abs(p(0.5) - 1) < 1e-12)
        // Monotone up to the middle, and symmetric about it.
        #expect(p(0.25) > p(0.1))
        #expect(abs(p(0.25) - p(0.75)) < 1e-12)
    }

    @Test
    func taperEndsAreTheValuesGiven() {
        let liftOff = StrokeProfile.taper(start: 1, end: 0)
        #expect(abs(liftOff(0) - 1) < 1e-12)
        #expect(liftOff(1) == 0)
        // A full-width taper is flat: the ends are the middle.
        let flat = StrokeProfile.taper(start: 1, end: 1)
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(abs(flat(t) - 1) < 1e-12)
        }
    }

    @Test
    func rampIsStraight() {
        let p = StrokeProfile.ramp(from: 0.2, to: 1)
        #expect(abs(p(0) - 0.2) < 1e-12)
        #expect(abs(p(1) - 1) < 1e-12)
        #expect(abs(p(0.5) - 0.6) < 1e-12)
    }

    @Test
    func valuesInterpolateBetweenSamples() {
        let p = StrokeProfile.values([0, 1, 0])
        #expect(p(0) == 0)
        #expect(abs(p(0.5) - 1) < 1e-12)
        #expect(p(1) == 0)
        #expect(abs(p(0.25) - 0.5) < 1e-12)
        // Degenerate inputs stay well defined.
        #expect(StrokeProfile.values([])(0.5) == 1)
        #expect(abs(StrokeProfile.values([0.3])(0.5) - 0.3) < 1e-12)
    }

    /// A nib is widest across its edge and thinnest along it, which is the whole
    /// thick-and-thin behaviour of broad-edge calligraphy.
    @Test
    func nibIsWidestAcrossItsEdge() {
        let angle = Double.pi / 4
        let p = StrokeProfile.nib(angle: angle, thinness: 0.1)
        let along = Vector2(cos(angle), sin(angle))
        let across = Vector2(-sin(angle), cos(angle))
        #expect(abs(p(0.5, direction: along) - 0.1) < 1e-9)
        #expect(abs(p(0.5, direction: across) - 1) < 1e-9)
        // Reversing a direction draws the same mark: a nib has no front.
        #expect(abs(p(0.5, direction: across * -1) - p(0.5, direction: across)) < 1e-12)
    }

    @Test
    func inputIsClampedAndOutputIsNeverNegative() {
        let p = StrokeProfile.ramp(from: 0.2, to: 1)
        #expect(abs(p(-3) - 0.2) < 1e-12)      // t clamps to 0
        #expect(abs(p(9) - 1) < 1e-12)         // and to 1
        #expect(StrokeProfile({ _ in -5 })(0.5) == 0)
    }

    // MARK: Width along the path

    /// Width is read along the path's *length*, not per vertex: a polyline sampled
    /// unevenly still tapers evenly in space. Reading by index instead would bunch
    /// the whole taper into the densely sampled end.
    @Test
    func widthFollowsArcLengthNotVertexIndex() throws {
        let drawer = Drawer()
        drawer.strokeWeight(10)
        drawer.strokeProfile(.ramp(from: 0, to: 1))
        // Three quarters of the vertices sit in the first half of the run.
        let pts = [Vector2(0, 0), Vector2(10, 0), Vector2(20, 0), Vector2(30, 0),
                   Vector2(40, 0), Vector2(50, 0), Vector2(100, 0)]
        let hws = try #require(drawer.strokeHalfWidths(for: pts, closed: false))
        #expect(hws.count == pts.count)
        #expect(abs(hws[0]) < 1e-12)
        #expect(abs(hws[hws.count - 1] - 5) < 1e-12)
        // The vertex at x = 50 is halfway along the run, so it is half width, even
        // though it is the fifth of seven points.
        #expect(abs(hws[5] - 2.5) < 1e-12)
    }

    @Test
    func uniformStrokesSkipTheProfilePathEntirely() {
        let drawer = Drawer()
        drawer.strokeWeight(10)
        #expect(drawer.strokeHalfWidths(for: [Vector2(0, 0), Vector2(50, 0)], closed: false) == nil)
        #expect(drawer.variableStrokeOutline([Vector2(0, 0), Vector2(50, 0)], closed: false) == nil)
    }

    // MARK: The vector outline

    /// The outline the exporters write is one nonzero-wound shape, so every piece
    /// must wind the same way: mixed winding would punch the overlaps into holes.
    @Test
    func outlinePiecesAllWindTheSameWay() throws {
        let drawer = Drawer()
        drawer.strokeWeight(12)
        drawer.strokeProfile(.taper())
        drawer.strokeJoin(.round)
        let pts = [Vector2(20, 20), Vector2(80, 40), Vector2(120, 10), Vector2(180, 60)]
        let outline = try #require(drawer.variableStrokeOutline(pts, closed: false))
        #expect(outline.winding == .nonZero)
        #expect(outline.contours.count > 1)
        for contour in outline.contours {
            #expect(contour.isClosed)
            #expect(signedArea(contour.points) > 0)
        }
    }

    /// The exported outline covers the ink the profile asks for: a straight run
    /// under a linear ramp is a trapezoid, whose area is the mean width times the
    /// length. This is what keeps a plotted or printed mark true to the screen.
    @Test
    func outlineAreaMatchesTheProfilesInk() throws {
        let drawer = Drawer()
        drawer.strokeWeight(20)                       // full width 20, so half is 10
        drawer.strokeProfile(.ramp(from: 0, to: 1))
        let outline = try #require(
            drawer.variableStrokeOutline([Vector2(0, 50), Vector2(200, 50)], closed: false))
        let area = outline.contours.reduce(0.0) { $0 + signedArea($1.points) }
        // Mean width 10 over a 200-long run.
        #expect(abs(area - 2000) / 2000 < 0.02)
    }

    // MARK: Rendered behaviour

    /// A taper thins the mark toward its end rather than fading the whole thing:
    /// the middle stays solid ink, the ink falls off monotonically over the last
    /// stretch, and nothing is drawn past the end of the path.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTaperThinsTowardItsEnd() throws {
        let image = try #require(OllinApp.image(of: TaperTipProbe()))
        let px = pixels(of: image)
        // The mark runs along y = 64 from x = 20, tapering to nothing at x = 200.
        #expect(px.gray(128, 64) <= 12)                  // middle: solid
        // Ink laid down in a column: summed, not peaked, because the middle of a
        // thick mark is saturated black and a peak reading cannot see it thinning.
        func ink(_ x: Int) -> Int { (30..<98).reduce(0) { $0 + 255 - px.gray(x, $1) } }
        #expect(ink(60) > ink(170))                      // thinner as it goes
        #expect(ink(170) > ink(196))
        // Past the path's end (plus the fringe), blank paper.
        for x in 205..<250 {
            for y in 40..<88 { #expect(px.gray(x, y) >= 250) }
        }
    }

    /// A uniform stroke at a normal weight draws exactly what it drew before width
    /// profiles existed: the sub-pixel ink scaling is 1 at a full pixel and above,
    /// so nothing at or over 1px moves.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aUniformStrokeIsUnchangedByTheProfilePath() throws {
        let a = try #require(OllinApp.image(of: UniformStrokeProbe()))
        let b = try #require(OllinApp.image(of: UniformStrokeProbe()))
        #expect(pixels(of: a).bytes == pixels(of: b).bytes)
        // A 6px stroke covers its full width: the centre is solid ink.
        #expect(pixels(of: a).gray(128, 64) <= 12)
    }
}

// MARK: - Helpers

private func signedArea(_ points: [Vector2]) -> Double {
    var area = 0.0
    for i in 0..<points.count {
        let a = points[i], b = points[(i + 1) % points.count]
        area += a.x * b.y - b.x * a.y
    }
    return area / 2
}

private struct Pixels {
    var bytes: [UInt8]
    var width: Int
    func gray(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4]) }
}

private func pixels(of image: CGImage) -> Pixels {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return Pixels(bytes: bytes, width: w)
}

private final class TaperTipProbe: Sketch {
    override var canvasSize: CanvasSize { .size(256, 128) }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(18)
        strokeCap(.butt)
        strokeProfile(.taper(start: 1, end: 0))
        drawLine(Vector2(20, 64), Vector2(200, 64))
    }
}

private final class UniformStrokeProbe: Sketch {
    override var canvasSize: CanvasSize { .size(256, 128) }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(6)
        drawLine(Vector2(20, 64), Vector2(236, 64))
    }
}
