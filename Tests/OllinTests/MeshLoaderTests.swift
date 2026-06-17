import Testing
import Foundation
import simd
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

    // MARK: Model I/O (USD)

    /// Round-trip a box through Model I/O: build one, export to USD, read it back as a
    /// `Mesh`. Soft-skips if this toolchain can't export USD.
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
