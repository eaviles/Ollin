import Testing
import Foundation
import Ollin

/// The edits that bend an outline, each pinned by what it promises: a warp
/// from a curve onto itself changes nothing and a warp onto a straight target
/// lands where arithmetic says; a pull holds its ends and reaches only its
/// radius; a smoothing that keeps corners keeps a square's four; a split cuts
/// at the corners and nowhere else; a fit passes within its tolerance of
/// every point with a tenth of the points' worth of curves; and a path's
/// cubics trace the outline the path samples.
@Suite
@MainActor
struct BentOutlineTests {

    /// A wavy open trace with uneven spacing.
    static let wave: Contour = {
        var points: [Vector2] = []
        var x = 0.0
        var i = 0
        while x <= 600 {
            points.append(Vector2(x, 200 + 80 * sin(x / 70) + 25 * cos(x / 23)))
            x += 3 + Double(i % 5) * 2.5
            i += 1
        }
        return Contour(points, closed: false)
    }()

    /// A closed lopsided loop.
    static let loop: Contour = {
        let points = (0 ..< 90).map { i -> Vector2 in
            let a = Double(i) / 90 * 2 * .pi
            let r = 150 + 40 * sin(3 * a) + 15 * cos(5 * a)
            return Vector2(300 + r * cos(a), 300 + r * sin(a))
        }
        return Contour(points, closed: true)
    }()

    /// A square of side 200 with `perSide` points along each side.
    static func square(perSide: Int) -> Contour {
        let corners = [Vector2(100, 100), Vector2(300, 100), Vector2(300, 300), Vector2(100, 300)]
        var points: [Vector2] = []
        for k in 0 ..< 4 {
            let a = corners[k], b = corners[(k + 1) % 4]
            for i in 0 ..< perSide { points.append(a + (b - a) * (Double(i) / Double(perSide))) }
        }
        return Contour(points, closed: true)
    }

    /// How far `p` is from the polyline of `contour`.
    static func distance(from p: Vector2, to contour: Contour) -> Double {
        contour.distance(to: p)
    }

    // MARK: Warp

    @Test func aWarpFromACurveOntoItselfIsTheIdentity() {
        let straight = Contour([Vector2(0, 0), Vector2(600, 0)], closed: false)
        let bases = [straight, Self.wave, Self.loop]
        for base in bases {
            for outline in [Self.square(perSide: 7), Self.wave, Self.loop] {
                let warped = outline.warped(from: base, along: base, spacing: 5)
                #expect(warped.isClosed == outline.isClosed)
                // Every original point is still there, and every new point
                // lies on the original outline.
                for p in outline {
                    #expect(Self.distance(from: p, to: warped) < 1e-7)
                }
                for p in warped {
                    #expect(Self.distance(from: p, to: outline) < 1e-7)
                }
            }
        }
    }

    @Test func aWarpLandsAtTheSameFractionAndOffsetAlongTheTarget() {
        // A straight base of 400 and a straight target of 800 turned a
        // quarter turn: a point 30% along and 20 to the side lands 30% along
        // the target, 20 to its right.
        let base = Contour([Vector2(0, 0), Vector2(400, 0)], closed: false)
        let target = Contour([Vector2(50, 50), Vector2(50, 850)], closed: false)
        let point = base.point(at: 0.3) + base.normal(at: 0.3) * 20
        let warped = Contour([point, point + Vector2(0, 40)], closed: false)
            .warped(from: base, along: target, spacing: 0)
        let expected = target.point(at: 0.3) + target.normal(at: 0.3) * 20
        #expect(warped.points[0].distance(to: expected) < 1e-9)
        // The second point was 40 further to the side of the base, so it is
        // 40 further along the target's normal.
        #expect(warped.points[1].distance(to: expected + target.normal(at: 0.3) * 40) < 1e-9)
        // A point past the base's end carries on past the target's end.
        let beyond = Contour([Vector2(450, 0)], closed: false).warped(from: base, along: target, spacing: 0)
        #expect(beyond.points[0].distance(to: Vector2(50, 900)) < 1e-9)
    }

