import CoreGraphics
import Foundation
import simd
@testable import Ollin
import Testing

/// Structure-preserving scene loading. The CPU half pins the glTF scene reader:
/// the node tree with names and local (unbaked) meshes, transform composition in
/// `bounds`, camera resolution (eye/target/up from the node's world transform,
/// perspective and orthographic parameters), punctual-light resolution (all three
/// kinds, aiming down the node's -z, the per-kind intensity normalization, the
/// linear-to-sRGB color re-encode), the mesh-format fallback to a single-node
/// scene, and the value-semantics access (`node(_:)` copies, the subscript
/// mutates in place). One Metal-gated probe pins `drawScene`: the composed node
/// transforms render byte-identically to the same meshes drawn through manual
/// transform-stack calls.
@Suite
@MainActor
struct SceneLoaderTests {

    // MARK: Fixtures

    /// A triangle (0,0,0)-(1,0,0)-(0,1,0) as an embedded glTF buffer: 3 VEC3
    /// positions and 3 u16 indices.
    private static var triangleBufferB64: String {
        var buffer = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        for i: UInt16 in [0, 1, 2] {
            withUnsafeBytes(of: i) { buffer.append(contentsOf: $0) }
        }
        return buffer.base64EncodedString()
    }

    /// Write a glTF string to a temp file and load it as a `Scene`, cleaning up.
    private func loadScene(_ json: String) throws -> Ollin.Scene? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return Scene(contentsOf: url)
    }

    /// The main fixture: a "rig" root translated (1,0,0) carrying the triangle
    /// mesh on a child "part" at (0,2,0) and a point light at (0,5,0); a camera
    /// node at (0,1,5) looking down -z; a spot rotated -90 deg about y (so it
    /// aims along +x); a directional with no rotation (aims -z); and a second,
    /// half-intensity point light. Scene name "TestStage".
    private var stageJSON: String {
        """
        { "asset": {"version": "2.0"},
          "extensionsUsed": ["KHR_lights_punctual"],
          "extensions": {"KHR_lights_punctual": {"lights": [
            {"type": "point", "color": [1.0, 0.2140411, 0.0331048], "intensity": 30, "name": "warm"},
            {"type": "spot", "intensity": 120, "spot": {"innerConeAngle": 0.25, "outerConeAngle": 0.5}},
            {"type": "directional", "intensity": 3},
            {"type": "point", "intensity": 15}
          ]}},
          "scene": 0,
          "scenes": [{"name": "TestStage", "nodes": [0, 2, 4, 5, 6]}],
          "nodes": [
            {"name": "rig", "translation": [1, 0, 0], "children": [1, 3]},
            {"name": "part", "translation": [0, 2, 0], "mesh": 0},
            {"name": "camNode", "camera": 0, "translation": [0, 1, 5]},
            {"name": "warm", "translation": [0, 5, 0],
             "extensions": {"KHR_lights_punctual": {"light": 0}}},
            {"name": "key", "rotation": [0, -0.7071068, 0, 0.7071068],
             "extensions": {"KHR_lights_punctual": {"light": 1}}},
            {"name": "sun", "extensions": {"KHR_lights_punctual": {"light": 2}}},
            {"name": "warm2", "extensions": {"KHR_lights_punctual": {"light": 3}}}
          ],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "mode": 4}]}],
          "cameras": [{"name": "main", "type": "perspective",
                       "perspective": {"yfov": 0.7, "znear": 0.25, "zfar": 50}}],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(Self.triangleBufferB64)",
                       "byteLength": 42}]
        }
        """
    }

    // MARK: The node tree

    @Test func gltfSceneKeepsHierarchyAndNames() throws {
        let scene = try #require(try loadScene(stageJSON))
        #expect(scene.name == "TestStage")
        #expect(scene.nodes.count == 5)

        // The tree shape survives: "part" is a child of "rig", not flattened away.
        let rig = try #require(scene.node("rig"))
        #expect(rig.children.map(\.name) == ["part", "warm"])
        #expect(rig.mesh == nil)

        // node(_:) reaches nested nodes depth-first; the mesh stays in *local*
        // coordinates (the parent transforms are not baked into the vertices).
        let part = try #require(scene.node("part"))
        let mesh = try #require(part.mesh)
        #expect(mesh.triangleCount == 1)
        #expect(mesh.positions.map(\.x).max() == 1)
        #expect(mesh.positions.map(\.y).max() == 1)
        #expect(part.position == Vector3(0, 2, 0))

        #expect(scene.node("missing") == nil)
    }

    @Test func sceneBoundsComposeNodeTransforms() throws {
        let scene = try #require(try loadScene(stageJSON))
        // rig (1,0,0) + part (0,2,0) place the unit triangle at x 1...2, y 2...3.
        let b = scene.bounds
        #expect(abs(b.min.x - 1) < 1e-5 && abs(b.max.x - 2) < 1e-5)
        #expect(abs(b.min.y - 2) < 1e-5 && abs(b.max.y - 3) < 1e-5)
        #expect(abs(b.min.z) < 1e-5 && abs(b.max.z) < 1e-5)
    }

    // MARK: Cameras

    @Test func gltfSceneResolvesPerspectiveCamera() throws {
        let scene = try #require(try loadScene(stageJSON))
        #expect(scene.cameras.count == 1)
        let cam = try #require(scene.camera)
        #expect((cam.eye - Vector3(0, 1, 5)).length < 1e-5)
        // No rotation: the camera looks down -z, targeting the scene center's
        // depth along the view direction (center z = 0, so 5 units ahead).
        #expect((cam.target - Vector3(0, 1, 0)).length < 1e-4)
        #expect((cam.up - Vector3.unitY).length < 1e-5)
        #expect(cam.near == 0.25)
        #expect(cam.far == 50)
        guard case .perspective(let fov) = cam.projection else {
            Issue.record("expected a perspective projection"); return
        }
        #expect(abs(fov - 0.7) < 1e-9)
    }

    @Test func gltfSceneResolvesOrthographicCamera() throws {
        let json = """
        { "asset": {"version": "2.0"},
          "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"name": "cam", "camera": 0, "translation": [0, 0, 5]}],
          "cameras": [{"type": "orthographic",
                       "orthographic": {"xmag": 3, "ymag": 2, "znear": 0.5, "zfar": 20}}]
        }
        """
        let scene = try #require(try loadScene(json))
        let cam = try #require(scene.camera)
        guard case .orthographic(let height) = cam.projection else {
            Issue.record("expected an orthographic projection"); return
        }
        // ymag is the half-height, Ollin's height the full span.
        #expect(height == 4)
        #expect(cam.near == 0.5)
        #expect(cam.far == 20)
    }

    // MARK: Lights

    @Test func gltfSceneResolvesPunctualLights() throws {
        let scene = try #require(try loadScene(stageJSON))
        #expect(scene.lights.count == 4)

        // The point light rides its node's *world* transform: rig (1,0,0) + (0,5,0).
        let warm = scene.lights[0]
        #expect(warm.kind == .point)
        #expect((warm.position - Vector3(1, 5, 0)).length < 1e-5)
        // Linear (1, 0.214, 0.033) re-encodes to sRGB (1, 0.5, 0.2).
        #expect(abs(warm.color.red - 1) < 1e-3)
        #expect(abs(warm.color.green - 0.5) < 1e-3)
        #expect(abs(warm.color.blue - 0.2) < 1e-3)

        // The spot's -z axis, rotated -90 deg about y, aims along +x; the outer
        // half-angle doubles into the full cone; inner/outer becomes penumbra.
        let key = scene.lights[1]
        #expect(key.kind == .spot)
        #expect((key.direction - Vector3(1, 0, 0)).length < 1e-4)
        #expect(abs(key.coneAngle - 1.0) < 1e-6)
        #expect(abs(key.penumbra - 0.5) < 1e-6)

        // An unrotated directional travels down -z.
        let sun = scene.lights[2]
        #expect(sun.kind == .directional)
        #expect((sun.direction - Vector3(0, 0, -1)).length < 1e-6)

        // Per-kind intensity normalization: the brightest point (30) becomes 1,
        // the half-intensity one keeps the ratio; lone kinds normalize to 1.
        #expect(abs(warm.intensity - 1) < 1e-9)
        #expect(abs(scene.lights[3].intensity - 0.5) < 1e-9)
        #expect(abs(key.intensity - 1) < 1e-9)
        #expect(abs(sun.intensity - 1) < 1e-9)
    }

    // MARK: Format fallback

    @Test func meshOnlyFormatLoadsAsSingleNodeScene() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-fallback-\(ProcessInfo.processInfo.globallyUniqueString).obj")
        try "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let scene = try #require(Scene(contentsOf: url))
        #expect(scene.nodes.count == 1)
        #expect(scene.nodes[0].name.hasPrefix("ollin-fallback-"))
        #expect(scene.nodes[0].mesh?.triangleCount == 1)
        #expect(scene.cameras.isEmpty)
        #expect(scene.lights.isEmpty)
    }

    // MARK: Value semantics

    @Test func nodeReturnsACopyAndSubscriptMutatesInPlace() throws {
        let scene = try #require(try loadScene(stageJSON))
        var copy = try #require(scene.node("part"))
        copy.position += Vector3(0, 5, 0)
        // Mutating the copy leaves the scene untouched...
        #expect(scene.node("part")?.position == Vector3(0, 2, 0))

        // ...while the subscript writes through, reaching nested nodes.
        var mutable = scene
        mutable["part"]?.position = Vector3(0, 9, 0)
        #expect(mutable.node("part")?.position == Vector3(0, 9, 0))
        #expect(mutable.bounds.min.y > 8)

        // Writing to a missing name (or writing nil) changes nothing.
        mutable["missing"]?.position = .zero
        mutable["part"] = nil
        #expect(mutable.node("part")?.position == Vector3(0, 9, 0))
    }

    @Test func nodeRotationComposesAboutItsOwnPivot() {
        var node = SceneNode(name: "n", mesh: nil, position: Vector3(3, 0, 0))
        node.rotate(.pi / 2, axis: .unitY)
        // The rotation composes inside the translation: the pivot stays put.
        #expect((node.position - Vector3(3, 0, 0)).length < 1e-6)
        node.scale(by: 2)
        #expect((node.position - Vector3(3, 0, 0)).length < 1e-6)
    }

    // MARK: The draw path

    /// `drawScene` must place geometry exactly as the equivalent manual
    /// transform-stack calls: same translation matrices, composed in the same
    /// order, so the frames are byte-identical.
    @Test(.enabled(if: Snapshot.hasMetal))
    func drawSceneMatchesManualTransforms() throws {
        let viaScene = try #require(OllinApp.image(of: DrawScenePlacement.make(.scene), frame: 1))
        let manual = try #require(OllinApp.image(of: DrawScenePlacement.make(.manual), frame: 1))
        #expect(rgba(viaScene) == rgba(manual))
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

/// The placement probe: one nested arrangement (a child box riding a translated
/// parent, plus a root sphere) drawn either through `drawScene` or through the
/// equivalent manual transform-stack calls.
private final class DrawScenePlacement: Sketch {
    enum Mode { case scene, manual }
    private var mode: Mode = .scene

    static func make(_ mode: Mode) -> DrawScenePlacement {
        let sketch = DrawScenePlacement()
        sketch.mode = mode
        return sketch
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.06))
        camera(.orbiting(radius: 5, elevation: 0.35))
        directionalLight(.white, direction: Vector3(-0.4, -0.8, -0.5))
        fill(Color(hue: 0.1, saturation: 0.6, brightness: 0.9))
        switch mode {
        case .scene:
            let scene = Ollin.Scene(nodes: [
                SceneNode(name: "base", position: Vector3(0.4, -0.2, 0), children: [
                    SceneNode(name: "top", mesh: .box(size: 1), position: Vector3(0, 0.8, 0)),
                ]),
                SceneNode(name: "orb", mesh: .sphere(radius: 0.5), position: Vector3(-0.9, 0.3, 0)),
            ])
            drawScene(scene)
        case .manual:
            withState {
                translate(0.4, -0.2, 0)
                translate(0, 0.8, 0)
                drawMesh(.box(size: 1))
            }
            withState {
                translate(-0.9, 0.3, 0)
                drawMesh(.sphere(radius: 0.5))
            }
        }
        noLoop()
    }
}
