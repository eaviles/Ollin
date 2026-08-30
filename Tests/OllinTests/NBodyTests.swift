import Testing
import Foundation
@testable import Ollin

struct NBodyTests {

    /// The exact all-pairs softened sum, written independently of the tree.
    private func bruteForce(_ system: NBody) -> [Vector2] {
        let bodies = system.bodies
        let softening2 = system.softening * system.softening
        return bodies.indices.map { i in
            var acceleration = Vector2.zero
            for j in bodies.indices where j != i {
                let offset = bodies[j].position - bodies[i].position
                let distance2 = offset.lengthSquared + softening2
                acceleration += offset * (bodies[j].mass / (distance2 * distance2.squareRoot()))
            }
            return acceleration * system.gravity
        }
    }

    @Test func thetaZeroMatchesTheAllPairsSum() {
        let system = NBody.cluster(count: 120, center: Vector2(500, 500), radius: 300, seed: 7)
        system.theta = 0
        let tree = system.computeAccelerations()
        let exact = bruteForce(system)
        for i in tree.indices {
            #expect(tree[i].distance(to: exact[i]) <= exact[i].length * 1e-9 + 1e-12)
        }
    }

    @Test func treeApproximationStaysNearTheExactSum() {
        let system = NBody.cluster(count: 400, center: Vector2(500, 500), radius: 350, seed: 3)
        let exact = bruteForce(system)
        // Judge errors against the field's typical strength: a body whose
        // pulls nearly cancel has a tiny net force, so its own relative error
        // is meaningless even when the tree is accurate.
        let typical = exact.reduce(0.0) { $0 + $1.length } / Double(exact.count)
        func errors(theta: Double) -> [Double] {
            system.theta = theta
            let tree = system.computeAccelerations()
            return tree.indices.map { tree[$0].distance(to: exact[$0]) / typical }.sorted()
        }

        // At the balanced default the approximation stays a hair from exact
        // across the whole distribution (measured with generous headroom).
        let balanced = errors(theta: 0.7)
        #expect(balanced[balanced.count / 2] < 0.05)                          // median
        #expect(balanced[Int(Double(balanced.count) * 0.95)] < 0.12)          // tail
        #expect(balanced.last! < 0.3)                                         // worst

        // Halving the opening angle must shrink the error roughly
        // quadratically; this is what breaks if the opening criterion or the
        // center-of-mass bookkeeping regresses.
        let tight = errors(theta: 0.35)
        #expect(tight[tight.count / 2] < balanced[balanced.count / 2] / 2)
    }

    @Test func exactSumConservesMomentum() {
        // At theta 0 every pull has its equal and opposite partner, so the
        // total momentum cannot drift beyond roundoff.
        let system = NBody.cluster(count: 80, center: Vector2(400, 400), radius: 250, seed: 11)
        system.theta = 0
        func momentum() -> Vector2 {
            system.bodies.reduce(.zero) { $0 + $1.velocity * $1.mass }
        }
        let before = momentum()
        for _ in 0 ..< 60 { system.advance() }
        let speedScale = system.bodies.reduce(0.0) { $0 + $1.velocity.length * $1.mass }
        #expect(momentum().distance(to: before) < max(speedScale, 1) * 1e-9)
    }

    @Test func coincidentBodiesDoNotHang() {
        // Two bodies at the same point can never be separated by subdividing;
        // the depth cap must chain them instead of recursing forever.
        let system = NBody(bodies: [
            NBody.Body(position: Vector2(100, 100), mass: 10),
            NBody.Body(position: Vector2(100, 100), mass: 10),
            NBody.Body(position: Vector2(300, 250), mass: 10),
        ])
        let accelerations = system.computeAccelerations()
        for a in accelerations {
            #expect(a.x.isFinite && a.y.isFinite)
        }
        system.advance()
        for body in system.bodies {
            #expect(body.position.x.isFinite && body.position.y.isFinite)
        }
    }

    @Test func aCircularOrbitStaysCircular() {
        // One light satellite on the circular-orbit speed around a heavy
        // center: the leapfrog holds the radius across a whole revolution.
        let center = Vector2(540, 540)
        let radius = 200.0
        let centralMass = 100_000.0
        let speed = (centralMass / radius).squareRoot()
        let system = NBody(bodies: [
            NBody.Body(position: center, mass: centralMass),
            NBody.Body(position: center + Vector2(radius, 0),
                       velocity: Vector2(0, speed), mass: 1e-6),
        ], softening: 0.01)
        let period = 2 * Double.pi * radius / speed
        let steps = Int((period * 60).rounded())
        for _ in 0 ..< steps {
            system.advance()
            let r = system.bodies[1].position.distance(to: system.bodies[0].position)
            #expect(abs(r - radius) < radius * 0.01)
        }
    }

    @Test func seededRunsAreDeterministic() {
        let a = NBody.disk(count: 200, center: Vector2(500, 500), radius: 300, seed: 5)
        let b = NBody.disk(count: 200, center: Vector2(500, 500), radius: 300, seed: 5)
        for _ in 0 ..< 30 { a.advance(); b.advance() }
        for i in a.bodies.indices {
            #expect(a.bodies[i].position == b.bodies[i].position)
            #expect(a.bodies[i].velocity == b.bodies[i].velocity)
        }
    }

    @Test func diskFactoryShapesTheSystem() {
        let center = Vector2(500, 500)
        let system = NBody.disk(count: 300, center: center, radius: 250, seed: 2)
        #expect(system.bodies.count == 301)
        #expect(system.bodies[0].position == center)     // the heavy anchor
        #expect(system.bodies[0].mass > system.bodies[1].mass * 1000)
        for body in system.bodies.dropFirst() {
            let r = body.position.distance(to: center)
            #expect(r <= 250 + 1e-9 && r >= 250 * 0.12 - 1e-9)
            #expect(body.velocity.length > 0)
        }
    }
}
