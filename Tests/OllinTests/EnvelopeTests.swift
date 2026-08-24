import Foundation
import Ollin
import Testing

/// Laws for envelopes and the caustics built on them. An envelope is defined by
/// touching: every line of the family has to touch the curve, and the curve has to
/// be the one they all lean on. Both halves are measurable.
@Suite
struct EnvelopeTests {
    /// The self-check the whole idea rests on: the tangent lines of a circle lean
    /// on that circle, so their envelope has to be the circle back again.
    ///
    /// It arrives rather than lands. Two neighboring tangents cross a little way
    /// outside the circle, and how far outside falls with the square of the step
    /// between them, so the law is that shrinking: halve the step and the error
    /// quarters.
    @Test func theTangentsOfACircleEnvelopeThatCircle() {
        let center = Vector2(30, -12)
        let radius = 47.0

        func offBy(_ count: Int) -> Double {
            let rays = (0 ..< count).map { i -> Ray2 in
                let angle = Double(i) / Double(count) * .tau
                let touch = center + Vector2(angle: angle, length: radius)
                return Ray2(origin: touch, direction: Vector2(angle: angle + .pi / 2))
            }
            let runs = envelope(of: rays, closed: true)
            #expect(runs.count == 1)
            let points = runs.flatMap(\.points)
            #expect(points.count == count)
            // Every crossing sits outside the circle, never inside it.
            for point in points {
                #expect(point.distance(to: center) >= radius - 1e-9)
            }
            return points.map { abs($0.distance(to: center) - radius) }.max() ?? .infinity
        }

        let coarse = offBy(200)
        let fine = offBy(400)
        let finer = offBy(800)
        #expect(coarse < radius * 0.01, "200 tangents were off by \(coarse)")
        #expect(fine < coarse / 3.5, "\(fine) is not a quarter of \(coarse)")
        #expect(finer < fine / 3.5, "\(finer) is not a quarter of \(fine)")
    }

    /// Every line of the family touches the envelope. Measured the other way round
    /// from how the envelope was built: for each ray, the nearest envelope point
    /// has to sit on the ray itself.
    @Test func everyRayTouchesTheCurveItHelpedDraw() {
        let circle = (0 ..< 240).map { Vector2(angle: Double($0) / 240 * .tau, length: 100) }
        let rays = reflectedRays(off: circle, from: .parallel(0), closed: true)
        let points = caustic(off: circle, from: .parallel(0), closed: true).flatMap(\.points)
        #expect(points.count > 200)

        for ray in rays {
            let nearest = points.map { ray.distance(to: $0) }.min() ?? .infinity
            #expect(nearest < 0.5, "a reflected ray misses the caustic by \(nearest)")
        }
    }

    /// A circle lit from far away draws a nephroid. The curve is published, so the
    /// test is against it rather than against a picture: for a circle of radius r
    /// mirrored on the inside with rays along x, the caustic is the nephroid of
    /// half that size.
    @Test func aCircleLitFromFarAwayDrawsANephroid() {
        let radius = 120.0
        let circle = (0 ..< 720).map { Vector2(angle: Double($0) / 720 * .tau, length: radius) }
        let found = caustic(off: circle, from: .parallel(0), closed: true).flatMap(\.points)
        #expect(!found.isEmpty)

        // The nephroid, from its own parametric form, turned to lie along x.
        let known = (0 ..< 2000).map { i -> Vector2 in
            let t = Double(i) / 2000 * .tau
            let half = radius / 2
            return Vector2(half * (3 * cos(t) - cos(3 * t)) / 2,
                           half * (3 * sin(t) - sin(3 * t)) / 2)
        }
        for point in found {
            let nearest = known.map { $0.distance(to: point) }.min() ?? .infinity
            #expect(nearest < radius * 0.01, "\(point) is \(nearest) from the nephroid")
        }
        // And it is the whole curve rather than a piece of it: the nephroid runs
        // from its cusps, half a radius out, to the mirror it bounced off.
        let reach = found.map { $0.length }.max() ?? 0
        let closest = found.map { $0.length }.min() ?? 0
        #expect(abs(reach - radius) < radius * 0.01, "the caustic reaches \(reach)")
        #expect(abs(closest - radius / 2) < radius * 0.01, "the cusps sit at \(closest)")
    }

    /// A source at the middle of a circular mirror sends every ray straight back
    /// through the middle, so the caustic collapses to that point.
    @Test func aSourceAtTheCenterSendsEverythingBackToIt() {
        let circle = (0 ..< 180).map { Vector2(angle: Double($0) / 180 * .tau, length: 60) }
        let rays = reflectedRays(off: circle, from: .point(.zero), closed: true)
        for ray in rays {
            #expect(ray.distance(to: .zero) < 1e-9, "a ray missed the middle")
        }
        // Neighboring rays through one point cross there, so the envelope is that
        // point, over and over.
        let points = envelope(of: rays, closed: true).flatMap(\.points)
        for point in points {
            #expect(point.length < 1e-6, "\(point) is not the middle")
        }
    }

