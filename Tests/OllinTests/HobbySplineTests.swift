@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on Hobby's spline. The fit is a linear system whose right
/// answer looks no better to the eye than a slightly wrong one, so each test
/// here is a law the published technique guarantees, or a number that can be
/// worked out by hand from its equations.
///
/// The load-bearing pair: four points on a circle come out as the classic
/// four-Bézier circle (the control distance `4/3 · tan(π/8)` of a radius, the
/// number Hobby's velocity function was shaped to hit), and a symmetric
/// three-point arch under the default curl leaves the first point straight
/// up, which is what the curl equation gives when solved by hand.
@Suite
struct HobbySplineTests {

    private static let quarterCircle = 4.0 / 3.0 * tan(Double.pi / 8)   // 0.55228…

    private func cross(_ a: Vector2, _ b: Vector2) -> Double { a.x * b.y - a.y * b.x }

    private func parallel(_ a: Vector2, _ b: Vector2, within tolerance: Double = 1e-9) -> Bool {
        let u = a.normalized, v = b.normalized
        return abs(cross(u, v)) < tolerance && (u.x * v.x + u.y * v.y) > 0
    }

    // MARK: Laws

    @Test func passesThroughEveryPoint() {
        let points = [Vector2(20, 40), Vector2(120, 10), Vector2(200, 90), Vector2(260, 30), Vector2(340, 80)]
        let open = HobbySpline(through: points)
        #expect(open.segments.count == points.count - 1)
        for (i, s) in open.segments.enumerated() {
            #expect(s.start == points[i])
            #expect(s.end == points[i + 1])
        }
        let closed = HobbySpline(through: points, closed: true)
        #expect(closed.segments.count == points.count)
        #expect(closed.segments.last?.end == points[0])
        // The sampled contour keeps every given point as a vertex.
        let sampled = closed.contour.points
        for p in points {
            #expect(sampled.contains(where: { ($0 - p).length < 1e-9 }))
        }
    }

    @Test func fourPointsOnACircleGiveTheClassicCircle() {
        let r = 100.0
        let points = [Vector2(r, 0), Vector2(0, r), Vector2(-r, 0), Vector2(0, -r)]
        let spline = HobbySpline(through: points, closed: true)
        #expect(spline.segments.count == 4)
        for s in spline.segments {
            // The control distance of a quarter-circle Bézier, at every corner.
            #expect(abs((s.control1 - s.start).length / r - Self.quarterCircle) < 1e-6)
            #expect(abs((s.end - s.control2).length / r - Self.quarterCircle) < 1e-6)
            // And the controls sit on the tangent, square to the radius.
            #expect(abs(s.start.x * (s.control1 - s.start).x + s.start.y * (s.control1 - s.start).y) < 1e-6)
        }
        // The sampled outline never leaves the circle by more than the known
        // radial error of that Bézier circle (0.027%).
        for p in spline.contour.points {
            #expect(abs(p.length - r) / r < 3e-4)
        }
    }

    @Test func aSymmetricArchLeavesStraightUpUnderTheDefaultCurl() {
        // By hand, with tension 1 and curl 1: theta = pi/4 at both the first
        // and middle point, so the curve leaves (0,0) at 90 degrees, crosses
        // (1,1) level, and arrives at (2,0) straight down: the circle through
        // the three points, as two quarter-circle Béziers.
        let spline = HobbySpline(through: [Vector2(0, 0), Vector2(1, 1), Vector2(2, 0)])
        let first = spline.segments[0], second = spline.segments[1]
        #expect(abs(first.control1.x) < 1e-9)
        #expect(abs(first.control1.y - Self.quarterCircle) < 1e-6)
        #expect(abs(first.control2.y - 1) < 1e-9)
        #expect(abs(first.control2.x - (1 - Self.quarterCircle)) < 1e-6)
        #expect(abs(second.control2.x - 2) < 1e-9)
        #expect(abs(second.control2.y - Self.quarterCircle) < 1e-6)
        #expect(parallel(first.direction(at: 1), Vector2(1, 0)))
    }

    @Test func curlZeroLetsTheEndsRunStraighter() {
        // Same arch with curl 0: the hand solution is theta_0 = pi/8, so the
        // curve leaves at 67.5 degrees rather than 90.
        let spline = HobbySpline(through: [Vector2(0, 0), Vector2(1, 1), Vector2(2, 0)], curl: 0)
        let leaving = spline.segments[0].direction(at: 0).angle
        #expect(abs(leaving - 3 * Double.pi / 8) < 1e-9)
    }