    @Test func aStraightEdgeBendsAlongACurvedTarget() {
        // A straight edge laid along a straight base, warped along a half
        // circle, lands on that circle: every point at the circle's radius.
        let base = Contour([Vector2(0, 0), Vector2(Double.pi * 200, 0)], closed: false)
        let arc = Contour((0 ... 90).map { i -> Vector2 in
            let a = Double(i) / 90 * .pi
            return Vector2(500 + 200 * cos(a), 500 + 200 * sin(a))
        }, closed: false)
        let edge = Contour([Vector2(0, 0), Vector2(Double.pi * 200, 0)], closed: false)
        let bent = edge.warped(from: base, along: arc, spacing: 4)
        #expect(bent.count > 100)
        for p in bent {
            #expect(abs(p.distance(to: Vector2(500, 500)) - 200) < 0.5)
        }
        // A spacing of 0 keeps the two points and leaves the edge straight.
        #expect(edge.warped(from: base, along: arc, spacing: 0).count == 2)
    }

    @Test func aWarpOnAShapeKeepsItsWindingAndItsHoles() {
        let ring = Shape(outer: Self.square(perSide: 4).points,
                         holes: [[Vector2(150, 150), Vector2(250, 150), Vector2(250, 250), Vector2(150, 250)]])
        var shape = ring
        shape.winding = .nonZero
        let base = Contour([Vector2(0, 200), Vector2(400, 200)], closed: false)
        let bent = shape.warped(from: base, along: base)
        #expect(bent.winding == .nonZero)
        #expect(bent.contours.count == 2)
        let allClosed = bent.contours.allSatisfy { $0.isClosed }
        #expect(allClosed)
        #expect(abs(bent.area - shape.area) < 1e-6)
    }

    // MARK: Pull

    @Test func aPullHoldsItsEndsAndReachesOnlyItsRadius() {
        let rope = Contour([Vector2(0, 0), Vector2(600, 0)], closed: false)
        let hand = Vector2(300, 100)
        let pulled = rope.pulled(toward: hand, amount: 0.5, radius: 150, spacing: 2)
        #expect(pulled.isClosed == false)
        #expect(pulled.points.first == Vector2(0, 0))
        #expect(pulled.points.last == Vector2(600, 0))
        var moved = 0
        for p in pulled {
            let original = Vector2(p.x, 0)
            // Nothing outside the radius moved; a pulled point moved toward
            // the hand and never past it.
            if original.distance(to: hand) >= 150 {
                #expect(p.y == 0)
            } else if p.y != 0 {
                moved += 1
                #expect(p.y > 0 && p.y <= 100)
                #expect(p.distance(to: hand) < original.distance(to: hand))
            }
        }
        #expect(moved > 50)
        // The point under the hand moved by the amount, weighted by its
        // distance: a smooth bump of (1 - (d / r)^2)^2.
        let under = pulled.points.first { abs($0.x - 300) < 1e-9 }!
        let q = 1 - (100.0 / 150) * (100.0 / 150)
        #expect(abs(under.y - 100 * 0.5 * q * q) < 1e-9)
    }

    @Test func aPullTapersToAnOpenEndAndNotOnALoop() {
        // Pulled right at an open contour's end, the end stays and the pull
        // fades in over the radius.
        let rope = Contour([Vector2(0, 0), Vector2(600, 0)], closed: false)
        let pulled = rope.pulled(toward: Vector2(0, 60), amount: 1, radius: 100, spacing: 2)
        #expect(pulled.points.first == Vector2(0, 0))
        let near = pulled.points.first { $0.x > 10 && $0.x < 12 }!
        let far = pulled.points.first { $0.x > 50 && $0.x < 52 }!
        #expect(near.y > 0 && far.y > near.y)
        // A loop has no ends, so a pull at one of its points moves it by
        // the bump alone, and a point under the hand moves all the way.
        let loop = Self.square(perSide: 20)
        let corner = loop.points[0]
        let hand = corner + Vector2(-30, -40)
        let tugged = loop.pulled(toward: hand, amount: 1, radius: 100, spacing: 2)
        let q = 1 - 0.25
        #expect(tugged.points[0].distance(to: corner + (hand - corner) * (q * q)) < 1e-9)
        #expect(tugged.isClosed)
        let onto = loop.pulled(toward: corner, amount: 1, radius: 100, spacing: 2)
        #expect(onto.points[0] == corner)
        #expect(onto.points[1].distance(to: corner) < loop.points[1].distance(to: corner))
        // No amount, or no radius, changes nothing.
        #expect(loop.pulled(toward: corner, amount: 0, radius: 100) == loop)
        #expect(loop.pulled(toward: corner, amount: 1, radius: 0) == loop)
    }

    // MARK: Smoothed, corners kept

