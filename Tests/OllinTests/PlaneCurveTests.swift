import Testing
import Foundation
import Ollin

/// The plane curves as values, each pinned by closed-form geometry rather than
/// by a copy of its own output: where a segment meets a circle by the
/// quadratic, where two circles meet by the two-circle construction, where
/// two ellipses meet by symmetry, the ellipse's perimeter against a numeric
/// integral and against Ramanujan's approximation, and the sorting, folding,
/// and sweep rules every pair shares.
@Suite struct PlaneCurveTests {

    static func near(_ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-9) -> Bool {
        a.distance(to: b) <= tolerance
    }

    // MARK: Closed forms

    @Test func aSegmentMeetsACircleWhereTheQuadraticSays() throws {
        let circle = Circle(center: Vector2(300, 300), radius: 100)
        let road = LineSegment(Vector2(0, 350), Vector2(600, 350))
        let hits = road.crossings(with: circle)
        try #require(hits.count == 2)
        let half: Double = (100.0 * 100 - 50 * 50).squareRoot()
        #expect(Self.near(hits[0], Vector2(300 - half, 350)))
        #expect(Self.near(hits[1], Vector2(300 + half, 350)))
        // Asked the other way round, the same two points come back sorted
        // round the circle from the right, clockwise on the canvas: the
        // right-hand one first.
        let back = circle.crossings(with: road)
        try #require(back.count == 2)
        #expect(Self.near(back[0], Vector2(300 + half, 350)))
        #expect(Self.near(back[1], Vector2(300 - half, 350)))
        // A segment that ends inside meets the circle once.
        #expect(LineSegment(Vector2(0, 350), Vector2(300, 350)).crossings(with: circle).count == 1)
        // One that misses meets it nowhere.
        #expect(LineSegment(Vector2(0, 500), Vector2(600, 500)).crossings(with: circle).isEmpty)
    }

    @Test func twoSegmentsMeetOnce() throws {
        let a = LineSegment(Vector2(0, 0), Vector2(100, 100))
        let b = LineSegment(Vector2(0, 100), Vector2(100, 0))
        let hits = a.crossings(with: b)
        try #require(hits.count == 1)
        #expect(Self.near(hits[0], Vector2(50, 50)))
        // Parallel segments share no single point.
        #expect(a.crossings(with: LineSegment(Vector2(0, 10), Vector2(100, 110))).isEmpty)
    }

    @Test func twoCirclesMeetWhereTheConstructionSays() throws {
        let p = Circle(center: Vector2(0, 0), radius: 1)
        let q = Circle(center: Vector2(1, 0), radius: 1)
        let hits = p.crossings(with: q)
        try #require(hits.count == 2)
        let h: Double = 3.0.squareRoot() / 2
        // Sorted round p from the right, clockwise on the canvas: +y first.
        #expect(Self.near(hits[0], Vector2(0.5, h)))
        #expect(Self.near(hits[1], Vector2(0.5, -h)))
        // A touch counts once.
        let touching = Circle(center: Vector2(3, 0), radius: 2)
        let touch = p.crossings(with: touching)
        try #require(touch.count == 1)
        #expect(Self.near(touch[0], Vector2(1, 0)))
        // Apart, inside, and coincident: nothing.
        #expect(p.crossings(with: Circle(center: Vector2(5, 0), radius: 1)).isEmpty)
        #expect(p.crossings(with: Circle(center: Vector2(0.1, 0), radius: 0.5)).isEmpty)
        #expect(p.crossings(with: p).isEmpty)
    }

    @Test func arcsKeepOnlyTheirOwnSweep() throws {
        let h: Double = 3.0.squareRoot() / 2
        // The upper halves on the canvas (negative y) of the two circles above.
        let p = Arc(center: Vector2(0, 0), radius: 1, start: .pi, stop: 2 * .pi)
        let q = Arc(center: Vector2(1, 0), radius: 1, start: .pi, stop: 2 * .pi)
        let hits = p.crossings(with: q)
        try #require(hits.count == 1)
        #expect(Self.near(hits[0], Vector2(0.5, -h)))
        // The whole circle against the arc finds the same one.
        #expect(Circle(center: Vector2(0, 0), radius: 1).crossings(with: q).count == 1)
        // An arc that runs the other way round names the other piece.
        let lower = Arc(center: Vector2(1, 0), radius: 1, start: .pi, stop: 0)
        let other = Circle(center: Vector2(0, 0), radius: 1).crossings(with: lower)
        try #require(other.count == 1)
        #expect(Self.near(other[0], Vector2(0.5, h)))
        // A segment through an arc's circle meets the arc only on the sweep.
        let chordLine = LineSegment(Vector2(-2, -0.5), Vector2(2, -0.5))
        #expect(chordLine.crossings(with: p).count == 2)
        #expect(LineSegment(Vector2(-2, 0.5), Vector2(2, 0.5)).crossings(with: p).isEmpty)
        // A full-turn arc is the circle.
        let full = Arc(center: Vector2(0, 0), radius: 1, start: 0.3, stop: 0.3 + 2 * .pi)
        #expect(chordLine.crossings(with: full).count == 2)
    }

