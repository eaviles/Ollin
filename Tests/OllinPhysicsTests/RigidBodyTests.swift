import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the rigid `Body` sub-system (Box2D-backed): a dynamic body
/// falls under gravity, a static floor stops it, and contacts resolve. These run
/// in points and convert through `pixelsPerMeter`, so the asserts are in sketch
/// units. GPU-free, like the Verlet tests beside them. (Box2D's solver isn't the
/// Verlet solver, so these check behaviour qualitatively, not to the last point.)
@Suite
struct RigidBodyTests {

    func run(_ world: World, steps: Int, dt: Double) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    @Test func dynamicBodyFallsUnderGravity() {
        let world = World()
        world.gravity = Vector2(0, 1000)
        let body = world.addBody(.box(width: 40, height: 40), at: Vector2(0, 0))

        run(world, steps: 60, dt: 1.0 / 60)   // ~one second of fall

        // ½·g·t² ≈ 500 points down. Box2D damps a touch and the sub-step start
        // differs from textbook Verlet, so allow a generous band — it clearly fell.
        #expect(body.position.y > 350)
        #expect(abs(body.position.x) < 1)      // gravity is purely vertical
    }

    @Test func staticFloorStopsAFallingBody() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        world.bounce = 0
        world.bounds = Rectangle(x: 0, y: 0, width: 600, height: 600)
        let halfHeight = 20.0
        let body = world.addBody(.box(width: 40, height: 2 * halfHeight),
                                 at: Vector2(300, 100), friction: 0.5)

        run(world, steps: 180, dt: 1.0 / 60)   // let it land and settle

        // It rests on the floor: its centre sits ~halfHeight above the bottom wall.
        #expect(abs(body.position.y - (600 - halfHeight)) < 6)
        // And it came to rest, not still falling fast.
        #expect(body.velocity.length < 30)
    }

    @Test func staticBodyHoldsPosition() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        let body = world.addBody(.box(width: 40, height: 40), at: Vector2(120, 80),
                                 kind: .static)

        run(world, steps: 120, dt: 1.0 / 60)
        #expect(body.position.distance(to: Vector2(120, 80)) < 0.5)
    }

    @Test func polygonAndCapsuleBodiesFallAndHaveMass() {
        let world = World()
        world.gravity = Vector2(0, 1000)
        let triangle = world.addBody(.polygon([Vector2(-22, 18), Vector2(22, 18), Vector2(0, -26)]),
                                     at: Vector2(0, 0))
        let capsule = world.addBody(.capsule(from: Vector2(-30, 0), to: Vector2(30, 0), radius: 14),
                                    at: Vector2(300, 0))

        #expect(triangle.mass > 0)   // the hull gave it real area/mass
        #expect(capsule.mass > 0)

        run(world, steps: 30, dt: 1.0 / 60)
        #expect(triangle.position.y > 50)   // both fell under gravity
        #expect(capsule.position.y > 50)
    }

    @Test func aBodyComingToRestOnAnotherStacks() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        world.bounce = 0
        world.bounds = Rectangle(x: 0, y: 0, width: 600, height: 600)
        let half = 25.0
        // A floor-resting box and one dropped right above it.
        let lower = world.addBody(.box(width: 2 * half, height: 2 * half),
                                  at: Vector2(300, 600 - half), friction: 0.6)
        let upper = world.addBody(.box(width: 2 * half, height: 2 * half),
                                  at: Vector2(300, 600 - 3 * half - 40), friction: 0.6)

        run(world, steps: 240, dt: 1.0 / 60)

        // The upper box settles roughly a box-height above the lower one.
        let gap = lower.position.y - upper.position.y
        #expect(abs(gap - 2 * half) < 10)
        #expect(upper.velocity.length < 30)   // the stack is at rest
    }
}
