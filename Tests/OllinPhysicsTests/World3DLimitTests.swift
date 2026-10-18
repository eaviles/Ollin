import Testing
import Ollin
@testable import OllinPhysics

/// A `World3D` holds the bodies it was made for and no more, and every call
/// that would add one past that says so by throwing `PhysicsError.full`,
/// naming the limit, rather than handing back a body the solver never made.
@Suite
struct World3DLimitTests {

    /// The smallest world is 64 bodies; fill it to the brim with spheres.
    private func filled(ground: Bool) throws -> World3D {
        let world = World3D(maxBodies: 64)
        if ground { world.ground = 0 }
        while !world.isFull {
            _ = try world.addBody(.sphere(radius: 0.2), at: Vector3(0, Double(world.bodies.count), 0))
        }
        return world
    }

    @Test func theWorldTakesExactlyTheBodiesItWasMadeFor() throws {
        let world = try filled(ground: false)
        #expect(world.maxBodies == 64)
        #expect(world.bodies.count == 64)
        #expect(world.solverBodyCount == 64)
        // The ground slab is a body too, so it takes one of the places.
        let floored = try filled(ground: true)
        #expect(floored.bodies.count == 63)
        #expect(floored.solverBodyCount == 64)
    }

    @Test func oneBodyPastTheLimitThrowsFullAndNamesIt() throws {
        let world = try filled(ground: false)
        do {
            _ = try world.addBody(.sphere(radius: 0.2), at: .zero)
            Issue.record("a 65th body was added to a world made for 64")
        } catch PhysicsError.full(let limit) {
            #expect(limit == 64)
            #expect("\(PhysicsError.full(maxBodies: limit))".contains("64"))
        }
        #expect(world.bodies.count == 64, "the refused body is not among the world's")
    }

    @Test func removingABodyFreesItsPlace() throws {
        let world = try filled(ground: false)
        world.remove(world.bodies[3])
        #expect(!world.isFull)
        let again = try world.addBody(.box(width: 0.3, height: 0.3, depth: 0.3), at: Vector3(0, 70, 0))
        #expect(again.position.y == 70)
        #expect(world.isFull)
    }

    @Test func everyCreatorThrowsFullAtTheLimit() throws {
        let world = try filled(ground: false)
        func expectFull(_ what: String, _ body: () throws -> Void) {
            do {
                try body()
                Issue.record("\(what) added something to a full world")
            } catch PhysicsError.full {
            } catch {
                Issue.record("\(what) threw \(error) rather than .full")
            }
        }
        expectFull("addCharacter") { _ = try world.addCharacter(at: Vector3(0, 80, 0)) }
        #expect(world.characters.isEmpty, "a refused character is not kept")
        expectFull("addSoftBody") {
            _ = try world.addSoftBody(from: .plane(width: 1, depth: 1, segments: 2), at: Vector3(0, 80, 0))
        }
        expectFull("addRope") {
            _ = try world.addRope(through: [Vector3(0, 80, 0), Vector3(0, 81, 0)])
        }
        expectFull("addStaticBodies") {
            let scene = Scene(nodes: [SceneNode(mesh: .box(size: 1), position: Vector3(0, 90, 0))])
            _ = try world.addStaticBodies(from: scene)
        }
        #expect(world.bodies.count == 64, "nothing slipped in")
    }

    @Test func aGroundSetOnAFullWorldIsNotedRatherThanMade() throws {
        let world = try filled(ground: false)
        world.ground = 0
        #expect(world.groundBody == nil, "there was no place for the slab")
        #expect(world.solverBodyCount == 64)
        let ball = world.bodies[0]
        for _ in 0 ..< 60 { world.advance(by: 1.0 / 60) }
        #expect(ball.position.y < -1, "with no floor the bodies fall")
    }
}
