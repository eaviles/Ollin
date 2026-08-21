@testable import Ollin
import CoreGraphics
import Foundation
import ImageIO
import Testing

/// What a texture does past its own edges (`MeshMaterial.wrap`).
///
/// The render probes stage one plane whose uvs run 0…2 across it, wearing an
/// image that is black on its left half and white on its right. That makes the
/// plane read as four quarters, and the *third* one is the whole question: it
/// asks for u between 1 and 1.5, which is outside the image. Clamped it holds
/// the last texel and reads white; tiled it starts the image again and reads
/// black. One pixel patch separates the two answers, and no tolerance can blur
/// them together.
@Suite(.serialized)
@MainActor
struct TextureWrapTests {

    /// Black for the left half of the image, white for the right, in 8 texels so
    /// linear filtering never smears one half into the other at a patch center.
    static func halfAndHalf() -> Image {
        var image = Image(width: 8, height: 8, color: .black)
        for y in 0..<8 {
            for x in 4..<8 { image[x, y] = .white }
        }
        return image
    }

    final class Probe: Sketch {
        var wrap: TextureWrap = .clamp
        var traced = false

        override var canvasSize: CanvasSize { .square(240) }

        static func make(_ wrap: TextureWrap) -> Probe {
            let p = Probe()
            p.wrap = wrap
            return p
        }

