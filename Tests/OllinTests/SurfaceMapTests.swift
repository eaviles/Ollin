import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// The PBR map set: metallic-roughness, occlusion, and emissive maps on
/// `MeshMaterial`, the `surfaceMapped(...)` sugar, the glTF and USD readers
/// that fill them, the USD writer's round trip, and the surface-mapped render
/// path. The CPU half pins the attach/compose rules and both loaders' channel
/// handling (the packed reuse, the repack, the scale/bias factor recovery);
/// the Metal-gated probes pin the draw contract against counterfactuals: a
/// metallic map splits one surface where the mapless control shades evenly,
/// occlusion dims only indirect light, emission adds light with none set, the
/// factors multiply the sample (a zero factor makes any map inert, byte for
/// byte), and the gates keep unmapped routing untouched.
@Suite
@MainActor
struct SurfaceMapTests {

    // MARK: - Authoring helpers

    /// A solid-color 8×8 map with explicit byte channels.
    private func solidMap(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    /// Left half one set of channels, right half another.
    private func splitMap(left: (UInt8, UInt8, UInt8), right: (UInt8, UInt8, UInt8)) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<8 {
                let c = x < 4 ? left : right
                let i = (y * 8 + x) * 4
                bytes[i] = c.0; bytes[i + 1] = c.1; bytes[i + 2] = c.2
            }
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-surface-maps-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - The convenience

    @Test func surfaceMappedAttachesTheSetWithIdentityFactors() throws {
        let orm = solidMap(255, 128, 64)
        let ao = solidMap(200, 200, 200)
        let glowMap = solidMap(0, 255, 255)
        let mesh = Mesh.sphere(radius: 1, segments: 8, rings: 4)
            .surfaceMapped(metallicRoughness: orm, occlusion: ao, occlusionStrength: 0.7,
                           emissive: glowMap)
        let m = try #require(mesh.material)
        #expect(m.metallicRoughnessTexture === orm)
        #expect(m.occlusionTexture === ao)
        #expect(m.occlusionStrength == 0.7)
        #expect(m.emissiveTexture === glowMap)
        // Attaching a metallic-roughness map sets the identity factors (the
        // carried defaults, 0 and 0.5, would kill or halve the map), and an
        // emissive map with no color emits at full strength.
        #expect(m.metallic == 1 && m.roughness == 1)
        #expect(m.emissiveColor.red == 1 && m.emissiveColor.green == 1
                && m.emissiveColor.blue == 1)
    }

