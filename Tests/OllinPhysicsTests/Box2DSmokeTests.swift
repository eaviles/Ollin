import Foundation
import Testing
import CBox2D

/// Phase-1 smoke test for the vendored Box2D engine: prove the C library
/// compiles, links, and runs a real simulation step from Swift through the raw
/// `b2*` C API. The typed `World`/`Body` wrapper is built on top of this and
/// tested separately; this only certifies that the vendored substrate is sound.
@Suite
struct Box2DSmokeTests {

    /// A dynamic body released under gravity falls roughly ½·g·t². In Box2D's own
    /// units (meters, y-up) gravity points along −y, so after a second of stepping
    /// the body's y has dropped well past a loose floor (½·10·1² ≈ 5 m).
    @Test func dynamicBodyFallsUnderGravity() {
        var worldDef = b2DefaultWorldDef()
        worldDef.gravity = b2Vec2(x: 0, y: -10)
        let worldId = b2CreateWorld(&worldDef)
        defer { b2DestroyWorld(worldId) }

        var bodyDef = b2DefaultBodyDef()
        bodyDef.type = b2_dynamicBody
        bodyDef.position = b2Vec2(x: 0, y: 0)
        let bodyId = b2CreateBody(worldId, &bodyDef)

        var circle = b2Circle(center: b2Vec2(x: 0, y: 0), radius: 0.5)
        var shapeDef = b2DefaultShapeDef()
        shapeDef.density = 1
        _ = b2CreateCircleShape(bodyId, &shapeDef, &circle)

        let timeStep: Float = 1.0 / 60
        let subStepCount: Int32 = 4
        for _ in 0 ..< 60 { b2World_Step(worldId, timeStep, subStepCount) }

        let pos = b2Body_GetPosition(bodyId)
        #expect(pos.y < -4)
    }
}
