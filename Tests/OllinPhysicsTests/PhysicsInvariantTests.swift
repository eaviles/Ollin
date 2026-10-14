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
/// Each was measured on 2026-10-11 and pinned where it fell; the fixes of
/// 2026-10-14 took the pins off, and the numbers in the comments are the ones
/// the gaps had.
///
/// `.serialized` is load-bearing: the 2D world's engine keeps its worlds in a
/// global pool and is not thread-safe (see `RigidBodyTests`).
@Suite(.serialized)
struct PhysicsInvariantTests {

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
    /// Before `World3D.drag` every 3D body carried the engine's own 5% a
    /// second on its velocity and its spin, with nothing to turn it off, so a
    /// body coasting at 10 read 7.79 after five seconds.
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
        deep.drag = 0
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 5, 0))
        ball.velocity = Vector3(10, 0, 0)
        ball.angularVelocity = Vector3(0, 5, 0)
        run(deep, seconds: 5)
        #expect(abs(ball.velocity.x / 10 - 1) < 0.005, "the 3D body coasts at \(ball.velocity.x) of 10")
        #expect(abs(ball.angularVelocity.y / 5 - 1) < 0.005, "the 3D body spins at \(ball.angularVelocity.y) of 5")
    }

    /// The default 3D `drag` is the solver's own feel, 5% a second on the
    /// speed and the spin, so a sketch written before the setting existed
    /// moves as it did.
    @Test func theDefaultThreeDDragIsFivePercentASecond() {
        let deep = World3D()
        deep.gravity = .zero
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 5, 0))
        ball.velocity = Vector3(10, 0, 0)
        ball.angularVelocity = Vector3(0, 5, 0)
        run(deep, seconds: 1)
        #expect(abs(ball.velocity.x / (10 * exp(-0.05)) - 1) < 0.005, "the 3D body coasts at \(ball.velocity.x) of \(10 * exp(-0.05))")
        #expect(abs(ball.angularVelocity.y / (5 * exp(-0.05)) - 1) < 0.005, "the 3D body spins at \(ball.angularVelocity.y) of \(5 * exp(-0.05))")
    }

    /// The world's `drag` means one thing: a particle and a rigid body given
    /// the same drag and the same launch slow at the same rate, and that rate
    /// is the share lost per sixtieth of a second compounded (0.99 to the
    /// sixtieth after a second at 0.01), the feel every particle sketch had.
    ///
    /// Before the fix a particle's drag was taken once a step and a body's
    /// once a second (the engine's linear damping), so at 60 Hz and drag 0.01
    /// the particle kept 55% of its speed after a second and the body 99%.
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
        let expected = 600 * pow(0.99, 60.0)
        #expect(abs(particleSpeed / bodySpeed - 1) < 0.05, "after a second the particle moves at \(particleSpeed) and the body at \(bodySpeed)")
        #expect(abs(particleSpeed / expected - 1) < 0.01, "the particle keeps \(particleSpeed) of \(expected)")
        #expect(abs(bodySpeed / expected - 1) < 0.01, "the body keeps \(bodySpeed) of \(expected)")

        let deep = World3D()
        deep.gravity = .zero
        deep.drag = 0.01
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 5, 0))
        ball.velocity = Vector3(10, 0, 0)
        run(deep, seconds: 1)
        #expect(abs(ball.velocity.x / (10 * pow(0.99, 60.0)) - 1) < 0.01, "the 3D body keeps \(ball.velocity.x) of \(10 * pow(0.99, 60.0))")
    }

    /// A `drag` set after the bodies were added reaches them: a coasting body
    /// in each world slows once the world's drag is raised, and a 2D body made
    /// `.kinematic`, which moves only by the velocity it is given, is never
    /// dragged at all.
    @Test func aWorldsDragReachesItsBodiesWhenChanged() {
        let flat = World()
        flat.gravity = .zero
        flat.drag = 0
        let disk = flat.addBody(.circle(radius: 10), at: Vector2(0, 500))
        disk.velocity = Vector2(600, 0)
        let sweeper = flat.addBody(.box(width: 40, height: 40), at: Vector2(0, 800), kind: .kinematic)
        sweeper.velocity = Vector2(600, 0)
        run(flat, seconds: 1)
        #expect(abs(disk.velocity.x / 600 - 1) < 0.005)
        flat.drag = 0.01
        run(flat, seconds: 1)
        #expect(abs(disk.velocity.x / (600 * pow(0.99, 60.0)) - 1) < 0.01, "the 2D body slowed to \(disk.velocity.x) after drag was set")
        #expect(abs(sweeper.velocity.x / 600 - 1) < 1e-6, "the kinematic body moves at \(sweeper.velocity.x) of 600 under drag")

        let deep = World3D()
        deep.gravity = .zero
        deep.drag = 0
        let ball = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 5, 0))
        ball.velocity = Vector3(10, 0, 0)
        run(deep, seconds: 1)
        #expect(abs(ball.velocity.x / 10 - 1) < 0.005)
        deep.drag = 0.01
        run(deep, seconds: 1)
        #expect(abs(ball.velocity.x / (10 * pow(0.99, 60.0)) - 1) < 0.01, "the 3D body slowed to \(ball.velocity.x) after drag was set")
    }

    /// A particle's drag does not depend on the frame rate: a coasting particle
    /// keeps the same speed after one second at 30, 60, and 120 Hz.
    ///
    /// Before the fix the drag was applied once a step whatever the step, so a
    /// particle kept 74% of its speed after a second at 30 Hz, 55% at 60, and
    /// 30% at 120.
    @Test func aParticlesDragIsTheSameAtEveryFrameRate() {
        func remaining(at hz: Double) -> Double {
            let world = World()
            world.gravity = .zero
            let p = world.addParticle(at: .zero)
            p.previous = Vector2(-600 / hz, 0)
            run(world, seconds: 1, hz: hz)
            return p.velocity.x * hz
        }
        let slow = remaining(at: 30), fast = remaining(at: 120), usual = remaining(at: 60)
        #expect(abs(slow / fast - 1) < 0.05, "a second of drag leaves \(slow) px/s at 30 Hz and \(fast) at 120")
        #expect(abs(usual / (600 * pow(0.99, 60.0)) - 1) < 0.01, "a second of drag at 60 Hz leaves \(usual) px/s of \(600 * pow(0.99, 60.0))")
    }

    // MARK: Returning to a height

    /// A pendulum returns to the height it was released from: a bar hinged at
    /// one end and let go horizontal comes back to the pivot's height at every
    /// apex, within 5% of its swing, for ten seconds. Three pendulums: a 2D
    /// rigid bar, a 3D rigid bar at drag 0 stepped in sixteen pieces a frame,
    /// and a Verlet bob on a rod stepped in sixty-four.
    ///
    /// The 2D bar holds to 0.1% of its swing at one piece. The other two lose
    /// a share first order in the step, so `substeps` is the cure in both
    /// worlds (measured 2026-10-14 at 60 Hz, the first apex then the seventh
    /// or eighth). The 3D hinge: 7.9% and 37% at one piece, 2.1% and 13% at
    /// four, 0.6% and 3.6% at sixteen; before `World3D.drag` the solver's own
    /// damping put the first apex at 13% and the seventh at 56%. The Verlet
    /// bob: 30% and 80% at one piece, since projecting a plain Verlet step
    /// onto the rod drops the share of the motion that pointed along it, 2.4%
    /// and 17% at sixteen, 0.7% and 4.7% at sixty-four; four pieces at 60 Hz
    /// and one at 240 Hz give the same apexes to the third digit.
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
            world.drag = 0
            world.substeps = 16
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
            world.substeps = 64
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
        #expect(lost < 0.05, "\(kind) fell \(lost) of its swing short of the pivot's height at an apex")
    }

    /// A ball dropped at restitution 1 onto a floor returns to its drop, within
    /// 5% from 100 px in 2D and from 1 m in 3D, both at drag 0.
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
        deep.drag = 0
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
        #expect(abs(top - 1) < 0.05, "the 3D ball rose \(top) of 1")
    }

    /// A body given `restitution: 0` does not bounce, whatever the world's
    /// default: the world's value is what a body gets when it names none, not
    /// a floor under the one it names. The walls and the ground carry no
    /// bounce of their own, and both engines combine a pair by the larger, so
    /// against them a body's own value is the one that counts.
    ///
    /// Before the fix the walls and the ground carried the world's value, so a
    /// dead ball on a default floor rose 28 px from a 110 px drop in 2D (the
    /// world's 0.5) and 6.5 cm from 2.5 m in 3D (the world's 0.2).
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
        #expect(990 - apex < 2, "the 2D ball with no bounce rose \(990 - apex) px")

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
        #expect(top < 0.01, "the 3D ball with no bounce rose \(top)")
    }

    /// A body that named its own `restitution` keeps it when the world's
    /// changes, and one that named none follows the world's, in both worlds.
    @Test func aBodyThatNamedItsBounceKeepsItWhenTheWorldsChanges() {
        let flat = World()
        let own = flat.addBody(.circle(radius: 10), at: Vector2(100, 100), restitution: 0.9)
        let handed = flat.addBody(.circle(radius: 10), at: Vector2(300, 100))
        #expect(own.restitution == 0.9 && handed.restitution == 0.5)
        flat.restitution = 0.1
        #expect(own.restitution == 0.9, "the 2D body that named 0.9 reads \(own.restitution)")
        #expect(handed.restitution == 0.1, "the 2D body that named none reads \(handed.restitution)")
        handed.restitution = 0.7
        flat.restitution = 0.3
        #expect(handed.restitution == 0.7, "a 2D body given a value afterwards keeps it")

        let deep = World3D()
        let ownBall = deep.addBody(.sphere(radius: 0.5), at: Vector3(0, 5, 0), restitution: 0.9)
        let handedBall = deep.addBody(.sphere(radius: 0.5), at: Vector3(3, 5, 0))
        #expect(abs(ownBall.restitution - 0.9) < 1e-6 && abs(handedBall.restitution - 0.2) < 1e-6)
        deep.restitution = 0.1
        #expect(abs(ownBall.restitution - 0.9) < 1e-6, "the 3D body that named 0.9 reads \(ownBall.restitution)")
        #expect(abs(handedBall.restitution - 0.1) < 1e-6, "the 3D body that named none reads \(handedBall.restitution)")
        handedBall.restitution = 0.7
        deep.restitution = 0.3
        #expect(abs(handedBall.restitution - 0.7) < 1e-6, "a 3D body given a value afterwards keeps it")
    }

    // MARK: What the world says reaches its bodies

    /// A body resting on the floor rises when gravity is turned upward: a
    /// change to the world reaches a body that has gone to sleep.
    ///
    /// Neither engine wakes a sleeping body when its gravity changes, so the
    /// worlds do it themselves; before that a box settled for half a second
    /// stayed on the floor under gravity pointing the other way.
    @Test func aSleepingBodyWakesWhenGravityChanges() {
        let flat = World()
        flat.gravity = Vector2(0, 980)
        flat.bounds = Rectangle(x: 0, y: 0, width: 1000, height: 1000)
        let box = flat.addBody(.box(width: 40, height: 40), at: Vector2(500, 970))
        run(flat, seconds: 3)
        let rest = box.position.y
        flat.gravity = Vector2(0, -980)
        run(flat, seconds: 1)
        #expect(rest - box.position.y > 100, "the 2D box moved \(rest - box.position.y) px after gravity flipped")

        let deep = World3D()
        deep.ground = 0
        let crate = deep.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 0.5, 0))
        run(deep, seconds: 3)
        #expect(!crate.isAwake, "the 3D box never went to sleep, so the statement was not tested")
        deep.gravity = Vector3(0, 9.8, 0)
        run(deep, seconds: 1)
        #expect(crate.position.y > 2, "the 3D box rose to \(crate.position.y) after gravity flipped")
    }

    /// The world's `restitution` reaches a body already in it when it changes,
    /// not only when the body was added: a ball dropped after the world's
    /// restitution was set to 0 does not bounce off the walls.
    ///
    /// Before the fix the walls and each body read the world's `restitution`
    /// and `drag` once, when they were made, so a value set afterwards changed
    /// nothing already in the world (the ball rose 28 px on walls built at 0.5).
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
        #expect(990 - apex < 2, "the ball rose \(990 - apex) px off walls whose world was set to 0")
    }

    /// An angular velocity a sketch sets is the one it reads back a step later,
    /// in radians a second, with nothing acting on the body.
    ///
    /// Both engines cap a body's spin at a quarter turn a step unless told
    /// not to, 47.1 rad/s at 60 Hz (seven and a half turns a second), and the
    /// 2D cap halved at a 1/30 frame; a fan set to 100 rad/s read 47 with no
    /// note before the worlds lifted it.
    @Test func angularVelocityIsWhatWasSet() {
        let flat = World()
        flat.gravity = .zero
        flat.drag = 0
        let disk = flat.addBody(.circle(radius: 50), at: Vector2(500, 500))
        disk.angularVelocity = 100
        flat.advance(by: 1.0 / 60)
        #expect(abs(disk.angularVelocity / 100 - 1) < 0.01, "the 2D body set to 100 rad/s spins at \(disk.angularVelocity)")
        flat.advance(by: 1.0 / 30)
        #expect(abs(disk.angularVelocity / 100 - 1) < 0.01, "the 2D body spins at \(disk.angularVelocity) after a 1/30 step")
        let deep = World3D()
        deep.gravity = .zero
        deep.drag = 0
        let top = deep.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 5, 0))
        top.angularVelocity = Vector3(0, 100, 0)
        deep.advance(by: 1.0 / 60)
        #expect(abs(top.angularVelocity.y / 100 - 1) < 0.01, "the 3D body set to 100 rad/s spins at \(top.angularVelocity.y)")
    }
}