        override func draw() {
            background(Color(hex: 0x304050))
            // Straight down on the plane, framed to its exact width, so screen x
            // is world x is u: the quarters land where the arithmetic says.
            ortho(eye: Vector3(0, 100, 0), target: .zero, up: Vector3(0, 0, -1),
                  height: 200)
            ambientLight(.white)
            var floor = Mesh.plane(width: 200, depth: 200)
            floor.uvs = floor.uvs.map { Vector2($0.x * 2, $0.y) }
            fill(.white)
            drawMesh(floor.textured(TextureWrapTests.halfAndHalf(), wrap: wrap))
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The mean of one channel over a fractional region of the frame.
    private func regionMean(_ image: CGImage, x0: Double, x1: Double,
                            y0: Double = 0.4, y1: Double = 0.6, channel: Int = 1) -> Double {
        let d = pixels(of: image)
        var sum = 0, count = 0
        for py in Int(Double(image.height) * y0)..<Int(Double(image.height) * y1) {
            for px in Int(Double(image.width) * x0)..<Int(Double(image.width) * x1) {
                sum += Int(d[(py * image.width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(max(count, 1))
    }

    /// The four quarter means, left to right across the plane.
    private func quarters(_ image: CGImage) -> [Double] {
        (0..<4).map { regionMean(image, x0: 0.03 + Double($0) * 0.25, x1: 0.22 + Double($0) * 0.25) }
    }

    private func render(_ wrap: TextureWrap) -> CGImage? {
        OllinApp.image(of: Probe.make(wrap), frame: 1)
    }

    /// The default: the edge pixel holds, so the picture is drawn once and its
    /// right-hand half smears across everything past it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func clampHoldsTheEdgePixel() throws {
        let q = quarters(try #require(render(.clamp)))
        #expect(q[0] < 40, "the first quarter should be the image's black half: \(q)")
        #expect(q[1] > 200 && q[2] > 200 && q[3] > 200,
                "everything past the first quarter should hold the white edge: \(q)")
    }

    /// `.tile` starts the picture again, which is what a floor or a wall wants.
    @Test(.enabled(if: Snapshot.hasMetal))
    func tileStartsThePictureAgain() throws {
        let q = quarters(try #require(render(.tile)))
        #expect(q[0] < 40 && q[2] < 40, "the tiled black halves: \(q)")
        #expect(q[1] > 200 && q[3] > 200, "the tiled white halves: \(q)")
    }

    /// `.mirror` repeats the picture flipped, so the second tile runs white then
    /// black and every tile meets its neighbor on the same color.
    @Test(.enabled(if: Snapshot.hasMetal))
    func mirrorFlipsEveryOtherTile() throws {
        let q = quarters(try #require(render(.mirror)))
        #expect(q[0] < 40, "the first quarter is still the black half: \(q)")
        #expect(q[1] > 200 && q[2] > 200, "the two white halves meet in the middle: \(q)")
        #expect(q[3] < 40, "the mirrored tile ends where it started: \(q)")
    }

    /// The whole point of the default: a mesh whose uvs stay inside the square
    /// draws the same picture whatever it says about wrapping, so turning tiling
    /// on can never disturb a sketch that never leaves 0…1.
    ///
    /// *Strictly* inside: at u or v exactly 0 or 1, linear filtering reaches
    /// half a texel past the edge, and there the modes really do differ (clamp
    /// repeats the edge texel, tile blends in the far one). This probe keeps
    /// the uvs off the border so it measures the claim rather than that seam.
    @Test(.enabled(if: Snapshot.hasMetal))
    func insideTheSquareEveryModeAgrees() throws {
        final class InRange: Sketch {
            var wrap: TextureWrap = .clamp
            override var canvasSize: CanvasSize { .square(240) }
            override func draw() {
                background(Color(hex: 0x304050))
                ortho(eye: Vector3(0, 100, 0), target: .zero, up: Vector3(0, 0, -1),
                      height: 200)
                ambientLight(.white)
                fill(.white)
                // A window in the middle of the image: 0.1…0.6 on both axes,
                // so no sample lands on the border.
                var floor = Mesh.plane(width: 200, depth: 200)
                floor.uvs = floor.uvs.map { Vector2(0.1 + $0.x * 0.5, 0.1 + $0.y * 0.5) }
                drawMesh(floor.textured(TextureWrapTests.halfAndHalf(), wrap: wrap))
            }
        }
        func frame(_ wrap: TextureWrap) -> [UInt8]? {
            let s = InRange(); s.wrap = wrap
            return OllinApp.image(of: s, frame: 1).map(pixels(of:))
        }
        let clamped = try #require(frame(.clamp))
        #expect(try #require(frame(.tile)) == clamped)
        #expect(try #require(frame(.mirror)) == clamped)
    }

    /// Raster parity: the traced export tiles the same way, since an exported
    /// still of a tiled floor that stopped tiling would be a different picture
    /// from the one on screen.
    @Test(.enabled(if: Snapshot.hasRaytracing))
    func theTracedExportTilesTheSameWay() throws {
        OllinApp.pathTracedExport = PathTracing(samplesPerPixel: 8, denoise: false)
        defer { OllinApp.pathTracedExport = nil }
        let q = quarters(try #require(render(.tile)))
        #expect(q[0] < 60 && q[2] < 60, "the traced black halves: \(q)")
        #expect(q[1] > 150 && q[3] > 150, "the traced white halves: \(q)")
    }

    // MARK: - What the file says

    /// glTF states wrapping per texture, and its own default is repeat, so a
    /// file that declares no sampler at all describes a tiling texture. Reading
    /// it as clamp is what keeps an authored tiling floor from tiling.
    @Test func aGLTFTextureWithNoSamplerTiles() throws {
        let mesh = try #require(Mesh(contentsOf: try gltfFile(sampler: nil)))
        #expect(try #require(mesh.material).wrap == .tile)
    }

    /// The declared modes, read as the format spells them: 33071 clamp to edge,
    /// 33648 mirrored repeat, 10497 repeat.
    @Test(arguments: [(33071, TextureWrap.clamp), (33648, .mirror), (10497, .tile)])
    func aGLTFSamplerIsReadAsWritten(_ code: Int, _ expected: TextureWrap) throws {
        let mesh = try #require(Mesh(contentsOf: try gltfFile(sampler: code)))
        #expect(try #require(mesh.material).wrap == expected)
    }

    /// A one-triangle glTF wearing a texture, with `wrapS` set as given (or no
    /// sampler declared at all when `nil`).
    private func gltfFile(sampler code: Int?) throws -> URL {
        var buffer = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        for f: Float in [0, 0, 1, 0, 0, 1] {
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        for i: UInt16 in [0, 1, 2] {
            withUnsafeBytes(of: i) { buffer.append(contentsOf: $0) }
        }
        let b64 = buffer.base64EncodedString()
        let png = TextureWrapTests.solidPNG(rgb: (0, 0, 1)).base64EncodedString()
        let texture = code == nil ? "{\"source\": 0}" : "{\"source\": 0, \"sampler\": 0}"
        let samplers = code.map { ", \"samplers\": [{\"wrapS\": \($0), \"wrapT\": \($0)}]" } ?? ""
        let json = """
        { "asset": {"version": "2.0"},
          "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"mesh": 0}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "indices": 2, "mode": 4, "material": 0}]}],
          "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
          "textures": [\(texture)]\(samplers),
          "images": [{"uri": "data:image/png;base64,\(png)"}],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC2"},
            {"bufferView": 2, "componentType": 5123, "count": 3, "type": "SCALAR"}],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 24},
            {"buffer": 0, "byteOffset": 60, "byteLength": 6}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(b64)", "byteLength": \(buffer.count)}]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-wrap-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The `.mtl` format has one word about wrapping and it turns tiling off, so
    /// an unmarked map tiles and `-clamp on` is the exception.
    @Test(arguments: [("", TextureWrap.tile), ("-clamp on ", .clamp), ("-clamp off ", .tile)])
    func anMTLMapTilesUnlessItSaysOtherwise(_ option: String, _ expected: TextureWrap) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-mtl-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try TextureWrapTests.solidPNG(rgb: (1, 0, 0)).write(to: dir.appendingPathComponent("skin.png"))
        try """
        newmtl painted
        Kd 1 1 1
        map_Kd \(option)skin.png
        """.write(to: dir.appendingPathComponent("model.mtl"), atomically: true, encoding: .utf8)
        try """
        mtllib model.mtl
        usemtl painted
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vt 0 0
        vt 1 0
        vt 0 1
        f 1/1 2/2 3/3
        """.write(to: dir.appendingPathComponent("model.obj"), atomically: true, encoding: .utf8)

        let mesh = try #require(Mesh(contentsOf: dir.appendingPathComponent("model.obj")))
        #expect(try #require(mesh.material).wrap == expected)
    }

    /// The USD writer says what the material says, so a tiling floor written out
    /// and read back is still tiling. (The reader keeps clamp for a file that
    /// states nothing, since the spec defers that to image metadata Ollin does
    /// not read.) A texture needs the package format: a text layer has nowhere
    /// to keep the image.
    @Test(arguments: [TextureWrap.clamp, .tile, .mirror])
    func aWrapModeSurvivesAUSDRoundTrip(_ wrap: TextureWrap) throws {
        var floor = Mesh.plane(width: 2, depth: 2)
        floor.material = MeshMaterial(texture: TextureWrapTests.halfAndHalf(), wrap: wrap)
        var node = SceneNode(name: "floor")
        node.mesh = floor
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-wrap-\(UUID().uuidString).usdz")
        #expect(Scene(nodes: [node]).write(to: url))
        defer { try? FileManager.default.removeItem(at: url) }
        let read = try #require(Scene(contentsOf: url))
        func firstMesh(_ nodes: [SceneNode]) -> Mesh? {
            for node in nodes {
                if let mesh = node.mesh { return mesh }
                if let found = firstMesh(node.children) { return found }
            }
            return nil
        }
        let back = try #require(firstMesh(read.nodes))
        #expect(back.material?.wrap == wrap)
    }

    /// A small solid-color PNG as `Data`, for embedding a texture in a fixture.
    private static func solidPNG(rgb: (Double, Double, Double)) -> Data {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                            bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
}
