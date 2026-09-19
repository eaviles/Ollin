import Testing
import Foundation
import Ollin

/// The questions an outline answers about itself, each pinned by a law rather
/// than by a copy of its own output: the tangent against a finite difference
/// of `point(at:)`, the nearest point against a dense sampling, a piece's
/// length against the fractions, crossings of known lines at their closed
/// form, and a simplified trace against the tolerance it was given.
@Suite struct ContourQueryTests {

    /// A wavy open trace with uneven spacing, the kind a hand or a tracer makes.
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

    /// A closed, lopsided loop wound clockwise on the canvas.
    static let loop: Contour = {
        let points = (0..<90).map { i -> Vector2 in
            let a = Double(i) / 90 * 2 * .pi
            let r = 150 + 40 * sin(3 * a) + 15 * cos(5 * a)
            return Vector2(300 + r * cos(a), 300 + r * sin(a))
        }
        return Contour(points, closed: true)
    }()

    // MARK: Tangent and normal

    @Test func theTangentIsTheNormalizedDerivativeOfTheWalk() {
        for contour in [Self.wave, Self.loop] {
            let h = 1e-6
            var checked = 0
            for k in 1..<200 {
                let t = Double(k) / 200
                // A finite difference across a vertex mixes two segments, so
                // compare only where the step stays on one.
                let ahead = contour.point(at: t + h), behind = contour.point(at: t - h)
                let difference = (ahead - behind).normalized
                let tangent = contour.tangent(at: t)
                #expect(abs(tangent.length - 1) < 1e-9)
                if contour.tangent(at: t + h) == contour.tangent(at: t - h) {
                    #expect((tangent - difference).length < 1e-6, "t = \(t)")
                    checked += 1
                }
            }
            #expect(checked > 150)
        }
    }

    @Test func theNormalIsTheTangentTurnedToTheRightOfTravel() {
        // Walking right along the top of a clockwise square, the right hand
        // points down the canvas, into the square.
        let square = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
        #expect(square.tangent(at: 0.1) == Vector2(1, 0))
        #expect(square.normal(at: 0.1) == Vector2(0, 1))
        #expect(square.contains(square.point(at: 0.1) + square.normal(at: 0.1) * 5))
        // Reversed, the same stretch runs the other way and the normal flips.
        // (40, 0) sits 0.65 of the way round the reversed square.
        #expect(square.reversed().point(at: 0.65) == Vector2(40, 0))
        #expect(square.reversed().normal(at: 0.65) == Vector2(0, -1))
        for t in stride(from: 0.05, through: 0.95, by: 0.1) {
            #expect(abs(Self.loop.normal(at: t).dot(Self.loop.tangent(at: t))) < 1e-12)
        }
    }

