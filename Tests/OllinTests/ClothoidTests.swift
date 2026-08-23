@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on the clothoid. Every one of these is a law rather than a
/// matter of taste, which is the point: a curve that bends slightly wrong
/// looks exactly as good as the right one, and the whole reason to reach for
/// this curve instead of an arc is a property the eye cannot check.
///
/// The load-bearing pair is the bend law and the Fresnel pair. The first says
/// the bend is a straight line in the distance traveled, which is the entire
/// definition of the curve. The second pins the position against numbers
/// published long before any of this was written, so a quadrature that drifts
/// is caught rather than believed.
@Suite
struct ClothoidTests {

    /// The Fresnel integrals at a few points, from the standard tables. A
    /// clothoid whose bend grows at `pi` per unit is the Fresnel pair exactly,
    /// so these are the positions its end must land on.
    private static let fresnel: [(t: Double, c: Double, s: Double)] = [
        (0.5, 0.492344225871, 0.064732432860),
        (1.0, 0.779893400377, 0.438259147390),
        (1.5, 0.445261176040, 0.697504960082),
        (2.0, 0.488253406075, 0.343415678364),
        (3.0, 0.605720789298, 0.496312998967),
    ]

    /// The bend of the circle through three points, signed the way the curve
    /// is signed. It is the only way to ask a drawn polyline how hard it turns.
    private func measuredCurvature(_ a: Vector2, _ b: Vector2, _ c: Vector2) -> Double {
        let ab = b - a, bc = c - b, ac = c - a
        let denominator = ab.length * bc.length * ac.length
        guard denominator > 0 else { return 0 }
        return 2 * ab.cross(bc) / denominator
    }

    private func wrapped(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }

    private func polylineLength(_ points: [Vector2]) -> Double {
        guard points.count > 1 else { return 0 }
        return (1..<points.count).reduce(0) { $0 + points[$1].distance(to: points[$1 - 1]) }
    }

    // MARK: - The definition

