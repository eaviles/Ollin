import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Invariants of the physics that hold whatever the solver under the bridge: a
/// free body falls half g t squared and keeps its speed when nothing acts on it,
/// a pendulum returns to its height, a perfectly elastic ball returns to its
/// drop and one with no bounce does not bounce, a sleeping body wakes when the
/// world changes under it, a setting means one thing for every body, and what a
/// sketch sets is what it reads back. Each is read off the bodies' own motion
/// against an analytic value or a twin, never against the engine's arithmetic.
///
/// `.serialized` is load-bearing: the 2D world's engine keeps its worlds in a
/// global pool and is not thread-safe (see `RigidBodyTests`).
@Suite(.serialized)
struct PhysicsInvariantTests {

    /// A measured gap stands as a known issue only where it was measured; the
    /// statement runs plain everywhere else.
    private func pinned(_ reason: Comment, when active: Bool = true, _ body: () -> Void) {
        if active { withKnownIssue(reason, body) } else { body() }
    }

    private func run(_ world: World, seconds: Double, hz: Double = 60) {
        for _ in 0..<Int(seconds * hz) { world.advance(by: 1 / hz) }
    }

    private func run(_ world: World3D, seconds: Double, hz: Double = 60) {
        for _ in 0..<Int(seconds * hz) { world.advance(by: 1 / hz) }
    }

    // MARK: Falling and coasting