    @Test func aSegmentMeetsAnEllipseInItsOwnFrame() throws {
        let ellipse = Ellipse(center: Vector2(500, 500), radiusX: 200, radiusY: 100)
        let upright = LineSegment(Vector2(600, 0), Vector2(600, 1000))
        let hits = upright.crossings(with: ellipse)
        try #require(hits.count == 2)
        let half: Double = 100 * 0.75.squareRoot()
        #expect(Self.near(hits[0], Vector2(600, 500 - half)))
        #expect(Self.near(hits[1], Vector2(600, 500 + half)))
        // Turned a quarter turn, the ellipse's axes swap and the same segment,
        // now laid flat, meets it at the mirrored places.
        let turned = Ellipse(center: Vector2(500, 500), radiusX: 200, radiusY: 100, rotation: .pi / 2)
        let flat = LineSegment(Vector2(0, 600), Vector2(1000, 600))
        let turnedHits = flat.crossings(with: turned)
        try #require(turnedHits.count == 2)
        #expect(Self.near(turnedHits[0], Vector2(500 - half, 600)))
        #expect(Self.near(turnedHits[1], Vector2(500 + half, 600)))
        // A touch counts once.
        let tangent = LineSegment(Vector2(0, 400), Vector2(1000, 400))
        #expect(tangent.crossings(with: ellipse).count == 1)
    }

    @Test func twoEllipsesMeetAtTheClosedFormPoints() throws {
        let center = Vector2(500, 500)
        let wide = Ellipse(center: center, radiusX: 200, radiusY: 100)
        let tall = Ellipse(center: center, radiusX: 100, radiusY: 200)
        let hits = wide.crossings(with: tall)
        try #require(hits.count == 4)
        let d: Double = 200.0 * 100 / (200.0 * 200 + 100 * 100).squareRoot()
        let expected = [Vector2(d, d), Vector2(-d, d), Vector2(-d, -d), Vector2(d, -d)].map { center + $0 }
        for point in expected {
            #expect(hits.contains { Self.near($0, point, 1e-9) }, "\(point)")
        }
        // Sorted round the first ellipse from the end of its x axis, clockwise.
        let angles = hits.map { atan2($0.y - center.y, $0.x - center.x) }
        #expect(angles[0] > 0 && angles[0] < .pi / 2)
        #expect(angles[1] > .pi / 2)
        #expect(angles[2] < -.pi / 2)
        #expect(angles[3] < 0 && angles[3] > -.pi / 2)
        // The same pair turned together moves the crossings with them.
        let turnedWide = Ellipse(center: center, radiusX: 200, radiusY: 100, rotation: 0.7)
        let turnedTall = Ellipse(center: center, radiusX: 100, radiusY: 200, rotation: 0.7)
        let turnedHits = turnedWide.crossings(with: turnedTall)
        try #require(turnedHits.count == 4)
        for point in expected {
            let moved = center + (point - center).rotated(by: 0.7)
            #expect(turnedHits.contains { Self.near($0, moved, 1e-9) }, "\(moved)")
        }
    }

    @Test func anEllipseMeetsACircleAndAnArcExactly() throws {
        let center = Vector2(500, 500)
        let ellipse = Ellipse(center: center, radiusX: 200, radiusY: 50)
        let circle = Circle(center: center, radius: 100)
        let hits = ellipse.crossings(with: circle)
        try #require(hits.count == 4)
        let x: Double = 8000.0.squareRoot(), y: Double = 2000.0.squareRoot()
        for sx in [-1.0, 1.0] {
            for sy in [-1.0, 1.0] {
                let point = center + Vector2(sx * x, sy * y)
                #expect(hits.contains { Self.near($0, point, 1e-9) }, "\(point)")
            }
        }
        // Against an arc, only the sweep's share, and asked from the arc the
        // order follows the arc.
        let arc = Arc(center: center, radius: 100, start: 0, stop: .pi)
        let onArc = arc.crossings(with: ellipse)
        try #require(onArc.count == 2)
        #expect(Self.near(onArc[0], center + Vector2(x, y)))
        #expect(Self.near(onArc[1], center + Vector2(-x, y)))
        // An ellipse with equal radii is a circle and takes the circle's form.
        let round = Ellipse(center: Vector2(1, 0), radiusX: 1, radiusY: 1)
        let unit = Circle(center: .zero, radius: 1)
        let roundHits = unit.crossings(with: round)
        try #require(roundHits.count == 2)
        #expect(Self.near(roundHits[0], Vector2(0.5, 3.0.squareRoot() / 2)))
    }