    @Test func tensionPullsTheControlsTowardTheChord() {
        let points = [Vector2(0, 0), Vector2(80, 60), Vector2(160, -20), Vector2(240, 40)]
        let loose = HobbySpline(through: points, tension: 1)
        let tight = HobbySpline(through: points, tension: 2)
        let tighter = HobbySpline(through: points, tension: 4)
        for i in 0..<points.count - 1 {
            let a = (loose.segments[i].control1 - loose.segments[i].start).length
            let b = (tight.segments[i].control1 - tight.segments[i].start).length
            let c = (tighter.segments[i].control1 - tighter.segments[i].start).length
            #expect(a > b && b > c)
        }
        // And the whole curve sits closer to the polyline as tension rises.
        func deviation(_ s: HobbySpline) -> Double {
            s.segments.map { seg in
                let chord = seg.end - seg.start
                let n = chord.perpendicular.normalized
                return (1...9).map { k in
                    let p = seg.point(at: Double(k) / 10) - seg.start
                    return abs(p.x * n.x + p.y * n.y)
                }.max() ?? 0
            }.max() ?? 0
        }
        #expect(deviation(loose) > deviation(tight))
        #expect(deviation(tight) > deviation(tighter))
        // Below the technique's floor, tension is held at 0.75.
        #expect(HobbySpline(through: points, tension: 0.1).tension == 0.75)
    }

    @Test func twoPointsAreAStraightLineAndCollinearPointsStayOnIt() {
        let two = HobbySpline(through: [Vector2(10, 10), Vector2(90, 50)])
        #expect(two.segments.count == 1)
        let s = two.segments[0]
        #expect(abs(cross(s.control1 - s.start, s.end - s.start)) < 1e-9)
        #expect(abs(cross(s.control2 - s.start, s.end - s.start)) < 1e-9)
        #expect(s.control1.x.isFinite && s.control2.x.isFinite)
        // With one end's direction given, the single chord still bends to meet it.
        let bent = HobbySpline(through: [Vector2(0, 0), Vector2(100, 0)], startDirection: Vector2(0, 1))
        #expect(parallel(bent.segments[0].direction(at: 0), Vector2(0, 1)))
        #expect(bent.segments[0].control2.y.isFinite)

        let line = (0...5).map { Vector2(Double($0) * 37, Double($0) * 11) }
        let along = HobbySpline(through: line)
        for p in along.contour.points {
            #expect(abs(cross(p, Vector2(37, 11))) < 1e-7)
        }
    }

