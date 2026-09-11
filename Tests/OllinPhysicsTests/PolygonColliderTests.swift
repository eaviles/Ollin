import Foundation
import Ollin
@testable import OllinPhysics
import Testing

/// The polygon collider's corner limit, and what the pieces of a broken shape
/// do once they are bodies. The solver's polygon holds eight corners at most,
/// and handed more it builds nothing at all, so a body made from a nine-corner
/// outline used to have no collider, no mass, and no motion: it hung in the air
/// exactly where it was born. These pin the reduction that prevents that, and
/// the collisions that follow from it.
@Suite
struct PolygonColliderTests {

    /// A convex outline of `count` corners, radius 120, centered on the origin.
    private func ring(_ count: Int) -> [Vector2] {
        (0 ..< count).map { i in
            let a = Double(i) / Double(count) * .tau
            return Vector2(cos(a), sin(a)) * 120
        }
    }

    @Test func aPolygonPastTheCornerLimitStillGetsACollider() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        for corners in [3, 5, 8, 9, 12, 40] {
            let body = world.addBody(.polygon(ring(corners)), at: Vector2(0, 0))
            #expect(body.mass > 0, "a \(corners)-corner outline made a body with no collider")
        }
        let start = world.bodies.map(\.position.y)
        for _ in 0 ..< 60 { world.advance(by: 1.0 / 60) }
        for (i, body) in world.bodies.enumerated() {
            #expect(body.position.y > start[i] + 100, "a body with no collider does not fall")
        }
    }

    @Test func theReductionKeepsTheOutlineItWasGiven() {
        // Eight corners of a forty-corner ring still cover most of the disc, and
        // every corner kept is one that was passed in.
        let outline = ring(40)
        let kept = World.cornersForPolygon(outline)
        #expect(kept.count == 8)
        for corner in kept {
            #expect(outline.contains { $0.distance(to: corner) < 1e-9 })
        }
        let area = { (points: [Vector2]) -> Double in
            var sum = 0.0
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                sum += a.x * b.y - b.x * a.y
            }
            return abs(sum) / 2
        }
        #expect(area(kept) > area(outline) * 0.85)
        // A shape already inside the limit is handed back untouched.
        #expect(World.cornersForPolygon(ring(5)) == ring(5))
    }

    @Test func thePiecesOfABrokenShapeLandOnTheFloor() {
        let world = World()
        world.gravity = Vector2(0, 2000)
        world.restitution = 0.05
        let floorTop = 900.0
        _ = world.addBody(.box(width: 4000, height: 400), at: Vector2(500, floorTop + 200),
                          kind: .static)

        let disc = Shape(ring(120))
        var shards: [Body] = []
        for piece in disc.fractured(into: 9, seed: 5) {
            let middle = piece.centroid
            let local = piece.mapPoints { $0 - middle }
            guard let corners = local.contours.first?.points else { continue }
            shards.append(world.addBody(.polygon(corners), at: Vector2(500, 300) + middle,
                                        density: 1, friction: 0.5))
        }
        #expect(shards.count > 5)
        #expect(shards.allSatisfy { $0.mass > 0 })

        for _ in 0 ..< 360 { world.advance(by: 1.0 / 60) }
        for shard in shards {
            #expect(shard.position.y < floorTop, "a piece fell through the floor")
            #expect(shard.position.y > 600, "a piece never fell at all")
        }
        // Nine pieces cannot all rest at the same height on one floor unless some
        // of them are resting on each other.
        let heights = shards.map(\.position.y)
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 10)
    }
    @Test func theSolidPiecesLandOnTheGroundAndOnEachOther() {
        // The 3D side never had the flat side's corner limit: a hull collider
        // takes as many points as it is handed. This says so out loud.
        let world = World3D()
        world.ground = 0
        var shards: [Body3D] = []
        for piece in Mesh.icosphere(radius: 0.6, subdivisions: 1).fractured(into: 9, seed: 5) {
            let middle = piece.centroid
            let local = piece.mapPositions { $0 - middle }
            #expect(local.positions.count > 8, "the piece is not past the flat side's limit")
            shards.append(world.addBody(.hull(local.positions), at: Vector3(0, 3, 0) + middle,
                                        friction: 0.6, restitution: 0.05))
        }
        #expect(shards.count > 5)
        #expect(shards.allSatisfy { $0.mass > 0 })

        for _ in 0 ..< 420 { world.advance(by: 1.0 / 60) }
        for shard in shards {
            #expect(shard.position.y > 0, "a piece fell through the ground")
            #expect(shard.position.y < 1, "a piece never fell at all")
        }
        let heights = shards.map(\.position.y)
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) > 0.05,
                "nine pieces resting at one height are not resting on each other")
    }
}
