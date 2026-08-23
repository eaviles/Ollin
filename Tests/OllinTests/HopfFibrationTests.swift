@testable import Ollin
import Testing
import Foundation

/// Checks on the Hopf fibration.
///
/// This one is all theorem and no taste. A tangle of rings looks like a Hopf fibration long
/// before it is one, so every check here is a property the real thing has and a near miss
/// does not:
///
/// - every point of a fiber is on the three-sphere, and the map sends all of them back to
///   the one base point the fiber came from (that is what makes it a *fiber*);
/// - every projected fiber is a circle, flat and round, because that is what stereographic
///   projection does to a circle;
/// - **every fiber links the one over the top pole exactly once**, which is the whole
///   reason the picture is worth drawing. Linking is checked the honest way, by counting
///   crossings of the disc that circle bounds.
@Suite
struct HopfFibrationTests {

    private static let bases = hopfBases(latitudes: 5, perCircle: 7)

    /// Every lifted point sits on the unit three-sphere. If this drifts, nothing below it
    /// means anything.
    @Test func everyLiftedPointIsOnTheThreeSphere() {
        for base in Self.bases.map(hopfMath) {
            for i in 0 ..< 32 {
                let p = hopfLift(base, Double(i) / 32 * .pi * 2)
                let length = (p.x * p.x + p.y * p.y + p.z * p.z + p.w * p.w).squareRoot()
                #expect(abs(length - 1) < 1e-12, "a lift of \(base) had length \(length)")
            }
        }
    }

