import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for collision groups: what a rule filters, and everywhere it has
/// to reach. The group rides in the object layer, which the solver consults in
/// several places at once, so most of these tests exist to catch a pair that
/// would be filtered in one of them and not another: the contact listener, a
/// query, a sensor, a character's own sweep, a wheel feeling for the road.
/// Behavioral (the no-pixel-snapshot policy for physics), each answer pinned
/// against a counterfactual twin: the same scene run twice with one rule
/// changed, so nothing here can pass because of the geometry alone.
struct CollisionFilter3DTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// A world with a static slab at y = 1 and a crate dropped onto it from
    /// above. `filtered` puts the crate in a group the slab is told to ignore,
    /// which is the only difference between the two runs.
    func dropOntoSlab(filtered: Bool) -> Double {
        let world = World3D()
        world.ground = -4
        world.addBody(.box(width: 4, height: 0.4, depth: 4), at: Vector3(0, 1, 0),
                      kind: .static, group: "shelf")
        let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(0, 3, 0), group: "cargo")
        if filtered { world.ignoreCollisions(between: "cargo", and: "shelf") }
        run(world, steps: 150)
        return crate.position.y
    }

    // MARK: The rule itself

    /// The headline, and the whole point of the tier: one call is the
    /// difference between landing on a shelf and falling straight through it.
    @Test func aRuleIsWhatDecidesWhetherTwoThingsTouch() {
        let stopped = dropOntoSlab(filtered: false)
        let through = dropOntoSlab(filtered: true)
        #expect(stopped > 1, "it rests on top of the slab at y = 1")
        #expect(through < 0, "it went past the slab entirely")
    }

    /// The rule is one fact about a pair, not a direction: saying it the other
    /// way round says the same thing.
    @Test func aRuleReadsBothWays() {
        let world = World3D()
        world.ignoreCollisions(between: "b", and: "a")
        #expect(!world.collides("a", with: "b"))
        #expect(!world.collides("b", with: "a"))
        world.allowCollisions(between: "a", and: "b")
        #expect(world.collides("b", with: "a"))
    }

    /// Everything collides until something says otherwise, the diagonal
    /// included: two bodies in one group are still two ordinary bodies.
    @Test func agroupCollidesWithItselfUntilToldNotTo() {
        func topOfPile(ignoringItself: Bool) -> Double {
            let world = World3D()
            world.ground = 0
            if ignoringItself { world.ignoreCollisions(between: "beads", and: "beads") }
            var last: Body3D!
            for index in 0 ..< 4 {
                last = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                     at: Vector3(0, 0.3 + Double(index) * 0.5, 0),
                                     group: "beads")
            }
            run(world, steps: 200)
            return last.position.y
        }
        #expect(topOfPile(ignoringItself: false) > 1, "four boxes make a stack")
        #expect(topOfPile(ignoringItself: true) < 0.4,
                "they fall through each other into one layer on the floor")
    }

    /// A world nobody has said anything to behaves as one with no groups at
    /// all: naming a group is not itself a rule.
    @Test func namingAGroupIsNotARule() {
        let world = World3D()
        world.ground = 0
        let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(0, 2, 0), group: "cargo")
        run(world, steps: 150)
        #expect(crate.position.y > 0.2, "it landed on the floor like anything else")
        #expect(world.collides("cargo", with: .default))
    }

    /// The groups a world knows, in the order named. This is what makes a typo
    /// findable: a misspelled name is a new group and shows up here.
    @Test func theWorldListsTheGroupsItHasBeenTold() {
        let world = World3D()
        world.addBody(.sphere(radius: 0.2), at: .zero, group: "sparks")
        world.ignoreCollisions(between: "sparks", and: "playr")   // the typo
        #expect(world.collisionGroups == [.default, "sparks", "playr"])
        #expect(world.collides("sparks", with: "player"), "the rule missed it")
    }

    // MARK: Everywhere it has to reach

    /// A filtered pair never reaches the contact listener either: the solver
    /// stops looking before there is anything to report, so a sketch polling
    /// `contacts` sees the same answer the simulation does.
    @Test func aFilteredTouchIsNeverReported() {
        func landings(filtered: Bool) -> Int {
            let world = World3D()
            world.ground = -4
            let slab = world.addBody(.box(width: 4, height: 0.4, depth: 4),
                                     at: Vector3(0, 1, 0), kind: .static,
                                     group: "shelf")
            let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                      at: Vector3(0, 3, 0), group: "cargo")
            if filtered { world.ignoreCollisions(between: "cargo", and: "shelf") }
            var began = 0
            for _ in 0 ..< 150 {
                world.step(dt: 1.0 / 60)
                began += world.contacts.filter {
                    $0.phase == .began && $0.involves(slab) && $0.involves(crate)
                }.count
            }
            return began
        }
        #expect(landings(filtered: false) > 0)
        #expect(landings(filtered: true) == 0)
    }

    /// A sensor is filtered like anything else, which is what makes a detector
    /// that only notices one kind of thing: the trigger is in a group, and
    /// whatever it ignores walks through unannounced.
    @Test func aSensorOnlySeesWhatItsGroupCollidesWith() {
        func sawIt(filtered: Bool) -> Bool {
            let world = World3D()
            world.ground = -6
            let gate = world.addBody(.box(width: 3, height: 1, depth: 3),
                                     at: Vector3(0, 1, 0), isSensor: true,
                                     group: "gate")
            world.addBody(.sphere(radius: 0.3), at: Vector3(0, 4, 0), group: "cargo")
            if filtered { world.ignoreCollisions(between: "cargo", and: "gate") }
            var seen = false
            for _ in 0 ..< 200 {
                world.step(dt: 1.0 / 60)
                if !gate.touching.isEmpty { seen = true }
            }
            return seen
        }
        #expect(sawIt(filtered: false))
        #expect(!sawIt(filtered: true))
    }

    /// A query can ask as a group, and then it looks through exactly what that
    /// group looks through. The same ray asked plainly still finds everything,
    /// so a query that names no group sees the whole world.
    @Test func aQueryCanAskAsAGroup() throws {
        let world = World3D()
        let pane = world.addBody(.box(width: 4, height: 4, depth: 0.2),
                                 at: Vector3(0, 0, 2), kind: .static, group: "glass")
        let wall = world.addBody(.box(width: 4, height: 4, depth: 0.2),
                                 at: Vector3(0, 0, 5), kind: .static)
        world.ignoreCollisions(between: "bullets", and: "glass")

        let plain = try #require(world.raycast(from: .zero, to: Vector3(0, 0, 9)))
        #expect(plain.body === pane, "an ordinary ray still stops at the pane")

        let asBullet = try #require(world.raycast(from: .zero, to: Vector3(0, 0, 9),
                                                  as: "bullets"))
        #expect(asBullet.body === wall, "a bullet's ray goes through the glass")
    }

    /// The same narrowing on the other two query shapes, so a sketch does not
    /// have to learn which of them honors a group.
    @Test func sweepsAndOverlapsNarrowTheSameWay() {
        let world = World3D()
        world.addBody(.box(width: 4, height: 4, depth: 0.2), at: Vector3(0, 0, 2),
                      kind: .static, group: "glass")
        world.ignoreCollisions(between: "bullets", and: "glass")

        #expect(world.sweep(.sphere(radius: 0.3), from: .zero,
                            to: Vector3(0, 0, 4)) != nil)
        #expect(world.sweep(.sphere(radius: 0.3), from: .zero, to: Vector3(0, 0, 4),
                            as: "bullets") == nil)
        #expect(world.bodiesContaining(Vector3(0, 0, 2)).count == 1)
        #expect(world.bodiesContaining(Vector3(0, 0, 2), as: "bullets").isEmpty)
    }

    // MARK: Changing it while it runs

    /// A body can be moved between groups mid-simulation: the same crate, the
    /// same shelf, and the moment the rule applies to it, it drops through.
    @Test func aBodyCanChangeGroupWhileItRuns() {
        let world = World3D()
        world.ground = -4
        world.addBody(.box(width: 4, height: 0.4, depth: 4), at: Vector3(0, 1, 0),
                      kind: .static, group: "shelf")
        let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(0, 3, 0))
        world.ignoreCollisions(between: "cargo", and: "shelf")
        run(world, steps: 150)
        let resting = crate.position.y
        #expect(resting > 1, "it is on the shelf while it is in no group")

        crate.group = "cargo"
        #expect(crate.group == "cargo")
        run(world, steps: 150)
        #expect(crate.position.y < resting - 1, "the shelf stopped holding it")
    }

    /// The layer carries the kind and the group together, so changing one has
    /// to leave the other alone: a body let go from static keeps its group.
    @Test func agroupSurvivesAMotionChange() {
        let world = World3D()
        world.ground = -4
        world.addBody(.box(width: 4, height: 0.4, depth: 4), at: Vector3(0, 1, 0),
                      kind: .static, group: "shelf")
        let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(0, 3, 0), kind: .static, group: "cargo")
        world.ignoreCollisions(between: "cargo", and: "shelf")

        crate.kind = .dynamic
        #expect(crate.group == "cargo", "the group came through the switch")
        run(world, steps: 150)
        #expect(crate.position.y < 0, "and it still falls through the shelf")
    }

    /// A rule written while things are already settled on each other still
    /// takes effect: bodies asleep on a contact are woken so the solver looks
    /// at the pair again.
    @Test func aRuleWrittenAfterTheyHaveSettledStillApplies() {
        let world = World3D()
        world.ground = -4
        world.addBody(.box(width: 4, height: 0.4, depth: 4), at: Vector3(0, 1, 0),
                      kind: .static, group: "shelf")
        let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(0, 3, 0), group: "cargo")
        run(world, steps: 400)                       // long enough to fall asleep
        #expect(!crate.isAwake, "it has settled")

        world.ignoreCollisions(between: "cargo", and: "shelf")
        run(world, steps: 150)
        #expect(crate.position.y < 0, "the shelf let go of it")
    }

    // MARK: Characters

    /// A character's own sweep is filtered too, which is what makes a figure
    /// that walks through a wall rather than one that stands still in front of
    /// a wall it cannot see.
    @Test func aCharacterWalksThroughWhatItsGroupIgnores() {
        func walkedTo(filtered: Bool) -> Double {
            let world = World3D()
            world.ground = 0
            world.addBody(.box(width: 6, height: 3, depth: 0.4), at: Vector3(0, 1.5, 2),
                          kind: .static, group: "walls")
            let walker = world.addCharacter(radius: 0.3, height: 1.8,
                                            at: Vector3(0, 0, 0), group: "phantoms")
            if filtered { world.ignoreCollisions(between: "phantoms", and: "walls") }
            walker.move(Vector3(0, 0, 3))
            run(world, steps: 120)
            return walker.position.z
        }
        #expect(walkedTo(filtered: false) < 1.8, "the wall stopped it short")
        #expect(walkedTo(filtered: true) > 3, "it walked straight through")
    }

    /// Characters meet each other outside the broad phase, through the world's
    /// own list rather than through their layers, so the rule has to be applied
    /// there by hand. Without that, two figures told to ignore each other would
    /// still bump.
    @Test func twoCharactersCanBeToldToIgnoreEachOther() {
        /// The closest the two ever came, which is the measure that reads the
        /// same whether they stopped nose to nose or passed clean through and
        /// carried on (both leave them far apart at the end).
        func closestApproach(filtered: Bool) -> Double {
            let world = World3D()
            world.ground = 0
            let left = world.addCharacter(radius: 0.4, height: 1.8,
                                          at: Vector3(-2, 0, 0), group: "phantoms")
            let right = world.addCharacter(radius: 0.4, height: 1.8,
                                           at: Vector3(2, 0, 0), group: "phantoms")
            if filtered { world.ignoreCollisions(between: "phantoms", and: "phantoms") }
            left.move(Vector3(2, 0, 0))
            right.move(Vector3(-2, 0, 0))
            var closest = Double.infinity
            for _ in 0 ..< 120 {
                world.step(dt: 1.0 / 60)
                closest = min(closest, abs(left.position.x - right.position.x))
            }
            return closest
        }
        #expect(closestApproach(filtered: false) > 0.7,
                "two capsules keep their own width between them")
        #expect(closestApproach(filtered: true) < 0.2,
                "they walked through each other")
    }

    // MARK: Vehicles

    /// A wheel does not collide through its body's layer: it feels for the road
    /// with its own collision tester, built against one layer when the vehicle
    /// is made. So a vehicle in a group that ignores the ground has to find no
    /// road at all, which is the only way to know the testers were built with
    /// the group and not without it.
    @Test func aVehiclesWheelsFeelForTheRoadInItsOwnGroup() throws {
        func rideHeight(filtered: Bool) throws -> Double {
            let world = World3D()
            world.ground = 0
            world.groundBody?.group = "road"
            let car = try #require(world.addVehicle(
                .box(width: 1.8, height: 0.6, depth: 4), at: Vector3(0, 1, 0),
                wheels: [
                    .wheel(at: Vector3(0.9, -0.2, 1.3), steers: true),
                    .wheel(at: Vector3(-0.9, -0.2, 1.3), steers: true),
                    .wheel(at: Vector3(0.9, -0.2, -1.3), driven: true),
                    .wheel(at: Vector3(-0.9, -0.2, -1.3), driven: true),
                ], group: "traffic"))
            if filtered { world.ignoreCollisions(between: "traffic", and: "road") }
            run(world, steps: 120)
            return car.body.position.y
        }
        #expect(try rideHeight(filtered: false) > 0.3, "it sits on its suspension")
        #expect(try rideHeight(filtered: true) < -1, "nothing held it up")
    }

    /// And the testers are rebuilt when a live vehicle changes group, rather
    /// than keeping the layer they were made with.
    @Test func aVehicleChangingGroupRebuildsItsWheels() throws {
        let world = World3D()
        world.ground = 0
        world.groundBody?.group = "road"
        world.ignoreCollisions(between: "traffic", and: "road")
        let car = try #require(world.addVehicle(
            .box(width: 1.8, height: 0.6, depth: 4), at: Vector3(0, 1, 0),
            wheels: [
                .wheel(at: Vector3(0.9, -0.2, 1.3), steers: true),
                .wheel(at: Vector3(-0.9, -0.2, 1.3), steers: true),
                .wheel(at: Vector3(0.9, -0.2, -1.3), driven: true),
                .wheel(at: Vector3(-0.9, -0.2, -1.3), driven: true),
            ]))
        run(world, steps: 60)
        #expect(car.body.position.y > 0.3, "the default group rides the road")

        car.group = "traffic"
        #expect(car.group == "traffic")
        run(world, steps: 120)
        #expect(car.body.position.y < -1, "its wheels stopped finding the road")
    }

    // MARK: Soft bodies and figures

    /// A soft body carries a group like anything else, so a cloth can be told
    /// to drape through what it would otherwise land on.
    @Test func aSoftBodyIsFilteredToo() throws {
        func restingHeight(filtered: Bool) throws -> Double {
            let world = World3D()
            world.ground = -3
            world.addBody(.box(width: 2, height: 1, depth: 2), at: Vector3(0, 0, 0),
                          kind: .static, group: "props")
            let cloth = try #require(world.addSoftBody(
                from: Mesh.plane(width: 2, depth: 2, segments: 8),
                at: Vector3(0, 2, 0), mass: 0.5, group: "drapes"))
            if filtered { world.ignoreCollisions(between: "drapes", and: "props") }
            run(world, steps: 240)
            return cloth.center.y
        }
        #expect(try restingHeight(filtered: false) > 0,
                "it settles on top of the block")
        #expect(try restingHeight(filtered: true) < -2, "it fell past it")
    }

    /// A whole figure takes a group, and the filter that keeps its own limbs
    /// from fighting each other is a separate thing that stays as it was: two
    /// figures in one group still collide.
    @Test func afigureTakesAGroupWithoutLosingItsOwnJointFilter() throws {
        let scene = try Ragdoll3DTests.figure()
        let world = World3D()
        world.ground = 0
        world.addBody(.box(width: 6, height: 0.4, depth: 6), at: Vector3(0, 1, 0),
                      kind: .static, group: "shelf")
        let figure = try #require(world.addRagdoll(from: scene, at: Vector3(0, 3, 0),
                                                   group: "phantoms"))
        world.ignoreCollisions(between: "phantoms", and: "shelf")
        run(world, steps: 200)
        #expect(figure.position.y < 1, "it fell past the shelf")
        #expect(figure.limbs.count > 4, "and it is still a figure, not a heap")
    }

    // MARK: What the layer must not have broken

    /// Buoyancy sweeps the world for what it can float by asking about a
    /// layer, and a layer carries a group as well as a kind. A grouped body
    /// has to float exactly as an ungrouped one does.
    @Test func agroupedBodyStillFloats() {
        func waterline(group: CollisionGroup) -> Double {
            let world = World3D()
            world.water = Water(level: 0)
            let crate = world.addBody(.box(width: 1, height: 1, depth: 1),
                                      at: Vector3(0, 2, 0), density: 0.5,
                                      group: group)
            run(world, steps: 400)
            return crate.position.y
        }
        let plain = waterline(group: .default)
        let grouped = waterline(group: "cargo")
        #expect(plain > -0.4 && plain < 0.4, "a half-density crate rides half under")
        #expect(abs(grouped - plain) < 0.02, "the group changed nothing about it")
    }

    /// Statics still ignore each other, sensors still pair only with moving
    /// bodies, and a grab anchor is still invisible: the fixed rules survive
    /// having a group packed in beside them.
    @Test func theFixedRulesStillHold() {
        let world = World3D()
        let a = world.addBody(.box(width: 1, height: 1, depth: 1), at: .zero,
                              kind: .static, group: "scenery")
        let b = world.addBody(.box(width: 1, height: 1, depth: 1),
                              at: Vector3(0.2, 0, 0), kind: .static,
                              group: "scenery")
        run(world, steps: 30)
        #expect(a.touching.isEmpty && b.touching.isEmpty,
                "two overlapping statics report nothing, group or not")
    }

    /// The table is a fixed size. A world that names more groups than it holds
    /// keeps the extras in the default group rather than quietly aliasing them
    /// onto a group already in use, which would filter the wrong things.
    @Test func aWorldThatRunsOutOfGroupsFallsBackToTheDefault() {
        let world = World3D()
        for index in 0 ..< 100 { _ = world.groupIndex(CollisionGroup("g\(index)")) }
        #expect(world.collisionGroups.count == World3D.maxCollisionGroups)
        #expect(world.groupIndex("g0") == 1)
        #expect(world.groupIndex("g99") == 0, "past the table, everything is default")
    }

    /// The same rules and the same scene replay identically, which is what the
    /// whole 3D tier promises within one build.
    @Test func identicalRunsStayIdentical() {
        func trace() -> [Double] {
            let world = World3D()
            world.ground = -4
            world.addBody(.box(width: 4, height: 0.4, depth: 4), at: Vector3(0, 1, 0),
                          kind: .static, group: "shelf")
            let a = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(0, 3, 0), group: "cargo")
            let b = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                  at: Vector3(0.1, 4, 0.1))
            world.ignoreCollisions(between: "cargo", and: "shelf")
            var trace: [Double] = []
            for step in 0 ..< 150 {
                world.step(dt: 1.0 / 60)
                if step % 30 == 0 { trace += [a.position.y, b.position.y] }
            }
            return trace
        }
        #expect(trace() == trace())
    }
}
