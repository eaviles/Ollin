import Ollin
import Testing

/// Pure-CPU checks on the Fourier epicycle chain: canonical inputs reduce to
/// the terms the math predicts, the full chain reconstructs its input samples
/// exactly, and the read surfaces agree with each other.
@Suite
struct EpicyclesTests {
    /// A circle is one spinning term: radius as amplitude, one turn per lap,
    /// centered on the circle's center, with nothing left over.
    @Test func circleReducesToOneTerm() {
        let center = Vector2(300, 220)
        let radius = 120.0
        let points = (0 ..< 64).map { i -> Vector2 in
            let a = Double(i) / 64 * .tau
            return center + Vector2(angle: a, length: radius)
        }
        let epicycles = Epicycles(points: points)
        #expect(epicycles.center.distance(to: center) < 1e-9)
        #expect(abs(epicycles.terms[0].amplitude - radius) < 1e-9)
        #expect(epicycles.terms[0].frequency == 1)
        #expect(abs(epicycles.terms[0].phase) < 1e-9)
        #expect(epicycles.terms[1].amplitude < 1e-9)
    }

    /// An axis-aligned ellipse is exactly two counter-spinning terms, with
    /// the amplitudes the algebra predicts: (a + b) / 2 and (a - b) / 2.
    @Test func ellipseReducesToTwoTerms() {
        let points = (0 ..< 64).map { i -> Vector2 in
            let a = Double(i) / 64 * .tau
            return Vector2(200 * cos(a), 100 * sin(a))
        }
        let epicycles = Epicycles(points: points)
        #expect(epicycles.terms[0].frequency == 1)
        #expect(abs(epicycles.terms[0].amplitude - 150) < 1e-9)
        #expect(epicycles.terms[1].frequency == -1)
        #expect(abs(epicycles.terms[1].amplitude - 50) < 1e-9)
        #expect(epicycles.terms[2].amplitude < 1e-9)
    }

    /// With every term kept, phase i/n lands back on input sample i: the
    /// transform inverts exactly (up to floating-point noise).
    @Test func fullChainReconstructsItsSamples() {
        let points: [Vector2] = [
            Vector2(10, 40), Vector2(180, -30), Vector2(240, 90), Vector2(160, 210),
            Vector2(40, 260), Vector2(-80, 190), Vector2(-140, 60), Vector2(-60, -50),
            Vector2(30, -90), Vector2(120, -60), Vector2(200, 20), Vector2(90, 130),
        ]
        let epicycles = Epicycles(points: points)
        for (i, original) in points.enumerated() {
            let rebuilt = epicycles.point(at: Double(i) / Double(points.count))
            #expect(rebuilt.distance(to: original) < 1e-6)
        }
    }

    /// Truncating keeps the largest circles: amplitudes come sorted
    /// non-increasing, and the joints walk ends exactly at the traced point.
    @Test func jointsAndOrderingAgree() {
        let points = (0 ..< 48).map { i -> Vector2 in
            let a = Double(i) / 48 * .tau
            return Vector2(150 * cos(a) + 40 * cos(a * 3), 90 * sin(a) - 25 * sin(a * 2))
        }
        let epicycles = Epicycles(points: points)
        for i in 1 ..< epicycles.terms.count {
            #expect(epicycles.terms[i - 1].amplitude >= epicycles.terms[i].amplitude)
        }
        let joints = epicycles.joints(at: 0.37, terms: 5)
        #expect(joints.count == 6)
        #expect(joints[0] == epicycles.center)
        #expect(joints[5].distance(to: epicycles.point(at: 0.37, terms: 5)) < 1e-12)
    }

    /// The contour initializer resamples by walked length and the whole build
    /// is deterministic: the same contour twice gives the same chain, and the
    /// reconstructed path stays near the source outline.
    @Test func contourBuildIsDeterministicAndClose() {
        // A square traced with deliberately uneven points along its edges.
        let square = Contour([
            Vector2(0, 0), Vector2(30, 0), Vector2(200, 0),
            Vector2(200, 170), Vector2(200, 200),
            Vector2(10, 200), Vector2(0, 200), Vector2(0, 40),
        ], closed: true)
        let a = Epicycles(square, samples: 128)
        let b = Epicycles(square, samples: 128)
        #expect(a == b)

        let rebuilt = a.path(samples: 128)
        #expect(rebuilt.isClosed)
        // Full-term reconstruction lands on the resampled outline, every
        // point of which lies on the square's perimeter.
        for p in rebuilt.points {
            let onEdge = abs(p.x) < 1e-3 || abs(p.x - 200) < 1e-3
                || abs(p.y) < 1e-3 || abs(p.y - 200) < 1e-3
            #expect(onEdge)
        }
    }
}
