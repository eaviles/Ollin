import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for saving a world and loading it back. Behavioral (the
/// no-pixel-snapshot policy for physics), each answer pinned against a
/// counterfactual twin: the same scene with one thing changed, so a passing
/// test can't be explained by the geometry alone. Parallel-safe like the rest
/// of the 3D suite.
struct PhysicsSnapshotTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// A heap of boxes dropped into a ring, settled. Deterministic: no
    /// randomness anywhere near a physics test.
    @discardableResult
    func pile(in world: World3D, count: Int = 12, settle: Int = 600) -> World3D {
        world.ground = 0
        world.bounce = 0.15
        for i in 0 ..< count {
            let a = Double(i) * 0.7
            world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                          at: Vector3(cos(a) * 0.6, 1.0 + Double(i) * 0.6, sin(a) * 0.6),
                          rotated: a, axis: Vector3(0.3, 1, 0.2))
        }
        run(world, steps: settle)
        return world
    }

    // MARK: The pile comes back

    /// The headline: a settled heap restored from its own snapshot stands in
    /// exactly the poses it was captured in, to the last bit. The twin is the
    /// same heap after it has been knocked over, which is metres away, so the
    /// zero is the snapshot's doing and not a heap that never moved.
    @Test func aRestoredPileStandsExactlyWhereItWasSaved() {
        let world = World3D()
        pile(in: world)
        let saved = world.snapshot()
        let settled = world.bodies.map(\.position)

        // Knock it over.
        for body in world.bodies { body.velocity = Vector3(0, 2, 9) }
        run(world, steps: 240)
        let scattered = world.bodies.map(\.position)
        let disturbance = zip(settled, scattered).map { ($0 - $1).length }.max() ?? 0
        #expect(disturbance > 1, "the twin should really be knocked about")

        world.restore(saved)
        let restored = world.bodies.map(\.position)
        #expect(restored.count == settled.count)
        let error = zip(settled, restored).map { ($0 - $1).length }.max() ?? .infinity
        #expect(error == 0, "a restored pile stands exactly where it was saved")
    }

    /// Restoring is idempotent down to the byte: capture, put it back, capture
    /// again, and the two files are the same. Nothing is quietly re-derived on
    /// the way through.
    @Test func restoringAndCapturingAgainGivesTheSameBytes() {
        let world = World3D()
        pile(in: world)
        let first = world.snapshot()
        world.restore(first)
        #expect(world.snapshot() == first)
    }

    /// A settled pile is asleep, and it comes back asleep, so it holds its
    /// shape exactly rather than shuddering back into place. The twin is the
    /// same poses handed to `addBody` the ordinary way, which arrive awake.
    @Test func aRestoredPileIsAsSettledAsTheOneItCameFrom() {
        let world = World3D()
        pile(in: world)
        #expect(world.bodies.allSatisfy { !$0.isAwake }, "the pile has settled")
        let settled = world.bodies.map(\.position)

        world.restore(world.snapshot())
        #expect(world.bodies.allSatisfy { !$0.isAwake },
                "a restored pile is asleep, not woken")
        run(world, steps: 60)
        let drift = zip(settled, world.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(drift == 0, "and it does not move at all when stepped")

        let fresh = World3D()
        fresh.ground = 0
        for position in settled {
            fresh.addBody(.box(width: 0.5, height: 0.5, depth: 0.5), at: position)
        }
        #expect(fresh.bodies.allSatisfy { $0.isAwake },
                "an ordinarily built pile arrives awake")
    }

    /// The determinism claim: a world stepped on from a restore lands exactly
    /// where the one that was never interrupted does. The twin is the same
    /// flight with a different launch, which lands elsewhere.
    @Test func aRestoredWorldCarriesOnIdentically() {
        func flight(restoring: Bool, push: Double = 3) -> Vector3 {
            let world = World3D()
            let ball = world.addBody(.sphere(radius: 0.2), at: Vector3(0, 10, 0))
            ball.velocity = Vector3(push, 2, -1)
            ball.angularVelocity = Vector3(0.5, -0.2, 0.9)
            run(world, steps: 30)
            if restoring { world.restore(world.snapshot()) }
            run(world, steps: 60)
            return world.bodies[0].position
        }
        let straight = flight(restoring: false)
        let viaSnapshot = flight(restoring: true)
        #expect((straight - viaSnapshot).length == 0,
                "a restored world carries on exactly where it left off")
        #expect((straight - flight(restoring: false, push: 4)).length > 0.5,
                "and the measurement is not blind to a real difference")
    }

    /// A body in motion keeps it: the restored ball is travelling and spinning
    /// at the speed it was captured at, where a body rebuilt by hand starts
    /// from rest.
    @Test func aMovingBodyCarriesItsMotion() {
        let world = World3D()
        let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 5, 0),
                                 gravityScale: 0)
        ball.velocity = Vector3(2, -3, 1)
        ball.angularVelocity = Vector3(0.4, 1.1, -0.7)
        run(world, steps: 10)
        let velocity = ball.velocity
        let spin = ball.angularVelocity

        world.restore(world.snapshot())
        #expect((world.bodies[0].velocity - velocity).length == 0)
        #expect((world.bodies[0].angularVelocity - spin).length == 0)
    }

    // MARK: Joints keep their zero

    /// A joint's angle is measured from the pose it was made in, so a snapshot
    /// has to remember that pose rather than re-zeroing the joint wherever the
    /// door happens to be standing. The twin is the naive restore: the same
    /// door, the same limits, connected at the swung pose, which reads zero.
    @Test func aHingeKeepsItsZeroAcrossASnapshot() {
        let world = World3D()
        let frame = world.addBody(.box(width: 1, height: 0.2, depth: 1), at: .zero,
                                  kind: .static)
        let door = world.addBody(.box(width: 1.4, height: 0.1, depth: 0.6),
                                 at: Vector3(1, 0, 0))
        let hinge = world.connect(frame, door,
                                  .revolute(at: .zero, axis: .unitZ,
                                            limits: -0.02...1.2))
        hinge.drive(to: 0.8, frequency: 6)
        run(world, steps: 180)
        let swung = hinge.angle
        #expect(swung > 0.5, "the door really is standing open")

        world.restore(world.snapshot())
        #expect(abs(world.joints[0].angle - swung) == 0,
                "the restored hinge reads the same angle it was saved at")

        // The counterfactual: connect it where it now stands and zero moves.
        let naive = World3D()
        let post = naive.addBody(.box(width: 1, height: 0.2, depth: 1), at: .zero,
                                 kind: .static)
        let leaf = naive.addBody(.box(width: 1.4, height: 0.1, depth: 0.6),
                                 at: world.bodies[1].position)
        leaf.setRotation(swung, axis: .unitZ)
        let naiveHinge = naive.connect(post, leaf,
                                       .revolute(at: .zero, axis: .unitZ,
                                                 limits: -0.02...1.2))
        #expect(abs(naiveHinge.angle) < 1e-6,
                "a joint made at the swung pose calls that pose zero")
    }

    /// And the limit moves with the zero: a restored door still stops where the
    /// original one did, rather than opening another whole swing past it.
    @Test func aHingeLimitStillStopsWhereItDid() {
        func openWide(restoring: Bool) -> Double {
            let world = World3D()
            let frame = world.addBody(.box(width: 1, height: 0.2, depth: 1),
                                      at: .zero, kind: .static)
            let door = world.addBody(.box(width: 1.4, height: 0.1, depth: 0.6),
                                     at: Vector3(1, 0, 0))
            var hinge = world.connect(frame, door,
                                      .revolute(at: .zero, axis: .unitZ,
                                                limits: -0.02...1.2))
            hinge.drive(to: 0.6, frequency: 6)
            run(world, steps: 180)
            if restoring {
                world.restore(world.snapshot())
                hinge = world.joints[0]
            }
            // Now shove it as far open as it will go.
            hinge.drive(to: 4, frequency: 8)
            run(world, steps: 240)
            return world.bodies[1].rotationAngle
        }
        let straight = openWide(restoring: false)
        let viaSnapshot = openWide(restoring: true)
        #expect(abs(straight - 1.2) < 0.05, "the door stops at its limit")
        #expect(abs(viaSnapshot - straight) < 0.02,
                "and a restored door stops in the same place")
    }

    /// A rod between two bodies still holds them the distance it was made at,
    /// including the length it worked out for itself from where they stood.
    @Test func aRodKeepsTheLengthItWasMadeAt() {
        let world = World3D()
        world.ground = -6
        let anchor = world.addBody(.sphere(radius: 0.2), at: Vector3(0, 4, 0),
                                   kind: .static)
        let bob = world.addBody(.sphere(radius: 0.3), at: Vector3(1.7, 4, 0))
        world.connect(anchor, bob, .distance(from: anchor.position, to: bob.position))
        run(world, steps: 120)
        let spanBefore = (world.bodies[1].position - world.bodies[0].position).length

        world.restore(world.snapshot())
        run(world, steps: 120)
        let spanAfter = (world.bodies[1].position - world.bodies[0].position).length
        #expect(abs(spanAfter - 1.7) < 0.05, "the rod is still 1.7 long")
        #expect(abs(spanAfter - spanBefore) < 0.02)
    }

    /// A joint anchored to the world's own floor slab, which is not one of the
    /// saved bodies, comes back anchored to the restored floor.
    @Test func aJointToTheGroundCarries() {
        let world = World3D()
        world.ground = 0
        let post = world.addBody(.box(width: 0.3, height: 2, depth: 0.3),
                                 at: Vector3(0, 3, 0))
        world.connect(world.groundBody!, post, .ball(at: Vector3(0, 2, 0)))
        run(world, steps: 120)
        let hangingBefore = world.bodies[0].position

        world.restore(world.snapshot())
        #expect(world.joints.count == 1, "the joint to the floor was kept")
        run(world, steps: 120)
        #expect((world.bodies[0].position - hangingBefore).length < 0.05,
                "and it still hangs from the same point")

        // The twin: no joint at all and the post falls to the floor.
        let loose = World3D()
        loose.ground = 0
        let free = loose.addBody(.box(width: 0.3, height: 2, depth: 0.3),
                                 at: Vector3(0, 3, 0))
        run(loose, steps: 120)
        #expect(free.position.y < hangingBefore.y - 0.5,
                "an unjointed post ends up on the ground")
    }

    /// Gears are written against two joints rather than two bodies, so they are
    /// saved last and put back once both hinges exist. The twin is the same
    /// pair with the gear left out, where the second wheel never turns.
    @Test func aGearPairCarries() {
        func turn(linked: Bool, restoring: Bool) -> Double {
            let world = World3D()
            world.gravity = .zero
            let frame = world.addBody(.box(width: 4, height: 0.2, depth: 0.2),
                                      at: .zero, kind: .static)
            let small = world.addBody(.cylinder(height: 0.2, radius: 0.5),
                                      at: Vector3(-0.8, 0, 0),
                                      rotated: .pi / 2, axis: .unitX)
            let big = world.addBody(.cylinder(height: 0.2, radius: 1.0),
                                    at: Vector3(1.2, 0, 0),
                                    rotated: .pi / 2, axis: .unitX)
            world.ignoreCollisions(between: .default, and: .default)
            var driver = world.connect(frame, small,
                                       .revolute(at: small.position, axis: .unitZ))
            var follower = world.connect(frame, big,
                                         .revolute(at: big.position, axis: .unitZ))
            if linked { world.connect(driver, follower, .gear(teeth: 1, and: 2)) }
            if restoring {
                world.restore(world.snapshot())
                driver = world.joints[0]
                follower = world.joints[1]
            }
            driver.drive(at: 4)
            run(world, steps: 120)
            // How far the second hinge has turned from where it was made,
            // which is what the gear does or does not carry over to it.
            return abs(follower.angle)
        }
        #expect(turn(linked: true, restoring: false) > 0.5, "the gear pair turns")
        #expect(turn(linked: false, restoring: true) < 0.05,
                "without a gear the second wheel sits still")
        #expect(turn(linked: true, restoring: true) > 0.5,
                "and a restored gear pair still turns")
    }

    // MARK: The world's own settings

    /// Everything the world itself holds rides along: how hard gravity pulls,
    /// where the floor is, how bouncy it is, the unit scale, and the water.
    @Test func theWorldsOwnSettingsCarry() {
        let world = World3D(maxBodies: 256)
        world.unitsPerMeter = 4
        world.gravity = Vector3(0.5, -14, -0.25)
        world.ground = 1.5
        world.bounce = 0.42
        world.maxTimestep = 1.0 / 45
        world.water = Water(level: 2.5, density: 1.3, linearDrag: 0.7,
                            angularDrag: 0.2, flow: Vector3(0.4, 0, -0.1),
                            waves: Water.Waves(amplitude: 0.3, wavelength: 7,
                                               speed: 1.1, heading: 0.6))
        world.addBody(.sphere(radius: 0.4), at: Vector3(0, 6, 0), density: 0.4)
        run(world, steps: 60)
        let phase = world.waterPhase

        let fresh = World3D(maxBodies: 256)
        fresh.restore(world.snapshot())
        #expect(fresh.unitsPerMeter == 4)
        #expect(fresh.gravity == Vector3(0.5, -14, -0.25))
        #expect(fresh.ground == 1.5)
        #expect(fresh.bounce == 0.42)
        #expect(fresh.maxTimestep == 1.0 / 45)
        #expect(fresh.water == world.water)
        #expect(fresh.waterPhase == phase)
        #expect(fresh.groundBody != nil, "the floor was rebuilt")
    }

    /// A floating crate restored into a world with no water of its own arrives
    /// with the sea it was saved in, and stays afloat. The twin is the same
    /// crate restored from a snapshot taken with the water turned off, which
    /// sinks past the level the first one holds.
    @Test func aFloatingSceneStaysAfloatAcrossASnapshot() {
        func settle(withWater: Bool) -> Double {
            let world = World3D()
            world.ground = -12
            if withWater { world.water = Water(level: 0) }
            world.addBody(.box(width: 1, height: 1, depth: 1),
                          at: Vector3(0, 3, 0), density: 0.4)
            run(world, steps: 400)
            let restored = World3D()
            restored.restore(world.snapshot())
            run(restored, steps: 200)
            return restored.bodies[0].position.y
        }
        #expect(settle(withWater: true) > -0.6, "the crate is still floating")
        #expect(settle(withWater: false) < -10, "the dry twin is on the bottom")
    }

    /// The collision-group table carries: the names in their solver order and
    /// every rule written about them. The twin is a snapshot taken before the
    /// rule, whose beads land on the tray instead of falling through it.
    @Test func collisionGroupsAndTheirRulesCarry() {
        func drop(writingTheRule: Bool) -> Double {
            let world = World3D()
            world.ground = -8
            world.addBody(.box(width: 4, height: 0.3, depth: 4), at: .zero,
                          kind: .static, group: "tray")
            world.addBody(.sphere(radius: 0.3), at: Vector3(0, 3, 0), group: "beads")
            if writingTheRule { world.ignoreCollisions(between: "beads", and: "tray") }
            let saved = world.snapshot()

            let fresh = World3D()
            fresh.restore(saved)
            #expect(fresh.collisionGroups.map(\.name) == ["default", "tray", "beads"],
                    "the group names come back in the solver's own order")
            run(fresh, steps: 400)
            return fresh.bodies[1].position.y
        }
        #expect(drop(writingTheRule: false) > -0.5, "the bead rests on the tray")
        #expect(drop(writingTheRule: true) < -7, "the rule lets it through")
    }

    /// Every per-body knob comes back, including the ones only the solver knows
    /// (friction and restitution) and the ones only Ollin does (`buoyancy`).
    @Test func everyBodyKnobCarries() {
        let world = World3D()
        world.ground = 0
        let crate = world.addBody(.box(width: 1, height: 1, depth: 1),
                                  at: Vector3(0, 4, 0), density: 2.5,
                                  friction: 0.85, restitution: 0.33,
                                  freedom: .upright, gravityScale: 0.4,
                                  checksPath: true, group: "cargo")
        crate.buoyancy = 1.7
        let sensor = world.addBody(.sphere(radius: 1), at: Vector3(3, 1, 0),
                                   isSensor: true)
        let wall = world.addBody(.box(width: 2, height: 2, depth: 0.2),
                                 at: Vector3(-3, 1, 0), kind: .static)
        _ = sensor
        _ = wall

        world.restore(world.snapshot())
        let restored = world.bodies[0]
        #expect(restored.density == 2.5)
        #expect(abs(restored.friction - 0.85) < 1e-6)
        #expect(abs(restored.restitution - 0.33) < 1e-6)
        #expect(restored.freedom == Freedom3D.upright)
        #expect(abs(restored.gravityScale - 0.4) < 1e-6)
        #expect(restored.checksPath)
        #expect(restored.group == "cargo")
        #expect(restored.buoyancy == 1.7)
        #expect(abs(restored.mass - 2500) < 1, "density still sets the weight")
        #expect(world.bodies[1].isSensor, "the sensor is still a sensor")
        #expect(world.bodies[2].kind == .static, "the wall is still static")
    }

    /// Every collider kind survives, shape for shape. Mass is the check that a
    /// shape really came back the same size, since it falls out of the volume;
    /// the static-only kinds are checked by what they hold up.
    @Test func everyColliderKindCarries() {
        let world = World3D(maxBodies: 512)
        let field = Heightfield(columns: 9, rows: 9) { u, v in 0.2 + 0.3 * u * v }
        let sculpted = Mesh.box(width: 2, height: 0.4, depth: 2)
        let colliders: [Collider3D] = [
            .sphere(radius: 0.4),
            .box(width: 0.6, height: 0.5, depth: 0.7),
            .capsule(height: 0.8, radius: 0.25),
            .cylinder(height: 0.9, radius: 0.3),
            .taperedCapsule(height: 0.7, topRadius: 0.15, bottomRadius: 0.35),
            .taperedCylinder(height: 0.6, topRadius: 0.2, bottomRadius: 0.4),
            .cone(height: 0.8, radius: 0.35),
            .hull([Vector3(-0.3, -0.3, -0.3), Vector3(0.4, -0.2, -0.3),
                   Vector3(0, 0.5, -0.2), Vector3(0, 0, 0.45)]),
            .compound([.part(.box(width: 0.3, height: 0.3, depth: 0.3)),
                       .part(.sphere(radius: 0.2), at: Vector3(0, 0.4, 0),
                             rotated: 0.5, axis: .unitZ, density: 6)]),
        ]
        for (i, collider) in colliders.enumerated() {
            world.addBody(collider, at: Vector3(Double(i) * 3, 5, 0),
                          gravityScale: 0)
        }
        world.addBody(.mesh(sculpted), at: Vector3(0, 0, 12), kind: .static)
        world.addBody(.heightfield(field, width: 6, depth: 6, height: 2),
                      at: Vector3(0, 0, -12), kind: .static)
        let masses = world.bodies.map(\.mass)
        let positions = world.bodies.map(\.position)

        world.restore(world.snapshot())
        #expect(world.bodies.count == colliders.count + 2)
        for (i, body) in world.bodies.enumerated() {
            #expect(abs(body.mass - masses[i]) < 1e-4,
                    "collider \(i) came back the same size")
            #expect((body.position - positions[i]).length == 0)
        }
        // The static kinds are checked by what they carry: a ball dropped onto
        // the restored plate and one dropped onto the restored terrain both
        // come to rest above them.
        let onPlate = world.addBody(.sphere(radius: 0.2), at: Vector3(0, 3, 12))
        let onTerrain = world.addBody(.sphere(radius: 0.2), at: Vector3(0, 4, -12))
        run(world, steps: 300)
        #expect(onPlate.position.y > 0.3, "the restored mesh plate holds it up")
        #expect(onTerrain.position.y > 0.3, "and so does the restored terrain")
    }

    // MARK: Files

    /// The file round trip is the same snapshot: the bytes match, and a world
    /// built from the file stands where the one in memory does.
    @Test func aFileRoundTripIsTheSameSnapshot() throws {
        let world = World3D()
        pile(in: world, count: 6, settle: 400)
        let saved = world.snapshot()
        let settled = world.bodies.map(\.position)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-snapshot-test-\(UUID().uuidString).physics")
        defer { try? FileManager.default.removeItem(at: url) }
        try world.save(to: url)

        let read = try PhysicsSnapshot(contentsOf: url)
        #expect(read == saved, "the file holds exactly the snapshot")
        #expect(read.bodyCount == 6)

        let fresh = World3D()
        #expect(fresh.load(contentsOf: url), "the file loads")
        let error = zip(settled, fresh.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error == 0, "and the loaded pile stands where the saved one did")
    }

    /// Anything that isn't a snapshot is refused rather than half-read, and a
    /// truncated one leaves the pile that is already standing alone.
    @Test func aBadFileIsRefusedAndLeavesTheWorldStanding() {
        #expect(PhysicsSnapshot(data: Data()) == nil)
        #expect(PhysicsSnapshot(data: Data(repeating: 7, count: 64)) == nil)

        let world = World3D()
        pile(in: world, count: 4, settle: 300)
        let saved = world.snapshot()
        let settled = world.bodies.map(\.position)

        // Keep the header, lose the body: a snapshot that opens and then stops.
        let truncated = PhysicsSnapshot(data: saved.data.prefix(40))
        #expect(truncated != nil, "the header still reads")
        world.restore(truncated!)
        #expect(world.bodies.count == 4, "the world was left alone")
        let error = zip(settled, world.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error == 0, "down to the last bit")

        #expect(world.load(contentsOf: FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-there-is-no-such-file.physics")) == false)
    }

    /// A damaged snapshot is refused too, which a reader running out of bytes
    /// cannot manage on its own: the payload is packed, and a packed payload
    /// with a byte flipped still unpacks to a full-length buffer that parses
    /// into *some* world. The twin is the same snapshot undamaged, which
    /// restores the pile it came from.
    @Test func aDamagedSnapshotIsRefusedRatherThanHalfRead() {
        let world = World3D()
        pile(in: world, count: 5, settle: 300)
        let saved = world.snapshot()
        let settled = world.bodies.map(\.position)

        var bytes = saved.data
        let middle = bytes.startIndex + bytes.count / 2
        bytes[middle] = bytes[middle] &+ 1
        let damaged = PhysicsSnapshot(data: bytes)
        #expect(damaged != nil, "the header still reads, so the refusal is the payload's")

        world.restore(damaged!)
        #expect(world.bodies.count == 5, "the world was left alone")
        let held = zip(settled, world.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(held == 0, "down to the last bit")

        // The twin: undamaged, the same bytes restore the pile.
        let fresh = World3D()
        fresh.restore(saved)
        let restored = zip(settled, fresh.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(fresh.bodies.count == 5)
        #expect(restored == 0, "so the refusal was the damage, not the format")
    }

    /// The payload is packed, which is what keeps a settled arrangement small
    /// enough to commit beside a sketch. A body writes about 130 bytes of
    /// `Double`s whose high bytes repeat, so a pile of them packs several fold;
    /// the twin is the same count of bodies given genuinely varied poses, which
    /// packs less well and still round-trips exactly.
    @Test func aSnapshotIsPackedAndStillExact() {
        let world = World3D()
        pile(in: world, count: 40, settle: 400)
        let saved = world.snapshot()
        let loose = 40 * 130
        #expect(saved.data.count < loose / 2,
                "40 bodies packed into \(saved.data.count) bytes, under half of \(loose)")

        let fresh = World3D()
        fresh.restore(saved)
        let error = zip(world.bodies.map(\.position), fresh.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error == 0, "and packing lost nothing")

        // The twin: poses that share far fewer bytes still come back exact.
        let varied = World3D()
        varied.ground = 0
        for i in 0 ..< 40 {
            let t = Double(i)
            varied.addBody(.box(width: 0.3 + t * 0.017, height: 0.41, depth: 0.29),
                           at: Vector3(sin(t * 1.7) * 9.13, 1.37 + t * 0.61,
                                       cos(t * 2.3) * 7.41),
                           rotated: t * 0.37, axis: Vector3(0.31, 0.83, 0.46))
        }
        let variedSnapshot = varied.snapshot()
        let back = World3D()
        back.restore(variedSnapshot)
        let variedError = zip(varied.bodies.map(\.position), back.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(variedError == 0, "whatever the bytes look like")
    }

    // MARK: What a snapshot leaves out

    /// A soft body is the one tier a snapshot has no way to carry, since it is
    /// built from a mesh. Everything else in the world comes back, so the
    /// check is that the cloth is the only thing missing.
    @Test func aSoftBodyIsLeftOutRatherThanHalfSaved() {
        let world = World3D()
        world.ground = 0
        world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 1, 0))
        world.addVehicle(.box(width: 1.8, height: 0.6, depth: 4),
                         at: Vector3(6, 1, 0),
                         wheels: [
                            .wheel(at: Vector3(0.9, -0.1, 1.3), steers: true),
                            .wheel(at: Vector3(-0.9, -0.1, 1.3), steers: true),
                            .wheel(at: Vector3(0.9, -0.1, -1.3), driven: true),
                            .wheel(at: Vector3(-0.9, -0.1, -1.3), driven: true),
                         ])
        world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(-6, 2, 0))
        world.addSoftBody(from: Mesh.plane(width: 2, depth: 2, segments: 6),
                          at: Vector3(0, 4, 6))
        #expect(world.bodies.count == 2, "the chassis is one of the world's bodies")

        let saved = world.snapshot()
        #expect(saved.bodyCount == 2, "the crate and the chassis")

        let fresh = World3D()
        fresh.restore(saved)
        #expect(fresh.bodies.count == 2)
        #expect(fresh.vehicles.count == 1, "and the chassis came back a vehicle")
        #expect(fresh.characters.count == 1)
        #expect(fresh.softBodies.isEmpty, "only the cloth is left behind")
    }

    /// Restoring empties whatever the world was holding first, so a snapshot
    /// replaces a world rather than piling onto it.
    @Test func restoringReplacesTheWorldRatherThanAddingToIt() {
        let source = World3D()
        source.ground = 0
        for i in 0 ..< 3 {
            source.addBody(.sphere(radius: 0.3), at: Vector3(Double(i), 1, 0))
        }
        let saved = source.snapshot()

        let busy = World3D()
        busy.ground = 5
        for i in 0 ..< 9 {
            busy.addBody(.box(width: 1, height: 1, depth: 1),
                         at: Vector3(0, Double(i) + 6, 0))
        }
        busy.restore(saved)
        #expect(busy.bodies.count == 3)
        #expect(busy.ground == 0)
    }

    /// The counts on the snapshot itself say what is in it before anything is
    /// restored, which is what a sketch checks a file with.
    @Test func aSnapshotSaysWhatItHolds() {
        let world = World3D()
        world.ground = 0
        let a = world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 3, 0))
        let b = world.addBody(.sphere(radius: 0.4), at: Vector3(0, 5, 0))
        world.connect(a, b, .distance(from: a.position, to: b.position))
        let saved = world.snapshot()
        #expect(saved.bodyCount == 2)
        #expect(saved.jointCount == 1)
        #expect(saved.data.count > 20, "there is a payload behind the header")
    }

    /// A grab is a hand on a body, not a part of the world, so it is not saved
    /// and a restored world is not still holding on to anything.
    @Test func aGrabIsNotSaved() {
        let world = World3D()
        world.ground = 0
        let crate = world.addBody(.box(width: 1, height: 1, depth: 1),
                                  at: Vector3(0, 2, 0))
        world.grab(crate, at: crate.position)
        #expect(world.joints.count == 1)
        #expect(world.snapshot().jointCount == 0)
        world.restore(world.snapshot())
        #expect(world.joints.isEmpty)
    }
}