    /// Parallel lines never cross, so a flat mirror lit from far away has no
    /// envelope at all. The answer has to be nothing, not a pile of far-away
    /// points.
    @Test func aFlatMirrorLitFromFarAwayHasNoEnvelope() {
        let flat = (0 ... 40).map { Vector2(Double($0) * 10 - 200, 0) }
        let rays = reflectedRays(off: flat, from: .parallel(.pi / 3))
        #expect(rays.count == flat.count - 2)
        #expect(envelope(of: rays).isEmpty)
        // The rays themselves are real, and all point the same way.
        for ray in rays {
            #expect(abs(ray.direction.normalized.cross(rays[0].direction.normalized)) < 1e-9)
        }
    }

    /// The mirror law, on its own: the angle a ray leaves at equals the angle it
    /// arrived at, measured against the surface.
    @Test func aBounceKeepsItsAngleToTheSurface() {
        let circle = (0 ..< 120).map { Vector2(angle: Double($0) / 120 * .tau, length: 80) }
        let source = LightSource.point(Vector2(-400, 90))
        let rays = reflectedRays(off: circle, from: source, closed: true)
        for (index, ray) in rays.enumerated() {
            let point = circle[index]
            let normal = point.normalized      // the circle's own normal, independently
            let incoming = source.direction(reaching: point).normalized
            let outgoing = ray.direction.normalized
            #expect(abs(abs(incoming.dot(normal)) - abs(outgoing.dot(normal))) < 1e-9,
                    "the angle changed at \(point)")
            // And the ray really did turn around: it leaves on the other side.
            #expect(incoming.dot(normal) * outgoing.dot(normal) < 0 || abs(incoming.dot(normal)) < 1e-9)
        }
    }

    /// Snell's law, on its own: the sines of the two angles stand in the ratio of
    /// the two indices.
    @Test func aBendKeepsSnellsRatio() {
        let surface = (0 ... 60).map { Vector2(Double($0) * 6 - 180, 0) }
        let index = 1.5
        let angle = Double.pi / 2 + 0.6      // arriving at a slant
        let rays = refractedRays(through: surface, from: .parallel(angle), index: index)
        #expect(rays.count == surface.count - 2)
        let normal = Vector2(0, 1)
        let incoming = Vector2(angle: angle)
        let sinIn = abs(incoming.cross(normal))
        for ray in rays {
            let sinOut = abs(ray.direction.normalized.cross(normal))
            #expect(abs(sinIn - index * sinOut) < 1e-9, "\(sinIn) against \(index) times \(sinOut)")
        }
    }

    /// A ray that meets the surface too steeply on the way out turns back instead
    /// of crossing, and those are left out rather than faked.
    @Test func aRayThatCannotCrossIsLeftOut() {
        let surface = (0 ... 40).map { Vector2(Double($0) * 6 - 120, 0) }
        // Leaving glass for air, well past the critical angle.
        let steep = refractedRays(through: surface, from: .parallel(.pi / 2 + 1.2), index: 1 / 1.5)
        #expect(steep.isEmpty)
        let shallow = refractedRays(through: surface, from: .parallel(.pi / 2 + 0.2), index: 1 / 1.5)
        #expect(shallow.count == surface.count - 2)
    }

    /// Too few points to have a surface, or too few lines to cross.
    @Test func theSmallCasesAreAnsweredPlainly() {
        #expect(envelope(of: []).isEmpty)
        #expect(envelope(of: [Ray2(origin: .zero, direction: Vector2(1, 0))]).isEmpty)
        #expect(reflectedRays(off: [Vector2(0, 0), Vector2(1, 1)], from: .parallel(0)).isEmpty)
        #expect(caustic(off: [], from: .parallel(0)).isEmpty)
    }
}

/// Laws for the Huygens construction: a front is where the wavelets lean, so
/// every point of the answer is exactly a wavelet's radius from the old front and
/// no nearer to any part of it.
@Suite
struct HuygensTests {
    /// A straight front stays straight and moves by exactly what it was asked to.
    @Test func aStraightFrontMovesStraight() {
        let front = (0 ... 50).map { Vector2(Double($0) * 8, 40) }
        let runs = huygensFront(from: front, advancing: 30)
        #expect(runs.count == 1)
        for point in runs[0].points {
            #expect(abs(abs(point.y - 40) - 30) < 1e-9, "\(point) did not move 30")
        }
        // And the other way is the other way.
        let back = huygensFront(from: front, advancing: -30)
        #expect(back.count == 1)
        let forward = runs[0].points[0].y, backward = back[0].points[0].y
        #expect((forward - 40) * (backward - 40) < 0, "both fronts went the same way")
    }