    // MARK: The rules every pair shares

    @Test func aLineThroughACornerCountsItOnce() throws {
        let box = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let diagonal = LineSegment(Vector2(-50, -50), Vector2(150, 150))
        let hits = diagonal.crossings(with: box)
        try #require(hits.count == 2)
        #expect(Self.near(hits[0], Vector2(0, 0)))
        #expect(Self.near(hits[1], Vector2(100, 100)))
        // The box asked about the diagonal walks its corners from the top left.
        let fromBox = box.crossings(with: diagonal)
        try #require(fromBox.count == 2)
        #expect(Self.near(fromBox[0], Vector2(0, 0)))
        // A circle through a corner, too.
        let ring = Circle(center: Vector2(0, 0), radius: 100)
        let onBox = box.crossings(with: ring)
        try #require(onBox.count == 2)
        #expect(Self.near(onBox[0], Vector2(100, 0)))
        #expect(Self.near(onBox[1], Vector2(0, 100)))
        // And a triangle's edges answer the same way as its contour's.
        let triangle = Triangle(Vector2(0, 0), Vector2(200, 0), Vector2(0, 200))
        let line = LineSegment(Vector2(50, -10), Vector2(50, 300))
        #expect(triangle.crossings(with: line).count == 2)
        #expect(triangle.edges.count == 3)
        #expect(abs(triangle.perimeter - (400 + 200 * 2.0.squareRoot())) < 1e-9)
    }

    @Test func aTouchCountsOnce() throws {
        let circle = Circle(center: Vector2(300, 300), radius: 100)
        let touch = LineSegment(Vector2(0, 200), Vector2(600, 200)).crossings(with: circle)
        try #require(touch.count == 1)
        #expect(Self.near(touch[0], Vector2(300, 200)))
        // A segment ending exactly on the outline counts that end.
        let ending = LineSegment(Vector2(0, 300), Vector2(200, 300)).crossings(with: circle)
        try #require(ending.count == 1)
        #expect(Self.near(ending[0], Vector2(200, 300)))
    }

    @Test func crossingsAreSortedAlongTheAskedCurve() throws {
        let rings = [200.0, 500, 800].map { Circle(center: Vector2($0, 100), radius: 50) }
        let road = LineSegment(Vector2(0, 100), Vector2(1000, 100))
        let hits = rings.flatMap { road.crossings(with: $0) }
        try #require(hits.count == 6)
        // Each ring's pair comes back in the road's direction, and in the
        // other direction when the road runs the other way; a list of any
        // curve answers the same.
        let all: [any PlaneCurve] = rings
        for ring in all {
            let along = road.crossings(with: ring)
            #expect(along.count == 2 && along[0].x < along[1].x)
            let backward = road.reversed().crossings(with: ring)
            #expect(backward.count == 2 && backward[0].x > backward[1].x)
        }
        // A contour asks along its walk.
        let zigzag = Contour([Vector2(0, 120), Vector2(250, 60), Vector2(500, 140), Vector2(750, 60), Vector2(1000, 120)],
                             closed: false)
        let walked = zigzag.crossings(with: rings[1])
        try #require(walked.count == 2)
        #expect(walked[0].x < walked[1].x)
        // And the contour's own crossing call still answers with fractions.
        let detailed: [Contour.Crossing] = zigzag.crossings(with: rings[1].contour)
        #expect(detailed.count == 2)
    }

    @Test func aMixedListAnswersEveryPair() {
        let curves: [any PlaneCurve] = [
            LineSegment(Vector2(0, 500), Vector2(1000, 500)),
            Circle(center: Vector2(300, 500), radius: 120),
            Ellipse(center: Vector2(700, 500), radiusX: 200, radiusY: 80, rotation: 0.4),
            Arc(center: Vector2(500, 500), radius: 300, start: -.pi / 2, stop: .pi / 2),
            Rectangle(x: 200, y: 380, width: 600, height: 240),
        ]
        var total = 0
        for i in curves.indices {
            for j in curves.indices where j > i {
                let hits = curves[i].crossings(with: curves[j])
                let reverse = curves[j].crossings(with: curves[i])
                #expect(hits.count == reverse.count, "\(i) x \(j)")
                for hit in hits {
                    #expect(reverse.contains { Self.near($0, hit, 1e-7) })
                }
                total += hits.count
            }
        }
        #expect(total > 10)
    }