// MARK: - The tiers above a loose body

/// A snapshot carries the characters, vehicles, and figures a world is holding,
/// not just its loose bodies: none of them is built from anything heavier than
/// the shapes a body already writes down. Behavioral, counterfactual twins,
/// same house rules as the rest of the file.
struct SnapshotTierTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    // MARK: Characters

    /// A walking figure comes back walking: in the same place, at the same
    /// pace, and it carries on to exactly where the one that was never
    /// interrupted gets to. The twin is the same walk from a standing start,
    /// which ends up short.
    @Test func aWalkingFigureComesBackWalking() {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 2, 0))
        walker.move(Vector3(1.5, 0, 0))
        run(world, steps: 120)
        let mid = walker.position

        let fresh = World3D()
        fresh.ground = 0
        fresh.restore(world.snapshot())
        let back = try! #require(fresh.characters.first)
        #expect((back.position - mid).length == 0, "it comes back where it was")
        #expect((back.velocity - walker.velocity).length == 0, "at the same pace")

        walker.move(Vector3(1.5, 0, 0))
        back.move(Vector3(1.5, 0, 0))
        run(world, steps: 60)
        run(fresh, steps: 60)
        #expect((back.position - walker.position).length == 0,
                "and walks on to the same place")

        // The twin: a figure that came back standing where it started, or one
        // not walking at all, is a metre and a half away. (A character has no
        // inertia to lose, so the counterfactual has to be about the carried
        // position rather than about carried speed.)
        let idle = World3D()
        idle.ground = 0
        let sitting = idle.addCharacter(radius: 0.3, height: 1.8, at: mid)
        run(idle, steps: 60)
        #expect(sitting.position.x < walker.position.x - 1,
                "and the measurement is not blind to a figure that stayed put")
    }

    /// Every knob a character was tuned with comes back, each set away from
    /// its default so a forgotten one reads as the default rather than passing
    /// by accident.
    @Test func everyCharacterKnobCarries() {
        let world = World3D()
        world.ground = 0
        let walker = world.addCharacter(radius: 0.42, height: 1.55,
                                        at: Vector3(1, 2, -3),
                                        stepHeight: 0.61,
                                        stickToFloorDistance: 0.34,
                                        maxSlope: 0.77, mass: 88,
                                        pushStrength: 210,
                                        group: "walkers")
        walker.facing = 1.23

        let fresh = World3D()
        fresh.ground = 0
        fresh.restore(world.snapshot())
        let back = try! #require(fresh.characters.first)
        #expect(back.radius == 0.42)
        #expect(back.height == 1.55)
        #expect(back.stepHeight == 0.61)
        #expect(back.stickToFloorDistance == 0.34)
        #expect(back.maxSlope == 0.77)
        #expect(back.mass == 88)
        #expect(back.pushStrength == 210)
        #expect(back.facing == 1.23)
        #expect(back.group == "walkers")

        // The twin: a default character shares none of those numbers.
        let plain = World3D()
        let bare = plain.addCharacter(at: .zero)
        #expect(bare.radius != back.radius)
        #expect(bare.stepHeight != back.stepHeight)
        #expect(bare.maxSlope != back.maxSlope)
        #expect(bare.pushStrength != back.pushStrength)
    }

    // MARK: Vehicles

    func machine(in world: World3D, at position: Vector3 = Vector3(0, 1, 0),
                 tracked: Bool = false) -> Vehicle3D? {
        world.ground = 0
        return world.addVehicle(.box(width: 1.8, height: 0.6, depth: 4),
                                at: position,
                                wheels: [
                                    .wheel(at: Vector3(0.9, -0.1, 1.3), steers: !tracked),
                                    .wheel(at: Vector3(-0.9, -0.1, 1.3), steers: !tracked),
                                    .wheel(at: Vector3(0.9, -0.1, -1.3), driven: true),
                                    .wheel(at: Vector3(-0.9, -0.1, -1.3), driven: true),
                                ], tracked: tracked)
    }

    /// A parked machine comes back parked, and stepping it on moves it not at
    /// all: the chassis is in the same pose and everything under it is still.
    /// The twin is the same machine under power, which is metres away.
    @Test func aParkedMachineComesBackParked() throws {
        let world = World3D()
        let still = try #require(machine(in: world))
        run(world, steps: 240)
        let parked = still.body.position

        let fresh = World3D()
        fresh.restore(world.snapshot())
        let back = try #require(fresh.vehicles.first)
        #expect((back.body.position - parked).length == 0)

        run(fresh, steps: 120)
        #expect((back.body.position - parked).length == 0,
                "a parked machine restored stays parked")

        let driven = World3D()
        let mover = try #require(machine(in: driven, at: parked))
        mover.throttle = 1
        run(driven, steps: 120)
        #expect((mover.body.position - parked).length > 1,
                "and the measurement is not blind to a machine that moves")
    }

    /// A machine in motion keeps its drivetrain: the engine turning at the
    /// same speed, in the same gear, with its wheels already spinning. The twin
    /// is the same machine rebuilt by hand at the same pose and speed, whose
    /// wheels and engine start from rest and which falls behind.
    @Test func aMovingMachineKeepsItsDrivetrain() throws {
        let world = World3D()
        let car = try #require(machine(in: world))
        car.throttle = 1
        run(world, steps: 180)
        let pose = car.body.position
        let speed = car.speed

        let fresh = World3D()
        fresh.restore(world.snapshot())
        let back = try #require(fresh.vehicles.first)
        #expect(abs(back.rpm - car.rpm) == 0, "the engine is turning as fast")
        #expect(back.gear == car.gear, "in the gear it was in")
        #expect(abs(back.wheels[3].spinRate - car.wheels[3].spinRate) == 0,
                "and its wheels are already turning")
        #expect(abs(back.speed - speed) == 0)

        // The twin: rebuilt by hand, at the same pose, with the same chassis
        // velocity, but a drivetrain at rest.
        let rebuilt = World3D()
        let cold = try #require(machine(in: rebuilt, at: pose))
        cold.body.velocity = car.body.velocity
        #expect(cold.wheels[3].spinRate == 0, "its wheels are not turning")
        #expect(cold.rpm < back.rpm - 100, "and its engine is idling")

        car.throttle = 1; back.throttle = 1; cold.throttle = 1
        run(world, steps: 30); run(fresh, steps: 30); run(rebuilt, steps: 30)
        let carried = abs(back.speed - car.speed)
        let fromRest = abs(cold.speed - car.speed)
        #expect(carried < fromRest,
                "a carried drivetrain keeps pace better than one from rest: \(carried) against \(fromRest)")
    }

    /// Every wheel knob comes back, each moved off its default.
    @Test func everyWheelKnobCarries() throws {
        let world = World3D()
        world.ground = 0
        let front = Wheel3D.wheel(at: Vector3(0.9, -0.1, 1.3), radius: 0.41,
                                  width: 0.27, steers: true)
        front.maxSteerAngle = 0.44
        front.casterAngle = 0.13
        front.suspensionLength = 0.52
        front.suspensionTravel = 0.37
        front.suspensionFrequency = 1.9
        front.suspensionDamping = 0.61
        front.brakeTorque = 1234
        front.handBrakeTorque = 567
        front.grip = 1.4
        let rear = Wheel3D.wheel(at: Vector3(0, -0.1, -1.3), driven: true)
        let machine = try #require(
            world.addVehicle(.box(width: 1.8, height: 0.6, depth: 4),
                             at: Vector3(0, 1, 0), wheels: [front, rear],
                             mass: 900, engineTorque: 640, topSpeed: 22,
                             group: "traffic"))
        #expect(machine.wheels.count == 2)

        let fresh = World3D()
        fresh.restore(world.snapshot())
        let back = try #require(fresh.vehicles.first)
        #expect(back.wheels.count == 2)
        let wheel = back.wheels[0]
        #expect(wheel.radius == 0.41)
        #expect(wheel.width == 0.27)
        #expect(wheel.steers)
        #expect(wheel.maxSteerAngle == 0.44)
        #expect(wheel.casterAngle == 0.13)
        #expect(wheel.suspensionLength == 0.52)
        #expect(wheel.suspensionTravel == 0.37)
        #expect(wheel.suspensionFrequency == 1.9)
        #expect(wheel.suspensionDamping == 0.61)
        #expect(wheel.brakeTorque == 1234)
        #expect(wheel.handBrakeTorque == 567)
        #expect(wheel.grip == 1.4)
        #expect(back.wheels[1].driven, "and which wheels the engine turns")
        #expect(back.engineTorque == 640)
        #expect(back.topSpeed == 22)
        #expect(back.body.mass == 900)
        #expect(back.group == "traffic")

        // The twin: a default wheel shares none of the tuned numbers.
        let plain = Wheel3D.wheel(at: .zero)
        #expect(plain.radius != wheel.radius)
        #expect(plain.suspensionFrequency != wheel.suspensionFrequency)
        #expect(plain.grip != wheel.grip)
    }

    /// A tracked machine comes back tracked rather than as a car with four
    /// loose wheels, so its bands are still bands. The twin is the same hull
    /// saved as a wheeled machine, which reports no tracks at all.
    @Test func aTrackedMachineComesBackTracked() throws {
        let world = World3D()
        let crawler = try #require(machine(in: world, tracked: true))
        #expect(crawler.isTracked)
        run(world, steps: 60)

        let fresh = World3D()
        fresh.restore(world.snapshot())
        let back = try #require(fresh.vehicles.first)
        #expect(back.isTracked, "it is still a tracked machine")
        #expect(back.wheels(on: .left).count == 2)
        #expect(back.wheels(on: .right).count == 2)

        let wheeled = World3D()
        wheeled.restore({ () -> PhysicsSnapshot in
            let w = World3D()
            _ = machine(in: w, tracked: false)
            return w.snapshot()
        }())
        let plain = try #require(wheeled.vehicles.first)
        #expect(!plain.isTracked)
        #expect(plain.wheels(on: .left).isEmpty, "a wheeled machine has no bands")
    }

    /// A two-wheeler that holds itself up comes back still holding itself up.
    /// The twin is the same bike saved without balancing, which lies down.
    @Test func aBalancingTwoWheelerComesBackBalancing() throws {
        func lean(balances: Bool) throws -> Double {
            let world = World3D()
            world.ground = 0
            let bike = try #require(
                world.addVehicle(.box(width: 0.4, height: 0.6, depth: 1.8),
                                 at: Vector3(0, 1, 0),
                                 wheels: [
                                    .wheel(at: Vector3(0, -0.3, 0.7), radius: 0.35,
                                           width: 0.1, steers: true),
                                    .wheel(at: Vector3(0, -0.3, -0.7), radius: 0.35,
                                           width: 0.1, driven: true),
                                 ], balances: balances))
            for wheel in bike.wheels { wheel.casterAngle = 30 * .pi / 180 }
            // Start it leaned over, or nothing perturbs it and both stand up.
            bike.body.setRotation(0.44, axis: Vector3(0, 0, 1))
            bike.throttle = 0.6
            run(world, steps: 30)

            let fresh = World3D()
            fresh.restore(world.snapshot())
            let back = try #require(fresh.vehicles.first)
            #expect(back.balances == balances, "the machine came back as it was")
            back.throttle = 0.6
            run(fresh, steps: 240)
            return back.up.dot(Vector3(0, 1, 0))
        }
        let held = try lean(balances: true)
        let fallen = try lean(balances: false)
        #expect(held > 0.8, "the restored balancing bike rights itself (\(held))")
        #expect(fallen < held, "where the one saved unbalanced does not (\(fallen))")
    }

    // MARK: Figures

    /// A figure comes back with its limbs where they had fallen, fitted to the
    /// same shapes, and the scene it was fitted from still takes the pose. The
    /// twin is a figure built fresh from the same scene, which stands in the
    /// rest pose rather than in a heap.
    @Test func aFallenFigureComesBackWhereItLay() throws {
        let world = World3D()
        world.ground = 0
        let scene = try Ragdoll3DTests.figure()
        let doll = try #require(world.addRagdoll(from: scene, at: Vector3(0, 2, 0)))
        run(world, steps: 240)
        let fallen = doll.limbs.map(\.body.position)

        let fresh = World3D()
        fresh.ground = 0
        fresh.restore(world.snapshot())
        let back = try #require(fresh.ragdolls.first)
        #expect(back.limbs.count == doll.limbs.count)
        #expect(back.limbs.map { $0.name } == doll.limbs.map { $0.name },
                "the joints came back named")
        let error = zip(fallen, back.limbs.map(\.body.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error < 1e-6, "and lying where they fell (\(error))")

        // The scene is the sketch's own asset, and it still takes the pose.
        var drawn = scene
        drawn.apply(back)

        // The twin: built fresh, the same figure stands upright, not in a heap.
        let standing = World3D()
        standing.ground = 0
        let upright = try #require(standing.addRagdoll(from: scene,
                                                       at: Vector3(0, 2, 0)))
        let spread = zip(fallen, upright.limbs.map(\.body.position))
            .map { ($0 - $1).length }.max() ?? 0
        #expect(spread > 0.5, "a fresh figure is nowhere near a fallen one")
    }

    /// A figure keeps the shapes that were fitted to its mesh, which is the
    /// part a snapshot cannot re-derive without the skin. The twin is a
    /// different limb's shape, which is a different size.
    @Test func aFigureKeepsItsFittedShapes() throws {
        let world = World3D()
        world.ground = 0
        let doll = try #require(world.addRagdoll(from: try Ragdoll3DTests.figure(),
                                                 at: Vector3(0, 2, 0)))
        func radius(_ collider: Collider3D) -> Double? {
            if case .capsule(_, let r) = collider { return r }
            if case .sphere(let r) = collider { return r }
            return nil
        }
        let fitted = doll.limbs.compactMap { radius($0.collider) }
        #expect(fitted.count == doll.limbs.count, "every limb wears a round shape")

        let fresh = World3D()
        fresh.ground = 0
        fresh.restore(world.snapshot())
        let back = try #require(fresh.ragdolls.first)
        #expect(back.limbs.compactMap { radius($0.collider) } == fitted,
                "the fitted shapes came back unchanged")
        #expect((fitted.max() ?? 0) > (fitted.min() ?? 1) * 2,
                "and the fitting varies limb to limb, so matching them all is not matching one number")
    }

    /// A tightened joint keeps its limit across a snapshot, which the solver
    /// takes and never hands back. The twin is the same figure with the limits
    /// left loose, which folds further under the same shove.
    @Test func aFigureKeepsItsJointLimits() throws {
        // How far the figure has come apart: each limb's distance from the one
        // it hangs off, against the distance it was fitted at. A figure that
        // merely topples does not move here, where one whose joints let go
        // does, so this reads folding rather than falling.
        func splay(_ ragdoll: Ragdoll3D) -> Double {
            var worst = 0.0
            for (index, limb) in ragdoll.limbs.enumerated() {
                guard let parent = limb.parent else { continue }
                let now = (limb.body.position
                           - ragdoll.limbs[parent].body.position).length
                let fitted = (ragdoll.plan.limbs[index].jointOrigin
                              - ragdoll.plan.limbs[parent].jointOrigin).length
                worst = max(worst, abs(now - fitted))
            }
            return worst
        }
        func shove(tighten: Bool) throws -> Double {
            let world = World3D()
            world.ground = 0
            let doll = try #require(world.addRagdoll(from: try Ragdoll3DTests.figure(),
                                                     at: Vector3(0, 2, 0), swing: 1.2))
            if tighten {
                for limb in doll.limbs { doll.limit(limb.name, swing: 0.02) }
            }
            let fresh = World3D()
            fresh.ground = 0
            fresh.restore(world.snapshot())
            let back = try #require(fresh.ragdolls.first)
            back.limbs[0].body.kind = .kinematic     // hang it up, so it cannot fall
            back.limbs[3].body.velocity = Vector3(9, 0, 4)
            run(fresh, steps: 120)
            return splay(back)
        }
        let stiff = try shove(tighten: true)
        let loose = try shove(tighten: false)
        #expect(stiff < loose,
                "a restored figure holds the limits it was given: \(stiff) against \(loose)")
    }

    /// A figure does not need its scene to come back. The fitting is what the
    /// solver was built from, so a world restored in a process that never
    /// loaded the file still has the figure in it.
    @Test func aFigureComesBackWithoutItsScene() throws {
        let saved: PhysicsSnapshot
        do {
            let world = World3D()
            world.ground = 0
            _ = try #require(world.addRagdoll(from: try Ragdoll3DTests.figure(),
                                              at: Vector3(0, 2, 0)))
            run(world, steps: 120)
            saved = world.snapshot()
        }
        // Nothing here has seen the file.
        let fresh = World3D()
        fresh.ground = 0
        fresh.restore(saved)
        let back = try #require(fresh.ragdolls.first)
        #expect(back.limbs.count == 16)
        #expect(back.bodies.allSatisfy { $0.mass > 0 })
    }

    // MARK: Files

    /// The tiers survive a file the way the rigid tier does.
    @Test func theTiersSurviveAFileRoundTrip() throws {
        let world = World3D()
        let machine = try #require(machine(in: world))
        machine.throttle = 1
        world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(-6, 2, 0))
            .move(Vector3(0, 0, 1))
        run(world, steps: 120)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-tiers-\(UUID().uuidString).physics")
        defer { try? FileManager.default.removeItem(at: url) }
        try world.save(to: url)

        let fresh = World3D()
        #expect(fresh.load(contentsOf: url))
        #expect(fresh.vehicles.count == 1)
        #expect(fresh.characters.count == 1)
        let back = try #require(fresh.vehicles.first)
        #expect((back.body.position - machine.body.position).length == 0)
    }

    /// A world of every tier, restored and captured again, gives the same
    /// bytes: nothing is re-derived on the way through.
    ///
    /// The first capture of a *stepped* world is the exception, and it is the
    /// solver's doing rather than the format's: integrating a body lets its
    /// orientation drift a hair off unit length, and a quaternion handed back
    /// to the solver is normalized on the way in, since it requires a unit
    /// one. So the bytes settle after a single restore and never move again,
    /// which is what a file written from a loaded world needs.
    @Test func aWorldOfEveryTierRoundTripsToTheSameBytes() throws {
        let world = World3D()
        _ = try #require(machine(in: world))
        world.addCharacter(radius: 0.33, height: 1.7, at: Vector3(-6, 2, 0))
        _ = try #require(world.addRagdoll(from: try Ragdoll3DTests.figure(),
                                          at: Vector3(4, 2, 0)))
        world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(0, 6, 3))
        run(world, steps: 120)

        world.restore(world.snapshot())
        let settled = world.snapshot()
        world.restore(settled)
        #expect(world.snapshot() == settled)
        world.restore(world.snapshot())
        #expect(world.snapshot() == settled, "and it stays settled")
    }
}

