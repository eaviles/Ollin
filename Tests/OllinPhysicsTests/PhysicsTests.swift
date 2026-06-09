import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the Verlet solver: a body falls the way gravity says, springs
/// pull back to their rest length, pinned bodies hold, disks separate, and walls
/// bounce. No GPU and no timing, so these run anywhere including CI.
@Suite
struct PhysicsTests {

    /// Step a world `count` times at a fixed `dt` (so the time-corrected Verlet
    /// ratio stays 1 and the maths is the textbook case).
    func run(_ world: World, steps: Int, dt: Double) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    @Test func freeBodyFallsHalfGTSquared() {
        let world = World()
        world.gravity = Vector2(0, 1000)
        world.drag = 0
        let p = world.addParticle(at: .zero)

        let dt = 1.0 / 600
        run(world, steps: 600, dt: dt)   // one second of fall

        // Verlet from rest sums to g·dt²·n(n+1)/2 → ≈ ½·g·t² for small dt.
        let expected = 0.5 * 1000 * 1.0
        #expect(abs(p.position.y - expected) < expected * 0.02)
        #expect(p.position.x == 0)       // gravity is purely vertical
    }

    @Test func pinnedBodyDoesNotMove() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        let p = world.addParticle(at: Vector2(100, 100))
        p.pin()

        run(world, steps: 120, dt: 1.0 / 60)
        #expect(p.position == Vector2(100, 100))
    }

    @Test func zeroOrNegativeTimestepIsNoOp() {
        let world = World()
        world.gravity = Vector2(0, 1000)
        let p = world.addParticle(at: .zero)

        world.step(dt: 0)
        world.step(dt: -1)
        #expect(p.position == .zero)
    }

    @Test func springRestoresRestLength() {
        let world = World()
        world.gravity = .zero
        let a = world.addParticle(at: Vector2(0, 0))
        a.pin()
        let b = world.addParticle(at: Vector2(100, 0))
        let spring = world.connect(a, b)            // rest length 100
        #expect(spring.length == 100)

        // Yank b out to 180, then let the spring (stiffness 1) pull it back.
        b.place(at: Vector2(180, 0))
        run(world, steps: 240, dt: 1.0 / 60)

        #expect(abs(a.position.distance(to: b.position) - 100) < 0.5)
        #expect(a.position == .zero)                // the pinned end never moves
    }

    @Test func springStrainReadsStretch() {
        let world = World()
        let a = world.addParticle(at: Vector2(0, 0))
        let b = world.addParticle(at: Vector2(100, 0))
        let spring = world.connect(a, b)
        #expect(spring.strain == 0)

        b.place(at: Vector2(150, 0))
        #expect(abs(spring.strain - 0.5) < 1e-9)    // stretched 50%
    }

    @Test func collidingDisksSeparate() {
        let world = World()
        world.gravity = .zero
        world.collisions = true
        let a = world.addParticle(at: Vector2(0, 0), radius: 10)
        let b = world.addParticle(at: Vector2(8, 0), radius: 10)   // overlapping by 12

        run(world, steps: 40, dt: 1.0 / 60)

        // Pushed apart to at least the sum of radii (a hair of slack is fine).
        #expect(a.position.distance(to: b.position) >= 20 - 0.5)
        // Equal masses → symmetric split about the original midpoint x = 4.
        #expect(abs((a.position.x + b.position.x) / 2 - 4) < 1e-6)
    }

    @Test func pointsWithoutRadiusDoNotCollide() {
        let world = World()
        world.gravity = .zero
        world.collisions = true
        let a = world.addParticle(at: Vector2(0, 0))     // radius 0
        let b = world.addParticle(at: Vector2(1, 0))     // radius 0, right on top

        run(world, steps: 10, dt: 1.0 / 60)
        #expect(a.position == .zero && b.position == Vector2(1, 0))
    }

    @Test func wallBounceReversesVelocity() {
        let world = World()
        world.gravity = .zero
        world.bounce = 1.0
        world.bounds = Rectangle(x: 0, y: 0, width: 200, height: 200)
        let p = world.addParticle(at: Vector2(100, 100), radius: 5)
        p.push(Vector2(6, 0))             // heading right, per-step displacement

        // Step until it has crossed the right wall and reflected.
        var bounced = false
        for _ in 0 ..< 200 {
            world.step(dt: 1.0 / 60)
            if p.velocity.x < 0 { bounced = true; break }
        }
        #expect(bounced)
        #expect(p.position.x <= 200 - 5 + 1e-6)   // kept inside the wall
    }

    @Test func dragBleedsSpeed() {
        let world = World()
        world.gravity = .zero
        world.drag = 0.1
        let p = world.addParticle(at: .zero)
        p.push(Vector2(10, 0))

        let firstStepSpeed: Double = {
            world.step(dt: 1.0 / 60)
            return p.velocity.length
        }()
        run(world, steps: 30, dt: 1.0 / 60)
        #expect(p.velocity.length < firstStepSpeed)   // slowing down
    }

    @Test func massWeightsTheSplit() {
        // A heavy disk barely moves when a light one shoves it.
        let world = World()
        world.gravity = .zero
        world.collisions = true
        let heavy = world.addParticle(at: Vector2(0, 0), radius: 10, mass: 100)
        let light = world.addParticle(at: Vector2(8, 0), radius: 10, mass: 1)

        run(world, steps: 30, dt: 1.0 / 60)
        let heavyMoved = abs(heavy.position.x - 0)
        let lightMoved = abs(light.position.x - 8)
        #expect(lightMoved > 2 * heavyMoved)          // the light one takes the shove
        #expect(light.position.x > 11)                // and gets pushed clear
    }
}
