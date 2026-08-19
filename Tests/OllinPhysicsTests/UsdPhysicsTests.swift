import Foundation
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for reading physics somebody else authored: the `UsdPhysics`
/// annotations of a loaded scene become ordinary bodies and joints.
/// Behavioral, each answer pinned against a counterfactual twin, and every
/// attribute name checked against the schema rather than remembered.
struct UsdPhysicsTests {

    func run(_ world: World3D, steps: Int, dt: Double = 1.0 / 60) {
        for _ in 0 ..< steps { world.step(dt: dt) }
    }

    /// The hand-authored arrangement the Imported example runs.
    static let yardURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OllinPhysicsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Examples/3D/Physics/Imported/yard.usda")

    static func yard() throws -> Scene {
        try #require(Scene(contentsOf: Self.yardURL))
    }

    /// A scene written on the spot, so a test can say exactly what it is about
    /// rather than leaning on the shipped one.
    func scene(_ body: String) throws -> Scene {
        let text = """
        #usda 1.0
        (
            defaultPrim = "World"
            upAxis = "Y"
        )

        def Xform "World"
        {
        \(body)
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-usdphysics-\(UUID().uuidString).usda")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return try #require(Scene(contentsOf: url))
    }

    func body(_ world: World3D, _ name: String) throws -> Body3D {
        try #require(world.bodies.first { $0.assetName == name })
    }

    // MARK: What is a body at all

    /// The headline: the file says which prims are physical, and one call
    /// makes them. The twin is the same scene added to a world that reads no
    /// annotations, which gets nothing.
    @Test func aFileSaysWhichPrimsFall() throws {
        let world = World3D()
        let made = world.addBodies(from: try Self.yard(), applyGravity: true)
        #expect(made.count == world.bodies.count)
        #expect(made.count > 8, "the whole yard came across")
        #expect(world.joints.count == 2, "and both hinges")
        #expect(abs(world.gravity.y + 9.81) < 1e-5, "with the file's own gravity")

        // The twin: a scene with no physics annotations makes nothing.
        let bare = try scene("""
            def Cube "Crate"
            {
                double size = 1
            }
        """)
        let empty = World3D()
        #expect(empty.addBodies(from: bare).isEmpty)
    }

    /// A collider with no rigid body over it is scenery and never moves; one
    /// with a body falls. The twin is each against the other.
    @Test func aColliderWithoutABodyIsScenery() throws {
        let world = World3D()
        world.addBodies(from: try scene("""
            def Cube "Floor" (
                prepend apiSchemas = ["PhysicsCollisionAPI"]
            )
            {
                double size = 2
                double3 xformOp:scale = (4, 0.25, 4)
                uniform token[] xformOpOrder = ["xformOp:scale"]
            }

            def Cube "Faller" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            {
                double size = 1
                double3 xformOp:translate = (0, 4, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]
            }
        """))
        let floor = try body(world, "Floor")
        let faller = try body(world, "Faller")
        #expect(floor.kind == .static)
        #expect(faller.kind == .dynamic)

        let floorWas = floor.position
        run(world, steps: 240)
        #expect((floor.position - floorWas).length == 0, "the scenery held still")
        #expect(faller.position.y < 2, "and the body fell onto it")
        #expect(abs(faller.position.y - 0.75) < 0.05,
                "resting on the slab's top face rather than passing through")
    }

    /// `physics:kinematicEnabled` and `physics:rigidBodyEnabled = false` each
    /// change what a body is, and each against a plain dynamic twin.
    @Test func theMotionFlagsCarry() throws {
        let world = World3D()
        world.addBodies(from: try scene("""
            def Sphere "Falling" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            { double radius = 0.5 }

            def Sphere "Driven" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            {
                double radius = 0.5
                bool physics:kinematicEnabled = 1
            }

            def Sphere "Switched" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            {
                double radius = 0.5
                bool physics:rigidBodyEnabled = 0
            }
        """))
        #expect(try body(world, "Falling").kind == .dynamic)
        #expect(try body(world, "Driven").kind == .kinematic)
        #expect(try body(world, "Switched").kind == .static)
    }

    // MARK: Shapes

    /// A collider's shape is the prim's own geometry, and a scale on the prim
    /// is a bigger shape rather than a scaled body, since a solver's shapes
    /// carry no scale. The twin is the same prim unscaled.
    @Test func aScaledPrimIsABiggerShape() throws {
        func size(scaled: Bool) throws -> Double {
            let world = World3D()
            world.addBodies(from: try scene("""
                def Cube "Block" (
                    prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
                )
                {
                    double size = 2
                    \(scaled ? "double3 xformOp:scale = (3, 0.5, 3)" : "")
                    uniform token[] xformOpOrder = [\(scaled ? "\"xformOp:scale\"" : "")]
                }
            """))
            guard case .box(let width, _, _) = try body(world, "Block").collider else {
                return 0
            }
            return width
        }
        #expect(try size(scaled: false) == 2, "a cube's `size` is its whole width")
        #expect(try size(scaled: true) == 6, "and a scale multiplies it")
    }

    /// USD stands a capsule, cylinder, and cone on **z** unless told
    /// otherwise, where Ollin's stand on y, so the difference has to be baked
    /// into the shape's own turn. The twin is the same prim authored on y,
    /// which comes in upright.
    @Test func aCapsuleAuthoredOnZComesInLyingDown() throws {
        func settled(axis: String) throws -> Double {
            let world = World3D()
            world.ground = 0
            world.addBodies(from: try scene("""
                def Capsule "Rod" (
                    prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
                )
                {
                    double radius = 0.2
                    double height = 2
                    uniform token axis = "\(axis)"
                    double3 xformOp:translate = (0, 3, 0)
                    uniform token[] xformOpOrder = ["xformOp:translate"]
                }
            """))
            run(world, steps: 300)
            return try body(world, "Rod").position.y
        }
        // A rod on its side rests at its own radius; one standing up rests at
        // half its length plus a cap.
        let lying = try settled(axis: "Z")
        let upright = try settled(axis: "Y")
        #expect(abs(lying - 0.2) < 0.05,
                "a z-axis rod lands lying down, at its radius (\(lying))")
        #expect(upright > 0.9,
                "where a y-axis one stands up (\(upright))")
    }

    /// A rigid body owns everything under it, so several collider prims in one
    /// subtree fuse into one compound body. The twin is the same two shapes
    /// authored as their own bodies, which is two.
    @Test func collidersUnderOneBodyFuseIntoOne() throws {
        let fused = World3D()
        fused.addBodies(from: try scene("""
            def Xform "Tool" (
                prepend apiSchemas = ["PhysicsRigidBodyAPI"]
            )
            {
                def Cylinder "Handle" (
                    prepend apiSchemas = ["PhysicsCollisionAPI"]
                )
                {
                    double radius = 0.1
                    double height = 2
                    uniform token axis = "Y"
                }

                def Cube "Head" (
                    prepend apiSchemas = ["PhysicsCollisionAPI"]
                )
                {
                    double size = 0.5
                    double3 xformOp:translate = (0, 1, 0)
                    uniform token[] xformOpOrder = ["xformOp:translate"]
                }
            }
        """))
        #expect(fused.bodies.count == 1, "one body, not two")
        let tool = try body(fused, "Tool")
        guard case .compound(let parts) = tool.collider else {
            Issue.record("expected a compound collider, got \(tool.collider)")
            return
        }
        #expect(parts.count == 2)
        // The head sits a unit up inside the body, which is where the file put
        // it relative to the body prim.
        #expect(abs((parts[1].position - Vector3(0, 1, 0)).length) < 1e-9)

        // The twin: the same two shapes as their own bodies.
        let loose = World3D()
        loose.addBodies(from: try scene("""
            def Cylinder "Handle" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            { double radius = 0.1
              double height = 2
              uniform token axis = "Y" }

            def Cube "Head" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            { double size = 0.5 }
        """))
        #expect(loose.bodies.count == 2)
    }

    // MARK: Mass and material

    /// An authored mass is the body's mass, whatever its shape's volume would
    /// otherwise give. The twin is the same shape with no mass authored.
    @Test func anAuthoredMassWins() throws {
        let world = World3D()
        world.addBodies(from: try scene("""
            def Sphere "Light" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI", "PhysicsMassAPI"]
            )
            {
                double radius = 0.5
                float physics:mass = 3
            }