    @Test func aClosedLoopIsSmoothAtEveryPointIncludingTheSeam() {
        let points = [Vector2(0, 0), Vector2(90, -30), Vector2(160, 40), Vector2(130, 120),
                      Vector2(40, 150), Vector2(-30, 70)]
        let spline = HobbySpline(through: points, closed: true)
        let n = spline.segments.count
        for k in 0..<n {
            let arriving = spline.segments[(k + n - 1) % n]
            let leaving = spline.segments[k]
            #expect(parallel(arriving.end - arriving.control2, leaving.control1 - leaving.start, within: 1e-8),
                    "kink at point \(k)")
        }
        // An open run is smooth at its interior points too.
        let open = HobbySpline(through: points)
        for k in 1..<open.segments.count {
            let arriving = open.segments[k - 1], leaving = open.segments[k]
            #expect(parallel(arriving.end - arriving.control2, leaving.control1 - leaving.start, within: 1e-8))
        }
    }

    @Test func mirroredPointsGiveTheMirroredCurve() {
        let points = [Vector2(5, 12), Vector2(70, 80), Vector2(140, 30), Vector2(210, 95), Vector2(260, 20)]
        let mirrored = points.map { Vector2(-$0.x, $0.y) }
        let a = HobbySpline(through: points), b = HobbySpline(through: mirrored)
        for (s, t) in zip(a.segments, b.segments) {
            #expect(abs(s.control1.x + t.control1.x) < 1e-9 && abs(s.control1.y - t.control1.y) < 1e-9)
            #expect(abs(s.control2.x + t.control2.x) < 1e-9 && abs(s.control2.y - t.control2.y) < 1e-9)
        }
        // Reversing the points reverses the curve, control for control.
        let reversed = HobbySpline(through: points.reversed())
        for (s, t) in zip(a.segments, reversed.segments.reversed()) {
            #expect((s.control1 - t.control2).length < 1e-9)
            #expect((s.control2 - t.control1).length < 1e-9)
        }
    }

    @Test func endDirectionsAreHonored() {
        let points = [Vector2(0, 0), Vector2(1, 1), Vector2(2, 0)]
        let level = HobbySpline(through: points, startDirection: Vector2(1, 0), endDirection: Vector2(1, 0))
        #expect(parallel(level.segments[0].direction(at: 0), Vector2(1, 0)))
        #expect(parallel(level.segments[1].direction(at: 1), Vector2(1, 0)))
        // The direction's length does not matter, only where it points.
        let scaled = HobbySpline(through: points, startDirection: Vector2(30, 0), endDirection: Vector2(0.01, 0))
        #expect(scaled.segments == level.segments)
        // The interior stays smooth with the ends pinned.
        #expect(parallel(level.segments[0].direction(at: 1), level.segments[1].direction(at: 0), within: 1e-8))
    }

    @Test func repeatedPointsAreDroppedAndAClosingRepeatToo() {
        let points = [Vector2(0, 0), Vector2(0, 0), Vector2(50, 20), Vector2(50, 20), Vector2(90, -10)]
        #expect(HobbySpline(through: points).segments.count == 2)
        let ring = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 60), Vector2(0, 60), Vector2(0, 0)]
        let closed = HobbySpline(through: ring, closed: true)
        #expect(closed.points.count == 4)
        #expect(closed.segments.count == 4)
        // Degenerate input never traps: one point, none, two repeated.
        #expect(HobbySpline(through: [Vector2(3, 3)]).segments.isEmpty)
        #expect(HobbySpline(through: []).contour.points.isEmpty)
        #expect(HobbySpline(through: [Vector2(1, 1), Vector2(1, 1)]).segments.isEmpty)
        // Two points closed is a loop out and back.
        #expect(HobbySpline(through: [Vector2(0, 0), Vector2(100, 0)], closed: true).segments.count == 2)
    }

    @Test func aHairpinKeepsItsControlsWithinFourChords() {
        let points = [Vector2(0, 0), Vector2(100, 0), Vector2(0, 0.5)]
        let spline = HobbySpline(through: points)
        for s in spline.segments {
            let chord = (s.end - s.start).length
            #expect((s.control1 - s.start).length <= 4 * chord + 1e-9)
            #expect((s.end - s.control2).length <= 4 * chord + 1e-9)
            #expect(s.control1.x.isFinite && s.control2.y.isFinite)
        }
    }

    // MARK: The surface

    @Test func thePathAndTheContourAgree() {
        let points = [Vector2(0, 0), Vector2(90, -30), Vector2(160, 40), Vector2(130, 120)]
        let open = HobbySpline(through: points)
        #expect(open.path.contour.points == open.contour.points)
        #expect(open.contour.isClosed == false)
        // A closed path keeps the sample that lands back on its start, as any
        // closed `Path` does; the contour leaves it to `isClosed`.
        let closed = HobbySpline(through: points, closed: true)
        #expect(Array(closed.path.contour.points.dropLast()) == closed.contour.points)
        #expect(closed.path.contour.points.last == points[0])
        #expect(closed.path.contour.isClosed)
        #expect(closed.contour.isClosed)
        #expect(closed.shape.contours.count == 1)
    }

    @Test func theSplineModeReachesTheSameCurveAndTheDefaultIsUntouched() {
        let points = [Vector2(0, 0), Vector2(90, -30), Vector2(160, 40), Vector2(130, 120)]
        let byMode = Contour(curveThrough: points, closed: false, spline: .hobby)
        #expect(byMode.points == HobbySpline(through: points).contour.points)
        let tuned = Contour(curveThrough: points, closed: true, spline: .hobby(tension: 1.5, curl: 0))
        #expect(tuned.points == HobbySpline(through: points, closed: true, tension: 1.5, curl: 0).contour.points)
        #expect(Contour(curveThrough: points, closed: true).points
                == CurveSampling.catmullRom(through: points, closed: true))
        #expect(Shape(curveThrough: points, spline: .hobby).contours[0].points == HobbySpline(through: points, closed: true).contour.points)
        #expect(Spline.hobby == Spline.hobby(tension: 1, curl: 1))
    }
}