    /// A free body falls half g t squared in one second, in both worlds, within
    /// a percent (the semi-implicit step's own bias is a quarter of that at
    /// four substeps).
    @Test func aFreeBodyFallsHalfGTSquared() {
        let flat = World()
        flat.gravity = Vector2(0, 980)
        flat.drag = 0
        let disk = flat.addBody(.circle(radius: 10), at: .zero)
        run(flat, seconds: 1)
        #expect(abs(disk.position.y / 490 - 1) < 0.01, "the 2D body fell \(disk.position.y) of 490")

        let deep = World3D()
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 100, 0))
        run(deep, seconds: 1)
        #expect(abs((100 - ball.position.y) / 4.9 - 1) < 0.01, "the 3D body fell \(100 - ball.position.y) of 4.9")
    }

    /// A body with nothing acting on it keeps its speed and its spin: in zero
    /// gravity, at zero drag, five seconds later it moves as it did.
    ///
    /// Measured 2026-10-11 and filed: every 3D body carries the engine's
    /// default damping of 5% a second on both its velocity and its spin, with
    /// nothing in the API to turn it off, so a body coasting at 10 reads 7.79
    /// after five seconds and a thrown ball lands 7% short of the parabola.
    /// The 2D body at drag 0 holds exactly.
    @Test func aCoastingBodyKeepsItsSpeed() {
        let flat = World()
        flat.gravity = .zero
        flat.drag = 0
        let disk = flat.addBody(.circle(radius: 10), at: Vector2(0, 500))
        disk.velocity = Vector2(600, 0)
        disk.angularVelocity = 5
        run(flat, seconds: 5)
        #expect(abs(disk.velocity.x / 600 - 1) < 0.005, "the 2D body coasts at \(disk.velocity.x) of 600")
        #expect(abs(disk.angularVelocity / 5 - 1) < 0.005, "the 2D body spins at \(disk.angularVelocity) of 5")

        let deep = World3D()
        deep.gravity = .zero
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 5, 0))
        ball.velocity = Vector3(10, 0, 0)
        ball.angularVelocity = Vector3(0, 5, 0)
        run(deep, seconds: 5)
        pinned("every 3D body carries 5% a second of damping with no way to turn it off (measured 2026-10-11)") {
            #expect(abs(ball.velocity.x / 10 - 1) < 0.005, "the 3D body coasts at \(ball.velocity.x) of 10")
            #expect(abs(ball.angularVelocity.y / 5 - 1) < 0.005, "the 3D body spins at \(ball.angularVelocity.y) of 5")
        }
    }

    /// The world's `drag` means one thing: a particle and a rigid body given
    /// the same drag and the same launch slow at the same rate.
    ///
    /// Measured 2026-10-11 and filed: a particle's drag is taken once a step
    /// and a body's once a second (the engine's linear damping), so at 60 Hz
    /// and drag 0.01 the particle keeps 55% of its speed after a second and the
    /// body 99%, a factor of sixty between two readings of one number.
    @Test func dragMeansTheSameForAParticleAndABody() {
        let world = World()
        world.gravity = .zero
        world.drag = 0.01
        let particle = world.addParticle(at: .zero)
        particle.previous = Vector2(-10, 0)   // 600 px/s at 60 Hz
        let body = world.addBody(.circle(radius: 10), at: Vector2(0, 500))
        body.velocity = Vector2(600, 0)
        run(world, seconds: 1)
        let particleSpeed = particle.velocity.x * 60, bodySpeed = body.velocity.x
        pinned("drag is per step for a particle and per second for a body (measured 2026-10-11)") {
            #expect(abs(particleSpeed / bodySpeed - 1) < 0.05, "after a second the particle moves at \(particleSpeed) and the body at \(bodySpeed)")
        }
    }

    /// A particle's drag does not depend on the frame rate: a coasting particle
    /// keeps the same speed after one second at 30, 60, and 120 Hz.
    ///
    /// Measured 2026-10-11 and filed: the drag is applied once a step whatever
    /// the step, so a particle keeps 74% of its speed after a second at 30 Hz,
    /// 55% at 60, and 30% at 120.
    @Test func aParticlesDragIsTheSameAtEveryFrameRate() {
        func remaining(at hz: Double) -> Double {
            let world = World()
            world.gravity = .zero
            let p = world.addParticle(at: .zero)
            p.previous = Vector2(-600 / hz, 0)
            run(world, seconds: 1, hz: hz)
            return p.velocity.x * hz
        }
        let slow = remaining(at: 30), fast = remaining(at: 120)
        pinned("a particle's drag is taken once a step, so it depends on the frame rate (measured 2026-10-11)") {
            #expect(abs(slow / fast - 1) < 0.05, "a second of drag leaves \(slow) px/s at 30 Hz and \(fast) at 120")
        }
    }

    // MARK: Returning to a height

    /// A pendulum returns to the height it was released from: a bar hinged at
    /// one end and let go horizontal comes back to the pivot's height at every
    /// apex, within 5% of its swing, for ten seconds. Three pendulums: a 2D
    /// rigid bar, a 3D rigid bar, and a Verlet bob on a rod.
    ///
    /// Measured 2026-10-11 and filed: the 2D bar holds to 0.1% of its swing.
    /// The 3D bar loses 13% of its swing on the first half swing and 56% by
    /// the seventh (the body damping above). The Verlet bob at drag 0 gives
    /// back 70% of its height on the first swing at 60 Hz (91% at 240 Hz,
    /// 96% at 600): the projection of a plain Verlet step onto the rod takes
    /// the radial share of each step's motion with it, a loss first order in
    /// the step, and the model in numpy reproduces the numbers exactly.
    @Test(arguments: ["2D rigid", "3D rigid", "Verlet"])
    func aPendulumReturnsToItsHeight(kind: String) {
        var apexes: [Double] = []
        switch kind {
        case "2D rigid":
            let world = World()
            world.gravity = Vector2(0, 980)
            world.drag = 0
            let anchor = world.addBody(.box(width: 10, height: 10), at: .zero, kind: .static)
            let bar = world.addBody(.box(width: 200, height: 10), at: Vector2(100, 0), friction: 0)
            world.connect(anchor, bar, .revolute(at: .zero))
            var lastVy = 0.0
            for _ in 0..<600 {
                world.advance(by: 1.0 / 60)
                let vy = bar.velocity.y
                if lastVy != 0 && (lastVy > 0) != (vy > 0) && abs(bar.position.y) < 80 { apexes.append(bar.position.y / 100) }
                lastVy = vy
            }
        case "3D rigid":
            let world = World3D()
            let bar = world.addBody(.box(width: 2, height: 0.1, depth: 0.1), at: Vector3(1, 5, 0), friction: 0)
            _ = world.connect(bar, toWorld: .revolute(at: Vector3(0, 5, 0), axis: .unitZ))
            var lastVy = 0.0
            for _ in 0..<600 {
                world.advance(by: 1.0 / 60)
                let vy = bar.velocity.y
                if lastVy != 0 && (lastVy > 0) != (vy > 0) && abs(bar.position.y - 5) < 0.8 { apexes.append(5 - bar.position.y) }
                lastVy = vy
            }
        default:
            let world = World()
            world.gravity = Vector2(0, 980)
            world.drag = 0
            let pin = world.addParticle(at: .zero).pin()
            let bob = world.addParticle(at: Vector2(100, 0))
            _ = world.connect(pin, bob, length: 100, stiffness: 1)
            var lastVy = 0.0
            for _ in 0..<600 {
                world.advance(by: 1.0 / 60)
                let vy = bob.velocity.y
                if lastVy != 0 && (lastVy > 0) != (vy > 0) && abs(bob.position.y) < 80 { apexes.append(bob.position.y / 100) }
                lastVy = vy
            }
        }
        #expect(apexes.count >= 5, "\(kind): only \(apexes.count) apexes in ten seconds")
        let lost = apexes.max() ?? 1
        pinned("the 3D bar's damping and the Verlet rod's projection lose height every swing (measured 2026-10-11)",
               when: kind != "2D rigid") {
            #expect(lost < 0.05, "\(kind) fell \(lost) of its swing short of the pivot's height at an apex")
        }
    }

    /// A ball dropped at restitution 1 onto a floor returns to its drop, within
    /// 5% from 100 px in 2D and within 7% from 1 m in 3D (whose five percent a
    /// second of damping takes the rest).
    @Test func aPerfectlyElasticBallReturnsToItsDrop() {
        let flat = World()
        flat.gravity = Vector2(0, 980)
        flat.drag = 0
        flat.restitution = 1
        _ = flat.addBody(.box(width: 2000, height: 20), at: Vector2(0, 510), kind: .static)
        let disk = flat.addBody(.circle(radius: 10), at: Vector2(0, 490 - 100), restitution: 1)
        var apex = 1000.0, bounced = false, lastVy = 0.0
        for _ in 0..<240 {
            flat.advance(by: 1.0 / 60)
            if bounced { apex = min(apex, disk.position.y) }
            if lastVy > 0 && disk.velocity.y < 0 { bounced = true }
            lastVy = disk.velocity.y
        }
        #expect(bounced)
        #expect(abs((490 - apex) / 100 - 1) < 0.05, "the 2D ball rose \(490 - apex) of 100")

        let deep = World3D()
        deep.restitution = 1
        deep.ground = 0
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 1.5, 0), restitution: 1)
        var top = 0.0, rose = false, lastUp = 0.0
        for _ in 0..<240 {
            deep.advance(by: 1.0 / 60)
            if rose { top = max(top, ball.position.y - 0.5) }
            if lastUp < 0 && ball.velocity.y > 0 { rose = true }
            lastUp = ball.velocity.y
        }
        #expect(rose)
        #expect(abs(top - 1) < 0.07, "the 3D ball rose \(top) of 1")
    }

    /// A body given `restitution: 0` does not bounce, whatever the world's
    /// default: the world's value is what a body gets when it names none, not
    /// a floor under the one it names.
    ///
    /// Measured 2026-10-11 and filed: both engines combine the pair's
    /// restitution by the larger, and the walls and the ground carry the
    /// world's value, so a dead ball on a default floor rises 28 px from a
    /// 110 px drop in 2D (the world's 0.5) and 6.5 cm from 2.5 m in 3D (the
    /// world's 0.2); with the world's value at 0 neither bounces.
    @Test func aBallWithNoBounceDoesNotBounce() {
        let flat = World()
        flat.gravity = Vector2(0, 980)
        flat.drag = 0
        flat.bounds = Rectangle(x: 0, y: 0, width: 1000, height: 1000)
        let disk = flat.addBody(.circle(radius: 10), at: Vector2(500, 880), restitution: 0)
        var apex = 1000.0, bounced = false, lastVy = 0.0
        for _ in 0..<300 {
            flat.advance(by: 1.0 / 60)
            if bounced { apex = min(apex, disk.position.y) }
            if lastVy > 0 && disk.velocity.y < 0 { bounced = true }
            lastVy = disk.velocity.y
        }
        pinned("the world's restitution is a floor under a body's own in both worlds (measured 2026-10-11)") {
            #expect(990 - apex < 2, "the 2D ball with no bounce rose \(990 - apex) px")
        }

        let deep = World3D()
        deep.ground = 0
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 3, 0), restitution: 0)
        var top = 0.0, rose = false, lastUp = 0.0
        for _ in 0..<300 {
            deep.advance(by: 1.0 / 60)
            if rose { top = max(top, ball.position.y - 0.5) }
            if lastUp < 0 && ball.velocity.y > 0 { rose = true }
            lastUp = ball.velocity.y
        }
        pinned("the world's restitution is a floor under a body's own in both worlds (measured 2026-10-11)") {
            #expect(top < 0.01, "the 3D ball with no bounce rose \(top)")
        }
    }

    // MARK: What the world says reaches its bodies

    /// A body resting on the floor rises when gravity is turned upward: a
    /// change to the world reaches a body that has gone to sleep.
    ///
    /// Measured 2026-10-11 and filed: neither engine wakes a sleeping body
    /// when the world's gravity changes, so a box settled for half a second
    /// stays on the floor under gravity pointing the other way, in both
    /// worlds.
    @Test func aSleepingBodyWakesWhenGravityChanges() {
        let flat = World()
        flat.gravity = Vector2(0, 980)
        flat.bounds = Rectangle(x: 0, y: 0, width: 1000, height: 1000)
        let box = flat.addBody(.box(width: 40, height: 40), at: Vector2(500, 970))
        run(flat, seconds: 3)
        let rest = box.position.y
        flat.gravity = Vector2(0, -980)
        run(flat, seconds: 1)
        pinned("a sleeping body is not woken by a change of gravity (measured 2026-10-11)") {
            #expect(rest - box.position.y > 100, "the 2D box moved \(rest - box.position.y) px after gravity flipped")
        }

        let deep = World3D()
        deep.ground = 0
        let crate = deep.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 0.5, 0))
        run(deep, seconds: 3)
        #expect(!crate.isAwake, "the 3D box never went to sleep, so the statement was not tested")
        deep.gravity = Vector3(0, 9.8, 0)
        run(deep, seconds: 1)
        pinned("a sleeping body is not woken by a change of gravity (measured 2026-10-11)") {
            #expect(crate.position.y > 2, "the 3D box rose to \(crate.position.y) after gravity flipped")
        }
    }

    /// The world's `restitution` reaches its walls when it changes, not only
    /// when they were built: a ball dropped after the world's restitution was
    /// set to 0 does not bounce off them.
    ///
    /// Measured 2026-10-11 and filed: the walls and each body read the
    /// world's `restitution` and `drag` once, when they are made, so a value
    /// set afterwards changes nothing already in the world (the ball rose
    /// 28 px on walls built at 0.5).
    @Test func aWorldsRestitutionReachesItsWallsWhenChanged() {
        let world = World()
        world.gravity = Vector2(0, 980)
        world.drag = 0
        world.bounds = Rectangle(x: 0, y: 0, width: 1000, height: 1000)
        let disk = world.addBody(.circle(radius: 10), at: Vector2(500, 880))
        world.restitution = 0
        var apex = 1000.0, bounced = false, lastVy = 0.0
        for _ in 0..<300 {
            world.advance(by: 1.0 / 60)
            if bounced { apex = min(apex, disk.position.y) }
            if lastVy > 0 && disk.velocity.y < 0 { bounced = true }
            lastVy = disk.velocity.y
        }
        pinned("the walls read the world's restitution once, when they are built (measured 2026-10-11)") {
            #expect(990 - apex < 2, "the ball rose \(990 - apex) px off walls whose world was set to 0")
        }
    }

    /// An angular velocity a sketch sets is the one it reads back a step later,
    /// in radians a second, with nothing acting on the body.
    ///
    /// Measured 2026-10-11 and filed: both engines cap a body's spin at a
    /// quarter turn a step, 47.1 rad/s at 60 Hz (seven and a half turns a
    /// second), and the 2D cap halves at a 1/30 frame; a fan set to 100 rad/s
    /// reads 47 with no note.
    @Test func angularVelocityIsWhatWasSet() {
        let flat = World()
        flat.gravity = .zero
        flat.drag = 0
        let disk = flat.addBody(.circle(radius: 50), at: Vector2(500, 500))
        disk.angularVelocity = 100
        flat.advance(by: 1.0 / 60)
        pinned("a spin is capped at a quarter turn a step in both worlds (measured 2026-10-11)") {
            #expect(abs(disk.angularVelocity / 100 - 1) < 0.01, "the 2D body set to 100 rad/s spins at \(disk.angularVelocity)")
        }
        let deep = World3D()
        deep.gravity = .zero
        let top = deep.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 5, 0))
        top.angularVelocity = Vector3(0, 100, 0)
        deep.advance(by: 1.0 / 60)
        pinned("a spin is capped at a quarter turn a step in both worlds (measured 2026-10-11)") {
            #expect(abs(top.angularVelocity.y / 100 - 1) < 0.01, "the 3D body set to 100 rad/s spins at \(top.angularVelocity.y)")
        }
    }
}
