import Foundation
import simd
import Testing
import Ollin
@testable import OllinPhysics

/// Correctness for cloth a skeleton carries: a cape follows the figure it was
/// hung on, each leash holds it exactly as far as it was told to, and the
/// long-range attachments stop a hung sheet stretching. Behavioral (the
/// no-pixel-snapshot policy for physics), each knob pinned against a
/// counterfactual twin: the same cape run twice with one setting changed.
struct SkinnedCloth3DTests {

    /// The authored humanoid the Ragdoll and Cape examples use: sixteen joints,
    /// one skinned mesh.
    static let figureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // OllinPhysicsTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("Examples/3D/Physics/Ragdoll/figure.gltf")

    /// A cape: a sheet lying in the xz plane, stood upright by the body's own
    /// rotation, so in mesh space `z` runs from the collar to the hem.
    static let sheet = Mesh.plane(width: 0.8, depth: 1.1, segments: 12)

    static func figure() throws -> Scene {
        try #require(Scene(contentsOf: figureURL))
    }

    func chest(of scene: Scene) throws -> Vector3 {
        let joint = try #require(scene.skeleton().first { $0.name == "chest" })
        return Vector3(Double(joint.world.columns.3.x),
                       Double(joint.world.columns.3.y),
                       Double(joint.world.columns.3.z))
    }