    @Test func aTangentAtAVertexIsTheSegmentArriving() {
        let corner = Contour([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)], closed: false)
        #expect(corner.tangent(at: 0) == Vector2(1, 0))
        #expect(corner.tangent(at: 0.5) == Vector2(1, 0))
        #expect(corner.tangent(at: 0.5 + 1e-9) == Vector2(0, 1))
        #expect(corner.tangent(at: 1) == Vector2(0, 1))
        #expect(corner.tangent(at: 7) == Vector2(0, 1))
    }

    // MARK: Nearest point

    @Test func theNearestPointIsNoFartherThanAnySampledPoint() {
        let probes = [Vector2(120, 40), Vector2(333, 250), Vector2(590, 420),
                      Vector2(-40, 210), Vector2(300, 300), Vector2(460, 90)]
        for contour in [Self.wave, Self.loop] {
            let samples = (0...4000).map { contour.point(at: Double($0) / 4000) }
            for p in probes {
                let nearest = contour.nearestPoint(to: p)
                let best = samples.map { $0.distance(to: p) }.min()!
                #expect(nearest.distance(to: p) <= best + 1e-9)
                #expect(abs(contour.distance(to: p) - nearest.distance(to: p)) < 1e-12)
                // The fraction is where the nearest point sits on the walk.
                #expect(contour.point(at: contour.fraction(of: p)).distance(to: nearest) < 1e-6)
            }
        }
    }

    @Test func aPointOnTheOutlineIsItsOwnNearestAtItsOwnFraction() {
        for t in stride(from: 0.0, to: 1.0, by: 0.037) {
            let p = Self.loop.point(at: t)
            #expect(Self.loop.distance(to: p) < 1e-9)
            #expect(abs(Self.loop.fraction(of: p) - t) < 1e-9)
        }
    }

    @Test func degenerateOutlinesStillAnswer() {
        let empty = Contour([], closed: false)
        #expect(empty.tangent(at: 0.5) == .zero)
        #expect(empty.nearestPoint(to: Vector2(3, 4)) == .zero)
        #expect(empty.distance(to: Vector2(3, 4)) == .infinity)
        #expect(empty.fraction(of: Vector2(3, 4)) == 0)
        let dot = Contour([Vector2(3, 4)], closed: true)
        #expect(dot.nearestPoint(to: Vector2(6, 8)) == Vector2(3, 4))
        #expect(dot.distance(to: Vector2(6, 8)) == 5)
        #expect(dot.piece(from: 0.2, to: 0.8).points == [Vector2(3, 4)])
        #expect(dot.crossings().isEmpty)
        #expect(dot.simplified(tolerance: 1) == dot)
    }

    // MARK: Pieces

    @Test func aPiecesLengthIsItsShareOfTheWhole() {
        let pairs: [(Double, Double)] = [(0, 1), (0.2, 0.7), (0.513, 0.514), (0.9, 0.1), (0.4, 0.4)]
        for (a, b) in pairs {
            let open = Self.wave.piece(from: a, to: b)
            #expect(abs(open.length - abs(b - a) * Self.wave.length) < 1e-7)
            #expect(!open.isClosed)
            #expect(open.first == Self.wave.point(at: a))
            #expect(open.last == Self.wave.point(at: b))

            // A closed outline always runs forward, through the seam if it must.
            let closed = Self.loop.piece(from: a, to: b)
            let span = b >= a ? b - a : b - a + 1
            #expect(abs(closed.length - span * Self.loop.length) < 1e-7)
            #expect((closed.first?.distance(to: Self.loop.point(at: a)) ?? .infinity) < 1e-9)
            #expect((closed.last?.distance(to: Self.loop.point(at: b)) ?? .infinity) < 1e-9)
        }
    }

    @Test func aPieceKeepsTheVerticesItPassesAndTheWholeLoopComesBackOpen() {
        let square = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
        // From the middle of the left leg round to the middle of the top one.
        let seam = square.piece(from: 0.875, to: 0.125)
        #expect(seam.points == [Vector2(0, 50), Vector2(0, 0), Vector2(50, 0)])
        let whole = square.piece(from: 0, to: 1)
        #expect(whole.points == square.points + [Vector2(0, 0)])
        #expect(!whole.isClosed)
        // Backward on an open run is the forward piece, reversed.
        let line = Contour([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)], closed: false)
        #expect(line.piece(from: 0.75, to: 0.25).points == [Vector2(10, 5), Vector2(10, 0), Vector2(5, 0)])
    }

    // MARK: Crossings

    @Test func twoKnownLinesCrossWhereTheClosedFormSays() throws {
        // y = 0.5x + 10 against y = -2x + 400, sampled as polylines with
        // vertices that miss the crossing: x = 156, y = 88.
        let rising = Contour(stride(from: 0.0, through: 300, by: 7).map { Vector2($0, 0.5 * $0 + 10) },
                             closed: false)
        let falling = Contour(stride(from: 20.0, through: 260, by: 11).map { Vector2($0, -2 * $0 + 400) },
                              closed: false)
        let hits = rising.crossings(with: falling)
        try #require(hits.count == 1)
        let hit = hits[0]
        #expect(hit.point.distance(to: Vector2(156, 88)) < 1e-9)
        #expect(abs(rising.point(at: hit.fraction).distance(to: hit.point)) < 1e-9)
        #expect(abs(falling.point(at: hit.otherFraction).distance(to: hit.point)) < 1e-9)
        // Asked the other way round, the two fractions swap.
        let back = falling.crossings(with: rising)
        try #require(back.count == 1)
        #expect(abs(back[0].fraction - hit.otherFraction) < 1e-12)
        #expect(abs(back[0].otherFraction - hit.fraction) < 1e-12)
    }

    @Test func aCircleAndALineMeetTwiceNearTheirClosedForm() throws {
        // A radius-100 circle at the origin against y = 60: x = ±80.
        let circle = Contour((0..<2000).map { i -> Vector2 in
            let a = Double(i) / 2000 * 2 * .pi
            return Vector2(100 * cos(a), 100 * sin(a))
        })
        let line = Contour([Vector2(-150, 60), Vector2(150, 60)], closed: false)
        let hits = line.crossings(with: circle)
        try #require(hits.count == 2)
        #expect(hits[0].point.distance(to: Vector2(-80, 60)) < 0.01)
        #expect(hits[1].point.distance(to: Vector2(80, 60)) < 0.01)
        // Sorted along the line that asked.
        #expect(abs(hits[0].fraction - 70.0 / 300) < 1e-4)
        #expect(abs(hits[1].fraction - 230.0 / 300) < 1e-4)
    }

    @Test func aCrossingOnAVertexIsFoundOnce() {
        // The vertical line passes exactly through a vertex of the zigzag.
        let zigzag = Contour([Vector2(0, 0), Vector2(50, 50), Vector2(100, 0)], closed: false)
        let line = Contour([Vector2(50, -10), Vector2(50, 100)], closed: false)
        let hits = zigzag.crossings(with: line)
        #expect(hits.count == 1)
        #expect(hits.first?.point == Vector2(50, 50))
        // Parallel lines share no single point.
        let parallel = Contour([Vector2(0, 10), Vector2(100, 10)], closed: false)
        let other = Contour([Vector2(0, 20), Vector2(100, 20)], closed: false)
        #expect(parallel.crossings(with: other).isEmpty)
    }

    @Test func aFigureEightCrossesItselfOnceAtItsWaist() throws {
        // The lemniscate of Gerono, x = sin 2a, y = sin a, crosses at the origin.
        let eight = Contour((0..<400).map { i -> Vector2 in
            // Starting from the top of one lobe, so the waist is passed a
            // quarter and three quarters of the way round.
            let a = .pi / 2 + (Double(i) + 0.5) / 400 * 2 * .pi
            return Vector2(100 * sin(2 * a), 200 * sin(a))
        })
        let hits = eight.crossings()
        try #require(hits.count == 1)
        #expect(hits[0].point.length < 0.1)
        #expect(hits[0].fraction < hits[0].otherFraction)
        #expect(abs(hits[0].fraction - 0.25) < 0.01)
        #expect(abs(hits[0].otherFraction - 0.75) < 0.01)
        // A simple loop never crosses itself, not even where it closes.
        #expect(Self.loop.crossings().isEmpty)
        #expect(Self.wave.crossings().isEmpty)
    }

    @Test func aStarCrossesItselfAtItsInnerCorners() {
        // The pentagram {5/2}: five points joined every second one, five
        // crossings, each at the circumradius times cos(72°)/cos(36°).
        let outer = 100.0
        let star = Contour((0..<5).map { i -> Vector2 in
            let a = Double(i * 2) / 5 * 2 * .pi - .pi / 2
            return Vector2(outer * cos(a), outer * sin(a))
        })
        let hits = star.crossings()
        #expect(hits.count == 5)
        let inner = outer * cos(2 * .pi / 5) / cos(.pi / 5)
        for hit in hits { #expect(abs(hit.point.length - inner) < 1e-9) }
    }

    @Test func theSweepFindsWhatTheBruteForceScanFinds() {
        // A tangled random walk, crossing itself many times: every pair of
        // segments tested directly must agree with the swept count.
        var generator = SplitMix(seed: 7)
        var p = Vector2(300, 300)
        var points = [p]
        for _ in 0..<300 {
            p = p + Vector2(generator.next() * 60 - 30, generator.next() * 60 - 30)
            points.append(p)
        }
        let walk = Contour(points, closed: false)
        var expected = 0
        for i in 0..<(points.count - 1) {
            for j in stride(from: i + 2, to: points.count - 1, by: 1) {
                if Self.segmentsCross(points[i], points[i + 1], points[j], points[j + 1],
                                      lastOwnsEnd: j == points.count - 2) { expected += 1 }
            }
        }
        #expect(expected > 100)
        #expect(walk.crossings().count == expected)
        for hit in walk.crossings() {
            #expect(walk.point(at: hit.fraction).distance(to: hit.point) < 1e-6)
            #expect(walk.point(at: hit.otherFraction).distance(to: hit.point) < 1e-6)
        }
    }

    // MARK: Simplify

    @Test func simplifyKeepsEveryPointWithinTolerance() {
        for contour in [Self.wave, Self.loop] {
            for tolerance in [0.25, 2, 10] {
                let lighter = contour.simplified(tolerance: tolerance)
                #expect(lighter.count < contour.count)
                #expect(lighter.isClosed == contour.isClosed)
                for p in contour { #expect(lighter.distance(to: p) <= tolerance + 1e-9) }
            }
        }
        let open = Self.wave.simplified(tolerance: 5)
        #expect(open.first == Self.wave.first && open.last == Self.wave.last)
        // A looser tolerance never keeps more.
        #expect(Self.wave.simplified(tolerance: 10).count <= Self.wave.simplified(tolerance: 2).count)
    }

    @Test func simplifyKeepsTheTurnOfARunThatDoublesBack() {
        // Out along the x axis and most of the way back: every point is on
        // the line through the two ends, but not on the segment between them.
        let hairpin = Contour([Vector2(0, 0), Vector2(50, 0.2), Vector2(100, 0),
                               Vector2(60, 0.1), Vector2(20, 0)], closed: false)
        let lighter = hairpin.simplified(tolerance: 1)
        #expect(lighter.contains(where: { $0.x == 100 }))
        for p in hairpin { #expect(lighter.distance(to: p) <= 1 + 1e-9) }
    }

    @Test func aStraightRunSimplifiesToItsEnds() {
        let line = Contour((0...50).map { Vector2(Double($0) * 4, Double($0) * 2) }, closed: false)
        #expect(line.simplified(tolerance: 1e-9).points == [Vector2(0, 0), Vector2(200, 100)])
    }

    // MARK: Reversing

    @Test func reversedWalksTheOtherWay() {
        let r = Self.wave.reversed()
        #expect(r.points == Array(Self.wave.points.reversed()))
        #expect(!r.isClosed)
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(r.point(at: t).distance(to: Self.wave.point(at: 1 - t)) < 1e-9)
        }
        #expect(Self.loop.reversed().isClosed)
        // Read as an array, it is the points in reverse.
        #expect(Array(Self.loop.reversed()) == Array(Self.loop.points.reversed()))
    }

    // MARK: Corners

    @Test func aRoundedSquareIsItsStraightsAndOneCircle() {
        let square = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
        let rounded = square.rounded(10)
        let expected = 4 * 80 + 2 * Double.pi * 10
        // Each arc is drawn as chords, which run a little short of it.
        #expect(rounded.length < expected && rounded.length > expected - 0.5)
        // Every arc point is ten from its corner's center.
        let centers = [Vector2(10, 10), Vector2(90, 10), Vector2(90, 90), Vector2(10, 90)]
        for p in rounded where !(p.x > 10 && p.x < 90) && !(p.y > 10 && p.y < 90) {
            #expect(centers.contains { abs($0.distance(to: p) - 10) < 1e-9 })
        }
        // No corner is left.
        #expect(!rounded.contains(where: { $0 == Vector2(0, 0) }))
        #expect(square.rounded(0) == square)
    }

    @Test func aChamferedSquareIsAnOctagon() {
        let square = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)])
        let cut = square.chamfered(10)
        #expect(cut.count == 8)
        #expect(abs(cut.length - (4 * 80 + 4 * 10 * 2.squareRoot())) < 1e-9)
        #expect(cut.points.first == Vector2(0, 10))
    }

    @Test func aCornerIsLimitedByItsShorterEdge() {
        // An equilateral triangle rounded past what it can take becomes its
        // incircle: the arcs meet at the midpoints of the sides.
        let side = 120.0
        let triangle = Contour([Vector2(0, 0), Vector2(side, 0), Vector2(side / 2, side * 3.squareRoot() / 2)])
        let round = triangle.rounded(1000)
        let incenter = Vector2(side / 2, side * 3.squareRoot() / 6)
        let inradius = side / (2 * 3.squareRoot())
        for p in round { #expect(abs(p.distance(to: incenter) - inradius) < 1e-9) }
        // An open run keeps its ends, and its first and last edges give their
        // whole length to the one corner they reach.
        let elbow = Contour([Vector2(0, 0), Vector2(40, 0), Vector2(40, 100)], closed: false)
        let chamfered = elbow.chamfered(60)
        #expect(chamfered.points == [Vector2(0, 0), Vector2(40, 40), Vector2(40, 100)])
        let rounded = elbow.rounded(15)
        #expect(rounded.first == Vector2(0, 0) && rounded.last == Vector2(40, 100))
    }

    @Test func aShapeRoundsEveryContourAndKeepsItsWinding() {
        let ring = Shape(contours: [
            Contour([Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)]),
            Contour([Vector2(50, 50), Vector2(150, 50), Vector2(150, 150), Vector2(50, 150)]),
        ], winding: .nonZero)
        let soft = ring.rounded(20)
        #expect(soft.winding == .nonZero)
        #expect(soft.count == 2)
        #expect(soft.contours[1] == ring.contours[1].rounded(20))
        #expect(ring.chamfered(5).contours[0] == ring.contours[0].chamfered(5))
        #expect(ring.simplified(tolerance: 1).contours[0] == ring.contours[0].simplified(tolerance: 1))
    }

    // MARK: Helpers

    /// The segment test written out plainly, owning each start and not each
    /// far end, for the brute-force comparison.
    static func segmentsCross(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2,
                              lastOwnsEnd: Bool) -> Bool {
        let r = b - a, v = d - c
        let denominator = r.x * v.y - r.y * v.x
        if abs(denominator) < 1e-12 { return false }
        let s = ((c.x - a.x) * v.y - (c.y - a.y) * v.x) / denominator
        let u = ((c.x - a.x) * r.y - (c.y - a.y) * r.x) / denominator
        return s >= 0 && s < 1 && u >= 0 && (lastOwnsEnd ? u <= 1 : u < 1)
    }
}

/// A small seeded generator for the tests' own walks.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
