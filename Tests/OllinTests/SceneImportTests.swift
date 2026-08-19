import Foundation
import Testing
import simd
import OllinProjects
@testable import OllinSceneImport
@testable import Ollin

/// Whether a real scene file turns into the right description.
///
/// The headline is the first test: the moves written into a sketch have to
/// compose back to the transform the file authored. If they do, the parts land
/// where `drawScene` would put them, which is the whole claim the feature makes.
@Suite("Scene import")
struct SceneImportTests {

    static var sampleScene: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OllinTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Examples/3D/Geometry/LoadedScene/scene.gltf")
    }

    // MARK: - The placements

    /// Composing what the sketch will call has to land on the matrix the file
    /// authored, node for node. A wrong axis, a dropped scale, or the wrong
    /// order would move a part, and this is what would catch it.
    @Test("Every placement composes back to the node's own transform")
    func placementsComposeBackToTheAuthoredTransform() throws {
        let opened = Ollin.Scene(contentsOf: Self.sampleScene)
        let scene = try #require(opened)
        let described = SceneImport.read(Self.sampleScene)
        let imported = try #require(described)

        var checked = 0
        func compare(_ authored: [SceneNode], _ described: [ImportedSceneNode]) {
            #expect(authored.count == described.count,
                    "the description has to mirror the tree, or nothing below lines up")
            for (node, description) in zip(authored, described) {
                let rebuilt = Self.compose(description)
                let original = Self.asDouble(node.localTransform)
                #expect(Self.matches(rebuilt, original),
                        "\(node.name) would be placed somewhere else than the file put it")
                checked += 1
                compare(node.children, description.children)
            }
        }
        compare(scene.nodes, imported.roots)
        #expect(checked >= 6, "the sample scene should have exercised several nodes, saw \(checked)")
    }

    @Test("A known transform splits into the moves that built it")
    func aKnownTransformSplits() {
        let turn = simd_quatd(angle: 0.7, axis: simd_normalize(SIMD3<Double>(0.3, 1, 0.2)))
        var built = matrix_identity_double4x4
        built.columns.3 = SIMD4(1.5, -2, 0.25, 1)
        built = built * simd_double4x4(turn)
        built = built * simd_double4x4(diagonal: SIMD4(2, 3, 0.5, 1))

        let node = SceneNode(name: "n", mesh: nil, children: [],
                             localTransform: Self.asFloat(built))
        let placement = node.placement

        #expect(placement.isExact)
        #expect(abs(placement.translation.x - 1.5) < 1e-5)
        #expect(abs(placement.translation.y + 2) < 1e-5)
        #expect(abs(placement.scale.x - 2) < 1e-5)
        #expect(abs(placement.scale.y - 3) < 1e-5)
        #expect(abs(placement.scale.z - 0.5) < 1e-5)
        #expect(abs(placement.angle - 0.7) < 1e-5)
    }

    /// The counterfactual for the test above: if the moves were composed in the
    /// other order, they would not land on the same matrix. Without this, a test
    /// that checked the composition could pass while the emitter printed the
    /// calls in an order that draws something else.
    @Test("Scaling before turning is a different transform, so the order is load-bearing")
    func theOrderOfTheMovesMatters() {
        let turn = simd_quatd(angle: 0.7, axis: simd_normalize(SIMD3<Double>(0.3, 1, 0.2)))
        let scale = simd_double4x4(diagonal: SIMD4<Double>(2, 3, 0.5, 1))
        let rotateThenScale = simd_double4x4(turn) * scale
        let scaleThenRotate = scale * simd_double4x4(turn)
        #expect(!Self.matches(rotateThenScale, scaleThenRotate),
                "a non-uniform scale does not commute with a turn; if it did, this suite proves nothing")
    }

    /// A transform that is not translate, rotate and scale cannot be written as
    /// those three, and saying so is better than printing a placement that is
    /// quietly wrong.
    @Test("A sheared transform reports that it cannot be reproduced")
    func shearIsReported() {
        var sheared = matrix_identity_double4x4
        sheared.columns.1 = SIMD4(0.6, 1, 0, 0)     // y leans along x
        let node = SceneNode(name: "skew", mesh: nil, children: [],
                             localTransform: Self.asFloat(sheared))
        #expect(!node.placement.isExact)

        // And the honest case still reads as exact, so the flag means something.
        let plain = SceneNode(name: "plain", mesh: nil, children: [],
                              localTransform: Self.asFloat(matrix_identity_double4x4))
        #expect(plain.placement.isExact)
    }

    // MARK: - Parts

    /// The generated sketch walks the file itself, taking each node before its
    /// children. The names it uses are written out at generation time, so the two
    /// walks have to agree or every part would draw as the wrong shape.
    @Test("Part names follow the same walk the generated sketch uses")
    func partNamesFollowTheGeneratedWalk() throws {
        let opened = Ollin.Scene(contentsOf: Self.sampleScene)
        let scene = try #require(opened)
        let described = SceneImport.read(Self.sampleScene)
        let imported = try #require(described)

        // The walk as the emitted loader spells it.
        var meshOrder: [String] = []
        func visit(_ nodes: [SceneNode]) {
            for node in nodes {
                if node.mesh != nil { meshOrder.append(node.name) }
                visit(node.children)
            }
        }
        visit(scene.nodes)

        // The walk as the description carries it.
        var describedOrder: [String] = []
        func walk(_ nodes: [ImportedSceneNode]) {
            for node in nodes {
                if let part = node.part { describedOrder.append(part) }
                walk(node.children)
            }
        }
        walk(imported.roots)

        #expect(describedOrder == imported.partNames,
                "the tree and the written list have to name the parts in one order")
        #expect(describedOrder.count == meshOrder.count,
                "one name per mesh the loader will find")
        #expect(imported.needsResource)
        #expect(imported.resourceFileName == "scene.gltf")
    }

    @Test("A repeated name still gets a part of its own")
    func repeatedNamesAreMadeUnique() {
        var namer = SceneImport.PartNamer()
        #expect(namer.name(for: "wheel") == "wheel")
        #expect(namer.name(for: "wheel") == "wheel-2")
        #expect(namer.name(for: "wheel") == "wheel-3")
        #expect(namer.name(for: "  ") == "part", "a blank name still has to be reachable")
        #expect(namer.assigned.count == 4)
        #expect(Set(namer.assigned).count == 4, "two parts sharing a key would draw as one shape")
    }

    // MARK: - Camera and lights

    @Test("The camera is the one the file authored")
    func theCameraIsTheAuthoredOne() throws {
        let opened = Ollin.Scene(contentsOf: Self.sampleScene)
        let scene = try #require(opened)
        let authored = try #require(scene.camera)
        let read = SceneImport.read(Self.sampleScene)
        let imported = try #require(read)
        let mineCamera = try #require(imported.camera)

        #expect(abs(mineCamera.eye.x - authored.eye.x) < 1e-4)
        #expect(abs(mineCamera.eye.y - authored.eye.y) < 1e-4)
        #expect(abs(mineCamera.eye.z - authored.eye.z) < 1e-4)
        #expect(abs(mineCamera.target.y - authored.target.y) < 1e-4)
        if case .perspective(let mine) = mineCamera.projection,
           case .perspective(let theirs) = authored.projection {
            #expect(abs(mine - theirs) < 1e-4)
        } else {
            Issue.record("the sample scene authors a perspective camera")
        }
    }

    /// With no camera in the file the sketch would open on nothing, so one is
    /// worked out from the scene's own size and said so.
    @Test("A file with no camera gets one that frames what it holds")
    func aMissingCameraIsWorkedOut() throws {
        let opened = Ollin.Scene(contentsOf: Self.sampleScene)
        var scene = try #require(opened)
        scene.cameras = []     // assigning fixes the array, so no node camera resolves

        var notes: [String] = []
        let framed = try #require(SceneImport.camera(of: scene, notes: &notes))
        #expect(notes.contains { $0.contains("no camera") })

        // It has to be outside the scene, looking at the middle of it.
        let bounds = scene.bounds
        let center = (bounds.min + bounds.max) * 0.5
        let eye = Vector3(framed.eye.x, framed.eye.y, framed.eye.z)
        #expect((eye - center).length > (bounds.max - bounds.min).length / 2,
                "the camera should stand off the scene rather than inside it")
        #expect(abs(framed.target.y - center.y) < 1e-6)
    }

    @Test("Lights keep their kind, their place and their color")
    func lightsCarryOver() throws {
        let opened = Ollin.Scene(contentsOf: Self.sampleScene)
        let scene = try #require(opened)
        let described = SceneImport.read(Self.sampleScene)
        let imported = try #require(described)

        #expect(imported.lights.count == scene.lights.count)
        #expect(!imported.lights.isEmpty, "the sample scene authors lights")

        for (described, authored) in zip(imported.lights, scene.lights) {
            switch (described.kind, authored.kind) {
            case (.directional, .directional), (.point, .point), (.spot, .spot),
                 (.rect, .rect), (.disk, .disk), (.tube, .tube):
                break
            default:
                Issue.record("a \(authored.kind) light came over as \(described.kind)")
            }
            #expect(abs(described.position.x - authored.position.x) < 1e-4)
            #expect(abs(described.intensity - authored.intensity) < 1e-6)
        }
    }

    // MARK: - What is left behind

    @Test("What cannot come over is written down rather than dropped")
    func lossesAreReported() throws {
        let described = SceneImport.read(Self.sampleScene)
        let imported = try #require(described)

        // The sample scene's pedestal wears two materials, which is exactly the
        // difference between this and drawScene, so it has to be said.
        #expect(imported.notes.contains { $0.contains("more than one material") })

        var marked = 0
        func walk(_ nodes: [ImportedSceneNode]) {
            for node in nodes {
                if node.note?.contains("several materials") == true { marked += 1 }
                walk(node.children)
            }
        }
        walk(imported.roots)
        #expect(marked == 1, "the note belongs on the one part it is about, saw \(marked)")
    }

    @Test("A file that will not open is refused rather than half-read")
    func anUnreadableFileIsRefused() throws {
        let bogus = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-scene-\(UUID().uuidString).gltf")
        try "this is not a scene".write(to: bogus, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: bogus) }
        #expect(SceneImport.read(bogus) == nil)
    }

    // MARK: - Helpers

    static func compose(_ node: ImportedSceneNode) -> simd_double4x4 {
        var m = matrix_identity_double4x4
        if let t = node.translation {
            var move = matrix_identity_double4x4
            move.columns.3 = SIMD4(t.x, t.y, t.z, 1)
            m = m * move
        }
        if let r = node.rotation {
            let axis = simd_normalize(SIMD3<Double>(r.axis.x, r.axis.y, r.axis.z))
            m = m * simd_double4x4(simd_quatd(angle: r.angle, axis: axis))
        }
        if let s = node.scale {
            m = m * simd_double4x4(diagonal: SIMD4(s.x, s.y, s.z, 1))
        }
        return m
    }

    static func matches(_ a: simd_double4x4, _ b: simd_double4x4, tolerance: Double = 1e-3) -> Bool {
        for column in 0..<4 {
            for row in 0..<4 where abs(a[column][row] - b[column][row]) > tolerance { return false }
        }
        return true
    }

    static func asDouble(_ m: simd_float4x4) -> simd_double4x4 {
        simd_double4x4(columns: (SIMD4<Double>(m.columns.0), SIMD4<Double>(m.columns.1),
                                 SIMD4<Double>(m.columns.2), SIMD4<Double>(m.columns.3)))
    }

    static func asFloat(_ m: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                                SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }
}