    @Test func surfaceMappedComposesWithTexturedAndNormalMapped() throws {
        let wood = solidMap(180, 140, 100)
        let bumps = solidMap(127, 127, 255)
        let orm = solidMap(255, 90, 30)
        let mesh = Mesh.sphere(radius: 1, segments: 8, rings: 4)
            .textured(wood).normalMapped(bumps).surfaceMapped(metallicRoughness: orm)
        let m = try #require(mesh.material)
        #expect(m.texture === wood)
        #expect(m.normalTexture === bumps)
        #expect(m.metallicRoughnessTexture === orm)
        // A constant emissive color needs no map.
        let glowing = mesh.surfaceMapped(emissiveColor: Color(red: 0.2, green: 0.4, blue: 0.6))
        #expect(glowing.material?.emissiveTexture == nil)
        #expect(glowing.material?.emissiveColor.blue == 0.6)
        #expect(glowing.material?.metallicRoughnessTexture === orm,
                "surfaceMapped must leave the channels it wasn't given alone")
    }

    // MARK: - The glTF reader

    @Test func gltfMaterialCarriesThePBRMapSet() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Distinct solid colors per image, so a swapped channel shows up.
        try #require(solidMap(10, 200, 90).pngData()).write(to: dir.appendingPathComponent("orm.png"))
        try #require(solidMap(240, 240, 240).pngData()).write(to: dir.appendingPathComponent("ao.png"))
        try #require(solidMap(0, 80, 255).pngData()).write(to: dir.appendingPathComponent("glow.png"))

        // One indexed triangle wearing the full map set.
        var buffer = Data()
        for v: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
            withUnsafeBytes(of: v) { buffer.append(contentsOf: $0) }
        }
        for i: UInt16 in [0, 1, 2] {
            withUnsafeBytes(of: i) { buffer.append(contentsOf: $0) }
        }
        let json = """
        { "asset": {"version": "2.0"},
          "scene": 0,
          "scenes": [{"nodes": [0]}],
          "nodes": [{"mesh": 0}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}]}],
          "materials": [{
            "pbrMetallicRoughness": {
              "metallicRoughnessTexture": {"index": 0},
              "metallicFactor": 0.75,
              "roughnessFactor": 0.4
            },
            "occlusionTexture": {"index": 1, "strength": 0.6},
            "emissiveTexture": {"index": 2},
            "emissiveFactor": [1, 0.5, 0.25]
          }],
          "textures": [{"source": 0}, {"source": 1}, {"source": 2}],
          "images": [{"uri": "orm.png"}, {"uri": "ao.png"}, {"uri": "glow.png"}],
          "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
                        {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}],
          "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36},
                          {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(buffer.base64EncodedString())",
                       "byteLength": 42}]
        }
        """
        let url = dir.appendingPathComponent("mapped.gltf")
        try json.data(using: .utf8)!.write(to: url)

        let mesh = try #require(Mesh(contentsOf: url))
        let m = try #require(mesh.material)
        #expect((m.metallicRoughnessTexture?[0, 0].green ?? 0) > 0.7,
                "the packed map's green channel should read back")
        #expect((m.occlusionTexture?[0, 0].red ?? 0) > 0.9)
        #expect((m.emissiveTexture?[0, 0].blue ?? 0) > 0.9)
        #expect(abs(m.metallic - 0.75) < 1e-9)
        #expect(abs(m.roughness - 0.4) < 1e-9)
        #expect(abs(m.occlusionStrength - 0.6) < 1e-9)
        // The emissive factor is authored linear; the reader re-encodes to the
        // display-encoded Color like every glTF factor.
        #expect(abs(m.emissiveColor.red - 1) < 1e-6)
        #expect(abs(m.emissiveColor.green - Color.linearToSrgb(0.5)) < 1e-6)
    }

    // MARK: - The USD reader

    /// A quad layer binding one preview surface whose inputs are given
    /// verbatim, plus whatever PNGs the caller wrote beside it.
    private func usdaQuad(materialInputs: String, shaders: String) -> String {
        """
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
         def Mesh "quad"
         {
          point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
          int[] faceVertexCounts = [4]
          int[] faceVertexIndices = [0, 1, 2, 3]
          normal3f[] normals = [(0, 0, 1), (0, 0, 1), (0, 0, 1), (0, 0, 1)] (
           interpolation = "vertex"
          )
          texCoord2f[] primvars:st = [(0, 0), (1, 0), (1, 1), (0, 1)] (
           interpolation = "vertex"
          )
          rel material:binding = </Root/Materials/mat>
         }
         def Scope "Materials"
         {
          def Material "mat"
          {
           token outputs:surface.connect = </Root/Materials/mat/surface.outputs:surface>
           def Shader "st"
           {
            uniform token info:id = "UsdPrimvarReader_float2"
            string inputs:varname = "st"
            float2 outputs:result
           }
        \(shaders)
           def Shader "surface"
           {
            uniform token info:id = "UsdPreviewSurface"
        \(materialInputs)
            token outputs:surface
           }
          }
         }
        }
        """
    }

    private func textureShader(_ name: String, file: String, scale: String? = nil,
                               bias: String? = nil, outputs: [String]) -> String {
        var s = "   def Shader \"\(name)\"\n   {\n"
        s += "    uniform token info:id = \"UsdUVTexture\"\n"
        s += "    asset inputs:file = @./\(file)@\n"
        s += "    float2 inputs:st.connect = </Root/Materials/mat/st.outputs:result>\n"
        s += "    token inputs:sourceColorSpace = \"raw\"\n"
        if let scale { s += "    float4 inputs:scale = \(scale)\n" }
        if let bias { s += "    float4 inputs:bias = \(bias)\n" }
        for o in outputs { s += "    \(o)\n" }
        s += "   }\n"
        return s
    }

    private func loadUSDQuadMaterial(_ text: String, images: [(String, Image)]) throws -> (MeshMaterial, Mesh) {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (name, image) in images {
            try #require(image.pngData()).write(to: dir.appendingPathComponent(name))
        }
        let url = dir.appendingPathComponent("scene.usda")
        try text.data(using: .utf8)!.write(to: url)
        let scene = try #require(Scene(contentsOf: url))
        let mesh = try #require(scene.nodes.first?.mesh ?? scene.nodes.first?.children.first?.mesh)
        return (try #require(mesh.material), mesh)
    }

    @Test func usdPreviewSurfaceReadsThePackedMapSet() throws {
        // The canonical arrangement: one ORM file feeding occlusion (r),
        // roughness (g), and metallic (b), a normal map whose scale/bias carry
        // its strength, an emissive map whose scale is the factor, and the
        // carried constants.
        let shaders = textureShader("orm", file: "orm.png",
                                    scale: "(0.9, 0.8, 0.7, 1)", bias: "(0.1, 0, 0, 0)",
                                    outputs: ["float outputs:r", "float outputs:g", "float outputs:b"])
            + textureShader("nrm", file: "normal.png",
                            scale: "(1.6, 1.6, 2, 1)", bias: "(-0.8, -0.8, -1, 0)",
                            outputs: ["float3 outputs:rgb"])
            + textureShader("emit", file: "glow.png",
                            scale: "(0.25, 0.5, 1, 1)",
                            outputs: ["float3 outputs:rgb"])
        let inputs = """
            float inputs:metallic.connect = </Root/Materials/mat/orm.outputs:b>
            float inputs:roughness.connect = </Root/Materials/mat/orm.outputs:g>
            float inputs:occlusion.connect = </Root/Materials/mat/orm.outputs:r>
            normal3f inputs:normal.connect = </Root/Materials/mat/nrm.outputs:rgb>
            color3f inputs:emissiveColor.connect = </Root/Materials/mat/emit.outputs:rgb>
            float inputs:ior = 1.42
            float inputs:opacity = 0.9
        """
        let (m, mesh) = try loadUSDQuadMaterial(
            usdaQuad(materialInputs: inputs, shaders: shaders),
            images: [("orm.png", solidMap(255, 120, 30)),
                     ("normal.png", solidMap(127, 127, 255)),
                     ("glow.png", solidMap(255, 255, 255))])
        // One file, standard channels: the image itself is the packed map, and
        // occlusion shares the very same instance (the asset-store cache).
        #expect(m.metallicRoughnessTexture != nil)
        #expect(m.metallicRoughnessTexture === m.occlusionTexture)
        // The factors are the taps' channel scales; strength is the r scale.
        #expect(abs(m.metallic - 0.7) < 1e-6)
        #expect(abs(m.roughness - 0.8) < 1e-6)
        #expect(abs(m.occlusionStrength - 0.9) < 1e-6)
        // The normal map's strength comes back out of its decode.
        #expect(m.normalTexture != nil)
        #expect(abs(m.normalScale - 0.8) < 1e-6)
        // The emissive factor is the map's scale, linear re-encoded.
        #expect(m.emissiveTexture != nil)
        #expect(abs(m.emissiveColor.red - Color.linearToSrgb(0.25)) < 1e-6)
        #expect(abs(m.emissiveColor.green - Color.linearToSrgb(0.5)) < 1e-6)
        // Carried constants.
        #expect(abs(m.ior - 1.42) < 1e-6)
        #expect(abs(m.opacity - 0.9) < 1e-6)
        // A normal-mapped USD mesh generates its MikkTSpace basis (USD has no
        // authored-tangent attribute).
        #expect(mesh.tangents.count == mesh.positions.count)
    }

    @Test func usdSeparateChannelTexturesRepackIntoTheStandardLayout() throws {
        // Metallic and roughness authored as two separate grayscale files,
        // each tapped at r: the reader must repack them into one image with
        // roughness in g and metallic in b (white where untapped).
        let shaders = textureShader("metal", file: "metal.png",
                                    outputs: ["float outputs:r"])
            + textureShader("rough", file: "rough.png",
                            outputs: ["float outputs:r"])
        let inputs = """
            float inputs:metallic.connect = </Root/Materials/mat/metal.outputs:r>
            float inputs:roughness.connect = </Root/Materials/mat/rough.outputs:r>
        """
        let (m, _) = try loadUSDQuadMaterial(
            usdaQuad(materialInputs: inputs, shaders: shaders),
            images: [("metal.png", solidMap(153, 10, 10)),
                     ("rough.png", solidMap(77, 20, 20))])
        let packed = try #require(m.metallicRoughnessTexture)
        let px = try #require(packed.premultipliedPixels())
        #expect(px[1] == 77, "roughness's r channel must land in g, got \(px[1])")
        #expect(px[2] == 153, "metallic's r channel must land in b, got \(px[2])")
        #expect(px[0] == 255, "the untapped channel reads white")
        // A connected input with no scale is the identity factor.
        #expect(m.metallic == 1 && m.roughness == 1)
    }

    // MARK: - The USD writer's round trip

    @Test func usdzRoundTripKeepsTheMapSet() throws {
        var mesh = Mesh.plane(width: 2, depth: 2)
        var material = MeshMaterial(baseColor: .white,
                                    texture: solidMap(200, 150, 100))
        material.normalTexture = solidMap(127, 127, 255)
        material.normalScale = 1.5
        let orm = solidMap(255, 120, 30)
        material.metallicRoughnessTexture = orm
        material.occlusionTexture = orm          // the shared-ORM arrangement
        material.occlusionStrength = 0.65
        material.emissiveTexture = solidMap(0, 200, 255)
        material.emissiveColor = Color(red: 0.9, green: 0.5, blue: 0.2)
        material.metallic = 0.7
        material.roughness = 0.8
        mesh.material = material
        var node = SceneNode(name: "panel")
        node.mesh = mesh

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-surface-maps-\(UUID().uuidString).usdz")
        #expect(Scene(nodes: [node]).write(to: url))
        defer { try? FileManager.default.removeItem(at: url) }
        let back = try #require(Scene(contentsOf: url))
        func firstMesh(_ nodes: [SceneNode]) -> Mesh? {
            for n in nodes {
                if let mesh = n.mesh { return mesh }
                if let hit = firstMesh(n.children) { return hit }
            }
            return nil
        }
        let m = try #require(firstMesh(back.nodes)?.material)
        #expect((m.texture?[0, 0].red ?? 0) > 0.7)
        #expect(m.normalTexture != nil)
        #expect(abs(m.normalScale - 1.5) < 1e-5)
        let packed = try #require(m.metallicRoughnessTexture)
        #expect(packed === m.occlusionTexture, "the shared ORM must come back shared")
        let px = try #require(packed.premultipliedPixels())
        #expect(px[0] == 255 && px[1] == 120 && px[2] == 30,
                "the packed channels must survive the trip, got \(px[0...2])")
        #expect(abs(m.metallic - 0.7) < 1e-5)
        #expect(abs(m.roughness - 0.8) < 1e-5)
        #expect(abs(m.occlusionStrength - 0.65) < 1e-5)
        #expect((m.emissiveTexture?[0, 0].blue ?? 0) > 0.9)
        #expect(abs(m.emissiveColor.red - 0.9) < 1e-3)
        #expect(abs(m.emissiveColor.green - 0.5) < 1e-3)
        #expect(abs(m.emissiveColor.blue - 0.2) < 1e-3)
    }

    @Test func aMappedPackagePassesTheSystemValidator() throws {
        let checker = URL(fileURLWithPath: "/usr/bin/usdchecker")
        guard FileManager.default.isExecutableFile(atPath: checker.path) else { return }

        var mesh = Mesh.plane(width: 2, depth: 2)
        var material = MeshMaterial(baseColor: .white, texture: solidMap(200, 150, 100))
        material.normalTexture = solidMap(127, 127, 255)
        let orm = solidMap(255, 120, 30)
        material.metallicRoughnessTexture = orm
        material.occlusionTexture = orm
        material.emissiveTexture = solidMap(0, 200, 255)
        material.emissiveColor = .white
        material.metallic = 1
        material.roughness = 1
        mesh.material = material
        var node = SceneNode(name: "panel")
        node.mesh = mesh

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-surface-maps-\(UUID().uuidString).usdz")
        #expect(Scene(nodes: [node]).write(to: url))
        defer { try? FileManager.default.removeItem(at: url) }

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
        #expect(process.terminationStatus == 0, "usdchecker --arkit refused the mapped package:\n\(text)")
    }

    // MARK: - Render probes

    private func pixel(of image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let bytes = imageBytes(image)
        let i = (y * image.width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    private func imageBytes(_ image: CGImage) -> [UInt8] {
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

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMetallicMapSplitsOneSurface() throws {
        // Left half dielectric (b 0), right half metal (b 255), under one
        // frontal light with no environment: the metal half loses its diffuse
        // body and reads darker, the dielectric half keeps it. The margin is
        // modest on purpose: at roughness 1 the metal half keeps its
        // multiple-scattering compensated specular (the energy a bare
        // single-scatter lobe drops), so the split is a clear step rather
        // than a cliff (measured 120 vs 95). The mapless control (the same
        // finish) shades both halves equal.
        let mapped = try #require(OllinApp.image(of: SurfaceMapProbe.make(.metalSplit), frame: 1))
        let left = pixel(of: mapped, x: 64, y: 128).r
        let right = pixel(of: mapped, x: 192, y: 128).r
        #expect(left - right > 12, "expected the metal half darker, got \(left) vs \(right)")
        let control = try #require(OllinApp.image(of: SurfaceMapProbe.make(.metalControl), frame: 1))
        let cl = pixel(of: control, x: 64, y: 128).r
        let cr = pixel(of: control, x: 192, y: 128).r
        #expect(abs(cl - cr) <= 2, "the control must shade evenly, got \(cl) vs \(cr)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRoughnessMapSpreadsTheHighlight() throws {
        // Rough left (g 230), polished right (g 25), lit head-on so the
        // specular peak sits at the quad's center: away from the peak the
        // rough half's wide lobe holds more energy than the polished half's
        // tight one, measured at mirrored off-peak points.
        let img = try #require(OllinApp.image(of: SurfaceMapProbe.make(.roughSplit), frame: 1))
        let rough = pixel(of: img, x: 64, y: 128).r
        let smooth = pixel(of: img, x: 192, y: 128).r
        #expect(rough - smooth > 15,
                "the rough half must be brighter off-peak, got \(rough) vs \(smooth)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anOcclusionMapDimsOnlyTheIndirectLight() throws {
        // Under ambient light alone, the occluded (black-map) half darkens;
        // under a direct light alone the same map must change nothing at all,
        // because baked occlusion is an indirect-light fact (the glTF rule).
        let ambient = try #require(OllinApp.image(of: SurfaceMapProbe.make(.aoAmbient), frame: 1))
        let dark = pixel(of: ambient, x: 64, y: 128).r
        let open = pixel(of: ambient, x: 192, y: 128).r
        #expect(open - dark > 40, "occlusion must dim the ambient, got \(dark) vs \(open)")
        let direct = try #require(OllinApp.image(of: SurfaceMapProbe.make(.aoDirect), frame: 1))
        let dl = pixel(of: direct, x: 64, y: 128).r
        let dr = pixel(of: direct, x: 192, y: 128).r
        #expect(abs(dl - dr) <= 2, "occlusion must not touch direct light, got \(dl) vs \(dr)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anEmissiveMapAddsItsOwnLight() throws {
        // No lights at all: a black surface with an emissive map still shows
        // the map's color times the factor; with the factor black (the
        // format's default) the same map emits nothing.
        let lit = try #require(OllinApp.image(of: SurfaceMapProbe.make(.emissive), frame: 1))
        let p = pixel(of: lit, x: 128, y: 128)
        #expect(p.b > 100, "the emissive map must show unlit, got \(p)")
        #expect(p.b > p.r + 40, "the emission carries the map's color, got \(p)")
        let off = try #require(OllinApp.image(of: SurfaceMapProbe.make(.emissiveBlackFactor), frame: 1))
        let q = pixel(of: off, x: 128, y: 128)
        #expect(q.b < 20, "a black factor emits nothing (the format's default), got \(q)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFactorsMultiplyTheSample() throws {
        // Metallic factor 0: a full-metal map and a no-metal map must render
        // byte-identically, because the factor multiplies the sample. This is
        // the composition order pin; it fails if the map replaced the factor.
        let white = try #require(OllinApp.image(of: SurfaceMapProbe.make(.factorZeroMetalMap), frame: 1))
        let black = try #require(OllinApp.image(of: SurfaceMapProbe.make(.factorZeroDielectricMap), frame: 1))
        #expect(imageBytes(white) == imageBytes(black))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func strengthZeroOcclusionRoutesDownThePlainPath() throws {
        // occlusionStrength 0 is the off switch: the drawer never raises the
        // surface-map gates, so the frame is byte-identical to the same mesh
        // with no occlusion map attached at all.
        let off = try #require(OllinApp.image(of: SurfaceMapProbe.make(.aoStrengthZero), frame: 1))
        let none = try #require(OllinApp.image(of: SurfaceMapProbe.make(.texturedOnly), frame: 1))
        #expect(imageBytes(off) == imageBytes(none))
    }
}

/// The camera-facing quad the surface-map render probes draw, one lighting
/// arrangement per mode.
private final class SurfaceMapProbe: Sketch {
    enum Mode {
        case metalSplit, metalControl, roughSplit, aoAmbient, aoDirect
        case emissive, emissiveBlackFactor, factorZeroMetalMap, factorZeroDielectricMap
        case aoStrengthZero, texturedOnly
    }
    var mode = Mode.metalSplit

    static func make(_ mode: Mode) -> SurfaceMapProbe {
        let probe = SurfaceMapProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    private func split(left: (UInt8, UInt8, UInt8), right: (UInt8, UInt8, UInt8)) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<8 {
                let c = x < 4 ? left : right
                let i = (y * 8 + x) * 4
                bytes[i] = c.0; bytes[i + 1] = c.1; bytes[i + 2] = c.2
            }
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    private func quad() -> Mesh {
        Mesh(positions: [Vector3(-1, -1, 0), Vector3(1, -1, 0),
                         Vector3(1, 1, 0), Vector3(-1, 1, 0)],
             normals: [.unitZ, .unitZ, .unitZ, .unitZ],
             indices: [0, 1, 2, 0, 2, 3],
             uvs: [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
    }

    override func draw() {
        background(.black)
        camera(.orbiting(radius: 3))
        fill(Color(white: 0.8))
        var mesh = quad()
        switch mode {
        case .metalSplit:
            material(.physicallyBased(metallic: 1, roughness: 1))
            directionalLight(.white, direction: Vector3(0, 0, -1))
            mesh = mesh.surfaceMapped(metallicRoughness: split(left: (255, 255, 0),
                                                               right: (255, 255, 255)))
        case .metalControl:
            material(.physicallyBased(metallic: 1, roughness: 1))
            directionalLight(.white, direction: Vector3(0, 0, -1))
            mesh = mesh.surfaceMapped(metallicRoughness: solid(255, 255, 0))
        case .roughSplit:
            material(.physicallyBased(metallic: 1, roughness: 1))
            directionalLight(.white, direction: Vector3(0, 0, -1), intensity: 2)
            mesh = mesh.surfaceMapped(metallicRoughness: split(left: (255, 230, 255),
                                                               right: (255, 25, 255)))
        case .aoAmbient:
            ambientLight(Color(white: 0.8))
            mesh = mesh.surfaceMapped(occlusion: split(left: (0, 0, 0), right: (255, 255, 255)))
        case .aoDirect:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            mesh = mesh.surfaceMapped(occlusion: split(left: (0, 0, 0), right: (255, 255, 255)))
        case .emissive:
            fill(.black)
            mesh = mesh.surfaceMapped(emissive: solid(30, 120, 220))
        case .emissiveBlackFactor:
            fill(.black)
            mesh = mesh.surfaceMapped(emissive: solid(30, 120, 220), emissiveColor: .black)
        case .factorZeroMetalMap:
            material(.physicallyBased(metallic: 0, roughness: 0.5))
            directionalLight(.white, direction: Vector3(0, 0, -1))
            mesh = mesh.surfaceMapped(metallicRoughness: solid(255, 128, 255))
            mesh.material?.metallic = 0
        case .factorZeroDielectricMap:
            material(.physicallyBased(metallic: 0, roughness: 0.5))
            directionalLight(.white, direction: Vector3(0, 0, -1))
            mesh = mesh.surfaceMapped(metallicRoughness: solid(255, 128, 0))
            mesh.material?.metallic = 0
        case .aoStrengthZero:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            mesh = mesh.textured(solid(255, 255, 255))
                .surfaceMapped(occlusion: solid(0, 0, 0), occlusionStrength: 0)
        case .texturedOnly:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            mesh = mesh.textured(solid(255, 255, 255))
        }
        drawMesh(mesh)
    }
}