    @Test func aSquareSmoothedKeepsItsFourCornersAndStraightSides() {
        let square = Self.square(perSide: 25)
        let kept = square.smoothed(neighbors: 6, keepingCornersOver: .pi / 4)
        #expect(kept.count == square.count)
        #expect(kept.isClosed)
        for k in 0 ..< 4 {
            #expect(kept.points[k * 25] == square.points[k * 25])
        }
        for p in kept {
            #expect(Self.distance(from: p, to: square) < 1e-9)
        }
        // The plain smoothing rounds the corners off.
        let plain = square.smoothed(neighbors: 6)
        #expect(plain.points[0].distance(to: square.points[0]) > 1)
        // A loop with no corner over the angle smooths as the plain form does.
        let blob = Self.loop
        #expect(blob.smoothed(neighbors: 3, keepingCornersOver: .pi / 2) == blob.smoothed(neighbors: 3))
    }

    @Test func anOpenOutlineKeepsItsEndsAndItsCorners() {
        // A zigzag with two corners: the corners and the ends stay, the
        // middle of each straight run stays on its line.
        let a = Vector2(0, 0), b = Vector2(100, 100), c = Vector2(200, 0), d = Vector2(300, 100)
        var points: [Vector2] = []
        for (from, to) in [(a, b), (b, c), (c, d)] {
            for i in 0 ..< 20 { points.append(from + (to - from) * (Double(i) / 20)) }
        }
        points.append(d)
        let zigzag = Contour(points, closed: false)
        let kept = zigzag.smoothed(neighbors: 5, keepingCornersOver: .pi / 4)
        #expect(kept.points[0] == a)
        #expect(kept.points[20] == b)
        #expect(kept.points[40] == c)
        #expect(kept.points.last == d)
        for p in kept {
            #expect(Self.distance(from: p, to: zigzag) < 1e-9)
        }
        // A jittered run between the corners is smoothed: its points move,
        // the corners do not.
        var shaky = points
        for i in shaky.indices where i % 20 != 0 && i != shaky.count - 1 {
            shaky[i] = shaky[i] + Vector2(0, i.isMultiple(of: 2) ? 0.6 : -0.6)
        }
        let smooth = Contour(shaky, closed: false).smoothed(neighbors: 3, keepingCornersOver: .pi / 4)
        #expect(smooth.points[20] == b)
        #expect(smooth.points[40] == c)
        let wobble = (1 ..< 19).map { abs(Self.distance(from: smooth.points[$0], to: zigzag)) }.max()!
        #expect(wobble < 0.3)
    }

    // MARK: Split

    @Test func aSplitCutsAtTheCornersAndNowhereElse() throws {
        let a = Vector2(0, 0), b = Vector2(100, 100), c = Vector2(200, 0), d = Vector2(300, 100)
        var points: [Vector2] = []
        for (from, to) in [(a, b), (b, c), (c, d)] {
            for i in 0 ..< 10 { points.append(from + (to - from) * (Double(i) / 10)) }
        }
        points.append(d)
        let zigzag = Contour(points, closed: false)
        let pieces = zigzag.split(atCornersOver: .pi / 4)
        try #require(pieces.count == 3)
        let allOpen = pieces.allSatisfy { !$0.isClosed }
        #expect(allOpen)
        #expect(pieces[0].points.first == a && pieces[0].points.last == b)
        #expect(pieces[1].points.first == b && pieces[1].points.last == c)
        #expect(pieces[2].points.first == c && pieces[2].points.last == d)
        #expect(pieces.map(\.count).reduce(0, +) == zigzag.count + 2)
        // A closed square gives four sides, each from corner to corner.
        let sides = Self.square(perSide: 10).split(atCornersOver: .pi / 4)
        try #require(sides.count == 4)
        for side in sides {
            #expect(side.count == 11)
            #expect(abs(side.length - 200) < 1e-9)
        }
        // A loop with no corner over the angle comes back whole.
        let whole = Self.loop.split(atCornersOver: .pi / 2)
        #expect(whole == [Self.loop])
        // A turn under the angle is not a corner.
        #expect(zigzag.split(atCornersOver: .pi * 0.6).count == 1)
    }