    /// A ring grows and shrinks by the radius it was given, which is the closed
    /// case and the easiest one to be sure of.
    @Test func aRingGrowsAndShrinksByTheDistance() {
        let radius = 100.0
        let ring = (0 ..< 400).map { Vector2(angle: Double($0) / 400 * .tau, length: radius) }
        for step in [-40.0, -12, 15, 60] {
            let runs = huygensFront(from: ring, advancing: step, closed: true)
            let points = runs.flatMap(\.points)
            #expect(!points.isEmpty, "nothing came back for \(step)")
            for point in points {
                #expect(abs(point.length - abs(radius + step)) < 0.2,
                        "\(point.length) is not \(abs(radius + step))")
            }
        }
    }

    /// The rule the construction is made of, measured directly: every point of the
    /// new front is exactly a wavelet away from the old one, and no nearer to any
    /// part of it.
    @Test func everyPointIsOneWaveletFromTheOldFront() {
        // A front with a real hollow in it, so there is something to fold.
        let front = (0 ... 120).map { i -> Vector2 in
            let x = Double(i) * 4 - 240
            return Vector2(x, 60 * cos(x / 80))
        }
        let reach = 45.0
        let points = huygensFront(from: front, advancing: reach).flatMap(\.points)
        #expect(points.count > 40)

        // A sampled front is a run of chords sitting a little inside the curve it
        // stands for, so the answer is right to about that much: the sagitta of one
        // segment, which is a twentieth of a unit here.
        let slack = 0.05
        for point in points {
            var nearest = Double.infinity
            for i in 0 ..< (front.count - 1) {
                nearest = Swift.min(nearest, toSegment(point, front[i], front[i + 1]))
            }
            #expect(nearest > reach - slack, "\(point) is only \(nearest) from the old front")
            #expect(nearest < reach + slack, "\(point) is \(nearest) from the old front")
        }
    }

    /// A front travelling into its own hollow loses the pieces that fold over. The
    /// fold begins exactly when the front has travelled the radius the curve bends
    /// at, so a shorter trip keeps everything and a longer one does not.
    @Test func aFrontTravellingIntoAHollowLosesTheFoldedPieces() {
        // y = 70 cos(x / 70) bends at a radius of 70 where it turns over, so that
        // is where the fold starts.
        let front = (0 ... 200).map { i -> Vector2 in
            let x = Double(i) * 2 - 200
            return Vector2(x, 70 * cos(x / 70))
        }
        let near = huygensFront(from: front, advancing: 30).flatMap(\.points).count
        let far = huygensFront(from: front, advancing: 120).flatMap(\.points).count
        #expect(near > far, "the far front kept \(far) points against \(near) near")
        #expect(far > 0)
        #expect(huygensFront(from: front, advancing: 120).count > 1, "the far front did not break up")
        // Going the other way, into the outside of the same bends, nothing folds.
        let outward = huygensFront(from: front, advancing: -120)
        #expect(outward.count == 1, "the outward front broke into \(outward.count) runs")
    }

    /// A ring collapsing inward past its own middle has nowhere left to be.
    @Test func aRingCollapsingPastItsMiddleVanishes() {
        let ring = (0 ..< 200).map { Vector2(angle: Double($0) / 200 * .tau, length: 50) }
        #expect(huygensFront(from: ring, advancing: -70, closed: true).isEmpty)
        #expect(!huygensFront(from: ring, advancing: -30, closed: true).isEmpty)
    }

    /// Nothing to advance, or nowhere to advance to.
    @Test func theSmallCasesAreAnsweredPlainly() {
        let front = (0 ... 10).map { Vector2(Double($0) * 5, 0) }
        #expect(huygensFront(from: front, advancing: 0).isEmpty)
        #expect(huygensFront(from: [], advancing: 10).isEmpty)
        #expect(huygensFront(from: [Vector2(0, 0), Vector2(1, 0)], advancing: 10).isEmpty)
    }

    private func toSegment(_ point: Vector2, _ a: Vector2, _ b: Vector2) -> Double {
        let along = b - a
        let lengthSquared = along.lengthSquared
        guard lengthSquared > 1e-24 else { return point.distance(to: a) }
        let t = Swift.max(0, Swift.min(1, (point - a).dot(along) / lengthSquared))
        return point.distance(to: a + along * t)
    }
}
