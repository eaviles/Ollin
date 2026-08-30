import Foundation
import simd
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for the ragdoll tier: a skinned figure becomes a tree of bodies
/// sized from its own mesh, the simulated pose comes back onto the skin exactly,
/// a powered figure holds a shape a limp one loses, and a cone-limited joint
/// stops where a free one keeps going. Behavioral (the no-pixel-snapshot policy
/// for physics), each knob pinned against a counterfactual twin: the same scene
/// run twice with one setting changed.
struct Ragdoll3DTests {

    /// The authored humanoid the Ragdoll example uses: sixteen joints, one
    /// skinned mesh, and a looping "wave" animation.
    static let figureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OllinPhysicsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Examples/3D/Physics/Ragdoll/figure.gltf")

    static func figure() throws -> Scene {
        try #require(Scene(contentsOf: figureURL))
    }

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.advance(by: dt) }
    }

    func limb(_ ragdoll: Ragdoll3D, _ name: String) throws -> Ragdoll3D.Limb {
        try #require(ragdoll.limbs.first { $0.name == name })
    }

    /// Every limb's offset from the root, in the root's own frame, so a figure
    /// that has fallen over still reads as holding its shape.
    func shape(of ragdoll: Ragdoll3D) -> [Vector3] {
        guard let root = ragdoll.limbs.first?.body else { return [] }
        let q = root.quaternion
        let inverse = simd_inverse(simd_quatf(ix: q.0, iy: q.1, iz: q.2, r: q.3))
        let origin = root.position
        return ragdoll.limbs.map { limb in
            let d = limb.body.position - origin
            let v = inverse.act(SIMD3<Float>(Float(d.x), Float(d.y), Float(d.z)))
            return Vector3(Double(v.x), Double(v.y), Double(v.z))
        }
    }

    /// How far the figure has folded away from the shape it was built in, per
    /// limb, averaged.
    func shapeError(_ ragdoll: Ragdoll3D, from rest: [Vector3]) -> Double {
        let now = shape(of: ragdoll)
        guard now.count == rest.count, !rest.isEmpty else { return .infinity }
        return zip(now, rest).map { ($0 - $1).length }.reduce(0, +) / Double(rest.count)
    }

    // MARK: Building the figure

    @Test func buildsOneLimbPerSkeletonJoint() throws {
        let scene = try Self.figure()
        let world = World3D()
        let ragdoll = try #require(world.addRagdoll(from: scene))

        #expect(ragdoll.limbs.count == 16)
        // Parents before children, so the root comes first.
        #expect(ragdoll.limbs.first?.name == "hips")
        #expect(Set(ragdoll.limbs.map(\.name)).isSuperset(of: ["head", "forearmL",
                                                              "shinR", "footL"]))
        // The limbs are simulated bodies, but not ones a drawing loop asked
        // for: the sketch draws the mesh they carry.
        #expect(world.bodies.isEmpty)
        #expect(world.ragdolls.count == 1)
        for limb in ragdoll.limbs {
            #expect(world.bodyByID[limb.body.id] === limb.body)
        }
    }

    @Test func limbShapesAreFittedToTheMeshNotTheBone() throws {
        let scene = try Self.figure()
        let world = World3D()
        let ragdoll = try #require(world.addRagdoll(from: scene))

        func radius(_ name: String) throws -> Double {
            switch try limb(ragdoll, name).collider {
            case .capsule(_, let radius), .sphere(let radius): return radius
            default: return 0
            }
        }
        // The figure's own proportions: a torso is thick and a forearm thin,
        // though the bones behind them are much closer in length.
        let torso = try radius("spine")
        let forearm = try radius("forearmL")
        #expect(torso > 2.5 * forearm)
        // Left and right are mirror images, so their fits match.
        #expect(abs(try radius("forearmL") - (try radius("forearmR"))) < 1e-3)
        // A limb's shape is pushed out along its bone from the joint it hangs
        // at, rather than centered on it: the upper arm reaches outward.
        let armL = try limb(ragdoll, "armL")
        #expect(armL.shapeCenter.x > 0.08)
        #expect(try limb(ragdoll, "armR").shapeCenter.x < -0.08)
    }

    @Test func massIsSplitBetweenTheLimbsByHowMuchOfTheFigureTheyFill() throws {
        let scene = try Self.figure()
        let world = World3D()
        let ragdoll = try #require(world.addRagdoll(from: scene, mass: 70))

        let total = ragdoll.limbs.map(\.body.mass).reduce(0, +)
        #expect(abs(total - 70) < 0.5)
        // A thigh outweighs a hand.
        #expect(try limb(ragdoll, "legL").body.mass
            > limb(ragdoll, "handL").body.mass)
        // Twice the figure means twice every limb.
        let heavier = World3D()
        let heavy = try #require(heavier.addRagdoll(from: scene, mass: 140))
        #expect(abs(heavy.limbs.map(\.body.mass).reduce(0, +) - 140) < 1)
    }

    @Test func standsWhereItIsAskedTo() throws {
        let scene = try Self.figure()
        let world = World3D()
        let placed = try #require(world.addRagdoll(from: scene, at: Vector3(2, 5, -1)))
        #expect((placed.position - Vector3(2, 5, -1)).length < 1e-4)

        // With no placement it keeps the pose the file authored (hips at 0.95).
        let asAuthored = World3D()
        let authored = try #require(asAuthored.addRagdoll(from: scene))
        #expect(abs(authored.position.y - 0.95) < 1e-4)
        #expect(abs(authored.position.x) < 1e-4)
    }

    @Test func aSceneWithNoSkinBuildsNoRagdoll() {
        let world = World3D()
        let plain = Scene(nodes: [SceneNode(name: "block", mesh: Mesh.box(width: 1,
                                                                         height: 1,
                                                                         depth: 1))])
        #expect(world.addRagdoll(from: plain) == nil)
        #expect(world.ragdolls.isEmpty)
    }

    @Test func namedJointsBecomeLimbsAndTheRestRideThem() throws {
        let scene = try Self.figure()
        let world = World3D()
        let ragdoll = try #require(world.addRagdoll(
            from: scene, joints: ["spine", "armL", "armR", "legL", "legR"]))

        // The five named joints plus the root, which is always kept: a figure
        // with nothing to hang off would be a pile of loose parts.
        #expect(ragdoll.limbs.count == 6)
        #expect(ragdoll.limbs.first?.name == "hips")
        #expect(!ragdoll.limbs.contains { $0.name == "forearmL" })
        // The forearm's flesh went to the arm that now carries it, so that limb
        // reaches further than it would have on its own.
        let everyJoint = World3D()
        let whole = try #require(everyJoint.addRagdoll(from: scene))
        func reach(_ r: Ragdoll3D) throws -> Double {
            let arm = try limb(r, "armL")
            guard case .capsule(let height, let radius) = arm.collider else { return 0 }
            return height / 2 + radius
        }
        #expect(try reach(ragdoll) > 1.6 * (try reach(whole)))
    }

    // MARK: The pose, both ways

    @Test func theSkinFollowsTheSimulatedBodies() throws {
        var scene = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: scene, at: Vector3(0, 1.2, 0)))
        run(world, steps: 40)
        scene.apply(ragdoll)

        // Each joint node lands exactly on its limb: the body transform *is*
        // the joint transform, so the write-back has nothing to undo.
        let worlds = scene.nodeWorldTransforms()
        for (index, source) in ragdoll.jointSource.enumerated() {
            let node = try #require(worlds[source])
            let posed = Vector3(Double(node.columns.3.x), Double(node.columns.3.y),
                                Double(node.columns.3.z))
            #expect((posed - ragdoll.limbs[index].body.position).length < 1e-5)
        }
        // And it is no longer standing: the head came down with the rest.
        let head = try #require(scene.skeleton().first { $0.name == "head" })
        let headWorld = try #require(worlds[head.sourceIndex])
        #expect(Double(headWorld.columns.3.y) < 1.4)
    }

    @Test func jointsTheRagdollSkippedRideTheLimbAboveThem() throws {
        var scene = try Self.figure()
        let world = World3D()
        let ragdoll = try #require(world.addRagdoll(from: scene, joints: ["armL", "armR"]))
        let elbowBefore = try #require(scene.node("forearmL")).position

        // Lift the arm that *is* simulated, then pose the scene from it.
        try limb(ragdoll, "armL").body.position = Vector3(0, 4, 0)
        scene.apply(ragdoll)

        // The elbow was not simulated, so its local pose is untouched and it
        // simply travels with the arm it hangs off.
        let elbowAfter = try #require(scene.node("forearmL")).position
        #expect((elbowAfter - elbowBefore).length < 1e-5)
        let worlds = scene.nodeWorldTransforms()
        let source = try #require(scene.skeleton().first { $0.name == "forearmL" })
            .sourceIndex
        let elbowWorld = try #require(worlds[source])
        #expect(abs(Double(elbowWorld.columns.3.y) - 4) < 1e-4)
    }

    @Test func poseFromASceneStandsTheFigureBackUp() throws {
        let rest = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: rest, at: Vector3(0, 1.2, 0)))
        let built = shape(of: ragdoll)
        run(world, steps: 150)
        #expect(shapeError(ragdoll, from: built) > 0.2)   // it fell in a heap

        ragdoll.pose(from: rest)
        #expect(shapeError(ragdoll, from: built) < 1e-4)
        // Back where the file authored it, not where it landed.
        #expect(abs(ragdoll.position.y - 0.95) < 1e-3)
        #expect(ragdoll.limbs.allSatisfy { $0.body.velocity.length < 1e-6 })
    }

    // MARK: Powered against limp

    @Test func aPoweredFigureHoldsItsShapeWhereALimpOneCollapses() throws {
        let rest = try Self.figure()
        var errors: [Double] = []
        for powered in [false, true] {
            let world = World3D()
            world.ground = 0
            let ragdoll = try #require(world.addRagdoll(from: rest,
                                                        at: Vector3(0, 1.2, 0)))
            let built = shape(of: ragdoll)
            for _ in 0..<180 {
                if powered { ragdoll.drive(toward: rest) }
                world.advance(by: 1.0 / 60)
            }
            errors.append(shapeError(ragdoll, from: built))
        }
        // Same drop, same figure, one difference: the limp one folds up on
        // landing, the powered one arrives still holding its pose.
        #expect(errors[0] > 0.25)
        #expect(errors[1] < 0.08)
        #expect(errors[0] > 4 * errors[1])
    }

    @Test func goingLimpGivesUpAPoseThatWasBeingHeld() throws {
        let rest = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: rest, at: Vector3(0, 1.2, 0)))
        let built = shape(of: ragdoll)
        for _ in 0..<120 {
            ragdoll.drive(toward: rest)
            world.advance(by: 1.0 / 60)
        }
        let held = shapeError(ragdoll, from: built)
        #expect(held < 0.08)

        ragdoll.goLimp()
        run(world, steps: 120)
        #expect(shapeError(ragdoll, from: built) > 2 * held)
    }

    @Test func aWeakerMotorLetsTheFigureSagFurther() throws {
        let rest = try Self.figure()
        var errors: [Double] = []
        for strength in [4.0, 400.0] {
            let world = World3D()
            world.ground = 0
            let ragdoll = try #require(world.addRagdoll(from: rest,
                                                        at: Vector3(0, 1.2, 0)))
            let built = shape(of: ragdoll)
            for _ in 0..<180 {
                ragdoll.drive(toward: rest, strength: strength)
                world.advance(by: 1.0 / 60)
            }
            errors.append(shapeError(ragdoll, from: built))
        }
        // The one thing changed is how hard a joint may pull.
        #expect(errors[0] > 2 * errors[1])
    }

    @Test func aKinematicFigureFollowsThePoseThroughWhateverIsInTheWay() throws {
        var target = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: target, at: Vector3(0, 0, 0)))
        ragdoll.kind = .kinematic
        // A crate right where the figure's arm will sweep.
        let crate = world.addBody(.box(width: 0.3, height: 0.3, depth: 0.3),
                                  at: Vector3(0.55, 1.48, 0))
        let crateStart = crate.position

        // Walk the whole figure sideways: nothing may stop it.
        for step in 0..<120 {
            for index in target.nodes.indices where target.nodes[index].name == "hips" {
                target.nodes[index].position = Vector3(Double(step) * 0.01, 0.95, 0)
            }
            ragdoll.drive(toward: target)
            world.advance(by: 1.0 / 60)
        }
        #expect(ragdoll.position.x > 1.0)
        // And it shoved the crate out of the way on its way through.
        #expect((crate.position - crateStart).length > 0.2)
    }

    // MARK: Limits

    @Test func aConeLimitedJointStopsWhereAFreeOneKeepsGoing() {
        /// A rod sticking out sideways from a small fixed post, hung on one
        /// joint at the post, left to fall under gravity. The rod's center
        /// height says how far it got: 0 is still horizontal, -0.5 is hanging
        /// straight down.
        func drop(_ kind: (Vector3, Vector3) -> JointKind3D) -> Double {
            let world = World3D()
            let post = world.addBody(.box(width: 0.04, height: 0.04, depth: 0.04),
                                     at: .zero, kind: .static)
            let rod = world.addBody(.capsule(height: 0.8, radius: 0.06),
                                    at: Vector3(0.55, 0, 0), rotated: .pi / 2,
                                    axis: .unitZ)
            world.connect(post, rod, kind(.zero, .unitX))
            for _ in 0..<300 { world.advance(by: 1.0 / 60) }
            return rod.position.y
        }
        let free = drop { at, _ in .ball(at: at) }
        let limited = drop { at, axis in
            .swingTwist(at: at, axis: axis, swing: 20 * .pi / 180)
        }
        // The free joint lets the rod hang straight down; the cone catches it
        // barely off horizontal.
        #expect(free < -0.4)
        #expect(limited > -0.25)
        #expect(limited > free + 0.2)
    }

    @Test func aTighterConeHoldsTheFigureStraighter() throws {
        let scene = try Self.figure()
        var errors: [Double] = []
        for swing in [10 * Double.pi / 180, 80 * Double.pi / 180] {
            let world = World3D()
            world.ground = 0
            let ragdoll = try #require(world.addRagdoll(from: scene,
                                                        at: Vector3(0, 1.2, 0),
                                                        swing: swing))
            let built = shape(of: ragdoll)
            run(world, steps: 180)
            errors.append(shapeError(ragdoll, from: built))
        }
        // Same fall, same figure: the loose one crumples further.
        #expect(errors[1] > 1.5 * errors[0])
    }

    @Test func retuningOneJointsLimitLoosensOnlyThatJoint() throws {
        let scene = try Self.figure()

        /// How far an elbow has folded: the angle between the two arm bones.
        func bend(_ ragdoll: Ragdoll3D, _ side: String) throws -> Double {
            let arm = try limb(ragdoll, "arm\(side)").body.position
            let elbow = try limb(ragdoll, "forearm\(side)").body.position
            let wrist = try limb(ragdoll, "hand\(side)").body.position
            let upper = (elbow - arm).normalized
            let lower = (wrist - elbow).normalized
            return acos(max(-1, min(1, upper.dot(lower))))
        }

        var bends: [(left: Double, right: Double)] = []
        for loosen in [false, true] {
            // Hung by the hips with the arms out, so nothing but gravity and
            // the limits decides where they end up.
            let world = World3D()
            let ragdoll = try #require(world.addRagdoll(from: scene,
                                                        swing: 6 * .pi / 180))
            ragdoll.limbs[0].body.kind = .kinematic
            if loosen { ragdoll.limit("forearmL", swing: 100 * .pi / 180) }
            run(world, steps: 180)
            bends.append((try bend(ragdoll, "L"), try bend(ragdoll, "R")))
        }
        // A tight figure hangs almost straight-armed on both sides.
        #expect(bends[0].left < 12 * .pi / 180)
        #expect(bends[0].right < 12 * .pi / 180)
        // Loosening one elbow folds that arm and leaves its twin alone.
        #expect(bends[1].left > 3 * bends[0].left)
        #expect(bends[1].right < bends[1].left / 3)
    }

    // MARK: Living among the other bodies

    @Test func limbsLandOnTheGroundAndSaySo() throws {
        let scene = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: scene, at: Vector3(0, 1.2, 0)))

        var landed: Set<String> = []
        for _ in 0..<180 {
            world.advance(by: 1.0 / 60)
            for contact in world.contacts where contact.phase == .began {
                guard contact.involves(try #require(world.groundBody)) else { continue }
                let other = contact.other(than: try #require(world.groundBody))
                if let name = ragdoll.limbs.first(where: { $0.body === other })?.name {
                    landed.insert(name)
                }
            }
        }
        // The floor names limbs, not anonymous handles.
        #expect(landed.count >= 3)
        // And it comes to rest above the floor rather than sinking through it.
        #expect(ragdoll.limbs.allSatisfy { $0.body.position.y > -0.3 })
    }

    @Test func neighbouringLimbsDoNotFightEachOther() throws {
        let scene = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: scene, at: Vector3(0, 1.05, 0)))
        run(world, steps: 300)

        // A figure whose overlapping limbs collided would shake itself apart:
        // it stays one figure, in one place, at rest.
        let root = ragdoll.position
        for limbBody in ragdoll.bodies {
            #expect(limbBody.position.x.isFinite)
            #expect((limbBody.position - root).length < 1.5)
            #expect(limbBody.velocity.length < 1.0)
        }
        #expect(root.length < 5)
    }

    @Test func twoFiguresCollideWithEachOther() throws {
        let scene = try Self.figure()
        let world = World3D()
        world.ground = 0
        let lower = try #require(world.addRagdoll(from: scene, at: Vector3(0, 0.95, 0)))
        let upper = try #require(world.addRagdoll(from: scene, at: Vector3(0, 3.4, 0)))

        // The group filter that stops one figure's own limbs from colliding is
        // per figure, so the dropped one lands *on* the standing one rather
        // than falling through it.
        let upperIDs = Set(upper.bodies.map(\.id))
        let lowerIDs = Set(lower.bodies.map(\.id))
        var betweenFigures = 0
        for _ in 0..<200 {
            world.advance(by: 1.0 / 60)
            for contact in world.contacts where contact.phase == .began {
                let ids = [contact.a, contact.b].compactMap(world.identifier(of:))
                if ids.contains(where: upperIDs.contains),
                   ids.contains(where: lowerIDs.contains) {
                    betweenFigures += 1
                }
            }
        }
        #expect(betweenFigures > 0)
        // The counterfactual is inside a figure: a limb and the one it hangs
        // off overlap the whole time (a thigh sits inside the pelvis) and never
        // report a touch, because a figure's own joints are filtered out while
        // another figure's are not.
        for ragdoll in [lower, upper] {
            for limb in ragdoll.limbs {
                guard let parent = limb.parent else { continue }
                #expect(!limb.body.isTouching(ragdoll.limbs[parent].body))
            }
        }
    }

    @Test func anImpulseThrowsTheWholeFigure() throws {
        let scene = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: scene, at: Vector3(0, 1.2, 0)))
        let built = shape(of: ragdoll)
        // One impulse for the whole 72 kg figure: about 5 m/s downrange.
        ragdoll.applyImpulse(Vector3(0, 0, 360))
        run(world, steps: 45)

        // It traveled, and it traveled together: every limb took the same
        // change in velocity, so the shove alone does not fold the figure.
        #expect(ragdoll.position.z > 2)
        #expect(shapeError(ragdoll, from: built) < 0.22)
    }

    @Test func removingAFigureTakesItsLimbsWithIt() throws {
        let scene = try Self.figure()
        let world = World3D()
        world.ground = 0
        let ragdoll = try #require(world.addRagdoll(from: scene, at: Vector3(0, 1.2, 0)))
        let ids = ragdoll.bodies.map(\.id)
        run(world, steps: 30)
        world.remove(ragdoll)

        #expect(world.ragdolls.isEmpty)
        for id in ids { #expect(world.bodyByID[id] == nil) }
        // The world keeps stepping with no figure in it.
        run(world, steps: 30)
        #expect(world.contacts.allSatisfy { contact in
            [contact.a, contact.b].compactMap(world.identifier(of:))
                .allSatisfy { !ids.contains($0) }
        })
    }

    // MARK: Determinism

    @Test func theSameFallReplaysIdentically() throws {
        let scene = try Self.figure()
        func fall() throws -> [Vector3] {
            let world = World3D()
            world.ground = 0
            let ragdoll = try #require(world.addRagdoll(from: scene,
                                                        at: Vector3(0.2, 1.4, -0.1)))
            run(world, steps: 200)
            return ragdoll.bodies.map(\.position)
        }
        let first = try fall()
        let second = try fall()
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) { #expect(a == b) }
    }
}