    @Test func aGradualCornerCountsOnceWithASpan() throws {
        // A dense trace rounding two corners over several points: with the
        // turn read at the neighbors each corner spreads over points under
        // the angle, and with a span the turn is read whole.
        var points: [Vector2] = [Vector2(0, 100)]
        func straight(to target: Vector2, steps: Int) {
            let from = points[points.count - 1]
            for i in 1 ... steps { points.append(from + (target - from) * (Double(i) / Double(steps))) }
        }
        func arc(center: Vector2, radius: Double, from: Double, to: Double) {
            for i in 1 ... 8 {
                let a = from + (to - from) * Double(i) / 8
                points.append(center + Vector2(angle: a, length: radius))
            }
        }
        straight(to: Vector2(100, 100), steps: 40)
        arc(center: Vector2(100, 92), radius: 8, from: .pi / 2, to: 0)
        straight(to: Vector2(108, 8), steps: 34)
        arc(center: Vector2(116, 8), radius: 8, from: .pi, to: 1.5 * .pi)
        straight(to: Vector2(216, 0), steps: 40)
        let trace = Contour(points, closed: false)
        #expect(trace.split(atCornersOver: .pi / 3).count == 1)
        let pieces = trace.split(atCornersOver: .pi / 3, span: 14)
        try #require(pieces.count == 3)
        // Each cut sits in its corner's arc.
        #expect(pieces[0].points.last!.distance(to: Vector2(100, 92)) < 9)
        #expect(pieces[1].points.last!.distance(to: Vector2(116, 8)) < 9)
    }

    // MARK: Fit

    /// How far `p` is from any of the cubics, sampled finely.
    static func distance(from p: Vector2, to cubics: [CubicBezier]) -> Double {
        var best = Double.infinity
        for cubic in cubics {
            for i in 0 ... 200 {
                best = min(best, cubic.point(at: Double(i) / 200).distance(to: p))
            }
        }
        return best
    }

    /// How far `p` is from the nearest of the cubics, the parameter refined
    /// by a ternary search inside the best sampled bracket.
    static func exactDistance(from p: Vector2, to cubics: [CubicBezier]) -> Double {
        var best = Double.infinity
        for cubic in cubics {
            var at = 0
            var nearest = Double.infinity
            for i in 0 ... 400 {
                let d = cubic.point(at: Double(i) / 400).distanceSquared(to: p)
                if d < nearest { nearest = d; at = i }
            }
            var low = Double(max(at - 1, 0)) / 400, high = Double(min(at + 1, 400)) / 400
            for _ in 0 ..< 60 {
                let a = low + (high - low) / 3, b = high - (high - low) / 3
                if cubic.point(at: a).distanceSquared(to: p) < cubic.point(at: b).distanceSquared(to: p) {
                    high = b
                } else {
                    low = a
                }
            }
            best = min(best, cubic.point(at: (low + high) / 2).distance(to: p))
        }
        return best
    }

    @Test func theFitPassesWithinTheToleranceWithFewCurves() throws {
        let trace = Contour((0 ... 400).map { i -> Vector2 in
            let x = Double(i) * 1.5
            return Vector2(x, 300 + 120 * sin(x / 90) + 30 * sin(x / 31))
        }, closed: false)
        let path = trace.fitted(tolerance: 1)
        let cubics = path.cubics
        try #require(cubics.count >= 2)
        #expect(cubics.count * 10 <= trace.count, "\(cubics.count) curves for \(trace.count) points")
        for p in trace {
            // Within the tolerance, plus what sampling the curve at 200
            // steps can miss.
            #expect(Self.distance(from: p, to: cubics) < 1.05)
        }
        #expect(!path.contour.isClosed)
        #expect(cubics.first!.start == trace.points.first)
        #expect(cubics.last!.end == trace.points.last)
        // The curves join smoothly: each leaves in the direction the last arrived.
        for k in 1 ..< cubics.count {
            #expect(cubics[k - 1].direction(at: 1).dot(cubics[k].direction(at: 0)) > 0.999)
        }
        // A tighter tolerance needs more curves and a looser one fewer.
        #expect(trace.fitted(tolerance: 0.25).cubics.count > cubics.count)
        #expect(trace.fitted(tolerance: 4).cubics.count < cubics.count)
    }

    @Test func aClosedTraceFitsAsAClosedPathWithASmoothSeam() throws {
        let path = Self.loop.fitted(tolerance: 1)
        let cubics = path.cubics
        try #require(cubics.count >= 2)
        #expect(path.contour.isClosed)
        #expect(cubics.first!.start == cubics.last!.end)
        #expect(cubics.last!.direction(at: 1).dot(cubics.first!.direction(at: 0)) > 0.999)
        for p in Self.loop {
            #expect(Self.distance(from: p, to: cubics) < 1.05)
        }
        // A circle of 300 points is a handful of curves.
        let circle = Contour((0 ..< 300).map { i in
            Vector2(500, 500) + Vector2(angle: Double(i) / 300 * .tau, length: 200)
        }, closed: true)
        #expect(circle.fitted(tolerance: 0.5).cubics.count <= 8)
    }