    // MARK: Perimeters, areas, and the questions each value answers

    @Test func perimetersMatchTheAnalyticValues() {
        #expect(abs(Circle(center: .zero, radius: 30).perimeter - 60 * .pi) < 1e-12)
        #expect(abs(Circle(center: .zero, radius: 30).area - 900 * .pi) < 1e-12)
        #expect(Rectangle(x: 0, y: 0, width: 30, height: 40).perimeter == 140)
        #expect(Rectangle(x: 0, y: 0, width: 30, height: 40).area == 1200)
        for (a, b) in [(200.0, 100.0), (100.0, 100.0), (300.0, 20.0), (50.0, 49.0), (1000.0, 1.0)] {
            let ellipse = Ellipse(center: .zero, radiusX: a, radiusY: b, rotation: 0.3)
            // Ramanujan's second approximation, within its known error of
            // about four parts in ten thousand, which it only reaches on a
            // very flat ellipse; a round one agrees to many more digits.
            let h: Double = ((a - b) / (a + b)) * ((a - b) / (a + b))
            let ramanujan: Double = .pi * (a + b) * (1 + 3 * h / (10 + (4 - 3 * h).squareRoot()))
            #expect(abs(ellipse.perimeter - ramanujan) / ramanujan < 4e-4, "\(a) x \(b)")
            if b / a > 0.3 {
                #expect(abs(ellipse.perimeter - ramanujan) / ramanujan < 1e-7, "\(a) x \(b)")
            }
            // And the integral of the speed round the parameter, by Simpson's
            // rule on a fine grid, to the precision the rule allows.
            let n = 20000
            var sum = 0.0
            for i in 0 ... n {
                let t = Double(i) / Double(n) * 2 * .pi
                let speed = (a * a * sin(t) * sin(t) + b * b * cos(t) * cos(t)).squareRoot()
                let weight = i == 0 || i == n ? 1.0 : (i % 2 == 1 ? 4.0 : 2.0)
                sum += weight * speed
            }
            let integral: Double = sum * (2 * .pi / Double(n)) / 3
            #expect(abs(ellipse.perimeter - integral) / integral < 1e-9, "\(a) x \(b)")
            #expect(abs(ellipse.area - .pi * a * b) < 1e-9)
        }
        // A circle's perimeter, exactly, and a flat ellipse's four half-widths.
        #expect(Ellipse(center: .zero, radiusX: 70, radiusY: 70).perimeter == 140 * .pi)
        #expect(Ellipse(center: .zero, radiusX: 70, radiusY: 0).perimeter == 280)
        #expect(abs(Ellipse(center: .zero, radiusX: 5, radiusY: 3).eccentricity - 0.8) < 1e-12)
    }

    @Test func anEllipseKnowsItsBoundsInsideAndNearestPoint() {
        let ellipse = Ellipse(center: Vector2(400, 300), radiusX: 200, radiusY: 80, rotation: 0.6)
        let samples = (0 ..< 4000).map { ellipse.point(at: Double($0) / 4000 * 2 * .pi) }
        let bounds = ellipse.bounds
        let minX = samples.map(\.x).min()!, maxX = samples.map(\.x).max()!
        let minY = samples.map(\.y).min()!, maxY = samples.map(\.y).max()!
        #expect(abs(bounds.x - minX) < 1e-3 && abs(bounds.x + bounds.width - maxX) < 1e-3)
        #expect(abs(bounds.y - minY) < 1e-3 && abs(bounds.y + bounds.height - maxY) < 1e-3)
        for sample in samples.prefix(400) {
            let inward = ellipse.center + (sample - ellipse.center) * 0.98
            let outward = ellipse.center + (sample - ellipse.center) * 1.02
            #expect(ellipse.contains(inward))
            #expect(!ellipse.contains(outward))
        }
        // The nearest point is at least as near as any of the samples.
        for probe in [Vector2(700, 100), Vector2(400, 300), Vector2(420, 290), Vector2(0, 600)] {
            let nearest = ellipse.nearestPoint(to: probe)
            let best = samples.map { $0.distance(to: probe) }.min()!
            #expect(nearest.distance(to: probe) <= best + 1e-6, "\(probe)")
            let local = (nearest - ellipse.center).rotated(by: -ellipse.rotation)
            #expect(abs(local.x * local.x / (200 * 200) + local.y * local.y / (80 * 80) - 1) < 1e-9)
            #expect(abs(ellipse.distance(to: probe) - nearest.distance(to: probe)) < 1e-12)
        }
        // The outline runs clockwise on the canvas from the end of the x axis.
        let contour = ellipse.contour
        #expect(contour.isClosed)
        #expect(Self.near(contour.points[0], ellipse.point(at: 0)))
        #expect(contour.points.count == Circle(center: .zero, radius: 200).contour.points.count)
    }

