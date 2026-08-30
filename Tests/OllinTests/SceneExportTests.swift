import Foundation
@testable import Ollin
import Testing
import simd

/// Pure-CPU checks on writing a `Scene` out as a spatial model.
///
/// A writer and its reader are two halves of one mapping, and a writer that
/// drifts from its reader is wrong in a way nothing else notices, so almost
/// everything here is a round trip: build a scene, write it, read it back with
/// the shipped `Scene(contentsOf:)`, and hold the two against each other. Where
/// the mapping is a conversion rather than a copy (a color that has to leave as
/// linear, a field of view that has to become a focal length), the test also
/// looks at what was actually written, because a round trip through two
/// matching mistakes still passes.
///
/// The package layout is checked against the spec's own rules (no compression,
/// every file on a 64-byte boundary, the layer first), and where the system's
/// USD tools are installed they get the last word: `usdchecker --arkit` is the
/// validator Apple's own platforms are held to. No GPU.
@Suite
struct SceneExportTests {

    // MARK: Support

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-scene-export-\(UUID().uuidString)-\(name)")
    }

    /// A small mesh whose every number is distinct, so a transposed or
    /// off-by-one read shows up rather than landing on a lookalike.
    private func lopsidedTriangle() -> Mesh {
        Mesh(positions: [Vector3(0.25, 0, 0), Vector3(1.5, 0, 0), Vector3(0, 2.75, 0)],
             normals: [Vector3(0, 0, 1), Vector3(0, 0, 1), Vector3(0, 0, 1)],
             indices: [0, 1, 2],
             uvs: [Vector2(0.125, 0.25), Vector2(0.875, 0.25), Vector2(0.5, 0.75)])
    }

    /// Write `scene` and read it back through the shipped loader.
    private func roundTrip(_ scene: Scene, as format: SceneFileFormat = .usda,
                           metersPerUnit: Double = 1) throws -> Scene {
        let url = temporaryURL("scene.\(format.fileExtension)")
        #expect(scene.write(to: url, metersPerUnit: metersPerUnit))
        defer { try? FileManager.default.removeItem(at: url) }
        return try #require(Scene(contentsOf: url), "the writer produced a layer its own reader couldn't open")
    }

    /// Every mesh anywhere in a scene, depth-first. A read-back scene hangs
    /// under the layer's root prim, so counting has to walk rather than look at
    /// the top level.
    private func meshes(_ scene: Scene) -> [Mesh] {
        func search(_ nodes: [SceneNode]) -> [Mesh] {
            nodes.flatMap { node in (node.mesh.map { [$0] } ?? []) + search(node.children) }
        }
        return search(scene.nodes)
    }

    private func firstMesh(_ scene: Scene) -> Mesh? { meshes(scene).first }

    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-5) -> Bool {
        abs(a - b) <= tolerance
    }

    private func near(_ a: Vector3, _ b: Vector3, _ tolerance: Double = 1e-5) -> Bool {
        (a - b).length <= tolerance
    }

    // MARK: Geometry

    @Test func aMeshComesBackAsTheGeometryItWentOutAs() throws {
        let mesh = lopsidedTriangle()
        var node = SceneNode(name: "piece")
        node.mesh = mesh
        let read = try roundTrip(Scene(nodes: [node]))
        let back = try #require(firstMesh(read))

        #expect(back.indices == mesh.indices)
        #expect(back.positions.count == mesh.positions.count)
        for (a, b) in zip(back.positions, mesh.positions) {
            #expect(near(a, b), "position moved: \(a) vs \(b)")
        }
        for (a, b) in zip(back.normals, mesh.normals) {
            #expect(near(a, b), "normal moved: \(a) vs \(b)")
        }
        // The v flip is a real conversion in both directions, so an uneven uv
        // catches a writer that flips once or not at all.
        #expect(back.uvs.count == mesh.uvs.count)
        for (a, b) in zip(back.uvs, mesh.uvs) {
            #expect(near(a.x, b.x) && near(a.y, b.y), "uv moved: \(a) vs \(b)")
        }
    }

    @Test func aMeshIsWrittenAsPolygonsRatherThanASubdivisionCage() throws {
        var node = SceneNode(name: "piece")
        node.mesh = lopsidedTriangle()
        let text = String(decoding: Scene(nodes: [node]).data(as: .usda), as: UTF8.self)
        // Left unsaid, a Mesh prim is a subdivision cage by default and every
        // viewer that honors the schema shows a smoothed, shrunken model.
        #expect(text.contains("uniform token subdivisionScheme = \"none\""))
    }

    @Test func aNodeTreeKeepsEveryTransform() throws {
        var child = SceneNode(name: "child", position: Vector3(0, 1.5, 0))
        child.mesh = lopsidedTriangle()
        var parent = SceneNode(name: "parent", position: Vector3(3, 0, -2))
        parent.children = [child]
        let read = try roundTrip(Scene(nodes: [parent]))

        let readParent = try #require(read.node("parent"))
        let readChild = try #require(read.node("child"))
        #expect(near(readParent.position, Vector3(3, 0, -2)))
        #expect(near(readChild.position, Vector3(0, 1.5, 0)))
    }

    @Test func aRotatedNodeKeepsItsRotationAndNotItsTranspose() throws {
        // A transpose is the classic way a matrix convention goes wrong, and it
        // is invisible on a symmetric transform, so this one turns about a
        // single axis and then checks where a known point lands.
        var node = SceneNode(name: "turned", position: Vector3(1, 2, 3))
        node.mesh = lopsidedTriangle()
        node.rotate(.pi / 3, axis: .unitY)
        let before = node.localTransform * SIMD4<Float>(1, 0, 0, 1)
        let read = try roundTrip(Scene(nodes: [node]))
        let after = try #require(read.node("turned")).localTransform * SIMD4<Float>(1, 0, 0, 1)
        #expect(near(Double(before.x), Double(after.x), 1e-4))
        #expect(near(Double(before.y), Double(after.y), 1e-4))
        #expect(near(Double(before.z), Double(after.z), 1e-4))
    }

    // MARK: Materials, the halves that have to agree

    @Test func aSurfaceColorSurvivesTheLinearRoundTrip() throws {
        // Mid-tones are where the sRGB curve bites hardest, so a color that
        // came back unconverted (or converted twice) misses by a mile.
        let color = Color(red: 0.2, green: 0.5, blue: 0.8)
        var mesh = lopsidedTriangle()
        mesh.material = MeshMaterial(baseColor: color)
        var node = SceneNode(name: "piece")
        node.mesh = mesh

        let read = try roundTrip(Scene(nodes: [node]))
        let back = try #require(firstMesh(read)?.material)
        #expect(near(back.baseColor.red, color.red, 1e-3))
        #expect(near(back.baseColor.green, color.green, 1e-3))
        #expect(near(back.baseColor.blue, color.blue, 1e-3))
    }

    @Test func theWrittenColorIsLinearNotTheDisplayValue() throws {
        // The round trip above passes even if both halves skip the conversion,
        // so this reads the actual number: 0.5 in sRGB is 0.2140 in linear, and
        // those are nowhere near each other.
        var mesh = lopsidedTriangle()
        mesh.material = MeshMaterial(baseColor: Color(red: 0.5, green: 0.5, blue: 0.5))
        var node = SceneNode(name: "piece")
        node.mesh = mesh
        let text = String(decoding: Scene(nodes: [node]).data(as: .usda), as: UTF8.self)

        let line = try #require(text.split(separator: "\n")
            .first { $0.contains("inputs:diffuseColor = ") })
        let written = try #require(Double(line.split(separator: "(")[1]
            .split(separator: ",")[0]))
        #expect(near(written, Color.srgbToLinear(0.5), 1e-4),
                "diffuseColor went out as \(written); linear 0.5 is \(Color.srgbToLinear(0.5))")
        #expect(!near(written, 0.5, 0.05), "the color was written as its display value")
    }

    @Test func aFinishTravelsAsThePartsTheFormatCanHold() throws {
        var mesh = lopsidedTriangle()
        mesh.material = MeshMaterial(baseColor: .white, metallic: 1, roughness: 0.2,
                                     opacity: 0.75, ior: 1.33, clearcoat: 0.6,
                                     clearcoatRoughness: 0.05)
        var node = SceneNode(name: "piece")
        node.mesh = mesh
        let text = String(decoding: Scene(nodes: [node]).data(as: .usda), as: UTF8.self)
        for expected in ["float inputs:metallic = 1", "float inputs:roughness = 0.2",
                         "float inputs:opacity = 0.75", "float inputs:ior = 1.33",
                         "float inputs:clearcoat = 0.6",
                         "float inputs:clearcoatRoughness = 0.05"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
    }

    @Test func onlyOneMaterialIsWrittenForMeshesWearingTheSameOne() throws {
        let material = MeshMaterial(baseColor: Color(red: 0.9, green: 0.3, blue: 0.1))
        let nodes = (0 ..< 4).map { i -> SceneNode in
            var mesh = lopsidedTriangle()
            mesh.material = material
            var node = SceneNode(name: "piece\(i)", position: Vector3(Double(i), 0, 0))
            node.mesh = mesh
            return node
        }
        let text = String(decoding: Scene(nodes: nodes).data(as: .usda), as: UTF8.self)
        #expect(text.components(separatedBy: "def Material ").count - 1 == 1,
                "four meshes in one material wrote more than one material prim")
    }

    @Test func twoTexturesNeverShareOneMaterial() throws {
        // Materials are shared by value, and a texture is the one part of a
        // material that has no value to compare, so it is told apart by which
        // image it is. Two images alike in every other respect must still write
        // two materials and two files.
        let nodes = [Image(width: 4, height: 4, color: .red),
                     Image(width: 4, height: 4, color: .blue)]
            .enumerated().map { i, texture -> SceneNode in
                var mesh = lopsidedTriangle()
                mesh.material = MeshMaterial(baseColor: .white, texture: texture)
                var node = SceneNode(name: "piece\(i)", position: Vector3(Double(i), 0, 0))
                node.mesh = mesh
                return node
            }
        let data = Scene(nodes: nodes).data(as: .usdz)
        let text = String(decoding: try #require(USDZipArchive(data: data).data(named: "scene.usda")),
                          as: UTF8.self)
        #expect(text.components(separatedBy: "def Material ").count - 1 == 2)
        #expect(try USDZipArchive(data: data).entryNames
            .filter { $0.hasSuffix(".png") }.count == 2)
    }

    // MARK: Cameras

    @Test func aPerspectiveCameraSurvivesTheApertureRoundTrip() throws {
        let camera = Camera3D(eye: Vector3(2, 3, 8), target: Vector3(0, 1, 0), up: .unitY,
                              near: 0.05, far: 250,
                              projection: .perspective(fieldOfView: .pi / 3.4))
        var node = SceneNode(name: "piece")
        node.mesh = lopsidedTriangle()
        let read = try roundTrip(Scene(nodes: [node], cameras: [camera]))
        let back = try #require(read.camera)

        #expect(near(back.eye, camera.eye, 1e-4))
        #expect(near(back.near, camera.near, 1e-4))
        #expect(near(back.far, camera.far, 1e-3))
        guard case .perspective(let fov) = back.projection else {
            Issue.record("came back as \(back.projection)"); return
        }
        #expect(near(fov, .pi / 3.4, 1e-4), "field of view went out and came back as \(fov)")
        // The camera has to look the same way, which the eye alone doesn't say.
        let wentOut = (camera.target - camera.eye).normalized
        let cameBack = (back.target - back.eye).normalized
        #expect(near(wentOut, cameBack, 1e-4), "the camera turned: \(wentOut) vs \(cameBack)")
    }

    @Test func anOrthographicCameraKeepsItsFrameHeight() throws {
        let camera = Camera3D(eye: Vector3(0, 0, 6), target: .zero, up: .unitY,
                              near: 0.1, far: 40, projection: .orthographic(height: 3.5))
        var node = SceneNode(name: "piece")
        node.mesh = lopsidedTriangle()
        let read = try roundTrip(Scene(nodes: [node], cameras: [camera]))
        guard case .orthographic(let height) = try #require(read.camera).projection else {
            Issue.record("an orthographic camera came back perspective"); return
        }
        #expect(near(height, 3.5, 1e-4))
    }

    // MARK: Lights

    @Test func everyLightKindComesBackAsItself() throws {
        var node = SceneNode(name: "piece")
        node.mesh = lopsidedTriangle()
        let lights: [Light] = [
            .directional(.white, direction: Vector3(-1, -2, -0.5).normalized, intensity: 1),
            .point(Color(red: 1, green: 0.8, blue: 0.6), at: Vector3(3, 4, 5), intensity: 1),
            .spot(.white, at: Vector3(-2, 6, 1), direction: Vector3(0, -1, 0),
                  coneAngle: .pi / 5, penumbra: 0.35, intensity: 1),
            .rectangle(.white, at: Vector3(0, 4, 2), direction: Vector3(0, -1, 0),
                  width: 2.5, height: 1.25, up: Vector3(0, 0, -1), intensity: 1),
            .disk(.white, at: Vector3(1, 3, 0), direction: Vector3(0, -1, 0),
                  radius: 0.8, intensity: 1),
            .tube(.white, from: Vector3(-2, 3, 0), to: Vector3(2, 3, 0),
                  radius: 0.15, intensity: 1),
        ]
        let read = try roundTrip(Scene(nodes: [node], lights: lights))
        #expect(read.lights.count == lights.count)

        for (back, sent) in zip(read.lights, lights) {
            #expect(back.kind == sent.kind, "a \(sent.kind) came back a \(back.kind)")
            switch sent.kind {
            case .directional:
                #expect(near(back.direction, sent.direction, 1e-4))
            case .point:
                #expect(near(back.position, sent.position, 1e-4))
                #expect(near(back.color.red, sent.color.red, 1e-3))
                #expect(near(back.color.green, sent.color.green, 1e-3))
                #expect(near(back.color.blue, sent.color.blue, 1e-3))
            case .spot:
                #expect(near(back.position, sent.position, 1e-4))
                #expect(near(back.direction, sent.direction, 1e-4))
                // The half-angle in degrees on the way out, doubled back into
                // radians on the way in: two conversions that must undo.
                #expect(near(back.coneAngle, sent.coneAngle, 1e-4),
                        "cone went out \(sent.coneAngle) and came back \(back.coneAngle)")
                #expect(near(back.penumbra, sent.penumbra, 1e-4))
            case .rectangle:
                #expect(near(back.position, sent.position, 1e-4))
                #expect(near(back.direction, sent.direction, 1e-4))
                #expect(near(back.width, sent.width, 1e-4))
                #expect(near(back.height, sent.height, 1e-4))
            case .disk:
                #expect(near(back.position, sent.position, 1e-4))
                #expect(near(back.radius, sent.radius, 1e-4))
            case .tube:
                // A tube runs along its prim's local x, so its endpoints come
                // back through the transform rather than from the numbers.
                #expect(near(back.position, sent.position, 1e-4))
                #expect(near(back.length, sent.length, 1e-4))
                #expect(near(back.radius, sent.radius, 1e-4))
            }
        }
    }

    @Test func aSpotConeIsWrittenAsAHalfAngleInDegrees() throws {
        var node = SceneNode(name: "piece")
        node.mesh = lopsidedTriangle()
        let scene = Scene(nodes: [node], lights: [
            .spot(.white, at: .zero, direction: Vector3(0, -1, 0), coneAngle: .pi / 2,
                  penumbra: 0, intensity: 1),
        ])
        let text = String(decoding: scene.data(as: .usda), as: UTF8.self)
        // A full cone of 90 degrees is a half-angle of 45. Writing the whole
        // angle, or radians, lands on a different number entirely.
        #expect(text.contains("float inputs:shaping:cone:angle = 45"),
                "the cone angle isn't a 45 degree half-angle")
    }

    // MARK: The package

    @Test func aPackageIsUncompressedAndAligned() throws {
        var mesh = Mesh.icosphere(radius: 1, subdivisions: 2)
        mesh.material = MeshMaterial(baseColor: Color(red: 0.4, green: 0.6, blue: 0.9))
        var node = SceneNode(name: "ball")
        node.mesh = mesh
        let data = Scene(nodes: [node]).data(as: .usdz)

        // Walk the local headers the way a reader mapping the file would.
        var offset = 0
        var entries = 0
        while offset + 30 <= data.count,
              data.readU32(at: offset) == 0x0403_4b50 {
            let method = data.readU16(at: offset + 8)
            let compressed = Int(data.readU32(at: offset + 18))
            let nameLength = Int(data.readU16(at: offset + 26))
            let extraLength = Int(data.readU16(at: offset + 28))
            let start = offset + 30 + nameLength + extraLength
            #expect(method == 0, "an entry was compressed, which a package may not be")
            #expect(start % 64 == 0, "an entry's data started at \(start), off the 64-byte grid")
            entries += 1
            offset = start + compressed
        }
        #expect(entries >= 1, "no entries found in the package")
    }

    @Test func aPackageLeadsWithItsLayer() throws {
        var node = SceneNode(name: "piece")
        node.mesh = lopsidedTriangle()
        let data = Scene(nodes: [node]).data(as: .usdz)
        let archive = try USDZipArchive(data: data)
        // A package is presented as whichever usd file comes first, so the
        // layer has to lead however many textures follow it.
        let first = try #require(archive.entryNames.first)
        #expect(first.hasSuffix(".usda"), "the package leads with '\(first)'")
    }

    @Test func aPackageOpensThroughTheShippedReader() throws {
        var mesh = Mesh.box(size: 1.5)
        mesh.material = MeshMaterial(baseColor: Color(red: 0.8, green: 0.2, blue: 0.3))
        var node = SceneNode(name: "crate")
        node.mesh = mesh
        let read = try roundTrip(Scene(nodes: [node]), as: .usdz)
        let back = try #require(firstMesh(read))
        #expect(back.indices.count == mesh.indices.count)
    }

    @Test func theSameSceneWritesTheSameBytes() throws {
        var mesh = Mesh.icosphere(radius: 1, subdivisions: 1)
        mesh.material = MeshMaterial(baseColor: Color(red: 0.3, green: 0.7, blue: 0.2))
        var node = SceneNode(name: "ball", position: Vector3(0.5, 1, -2))
        node.mesh = mesh
        let scene = Scene(nodes: [node], cameras: [.orbiting(radius: 5)],
                          lights: [.point(.white, at: Vector3(2, 3, 4))])
        #expect(scene.data(as: .usdz) == scene.data(as: .usdz),
                "two writes of one scene disagreed, so an export isn't reproducible")
    }

    @Test func metersPerUnitIsWrittenAsAskedAndScalesNothing() throws {
        var node = SceneNode(name: "piece")
        node.mesh = lopsidedTriangle()
        let scene = Scene(nodes: [node])
        let text = String(decoding: scene.data(as: .usda, metersPerUnit: 0.01), as: UTF8.self)
        #expect(text.contains("metersPerUnit = 0.01"))
        // It is a declaration about the numbers, not a change to them.
        #expect(text.contains("(0.25, 0, 0)"), "the geometry was scaled, and it should not be")
    }

    // MARK: Textures

    @Test func aTextureTravelsInsideAPackageAndNotBesideALayer() throws {
        var mesh = lopsidedTriangle()
        mesh.material = MeshMaterial(baseColor: .white,
                                     texture: Image(width: 4, height: 4, color: .red))
        var node = SceneNode(name: "piece")
        node.mesh = mesh
        let scene = Scene(nodes: [node])

        let archive = try USDZipArchive(data: scene.data(as: .usdz))
        #expect(archive.entryNames.contains { $0.hasSuffix(".png") },
                "the package carried no image: \(archive.entryNames)")

        // A layer is one text file, so there is nowhere to put the image; the
        // material still writes, just untextured.
        let text = String(decoding: scene.data(as: .usda), as: UTF8.self)
        #expect(!text.contains("UsdUVTexture"))
        #expect(text.contains("def Material "))
    }

    @Test func aPackagedTextureComesBackAsAnImage() throws {
        var mesh = lopsidedTriangle()
        mesh.material = MeshMaterial(baseColor: .white,
                                     texture: Image(width: 6, height: 3, color: .blue))
        var node = SceneNode(name: "piece")
        node.mesh = mesh
        // Written into the package, referred to by an anchored relative path,
        // and found again by the reader that resolves paths through the package.
        let read = try roundTrip(Scene(nodes: [node]), as: .usdz)
        let back = try #require(firstMesh(read)?.material?.texture)
        #expect(back.width == 6 && back.height == 3)
    }

    @Test func perVertexColorsAreReadIntoTheSurfaceRatherThanLeftDecorative() throws {
        var mesh = lopsidedTriangle()
        mesh.colors = [.red, .green, .blue]
        mesh.material = MeshMaterial(baseColor: .white)
        var node = SceneNode(name: "piece")
        node.mesh = mesh
        let text = String(decoding: Scene(nodes: [node]).data(as: .usda), as: UTF8.self)
        #expect(text.contains("primvars:displayColor"))
        // A preview surface has no per-vertex input, so without a reader shader
        // feeding the diffuse slot the colors are decoration nothing shades by.
        #expect(text.contains("UsdPrimvarReader_float3"))
        #expect(text.contains("inputs:diffuseColor.connect"))
    }

    // MARK: The frame recorder

    /// A sketch drawing two boxes at known places, one of them colored.
    private final class TwoBoxes: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            camera(.orbiting(radius: 6))
            withState {
                translate(-1.5, 0, 0)
                fill(.red)
                drawMesh(.box(size: 1))
            }
            withState {
                translate(2.5, 0.5, 0)
                fill(.blue)
                drawMesh(.box(size: 1))
            }
        }
    }

    @Test @MainActor func aRecordedFrameIsOneNodePerMeshAtTheTransformThatPlacedIt() {
        let scene = OllinApp.spatialScene(of: TwoBoxes(), frame: 0)
        #expect(scene.nodes.count == 2)
        #expect(near(scene.nodes[0].position, Vector3(-1.5, 0, 0), 1e-4))
        #expect(near(scene.nodes[1].position, Vector3(2.5, 0.5, 0), 1e-4))
        // The geometry stays in its own space rather than being baked flat,
        // which is what makes the node transform mean anything.
        let first = scene.nodes[0].mesh?.positions.first
        #expect(first.map { abs($0.x) <= 0.51 } ?? false,
                "the mesh came back world-placed instead of local")
    }

    @Test @MainActor func aRecordedFrameCarriesTheFillAsTheSurfaceColor() throws {
        let scene = OllinApp.spatialScene(of: TwoBoxes(), frame: 0)
        let red = try #require(scene.nodes[0].mesh?.material)
        let blue = try #require(scene.nodes[1].mesh?.material)
        #expect(red.baseColor.red > 0.9 && red.baseColor.blue < 0.1)
        #expect(blue.baseColor.blue > 0.9 && blue.baseColor.red < 0.1)
    }

    @Test @MainActor func aRecordedFrameCarriesItsCameraAndLights() throws {
        let scene = OllinApp.spatialScene(of: TwoBoxes(), frame: 0)
        let camera = try #require(scene.camera)
        #expect(near(camera.eye.length, 6, 1e-3))
        // The sketch set no lights, so the frame was shaded by the default rig
        // and that is what the model has to leave with.
        #expect(!scene.lights.isEmpty, "the auto-lit default didn't reach the export")
    }

    /// A sketch whose only 3D content is a point cloud, which is not a surface.
    private final class JustPoints: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            camera(.orbiting(radius: 6))
            drawPointCloud(PointCloud(points: [.init(position: .zero, color: .white, size: 1)]))
        }
    }

    @Test @MainActor func contentWithNoSurfaceIsLeftBehindRatherThanMisdrawn() {
        let scene = OllinApp.spatialScene(of: JustPoints(), frame: 0)
        #expect(scene.nodes.isEmpty, "a point cloud became geometry, which it isn't")
    }

    @Test @MainActor func aRecordedFrameWritesAPackageTheReaderOpens() throws {
        let scene = OllinApp.spatialScene(of: TwoBoxes(), frame: 0)
        let read = try roundTrip(scene, as: .usdz)
        #expect(meshes(read).count == 2)
        #expect(read.camera != nil)
    }

    // MARK: The finish mapping

    @Test func aPhysicallyBasedFinishCarriesAcrossAndAStylizedOneCarriesItsSheen() {
        var notes: [String] = []
        let metal = SpatialRecorder.previewSurface(
            .metal(roughness: 0.15), surface: .white, base: nil, notes: &notes)
        #expect(near(metal.metallic, 1, 1e-6))
        #expect(near(metal.roughness, 0.15, 1e-6))

        // A stylized look is a way of shading rather than a material, so what
        // survives is how shiny it is, through the same curve the renderer's
        // own area lights convert with.
        var toonNotes: [String] = []
        var toon = Material()
        toon.shading = .toon
        toon.shininess = 64
        let mapped = SpatialRecorder.previewSurface(toon, surface: .white, base: nil,
                                                    notes: &toonNotes)
        #expect(near(mapped.roughness, pow(2 / 66.0, 0.25), 1e-6))
        #expect(!toonNotes.isEmpty, "a stylized finish went out without saying what was lost")
    }

    @Test func glassLeavesAsSomethingYouCanSeeThrough() {
        var notes: [String] = []
        let glass = SpatialRecorder.previewSurface(
            .glass(roughness: 0.05, ior: 1.45), surface: .white, base: nil, notes: &notes)
        #expect(glass.opacity < 0.5, "glass exported opaque (opacity \(glass.opacity))")
        #expect(near(glass.ior, 1.45, 1e-6))
    }

    // MARK: The fabrication writer is not disturbed

    @Test func aFabricationPackageStaysCompressedAndUnaligned() {
        // 3MF and usdz share one ZIP writer but want opposite things, so this
        // pins that adding the package rules left the older caller alone.
        guard let data = Mesh.icosphere(radius: 10, subdivisions: 3)
            .data(as: .threeMF) else { return }
        #expect(data.readU16(at: 8) == 8, "a 3MF entry stopped being deflated")
    }

    // MARK: The system's own validator

    @Test func thePackagePassesTheSystemValidator() throws {
        let checker = URL(fileURLWithPath: "/usr/bin/usdchecker")
        guard FileManager.default.isExecutableFile(atPath: checker.path) else { return }

        var mesh = Mesh.icosphere(radius: 1, subdivisions: 2)
        mesh.material = MeshMaterial(baseColor: Color(red: 0.4, green: 0.6, blue: 0.9),
                                     metallic: 0.2, roughness: 0.35)
        var textured = lopsidedTriangle()
        textured.material = MeshMaterial(baseColor: .white,
                                         texture: Image(width: 8, height: 8, color: .green))
        var ball = SceneNode(name: "ball")
        ball.mesh = mesh
        var flag = SceneNode(name: "flag", position: Vector3(3, 0, 0))
        flag.mesh = textured
        var colored = SceneNode(name: "colored", position: Vector3(-3, 0, 0))
        var rainbow = lopsidedTriangle()
        rainbow.colors = [.red, .green, .blue]
        rainbow.material = MeshMaterial(baseColor: .white)
        colored.mesh = rainbow

        let scene = Scene(nodes: [ball, flag, colored],
                          cameras: [.orbiting(radius: 8)],
                          lights: [.point(.white, at: Vector3(2, 3, 4)),
                                   .directional(.white, direction: Vector3(0, -1, -0.3)),
                                   .rectangle(.white, at: Vector3(0, 4, 0),
                                         direction: Vector3(0, -1, 0), width: 2, height: 1),
                                   .disk(.white, at: Vector3(2, 4, 0),
                                         direction: Vector3(0, -1, 0), radius: 1),
                                   .tube(.white, from: Vector3(-2, 4, 0), to: Vector3(2, 4, 0)),
                                   .spot(.white, at: Vector3(0, 5, 0),
                                         direction: Vector3(0, -1, 0), coneAngle: .pi / 4,
                                         penumbra: 0.2)])

        let url = temporaryURL("checked.usdz")
        #expect(scene.write(to: url))
        defer { try? FileManager.default.removeItem(at: url) }

        // The profile Apple's own platforms hold a model to.
        let process = Process()
        process.executableURL = checker
        process.arguments = ["--arkit", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(),
                          as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "usdchecker --arkit refused the package:\n\(text)")
    }
}

// MARK: - Little-endian reads, for looking at a package's bytes

private extension Data {
    func readU16(at i: Int) -> UInt16 {
        UInt16(self[startIndex + i]) | (UInt16(self[startIndex + i + 1]) << 8)
    }
    func readU32(at i: Int) -> UInt32 {
        UInt32(self[startIndex + i]) | (UInt32(self[startIndex + i + 1]) << 8)
            | (UInt32(self[startIndex + i + 2]) << 16) | (UInt32(self[startIndex + i + 3]) << 24)
    }
}
