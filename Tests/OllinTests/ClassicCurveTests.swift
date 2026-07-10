import Foundation
import Ollin
import Testing

/// Pure-CPU checks on the classic-curve builders: each curve's closed form is
/// pinned against the values the mathematics predicts, closure spans close,
/// and everything is deterministic (no rng anywhere in the family).
@Suite
struct ClassicCurveTests {
    // MARK: - Phyllotaxis

    /// Point `i` sits at radius `spacing * sqrt(i)` and angle `i * angle`,
    /// straight from Vogel's model.
    @Test func phyllotaxisFollowsVogelsModel() {
        let spacing = 9.0
        let points = phyllotaxis(count: 200, spacing: spacing)
        #expect(points.count == 200)
        #expect(points[0] == .zero)
        for i in [1, 7, 50, 199] {
            let expected = Vector2(angle: Double(i) * .goldenAngle,
                                   length: spacing * Double(i).squareRoot())
            #expect(points[i].distance(to: expected) < 1e-9)
        }
        #expect(phyllotaxis(count: 0, spacing: spacing).isEmpty)
    }

    /// The golden angle matches its closed form (and the value the shader
    /// library bakes in).
    @Test func goldenAngleValue() {
        #expect(abs(Double.goldenAngle - 2.399963229728653) < 1e-12)
    }

    // MARK: - Lissajous

    /// Equal frequencies at a quarter-turn phase trace a circle.
    @Test func lissajousUnisonIsCircle() {
        let c = lissajous(a: 1, b: 1, width: 400)
        #expect(c.isClosed)
        for p in c.points {
            #expect(abs(p.length - 200) < 1e-9)
        }
    }

    /// Distinct width and height scale the two axes independently, and every
    /// sample stays inside the stated extents.
    @Test func lissajousRespectsExtents() {
        let c = lissajous(a: 3, b: 2, width: 400, height: 240)
        let maxX = c.points.map { abs($0.x) }.max() ?? 0
        let maxY = c.points.map { abs($0.y) }.max() ?? 0
        #expect(maxX <= 200 + 1e-9)
        #expect(maxY <= 120 + 1e-9)
        // Both extents are actually reached (the curve fills its box).
        #expect(maxX > 199)
        #expect(maxY > 119)
    }

    /// A shared frequency factor cancels: `a: 2, b: 4` is the same curve as
    /// `a: 1, b: 2`.
    @Test func lissajousReducesSharedFactors() {
        let reduced = lissajous(a: 1, b: 2, width: 300)
        let doubled = lissajous(a: 2, b: 4, width: 300)
        #expect(reduced == doubled)
    }

    // MARK: - Rose

    /// An odd `n` traces `n` petals, an even `n` traces `2n`; petals are
    /// counted as clusters of samples out near the full radius.
    @Test func rosePetalCounts() {
        #expect(petalCount(rose(n: 3, radius: 100, samples: 4096)) == 3)
        #expect(petalCount(rose(n: 5, radius: 100, samples: 4096)) == 5)
        #expect(petalCount(rose(n: 2, radius: 100, samples: 4096)) == 4)
        #expect(petalCount(rose(n: 4, radius: 100, samples: 4096)) == 8)
    }

    /// A rational `k = n/d` with both odd closes over `pi * d`; the sampled
    /// span ends where it started (no retrace, no gap).
    @Test func roseRationalCloses() {
        let c = rose(n: 7, d: 3, radius: 100, samples: 4096)
        #expect(c.isClosed)
        #expect(c.points[0].distance(to: Vector2(100, 0)) < 1e-9)
        // The final sample sits one step short of the start; the closing
        // segment spans the gap.
        let step = c.points[1].distance(to: c.points[0]) * 4
        #expect(c.points[c.points.count - 1].distance(to: c.points[0]) < max(step, 1))
    }

    // MARK: - Trochoids

    /// `ring: 4, wheel: 1, pen: 1` is the astroid: a hypocycloid whose cusps
    /// touch the ring and whose arms cross the axes at the ring radius.
    @Test func hypotrochoidAstroid() {
        let c = hypotrochoid(ring: 4, wheel: 1, pen: 1)
        #expect(c.isClosed)
        #expect(c.points[0].distance(to: Vector2(4, 0)) < 1e-9)
        let maxRadius = c.points.map(\.length).max() ?? 0
        #expect(maxRadius <= 4 + 1e-9)
    }

    /// The pen returns to its start after `wheel / gcd(ring, wheel)` laps:
    /// sampling one lap short leaves the curve visibly open.
    @Test func hypotrochoidClosesAfterItsLaps() {
        // ring 5, wheel 3: closes after 3 laps of the wheel center.
        let c = hypotrochoid(ring: 5, wheel: 3, pen: 2, samples: 3000)
        let n = c.points.count
        // One third of the way through (one lap) the pen is far from the
        // start; at the wrap it is one sample step away.
        let oneLap = c.points[n / 3]
        #expect(oneLap.distance(to: c.points[0]) > 0.5)
        let step = c.points[1].distance(to: c.points[0]) * 4
        #expect(c.points[n - 1].distance(to: c.points[0]) < max(step, 1))
    }