    @Test func anArcKnowsItsEndsLengthAndBounds() {
        let arc = Arc(center: Vector2(0, 0), radius: 100, start: 0, stop: .pi / 2)
        #expect(Self.near(arc.startPoint, Vector2(100, 0)))
        #expect(Self.near(arc.endPoint, Vector2(0, 100)))
        #expect(abs(arc.length - 50 * .pi) < 1e-9)
        #expect(Self.near(arc.midpoint, Vector2(100 / 2.0.squareRoot(), 100 / 2.0.squareRoot())))
        let bounds = arc.bounds
        #expect(abs(bounds.x) < 1e-9 && abs(bounds.y) < 1e-9)
        #expect(abs(bounds.width - 100) < 1e-9 && abs(bounds.height - 100) < 1e-9)
        #expect(arc.contains(angle: .pi / 4))
        #expect(arc.contains(angle: .pi / 4 + 2 * .pi))
        #expect(!arc.contains(angle: -.pi / 4))
        #expect(arc.contains(angle: 0) && arc.contains(angle: .pi / 2))
        let outline = arc.contour
        #expect(!outline.isClosed)
        #expect(Self.near(outline.points.first!, arc.startPoint) && Self.near(outline.points.last!, arc.endPoint))
        #expect(arc.contour(mode: .pie).points.count == outline.points.count + 1)
        #expect(arc.contour(mode: .chord).isClosed)
        #expect(Self.near(arc.chord.start, arc.startPoint))
        // A negative sweep runs the other way round and its bounds follow.
        let other = Arc(center: Vector2(0, 0), radius: 100, start: 0, stop: -.pi / 2)
        #expect(Self.near(other.endPoint, Vector2(0, -100)))
        #expect(abs(other.bounds.y + 100) < 1e-9)
        #expect(abs(other.length - arc.length) < 1e-12)
        // Nearest point: on the sweep by projection, off it the nearer end.
        #expect(Self.near(arc.nearestPoint(to: Vector2(50, 50)), arc.midpoint))
        #expect(Self.near(arc.nearestPoint(to: Vector2(50, -200)), arc.startPoint))
        #expect(abs(arc.distance(to: Vector2(200, 0)) - 100) < 1e-9)
    }

    @Test func aSegmentAndACircleAnswerTheirOwnQuestions() {
        let segment = LineSegment(Vector2(100, 100), Vector2(400, 500))
        #expect(abs(segment.length - 500) < 1e-12)
        #expect(Self.near(segment.midpoint, Vector2(250, 300)))
        #expect(Self.near(segment.direction, Vector2(0.6, 0.8)))
        #expect(Self.near(segment.point(at: 0.25), Vector2(175, 200)))
        #expect(Self.near(segment.point(at: 2), segment.end))
        #expect(abs(segment.fraction(of: Vector2(175, 200)) - 0.25) < 1e-12)
        #expect(Self.near(segment.nearestPoint(to: Vector2(1000, 1000)), segment.end))
        #expect(abs(segment.distance(to: Vector2(100, 600)) - 300) < 1e-9)
        #expect(segment.reversed().start == segment.end)
        #expect(segment.bounds == Rectangle(x: 100, y: 100, width: 300, height: 400))
        #expect(segment.contour.points == [segment.start, segment.end] && !segment.contour.isClosed)

        let circle = Circle(center: Vector2(100, 100), radius: 50)
        #expect(Self.near(circle.point(at: .pi / 2), Vector2(100, 150)))
        #expect(Self.near(circle.nearestPoint(to: Vector2(400, 100)), Vector2(150, 100)))
        #expect(abs(circle.distance(to: Vector2(400, 100)) - 250) < 1e-9)
        #expect(abs(circle.distance(to: circle.center) - 50) < 1e-12)
        #expect(circle.contour.points.count == circle.contour(segments: nil).points.count)
        #expect(Rectangle(x: 0, y: 0, width: 10, height: 20).edges.map(\.length) == [10, 20, 10, 20])
    }
}