    /// Every point of a fiber maps back to the point the fiber was asked for. This is the
    /// definition, and it is the one check that the parameterization and the map are two
    /// halves of the same thing rather than two plausible formulas.
    @Test func theMapSendsEveryPointOfAFiberBackToItsBase() {
        for base in Self.bases.map(hopfMath) {
            for i in 0 ..< 32 {
                let back = hopfBase(of: hopfLift(base, Double(i) / 32 * .pi * 2))
                #expect(back.distance(to: base) < 1e-12,
                        "a point of the fiber over \(base) came back as \(back)")
            }
        }
    }

    /// A circle on the three-sphere comes down as a circle in space. So: the points are
    /// flat, and there is one place they are all the same distance from.
    ///
    /// The center is solved for rather than averaged. Equal steps in the parameter are not
    /// equal steps around the projected circle, because the projection stretches one end
    /// more than the other, so the middle of the points is not the middle of the circle and
    /// a check written against the average would fail on a perfectly good circle.
    @Test func everyFiberComesDownAsACircle() throws {
        for fiber in hopfFibers(over: Self.bases, segments: 64) {
            let p = fiber.points
            let normal = ((p[1] - p[0]).cross(p[2] - p[0])).normalized
            for point in p {
                #expect(abs((point - p[0]).dot(normal)) < 1e-6 * max(1, point.length),
                        "the fiber over \(fiber.base) is not flat")
            }
            let center = try #require(circleCenter(p[0], p[16], p[32]),
                                      "three points of the fiber over \(fiber.base) were in a line")
            let radius = center.distance(to: p[0])
            for point in p {
                #expect(abs(center.distance(to: point) - radius) < 1e-6 * max(1, radius),
                        "the fiber over \(fiber.base) is not round")
            }
        }
    }

    /// The top pole's fiber is the plain unit circle in the ground plane. It is the ring
    /// every other one is threaded through, and it is worth pinning exactly because so much
    /// below is measured against it.
    @Test func theTopPolesFiberIsTheUnitCircle() {
        let fiber = hopfFiber(over: Vector3(0, 1, 0), segments: 48)
        #expect(!fiber.isStraight)
        for point in fiber.points {
            #expect(abs(point.y) < 1e-12, "it should lie flat on the ground plane")
            #expect(abs(Vector2(point.x, point.z).length - 1) < 1e-12)
        }
    }

    /// The bottom pole's fiber runs through the point the projection sends to infinity, so it
    /// comes back as the straight axis rather than a circle. Drawing it is what puts the
    /// spine in the picture, so it is handed over as a line rather than dropped.
    @Test func theBottomPolesFiberComesBackStraight() {
        let fiber = hopfFiber(over: Vector3(0, -1, 0), reach: 25)
        #expect(fiber.isStraight)
        #expect(fiber.points.count == 2)
        for point in fiber.points {
            #expect(abs(point.x) < 1e-12 && abs(point.z) < 1e-12,
                    "the straight one should stand up, not lie down")
            #expect(abs(abs(point.y) - 25) < 1e-12)
        }
    }

    /// Every fiber links the top pole's circle exactly once, which is the property the
    /// whole figure exists for.
    ///
    /// Counted rather than asserted: walk the fiber, find where it crosses the ground plane,
    /// and ask whether each crossing is inside or outside the unit circle. A loop that
    /// passes through the disc once and around it once is linked; one that misses the disc
    /// entirely, or threads it twice in opposite directions, is not.
    @Test func everyFiberLinksTheTopPolesCircleExactlyOnce() {
        for fiber in hopfFibers(over: hopfBases(latitudes: 4, perCircle: 5), segments: 512) {
            guard fiber.base.distance(to: Vector3(0, 1, 0)) > 1e-6 else { continue }
            var through = 0, around = 0
            let p = fiber.points
            for i in 0 ..< p.count {
                let a = p[i], b = p[(i + 1) % p.count]
                guard (a.y <= 0) != (b.y <= 0) else { continue }
                let t = a.y / (a.y - b.y)
                let hit = Vector2(a.x + (b.x - a.x) * t, a.z + (b.z - a.z) * t)
                if hit.length < 1 { through += 1 } else { around += 1 }
            }
            let report = "the fiber over \(fiber.base) crossed the disc \(through) times "
                + "and the plane outside it \(around) times"
            #expect(through == 1 && around == 1, "\(report)")
        }
    }

    /// Distinct base points give distinct circles that never touch, which is the other half
    /// of "fibration": the circles fill the space without crossing.
    @Test func twoFibersNeverMeet() {
        let fibers = hopfFibers(over: hopfBases(latitudes: 3, perCircle: 4), segments: 128)
        for i in 0 ..< fibers.count {
            for j in (i + 1) ..< fibers.count {
                var closest = Double.infinity
                for a in fibers[i].points {
                    for b in fibers[j].points { closest = min(closest, a.distance(to: b)) }
                }
                let report = "the fibers over \(fibers[i].base) and \(fibers[j].base) "
                    + "came within \(closest) of each other"
                #expect(closest > 1e-3, "\(report)")
            }
        }
    }

    /// The rings of latitude cover their range, sit on the sphere, and are turned against
    /// each other so the circles interleave instead of lining up into spokes.
    @Test func theLatitudeRingsAreOnTheSphereAndOffset() {
        let bases = hopfBases(latitudes: 4, perCircle: 6, spanning: -0.5 ... 0.5)
        #expect(bases.count == 24)
        for base in bases { #expect(abs(base.length - 1) < 1e-12) }
        #expect(abs(bases[0].y + 0.5) < 1e-12, "the rings' height rides the world's up axis")
        #expect(abs(bases[23].y - 0.5) < 1e-12)
        // The second ring's first point is turned against the first ring's.
        let first = atan2(bases[0].z, bases[0].x)
        let second = atan2(bases[6].z, bases[6].x)
        #expect(abs(first - second) > 1e-6, "the rings line up instead of interleaving")
    }

    /// The spiral covers the sphere from pole to pole and every point of it is on the
    /// sphere.
    @Test func theSpiralCoversTheSphere() {
        let bases = hopfBases(spiral: 200)
        #expect(bases.count == 200)
        for base in bases { #expect(abs(base.length - 1) < 1e-12) }
        #expect(abs(bases.first!.y - 1) < 1e-12)
        #expect(abs(bases.last!.y + 1) < 1e-12)
    }

    /// Nothing asked for is nothing handed back, rather than a crash.
    @Test func anEmptyRequestIsEmpty() {
        #expect(hopfBases(latitudes: 0, perCircle: 8).isEmpty)
        #expect(hopfBases(spiral: 0).isEmpty)
        #expect(hopfFibers(over: []).isEmpty)
    }

    /// The center of the circle through three points, in their own plane, or nil if they
    /// are in a line.
    private func circleCenter(_ a: Vector3, _ b: Vector3, _ c: Vector3) -> Vector3? {
        let ab = b - a, ac = c - a
        let cross = ab.cross(ac)
        let denominator = 2 * cross.lengthSquared
        guard denominator > 1e-20 else { return nil }
        let term = (cross.cross(ab) * ac.lengthSquared + ac.cross(cross) * ab.lengthSquared)
        return a + term / denominator
    }
}
