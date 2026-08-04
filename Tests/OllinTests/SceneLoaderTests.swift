import CoreGraphics
import Foundation
import ImageIO
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

    // MARK: Lights and cameras ride their nodes

    @Test func lightsFollowAMovedNode() throws {
        var scene = try #require(try loadScene(stageJSON))
        // Moving the light's carrier moves the resolved light: the "warm"
        // point rides rig/warm, so lifting "rig" lifts it.
        scene["rig"]?.position = Vector3(3, 1, 0)
        #expect((scene.lights[0].position - Vector3(3, 6, 0)).length < 1e-5)
        // Rotating the directional's node re-aims it: a quarter turn about y
        // swings its -z beam onto -x.
        scene["sun"]?.rotate(.pi / 2, axis: .unitY)
        #expect((scene.lights[2].direction - Vector3(-1, 0, 0)).length < 1e-5)
    }

    @Test func camerasFollowAMovedNode() throws {
        var scene = try #require(try loadScene(stageJSON))
        scene["camNode"]?.position = Vector3(2, 1, 5)
        let cam = try #require(scene.camera)
        #expect((cam.eye - Vector3(2, 1, 5)).length < 1e-5)
    }

    @Test func anAppliedAnimationMovesALightsNode() throws {
        var scene = try #require(try loadScene(stageJSON))
        // A translation track targeting the "warm" carrier (file node 3): the
        // authored (0,5,0) slides to (0,5,4) at t=1, and the resolved light
        // (under "rig" at (1,0,0)) follows the posed tree.
        let slide = SceneAnimation.Sampler(times: [0, 1],
                                           values: [SIMD4<Float>(0, 5, 0, 0),
                                                    SIMD4<Float>(0, 5, 4, 0)],
                                           mode: .linear)
        let anim = SceneAnimation(name: "slide", duration: 1,
                                  tracks: [.init(nodeIndex: 3, translation: slide)])
        scene.apply(anim, at: 1)
        #expect((scene.lights[0].position - Vector3(1, 5, 4)).length < 1e-5)
    }

    @Test func settingLightsFreezesThemToTheHandSetArray() throws {
        var scene = try #require(try loadScene(stageJSON))
        // Tweaking one in place is a set: the array becomes yours, fixed in
        // world space, and stops following the nodes.
        scene.lights[0].intensity = 0.25
        #expect(abs(scene.lights[0].intensity - 0.25) < 1e-12)
        let held = scene.lights[0].position
        scene["rig"]?.position = Vector3(9, 9, 9)
        #expect(scene.lights[0].position == held)
        #expect(scene.lights.count == 4)
    }

    @Test func handBuiltSceneKeepsItsArrays() {
        let light = Light.point(.white, at: Vector3(1, 2, 3))
        let cam = Camera3D(eye: Vector3(0, 0, 5), target: .zero)
        let scene = Ollin.Scene(nodes: [SceneNode(name: "n")],
                                cameras: [cam], lights: [light])
        #expect(scene.lights == [light])
        #expect(scene.cameras == [cam])
    }

    // MARK: The USD reader

    /// Write a USD text fixture to a temp file and load it as a `Scene`.
    private func loadUSDScene(_ usda: String) throws -> Ollin.Scene? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        return Scene(contentsOf: url)
    }

    /// The USD sibling of the glTF stage: a "rig" root translated (1,0,0)
    /// carrying a unit-quad mesh on a child "part" at (0,2,0) with a preview-
    /// surface material; a translated camera; and a light prim.
    private var courtUSDA: String {
        """
        #usda 1.0
        (
            defaultPrim = "Stage"
            upAxis = "Y"
        )

        def Xform "Stage"
        {
            def Xform "rig"
            {
                double3 xformOp:translate = (1, 0, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]

                def Mesh "part"
                {
                    double3 xformOp:translate = (0, 2, 0)
                    uniform token[] xformOpOrder = ["xformOp:translate"]
                    uniform token subdivisionScheme = "none"
                    point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                    int[] faceVertexCounts = [4]
                    int[] faceVertexIndices = [0, 1, 2, 3]
                    rel material:binding = </Stage/Materials/orange>
                }
            }

            def Camera "cam"
            {
                double3 xformOp:translate = (0, 1, 5)
                uniform token[] xformOpOrder = ["xformOp:translate"]
                float focalLength = 35
                float horizontalAperture = 20.955
                float verticalAperture = 15.2908
                float2 clippingRange = (0.25, 50)
            }

            def SphereLight "warm"
            {
                float inputs:intensity = 30
            }

            def Scope "Materials"
            {
                def Material "orange"
                {
                    token outputs:surface.connect = </Stage/Materials/orange/pbr.outputs:surface>

                    def Shader "pbr"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor = (0.9, 0.4, 0.1)
                        token outputs:surface
                    }
                }
            }
        }
        """
    }

    @Test func usdSceneKeepsHierarchyAndLocalMeshes() throws {
        let scene = try #require(try loadUSDScene(courtUSDA))

        // The tree shape survives: "part" rides "rig", not flattened away, and
        // each keeps its authored local translation.
        let rig = try #require(scene.node("rig"))
        #expect(rig.mesh == nil)
        #expect(rig.children.map(\.name) == ["part"])
        #expect(rig.position == Vector3(1, 0, 0))
        let part = try #require(scene.node("part"))
        #expect(part.position == Vector3(0, 2, 0))

        // The quad arrives triangulated, in *local* coordinates (the parent
        // transforms are not baked into the vertices), wearing the authored
        // preview-surface color, which is linear and re-encodes to sRGB (the
        // treatment every loader's authored color gets).
        let mesh = try #require(part.mesh)
        #expect(mesh.triangleCount == 2)
        #expect(mesh.positions.map(\.x).max() == 1)
        #expect(mesh.positions.map(\.y).max() == 1)
        let color = try #require(mesh.material?.baseColor)
        #expect(abs(color.red - Color.linearToSrgb(0.9)) < 1e-5
                && abs(color.green - Color.linearToSrgb(0.4)) < 1e-5
                && abs(color.blue - Color.linearToSrgb(0.1)) < 1e-5)

        // Transform composition: rig (1,0,0) + part (0,2,0) place the unit quad
        // at x 1...2, y 2...3.
        let b = scene.bounds
        #expect(abs(b.min.x - 1) < 1e-5 && abs(b.max.x - 2) < 1e-5)
        #expect(abs(b.min.y - 2) < 1e-5 && abs(b.max.y - 3) < 1e-5)
    }

    @Test func usdSceneResolvesPerspectiveCamera() throws {
        let scene = try #require(try loadUSDScene(courtUSDA))
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
        // The importer derives the vertical angle from focal length over
        // vertical aperture.
        #expect(abs(fov - 2 * atan(15.2908 / 70)) < 1e-4)
    }

    @Test func usdSceneResolvesOrthographicCamera() throws {
        let usda = """
        #usda 1.0
        (
            defaultPrim = "cam"
        )

        def Camera "cam"
        {
            token projection = "orthographic"
            float horizontalAperture = 300
            float verticalAperture = 200
            float2 clippingRange = (0.5, 20)
            double3 xformOp:translate = (0, 0, 5)
            uniform token[] xformOpOrder = ["xformOp:translate"]
        }
        """
        let scene = try #require(try loadUSDScene(usda))
        let cam = try #require(scene.camera)
        guard case .orthographic(let height) = cam.projection else {
            Issue.record("expected an orthographic projection"); return
        }
        // A USD orthographic aperture is spelled in tenths of a world unit.
        #expect(height == 20)
        #expect(cam.near == 0.5)
        #expect(cam.far == 20)
    }

    @Test func usdSceneCarriesItsAuthoredLight() throws {
        // The authored SphereLight arrives as a point `Light` while its prim
        // keeps its place in the tree as a grouping node.
        let scene = try #require(try loadUSDScene(courtUSDA))
        #expect(scene.lights.count == 1)
        #expect(scene.lights.first?.kind == .point)
        #expect(scene.lights.first?.intensity == 1)
        #expect(scene.node("warm") != nil)
    }

    /// The UsdLux rig: every mapped light kind, with transforms, colors, the
    /// shaping cone, the `inputs:` prefix and one bare pre-2021 fallback,
    /// exposure, and per-kind normalization all exercised. The quad mesh keeps
    /// the platform importer fed alongside the lights.
    private var lightsUSDA: String {
        """
        #usda 1.0
        (
            defaultPrim = "Stage"
            upAxis = "Y"
        )

        def Xform "Stage"
        {
            def Mesh "part"
            {
                uniform token subdivisionScheme = "none"
                point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                int[] faceVertexCounts = [4]
                int[] faceVertexIndices = [0, 1, 2, 3]
            }

            def Xform "rig"
            {
                double3 xformOp:translate = (1, 0, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]

                def SphereLight "warm"
                {
                    double3 xformOp:translate = (0, 5, 0)
                    uniform token[] xformOpOrder = ["xformOp:translate"]
                    float inputs:intensity = 30
                    color3f inputs:color = (1, 0.2140411, 0.0331048)
                }
            }

            def SphereLight "key"
            {
                float3 xformOp:rotateXYZ = (0, -90, 0)
                uniform token[] xformOpOrder = ["xformOp:rotateXYZ"]
                float inputs:intensity = 120
                float inputs:shaping:cone:angle = 28.64789
                float inputs:shaping:cone:softness = 0.5
            }

            def DistantLight "sun"
            {
            }

            def SphereLight "warm2"
            {
                float intensity = 7.5
                float inputs:exposure = 1
            }

            def RectLight "panel"
            {
                double3 xformOp:translate = (0, 3, 4)
                float3 xformOp:rotateXYZ = (-90, 0, 0)
                uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]
                float inputs:width = 4
                float inputs:height = 2
            }

            def DiskLight "halo"
            {
                double3 xformOp:scale = (2, 2, 2)
                uniform token[] xformOpOrder = ["xformOp:scale"]
                float inputs:radius = 0.75
            }

            def CylinderLight "neon"
            {
                double3 xformOp:translate = (0, 2, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]
                float inputs:length = 4
                float inputs:radius = 0.1
            }
        }
        """
    }

    @Test func usdSceneResolvesUsdLuxLights() throws {
        let scene = try #require(try loadUSDScene(lightsUSDA))
        #expect(scene.lights.count == 7)

        // The sphere light rides its prim's *world* transform: rig (1,0,0) +
        // (0,5,0); its linear color re-encodes to sRGB (1, 0.5, 0.2).
        let warm = scene.lights[0]
        #expect(warm.kind == .point)
        #expect((warm.position - Vector3(1, 5, 0)).length < 1e-5)
        #expect(abs(warm.color.red - 1) < 1e-3)
        #expect(abs(warm.color.green - 0.5) < 1e-3)
        #expect(abs(warm.color.blue - 0.2) < 1e-3)

        // A cone-shaped sphere light is a spot: the -z axis rotated -90 deg
        // about y aims +x; the 28.64789-degree half-angle doubles into a
        // 1-radian cone; the softness is the penumbra.
        let key = scene.lights[1]
        #expect(key.kind == .spot)
        #expect((key.direction - Vector3(1, 0, 0)).length < 1e-4)
        #expect(abs(key.coneAngle - 1.0) < 1e-5)
        #expect(abs(key.penumbra - 0.5) < 1e-6)

        // An unrotated distant light travels down -z.
        let sun = scene.lights[2]
        #expect(sun.kind == .directional)
        #expect((sun.direction - Vector3(0, 0, -1)).length < 1e-6)
        #expect(abs(sun.intensity - 1) < 1e-9)

        // Per-kind normalization over intensity × 2^exposure, with the bare
        // pre-2021 `intensity` spelling honored: 7.5 × 2 = 15 is half of 30.
        #expect(abs(warm.intensity - 1) < 1e-9)
        #expect(abs(scene.lights[3].intensity - 0.5) < 1e-9)

        // The rect panel: rotateX(-90) aims it straight down, the height axis
        // (its up hint) landing on -z; width and height span local x and y.
        let panel = scene.lights[4]
        #expect(panel.kind == .rect)
        #expect((panel.position - Vector3(0, 3, 4)).length < 1e-5)
        #expect((panel.direction - Vector3(0, -1, 0)).length < 1e-5)
        #expect(abs(panel.width - 4) < 1e-6)
        #expect(abs(panel.height - 2) < 1e-6)
        #expect((panel.up - Vector3(0, 0, -1)).length < 1e-5)

        // The disk's radius scales with its prim's transform.
        let halo = scene.lights[5]
        #expect(halo.kind == .disk)
        #expect(abs(halo.radius - 1.5) < 1e-6)

        // The cylinder runs along local x: endpoints straddle its position.
        let neon = scene.lights[6]
        #expect(neon.kind == .tube)
        #expect((neon.position - Vector3(0, 2, 0)).length < 1e-6)
        #expect((neon.direction - Vector3(1, 0, 0)).length < 1e-6)
        #expect(abs(neon.length - 4) < 1e-6)
        #expect(abs(neon.radius - 0.1) < 1e-6)
    }

    @Test func usdLightsFollowAMovedNode() throws {
        var scene = try #require(try loadUSDScene(lightsUSDA))
        // The UsdLux prims are nodes too: lifting "rig" carries its sphere
        // light, and the rest of the rig keeps resolving.
        scene["rig"]?.position = Vector3(2, 1, 0)
        #expect((scene.lights[0].position - Vector3(2, 6, 0)).length < 1e-5)
        #expect(scene.lights.count == 7)
    }

    @Test func usdzPackageCarriesLightsThrough() throws {
        // The package path: the lights usda zipped as a stored usdz (64-byte
        // aligned per the spec) resolves the same rig.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usdz")
        try Self.storedZip([("stage.usda", Data(lightsUSDA.utf8))]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let lights = Scene.resolveUSDLights(try USDStage.load(contentsOf: url))
        #expect(lights.count == 7)
        #expect(lights[1].kind == .spot)
        #expect(lights[4].kind == .rect)

        // The whole scene read agrees: structure, meshes, and lights all
        // resolve from the one package parse.
        let scene = try #require(Scene(contentsOf: url))
        #expect(scene.lights.count == 7)
        #expect(scene.node("part")?.mesh != nil)
    }

    /// A ZIP with every entry stored uncompressed, file data aligned to the
    /// 64-byte boundaries the usdz spec requires (padding rides the local
    /// header's extra field, the reference writer's scheme).
    private static func storedZip(_ entries: [(name: String, data: Data)]) -> Data {
        var out = [UInt8]()
        var central = [UInt8]()
        for (name, data) in entries {
            let nameBytes = Array(name.utf8)
            let crc = crc32(data)
            let bytes = [UInt8](data)
            let offset = UInt32(out.count)

            // Pad so the entry's data starts 64-byte aligned; the padding is a
            // well-formed extra-field block (4-byte header + filler).
            let dataStart = out.count + 30 + nameBytes.count
            var padding = (64 - dataStart % 64) % 64
            if padding > 0, padding < 4 { padding += 64 }
            var extra = [UInt8]()
            if padding > 0 {
                extra += le16(0x1986) + le16(UInt16(padding - 4))
                extra += [UInt8](repeating: 0, count: padding - 4)
            }

            out += le32(0x0403_4b50)
            out += le16(20) + le16(0) + le16(0) + le16(0) + le16(0)   // version, flags, method, time, date
            out += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            out += le16(UInt16(nameBytes.count)) + le16(UInt16(extra.count))
            out += nameBytes + extra + bytes

            central += le32(0x0201_4b50)
            central += le16(20) + le16(20) + le16(0) + le16(0) + le16(0) + le16(0)
            central += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
            central += le16(UInt16(nameBytes.count)) + le16(0) + le16(0)
            central += le16(0) + le16(0) + le32(0)
            central += le32(offset) + nameBytes
        }
        let cdOffset = UInt32(out.count)
        out += central
        out += le32(0x0605_4b50) + le16(0) + le16(0)
        out += le16(UInt16(entries.count)) + le16(UInt16(entries.count))
        out += le32(UInt32(central.count)) + le32(cdOffset) + le16(0)
        return Data(out)
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: The native USD walk

    @Test func usdSceneKeepsAuthoredChildOrder() throws {
        // Children arrive in the file's own order, never alphabetized, each
        // node carrying real per-prim identity.
        let scene = try #require(try loadUSDScene("""
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
            def Xform "zebra"
            {
            }

            def Xform "apple"
            {
            }

            def Xform "mango"
            {
            }
        }
        """))
        let root = try #require(scene.nodes.first)
        #expect(root.children.map(\.name) == ["zebra", "apple", "mango"])
        let indices = root.children.compactMap(\.sourceIndex)
        #expect(indices.count == 3 && Set(indices).count == 3)
    }

    /// The system shaderball, the file that demonstrates the alphabetization
    /// the native walk fixes: its neutral_objects group authors core, base,
    /// sss_bars in that order (sorted would lead with base).
    @Test func systemShaderballKeepsAuthoredChildOrder() throws {
        let url = URL(fileURLWithPath:
            "/System/Library/PrivateFrameworks/CoreUSDEdit.framework/Versions/A/Resources/shaderball.usdz")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let loaded = Ollin.Scene(contentsOf: url)
        let scene = try #require(loaded)
        let group = try #require(scene.node("neutral_objects"))
        #expect(group.children.map(\.name) == ["core", "base", "sss_bars"])
        #expect(group.children.allSatisfy { $0.mesh != nil })
    }

    @Test func usdInvisibleAndGuidePrimsSkipRender() throws {
        // visibility = "invisible" hides its subtree (nodes stay, nothing
        // renders, its lights stay dark); a guide/proxy purpose skips
        // rendering the same way.
        let scene = try #require(try loadUSDScene("""
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
            def Mesh "hidden"
            {
                token visibility = "invisible"
                uniform token subdivisionScheme = "none"
                point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                int[] faceVertexCounts = [4]
                int[] faceVertexIndices = [0, 1, 2, 3]
            }

            def Xform "guides"
            {
                uniform token purpose = "guide"

                def Mesh "helper"
                {
                    uniform token subdivisionScheme = "none"
                    point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                    int[] faceVertexCounts = [4]
                    int[] faceVertexIndices = [0, 1, 2, 3]
                }
            }

            def Mesh "shown"
            {
                uniform token subdivisionScheme = "none"
                point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                int[] faceVertexCounts = [4]
                int[] faceVertexIndices = [0, 1, 2, 3]
            }

            def SphereLight "dark"
            {
                token visibility = "invisible"
            }

            def SphereLight "lit"
            {
            }
        }
        """))
        #expect(scene.node("hidden") != nil && scene.node("hidden")?.mesh == nil)
        #expect(scene.node("helper") != nil && scene.node("helper")?.mesh == nil)
        #expect(scene.node("shown")?.mesh != nil)
        #expect(scene.lights.count == 1)
    }

    @Test func usdFaceVaryingAttributesExpandPerCorner() throws {
        // Two quads sharing an edge with faceVarying texture coordinates:
        // the mesh expands to one vertex per corner so the seam's corners
        // keep their own values (v flips to the top-left convention).
        let scene = try #require(try loadUSDScene("""
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
            def Mesh "strip"
            {
                uniform token subdivisionScheme = "none"
                point3f[] points = [(0, 0, 0), (1, 0, 0), (2, 0, 0), (0, 1, 0), (1, 1, 0), (2, 1, 0)]
                int[] faceVertexCounts = [4, 4]
                int[] faceVertexIndices = [0, 1, 4, 3, 1, 2, 5, 4]
                texCoord2f[] primvars:st = [(0, 0), (0.5, 0), (0.5, 1), (0, 1), (0.5, 0), (1, 0), (1, 1), (0.5, 1)] (
                    interpolation = "faceVarying"
                )
            }
        }
        """))
        let mesh = try #require(scene.node("strip")?.mesh)
        #expect(mesh.positions.count == 8)
        #expect(mesh.triangleCount == 4)
        #expect(mesh.uvs.count == 8)
        #expect((mesh.uvs[1] - Vector2(0.5, 1)).length < 1e-6)
        // The shared point (1, 0, 0) appears once per face.
        #expect(mesh.positions.filter { ($0 - Vector3(1, 0, 0)).length < 1e-9 }.count == 2)
    }

    @Test func usdVertexAttributesStayOnAuthoredPoints() throws {
        // Vertex-interpolated texture coordinates need no expansion: the
        // mesh keeps its authored points shared.
        let scene = try #require(try loadUSDScene("""
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
            def Mesh "strip"
            {
                uniform token subdivisionScheme = "none"
                point3f[] points = [(0, 0, 0), (1, 0, 0), (2, 0, 0), (0, 1, 0), (1, 1, 0), (2, 1, 0)]
                int[] faceVertexCounts = [4, 4]
                int[] faceVertexIndices = [0, 1, 4, 3, 1, 2, 5, 4]
                texCoord2f[] primvars:st = [(0, 0), (0.5, 0), (1, 0), (0, 1), (0.5, 1), (1, 1)] (
                    interpolation = "vertex"
                )
            }
        }
        """))
        let mesh = try #require(scene.node("strip")?.mesh)
        #expect(mesh.positions.count == 6)
        #expect(mesh.triangleCount == 4)
        #expect(mesh.uvs.count == 6)
        #expect((mesh.uvs[4] - Vector2(0.5, 0)).length < 1e-6)
    }

    @Test func usdzTextureResolvesThroughThePackage() throws {
        // A UsdUVTexture connected to the diffuse input reads its image file
        // out of the package's entries, relative to the default layer.
        let layer = """
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
            def Mesh "tile"
            {
                uniform token subdivisionScheme = "none"
                point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                int[] faceVertexCounts = [4]
                int[] faceVertexIndices = [0, 1, 2, 3]
                texCoord2f[] primvars:st = [(0, 0), (1, 0), (1, 1), (0, 1)] (
                    interpolation = "vertex"
                )
                rel material:binding = </Root/mat>
            }

            def Material "mat"
            {
                token outputs:surface.connect = </Root/mat/pbr.outputs:surface>

                def Shader "pbr"
                {
                    uniform token info:id = "UsdPreviewSurface"
                    color3f inputs:diffuseColor.connect = </Root/mat/tex.outputs:rgb>
                    token outputs:surface
                }

                def Shader "tex"
                {
                    uniform token info:id = "UsdUVTexture"
                    asset inputs:file = @textures/swatch.png@
                    float3 outputs:rgb
                }
            }
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usdz")
        try Self.storedZip([("scene.usda", Data(layer.utf8)),
                            ("textures/swatch.png", Self.pngData(r: 200, g: 40, b: 90))])
            .write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let scene = try #require(Scene(contentsOf: url))
        let mesh = try #require(scene.node("tile")?.mesh)
        let texture = try #require(mesh.material?.texture)
        #expect(texture.width == 1 && texture.height == 1)
        #expect(mesh.uvs.count == 4)
    }

    /// A one-pixel PNG of the given color, for package-texture fixtures.
    private static func pngData(r: UInt8, g: UInt8, b: UInt8) -> Data {
        var pixel: [UInt8] = [r, g, b, 255]
        let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
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