    @Test func theBendGrowsInStepWithTheLength() {
        // The whole definition of the curve, measured off the drawn points
        // rather than read back out of the numbers that made them.
        let curve = Clothoid(
            start: Vector2(100, 200), heading: 0.4,
            curvature: -0.004, curvatureRate: 0.00008, length: 300
        )
        let count = 3001
        let points = curve.points(count: count)
        let step = curve.length / Double(count - 1)
        for i in 1..<(count - 1) {
            let s = Double(i) * step
            let measured = measuredCurvature(points[i - 1], points[i], points[i + 1])
            let stated = curve.curvature(at: s)
            #expect(abs(measured - stated) < 1e-7,
                    "at \(s) along, the drawing bends \(measured) where the rule says \(stated)")
        }
    }

    @Test func theCurveIsTheFresnelPair() {
        for sample in Self.fresnel {
            let arm = Clothoid(curvatureRate: .pi, length: sample.t)
            let end = arm.end
            #expect(abs(end.x - sample.c) < 1e-12,
                    "C(\(sample.t)) came out \(end.x), not \(sample.c)")
            #expect(abs(end.y - sample.s) < 1e-12,
                    "S(\(sample.t)) came out \(end.y), not \(sample.s)")
        }
    }

    @Test func theQuadratureHoldsUpWhenTheCurveWindsHard() {
        // Fifty turns in, the phase sweeps more than 300 radians across the
        // one unit the integral runs over. The panel count grows with the
        // sweep, and this is the check that it grows fast enough: the answer
        // is compared against the same integral worked out the plainest way
        // there is, two million panels of Simpson's rule.
        let turns = 50.0
        let t = (4 * turns).squareRoot()
        let a = Double.pi * t * t
        let reference = simpsonMomenta(a: a, b: 0, c: 0, panels: 2_000_000)
        let measured = clothoidMomenta(0, a, 0, 0)
        #expect(abs(measured.x - reference.x) < 1e-12,
                "the cosine part reads \(measured.x) where \(reference.x) is due")
        #expect(abs(measured.y - reference.y) < 1e-12,
                "the sine part reads \(measured.y) where \(reference.y) is due")

        // And the picture that goes with it: far out the curve is circling one
        // of the two eyes at (0.5, 0.5), at a radius of 1 / (pi * t).
        let arm = Clothoid(curvatureRate: .pi, length: t)
        let orbit = arm.end.distance(to: Vector2(0.5, 0.5))
        #expect(abs(orbit - 1 / (.pi * t)) / orbit < 0.01,
                "the arm sits \(orbit) from its eye, nowhere near the orbit it should be on")
    }

    @Test func theSampledLengthIsTheLengthItWasGiven() {
        // A polyline is always shorter than the curve it samples, by the
        // square of the step. So the law is not one number: it is that the
        // shortfall falls by four every time the point count doubles.
        let curve = Clothoid(curvature: 0.002, curvatureRate: -0.0004, length: 420)
        var shortfalls = [Double]()
        for count in [5_001, 10_001, 20_001, 40_001] {
            shortfalls.append(420 - polylineLength(curve.points(count: count)))
        }
        #expect(shortfalls.allSatisfy { $0 > 0 }, "a chord cannot be longer than its arc")
        for i in 1..<shortfalls.count {
            let ratio = shortfalls[i - 1] / shortfalls[i]
            #expect(abs(ratio - 4) < 0.1,
                    "doubling the points cut the shortfall by \(ratio), not by 4")
        }
        #expect(shortfalls.last! / 420 < 1e-7,
                "and 40,000 points must land within a ten-millionth: \(shortfalls.last!)")

        // A straight line and an arc have no shortfall to speak of at all.
        for rate in [0.0, 0.00002] {
            let gentle = Clothoid(curvature: 0.002, curvatureRate: rate, length: 420)
            let measured = polylineLength(gentle.points(count: 40_001))
            #expect(abs(measured - 420) / 420 < 1e-9,
                    "a gentle curve of length 420 drew \(measured) at rate \(rate)")
        }
    }

    /// The same integral `clothoidMomenta` works out, done the plainest way
    /// there is. Slow and obvious, which is what makes it worth comparing to.
    private func simpsonMomenta(a: Double, b: Double, c: Double, panels: Int) -> (x: Double, y: Double) {
        let even = panels % 2 == 0 ? panels : panels + 1
        let h = 1.0 / Double(even)
        func phase(_ t: Double) -> Double { 0.5 * a * t * t + b * t + c }
        var sumX = cos(phase(0)) + cos(phase(1))
        var sumY = sin(phase(0)) + sin(phase(1))
        for i in 1..<even {
            let weight = i % 2 == 0 ? 2.0 : 4.0
            let p = phase(Double(i) * h)
            sumX += weight * cos(p)
            sumY += weight * sin(p)
        }
        return (sumX * h / 3, sumY * h / 3)
    }

    @Test func theCurveGoesTheWayItSaysItFaces() {
        let curve = Clothoid(
            start: Vector2(-30, 12), heading: 2.1,
            curvature: 0.01, curvatureRate: -0.00006, length: 250
        )
        for fraction in stride(from: 0.0, through: 1.0, by: 0.05) {
            let s = fraction * curve.length
            let ahead = curve.point(at: s + 1e-5)
            let behind = curve.point(at: s - 1e-5)
            let measured = (ahead - behind).angle
            #expect(abs(wrapped(measured - curve.heading(at: s))) < 1e-8,
                    "at \(s) along it moves toward \(measured), not \(curve.heading(at: s))")
        }
    }

    @Test func spacingAndTurnBothDecideThePointCount() {
        // A short, hard corner must not go faceted just because it is short.
        let tight = Clothoid(curvature: 0.5, curvatureRate: 0, length: 6)
        #expect(tight.points(spacing: 100).count > 60,
                "a curve turning 3 radians in 6 units came back with too few points")
        let straight = Clothoid(curvatureRate: 0, length: 100)
        #expect(straight.points(spacing: 10).count == 11)
    }

    @Test func absurdArgumentsDoNotBringItDown() {
        // Converting a Double that is huge or not a number to an Int traps in
        // Swift, so every count worked out from an argument is clamped first.
        // These all used to be one step from a crash.
        let tiny = Clothoid(curvatureRate: 0.001, length: 400)
        #expect(tiny.points(spacing: 1e-300).count == 100_000)
        #expect(tiny.points(spacing: 2, angle: 1e-320).count == 100_000)
        #expect(tiny.points(spacing: .nan).count >= 2)
        #expect(tiny.points(spacing: 0).count >= 2)

        let vast = Clothoid(curvature: 1e290, curvatureRate: 1e290, length: 1e10)
        #expect(vast.points(count: 3).count == 3)
        #expect(vast.point(at: 1).x.isFinite || vast.point(at: 1).x.isNaN)

        // And a curve with nothing to draw comes back empty rather than wrong.
        #expect(Clothoid(curvatureRate: 0, length: 0).points(count: 0).isEmpty)
        #expect(eulerSpiral(size: 100, turns: 0).isEmpty)
        #expect(clothoidSpline(through: [Vector2(1, 1)]).isEmpty)
        #expect(clothoidCorners([Vector2(0, 0), Vector2(1, 1)], radius: 5, easement: 5).count == 1)
    }

    // MARK: - The easement

    @Test func anEasementEndsBendingExactlyAsHardAsItsArc() {
        for radius in [40.0, 200.0, -150.0] {
            for length in [30.0, 260.0] {
                let easement = Clothoid.easement(
                    from: Vector2(10, 20), heading: 0.3, radius: radius, length: length
                )
                #expect(easement.curvature == 0, "an easement must begin straight")
                #expect(abs(easement.endCurvature - 1 / radius) < 1e-15,
                        "it must hand over at the arc's own bend")
                // Half of what the same length of arc would turn: the piece
                // spends its first half hardly bending at all.
                #expect(abs(easement.turn - length / (2 * radius)) < 1e-15)
            }
        }
    }

    @Test func theEasementShiftMatchesTheSurveyorsRule() {
        // Road tables give the shift, how far the arc is pushed away from the
        // straight it left, as `length * length / (24 * radius)`. That is the
        // leading term of the real thing, so it must be close and it must get
        // closer as the piece gets gentler.
        let radius = 300.0
        var errors = [Double]()
        for length in [40.0, 80.0, 160.0] {
            let easement = Clothoid.easement(from: .zero, heading: 0, radius: radius, length: length)
            let spiralAngle = easement.endHeading
            let centerY = easement.end.y + radius * cos(spiralAngle)
            let shift = centerY - radius
            let rule = length * length / (24 * radius)
            errors.append(abs(shift - rule) / rule)
        }
        #expect(errors[0] < 0.001, "the gentlest piece must match the rule closely")
        #expect(errors[0] < errors[1] && errors[1] < errors[2],
                "and the match must get better as the piece gets gentler: \(errors)")
    }

    // MARK: - The fit

    @Test func theSlopeTheFitSolvesWithIsTheRightSlope() {
        // Newton needs the slope of the arrival error against the one unknown.
        // Getting it wrong still converges sometimes, which is the trap.
        for (sweep, phi0) in [(0.4, 0.2), (-1.7, 0.9), (2.5, -1.1)] {
            for a in [-3.0, -0.2, 0.0, 1.4, 6.0] {
                let h = 1e-6
                let up = clothoidMomenta(0, 2 * (a + h), sweep - (a + h), phi0).y
                let down = clothoidMomenta(0, 2 * (a - h), sweep - (a - h), phi0).y
                let numeric = (up - down) / (2 * h)
                let stated = clothoidMomenta(2, 2 * a, sweep - a, phi0).x
                    - clothoidMomenta(1, 2 * a, sweep - a, phi0).x
                #expect(abs(numeric - stated) < 1e-8,
                        "at a=\(a) the slope reads \(stated) where \(numeric) is measured")
            }
        }
    }

    @Test func theFitArrivesWhereItWasTold() {
        // Every configuration of two headings, on a grid, including the ones
        // that are really a straight line or an arc.
        let start = Vector2(120, 340)
        let target = Vector2(760, 610)
        let steps = 48
        var worstPosition = 0.0
        var worstHeading = 0.0
        for i in 0...steps {
            for j in 0...steps {
                let a = (Double(i) / Double(steps) * 2 - 1) * 0.999 * .pi
                let b = (Double(j) / Double(steps) * 2 - 1) * 0.999 * .pi
                guard let fit = Clothoid(from: start, heading: a, to: target, heading: b) else {
                    Issue.record("no curve fitted for headings \(a), \(b)")
                    continue
                }
                #expect(fit.length > 0, "a fitted curve must run forward, not back")
                worstPosition = max(worstPosition, fit.end.distance(to: target))
                worstHeading = max(worstHeading, abs(wrapped(fit.endHeading - b)))
            }
        }
        #expect(worstPosition < 1e-8, "worst arrival was \(worstPosition) away")
        #expect(worstHeading < 1e-9, "worst arrival heading was \(worstHeading) out")
    }

    @Test func theFitTreatsLinesAndArcsAsOrdinary() {
        // Both are clothoids whose bend stops growing. The method is built so
        // that neither needs its own branch, and this is the check that no
        // branch quietly appeared.
        let a = Vector2(100, 100)
        let b = Vector2(500, 100)

        let line = Clothoid(from: a, heading: 0, to: b, heading: 0)
        #expect(line != nil)
        #expect(abs(line!.curvature) < 1e-12, "a straight run must not bend")
        #expect(abs(line!.curvatureRate) < 1e-12, "and its bend must not grow")
        #expect(abs(line!.length - 400) < 1e-9, "it must be exactly as long as the gap")

        // A half turn to the left over the same gap is the semicircle on it.
        let arc = Clothoid(from: a, heading: .pi / 2, to: b, heading: -.pi / 2)
        #expect(arc != nil)
        #expect(abs(arc!.curvatureRate) < 1e-12, "an arc's bend must not grow")
        #expect(abs(abs(arc!.curvature) - 1 / 200.0) < 1e-9,
                "the semicircle on a 400 gap has radius 200, not \(1 / arc!.curvature)")
        #expect(abs(arc!.length - .pi * 200) < 1e-7)
    }

    @Test func aFitToNowhereIsRefused() {
        let here = Vector2(10, 10)
        #expect(Clothoid(from: here, heading: 0, to: here, heading: 1) == nil)
    }

    // MARK: - Chains

    @Test func aSplinePassesThroughEveryPointAndNeverKinks() {
        let waypoints = [
            Vector2(120, 700), Vector2(300, 300), Vector2(560, 620),
            Vector2(820, 260), Vector2(950, 640),
        ]
        let pieces = clothoidSpline(through: waypoints)
        #expect(pieces.count == waypoints.count - 1)
        for (i, piece) in pieces.enumerated() {
            #expect(piece.start.distance(to: waypoints[i]) < 1e-9,
                    "piece \(i) must begin on its point")
            #expect(piece.end.distance(to: waypoints[i + 1]) < 1e-8,
                    "piece \(i) must arrive on the next point")
            if i > 0 {
                let kink = abs(wrapped(piece.heading - pieces[i - 1].endHeading))
                #expect(kink < 1e-9, "piece \(i) starts \(kink) off the way the last one arrived")
            }
        }
    }

    @Test func aClosedSplineComesBackToWhereItStarted() {
        let waypoints = [
            Vector2(300, 300), Vector2(700, 320), Vector2(760, 700), Vector2(280, 660),
        ]
        let pieces = clothoidSpline(through: waypoints, closed: true)
        #expect(pieces.count == waypoints.count)
        let kink = abs(wrapped(pieces[0].heading - pieces[pieces.count - 1].endHeading))
        #expect(kink < 1e-9, "the seam kinks by \(kink)")
        #expect(pieces[pieces.count - 1].end.distance(to: waypoints[0]) < 1e-8)
    }

    @Test func aChainCanBeDrivenByDistance() {
        let route = clothoidCorners(
            [Vector2(100, 100), Vector2(500, 140), Vector2(560, 600), Vector2(180, 640)],
            radius: 90, easement: 70
        )
        let total = route.length
        #expect(total > 0)
        #expect(route.point(at: 0)!.distance(to: route[0].start) < 1e-12)
        #expect(route.point(at: total)!.distance(to: route[route.count - 1].end) < 1e-9)

        // Past either end it reads the end rather than running off.
        #expect(route.point(at: -50)!.distance(to: route[0].start) < 1e-12)
        #expect(route.point(at: total + 50)!.distance(to: route[route.count - 1].end) < 1e-9)

        // Driving it at a steady rate must cover ground at a steady rate,
        // which is the whole reason a chain is measured by length.
        let steps = 400
        var gaps = [Double]()
        for i in 1...steps {
            let a = route.point(at: total * Double(i - 1) / Double(steps))!
            let b = route.point(at: total * Double(i) / Double(steps))!
            gaps.append(a.distance(to: b))
        }
        let spread = (gaps.max()! - gaps.min()!) / gaps.max()!
        #expect(spread < 0.01, "the steps came out \(spread) uneven")

        // And the bend read by distance must never jump, which is the same
        // law again from the driver's seat.
        var worst = 0.0
        for i in 1...4000 {
            let a = route.curvature(at: total * Double(i - 1) / 4000)!
            let b = route.curvature(at: total * Double(i) / 4000)!
            worst = max(worst, abs(b - a))
        }
        #expect(worst < 0.001, "the wheel jerked by \(worst) between two steps")
    }

    // MARK: - Corners

    /// The largest jump in bend from one sampled point to the next, ignoring
    /// the few points nearest each end where three-point curvature has nothing
    /// to work with.
    private func worstBendJump(_ points: [Vector2]) -> Double {
        guard points.count > 4 else { return 0 }
        var curvatures = [Double]()
        for i in 1..<(points.count - 1) {
            curvatures.append(measuredCurvature(points[i - 1], points[i], points[i + 1]))
        }
        var worst = 0.0
        for i in 1..<curvatures.count {
            worst = max(worst, abs(curvatures[i] - curvatures[i - 1]))
        }
        return worst
    }

    @Test func aRouteHandsOverItsBendExactlyAtEveryJoin() {
        // The sampled check below can only measure this. Here it is exact: a
        // piece must begin bending precisely as hard as the one before it
        // stopped, and facing precisely the way it was facing. That is the
        // whole promise of the curve, and it must hold at a shrunk corner too.
        let legs = [
            Vector2(150, 800), Vector2(540, 200), Vector2(930, 780),
            Vector2(980, 300), Vector2(200, 240),
        ]
        for (radius, easement) in [(120.0, 150.0), (400.0, 400.0), (30.0, 4.0)] {
            let route = clothoidCorners(legs, radius: radius, easement: easement)
            #expect(route.count > 3)
            for i in 1..<route.count {
                let gap = route[i].start.distance(to: route[i - 1].end)
                let kink = abs(wrapped(route[i].heading - route[i - 1].endHeading))
                let jump = abs(route[i].curvature - route[i - 1].endCurvature)
                #expect(gap < 1e-9, "piece \(i) starts \(gap) away from where the last one ended")
                #expect(kink < 1e-12, "piece \(i) starts \(kink) off the last one's heading")
                #expect(jump < 1e-12, "piece \(i) jumps the bend by \(jump)")
            }
        }
    }

    @Test func acorneredPathNeverJumpsItsBend() {
        let legs = [Vector2(150, 800), Vector2(540, 200), Vector2(930, 780)]
        let radius = 120.0
        let eased = clothoidCorners(legs, radius: radius, easement: 150).contour(spacing: 1)
        let abrupt = clothoidCorners(legs, radius: radius, easement: 0.02).contour(spacing: 1)

        // The counterfactual is the point. With no easement worth the name the
        // corner is a plain arc, and the bend has to jump the whole way to
        // 1 / radius in a single step.
        #expect(worstBendJump(abrupt.points) > 0.5 / radius,
                "a corner with no easement should jump its bend, and did not")
        #expect(worstBendJump(eased.points) < 0.02 / radius,
                "an eased corner jumped its bend by \(worstBendJump(eased.points))")
    }

    @Test func aCorneredPathLeavesAndRejoinsItsLegs() {
        let legs = [Vector2(150, 800), Vector2(540, 200), Vector2(930, 780)]
        let path = clothoidCorners(legs, radius: 120, easement: 150).contour()
        // The points are accumulated span by span, so the ends land within
        // rounding of where they were told rather than exactly on it.
        #expect(path.points.first!.distance(to: legs[0]) < 1e-12,
                "it must still begin where it was told")
        #expect(path.points.last!.distance(to: legs[2]) < 1e-9, "and still end there")

        // The turn has to begin on the leg it came in along, and end on the
        // one it leaves along, or the corner is not a corner of this polyline.
        let entry = path.points[1]
        let exit = path.points[path.points.count - 2]
        let inLeg = (legs[1] - legs[0]).normalized
        let outLeg = (legs[2] - legs[1]).normalized
        #expect(abs((entry - legs[0]).cross(inLeg)) < 1e-9,
                "the turn began \(abs((entry - legs[0]).cross(inLeg))) off the incoming leg")
        #expect(abs((exit - legs[1]).cross(outLeg)) < 1e-9,
                "the turn rejoined off the outgoing leg")
    }

    @Test func aCornerTakesAtMostHalfOfEachLegItTouches() {
        // The asked-for radius is far too big for these legs. Each corner must
        // shrink itself rather than run into its neighbor or overshoot.
        let legs = [
            Vector2(200, 500), Vector2(300, 500), Vector2(340, 620), Vector2(700, 620),
        ]
        let path = clothoidCorners(legs, radius: 400, easement: 400).contour(spacing: 1)
        let shortestLeg = 100.0
        for point in path.points {
            let distanceToCorner = point.distance(to: legs[1])
            let distanceToNext = point.distance(to: legs[2])
            #expect(distanceToCorner < 1000 && distanceToNext < 1000,
                    "a shrunk corner threw a point out to \(point)")
        }
        // The two corners share a leg of 100 units of length, so neither may
        // reach more than 50 along it, and the path between them must still
        // run in the direction that leg runs.
        let midpoint = legs[1].lerp(to: legs[2], 0.5)
        let nearest = path.points.min { $0.distance(to: midpoint) < $1.distance(to: midpoint) }!
        #expect(nearest.distance(to: midpoint) < shortestLeg * 0.02,
                "the two corners ate the leg between them: nearest point was \(nearest)")
    }

    @Test func aClosedCorneredPathHasNoStartOrEnd() {
        let square = [
            Vector2(300, 300), Vector2(700, 300), Vector2(700, 700), Vector2(300, 700),
        ]
        let path = clothoidCorners(square, radius: 80, easement: 60, closed: true)
            .contour(closed: true)
        #expect(path.isClosed)
        // Every corner of the square is the same corner, so the drawn path has
        // to be unchanged by a quarter turn about the middle.
        let center = Vector2(500, 500)
        let turned = path.points.map { $0.rotated(by: .pi / 2, around: center) }
        for point in turned {
            let nearest = path.points.map { $0.distance(to: point) }.min()!
            #expect(nearest < 0.5, "a quarter turn moved the path: \(point) had nothing within 0.5")
        }
    }

    // MARK: - The whole spiral

    @Test func theDoubleSpiralWindsAsFarAsAsked() {
        for turns in [1.0, 2.5, 4.0] {
            let points = eulerSpiral(size: 600, turns: turns, count: 2001)
            let span = points.first!.distance(to: points.last!)
            #expect(abs(span - 600) / 600 < 1e-6,
                    "asked for 600 across at \(turns) turns and got \(span)")

            // Total turning, added up along the drawn polyline, must be one
            // full turn per arm per asked-for turn, both arms together.
            var total = 0.0
            for i in 1..<(points.count - 1) {
                let a = (points[i] - points[i - 1]).angle
                let b = (points[i + 1] - points[i]).angle
                total += abs(wrapped(b - a))
            }
            let due = 2 * turns * 2 * .pi
            #expect(abs(total - due) / due < 0.02,
                    "at \(turns) turns the arms swept \(total / (2 * .pi)) turns, not \(2 * turns)")
        }
    }

    @Test func theSameNumbersAlwaysDrawTheSameCurve() {
        let make = {
            Clothoid(start: Vector2(3, 4), heading: 1.1, curvature: 0.003,
                     curvatureRate: -0.00004, length: 275).points(count: 400)
        }
        #expect(make() == make())
        #expect(clothoidSpline(through: [Vector2(0, 0), Vector2(100, 40), Vector2(220, -30)])
            .contour().points
            == clothoidSpline(through: [Vector2(0, 0), Vector2(100, 40), Vector2(220, -30)])
            .contour().points)
    }
}