            def Sphere "Unsaid" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            { double radius = 0.5 }
        """))
        #expect(abs(try body(world, "Light").mass - 3) < 1e-4)
        #expect(try body(world, "Unsaid").mass > 100,
                "an unsaid mass comes from the volume, which for half a meter of water is a lot")
    }

    /// A bound physics material carries its friction and restitution. The twin
    /// is an identical ball with no material, which bounces less.
    @Test func aBoundMaterialCarriesItsBounce() throws {
        func height(bouncy: Bool) throws -> Double {
            let world = World3D()
            world.ground = 0
            world.bounce = 0.05
            world.addBodies(from: try scene("""
                def Sphere "Ball" (
                    prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI", "PhysicsMassAPI"]
                )
                {
                    \(bouncy ? "rel material:binding:physics = </World/Rubber>" : "")
                    float physics:mass = 1
                    double radius = 0.3
                    double3 xformOp:translate = (0, 4, 0)
                    uniform token[] xformOpOrder = ["xformOp:translate"]
                }

                def Material "Rubber" (
                    prepend apiSchemas = ["PhysicsMaterialAPI"]
                )
                {
                    float physics:dynamicFriction = 0.9
                    float physics:restitution = 0.85
                }
            """))
            let ball = try body(world, "Ball")
            var highest = 0.0
            // How high it comes back after the first landing.
            for _ in 0 ..< 200 { world.step(dt: 1.0 / 60) }
            for _ in 0 ..< 120 {
                world.step(dt: 1.0 / 60)
                highest = max(highest, ball.position.y)
            }
            return highest
        }
        let bouncy = try height(bouncy: true)
        let dull = try height(bouncy: false)
        #expect(bouncy > dull + 0.3,
                "the bound material's restitution carried: \(bouncy) against \(dull)")
    }

    /// Velocity and the starts-asleep flag come across.
    @Test func motionAndSleepCarry() throws {
        let world = World3D()
        world.addBodies(from: try scene("""
            def Sphere "Thrown" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            {
                double radius = 0.3
                vector3f physics:velocity = (4, 0, 0)
            }

