import Ollin
import Testing

/// Pure-CPU checks on the steering behaviors: forces point the right way, stay
/// capped, and a seeded creature retraces the same path.
@Suite
struct SteeringTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 400, height: 400)

    /// Seek points at the target and the force is capped at `maxForce`.
    @Test func seekPointsAtTargetAndCaps() {
        let v = Vehicle(at: Vector2(100, 100), maxSpeed: 3, maxForce: 0.1)
        let force = v.seek(Vector2(300, 100))
        #expect(force.x > 0)
        #expect(abs(force.y) < 1e-9)
        #expect(force.length <= 0.1 + 1e-9)
        // Flee is the mirror.
        let away = v.flee(Vector2(300, 100))
        #expect(away.x < 0)
    }

    /// At the target, arrive brakes (the force opposes the velocity), and
    /// inside the slowing radius the desired speed ramps down.
    @Test func arriveSlowsNearTarget() {
        let v = Vehicle(at: Vector2(200, 200), velocity: Vector2(3, 0), maxSpeed: 3, maxForce: 10)
        let braking = v.arrive(at: Vector2(200, 200))
        #expect(braking.x < 0)

        // 10 px from the target with a 100 px slowing radius: desired speed is
        // maxSpeed * 0.1, so the steering force pushes back against the velocity.
        let close = Vehicle(at: Vector2(190, 200), velocity: Vector2(3, 0), maxSpeed: 3, maxForce: 10)
        let easing = close.arrive(at: Vector2(200, 200), slowingRadius: 100)
        #expect(easing.x < 0)   // desired (0.3) is slower than current (3)

        // Far outside the slowing radius, arrive behaves like seek.
        let far = Vehicle(at: Vector2(0, 200), velocity: .zero, maxSpeed: 3, maxForce: 10)
        let seekLike = far.arrive(at: Vector2(200, 200), slowingRadius: 100)
        let seek = far.seek(Vector2(200, 200))
        #expect(abs(seekLike.x - seek.x) < 1e-9)
        #expect(abs(seekLike.y - seek.y) < 1e-9)
    }

    /// Pursuit leads a moving target: against a target moving up, the pursuit
    /// force tilts above plain seek.
    @Test func pursuitLeadsTheTarget() {
        let v = Vehicle(at: Vector2(0, 0), maxSpeed: 3, maxForce: 1)
        let seek = v.seek(Vector2(100, 0))
        let pursue = v.pursue(Vector2(100, 0), velocity: Vector2(0, 2))
        #expect(pursue.y > seek.y)
    }

    /// Two vehicles with the same seed wander identically; different seeds diverge.
    @Test func wanderIsSeeded() {
        func path(seed: UInt64) -> [Vector2] {
            let v = Vehicle(at: Vector2(200, 200), velocity: Vector2(1, 0), seed: seed)
            var points: [Vector2] = []
            for _ in 0 ..< 50 {
                v.applyForce(v.wander())
                v.step()
                points.append(v.position)
            }
            return points
        }
        let a = path(seed: 7), b = path(seed: 7), c = path(seed: 8)
        #expect(a == b)
        #expect(a != c)
    }

    /// On the path there is no correction; far off it, the force steers back
    /// toward the path.
    @Test func pathFollowingCorrectsOnlyOffPath() {
        let path = [Vector2(0, 200), Vector2(400, 200)]
        let on = Vehicle(at: Vector2(100, 205), velocity: Vector2(3, 0), maxSpeed: 3, maxForce: 1)
        #expect(on.follow(path: path, radius: 20) == .zero)

        let off = Vehicle(at: Vector2(100, 300), velocity: Vector2(3, 0), maxSpeed: 3, maxForce: 1)
        let force = off.follow(path: path, radius: 20)
        #expect(force.y < 0)   // back up toward y = 200
    }

    /// On a closed path the walk-ahead wraps through the seam instead of
    /// clamping at the last point, so the same geometry steers differently
    /// closed vs open once the target passes the seam.
    @Test func closedPathWrapsAtTheSeam() {
        // The projection lands at the far end (arc length 100); walking 60
        // further wraps onto the return segment when closed, clamps when open.
        let path = [Vector2(0, 0), Vector2(100, 0)]
        let v = Vehicle(at: Vector2(120, 50), velocity: Vector2(3, 0), maxSpeed: 3, maxForce: 1)
        let wrapped = v.follow(path: path, radius: 10, lookAhead: 60, closed: true)
        let clamped = v.follow(path: path, radius: 10, lookAhead: 60, closed: false)
        #expect(wrapped != .zero)
        #expect(wrapped != clamped)
    }

    /// Separation pushes away from a crowding neighbor and ignores far ones.
    @Test func separationPushesFromCrowding() {
        let a = Vehicle(at: Vector2(100, 100))
        let b = Vehicle(at: Vector2(110, 100))
        let c = Vehicle(at: Vector2(390, 390))
        let force = a.separate(from: [a, b, c], radius: 25)
        #expect(force.x < 0)   // pushed left, away from b
        #expect(a.separate(from: [a, c], radius: 25) == .zero)
    }

    /// Containment pushes inward near an edge and is zero in the middle.
    @Test func containmentPushesInward() {
        let nearLeft = Vehicle(at: Vector2(10, 200))
        #expect(nearLeft.contain(in: bounds).x > 0)
        let middle = Vehicle(at: Vector2(200, 200))
        #expect(middle.contain(in: bounds) == .zero)
    }

    /// Step integrates the accumulated force, caps speed, and clears the force.
    @Test func stepIntegratesAndCapsSpeed() {
        let v = Vehicle(at: .zero, velocity: Vector2(2, 0), maxSpeed: 3, maxForce: 10)
        v.applyForce(Vector2(5, 0))
        v.step()
        #expect(abs(v.velocity.x - 3) < 1e-9)   // capped at maxSpeed
        #expect(abs(v.position.x - 3) < 1e-9)
        v.step()   // force was cleared, velocity carries
        #expect(abs(v.position.x - 6) < 1e-9)
    }
}
