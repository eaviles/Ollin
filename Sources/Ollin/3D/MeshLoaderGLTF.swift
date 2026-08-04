import Foundation
import simd

// glTF / GLB loading. glTF 2.0 is the modern interchange standard that most 3D tools
// and web frameworks export, and it's the one common format Apple's Model I/O can't
// open, so Ollin reads it itself. Conveniently glTF's coordinate space is the same as
// Ollin's world space: right-handed, y-up, meters, so positions and normals carry over
// with no axis flip; only the node hierarchy's transforms need baking in. This reads
// the common mesh subset (POSITION + NORMAL + TEXCOORD_0 + triangle indices, float
// positions/normals/UVs, embedded or external buffers) plus the base-color material
// (factor + texture), the node TRS keyframe animations the scene loader plays, and
// the deforming tier the scene loader poses: skins (JOINTS_0/WEIGHTS_0 + inverse
// bind matrices) and morph targets (sparse-accessor displacements included). The
// other PBR channels (metallic/roughness, normal, emissive) are not read, and the
// merged `Mesh.loadGLTF` below keeps its bind-pose bake (deformation is the
// structure-preserving Scene path's job).
//
// The file-and-buffer plumbing lives in `GLTFDocument`, shared by two consumers with
// different contracts: `Mesh.loadGLTF` below bakes every node's world transform in and
// merges to one `Mesh`, while the structure-preserving `Scene` loader (Scene.swift)
// keeps the node graph, per-node meshes in local space, and the authored cameras and
// lights.

extension Mesh {

    /// Read positions, normals, triangle indices, texture coordinates, and the
    /// base-color material from a glTF 2.0 file, `.gltf` (JSON, with the binary in an
    /// embedded data-URI or a sidecar `.bin`) or `.glb` (the self-contained binary
    /// container). Every mesh in the scene is baked through its node's world transform
    /// and merged into one `Mesh`; a primitive without normals gets smooth ones. A
    /// multi-material file wears its first base-color material (preferring a textured
    /// one); UVs survive only if every merged primitive has them. Returns `nil` if the
    /// file can't be read or holds no triangles.
    static func loadGLTF(_ url: URL) -> Mesh? {
        guard let doc = GLTFDocument(contentsOf: url) else { return nil }
        let gltf = doc.gltf

        // Walk the scene's node tree, composing each node's world transform, and
        // collect every (mesh, world-matrix) instance.
        let nodes = gltf.nodes ?? []
        var instances: [(mesh: Int, world: simd_float4x4)] = []
        func visit(_ ni: Int, parent: simd_float4x4) {
            guard ni >= 0, ni < nodes.count else { return }
            let world = parent * nodes[ni].localMatrix
            if let m = nodes[ni].mesh { instances.append((m, world)) }
            for c in nodes[ni].children ?? [] { visit(c, parent: world) }
        }
        for r in doc.rootNodes { visit(r, parent: matrix_identity_float4x4) }

        let meshes = gltf.meshes ?? []
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []
        var uvs: [Vector2] = []
        // UVs are kept only if *every* merged primitive supplied them (a partial set
        // would mismap), so a mixed model drops to flat (untextured) instead.
        var allHaveUV = true
        // The material the merged mesh wears: the first primitive's material, but
        // preferring the first one that carries a base-color texture (the visible part).
        var chosenMaterial: Int?
        var chosenHasTexture = false

        for inst in instances {
            guard inst.mesh >= 0, inst.mesh < meshes.count else { continue }
            let normalMat = inst.world.normalMatrix
            for prim in meshes[inst.mesh].primitives {
                guard (prim.mode ?? 4) == 4, let posIndex = prim.attributes["POSITION"],
                      let localPos = doc.readVec3(posIndex) else { continue }
                let base = UInt32(positions.count)

                for p in localPos {
                    let w = inst.world * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
                    positions.append(Vector3(Double(w.x), Double(w.y), Double(w.z)))
                }

                if let normIndex = prim.attributes["NORMAL"], let localNorm = doc.readVec3(normIndex),
                   localNorm.count == localPos.count {
                    for n in localNorm {
                        let wn = normalMat * SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z))
                        let v = Vector3(Double(wn.x), Double(wn.y), Double(wn.z))
                        normals.append(v.lengthSquared > 1e-12 ? v.normalized : .unitY)
                    }
                } else {
                    normals.append(contentsOf: repeatElement(Vector3.zero, count: localPos.count))   // fill below
                }

                // Texture coordinates (kept aligned with positions; a missing or
                // unreadable set forfeits UVs for the whole merged mesh).
                if let uvIndex = prim.attributes["TEXCOORD_0"], let localUV = doc.readVec2(uvIndex),
                   localUV.count == localPos.count {
                    uvs.append(contentsOf: localUV)
                } else {
                    allHaveUV = false
                    uvs.append(contentsOf: repeatElement(Vector2.zero, count: localPos.count))
                }

                // Pick the material to carry: the first one seen, upgraded to the first
                // that has a base-color texture.
                if let mi = prim.material {
                    if chosenMaterial == nil { chosenMaterial = mi }
                    if !chosenHasTexture, doc.materialHasTexture(mi) { chosenMaterial = mi; chosenHasTexture = true }
                }

                let primIndices = prim.indices.flatMap(doc.readIndices) ?? Array(0..<UInt32(localPos.count))
                for idx in primIndices { indices.append(base + idx) }

                // If this primitive carried no normals, smooth them across its faces.
                if prim.attributes["NORMAL"] == nil {
                    smoothNormals(into: &normals, positions: positions, indices: indices,
                                  vertexRange: Int(base)..<positions.count)
                }
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else { return nil }
        return Mesh(positions: positions, normals: normals, indices: indices,
                    uvs: allHaveUV ? uvs : [], material: chosenMaterial.flatMap(doc.resolveMaterial))
    }

