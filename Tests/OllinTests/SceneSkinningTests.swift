import CoreGraphics
import Foundation
import simd
@testable import Ollin
import Testing

/// The deforming tier of scene animation: skins (joint parsing, inverse bind
/// matrices, per-vertex joint/weight attributes, the posed blend against
/// hand-computed positions, the skinned-node-transform-is-ignored rule) and
/// morph targets (dense and sparse displacement parsing, default-weight
/// precedence, the blended mesh against hand-computed positions, the
/// morph-weights animation channel in both linear and cubic layouts).
@Suite
@MainActor
struct SceneSkinningTests {

    // MARK: Fixtures

    /// A two-joint vertical bar: six vertices in three rows, the bottom row
    /// bound to joint 0, the middle row split 50/50, the top row bound to
    /// joint 1 (which sits at height 1, its inverse bind matrix the matching
    /// translation down). One animation "bend" swings joint 1 ninety degrees
    /// about z. The skinned node itself carries a translation of (5, 0, 0)
    /// that the format requires renderers to ignore.
    private static var skinBufferB64: String {
        var buffer = Data()
        func put(_ floats: [Float]) {
            for f in floats { withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) } }
        }
        // positions @ 0 (72 bytes)
        put([-0.1, 0, 0,  0.1, 0, 0,  -0.1, 1, 0,  0.1, 1, 0,  -0.1, 2, 0,  0.1, 2, 0])
        // normals @ 72 (72)
        put([0, 0, 1,  0, 0, 1,  0, 0, 1,  0, 0, 1,  0, 0, 1,  0, 0, 1])
        // WEIGHTS_0 @ 144 (96): weights pair with JOINTS_0 slot-wise, so the
        // top rows put their whole weight in slot x, whose joint index is 1.
        put([1, 0, 0, 0,  1, 0, 0, 0,  0.5, 0.5, 0, 0,  0.5, 0.5, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0])
        // inverse bind matrices @ 240 (128): identity, then translate(0, -1, 0)
        put([1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1])
        put([1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, -1, 0, 1])
        // times @ 368 (8), rotation values @ 376 (32): identity -> 90 deg about z
        put([0, 1])
        let half: Float = 0.7071068
        put([0, 0, 0, 1,  0, 0, half, half])
        // JOINTS_0 @ 408 (24, unsigned bytes)
        buffer.append(contentsOf: [0, 0, 0, 0,  0, 0, 0, 0,  0, 1, 0, 0,
                                   0, 1, 0, 0,  1, 0, 0, 0,  1, 0, 0, 0] as [UInt8])
        // indices @ 432 (24, unsigned shorts)
        for v: UInt16 in [0, 1, 3,  0, 3, 2,  2, 3, 5,  2, 5, 4] {
            withUnsafeBytes(of: v) { buffer.append(contentsOf: $0) }
        }
        return buffer.base64EncodedString()
    }

    private func skinnedJSON(barTranslation: [Double] = [5, 0, 0]) -> String {
        """
        { "asset": {"version": "2.0"},
          "scene": 0,
          "scenes": [{"name": "Bar", "nodes": [0, 2]}],
          "nodes": [
            {"name": "root", "children": [1]},
            {"name": "tip", "translation": [0, 1, 0]},
            {"name": "bar", "mesh": 0, "skin": 0, "translation": \(barTranslation)}
          ],
          "skins": [{"joints": [0, 1], "inverseBindMatrices": 3}],
          "meshes": [{"primitives": [{
            "attributes": {"POSITION": 0, "NORMAL": 1, "JOINTS_0": 6, "WEIGHTS_0": 2},
            "indices": 7, "mode": 4}]}],
          "animations": [
            {"name": "bend",
             "channels": [{"sampler": 0, "target": {"node": 1, "path": "rotation"}}],
             "samplers": [{"input": 4, "output": 5, "interpolation": "LINEAR"}]}
          ],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 6, "type": "VEC3",
             "min": [-0.1, 0, 0], "max": [0.1, 2, 0]},
            {"bufferView": 1, "componentType": 5126, "count": 6, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 6, "type": "VEC4"},
            {"bufferView": 3, "componentType": 5126, "count": 2, "type": "MAT4"},
            {"bufferView": 4, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
            {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 6, "componentType": 5121, "count": 6, "type": "VEC4"},
            {"bufferView": 7, "componentType": 5123, "count": 12, "type": "SCALAR"}
          ],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 72},
            {"buffer": 0, "byteOffset": 72, "byteLength": 72},
            {"buffer": 0, "byteOffset": 144, "byteLength": 96},
            {"buffer": 0, "byteOffset": 240, "byteLength": 128},
            {"buffer": 0, "byteOffset": 368, "byteLength": 8},
            {"buffer": 0, "byteOffset": 376, "byteLength": 32},
            {"buffer": 0, "byteOffset": 408, "byteLength": 24},
            {"buffer": 0, "byteOffset": 432, "byteLength": 24}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(Self.skinBufferB64)",
                       "byteLength": 456}]
        }
        """
    }

    /// One triangle with two morph targets: target 0 lifts every vertex by
    /// (0, 0, 1) (dense, with normal displacements), target 1 moves only the
    /// third vertex by (2, 0, 0), stored as a *sparse* accessor with no base
    /// buffer view (the zero-filled form exporters emit). The mesh's default
    /// weights are (0.25, 0.5); node "plain" inherits them, node "posed"
    /// overrides with its own. One animation "blend" drives node "posed".
    private static var morphBufferB64: String {
        var buffer = Data()
        func put(_ floats: [Float]) {
            for f in floats { withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) } }
        }
        put([0, 0, 0,  1, 0, 0,  0, 1, 0])            // positions @ 0 (36)
        put([0, 0, 1,  0, 0, 1,  0, 0, 1])            // normals @ 36 (36)
        put([0, 0, 1,  0, 0, 1,  0, 0, 1])            // target-0 position deltas @ 72 (36)
        put([0, 1, 0,  0, 1, 0,  0, 1, 0])            // target-0 normal deltas @ 108 (36)
        for v: UInt16 in [2] { withUnsafeBytes(of: v) { buffer.append(contentsOf: $0) } } // sparse idx @ 144 (2)
        buffer.append(contentsOf: [0, 0])              // pad to 148
        put([2, 0, 0])                                 // sparse values @ 148 (12)
        put([0, 1])                                    // times @ 160 (8)
        put([0, 0, 1, 1])                              // weight keys @ 168 (16)
        return buffer.base64EncodedString()
    }

    private var morphJSON: String {
        """
        { "asset": {"version": "2.0"},
          "scene": 0,
          "scenes": [{"name": "Morphs", "nodes": [0, 1]}],
          "nodes": [
            {"name": "plain", "mesh": 0},
            {"name": "posed", "mesh": 0, "weights": [1, 0]}
          ],
          "meshes": [{
            "primitives": [{
              "attributes": {"POSITION": 0, "NORMAL": 1}, "mode": 4,
              "targets": [{"POSITION": 2, "NORMAL": 3}, {"POSITION": 4}]}],
            "weights": [0.25, 0.5]}],
          "animations": [
            {"name": "blend",
             "channels": [{"sampler": 0, "target": {"node": 1, "path": "weights"}}],
             "samplers": [{"input": 5, "output": 6, "interpolation": "LINEAR"}]}
          ],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
             "min": [0, 0, 0], "max": [1, 1, 0]},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC3",
             "min": [0, 0, 1], "max": [0, 0, 1]},
            {"bufferView": 3, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"componentType": 5126, "count": 3, "type": "VEC3",
             "min": [0, 0, 0], "max": [2, 0, 0],
             "sparse": {"count": 1,
                        "indices": {"bufferView": 4, "componentType": 5123},
                        "values": {"bufferView": 5}}},
            {"bufferView": 6, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
            {"bufferView": 7, "componentType": 5126, "count": 4, "type": "SCALAR"}
          ],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 36},
            {"buffer": 0, "byteOffset": 72, "byteLength": 36},
            {"buffer": 0, "byteOffset": 108, "byteLength": 36},
            {"buffer": 0, "byteOffset": 144, "byteLength": 2},
            {"buffer": 0, "byteOffset": 148, "byteLength": 12},
            {"buffer": 0, "byteOffset": 160, "byteLength": 8},
            {"buffer": 0, "byteOffset": 168, "byteLength": 16}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(Self.morphBufferB64)",
                       "byteLength": 184}]
        }
        """
    }

    /// Write a glTF string to a temp file and load it as a `Scene`, cleaning up.
    private func loadScene(_ json: String) throws -> Ollin.Scene? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return Scene(contentsOf: url)
    }

    private func near(_ a: Vector3, _ b: Vector3, _ tolerance: Double = 1e-5) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
    }

    // MARK: Skins

    @Test func skinParsesJointsBindMatricesAndVertexAttributes() throws {
        let scene = try #require(try loadScene(skinnedJSON()))
        #expect(scene.skins.count == 1)
        #expect(scene.skins[0].joints == [0, 1])
        #expect(scene.skins[0].inverseBind.count == 2)
        #expect(scene.skins[0].inverseBind[1].columns.3 == SIMD4<Float>(0, -1, 0, 1))
        let bar = try #require(scene.node("bar"))
        #expect(bar.skinIndex == 0)
        #expect(bar.vertexJoints.count == 6)
        #expect(bar.vertexWeights.count == 6)
        #expect(bar.vertexJoints[2] == SIMD4<UInt16>(0, 1, 0, 0))
        #expect(bar.vertexWeights[2] == SIMD4<Float>(0.5, 0.5, 0, 0))
    }

    @Test func bindPoseSkinsToTheAuthoredShape() throws {
        // Unposed, every joint matrix is world x inverseBind = identity, so the
        // skinned mesh must come back at its authored positions.
        let scene = try #require(try loadScene(skinnedJSON()))
        let bar = try #require(scene.node("bar"))
        let mesh = try #require(bar.mesh)
        let posed = try #require(bar.skinnedMesh(mesh, skin: scene.skins[0],
                                                 worlds: scene.nodeWorldTransforms()))
        for (a, b) in zip(posed.positions, mesh.positions) {
            #expect(near(a, b))
        }
    }

    @Test func posedSkinMatchesHandComputedBlend() throws {
        // Joint 1 bent 90 degrees about z. Hand-derived: a top-row vertex
        // (0.1, 2, 0) maps through T(0,1,0) R90z T(0,-1,0) to (-1, 1.1, 0); a
        // middle-row vertex blends that matrix 50/50 with joint 0's identity.
        var scene = try #require(try loadScene(skinnedJSON()))
        let anim = try #require(scene.animation("bend"))
        scene.apply(anim, at: 1)
        let bar = try #require(scene.node("bar"))
        let mesh = try #require(bar.mesh)
        let posed = try #require(bar.skinnedMesh(mesh, skin: scene.skins[0],
                                                 worlds: scene.nodeWorldTransforms()))
        #expect(near(posed.positions[0], Vector3(-0.1, 0, 0)))     // bottom: joint 0 only
        #expect(near(posed.positions[2], Vector3(-0.05, 0.95, 0))) // middle: 50/50 blend
        #expect(near(posed.positions[3], Vector3(0.05, 1.05, 0)))
        #expect(near(posed.positions[4], Vector3(-1, 0.9, 0)))     // top: joint 1 only
        #expect(near(posed.positions[5], Vector3(-1, 1.1, 0)))
    }

    @Test func skinnedPosingIsDeterministic() throws {
        var a = try #require(try loadScene(skinnedJSON()))
        var b = try #require(try loadScene(skinnedJSON()))
        let anim = try #require(a.animation("bend"))
        a.apply(anim, at: 0.7)
        b.apply(try #require(b.animation("bend")), at: 0.7)
        let na = try #require(a.node("bar")), nb = try #require(b.node("bar"))
        let pa = try #require(na.skinnedMesh(na.mesh!, skin: a.skins[0],
                                             worlds: a.nodeWorldTransforms()))
        let pb = try #require(nb.skinnedMesh(nb.mesh!, skin: b.skins[0],
                                             worlds: b.nodeWorldTransforms()))
        #expect(pa.positions == pb.positions)
        #expect(pa.normals == pb.normals)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func skinnedNodeIgnoresItsOwnTransform() throws {
        // The format's rule: a skinned mesh's placement comes entirely from its
        // joints. Two files differing only in the skinned node's own translation
        // must render byte-identically, and the bend must actually move pixels.
        let offset = try #require(try loadScene(skinnedJSON(barTranslation: [5, 0, 0])))
        let centered = try #require(try loadScene(skinnedJSON(barTranslation: [0, 0, 0])))
        let a = try #require(OllinApp.image(of: SkinnedBarProbe.make(offset, bend: 1), frame: 1))
        let b = try #require(OllinApp.image(of: SkinnedBarProbe.make(centered, bend: 1), frame: 1))
        #expect(rgba(a) == rgba(b))
        let unbent = try #require(OllinApp.image(of: SkinnedBarProbe.make(centered, bend: 0), frame: 1))
        #expect(rgba(b) != rgba(unbent))
    }

    // MARK: Morph targets

    @Test func morphTargetsParseWithSparseDeltas() throws {
        let scene = try #require(try loadScene(morphJSON))
        let plain = try #require(scene.node("plain"))
        #expect(plain.morphTargets.count == 2)
        #expect(plain.morphTargets[0].positionDeltas == [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)])
        #expect(plain.morphTargets[0].normalDeltas.count == 3)
        // The sparse target: a zero-filled base with one substituted vertex.
        #expect(plain.morphTargets[1].positionDeltas == [Vector3.zero, Vector3.zero, Vector3(2, 0, 0)])
        #expect(plain.morphTargets[1].normalDeltas.isEmpty)
    }

    @Test func morphWeightDefaultsAndNodeOverride() throws {
        let scene = try #require(try loadScene(morphJSON))
        // "plain" takes the mesh's authored defaults; "posed" carries its own.
        #expect(scene.node("plain")?.weights == [0.25, 0.5])
        #expect(scene.node("posed")?.weights == [1, 0])
    }

    @Test func morphedMeshMatchesHandComputedBlend() throws {
        let scene = try #require(try loadScene(morphJSON))
        let plain = try #require(scene.node("plain"))
        let morphed = try #require(plain.morphedMesh())
        // v = base + 0.25 * target0 + 0.5 * target1.
        #expect(near(morphed.positions[0], Vector3(0, 0, 0.25)))
        #expect(near(morphed.positions[1], Vector3(1, 0, 0.25)))
        #expect(near(morphed.positions[2], Vector3(1, 1, 0.25)))
        // Normals take target 0's displacement at 0.25 and renormalize.
        let n = Vector3(0, 0.25, 1).normalized
        #expect(near(morphed.normals[0], n))
    }

    @Test func allZeroWeightsLeaveTheMeshUntouched() throws {
        var scene = try #require(try loadScene(morphJSON))
        scene["plain"]?.weights = [0, 0]
        #expect(scene.node("plain")?.morphedMesh() == nil)
    }

    @Test func weightsAnimationDrivesNodeWeights() throws {
        var scene = try #require(try loadScene(morphJSON))
        let anim = try #require(scene.animation("blend"))
        #expect(anim.duration == 1)
        scene.apply(anim, at: 0.5)
        let mid = try #require(scene.node("posed")?.weights)
        #expect(abs(mid[0] - 0.5) < 1e-6 && abs(mid[1] - 0.5) < 1e-6)
        // Outside the range it clamps; the un-animated node is untouched.
        scene.apply(anim, at: 5)
        #expect(scene.node("posed")?.weights == [1, 1])
        #expect(scene.node("plain")?.weights == [0.25, 0.5])
    }

    // MARK: The weights sampler's cubic layout

    @Test func weightsSamplerCubicSplineLayout() {
        // Two targets, keys at t 0 and 2. Per keyframe the file stores every
        // target's in-tangent, then every value, then every out-tangent.
        // Target 0 repeats the hand-computed Hermite pin from the TRS tests
        // (v0=0 with out-tangent 1, v1=4: 2.25 at the midpoint); target 1
        // holds value 1 with zero tangents everywhere.
        let s = SceneAnimation.WeightsSampler(
            times: [0, 2],
            values: [0, 0,  0, 1,  1, 0,
                     0, 0,  4, 1,  0, 0],
            count: 2, mode: .cubicSpline)
        let mid = s.sample(at: 1)
        #expect(abs(mid[0] - 2.25) < 1e-6)
        #expect(abs(mid[1] - 1) < 1e-6)
        #expect(s.sample(at: 0) == [0, 1])       // value elements, not tangents
        #expect(s.sample(at: 5) == [4, 1])       // clamps to the last key
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
}

/// The render probe for the ignored-node-transform rule: the two-joint bar
/// drawn through `drawScene` with its "bend" animation applied at a fixed time.
private final class SkinnedBarProbe: Sketch {
    private var scene: Ollin.Scene!
    private var bend: Double = 0

    static func make(_ scene: Ollin.Scene, bend: Double) -> SkinnedBarProbe {
        let sketch = SkinnedBarProbe()
        sketch.scene = scene
        sketch.bend = bend
        return sketch
    }

    override var canvasSize: CanvasSize { .square(160) }

    override func draw() {
        background(Color(white: 0.06))
        camera(.orbiting(target: Vector3(0, 1, 0), radius: 4, elevation: 0.25))
        directionalLight(.white, direction: Vector3(-0.4, -0.8, -0.5))
        fill(Color(hue: 0.08, saturation: 0.7, brightness: 0.95))
        if let anim = scene.animation("bend") {
            scene.apply(anim, at: bend)
        }
        drawScene(scene)
    }
}
