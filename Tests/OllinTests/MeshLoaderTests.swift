import Testing
import Foundation
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Ollin
#if canImport(ModelIO)
import ModelIO
#endif

/// GPU-free checks on loading a `Mesh` from a file: the hand-written Wavefront OBJ
/// reader, the glTF/GLB reader (an inline data-URI fixture, so it needs no asset),
/// a Model I/O round-trip (export a box to USD, read it back), and the bounds/fit
/// helpers. None of these touch Metal.
struct MeshLoaderTests {

    // MARK: OBJ

    /// A cube as OBJ (positions + per-face normals + quad faces) parses to 12
    /// triangles with unit normals; quads are fan-triangulated.
    @Test func objParsesCubeWithNormals() {
        let obj = """
        # a unit cube
        v -1 -1 -1
        v  1 -1 -1
        v  1  1 -1
        v -1  1 -1
        v -1 -1  1
        v  1 -1  1
        v  1  1  1
        v -1  1  1
        vn  0  0 -1
        vn  0  0  1
        vn -1  0  0
        vn  1  0  0
        vn  0 -1  0
        vn  0  1  0
        f 1//1 2//1 3//1 4//1
        f 5//2 8//2 7//2 6//2
        f 1//3 4//3 8//3 5//3
        f 2//4 6//4 7//4 3//4
        f 1//5 5//5 6//5 2//5
        f 4//6 3//6 7//6 8//6
        """
        let mesh = Mesh(objSource: obj)
        #expect(mesh != nil)
        guard let mesh else { return }
        #expect(mesh.triangleCount == 12)                 // 6 quads × 2
        #expect(mesh.normals.count == mesh.positions.count)
        for n in mesh.normals { #expect(abs(n.length - 1) < 1e-6) }
        for i in mesh.indices { #expect(Int(i) < mesh.positions.count) }
    }

    /// With no `vn` lines, smooth normals are computed, a single triangle in the x–y
    /// plane (CCW) gets the +z face normal.
    @Test func objComputesNormalsWhenAbsent() {
        let obj = "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
        let mesh = Mesh(objSource: obj)
        #expect(mesh != nil)
        guard let mesh else { return }
        #expect(mesh.triangleCount == 1)
        #expect(mesh.positions.count == 3)
        for n in mesh.normals {
            #expect(abs(n.x) < 1e-6 && abs(n.y) < 1e-6 && abs(n.z - 1) < 1e-6)
        }
    }

    /// Negative (relative) indices resolve against the count so far, and `vt`/`o`/`s`
    /// and malformed lines are skipped, not trapped.
    @Test func objHandlesNegativeIndicesAndJunk() {
        let obj = """
        o thing
        s 1
        v 0 0 0
        v 1 0 0
        v 0 1 0
        vt 0 0
        garbage line that is not valid
        f -3 -2 -1
        """
        let mesh = Mesh(objSource: obj)
        #expect(mesh != nil)
        #expect(mesh?.triangleCount == 1)
    }

    /// Empty or geometry-free source yields nil, not a trap.
    @Test func objRejectsEmpty() {
        #expect(Mesh(objSource: "") == nil)
        #expect(Mesh(objSource: "# just a comment\no nothing\n") == nil)
    }

    // MARK: glTF

    /// A minimal glTF 2.0 with an embedded base64 buffer and a node scale matrix:
    /// one triangle, no normals. Exercises data-URI decode, accessor reading,
    /// node-transform baking (×2 scale), and computed normals, no external asset.
    @Test func gltfReadsEmbeddedTriangleAndBakesTransform() throws {
        var buffer = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {          // 3 positions (VEC3)
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        for i: UInt16 in [0, 1, 2] {                            // 3 indices (SCALAR)
            withUnsafeBytes(of: i) { buffer.append(contentsOf: $0) }
        }
        let b64 = buffer.base64EncodedString()
        let json = """
        { "asset": {"version": "2.0"},
          "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"mesh": 0, "matrix": [2,0,0,0, 0,2,0,0, 0,0,2,0, 0,0,0,1]}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "mode": 4}]}],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(b64)", "byteLength": \(buffer.count)}]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mesh = Mesh(contentsOf: url)
        #expect(mesh != nil)
        guard let mesh else { return }
        #expect(mesh.triangleCount == 1)
        // The node matrix scales the triangle ×2.
        let maxX = mesh.positions.map(\.x).max() ?? 0
        let maxY = mesh.positions.map(\.y).max() ?? 0
        #expect(abs(maxX - 2) < 1e-5 && abs(maxY - 2) < 1e-5)
        // Computed normal of the CCW x–y triangle points +z.
        for n in mesh.normals { #expect(abs(n.z - 1) < 1e-5) }
    }

    /// A glTF triangle that carries TEXCOORD_0 and a base-color material (a factor
    /// plus an embedded PNG texture): exercises UV reading, the linear→sRGB base-color
    /// conversion, and decoding the texture image from a data-URI. No external asset.
    @Test func gltfReadsUVsAndBaseColorMaterial() throws {
        var buffer = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {           // 3 positions (VEC3) @0
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        for f: Float in [0, 0, 1, 0, 0, 1] {                    // 3 UVs (VEC2) @36
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        for i: UInt16 in [0, 1, 2] {                            // 3 indices (SCALAR) @60
            withUnsafeBytes(of: i) { buffer.append(contentsOf: $0) }
        }
        let b64 = buffer.base64EncodedString()
        let png = Self.solidPNG(width: 4, height: 4, rgb: (0, 0, 1)).base64EncodedString()
        // baseColorFactor is linear; 0.5 linear re-encodes to sRGB ≈ 0.7353.
        let json = """
        { "asset": {"version": "2.0"},
          "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"mesh": 0}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "indices": 2, "mode": 4, "material": 0}]}],
          "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [0.5, 0.25, 0.75, 1], "baseColorTexture": {"index": 0}}}],
          "textures": [{"source": 0}],
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
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mesh = try #require(Mesh(contentsOf: url))
        // UVs read and aligned with positions.
        #expect(mesh.uvs.count == mesh.positions.count)
        #expect(mesh.uvs.contains { abs($0.x - 1) < 1e-5 })
        // Base color: 0.5 linear → ~0.735 sRGB on the red channel.
        let mat = try #require(mesh.material)
        #expect(abs(mat.baseColor.red - 0.7353) < 0.01)
        // The texture decoded from the embedded PNG, at its 4×4 size.
        let tex = try #require(mat.texture)
        #expect(tex.width == 4 && tex.height == 4)
    }

    /// `COLOR_0` as normalized `UNSIGNED_BYTE` VEC4, the quantized form most exporters
    /// write. Pins that the attribute is read at all, that the byte form normalizes,
    /// and that the stored values re-encode linear to sRGB the way every other glTF
    /// color factor does (0.5 linear is *not* 0.5 sRGB, and reading it as sRGB would
    /// wash a painted mesh out by a visible amount).
    @Test func gltfReadsQuantizedVertexColors() throws {
        var buffer = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {           // 3 positions (VEC3) @0
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        // 3 colors (VEC4 of normalized bytes) @36: mid-gray, pure red, opaque white.
        buffer.append(contentsOf: [128, 128, 128, 255] as [UInt8])
        buffer.append(contentsOf: [255, 0, 0, 255] as [UInt8])
        buffer.append(contentsOf: [255, 255, 255, 255] as [UInt8])
        for i: UInt16 in [0, 1, 2] {                            // 3 indices (SCALAR) @48
            withUnsafeBytes(of: i) { buffer.append(contentsOf: $0) }
        }
        let b64 = buffer.base64EncodedString()
        let json = """
        { "asset": {"version": "2.0"},
          "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"mesh": 0}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "COLOR_0": 1}, "indices": 2, "mode": 4}]}],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5121, "normalized": true, "count": 3, "type": "VEC4"},
            {"bufferView": 2, "componentType": 5123, "count": 3, "type": "SCALAR"}],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 12},
            {"buffer": 0, "byteOffset": 48, "byteLength": 6}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(b64)", "byteLength": \(buffer.count)}]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mesh = try #require(Mesh(contentsOf: url))
        #expect(mesh.colors.count == mesh.positions.count)
        // 128/255 = 0.502 linear, which re-encodes to about 0.7366 sRGB.
        #expect(abs(mesh.colors[0].red - 0.7366) < 0.01)
        #expect(abs(mesh.colors[0].green - 0.7366) < 0.01)
        // The endpoints are fixed points of the transfer curve, so they stay exact.
        #expect(abs(mesh.colors[1].red - 1) < 1e-6)
        #expect(abs(mesh.colors[1].green) < 1e-6)
        #expect(abs(mesh.colors[2].blue - 1) < 1e-6)
        #expect(mesh.colors.allSatisfy { abs($0.alpha - 1) < 1e-6 })
    }

    /// A mesh whose file carries no `COLOR_0` must come back with *no* colors rather
    /// than a white array: an empty `colors` is the constant-color render path, and
    /// filling it with white would push every loaded model onto the per-vertex one.
    @Test func gltfWithoutVertexColorsCarriesNone() throws {
        var buffer = Data()
        for f: Float in [0, 0, 0, 1, 0, 0, 0, 1, 0] {
            withUnsafeBytes(of: f) { buffer.append(contentsOf: $0) }
        }
        for i: UInt16 in [0, 1, 2] {
            withUnsafeBytes(of: i) { buffer.append(contentsOf: $0) }
        }
        let b64 = buffer.base64EncodedString()
        let json = """
        { "asset": {"version": "2.0"},
          "scene": 0, "scenes": [{"nodes": [0]}],
          "nodes": [{"mesh": 0}],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "mode": 4}]}],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"}],
          "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": 36},
            {"buffer": 0, "byteOffset": 36, "byteLength": 6}],
          "buffers": [{"uri": "data:application/octet-stream;base64,\(b64)", "byteLength": \(buffer.count)}]
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).gltf")
        try json.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mesh = try #require(Mesh(contentsOf: url))
        #expect(mesh.colors.isEmpty)
    }

    /// An ASCII PLY with per-vertex `red`/`green`/`blue`, the form a scan or a
    /// vertex-painted export writes. Unlike glTF these are display values, so they
    /// arrive unconverted.
    @Test func plyReadsVertexColors() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 3
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        element face 1
        property list uchar int vertex_indices
        end_header
        0 0 0 255 0 0
        1 0 0 0 255 0
        0 1 0 0 0 255
        3 0 1 2

        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).ply")
        try ply.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mesh = try #require(Mesh(contentsOf: url))
        #expect(mesh.colors.count == mesh.positions.count)
        // One saturated vertex per channel, in the file's order.
        let reds = mesh.colors.map(\.red), greens = mesh.colors.map(\.green), blues = mesh.colors.map(\.blue)
        #expect(reds.contains { $0 > 0.99 } && greens.contains { $0 > 0.99 } && blues.contains { $0 > 0.99 })
        // Saturated in one channel means dark in the others: nothing re-encoded them.
        #expect(mesh.colors.allSatisfy { $0.red + $0.green + $0.blue < 1.05 })
    }

    /// An OBJ quad with UVs and an `mtllib`/`usemtl` material whose `.mtl` carries a
    /// diffuse color and a `map_Kd` texture: exercises `vt` reading and the `.mtl`
    /// parse (color + sibling texture file). Writes the trio to a temp folder.
    @Test func objReadsUVsAndMTLMaterial() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-obj-\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Self.solidPNG(width: 4, height: 4, rgb: (0, 1, 0)).write(to: dir.appendingPathComponent("tex.png"))
        try "newmtl Painted\nKd 0.8 0.2 0.1\nmap_Kd tex.png\n"
            .write(to: dir.appendingPathComponent("quad.mtl"), atomically: true, encoding: .utf8)
        let obj = """
        mtllib quad.mtl
        v 0 0 0
        v 1 0 0
        v 1 1 0
        v 0 1 0
        vt 0 0
        vt 1 0
        vt 1 1
        vt 0 1
        vn 0 0 1
        usemtl Painted
        f 1/1/1 2/2/1 3/3/1 4/4/1
        """
        let objURL = dir.appendingPathComponent("quad.obj")
        try obj.write(to: objURL, atomically: true, encoding: .utf8)

        let mesh = try #require(Mesh(contentsOf: objURL))
        #expect(mesh.uvs.count == mesh.positions.count)
        #expect(mesh.uvs.contains { abs($0.x - 1) < 1e-5 })
        let mat = try #require(mesh.material)
        #expect(abs(mat.baseColor.red - 0.8) < 0.01)   // Kd taken as the sRGB color directly
        #expect(mat.texture?.width == 4)
    }

    /// A small solid-color PNG as `Data`, for embedding a texture in a fixture.
    private static func solidPNG(width: Int, height: Int, rgb: (Double, Double, Double)) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    // MARK: USD (merged)

    /// The merged USD read bakes node transforms into the vertices, so a
    /// multi-part file's placement survives the merge (the glTF treatment).
    @Test func usdMergedMeshBakesNodeTransforms() throws {
        let usda = """
        #usda 1.0
        (
            defaultPrim = "Root"
        )

        def Xform "Root"
        {
            def Xform "mover"
            {
                double3 xformOp:translate = (3, 0, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]

                def Mesh "quad"
                {
                    uniform token subdivisionScheme = "none"
                    point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                    int[] faceVertexCounts = [4]
                    int[] faceVertexIndices = [0, 1, 2, 3]
                }
            }

            def Mesh "home"
            {
                uniform token subdivisionScheme = "none"
                point3f[] points = [(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)]
                int[] faceVertexCounts = [4]
                int[] faceVertexIndices = [0, 1, 2, 3]
            }
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let mesh = try #require(Mesh(contentsOf: url))
        #expect(mesh.triangleCount == 4)
        let b = mesh.bounds
        #expect(abs(b.min.x) < 1e-5 && abs(b.max.x - 4) < 1e-5)
    }

    // MARK: Model I/O (USD round-trip)

    /// Round-trip a box through Model I/O: build one, export to USD, and read it
    /// back through the native USD reader. Soft-skips if this toolchain can't
    /// export USD.
    @Test func modelIORoundTripsABox() throws {
        #if canImport(ModelIO)
        guard MDLAsset.canExportFileExtension("usdc") else { return }
        let allocator = MDLMeshBufferDataAllocator()
        let box = MDLMesh(boxWithExtent: SIMD3<Float>(2, 2, 2),
                          segments: SIMD3<UInt32>(1, 1, 1),
                          inwardNormals: false, geometryType: .triangles, allocator: allocator)
        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(box)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-\(ProcessInfo.processInfo.globallyUniqueString).usdc")
        defer { try? FileManager.default.removeItem(at: url) }
        do { try asset.export(to: url) } catch { return }   // soft-skip on export failure

        let mesh = Mesh(contentsOf: url)
        #expect(mesh != nil)
        guard let mesh else { return }
        #expect(mesh.triangleCount == 12)                   // a 1-segment box
        let b = mesh.bounds
        #expect(abs(b.max.x - 1) < 1e-4 && abs(b.min.x + 1) < 1e-4)
        for n in mesh.normals { #expect(abs(n.length - 1) < 1e-5) }
        #endif
    }

    // MARK: Bounds & fit

    /// `bounds`/`center`/`size` over a known mesh, and `normalized(scale:)` recenters
    /// and fits to its longest dimension.
    @Test func boundsAndNormalize() {
        // A box offset from the origin and non-cubic, built by hand.
        let raw = Mesh(positions: [Vector3(2, 2, 2), Vector3(6, 4, 3)],
                       normals: [.unitY, .unitY], indices: [0, 1, 0])
        let b = raw.bounds
        #expect(b.min == Vector3(2, 2, 2) && b.max == Vector3(6, 4, 3))
        #expect(raw.center == Vector3(4, 3, 2.5))
        #expect(raw.size == Vector3(4, 2, 1))

        let fitted = raw.normalized(scale: 2)
        // Recentered on the origin…
        #expect(fitted.center.length < 1e-9)
        // …and the longest dimension (x, span 4) now spans `scale` = 2.
        #expect(abs(fitted.size.x - 2) < 1e-9)
        #expect(abs(fitted.size.y - 1) < 1e-9)
    }

    /// The built-in generators are origin-centered, so `center` is ~zero and
    /// `normalized()` barely moves them.
    @Test func normalizeLeavesCenteredMeshCentered() {
        let sphere = Mesh.sphere(radius: 3, segments: 16, rings: 8)
        #expect(sphere.center.length < 1e-6)
        let unit = sphere.normalized(scale: 1)
        #expect(abs(unit.size.x - 1) < 1e-6)   // diameter 6 → 1
    }
}