    /// Fill in smooth, area-weighted normals for the vertices in `vertexRange`, using
    /// the triangles in `indices` that reference them, for a primitive that shipped
    /// no `NORMAL` attribute.
    static func smoothNormals(into normals: inout [Vector3], positions: [Vector3],
                              indices: [UInt32], vertexRange: Range<Int>) {
        var accum = [Vector3](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            if vertexRange.contains(a) {
                let fn = (positions[b] - positions[a]).cross(positions[c] - positions[a])
                accum[a] = accum[a] + fn; accum[b] = accum[b] + fn; accum[c] = accum[c] + fn
            }
            i += 3
        }
        for v in vertexRange {
            normals[v] = accum[v].lengthSquared > 1e-12 ? accum[v].normalized : .unitY
        }
    }
}

// MARK: - The parsed document (shared by the mesh and scene loaders)

/// A parsed glTF/GLB file with its buffers resolved to raw bytes: the accessor
/// readers, image bytes, and material resolution both loaders share. Value-typed and
/// internal; the public surface is `Mesh(contentsOf:)` and `Scene(contentsOf:)`.
struct GLTFDocument {
    let gltf: GLTF
    let buffers: [Data]
    let baseDir: URL

    /// Parse the file at `url` (`.gltf` JSON or a `.glb` container) and resolve every
    /// buffer: an embedded base64 data-URI, an external file beside the `.gltf`, or
    /// the `.glb`'s own BIN chunk (buffer 0). Returns `nil` on any unreadable piece.
    init?(contentsOf url: URL) {
        let jsonData: Data
        var glbBinary: Data?
        if url.pathExtension.lowercased() == "glb" {
            guard let (json, bin) = GLTFDocument.parseGLB(url) else { return nil }
            jsonData = json; glbBinary = bin
        } else {
            guard let d = try? Data(contentsOf: url) else { return nil }
            jsonData = d
        }
        guard let gltf = try? JSONDecoder().decode(GLTF.self, from: jsonData) else { return nil }

        let baseDir = url.deletingLastPathComponent()
        var buffers: [Data] = []
        for (i, b) in (gltf.buffers ?? []).enumerated() {
            if let uri = b.uri {
                if uri.hasPrefix("data:") {
                    guard let comma = uri.firstIndex(of: ","),
                          let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else { return nil }
                    buffers.append(data)
                } else {
                    let path = uri.removingPercentEncoding ?? uri
                    guard let data = try? Data(contentsOf: baseDir.appendingPathComponent(path)) else { return nil }
                    buffers.append(data)
                }
            } else if i == 0, let bin = glbBinary {
                buffers.append(bin)
            } else {
                return nil
            }
        }
        self.gltf = gltf
        self.buffers = buffers
        self.baseDir = baseDir
    }

    /// The root node indices of the default scene (falling back to every node when
    /// the file declares no scenes).
    var rootNodes: [Int] {
        let nodes = gltf.nodes ?? []
        return gltf.scenes?.indices.contains(gltf.scene ?? 0) == true
            ? (gltf.scenes![gltf.scene ?? 0].nodes ?? [])
            : Array(0..<nodes.count)
    }