    @Test func theDegenerateFitsAreStraight() {
        let two = Contour([Vector2(0, 0), Vector2(300, 0)], closed: false).fitted(tolerance: 1)
        #expect(two.cubics.count == 1)
        #expect(two.cubics[0].control1 == Vector2(100, 0))
        #expect(two.cubics[0].control2 == Vector2(200, 0))
        let one = Contour([Vector2(5, 5), Vector2(5, 5)], closed: false).fitted(tolerance: 1)
        #expect(one.cubics.isEmpty)
        #expect(one.contour.points == [Vector2(5, 5)])
        #expect(Contour([], closed: false).fitted(tolerance: 1).cubics.isEmpty)
        // A straight run of many points is one straight curve.
        let line = Contour((0 ... 50).map { Vector2(Double($0) * 4, 10) }, closed: false)
        let fit = line.fitted(tolerance: 0.5)
        #expect(fit.cubics.count == 1)
        for p in line { #expect(Self.distance(from: p, to: fit.cubics) < 0.5) }
    }

    @Test func aShapeFitsOnePathPerContourAndSplitsAcrossThem() {
        let shape = Shape(contours: [Self.loop, Self.square(perSide: 5)])
        let paths = shape.fitted(tolerance: 1)
        #expect(paths.count == 2)
        #expect(paths[0].contour.isClosed && paths[1].contour.isClosed)
        #expect(shape.split(atCornersOver: .pi / 4).count == 5)
        let kept = shape.smoothed(neighbors: 2, keepingCornersOver: .pi / 4)
        #expect(kept.contours[1].points[0] == Vector2(100, 100))
        #expect(kept.winding == shape.winding)
    }

    // MARK: Path.cubics

    @Test func aPathsCubicsTraceTheOutlineItSamples() {
        let path = Path { p in
            p.move(to: Vector2(0, 0))
            p.line(to: Vector2(100, 0))
            p.quadCurve(to: Vector2(200, 100), control: Vector2(200, 0))
            p.curve(to: Vector2(300, 50))
            p.curve(to: Vector2(400, 150))
            p.curve(to: Vector2(500, 100))
            p.cubicCurve(to: Vector2(600, 0), control1: Vector2(520, 160), control2: Vector2(580, -40))
            p.close()
        }
        let cubics = path.cubics
        // A line, a quad, three smooth spans, a cubic, and the closing run.
        #expect(cubics.count == 7)
        #expect(cubics[0].control1 == Vector2(100.0 / 3, 0))
        #expect(cubics[6].end == Vector2(0, 0))
        for p in path.contour {
            #expect(Self.exactDistance(from: p, to: cubics) < 1e-6)
        }
        // Consecutive cubics join end to start.
        for k in 1 ..< cubics.count { #expect(cubics[k - 1].end == cubics[k].start) }
        // A closed path whose pen is already home adds no closing run.
        let home = Path { p in
            p.move(to: Vector2(0, 0))
            p.line(to: Vector2(50, 0))
            p.line(to: Vector2(0, 0))
            p.close()
        }
        #expect(home.cubics.count == 2)
        #expect(Path().cubics.isEmpty)
        // The Hobby fit's segments are the same value.
        let hobby = HobbySpline(through: [Vector2(0, 0), Vector2(100, 50), Vector2(200, 0)])
        let segments: [HobbySpline.Segment] = hobby.segments
        #expect(hobby.path.cubics == segments)
    }

    // MARK: SVG

    private final class Bent: Sketch {
        override var canvasSize: CanvasSize { .square(300) }
        override func draw() {
            background(.white)
            let base = Contour([Vector2(20, 150), Vector2(280, 150)], closed: false)
            let target = Contour(curveThrough: [Vector2(20, 150), Vector2(100, 100), Vector2(200, 200),
                                                Vector2(280, 150)], closed: false)
            let box = Shape([Vector2(40, 120), Vector2(260, 120), Vector2(260, 180), Vector2(40, 180)])
            noStroke()
            fill(.black)
            drawShape(box.warped(from: base, along: target))
            stroke(.red)
            noFill()
            for piece in target.split(atCornersOver: .pi / 3) {
                drawPolyline(piece.fitted(tolerance: 1).contour.points)
            }
        }
    }

    @Test func theSVGWritesTheBentOutlineAsPaths() throws {
        let svg = try OllinApp.svg(of: Bent())
        // The bent box is one filled path, and the fitted pieces are
        // plottable polylines.
        let paths = svg.components(separatedBy: "<path d=").count - 1
        let polylines = svg.components(separatedBy: "<polyline ").count - 1
        #expect(paths >= 1, "\(paths) paths")
        #expect(polylines >= 1, "\(polylines) polylines")
    }
}