    /// Hang a cape on a figure, clasped along its collar.
    func cape(in world: World3D, on scene: Scene?, sway: Double? = nil,
              backStop: Double? = nil, maxStretch: Double? = nil) throws -> SoftBody3D {
        try #require(world.addSoftBody(
            from: Self.sheet, at: Vector3(0, 0.9, -0.13),
            rotated: .pi / 2, axis: Vector3(1, 0, 0),
            mass: 0.6, stiffness: 0.9, bend: 0.02, damping: 0.2,
            pinned: { $0.z < -0.5 },
            skinnedTo: scene,
            carriedBy: scene == nil ? nil : { _ in "chest" },
            sway: sway.map { distance in { _ in distance } },
            backStop: backStop, maxStretch: maxStretch))
    }

    /// Slide a whole skeleton along x, the way a figure walking would, without
    /// touching anything else about the pose.
    func walk(_ scene: Scene, to x: Double) -> Scene {
        var moved = scene
        var worlds: [Int: simd_float4x4] = [:]
        for joint in scene.skeleton() {
            var world = joint.world
            world.columns.3.x += Float(x)
            worlds[joint.sourceIndex] = world
        }
        moved.setJointWorlds(worlds)
        return moved
    }

    /// Walk a figure back and forth, posing the cape each frame, and report the
    /// furthest any particle got from where the skin put it. The skin here is a
    /// pure translation of the rest shape, so that distance is exact.
    @discardableResult
    func stride(_ cape: SoftBody3D, on figure: Scene, in world: World3D,
                steps: Int = 300, amplitude: Double = 0.7,
                measuringAfter settle: Int = 90) -> Double {
        let rest = cape.particlePositions
        var worst = 0.0
        for step in 0 ..< steps {
            let x = sin(Double(step) / 60 * 3) * amplitude
            cape.follow(walk(figure, to: x))
            world.advance(by: 1.0 / 60)
            guard step > settle else { continue }
            for (index, point) in cape.particlePositions.enumerated() {
                let skinned = Vector3(rest[index].x + x, rest[index].y, rest[index].z)
                worst = max(worst, (point - skinned).length)
            }
        }
        return worst
    }

    // MARK: Being carried

    @Test func aCarriedCapeGoesWhereTheFigureGoes() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try cape(in: world, on: figure)
        #expect(cape.isSkinned)

        for step in 0 ..< 240 {
            cape.follow(walk(figure, to: Double(step) / 240 * 2))
            world.advance(by: 1.0 / 60)
        }
        let carried = cape.position.x
        #expect(abs(carried - 2) < 0.1,
                "a cape hung on a figure that walked to x=2 read \(carried)")
    }

    /// The twin: the same cloth with no skeleton behind it. Its collar is
    /// pinned to the *world*, so the figure walks out from under it.
    @Test func aClothNoSkeletonCarriesStaysWhereItWasPinned() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cloth = try cape(in: world, on: nil)
        #expect(!cloth.isSkinned)

        for step in 0 ..< 240 {
            cloth.follow(walk(figure, to: Double(step) / 240 * 2))
            world.advance(by: 1.0 / 60)
        }
        #expect(abs(cloth.position.x) < 0.05,
                "an unskinned cloth moved to x=\(cloth.position.x)")
    }

    /// A cape that has hung still long enough to settle and go to sleep still
    /// answers the figure the moment it moves, which needs the pose change to
    /// wake it.
    @Test func aSettledCapeStillFollowsAFigureThatWalksAway() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try cape(in: world, on: figure)
        for _ in 0 ..< 900 {
            cape.follow(figure)
            world.advance(by: 1.0 / 60)
        }
        #expect(!cape.isAwake, "the cape never settled, so this proves nothing")

        for step in 0 ..< 180 {
            cape.follow(walk(figure, to: Double(step) / 180 * 1.5))
            world.advance(by: 1.0 / 60)
        }
        #expect(abs(cape.position.x - 1.5) < 0.1,
                "a settled cape read \(cape.position.x) after the figure walked to 1.5")
    }

    // MARK: The leash

    @Test func swayIsADistanceInWorldUnits() throws {
        for leash in [0.02, 0.05, 0.1] {
            let figure = try Self.figure()
            let world = World3D()
            world.ground = 0
            let cape = try cape(in: world, on: figure, sway: leash)
            let worst = stride(cape, on: figure, in: world)
            #expect(worst <= leash * 1.05,
                    "a sway of \(leash) let a particle get \(worst) from the skin")
            #expect(worst > leash * 0.5,
                    "a sway of \(leash) was never taken up (worst \(worst))")
        }
    }

    /// The twin: the same cape on no leash at all swings much further.
    @Test func aFreeCapeLeavesTheSkinFurtherThanASwayWouldAllow() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try cape(in: world, on: figure)
        let worst = stride(cape, on: figure, in: world)
        #expect(worst > 0.2, "a free cape only reached \(worst) from the skin")
    }

    @Test func aSwayOfZeroHoldsTheClothExactlyOnTheSkin() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try cape(in: world, on: figure, sway: 0)
        let worst = stride(cape, on: figure, in: world)
        #expect(worst < 1e-4, "a hard-skinned cape drifted \(worst) from the skin")
    }

    /// Cutting the skin loose leaves only the clasp following, so the same cape
    /// on the same walk leaves the skin far further behind.
    @Test func cuttingTheSkinLooseLetsTheClothGo() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try cape(in: world, on: figure, sway: 0.03)
        let held = stride(cape, on: figure, in: world)
        cape.followsSkin = false
        let loose = stride(cape, on: figure, in: world)
        #expect(held <= 0.035, "a held cape reached \(held)")
        #expect(loose > held * 5,
                "cutting the skin loose changed the reach from \(held) to \(loose)")
    }

    /// One number lets the whole surface out without rebuilding it.
    @Test func swayScaleLoosensTheWholeSurfaceAtOnce() throws {
        var reach: [Double] = []
        for scale in [1.0, 4.0] {
            let figure = try Self.figure()
            let world = World3D()
            world.ground = 0
            let cape = try cape(in: world, on: figure, sway: 0.03)
            cape.swayScale = scale
            reach.append(stride(cape, on: figure, in: world))
        }
        #expect(reach[1] > reach[0] * 2,
                "scaling the sway by 4 changed the reach from \(reach[0]) to \(reach[1])")
    }

    // MARK: The back stop

    @Test func theBackStopHoldsTheClothOffTheFigure() throws {
        var pushed: [Double] = []
        for stop in [nil, 0.04] as [Double?] {
            let figure = try Self.figure()
            let world = World3D()
            world.ground = 0
            let cape = try cape(in: world, on: figure, backStop: stop)
            let rest = cape.particlePositions
            var deepest = -Double.infinity
            for step in 0 ..< 300 {
                // Blow it forward, into the back it hangs on.
                cape.applyForce(Vector3(0, 0, 8))
                cape.follow(figure)
                world.advance(by: 1.0 / 60)
                guard step > 120 else { continue }
                for (index, point) in cape.particlePositions.enumerated() {
                    deepest = max(deepest, point.z - rest[index].z)
                }
            }
            pushed.append(deepest)
        }
        #expect(pushed[1] < 0.05,
                "a back stop of 0.04 let the cloth \(pushed[1]) past the skin")
        #expect(pushed[0] > 0.3,
                "with no back stop the cloth only reached \(pushed[0]) past the skin")
    }

    // MARK: Long range attachments

    /// A sheet pinned along one edge stretches under its own weight; capped at
    /// its rest length it hangs exactly as long as it is.
    @Test func maxStretchStopsAHungSheetStretching() throws {
        var lowest: [Double] = []
        for stretch in [nil, 1.0] as [Double?] {
            let world = World3D()
            world.ground = -20
            let cloth = try #require(world.addSoftBody(
                from: Mesh.plane(width: 2, depth: 2, segments: 16),
                at: Vector3(0, 4, 0), rotated: .pi / 2, axis: Vector3(1, 0, 0),
                mass: 8, stiffness: 0.4, damping: 0.1,
                pinned: { $0.z < -0.95 }, maxStretch: stretch))
            for _ in 0 ..< 600 { world.advance(by: 1.0 / 60) }
            lowest.append(cloth.particlePositions.min { $0.y < $1.y }!.y)
        }
        // The sheet hangs from y = 5 and is 2 long, so its rest hem is y = 3.
        #expect(abs(lowest[1] - 3) < 0.01,
                "an inextensible sheet hung to \(lowest[1]) rather than 3")
        #expect(lowest[0] < 2.95,
                "an uncapped sheet hung to \(lowest[0]), which is no stretch at all")
    }

    /// The anchors a cape's attachments measure from are held by the *skin*,
    /// not pinned to the world, which is why a particle held exactly on the
    /// skin has to be kinematic.
    @Test func maxStretchWorksFromAnchorsTheSkinHolds() throws {
        var lowest: [Double] = []
        for stretch in [nil, 1.0] as [Double?] {
            let figure = try Self.figure()
            let world = World3D()
            world.ground = 0
            let cape = try #require(world.addSoftBody(
                from: Self.sheet, at: Vector3(0, 0.9, -0.13),
                rotated: .pi / 2, axis: Vector3(1, 0, 0),
                mass: 6, stiffness: 0.3, damping: 0.2,
                pinned: { $0.z < -0.5 },
                skinnedTo: figure, carriedBy: { _ in "chest" },
                maxStretch: stretch))
            for _ in 0 ..< 600 {
                cape.follow(figure)
                world.advance(by: 1.0 / 60)
            }
            lowest.append(cape.particlePositions.min { $0.y < $1.y }!.y)
        }
        #expect(lowest[1] > lowest[0] + 0.03,
                "capping a carried cape moved its hem \(lowest[0]) to \(lowest[1])")
    }

    // MARK: Standing it somewhere else

    @Test func snappingCarriesEveryParticleToTheNewPose() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try cape(in: world, on: figure, sway: 0.05)
        stride(cape, on: figure, in: world, steps: 120)

        cape.snap(to: walk(figure, to: 10))
        let points = cape.particlePositions
        let mean = points.reduce(Vector3.zero) { $0 + $1 } / Double(points.count)
        #expect(abs(mean.x - 10) < 0.05,
                "a snapped cape stood at x=\(mean.x) rather than 10")
    }

    // MARK: Names it does not know

    @Test func aJointNoSkeletonHasLeavesThatPartOrdinaryCloth() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try #require(world.addSoftBody(
            from: Self.sheet, at: Vector3(0, 0.9, -0.13),
            rotated: .pi / 2, axis: Vector3(1, 0, 0),
            pinned: { $0.z < -0.5 },
            skinnedTo: figure,
            // Only the collar names a joint the figure has.
            carriedBy: { $0.z < -0.5 ? "chest" : "tail" }))
        #expect(cape.isSkinned)
        #expect(cape.skinning.vertices.count < cape.particleCount,
                "every particle was carried, so the unknown name was not skipped")
    }

    // MARK: Saving one

    @Test func aCarriedCapeSurvivesASnapshot() throws {
        let figure = try Self.figure()
        let world = World3D()
        world.ground = 0
        let cape = try cape(in: world, on: figure, sway: 0.05, backStop: 0.03,
                            maxStretch: 1.02)
        cape.assetName = "cape"
        stride(cape, on: figure, in: world, steps: 120)
        let saved = world.snapshot()

        let rebuilt = World3D()
        rebuilt.ground = 0
        rebuilt.restore(saved) { $0 == "cape" ? .mesh(Self.sheet) : nil }
        let back = try #require(rebuilt.softBodies.first)
        #expect(back.isSkinned)
        #expect(back.skinning.vertices.count == cape.skinning.vertices.count)
        #expect(back.skinning.binds.count == cape.skinning.binds.count)

        var worst = 0.0
        for (a, b) in zip(cape.particlePositions, back.particlePositions) {
            worst = max(worst, (a - b).length)
        }
        #expect(worst < 1e-6, "a restored cape's particles were \(worst) out")

        // And it answers a figure it has never seen: the bind pose it was hung
        // in comes back out of the inverse binds, so a later pose still means
        // the motion since.
        let moved = walk(figure, to: 3)
        for _ in 0 ..< 180 {
            back.follow(moved)
            rebuilt.advance(by: 1.0 / 60)
        }
        #expect(abs(back.position.x - 3) < 0.1,
                "a restored cape read \(back.position.x) after its figure stood at 3")
    }

    /// A world with a cape in it replays exactly, the way every other tier
    /// does.
    @Test func aCarriedCapeReplaysIdentically() throws {
        func run() throws -> [Vector3] {
            let figure = try Self.figure()
            let world = World3D()
            world.ground = 0
            let cape = try cape(in: world, on: figure, sway: 0.05)
            stride(cape, on: figure, in: world, steps: 200)
            return cape.particlePositions
        }
        let first = try run(), second = try run()
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.x == b.x && a.y == b.y && a.z == b.z)
        }
    }
}