    /// Read a VEC3-of-float accessor (positions, normals, morph displacements) as
    /// `[Vector3]`, honoring the buffer view's byte offset and (interleaved) stride.
    /// An accessor with no buffer view reads as zeros, and a sparse accessor
    /// substitutes its values at its indices: together, the layout morph-target
    /// exporters lean on (most displacements are zero, so only the moved
    /// vertices are stored).
    func readVec3(_ index: Int) -> [Vector3]? {
        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []
        guard index >= 0, index < accessors.count else { return nil }
        let a = accessors[index]
        guard a.type == "VEC3", a.componentType == 5126,         // VEC3, FLOAT
              a.count > 0 else { return nil }
        var out: [Vector3]
        if let bvi = a.bufferView {
            guard bvi < views.count else { return nil }
            let bv = views[bvi]
            guard bv.buffer < buffers.count else { return nil }
            let buf = buffers[bv.buffer]
            let stride = bv.byteStride ?? 12
            let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
            guard start + (a.count - 1) * stride + 12 <= buf.count else { return nil }
            var read = [Vector3](); read.reserveCapacity(a.count)
            buf.withUnsafeBytes { raw in
                for i in 0..<a.count {
                    let o = start + i * stride
                    let x = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                    let y = raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self)
                    let z = raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self)
                    read.append(Vector3(Double(x), Double(y), Double(z)))
                }
            }
            out = read
        } else {
            out = [Vector3](repeating: .zero, count: a.count)
        }
        if let sp = a.sparse {
            guard let idx = sparseIndices(sp),
                  let values = packedVec3(view: sp.values.bufferView,
                                          offset: sp.values.byteOffset ?? 0,
                                          count: sp.count) else { return nil }
            for (k, i) in idx.enumerated() where i < out.count { out[i] = values[k] }
        }
        return out
    }

    /// A sparse accessor's substitution indices: `count` tightly-packed unsigned
    /// ints (u8/u16/u32) from its own buffer view.
    private func sparseIndices(_ sp: GLTF.Sparse) -> [Int]? {
        let views = gltf.bufferViews ?? []
        guard sp.indices.bufferView >= 0, sp.indices.bufferView < views.count else { return nil }
        let bv = views[sp.indices.bufferView]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let size: Int
        switch sp.indices.componentType {
        case 5121: size = 1; case 5123: size = 2; case 5125: size = 4; default: return nil
        }
        let start = (bv.byteOffset ?? 0) + (sp.indices.byteOffset ?? 0)
        guard sp.count > 0, start + sp.count * size <= buf.count else { return nil }
        var out = [Int](); out.reserveCapacity(sp.count)
        buf.withUnsafeBytes { raw in
            for i in 0..<sp.count {
                let o = start + i * size
                switch size {
                case 1: out.append(Int(raw.loadUnaligned(fromByteOffset: o, as: UInt8.self)))
                case 2: out.append(Int(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)))
                default: out.append(Int(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)))
                }
            }
        }
        return out
    }

    /// `count` tightly-packed float VEC3 elements straight from a buffer view (a
    /// sparse accessor's values, which carry no accessor of their own).
    private func packedVec3(view: Int, offset: Int, count: Int) -> [Vector3]? {
        let views = gltf.bufferViews ?? []
        guard view >= 0, view < views.count else { return nil }
        let bv = views[view]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let start = (bv.byteOffset ?? 0) + offset
        guard count > 0, start + count * 12 <= buf.count else { return nil }
        var out = [Vector3](); out.reserveCapacity(count)
        buf.withUnsafeBytes { raw in
            for i in 0..<count {
                let o = start + i * 12
                out.append(Vector3(Double(raw.loadUnaligned(fromByteOffset: o, as: Float.self)),
                                   Double(raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self)),
                                   Double(raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self))))
            }
        }
        return out
    }

    /// Read a SCALAR index accessor (u8/u16/u32) as `[UInt32]`.
    func readIndices(_ index: Int) -> [UInt32]? {
        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []
        guard index >= 0, index < accessors.count else { return nil }
        let a = accessors[index]
        guard a.type == "SCALAR", let bvi = a.bufferView, bvi < views.count else { return nil }
        let size: Int
        switch a.componentType { case 5121: size = 1; case 5123: size = 2; case 5125: size = 4; default: return nil }
        let bv = views[bvi]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let stride = bv.byteStride ?? size
        let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
        guard a.count > 0, start + (a.count - 1) * stride + size <= buf.count else { return nil }
        var out = [UInt32](); out.reserveCapacity(a.count)
        buf.withUnsafeBytes { raw in
            for i in 0..<a.count {
                let o = start + i * stride
                switch size {
                case 1: out.append(UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt8.self)))
                case 2: out.append(UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)))
                default: out.append(raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))
                }
            }
        }
        return out
    }

    /// Read a SCALAR-of-float accessor (animation keyframe times) as `[Double]`.
    func readFloats(_ index: Int) -> [Double]? {
        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []
        guard index >= 0, index < accessors.count else { return nil }
        let a = accessors[index]
        guard a.type == "SCALAR", a.componentType == 5126,        // SCALAR, FLOAT
              let bvi = a.bufferView, bvi < views.count else { return nil }
        let bv = views[bvi]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let stride = bv.byteStride ?? 4
        let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
        guard a.count > 0, start + (a.count - 1) * stride + 4 <= buf.count else { return nil }
        var out = [Double](); out.reserveCapacity(a.count)
        buf.withUnsafeBytes { raw in
            for i in 0..<a.count {
                out.append(Double(raw.loadUnaligned(fromByteOffset: start + i * stride, as: Float.self)))
            }
        }
        return out
    }

    /// Read a VEC4 accessor (rotation quaternions) as `[SIMD4<Float>]`: float, or
    /// any of the four normalized-integer encodings the spec allows for rotation
    /// output, decoded by the spec's int-to-float equations.
    func readVec4(_ index: Int) -> [SIMD4<Float>]? {
        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []
        guard index >= 0, index < accessors.count else { return nil }
        let a = accessors[index]
        guard a.type == "VEC4", let bvi = a.bufferView, bvi < views.count else { return nil }
        let size: Int
        switch a.componentType {
        case 5126: size = 4                                       // FLOAT
        case 5120, 5121: size = 1                                 // BYTE, UNSIGNED_BYTE
        case 5122, 5123: size = 2                                 // SHORT, UNSIGNED_SHORT
        default: return nil
        }
        let bv = views[bvi]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let stride = bv.byteStride ?? size * 4
        let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
        guard a.count > 0, start + (a.count - 1) * stride + size * 4 <= buf.count else { return nil }
        var out = [SIMD4<Float>](); out.reserveCapacity(a.count)
        buf.withUnsafeBytes { raw in
            for i in 0..<a.count {
                let o = start + i * stride
                func component(_ c: Int) -> Float {
                    switch a.componentType {
                    case 5120: return max(Float(raw.loadUnaligned(fromByteOffset: o + c, as: Int8.self)) / 127, -1)
                    case 5121: return Float(raw.loadUnaligned(fromByteOffset: o + c, as: UInt8.self)) / 255
                    case 5122: return max(Float(raw.loadUnaligned(fromByteOffset: o + c * 2, as: Int16.self)) / 32767, -1)
                    case 5123: return Float(raw.loadUnaligned(fromByteOffset: o + c * 2, as: UInt16.self)) / 65535
                    default: return raw.loadUnaligned(fromByteOffset: o + c * 4, as: Float.self)
                    }
                }
                out.append(SIMD4<Float>(component(0), component(1), component(2), component(3)))
            }
        }
        return out
    }

    /// Read a VEC2-of-float accessor (texture coordinates) as `[Vector2]`. Only
    /// float UVs are read (the common export); a normalized-integer TEXCOORD comes
    /// back nil, so that primitive is treated as having no UVs.
    func readVec2(_ index: Int) -> [Vector2]? {
        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []
        guard index >= 0, index < accessors.count else { return nil }
        let a = accessors[index]
        guard a.type == "VEC2", a.componentType == 5126,         // VEC2, FLOAT
              let bvi = a.bufferView, bvi < views.count else { return nil }
        let bv = views[bvi]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let stride = bv.byteStride ?? 8
        let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
        guard a.count > 0, start + (a.count - 1) * stride + 8 <= buf.count else { return nil }
        var out = [Vector2](); out.reserveCapacity(a.count)
        buf.withUnsafeBytes { raw in
            for i in 0..<a.count {
                let o = start + i * stride
                let u = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                let v = raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self)
                out.append(Vector2(Double(u), Double(v)))
            }
        }
        return out
    }

    /// Read a MAT4-of-float accessor (a skin's inverse bind matrices) as
    /// column-major `simd_float4x4`s, honoring offset and stride.
    func readMat4(_ index: Int) -> [simd_float4x4]? {
        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []
        guard index >= 0, index < accessors.count else { return nil }
        let a = accessors[index]
        guard a.type == "MAT4", a.componentType == 5126,          // MAT4, FLOAT
              let bvi = a.bufferView, bvi < views.count else { return nil }
        let bv = views[bvi]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let stride = bv.byteStride ?? 64
        let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
        guard a.count > 0, start + (a.count - 1) * stride + 64 <= buf.count else { return nil }
        var out = [simd_float4x4](); out.reserveCapacity(a.count)
        buf.withUnsafeBytes { raw in
            for i in 0..<a.count {
                let o = start + i * stride
                func column(_ c: Int) -> SIMD4<Float> {
                    SIMD4<Float>(raw.loadUnaligned(fromByteOffset: o + c * 16, as: Float.self),
                                 raw.loadUnaligned(fromByteOffset: o + c * 16 + 4, as: Float.self),
                                 raw.loadUnaligned(fromByteOffset: o + c * 16 + 8, as: Float.self),
                                 raw.loadUnaligned(fromByteOffset: o + c * 16 + 12, as: Float.self))
                }
                out.append(simd_float4x4(columns: (column(0), column(1), column(2), column(3))))
            }
        }
        return out
    }

    /// Read a VEC4 joint-index accessor (JOINTS_0: unsigned byte or unsigned
    /// short) as `[SIMD4<UInt16>]`, each component an index into the skin's
    /// `joints` array.
    func readJointIndices(_ index: Int) -> [SIMD4<UInt16>]? {
        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []
        guard index >= 0, index < accessors.count else { return nil }
        let a = accessors[index]
        let size: Int
        switch a.componentType {
        case 5121: size = 1                                       // UNSIGNED_BYTE
        case 5123: size = 2                                       // UNSIGNED_SHORT
        default: return nil
        }
        guard a.type == "VEC4", let bvi = a.bufferView, bvi < views.count else { return nil }
        let bv = views[bvi]
        guard bv.buffer < buffers.count else { return nil }
        let buf = buffers[bv.buffer]
        let stride = bv.byteStride ?? size * 4
        let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
        guard a.count > 0, start + (a.count - 1) * stride + size * 4 <= buf.count else { return nil }
        var out = [SIMD4<UInt16>](); out.reserveCapacity(a.count)
        buf.withUnsafeBytes { raw in
            for i in 0..<a.count {
                let o = start + i * stride
                func component(_ c: Int) -> UInt16 {
                    size == 1 ? UInt16(raw.loadUnaligned(fromByteOffset: o + c, as: UInt8.self))
                              : raw.loadUnaligned(fromByteOffset: o + c * 2, as: UInt16.self)
                }
                out.append(SIMD4<UInt16>(component(0), component(1), component(2), component(3)))
            }
        }
        return out
    }

    /// The raw bytes of an image: an embedded base64 data-URI, an external file
    /// beside the .gltf, or a slice of a buffer view (a .glb-embedded texture).
    func imageData(_ imageIndex: Int) -> Data? {
        let views = gltf.bufferViews ?? []
        let images = gltf.images ?? []
        guard imageIndex >= 0, imageIndex < images.count else { return nil }
        let img = images[imageIndex]
        if let uri = img.uri {
            if uri.hasPrefix("data:") {
                guard let comma = uri.firstIndex(of: ","),
                      let data = Data(base64Encoded: String(uri[uri.index(after: comma)...])) else { return nil }
                return data
            }
            let path = uri.removingPercentEncoding ?? uri
            return try? Data(contentsOf: baseDir.appendingPathComponent(path))
        }
        if let bvi = img.bufferView, bvi < views.count {
            let bv = views[bvi]
            guard bv.buffer < buffers.count else { return nil }
            let buf = buffers[bv.buffer]
            let start = bv.byteOffset ?? 0
            guard start + bv.byteLength <= buf.count else { return nil }
            return buf.subdata(in: start..<(start + bv.byteLength))
        }
        return nil
    }

    /// Whether a material declares a base-color texture (used to prefer a textured
    /// material over a plain one when several primitives merge to one mesh).
    func materialHasTexture(_ mi: Int) -> Bool {
        let materials = gltf.materials ?? []
        guard mi >= 0, mi < materials.count else { return false }
        return materials[mi].pbrMetallicRoughness?.baseColorTexture != nil
    }

    /// Resolve a glTF material to a `MeshMaterial`: the base-color factor (linear,
    /// so re-encode to the sRGB `Color` the surface bakes) and the base-color
    /// texture image. Other PBR channels (metallic/roughness, normal, emissive) are
    /// the later PBR tier. Returns nil when the material carries neither.
    func resolveMaterial(_ matIndex: Int) -> MeshMaterial? {
        let materials = gltf.materials ?? []
        guard matIndex >= 0, matIndex < materials.count else { return nil }
        let pbr = materials[matIndex].pbrMetallicRoughness
        var baseColor = Color.white
        if let f = pbr?.baseColorFactor, f.count == 4 {
            func enc(_ x: Double) -> Double { Color.linearToSrgb(min(max(x, 0), 1)) }
            baseColor = Color(red: enc(f[0]), green: enc(f[1]), blue: enc(f[2]),
                              alpha: min(max(f[3], 0), 1))
        }
        var texture: Image?
        if let ti = pbr?.baseColorTexture?.index {
            let textures = gltf.textures ?? []
            if ti >= 0, ti < textures.count, let src = textures[ti].source,
               let data = imageData(src) {
                texture = Image(data: data)
            }
        }
        if texture == nil, pbr?.baseColorFactor == nil { return nil }
        return MeshMaterial(baseColor: baseColor, texture: texture)
    }

    /// One glTF mesh (all its triangle primitives merged) as a `Mesh` in the node's
    /// *local* space, with no world baking: that's the caller's transform to apply.
    /// The merge rules match `Mesh.loadGLTF`: UVs survive only when every primitive
    /// has them, the mesh wears its first material preferring a textured one, and a
    /// primitive without normals gets smooth ones. Returns `nil` when the mesh index
    /// is invalid or no triangles result.
    func localMesh(at meshIndex: Int) -> Mesh? { localMeshData(at: meshIndex)?.mesh }

    /// A merged local mesh together with its deformation data, aligned with the
    /// merged vertex order: per-vertex skin joints and weights (kept only when
    /// *every* primitive carries them, the UV rule), the morph-target
    /// displacements (kept only when every primitive declares the same target
    /// count, which the format requires), and the mesh's authored default morph
    /// weights.
    struct LocalMeshData {
        var mesh: Mesh
        var joints: [SIMD4<UInt16>] = []
        var weights: [SIMD4<Float>] = []
        var targets: [SceneMorphTarget] = []
        var defaultWeights: [Double] = []
        /// Per-material slices of the merged mesh, filled only when the
        /// primitives wear two or more distinct materials (`drawScene` then
        /// draws each with its own); empty for a single-material mesh.
        var parts: [SceneMeshPart] = []
    }

    func localMeshData(at meshIndex: Int) -> LocalMeshData? {
        let meshes = gltf.meshes ?? []
        guard meshIndex >= 0, meshIndex < meshes.count else { return nil }
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []
        var uvs: [Vector2] = []
        var allHaveUV = true
        var chosenMaterial: Int?
        var chosenHasTexture = false
        // Each primitive's slice of the merged index buffer with its material
        // index (nil for a material-less primitive), the raw material for the
        // per-material parts below.
        var primitiveSpans: [(material: Int?, span: Range<Int>)] = []

        var joints: [SIMD4<UInt16>] = []
        var weights: [SIMD4<Float>] = []
        var allHaveSkin = true
        // Every primitive of a morphing mesh must declare the same target count
        // (the format's rule); a mismatch drops the morph data whole rather than
        // misaligning it.
        let targetCount = meshes[meshIndex].primitives.first?.targets?.count ?? 0
        var targetsAgree = targetCount > 0
        var targetPositions = [[Vector3]](repeating: [], count: targetCount)
        var targetNormals = [[Vector3]](repeating: [], count: targetCount)
        var anyNormalDeltas = [Bool](repeating: false, count: targetCount)

        for prim in meshes[meshIndex].primitives {
            guard (prim.mode ?? 4) == 4, let posIndex = prim.attributes["POSITION"],
                  let localPos = readVec3(posIndex) else { continue }
            let base = UInt32(positions.count)
            positions.append(contentsOf: localPos)

            if let normIndex = prim.attributes["NORMAL"], let localNorm = readVec3(normIndex),
               localNorm.count == localPos.count {
                for n in localNorm {
                    normals.append(n.lengthSquared > 1e-12 ? n.normalized : .unitY)
                }
            } else {
                normals.append(contentsOf: repeatElement(Vector3.zero, count: localPos.count))   // fill below
            }

            if let uvIndex = prim.attributes["TEXCOORD_0"], let localUV = readVec2(uvIndex),
               localUV.count == localPos.count {
                uvs.append(contentsOf: localUV)
            } else {
                allHaveUV = false
                uvs.append(contentsOf: repeatElement(Vector2.zero, count: localPos.count))
            }

            // Skin attributes, all-or-nothing like UVs: a primitive missing either
            // half pads with zeros and forfeits skinning for the merged mesh.
            if let ji = prim.attributes["JOINTS_0"], let localJoints = readJointIndices(ji),
               localJoints.count == localPos.count,
               let wi = prim.attributes["WEIGHTS_0"], let localWeights = readVec4(wi),
               localWeights.count == localPos.count {
                joints.append(contentsOf: localJoints)
                weights.append(contentsOf: localWeights)
            } else {
                allHaveSkin = false
                joints.append(contentsOf: repeatElement(SIMD4<UInt16>(), count: localPos.count))
                weights.append(contentsOf: repeatElement(SIMD4<Float>(), count: localPos.count))
            }

            // Morph-target displacements, aligned per target across primitives; a
            // target without an attribute contributes zero displacement.
            if targetsAgree {
                if (prim.targets?.count ?? 0) != targetCount {
                    targetsAgree = false
                } else if let targets = prim.targets {
                    for (t, target) in targets.enumerated() {
                        if let pi = target["POSITION"], let deltas = readVec3(pi),
                           deltas.count == localPos.count {
                            targetPositions[t].append(contentsOf: deltas)
                        } else {
                            targetPositions[t].append(contentsOf: repeatElement(.zero, count: localPos.count))
                        }
                        if let ni = target["NORMAL"], let deltas = readVec3(ni),
                           deltas.count == localPos.count {
                            targetNormals[t].append(contentsOf: deltas)
                            anyNormalDeltas[t] = true
                        } else {
                            targetNormals[t].append(contentsOf: repeatElement(.zero, count: localPos.count))
                        }
                    }
                }
            }

            if let mi = prim.material {
                if chosenMaterial == nil { chosenMaterial = mi }
                if !chosenHasTexture, materialHasTexture(mi) { chosenMaterial = mi; chosenHasTexture = true }
            }

            let primIndices = prim.indices.flatMap(readIndices) ?? Array(0..<UInt32(localPos.count))
            let spanStart = indices.count
            for idx in primIndices { indices.append(base + idx) }
            primitiveSpans.append((material: prim.material, span: spanStart..<indices.count))

            if prim.attributes["NORMAL"] == nil {
                Mesh.smoothNormals(into: &normals, positions: positions, indices: indices,
                                   vertexRange: Int(base)..<positions.count)
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else { return nil }

        // Group the primitive spans by material (nil is its own, material-less
        // look), in first-appearance order. Two or more distinct materials make
        // the mesh multi-material: each group becomes a `SceneMeshPart` so
        // `drawScene` draws it with its own material, while the merged mesh
        // keeps wearing one material (the first, preferring a textured one) for
        // standalone draws. Each material resolves once, shared with the merged
        // mesh's own resolution, so a texture never decodes twice here.
        var resolvedByIndex: [Int: MeshMaterial?] = [:]
        func resolved(_ key: Int?) -> MeshMaterial? {
            guard let key else { return nil }
            if let hit = resolvedByIndex[key] { return hit }
            let material = resolveMaterial(key)
            resolvedByIndex[key] = material
            return material
        }
        var keyOrder: [Int?] = []
        var spansByKey: [Int?: [Range<Int>]] = [:]
        for entry in primitiveSpans where !entry.span.isEmpty {
            if spansByKey[entry.material] == nil { keyOrder.append(entry.material) }
            spansByKey[entry.material, default: []].append(entry.span)
        }
        var parts: [SceneMeshPart] = []
        if keyOrder.count >= 2 {
            parts = keyOrder.map { key in
                var slice: [UInt32] = []
                for span in spansByKey[key] ?? [] { slice.append(contentsOf: indices[span]) }
                return SceneMeshPart(indices: slice, material: resolved(key))
            }
        }

        let mesh = Mesh(positions: positions, normals: normals, indices: indices,
                        uvs: allHaveUV ? uvs : [], material: resolved(chosenMaterial))
        var data = LocalMeshData(mesh: mesh)
        data.parts = parts
        if allHaveSkin, !joints.isEmpty {
            data.joints = joints
            data.weights = weights
        }
        if targetsAgree {
            data.targets = (0..<targetCount).map {
                SceneMorphTarget(positionDeltas: targetPositions[$0],
                                 normalDeltas: anyNormalDeltas[$0] ? targetNormals[$0] : [])
            }
            data.defaultWeights = meshes[meshIndex].weights
                ?? [Double](repeating: 0, count: targetCount)
        }
        return data
    }

    /// Split a `.glb` container into its JSON chunk and (optional) BIN chunk.
    private static func parseGLB(_ url: URL) -> (json: Data, bin: Data?)? {
        guard let data = try? Data(contentsOf: url), data.count >= 12 else { return nil }
        return data.withUnsafeBytes { raw -> (Data, Data?)? in
            guard raw.loadUnaligned(fromByteOffset: 0, as: UInt32.self) == 0x4654_6C67 else { return nil }  // "glTF"
            var offset = 12
            var json: Data?, bin: Data?
            while offset + 8 <= data.count {
                let len = Int(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                let type = raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)
                let chunkStart = offset + 8
                guard chunkStart + len <= data.count else { break }
                let chunk = data.subdata(in: chunkStart..<(chunkStart + len))
                if type == 0x4E4F_534A { json = chunk }        // "JSON"
                else if type == 0x004E_4942 { bin = chunk }     // "BIN\0"
                offset = chunkStart + len
            }
            guard let j = json else { return nil }
            return (j, bin)
        }
    }
}

// MARK: - glTF JSON (the subset Ollin reads)

struct GLTF: Decodable {
    struct SceneDef: Decodable { var nodes: [Int]?; var name: String? }
    struct Node: Decodable {
        var name: String?
        var children: [Int]?
        var mesh: Int?
        var camera: Int?
        var skin: Int?
        var weights: [Double]?
        var matrix: [Double]?
        var translation: [Double]?
        var rotation: [Double]?
        var scale: [Double]?
        var extensions: NodeExtensions?

        /// The node's local transform: an explicit 4×4 (column-major, as glTF stores
        /// it) or composed from translation · rotation · scale.
        var localMatrix: simd_float4x4 {
            if let m = matrix, m.count == 16 {
                return simd_float4x4(columns: (
                    SIMD4<Float>(Float(m[0]), Float(m[1]), Float(m[2]), Float(m[3])),
                    SIMD4<Float>(Float(m[4]), Float(m[5]), Float(m[6]), Float(m[7])),
                    SIMD4<Float>(Float(m[8]), Float(m[9]), Float(m[10]), Float(m[11])),
                    SIMD4<Float>(Float(m[12]), Float(m[13]), Float(m[14]), Float(m[15]))))
            }
            var t = SIMD3<Float>(0, 0, 0)
            if let tr = translation, tr.count == 3 { t = SIMD3(Float(tr[0]), Float(tr[1]), Float(tr[2])) }
            var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            if let r = rotation, r.count == 4 { q = simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3])) }
            var s = SIMD3<Float>(1, 1, 1)
            if let sc = scale, sc.count == 3 { s = SIMD3(Float(sc[0]), Float(sc[1]), Float(sc[2])) }
            var translationM = matrix_identity_float4x4
            translationM.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
            let scaleM = simd_float4x4(diagonal: SIMD4<Float>(s.x, s.y, s.z, 1))
            return translationM * simd_float4x4(q) * scaleM
        }

        /// The node's authored translation/rotation/scale components (rotation as
        /// the raw xyzw quaternion), with the spec defaults filled in; `nil` for a
        /// node authored with an explicit `matrix`, which the spec forbids as an
        /// animation target and which can't be recomposed per component.
        var authoredTRS: (t: SIMD3<Float>, r: SIMD4<Float>, s: SIMD3<Float>)? {
            guard matrix == nil else { return nil }
            var t = SIMD3<Float>(0, 0, 0)
            if let tr = translation, tr.count == 3 { t = SIMD3(Float(tr[0]), Float(tr[1]), Float(tr[2])) }
            var r = SIMD4<Float>(0, 0, 0, 1)
            if let ro = rotation, ro.count == 4 { r = SIMD4(Float(ro[0]), Float(ro[1]), Float(ro[2]), Float(ro[3])) }
            var s = SIMD3<Float>(1, 1, 1)
            if let sc = scale, sc.count == 3 { s = SIMD3(Float(sc[0]), Float(sc[1]), Float(sc[2])) }
            return (t, r, s)
        }
    }
    struct NodeExtensions: Decodable {
        var KHR_lights_punctual: NodeLightRef?
    }
    struct NodeLightRef: Decodable { var light: Int? }
    struct Primitive: Decodable {
        var attributes: [String: Int]
        var indices: Int?
        var mode: Int?
        var material: Int?
        var targets: [[String: Int]]?
    }
    struct MeshDef: Decodable {
        var primitives: [Primitive]
        var weights: [Double]?
    }
    struct Skin: Decodable {
        var inverseBindMatrices: Int?
        var joints: [Int]
        var name: String?
    }
    struct Material: Decodable {
        var pbrMetallicRoughness: PBRMetallicRoughness?
    }
    struct PBRMetallicRoughness: Decodable {
        var baseColorFactor: [Double]?
        var baseColorTexture: TextureInfo?
    }
    struct TextureInfo: Decodable { var index: Int; var texCoord: Int? }
    struct TextureDef: Decodable { var source: Int?; var sampler: Int? }
    struct ImageDef: Decodable { var uri: String?; var bufferView: Int?; var mimeType: String? }
    struct Accessor: Decodable {
        var bufferView: Int?
        var byteOffset: Int?
        var componentType: Int
        var count: Int
        var type: String
        var sparse: Sparse?
    }
    struct Sparse: Decodable {
        struct Indices: Decodable { var bufferView: Int; var byteOffset: Int?; var componentType: Int }
        struct Values: Decodable { var bufferView: Int; var byteOffset: Int? }
        var count: Int
        var indices: Indices
        var values: Values
    }
    struct BufferView: Decodable {
        var buffer: Int
        var byteOffset: Int?
        var byteLength: Int
        var byteStride: Int?
    }
    struct BufferDef: Decodable {
        var uri: String?
        var byteLength: Int
    }
    struct CameraDef: Decodable {
        struct Perspective: Decodable {
            var yfov: Double
            var znear: Double
            var zfar: Double?
            var aspectRatio: Double?
        }
        struct Orthographic: Decodable {
            var xmag: Double
            var ymag: Double
            var znear: Double
            var zfar: Double
        }
        var type: String
        var perspective: Perspective?
        var orthographic: Orthographic?
        var name: String?
    }
    struct PunctualLightDef: Decodable {
        struct Spot: Decodable {
            var innerConeAngle: Double?
            var outerConeAngle: Double?
        }
        var type: String
        var color: [Double]?
        var intensity: Double?
        var range: Double?
        var spot: Spot?
        var name: String?
    }
    struct Extensions: Decodable {
        var KHR_lights_punctual: KHRLightsPunctual?
    }
    struct KHRLightsPunctual: Decodable { var lights: [PunctualLightDef]? }
    struct AnimationDef: Decodable {
        struct Channel: Decodable { var sampler: Int; var target: Target }
        struct Target: Decodable { var node: Int?; var path: String }
        struct SamplerDef: Decodable { var input: Int; var output: Int; var interpolation: String? }
        var name: String?
        var channels: [Channel]
        var samplers: [SamplerDef]
    }

    var scene: Int?
    var scenes: [SceneDef]?
    var nodes: [Node]?
    var meshes: [MeshDef]?
    var skins: [Skin]?
    var accessors: [Accessor]?
    var bufferViews: [BufferView]?
    var buffers: [BufferDef]?
    var materials: [Material]?
    var textures: [TextureDef]?
    var images: [ImageDef]?
    var cameras: [CameraDef]?
    var animations: [AnimationDef]?
    var extensions: Extensions?
}