// MARK: - Naming geometry rather than holding it

/// A snapshot holds everything by value, which is what makes it a file you can
/// commit. Bulk geometry is the exception worth naming: a mesh or heightfield
/// collider, and a soft body's whole surface. Behavioral, counterfactual twins.
struct SnapshotAssetTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    static let terrain = Heightfield.diamondSquare(size: 65, roughness: 0.6, seed: 3)
    static let knot = Mesh.torusKnot(radius: 2, tube: 0.5, segments: 120, sides: 18)

    /// A world with scenery in it: a terrain collider, a mesh collider, and a
    /// heap of crates settled on top.
    @discardableResult
    func scenery(in world: World3D, named: Bool) -> World3D {
        world.ground = 0
        // Standing on the floor rather than sunk into it, so anything landing
        // on the terrain is above where the bare floor would have caught it.
        let island = world.addBody(.heightfield(Self.terrain, width: 40, depth: 40,
                                                height: 6),
                                   at: Vector3(0, 0, 0), kind: .static)
        let sculpture = world.addBody(.mesh(Self.knot), at: Vector3(0, 11, 0),
                                      kind: .static)
        if named {
            island.assetName = "island"
            sculpture.assetName = "knot"
        }
        for i in 0 ..< 20 {
            world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                          at: Vector3(Double(i % 5) * 0.5 - 1,
                                      9 + Double(i / 5) * 0.5, 0))
        }
        run(world, steps: 400)
        return world
    }

    func resolver(_ name: String) -> PhysicsAsset? {
        switch name {
        case "island": return .heightfield(Self.terrain)
        case "knot": return .mesh(Self.knot)
        default: return nil
        }
    }

    /// The headline: naming the scenery takes the file from a hundred kilobytes
    /// to about one, and the world that comes back is the same world. The twin
    /// is the identical scene saved whole, which is the size of its scenery.
    @Test func namingTheSceneryIsTheDifferenceBetweenAKilobyteAndAHundred() {
        let whole = World3D()
        scenery(in: whole, named: false)
        let held = whole.snapshot()

        let world = World3D()
        scenery(in: world, named: true)
        let named = world.snapshot()

        #expect(held.assetNames.isEmpty, "a snapshot that holds everything names nothing")
        #expect(named.assetNames == ["island", "knot"], "and one that names says what")
        #expect(named.data.count * 20 < held.data.count,
                "naming it is at least twenty times smaller: \(named.data.count) against \(held.data.count)")

        let back = World3D()
        back.restore(named, resolving: resolver)
        #expect(back.bodies.count == world.bodies.count, "every body came back")
        let error = zip(world.bodies.map(\.position), back.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error == 0, "in exactly the poses it was saved in")
    }

    /// The named geometry itself comes back, not a stand-in: the terrain still
    /// holds bodies up where it did. The twin is the same world restored with
    /// no resolver, where the terrain is missing and a dropped body falls past
    /// where it should have landed.
    @Test func namedSceneryStillHoldsThingsUp() throws {
        let world = World3D()
        scenery(in: world, named: true)
        let saved = world.snapshot()

        let back = World3D()
        back.restore(saved, resolving: resolver)
        let onTerrain = back.addBody(.sphere(radius: 0.2), at: Vector3(4, 12, 4))
        run(back, steps: 240)

        let bare = World3D()
        bare.ground = 0
        bare.restore(saved)      // no resolver: the scenery is left out
        let falling = bare.addBody(.sphere(radius: 0.2), at: Vector3(4, 12, 4))
        run(bare, steps: 240)

        #expect(bare.bodies.count == back.bodies.count - 2,
                "the two named bodies are the ones missing")
        #expect(onTerrain.position.y > falling.position.y + 0.5,
                "the restored terrain holds the ball above where the bare world lets it fall")
    }

    /// A name the resolver does not know costs that one body, not the restore.
    /// The twin is the resolver that knows both names.
    @Test func anUnknownNameCostsOneBodyRatherThanTheWholeWorld() {
        let world = World3D()
        scenery(in: world, named: true)
        let saved = world.snapshot()
        let crates = world.bodies.count - 2

        let partial = World3D()
        partial.restore(saved) { $0 == "island" ? .heightfield(Self.terrain) : nil }
        #expect(partial.bodies.count == crates + 1, "the knot is the only one lost")

        let full = World3D()
        full.restore(saved, resolving: resolver)
        #expect(full.bodies.count == crates + 2, "where a resolver that knows both keeps both")
    }

    /// Handing back the wrong kind of geometry for a name is refused rather
    /// than forced into a collider it cannot be. The twin is the right kind.
    @Test func theWrongKindOfGeometryIsRefused() {
        let world = World3D()
        scenery(in: world, named: true)
        let saved = world.snapshot()

        let muddled = World3D()
        muddled.restore(saved) { name in
            // Both names answered, both with the other one's kind.
            name == "island" ? .mesh(Self.knot) : .heightfield(Self.terrain)
        }
        #expect(muddled.bodies.count == world.bodies.count - 2,
                "neither could be used")

        let right = World3D()
        right.restore(saved, resolving: resolver)
        #expect(right.bodies.count == world.bodies.count)
    }

    /// A name that now resolves to different geometry is still restored, since
    /// the saved poses are the best answer there is, but the snapshot notices.
    /// The fingerprint is what notices, so this pins that it can tell the two
    /// apart at all.
    @Test func aFingerprintTellsChangedGeometryFromTheSame() {
        let same = AssetFingerprint(of: .mesh(Self.knot))
        #expect(same.matches(AssetFingerprint(of: .mesh(Self.knot))))

        let coarser = Mesh.torusKnot(radius: 2, tube: 0.5, segments: 60, sides: 18)
        #expect(!same.matches(AssetFingerprint(of: .mesh(coarser))),
                "a re-exported mesh with a different vertex count is caught")

        let bigger = Mesh.torusKnot(radius: 3, tube: 0.5, segments: 120, sides: 18)
        #expect(!same.matches(AssetFingerprint(of: .mesh(bigger))),
                "and so is one of the same counts at a different size")

        let field = AssetFingerprint(of: .heightfield(Self.terrain))
        #expect(field.matches(AssetFingerprint(of: .heightfield(Self.terrain))))
        #expect(!field.matches(AssetFingerprint(
            of: .heightfield(Heightfield.diamondSquare(size: 65, roughness: 0.6,
                                                       seed: 9)))),
            "a terrain regenerated from another seed is not the same terrain")
    }

    // MARK: Soft bodies

    static let sheet = Mesh.plane(width: 3, depth: 3, segments: 16)

    /// A draped sheet comes back draped, particle for particle, still pinned
    /// where it was pinned. The twin is a sheet built fresh from the same mesh,
    /// which is flat and up in the air.
    @Test func aDrapedSheetComesBackDraped() throws {
        let world = World3D()
        world.ground = 0
        let cloth = try #require(world.addSoftBody(from: Self.sheet,
                                                   at: Vector3(0, 3, 0),
                                                   mass: 1.5, stiffness: 0.8,
                                                   pinned: { $0.z < -1.4 }))
        cloth.assetName = "sheet"
        run(world, steps: 240)
        let draped = cloth.particlePositions
        let pinned = (0 ..< cloth.particleCount).filter { cloth.isPinned($0) }
        #expect(!pinned.isEmpty, "some of it is held up")

        let back = World3D()
        back.ground = 0
        back.restore(world.snapshot()) { $0 == "sheet" ? .mesh(Self.sheet) : nil }
        let restored = try #require(back.softBodies.first)
        #expect(restored.particleCount == cloth.particleCount)
        let error = zip(draped, restored.particlePositions)
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error < 1e-6, "every particle came back where it was (\(error))")
        #expect((0 ..< restored.particleCount).filter { restored.isPinned($0) } == pinned,
                "and the same ones are still held")

        // The twin: built fresh, the same sheet is flat and has not fallen.
        let fresh = World3D()
        fresh.ground = 0
        let flat = try #require(fresh.addSoftBody(from: Self.sheet,
                                                  at: Vector3(0, 3, 0),
                                                  mass: 1.5, stiffness: 0.8,
                                                  pinned: { $0.z < -1.4 }))
        let spread = zip(draped, flat.particlePositions)
            .map { ($0 - $1).length }.max() ?? 0
        #expect(spread > 0.5, "a fresh sheet is nowhere near a draped one")
    }

    /// A soft body with no name is left out, because a soft body is nothing but
    /// its mesh. The twin is the same sheet with a name, which is saved.
    @Test func anUnnamedSoftBodyIsLeftOutRatherThanHalfSaved() throws {
        func saveAndRestore(naming: Bool) throws -> Int {
            let world = World3D()
            world.ground = 0
            let cloth = try #require(world.addSoftBody(from: Self.sheet,
                                                       at: Vector3(0, 3, 0)))
            if naming { cloth.assetName = "sheet" }
            run(world, steps: 120)
            let back = World3D()
            back.ground = 0
            back.restore(world.snapshot()) { $0 == "sheet" ? .mesh(Self.sheet) : nil }
            return back.softBodies.count
        }
        #expect(try saveAndRestore(naming: true) == 1)
        #expect(try saveAndRestore(naming: false) == 0)
    }

    /// A named soft body whose mesh nothing answers for is left out too, rather
    /// than failing the restore or coming back as something else.
    @Test func aSoftBodyWhoseMeshIsNotFoundIsLeftOut() throws {
        let world = World3D()
        world.ground = 0
        let cloth = try #require(world.addSoftBody(from: Self.sheet,
                                                   at: Vector3(0, 3, 0)))
        cloth.assetName = "sheet"
        world.addBody(.box(width: 1, height: 1, depth: 1), at: Vector3(4, 1, 0))
        run(world, steps: 120)

        let back = World3D()
        back.ground = 0
        back.restore(world.snapshot())          // no resolver
        #expect(back.softBodies.isEmpty)
        #expect(back.bodies.count == 1, "and the crate still came back")
    }

    /// Naming carries through a file, and the names can be read off a snapshot
    /// before anything is restored, which is how a sketch knows what to hand
    /// back.
    @Test func aNamedWorldSurvivesAFile() throws {
        let world = World3D()
        scenery(in: world, named: true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-named-\(UUID().uuidString).physics")
        defer { try? FileManager.default.removeItem(at: url) }
        try world.save(to: url)

        let read = try PhysicsSnapshot(contentsOf: url)
        #expect(read.assetNames == ["island", "knot"],
                "a sketch can ask what it will be needing")

        let back = World3D()
        #expect(back.load(contentsOf: url, resolving: resolver))
        #expect(back.bodies.count == world.bodies.count)
        let error = zip(world.bodies.map(\.position), back.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error == 0)
    }

    /// A named world restored and captured again gives the same bytes, name
    /// table and all.
    @Test func aNamedWorldRoundTripsToTheSameBytes() {
        let world = World3D()
        scenery(in: world, named: true)
        world.restore(world.snapshot(), resolving: resolver)
        let settled = world.snapshot()
        world.restore(settled, resolving: resolver)
        #expect(world.snapshot() == settled)
    }
}
