import Foundation
import Testing
import Ollin
import CBox2D
@testable import OllinPhysics

/// Correctness for the rigid `Body` sub-system (Box2D-backed): a dynamic body
/// falls under gravity, a static floor stops it, contacts resolve, and joints
/// hold. These run in points and convert through `pixelsPerMeter`, so the asserts
/// are in sketch units. GPU-free, like the Verlet tests beside them. (Box2D's
/// solver isn't the Verlet solver, so these check behavior qualitatively, not to
/// the last point.)
///
/// `.serialized` is load-bearing: Box2D keeps its worlds in a global pool and is
/// not thread-safe, so two `b2CreateWorld` calls racing across parallel tests
/// corrupt it (a SIGILL). Every Box2D-touching test belongs in this one suite so
/// they never run concurrently. (The Verlet `PhysicsTests` suite never creates a
/// rigid world — `addBody` is lazy — so it stays safely parallel.)
@Suite(.serialized)
struct RigidBodyTests {

    func run(_ world: World, steps: Int, dt: Double) {
        for _ in 0 ..< steps { world.advance(by: dt) }
    }

    /// Low-level certification that the vendored Box2D builds, links, and steps
    /// from Swift through the raw `b2*` C API (the typed `Body` path is built on
    /// this and exercised by the tests below).
    @Test func rawBox2DStepsAndReadsBack() {
        var worldDef = b2DefaultWorldDef()
        worldDef.gravity = b2Vec2(x: 0, y: -10)
        let worldId = b2CreateWorld(&worldDef)
        defer { b2DestroyWorld(worldId) }

        var bodyDef = b2DefaultBodyDef()
        bodyDef.type = b2_dynamicBody
        let bodyId = b2CreateBody(worldId, &bodyDef)
        var circle = b2Circle(center: b2Vec2(x: 0, y: 0), radius: 0.5)
        var shapeDef = b2DefaultShapeDef()
        shapeDef.density = 1
        _ = b2CreateCircleShape(bodyId, &shapeDef, &circle)

        for _ in 0 ..< 60 { b2World_Step(worldId, 1.0 / 60, 4) }
        #expect(b2Body_GetPosition(bodyId).y < -4)   // ½·10·1² ≈ 5 m of fall
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
        world.restitution = 0
        world.bounds = Rectangle(x: 0, y: 0, width: 600, height: 600)
        let halfHeight = 20.0
        let body = world.addBody(.box(width: 40, height: 2 * halfHeight),
                                 at: Vector2(300, 100), friction: 0.5)

        run(world, steps: 180, dt: 1.0 / 60)   // let it land and settle

        // It rests on the floor: its center sits ~halfHeight above the bottom wall.
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

    @Test func revoluteJointHoldsBodiesAtThePivot() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        // A static anchor and a bar hinged to it at the anchor point; the bar
        // should swing down but stay pinned at the pivot.
        let anchor = world.addBody(.box(width: 20, height: 20), at: Vector2(300, 100),
                                   kind: .static)
        let bar = world.addBody(.box(width: 200, height: 24), at: Vector2(400, 100))
        let pivot = Vector2(300, 100)
        world.connect(anchor, bar, .revolute(at: pivot))

        // Released horizontal, the bar swings down about the pivot. It's lightly
        // damped, so it oscillates rather than settling — track the deepest swing.
        var maxY = bar.position.y
        for _ in 0 ..< 180 {
            world.advance(by: 1.0 / 60)
            maxY = Swift.max(maxY, bar.position.y)
        }

        // The hinge holds: the bar's near end stays at the pivot throughout…
        let nearEnd = bar.position + Vector2(angle: bar.angle + .pi, length: 100)
        #expect(nearEnd.distance(to: pivot) < 12)
        // …and gravity swung its center well below the pivot (toward hanging down).
        #expect(maxY > 180)
    }

    @Test func distanceJointHoldsLength() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        let anchor = world.addBody(.circle(radius: 10), at: Vector2(300, 100), kind: .static)
        let bob = world.addBody(.circle(radius: 20), at: Vector2(300, 250))
        world.connect(anchor, bob, .distance(from: Vector2(300, 100), to: Vector2(300, 250)))

        run(world, steps: 180, dt: 1.0 / 60)

        // The rigid rod keeps the bob ~150 points from the anchor as it hangs.
        #expect(abs(bob.position.distance(to: anchor.position) - 150) < 12)
    }

    @Test func grabPullsABodyToTheTarget() {
        let world = World()
        world.gravity = .zero
        let body = world.addBody(.circle(radius: 20), at: Vector2(100, 100))
        let joint = world.grab(body, at: Vector2(100, 100))
        joint.target = Vector2(400, 300)

        run(world, steps: 120, dt: 1.0 / 60)
        #expect(body.position.distance(to: Vector2(400, 300)) < 20)
    }

    @Test func aBodyComingToRestOnAnotherStacks() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        world.restitution = 0
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