            def Sphere "Settled" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI"]
            )
            {
                double radius = 0.3
                uniform bool physics:startsAsleep = 1
                double3 xformOp:translate = (5, 0, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]
            }
        """))
        #expect(abs(try body(world, "Thrown").velocity.x - 4) < 1e-5)
        #expect(try body(world, "Thrown").isAwake)
        #expect(try !body(world, "Settled").isAwake)
    }

    // MARK: Joints

    /// A hinge in the file is a hinge in the world: the plank tips about it
    /// and stays put. The twin is the same plank with the hinge taken away,
    /// which falls off its fulcrum.
    @Test func aHingeInTheFileHoldsTheBody() throws {
        func fell(hinged: Bool) throws -> Double {
            let world = World3D()
            world.ground = 0
            world.addBodies(from: try scene("""
                def Cube "Plank" (
                    prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI", "PhysicsMassAPI"]
                )
                {
                    double size = 2
                    float physics:mass = 4
                    double3 xformOp:translate = (0, 2, 0)
                    double3 xformOp:scale = (1.5, 0.05, 0.4)
                    uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scale"]
                }
                \(hinged ? """

                def PhysicsRevoluteJoint "Hinge"
                {
                    rel physics:body0 = </World/Plank>
                    uniform token physics:axis = "Z"
                    point3f physics:localPos0 = (0, 0, 0)
                }
                """ : "")
            """))
            run(world, steps: 240)
            return try body(world, "Plank").position.y
        }
        let held = try fell(hinged: true)
        let dropped = try fell(hinged: false)
        #expect(abs(held - 2) < 0.05, "the hinged plank stayed at its pivot (\(held))")
        #expect(dropped < 0.5, "where the free one fell to the floor (\(dropped))")
    }

    /// A hinge naming only one body holds it to the world, which needs no
    /// floor and no second body. The twin is a hinge naming both, which holds
    /// them to each other and lets the pair fall together.
    @Test func aJointNamingOneBodyHoldsItToTheWorld() throws {
        let world = World3D()
        world.addBodies(from: try scene("""
            def Cube "Sign" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI", "PhysicsMassAPI"]
            )
            {
                double size = 1
                float physics:mass = 2
                double3 xformOp:translate = (0, 3, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]
            }

            def PhysicsRevoluteJoint "Hinge"
            {
                rel physics:body0 = </World/Sign>
                uniform token physics:axis = "Z"
                point3f physics:localPos0 = (0, 0.5, 0)
            }
        """))
        #expect(world.joints.count == 1)
        run(world, steps: 300)
        let sign = try body(world, "Sign")
        #expect(sign.position.y > 2.3,
                "it is still hanging where the file pinned it (\(sign.position.y))")

        // The twin: no joint at all, and it is on the floor of nowhere.
        let free = World3D()
        free.addBodies(from: try scene("""
            def Cube "Sign" (
                prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI", "PhysicsMassAPI"]
            )
            {
                double size = 1
                float physics:mass = 2
                double3 xformOp:translate = (0, 3, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]
            }
        """))
        run(free, steps: 300)
        #expect(try body(free, "Sign").position.y < -5, "where an unjointed one falls")
    }

    /// A hinge's limits carry: a plank told it may swing 15° does not swing
    /// 60°. The twin is the same plank with no limits authored.
    @Test func aHingeKeepsTheLimitsTheFileGaveIt() throws {
        func swing(limited: Bool) throws -> Double {
            let world = World3D()
            world.addBodies(from: try scene("""
                def Cube "Arm" (
                    prepend apiSchemas = ["PhysicsCollisionAPI", "PhysicsRigidBodyAPI", "PhysicsMassAPI"]
                )
                {
                    double size = 2
                    float physics:mass = 3
                    double3 xformOp:translate = (0, 3, 0)
                    double3 xformOp:scale = (1.2, 0.05, 0.3)
                    uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scale"]
                }

                def PhysicsRevoluteJoint "Hinge"
                {
                    rel physics:body0 = </World/Arm>
                    uniform token physics:axis = "Z"
                    point3f physics:localPos0 = (-1, 0, 0)
                \(limited ? """
                    float physics:lowerLimit = -15
                    float physics:upperLimit = 15
                """ : "")
                }
            """))
            run(world, steps: 300)
            return abs(world.joints.first?.angle ?? 0)
        }
        let limited = try swing(limited: true)
        let loose = try swing(limited: false)
        #expect(limited < 20 * .pi / 180,
                "the limited arm stopped where the file said (\(limited) rad)")
        #expect(loose > limited + 0.3,
                "where the free one swung right down (\(loose) rad)")
    }

    // MARK: The shipped arrangement

    /// The example's own file, end to end, checked part by part so a change to
    /// it that breaks a rule shows up here.
    @Test func theShippedYardComesInAsAuthored() throws {
        let world = World3D()
        world.addBodies(from: try Self.yard(), applyGravity: true)

        #expect(try body(world, "Ground").kind == .static)
        #expect(try body(world, "Fulcrum").kind == .static)
        #expect(try body(world, "Plank").kind == .dynamic)
        #expect(abs(try body(world, "Weight").mass - 10) < 1e-4)

        // The hammer is one body wearing two shapes.
        guard case .compound(let parts) = try body(world, "Hammer").collider else {
            Issue.record("the hammer should be a compound")
            return
        }
        #expect(parts.count == 2)

        // The roller is a z-axis capsule, so it comes in turned onto its side.
        guard case .compound(let rolled) = try body(world, "Roller").collider,
              case .capsule = rolled[0].collider else {
            Issue.record("the roller should be a turned capsule")
            return
        }
        #expect(abs(rolled[0].angle - .pi / 2) < 1e-6)

        run(world, steps: 400)
        #expect(try body(world, "Weight").position.y > 0.3,
                "the weight came to rest on the plank rather than sliding off")
        #expect(try body(world, "Sign").position.y > 1.8, "the sign is still hung")
        #expect(abs(try body(world, "Roller").position.y - 0.28) < 0.05,
                "and the roller settled on its side, at its radius")
    }

    /// Everything read comes in as ordinary bodies, so it is all savable the
    /// way a hand-built world is.
    @Test func animportedWorldSnapshotsLikeAnyOther() throws {
        let world = World3D()
        world.addBodies(from: try Self.yard(), applyGravity: true)
        run(world, steps: 400)
        let settled = world.bodies.map(\.position)

        let back = World3D()
        back.restore(world.snapshot())
        #expect(back.bodies.count == world.bodies.count)
        let error = zip(settled, back.bodies.map(\.position))
            .map { ($0 - $1).length }.max() ?? .infinity
        #expect(error == 0)
        #expect(back.bodies.first?.assetName != nil, "the prim names came with it")
    }
}
