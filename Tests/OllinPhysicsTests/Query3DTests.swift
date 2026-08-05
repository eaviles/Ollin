import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the world queries: what a ray, a swept shape, and an overlap
/// find, where they say it is, and what each one is deliberately blind to.
/// Behavioral (the no-pixel-snapshot policy for physics), each answer pinned
/// against a counterfactual twin: the same scene asked twice with one thing
/// changed, so a passing test can't be explained by the geometry alone.
/// Parallel-safe like the rest of the 3D suite.
struct Query3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// A world with a unit box parked in the air at each of the given heights,
    /// so a ray dropped down the y axis meets them in order.
    func tower(_ heights: [Double]) -> (World3D, [Body3D]) {
        let world = World3D()
        let boxes = heights.map {
            world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, $0, 0),
                          kind: .static)
        }
        return (world, boxes)
    }

    // MARK: Rays

    /// The headline: a ray reports what it reaches first, and it is the geometry
    /// that decides, not the order things were added.
    @Test func aRayReportsTheNearestBody() throws {
        let (world, boxes) = tower([3, 1])          // far one added first
        let hit = try #require(world.raycast(from: Vector3(0, 8, 0),
                                             to: Vector3(0, -8, 0)))
        #expect(hit.body === boxes[0], "the box at y = 3 is the one in the way")
    }

    /// The same ray with the near body gone reaches the far one: what stopped it
    /// was that body, not the ray's own reach.
    @Test func withTheNearBodyGoneTheRayReachesTheFarOne() throws {
        let (world, boxes) = tower([3, 1])
        world.remove(boxes[0])
        let hit = try #require(world.raycast(from: Vector3(0, 8, 0),
                                             to: Vector3(0, -8, 0)))
        #expect(hit.body === boxes[1])
    }

    /// Line of sight, the question this whole surface exists for: the target is
    /// what the ray finds only when nothing stands between.
    @Test func aWallIsWhatBreaksTheLineOfSight() {
        func canSee(throughAWall: Bool) -> Bool {
            let world = World3D()
            let target = world.addBody(.sphere(radius: 0.5), at: Vector3(0, 1, 6),
                                       kind: .static)
            if throughAWall {
                world.addBody(.box(width: 6, height: 6, depth: 0.4),
                              at: Vector3(0, 1, 3), kind: .static)
            }
            return world.raycast(from: Vector3(0, 1, 0),
                                 to: target.position)?.body === target
        }
        #expect(canSee(throughAWall: false))
        #expect(!canSee(throughAWall: true))
    }

    /// The hit says where and which way, not just what: a ray dropped onto a
    /// box's top face lands on the face, pointing up, at the distance it fell.
    @Test func theHitCarriesWhereItLandedAndWhichWayTheSurfaceFaces() throws {
        let (world, _) = tower([1])                  // top face at y = 1.5
        let hit = try #require(world.raycast(from: Vector3(0, 5, 0),
                                             to: Vector3(0, -5, 0)))
        #expect(abs(hit.point.y - 1.5) < 1e-3, "landed at \(hit.point)")
        #expect(abs(hit.normal.y - 1) < 1e-3, "normal was \(hit.normal)")
        #expect(abs(hit.distance - 3.5) < 1e-3, "distance was \(hit.distance)")
    }

    /// A ray is a segment, not a line: it stops where it was told to.
    @Test func aRayReachesOnlyAsFarAsItsEnd() {
        let (world, _) = tower([1])
        #expect(world.raycast(from: Vector3(0, 5, 0), to: Vector3(0, 3, 0)) == nil)
        #expect(world.raycast(from: Vector3(0, 5, 0), to: Vector3(0, 1, 0)) != nil)
    }

    /// Everything along the way, nearest first.
    @Test func everyHitComesBackNearestFirst() {
        let (world, boxes) = tower([5, 3, 1])
        let hits = world.raycastAll(from: Vector3(0, 9, 0), to: Vector3(0, -9, 0))
        #expect(hits.count == 3, "found \(hits.count)")
        #expect(hits.map(\.body) === boxes)
        #expect(hits.map(\.distance) == hits.map(\.distance).sorted())
    }

    /// The ignore list is what lets a body cast from inside itself.
    @Test func anIgnoredBodyIsLookedStraightThrough() throws {
        let (world, boxes) = tower([3, 1])
        let plain = try #require(world.raycast(from: Vector3(0, 8, 0),
                                               to: Vector3(0, -8, 0)))
        #expect(plain.body === boxes[0])
        let skipping = try #require(world.raycast(from: Vector3(0, 8, 0),
                                                  to: Vector3(0, -8, 0),
                                                  ignoring: [boxes[0]]))
        #expect(skipping.body === boxes[1])
    }

    /// A sensor is a region to be inside rather than a surface to hit, so a ray
    /// passes through one unless it is asked for.
    @Test func sensorsAreTransparentUntilTheyAreAskedFor() throws {
        let world = World3D()
        let field = world.addBody(.box(width: 4, height: 4, depth: 4),
                                  at: Vector3(0, 4, 0), isSensor: true)
        let floor = world.addBody(.box(width: 4, height: 1, depth: 4),
                                  at: Vector3(0, 0, 0), kind: .static)
        let solid = try #require(world.raycast(from: Vector3(0, 9, 0),
                                               to: Vector3(0, -9, 0)))
        #expect(solid.body === floor)
        let everything = try #require(world.raycast(from: Vector3(0, 9, 0),
                                                    to: Vector3(0, -9, 0),
                                                    includingSensors: true))
        #expect(everything.body === field)
    }

    /// The floor is a body like any other as far as a query is concerned, which
    /// is what makes "how far down is the ground" answerable at all.
    @Test func theGroundSlabIsHittable() throws {
        let world = World3D()
        world.ground = 0
        let hit = try #require(world.raycast(from: Vector3(2, 6, -3),
                                             to: Vector3(2, -1, -3)))
        #expect(hit.body === world.groundBody)
        #expect(abs(hit.distance - 6) < 1e-3, "distance was \(hit.distance)")
    }

    /// A walking character is not in `world.bodies`, but its stand-in is a real
    /// body, so it can be seen.
    @Test func aCharacterCanBeSeen() throws {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 0, 4))
        run(world, steps: 30)
        let hit = try #require(world.raycast(from: Vector3(0, 1, 0),
                                             to: Vector3(0, 1, 8)))
        #expect(hit.body === walker.body)
    }

    // MARK: Sweeps

    /// A swept shape stops a radius short of where a ray reaches, because it is
    /// the shape's surface that touches rather than a point.
    @Test func aSweptSphereStopsARadiusShortOfTheRay() throws {
        let (world, _) = tower([1])                  // top face at y = 1.5
        let ray = try #require(world.raycast(from: Vector3(0, 5, 0),
                                             to: Vector3(0, -5, 0)))
        let swept = try #require(world.sweep(.sphere(radius: 0.5),
                                             from: Vector3(0, 5, 0),
                                             to: Vector3(0, -5, 0)))
        #expect(abs((ray.distance - swept.distance) - 0.5) < 1e-2,
                "ray \(ray.distance) vs swept \(swept.distance)")
        #expect(abs(swept.point.y - 1.5) < 1e-2, "touched at \(swept.point)")
        #expect(abs(swept.normal.y - 1) < 1e-2, "normal was \(swept.normal)")
    }

    /// The reason a sweep exists: a ray answers what is in the way, a sweep
    /// answers whether something *fits*. The same line through the same gap is
    /// clear for one and blocked for the other.
    @Test func aSweepIsStoppedByAGapARayPassesThrough() {
        func slot() -> World3D {
            let world = World3D()
            // Two slabs with a 0.5-wide gap between their inner faces.
            for side in [-1.0, 1.0] {
                world.addBody(.box(width: 1, height: 4, depth: 4),
                              at: Vector3(side * 0.75, 0, 0), kind: .static)
            }
            return world
        }
        let through = slot().raycast(from: Vector3(0, 0, -4), to: Vector3(0, 0, 4))
        #expect(through == nil, "a ray down the middle of the gap is clear")

        let squeezed = slot().sweep(.sphere(radius: 0.1), from: Vector3(0, 0, -4),
                                    to: Vector3(0, 0, 4))
        #expect(squeezed == nil, "a shape narrower than the gap fits too")

        let stuck = slot().sweep(.sphere(radius: 0.4), from: Vector3(0, 0, -4),
                                 to: Vector3(0, 0, 4))
        #expect(stuck != nil, "a shape wider than the gap does not")
    }

    /// A sweep that sets off already touching reports no travel at all.
    @Test func aSweepThatStartsTouchingTravelsNothing() throws {
        let (world, _) = tower([1])
        let hit = try #require(world.sweep(.sphere(radius: 0.5), from: Vector3(0, 1, 0),
                                           to: Vector3(0, -5, 0)))
        #expect(hit.distance < 1e-3, "distance was \(hit.distance)")
    }

    /// Turning the probe changes what fits, the way a sheet of plywood goes
    /// through a doorway edge-on and not flat.
    @Test func aRotatedProbeFitsWhereAnUprightOneDoesNot() {
        func blocked(rotated angle: Double) -> Bool {
            let world = World3D()
            for side in [-1.0, 1.0] {
                world.addBody(.box(width: 1, height: 4, depth: 4),
                              at: Vector3(side * 0.9, 0, 0), kind: .static)
            }
            // A blade 1.4 wide and 0.3 thick against a 0.8-wide gap.
            return world.sweep(.box(width: 1.4, height: 1, depth: 0.3),
                               from: Vector3(0, 0, -4), to: Vector3(0, 0, 4),
                               rotated: angle, axis: .unitY) != nil
        }
        #expect(blocked(rotated: 0), "flat on, the blade is wider than the gap")
        #expect(!blocked(rotated: .pi / 2), "turned edge-on it slides through")
    }

    /// Everything a sweep brushes past, nearest first.
    @Test func aSweepCanReportEverythingItTouches() {
        let (world, boxes) = tower([5, 3, 1])
        let hits = world.sweepAll(.sphere(radius: 0.2), from: Vector3(0, 9, 0),
                                  to: Vector3(0, -9, 0))
        #expect(hits.map(\.body) === boxes, "found \(hits.count)")
    }

    /// Scenery is not a probe: a mesh collider describes a landscape, and the
    /// narrow phase cannot sweep one, so the query says so rather than guessing.
    @Test func sceneryColliderscannotBeUsedAsProbes() {
        let (world, _) = tower([1])
        let mesh = Mesh.box(size: 1)
        #expect(world.sweep(.mesh(mesh), from: Vector3(0, 5, 0),
                            to: Vector3(0, -5, 0)) == nil)
        #expect(world.bodiesOverlapping(.mesh(mesh), at: Vector3(0, 1, 0)).isEmpty)
        // The same probe as a hull, which the narrow phase can carry, finds it.
        let corners = [Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
                       Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
                       Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
                       Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5)]
        #expect(!world.bodiesOverlapping(.hull(corners), at: Vector3(0, 1, 0)).isEmpty)
    }

    // MARK: Overlaps

    /// What is inside a region, with no body built to hold it, and the region's
    /// own size deciding.
    @Test func anOverlapFindsWhatIsInsideItAndNothingElse() {
        let world = World3D()
        let near = world.addBody(.sphere(radius: 0.3), at: Vector3(1, 0, 0),
                                 kind: .static)
        let far = world.addBody(.sphere(radius: 0.3), at: Vector3(4, 0, 0),
                                kind: .static)
        let small = world.bodiesOverlapping(.sphere(radius: 2), at: .zero)
        #expect(small.count == 1 && small[0] === near, "found \(small.count)")
        let wide = world.bodiesOverlapping(.sphere(radius: 5), at: .zero)
        #expect(wide.count == 2 && wide.contains { $0 === far })
    }

    /// One entry per body, however many of its parts are inside: a compound of
    /// twenty beads is one answer, not twenty.
    @Test func aBodyIsReportedOnceHoweverManyPartsAreInside() {
        let world = World3D()
        var beads: [Collider3D.Part] = []
        for index in 0 ..< 20 {
            let angle = Double(index) / 20 * .tau
            beads.append(.part(.sphere(radius: 0.2),
                               at: Vector3(cos(angle), 0, sin(angle))))
        }
        world.addBody(.compound(beads), at: .zero, kind: .static)
        #expect(world.bodiesOverlapping(.sphere(radius: 3), at: .zero).count == 1)
    }

    /// The same sensor rule as a ray: a detector volume is reported only when
    /// the query asks for one.
    @Test func anOverlapSeesSensorsOnlyWhenAsked() {
        let world = World3D()
        world.addBody(.box(width: 2, height: 2, depth: 2), at: .zero, isSensor: true)
        #expect(world.bodiesOverlapping(.sphere(radius: 1), at: .zero).isEmpty)
        #expect(world.bodiesOverlapping(.sphere(radius: 1), at: .zero,
                                        includingSensors: true).count == 1)
    }

    /// The exact form of the question: a point is inside a body or it is not.
    @Test func aPointIsInsideOnlyWhatContainsIt() {
        let world = World3D()
        let box = world.addBody(.box(width: 2, height: 2, depth: 2),
                                at: Vector3(0, 1, 0), kind: .static)
        let inside = world.bodiesContaining(Vector3(0.5, 1.5, 0.5))
        #expect(inside.count == 1 && inside[0] === box)
        #expect(world.bodiesContaining(Vector3(0, 3, 0)).isEmpty)
    }

    // MARK: What a query is blind to

    /// A soft body is part of the world a query asks about: a curtain stops a
    /// sightline the way a wall does, and the hit names the cloth. Twins: the
    /// same sheet as a rigid slab stops the ray at the same height, and
    /// `ignoring:` is what looks through one.
    @Test func aClothStopsARayTheWayASlabDoes() throws {
        /// How high the ray stopped: at the sheet hanging at y = 3, or at the
        /// floor below it.
        func stoppedAt(cloth: Bool, ignoringIt: Bool = false) throws -> Double {
            let world = World3D()
            world.addBody(.box(width: 6, height: 1, depth: 6), at: .zero,
                          kind: .static)
            var sheet: SoftBody3D?
            if cloth {
                sheet = world.addSoftBody(from: Mesh.plane(width: 4, depth: 4, segments: 8),
                                          at: Vector3(0, 3, 0))
            } else {
                world.addBody(.box(width: 4, height: 0.1, depth: 4),
                              at: Vector3(0, 3, 0), kind: .static)
            }
            let hit = try #require(world.raycast(from: Vector3(0, 6, 0),
                                                 to: Vector3(0, -2, 0),
                                                 ignoring: ignoringIt
                                                     ? [sheet].compactMap { $0 } : []))
            if cloth && !ignoringIt { #expect(hit.body === sheet) }
            return hit.point.y
        }
        #expect(try abs(stoppedAt(cloth: false) - 3.05) < 0.1,
                "a rigid sheet at that height stops the ray")
        #expect(try abs(stoppedAt(cloth: true) - 3) < 0.1,
                "and so does a cloth")
        #expect(try abs(stoppedAt(cloth: true, ignoringIt: true) - 0.5) < 0.1,
                "unless the ray is told to look through it")
    }

    // MARK: Scale and repeatability

    /// Distances come back in the world's own units, whatever the solver
    /// measured them in.
    @Test func distancesAreInWorldUnits() throws {
        let world = World3D()
        world.unitsPerMeter = 100
        world.addBody(.box(width: 100, height: 100, depth: 100),
                      at: Vector3(0, 0, 0), kind: .static)
        let hit = try #require(world.raycast(from: Vector3(0, 500, 0),
                                             to: Vector3(0, -500, 0)))
        #expect(abs(hit.distance - 450) < 1, "distance was \(hit.distance)")
        #expect(abs(hit.point.y - 50) < 1, "point was \(hit.point)")
    }

    /// A query is a question, not a step: asking twice answers the same, and
    /// asking at all leaves the world where it was.
    @Test func askingChangesNothingAndAnswersTheSame() {
        let world = World3D()
        world.ground = 0
        let box = world.addBody(.box(width: 1, height: 1, depth: 1),
                                at: Vector3(0, 3, 0))
        run(world, steps: 60)
        let before = box.position
        let first = world.raycast(from: Vector3(0, 8, 0), to: Vector3(0, -8, 0))
        let second = world.raycast(from: Vector3(0, 8, 0), to: Vector3(0, -8, 0))
        #expect(first?.body === second?.body)
        #expect(first?.distance == second?.distance)
        #expect(box.position == before)
    }

    /// Two identical worlds answer identically, the determinism the whole 3D
    /// tier is pinned by.
    @Test func identicalWorldsAnswerIdentically() {
        func probe() -> [Double] {
            let world = World3D()
            world.ground = 0
            for index in 0 ..< 6 {
                world.addBody(.box(width: 1, height: 1, depth: 1),
                              at: Vector3(Double(index) * 0.15, 2 + Double(index), 0))
            }
            for _ in 0 ..< 120 { world.step(dt: 1.0 / 60) }
            return world.raycastAll(from: Vector3(0, 12, 0), to: Vector3(0, -1, 0))
                .flatMap { [$0.distance, $0.point.x, $0.normal.y] }
        }
        #expect(probe() == probe())
    }
}

/// Identity comparison for a list of whatever a world holds, so a hit order
/// reads as one line.
private func === (lhs: [any Colliding3D], rhs: [any Colliding3D]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
}