    /// `ring == wheel == pen` outside is the cardioid, whose cusp touches the
    /// ring at `(ring, 0)` after one full lap.
    @Test func epitrochoidCardioid() {
        let c = epitrochoid(ring: 2, wheel: 2, pen: 2)
        #expect(c.points[0].distance(to: Vector2(2, 0)) < 1e-9)
        // The cardioid's far side reaches (ring + wheel) + pen across from the cusp.
        let maxRadius = c.points.map(\.length).max() ?? 0
        #expect(abs(maxRadius - 6) < 0.01)
    }

    // MARK: - Chaikin smoothing

    /// One open pass keeps both endpoints and cuts each corner at the quarter
    /// points, exactly.
    @Test func chaikinOpenPassIsExact() {
        let c = Contour([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4)], closed: false)
        let s = c.smoothed(iterations: 1)
        #expect(s.points == [Vector2(0, 0),
                             Vector2(1, 0), Vector2(3, 0),
                             Vector2(4, 1), Vector2(4, 3),
                             Vector2(4, 4)])
        #expect(!s.isClosed)
    }

    /// A closed pass emits two points per segment (2n total) and drops every
    /// original corner.
    @Test func chaikinClosedPassCutsCorners() {
        let square = Contour([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)],
                             closed: true)
        let s = square.smoothed(iterations: 1)
        #expect(s.points.count == 8)
        #expect(s.isClosed)
        for corner in square.points {
            #expect(!s.points.contains(corner))
        }
        // Repeated passes converge toward a curve strictly inside the square.
        let round = square.smoothed(iterations: 5)
        #expect(round.points.count == 4 * 32)
        for p in round.points {
            #expect(p.x > -1e-9 && p.x < 4 + 1e-9 && p.y > -1e-9 && p.y < 4 + 1e-9)
        }
    }

    /// Degenerate inputs pass through unchanged, and a `Shape` smooths every
    /// contour while keeping its winding rule.
    @Test func chaikinEdgeCases() {
        let dot = Contour([Vector2(1, 1)], closed: false)
        #expect(dot.smoothed(iterations: 3) == dot)
        let square = Contour([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)],
                             closed: true)
        #expect(square.smoothed(iterations: 0) == square)
        let shape = Shape(contours: [square], winding: .nonZero).smoothed(iterations: 1)
        #expect(shape.winding == .nonZero)
        #expect(shape.contours[0].points.count == 8)
    }

    // MARK: - Harmonograph

    /// One undamped pendulum per axis at equal frequency and a quarter-turn
    /// phase offset is a circle.
    @Test func harmonographUndampedUnisonIsCircle() {
        let h = Harmonograph(
            x: [.init(amplitude: 100, frequency: 1, phase: .pi / 2, damping: 0)],
            y: [.init(amplitude: 100, frequency: 1, damping: 0)])
        for i in 0..<32 {
            let p = h.point(at: Double(i) / 32)
            #expect(abs(p.length - 100) < 1e-9)
        }
        #expect(h.settleTime == .infinity)
    }

    /// Damping shrinks the envelope monotonically, and `settleTime` is where
    /// the slowest decay reaches 1%.
    @Test func harmonographDampingDecays() {
        let h = Harmonograph(
            x: [.init(amplitude: 100, frequency: 2, phase: .pi / 2, damping: 0.05)],
            y: [.init(amplitude: 100, frequency: 2, damping: 0.02)])
        #expect(abs(h.settleTime - log(100.0) / 0.02) < 1e-9)
        // Sample the envelope at whole periods of the x pendulum, where the
        // sine factor is 1 again: it must decay strictly.
        let xOnly = Harmonograph(x: h.x, y: [])
        var last = Double.infinity
        for lap in 0..<5 {
            let t = Double(lap) / 2
            let v = abs(xOnly.point(at: t).x)
            #expect(v < last)
            last = v
        }
    }

    /// The baked trace is deterministic, open, spans `0...duration`, and
    /// starts where `point(at: 0)` says.
    @Test func harmonographContourIsDeterministic() {
        let h = Harmonograph(
            x: [.init(amplitude: 360, frequency: 2.00, damping: 0.015),
                .init(amplitude: 120, frequency: 6.01, phase: .pi / 2, damping: 0.02)],
            y: [.init(amplitude: 360, frequency: 2.01, phase: .pi / 4, damping: 0.015)])
        let a = h.contour(duration: 40)
        let b = h.contour(duration: 40)
        #expect(a == b)
        #expect(!a.isClosed)
        #expect(a.points.first?.distance(to: h.point(at: 0)) ?? 1 < 1e-9)
        #expect(a.points.last?.distance(to: h.point(at: 40)) ?? 1 < 1e-9)
        #expect(Harmonograph(x: [], y: []).contour().points.isEmpty)
    }

    // MARK: - Helpers

    /// Count clusters of consecutive samples whose radius exceeds 95% of the
    /// petal length; each petal tip is one cluster (the closing wrap joins
    /// the last cluster to the first when they touch).
    private func petalCount(_ contour: Contour) -> Int {
        let near = contour.points.map { $0.length > 95.0 }
        var clusters = 0
        for i in 0..<near.count where near[i] && !near[(i + near.count - 1) % near.count] {
            clusters += 1
        }
        return clusters
    }
}
