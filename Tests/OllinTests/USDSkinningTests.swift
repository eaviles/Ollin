import CoreGraphics
import Foundation
import simd
#if canImport(ModelIO)
import ModelIO
#endif
@testable import Ollin
import Testing

/// UsdSkel skinning and blend shapes (stage 4 of the USD-native arc): the
/// Skeleton prim synthesized into joint nodes, the deforming mesh rebuilt on
/// its authored points, the skel primvars expanded into per-vertex influences
/// (elementSize, rigid constant bindings, the skel:joints remap), blend-shape
/// offsets landed dense and sparse, SkelAnimation channels and blend-shape
/// weights bound by node identity, and the whole path from
/// `Scene(contentsOf:)` through `apply(_:at:)` to hand-derived skinned
/// positions. The crate container is pinned against the system usdcat writer,
/// and the bind-matrix decode against the platform importer's own skeleton
/// read.
@Suite
@MainActor
struct USDSkinningTests {

    /// Write a usda string to a temp file and load it as a `Scene` (the
    /// native walk plus the skinning attach).
    private func loadUSDScene(_ usda: String) throws -> Ollin.Scene? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return Scene(contentsOf: url)
    }

    /// A two-joint arm: a 2-unit column of 8 points, the bottom ring bound to
    /// `Base` and the top ring to `Base/Tip` (elementSize 1), the tip bending
    /// 90 degrees about z over one second, plus one sparse blend shape
    /// ("bulge", pushing points 1 and 3 outward) whose weight ramps 0 to 1.
    /// The knobs vary the binding for the per-feature tests; the defaults are
    /// the canonical arm.
    private func armUSDA(rootOps: String = "",
                         meshExtras: String = "",
                         jointIndices: String = "[0, 0, 0, 0, 1, 1, 1, 1]",
                         jointWeights: String = "[1, 1, 1, 1, 1, 1, 1, 1]",
                         elementSize: Int = 1,
                         interpolation: String = "vertex") -> String {
        """
        #usda 1.0
        (
            defaultPrim = "Model"
            metersPerUnit = 1
            upAxis = "Y"
            startTimeCode = 0
            endTimeCode = 24
            timeCodesPerSecond = 24
        )

        def SkelRoot "Model" (
            prepend apiSchemas = ["SkelBindingAPI"]
        )
        {
            \(rootOps)
            def Skeleton "Skel" (
                prepend apiSchemas = ["SkelBindingAPI"]
            )
            {
                uniform token[] joints = ["Base", "Base/Tip"]
                uniform matrix4d[] bindTransforms = [((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)), ((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 1, 0, 1))]
                uniform matrix4d[] restTransforms = [((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)), ((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 1, 0, 1))]
                rel skel:animationSource = </Model/Skel/Anim>

                def SkelAnimation "Anim"
                {
                    uniform token[] joints = ["Base/Tip"]
                    float3[] translations.timeSamples = {
                        0: [(0, 1, 0)],
                        24: [(0, 1, 0)],
                    }
                    quatf[] rotations.timeSamples = {
                        0: [(1, 0, 0, 0)],
                        24: [(0.7071068, 0, 0, 0.7071068)],
                    }
                    half3[] scales.timeSamples = {
                        0: [(1, 1, 1)],
                        24: [(1, 1, 1)],
                    }
                    uniform token[] blendShapes = ["bulge"]
                    float[] blendShapeWeights.timeSamples = {
                        0: [0],
                        24: [1],
                    }
                }
            }

            def Mesh "Arm" (
                prepend apiSchemas = ["SkelBindingAPI"]
            )
            {
                uniform token subdivisionScheme = "none"
                point3f[] points = [(-0.2, 0, 0.2), (0.2, 0, 0.2), (0.2, 0, -0.2), (-0.2, 0, -0.2), (-0.2, 2, 0.2), (0.2, 2, 0.2), (0.2, 2, -0.2), (-0.2, 2, -0.2)]
                int[] faceVertexCounts = [4, 4, 4, 4, 4, 4]
                int[] faceVertexIndices = [0, 1, 5, 4, 1, 2, 6, 5, 2, 3, 7, 6, 3, 0, 4, 7, 4, 5, 6, 7, 3, 2, 1, 0]
                rel skel:skeleton = </Model/Skel>
                \(meshExtras)
                int[] primvars:skel:jointIndices = \(jointIndices) (
                    elementSize = \(elementSize)
                    interpolation = "\(interpolation)"
                )
                float[] primvars:skel:jointWeights = \(jointWeights) (
                    elementSize = \(elementSize)
                    interpolation = "\(interpolation)"
                )
                uniform token[] skel:blendShapes = ["bulge"]
                rel skel:blendShapeTargets = [</Model/Arm/bulge>]

                def BlendShape "bulge"
                {
                    uniform vector3f[] offsets = [(0.3, 0, 0), (-0.3, 0, 0)]
                    uniform int[] pointIndices = [1, 3]
                }
            }
        }
        """
    }

    private var arm: String { armUSDA() }

    /// The arm's node posed by the scene's animation at `time`, through the
    /// same walk `drawScene` runs.
    private func posedArm(_ scene: Ollin.Scene, at time: Double) throws -> Mesh {
        var posed = scene
        let animation = try #require(posed.animations.first)
        posed.apply(animation, at: time)
        let worlds = posed.nodeWorldTransforms()
        let node = try #require(posed.node("Arm"))
        let base = try #require(node.mesh)
        let shaped = node.morphedMesh() ?? base
        let si = try #require(node.skinIndex)
        return try #require(node.skinnedMesh(shaped, skin: posed.skins[si], worlds: worlds))
    }

    // MARK: The synthesized skeleton

    @Test func skeletonSynthesizesJointNodes() throws {
        let scene = try #require(try loadUSDScene(arm))
        // The container carries the Skeleton prim's name; joints nest by
        // their path hierarchy, each based at its local rest transform.
        let container = try #require(scene.node("Skel"))
        #expect(container.children.count == 1)
        let base = container.children[0]
        #expect(base.name == "Base" && base.children.count == 1)
        let tip = base.children[0]
        #expect(tip.name == "Tip")
        #expect(simd_length(tip.localTransform.columns.3 - SIMD4<Float>(0, 1, 0, 1)) < 1e-6)
        // Real identity: the platform tree carries none, so the joints' own
        // indices are unambiguous.
        #expect(base.sourceIndex != nil && tip.sourceIndex != nil)
    }

    @Test func deformingMeshKeepsAuthoredPointsIndexed() throws {
        let scene = try #require(try loadUSDScene(arm))
        let node = try #require(scene.node("Arm"))
        let mesh = try #require(node.mesh)
        // The rebuilt mesh is the authored 8 points, not an expanded copy,
        // so every skel primvar and blend-shape offset aligns by index.
        #expect(mesh.positions.count == 8)
        #expect((mesh.positions[5] - Vector3(0.2, 2, 0.2)).length < 1e-6)
        #expect(mesh.indices.count == 6 * 2 * 3)   // six quads fanned
        #expect(node.vertexJoints.count == 8 && node.vertexWeights.count == 8)
        #expect(scene.skins.count == 1)
    }

    // MARK: The skinning math

    @Test func bindPoseIsTheAuthoredMesh() throws {
        let scene = try #require(try loadUSDScene(arm))
        let posed = try posedArm(scene, at: 0)
        let original = try #require(scene.node("Arm")?.mesh)
        for (a, b) in zip(posed.positions, original.positions) {
            #expect((a - b).length < 1e-5)
        }
    }

    @Test func skinnedMeshBendsThroughApply() throws {
        // At 1 s the tip joint is T(0,1,0) · R(90 deg about z): the top ring
        // swings to the left. Point 5 (0.2, 2, 0.2): the inverse bind takes it
        // to (0.2, 1, 0.2) in tip space, the rotation sends it to
        // (-1, 0.2, 0.2), the translation lands it at (-1, 1.2, 0.2).
        let scene = try #require(try loadUSDScene(arm))
        #expect(scene.animations.first?.duration == 1)
        let posed = try posedArm(scene, at: 1)
        #expect((posed.positions[5] - Vector3(-1, 1.2, 0.2)).length < 1e-4)
        // The bottom ring rides the un-animated base joint: only the bulge
        // (fully applied at 1 s) moves point 1, +0.3 in x.
        #expect((posed.positions[1] - Vector3(0.5, 0, 0.2)).length < 1e-5)
    }

    @Test func skeletonWorldCarriesTheSkinnedMesh() throws {
        // The same arm with the whole SkelRoot moved +3 x: joint worlds pick
        // up the chain, so even the bind pose lands shifted.
        let moved = armUSDA(rootOps: """
            double3 xformOp:translate = (3, 0, 0)
                    uniform token[] xformOpOrder = ["xformOp:translate"]
            """)
        let scene = try #require(try loadUSDScene(moved))
        let posed = try posedArm(scene, at: 0)
        #expect((posed.positions[1] - Vector3(3.2, 0, 0.2)).length < 1e-4)
    }

    @Test func twoInfluencesBlendAtElementSizeTwo() throws {
        // The top ring bound half to Base, half to Tip: the posed point is
        // the midpoint of the two joints' images (matrix blending is linear).
        let blended = armUSDA(
            jointIndices: "[0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1]",
            jointWeights: "[1, 0, 1, 0, 1, 0, 1, 0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]",
            elementSize: 2)
        let scene = try #require(try loadUSDScene(blended))
        let posed = try posedArm(scene, at: 1)
        // Base leaves point 5 at (0.2, 2, 0.2); Tip sends it to (-1, 1.2, 0.2).
        #expect((posed.positions[5] - Vector3(-0.4, 1.6, 0.2)).length < 1e-4)
    }

    @Test func constantInterpolationBindsRigidly() throws {
        // One shared element rides every point: the whole mesh follows Tip.
        let rigid = armUSDA(jointIndices: "[1]", jointWeights: "[1]",
                            interpolation: "constant")
        let scene = try #require(try loadUSDScene(rigid))
        let posed = try posedArm(scene, at: 1)
        // Point 1 bulges first to (0.5, 0, 0.2) (morphs apply before the
        // skin), sits at (0.5, -1, 0.2) in tip space, rotates to
        // (1, 0.5, 0.2), and lands at (1, 1.5, 0.2). A skin applied before
        // the morph would land at (1.3, 1.2, 0.2), so this also pins the
        // deform order.
        #expect((posed.positions[1] - Vector3(1, 1.5, 0.2)).length < 1e-4)
    }

    @Test func skelJointsRemapReordersMeshLocalIndices() throws {
        // The mesh declares its own joint order (Tip first), so index 0 in the
        // primvars now means Tip: swapping the primvar values keeps the pose
        // identical to the unremapped arm.
        let remapped = armUSDA(
            meshExtras: "uniform token[] skel:joints = [\"Base/Tip\", \"Base\"]",
            jointIndices: "[1, 1, 1, 1, 0, 0, 0, 0]")
        let scene = try #require(try loadUSDScene(remapped))
        let posed = try posedArm(scene, at: 1)
        #expect((posed.positions[5] - Vector3(-1, 1.2, 0.2)).length < 1e-4)
        #expect((posed.positions[1] - Vector3(0.5, 0, 0.2)).length < 1e-5)
    }

    // MARK: Blend shapes

    @Test func sparseOffsetsLandOnTheirPoints() throws {
        let scene = try #require(try loadUSDScene(arm))
        let node = try #require(scene.node("Arm"))
        #expect(node.weights == [0])
        let target = try #require(node.morphTargets.first)
        #expect(target.positionDeltas.count == 8)
        #expect((target.positionDeltas[1] - Vector3(0.3, 0, 0)).length < 1e-6)
        #expect((target.positionDeltas[3] - Vector3(-0.3, 0, 0)).length < 1e-6)
        #expect(target.positionDeltas[0] == .zero && target.positionDeltas[5] == .zero)
    }

    @Test func weightsChannelDrivesTheTargetsByName() throws {
        // The blendShapeWeights ramp 0 to 1 over the second; halfway the
        // bulge is half applied.
        let scene = try #require(try loadUSDScene(arm))
        var posed = scene
        let animation = try #require(posed.animations.first)
        posed.apply(animation, at: 0.5)
        #expect(posed.node("Arm")?.weights == [0.5])
        let morphed = try #require(posed.node("Arm")?.morphedMesh())
        #expect((morphed.positions[1] - Vector3(0.35, 0, 0.2)).length < 1e-5)
    }

    // MARK: The merged animation

    @Test func xformAndSkelTracksMergeIntoOneAnimation() throws {
        // A spinning prop beside the skinned arm: one animation carries the
        // prop's xform track, the joint tracks, and the weights track, every
        // one bound by node identity, its duration the later of the two
        // timelines.
        let combined = arm.replacingOccurrences(
            of: "def Mesh \"Arm\" (",
            with: """
            def Xform "prop"
                {
                    float xformOp:rotateY.timeSamples = {
                        0: 0,
                        48: 360,
                    }
                    uniform token[] xformOpOrder = ["xformOp:rotateY"]
                }

                def Mesh "Arm" (
            """)
        let scene = try #require(try loadUSDScene(combined))
        #expect(scene.animations.count == 1)
        let animation = try #require(scene.animations.first)
        #expect(animation.duration == 2)
        let prop = try #require(scene.node("prop"))
        let tip = try #require(scene.node("Tip"))
        let armNode = try #require(scene.node("Arm"))
        #expect(animation.tracks.contains { $0.nodeIndex == prop.sourceIndex })
        #expect(animation.tracks.contains { $0.rotation != nil && $0.nodeIndex == tip.sourceIndex })
        #expect(animation.tracks.contains { $0.weights != nil && $0.nodeIndex == armNode.sourceIndex })
    }

    // MARK: The crate container

    /// The same rig authored as text and converted to crate by the system
    /// usdcat must resolve identically: the matrix4d[] bind decode, the token
    /// order, the primvar metadata (elementSize, interpolation), the sparse
    /// blend shape, and every SkelAnimation channel.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/usr/bin/usdcat")))
    func crateAgreesWithTextOnSkinning() throws {
        let dir = FileManager.default.temporaryDirectory
        let stem = "ollin-\(ProcessInfo.processInfo.globallyUniqueString)"
        let textURL = dir.appendingPathComponent(stem + ".usda")
        let crateURL = dir.appendingPathComponent(stem + ".usdc")
        try arm.write(to: textURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: textURL)
            try? FileManager.default.removeItem(at: crateURL)
        }
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/usdcat")
        convert.arguments = [textURL.path, "-o", crateURL.path]
        try convert.run()
        convert.waitUntilExit()
        try #require(convert.terminationStatus == 0)

        let fromText = try #require(Scene(contentsOf: textURL))
        let fromCrate = try #require(Scene(contentsOf: crateURL))

        let textArm = try #require(fromText.node("Arm"))
        let crateArm = try #require(fromCrate.node("Arm"))
        #expect(textArm.mesh?.positions == crateArm.mesh?.positions)
        #expect(textArm.vertexJoints == crateArm.vertexJoints)
        #expect(textArm.vertexWeights == crateArm.vertexWeights)
        #expect(textArm.morphTargets.first?.positionDeltas
            == crateArm.morphTargets.first?.positionDeltas)
        #expect(fromText.skins.count == fromCrate.skins.count)
        for (a, b) in zip(fromText.skins, fromCrate.skins) {
            #expect(a.joints == b.joints)
            #expect(a.inverseBind == b.inverseBind)
        }

        let textAnim = try #require(fromText.animations.first)
        let crateAnim = try #require(fromCrate.animations.first)
        #expect(textAnim.duration == crateAnim.duration)
        #expect(textAnim.tracks.count == crateAnim.tracks.count)
        for (a, b) in zip(textAnim.tracks, crateAnim.tracks) {
            #expect(a.nodeIndex == b.nodeIndex)
            #expect(a.translation?.values == b.translation?.values)
            #expect(a.rotation?.values == b.rotation?.values)
            #expect(a.scale?.values == b.scale?.values)
            #expect(a.weights?.values == b.weights?.values)
        }

        // The posed result agrees to float precision.
        let posedText = try posedArm(fromText, at: 1)
        let posedCrate = try posedArm(fromCrate, at: 1)
        for (a, b) in zip(posedText.positions, posedCrate.positions) {
            #expect((a - b).length < 1e-5)
        }
    }

    // MARK: The loop wrap

    /// The committed pond asset wraps seamlessly: frames one authored lap
    /// apart sample the same animation time and must render byte-identically
    /// (apply is absolute, and nothing else in the probe reads the clock).
    @Test(.enabled(if: Snapshot.hasMetal))
    func exampleAssetWrapsByteIdentically() throws {
        let before = try #require(OllinApp.image(of: USDPondWrapProbe(), frame: 5))
        let after = try #require(OllinApp.image(of: USDPondWrapProbe(), frame: 21))
        #expect(rgba(before) == rgba(after))
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    // MARK: The platform oracle

    #if canImport(ModelIO)
    /// The platform importer reads the same skeleton (its joint attributes
    /// are unusable, but its bind-matrix read is a fair reference): our
    /// resolved inverse binds must invert to its jointBindTransforms.
    @Test func bindMatricesAgreeWithThePlatformSkeletonRead() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usda")
        try arm.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let scene = try #require(Scene(contentsOf: url))
        let skin = try #require(scene.skins.first)

        let asset = MDLAsset(url: url)
        var mdlSkeleton: MDLSkeleton?
        func find(_ obj: MDLObject) {
            if let s = obj as? MDLSkeleton { mdlSkeleton = s }
            for child in obj.children.objects { find(child) }
        }
        for i in 0..<asset.count { find(asset.object(at: i)) }
        let skeleton = try #require(mdlSkeleton)
        let binds = skeleton.jointBindTransforms.float4x4Array
        #expect(binds.count == skin.inverseBind.count)
        for (inverse, reference) in zip(skin.inverseBind, binds) {
            let recovered = inverse.inverse   // geomBind is the identity here
            for c in 0..<4 {
                #expect(simd_length(recovered[c] - reference[c]) < 1e-5)
            }
        }
    }
    #endif
}

/// The wrap probe: the committed pond asset applied at half-second steps
/// wrapped over its 8-second lap, so frame 5 (2.0 s) and frame 21 (10.0 s,
/// wrapped to 2.0 s) must pose, and render, identically. Frame-count-driven so
/// the sample times are exact.
private final class USDPondWrapProbe: Sketch {
    override var canvasSize: CanvasSize { .square(192) }
    private var pond: Ollin.Scene!

    override func setup() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/SkinnedScene/stage.usda")
        pond = Ollin.Scene(contentsOf: url)
    }

    override func draw() {
        background(Color(white: 0.05))
        camera(pond.camera ?? .orbiting(target: Vector3(0, 0.8, 0), radius: 6))
        ambientLight(Color(white: 0.2))
        for l in pond.lights { light(l) }
        if let lap = pond.animations.first {
            let t = Double(frameCount - 1) * 0.5
            pond.apply(lap, at: t.truncatingRemainder(dividingBy: lap.duration))
        }
        fill(.white)
        drawScene(pond)
    }
}
