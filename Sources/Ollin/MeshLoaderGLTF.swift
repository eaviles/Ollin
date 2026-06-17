import Foundation
import simd

// glTF / GLB loading. glTF 2.0 is the modern interchange standard that most 3D tools
// and web frameworks export, and it's the one common format Apple's Model I/O can't
// open, so Ollin reads it itself. Conveniently glTF's coordinate space is the same as
// Ollin's world space: right-handed, y-up, meters, so positions and normals carry over
// with no axis flip; only the node hierarchy's transforms need baking in. This reads
// the common mesh subset (POSITION + NORMAL + TEXCOORD_0 + triangle indices, float
// positions/normals/UVs, embedded or external buffers) plus the base-color material
// (factor + texture); skeletal animation, morph targets, and the other PBR channels
// (metallic/roughness, normal, emissive) are not read.

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
        let jsonData: Data
        var glbBinary: Data?
        if url.pathExtension.lowercased() == "glb" {
            guard let (json, bin) = parseGLB(url) else { return nil }
            jsonData = json; glbBinary = bin
        } else {
            guard let d = try? Data(contentsOf: url) else { return nil }
            jsonData = d
        }
        guard let gltf = try? JSONDecoder().decode(GLTF.self, from: jsonData) else { return nil }

        // Resolve every buffer to its raw bytes: an embedded base64 data-URI, an
        // external file beside the .gltf, or the .glb's own BIN chunk (buffer 0).
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

        let accessors = gltf.accessors ?? []
        let views = gltf.bufferViews ?? []

        // Read a VEC3-of-float accessor (positions, normals) as `[Vector3]`, honoring
        // the buffer view's byte offset and (interleaved) stride.
        func readVec3(_ index: Int) -> [Vector3]? {
            guard index >= 0, index < accessors.count else { return nil }
            let a = accessors[index]
            guard a.type == "VEC3", a.componentType == 5126,         // VEC3, FLOAT
                  let bvi = a.bufferView, bvi < views.count else { return nil }
            let bv = views[bvi]
            guard bv.buffer < buffers.count else { return nil }
            let buf = buffers[bv.buffer]
            let stride = bv.byteStride ?? 12
            let start = (bv.byteOffset ?? 0) + (a.byteOffset ?? 0)
            guard a.count > 0, start + (a.count - 1) * stride + 12 <= buf.count else { return nil }
            var out = [Vector3](); out.reserveCapacity(a.count)
            buf.withUnsafeBytes { raw in
                for i in 0..<a.count {
                    let o = start + i * stride
                    let x = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                    let y = raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self)
                    let z = raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self)
                    out.append(Vector3(Double(x), Double(y), Double(z)))
                }
            }
            return out
        }

        // Read a SCALAR index accessor (u8/u16/u32) as `[UInt32]`.
        func readIndices(_ index: Int) -> [UInt32]? {
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

        // Read a VEC2-of-float accessor (texture coordinates) as `[Vector2]`. Only
        // float UVs are read (the common export); a normalized-integer TEXCOORD comes
        // back nil, so that primitive is treated as having no UVs.
        func readVec2(_ index: Int) -> [Vector2]? {
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

        // The raw bytes of an image: an embedded base64 data-URI, an external file
        // beside the .gltf, or a slice of a buffer view (a .glb-embedded texture).
        func imageData(_ imageIndex: Int) -> Data? {
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

        // Whether a material declares a base-color texture (used to prefer a textured
        // material over a plain one when a multi-material file merges to one).
        func materialHasTexture(_ mi: Int) -> Bool {
            let materials = gltf.materials ?? []
            guard mi >= 0, mi < materials.count else { return false }
            return materials[mi].pbrMetallicRoughness?.baseColorTexture != nil
        }

        // Resolve a glTF material to a `MeshMaterial`: the base-color factor (linear,
        // so re-encode to the sRGB `Color` the surface bakes) and the base-color
        // texture image. Other PBR channels (metallic/roughness, normal, emissive) are
        // the later PBR tier. Returns nil when the material carries neither.
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
        let roots = gltf.scenes?.indices.contains(gltf.scene ?? 0) == true
            ? (gltf.scenes![gltf.scene ?? 0].nodes ?? [])
            : Array(0..<nodes.count)
        for r in roots { visit(r, parent: matrix_identity_float4x4) }

        let meshes = gltf.meshes ?? []
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []
        var uvs: [Vector2] = []
        // UVs are kept only if *every* merged primitive supplied them — a partial set
        // would mismap, so a mixed model drops to flat (untextured) instead.
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
                      let localPos = readVec3(posIndex) else { continue }
                let base = UInt32(positions.count)

                for p in localPos {
                    let w = inst.world * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
                    positions.append(Vector3(Double(w.x), Double(w.y), Double(w.z)))
                }

                if let normIndex = prim.attributes["NORMAL"], let localNorm = readVec3(normIndex),
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
                if let uvIndex = prim.attributes["TEXCOORD_0"], let localUV = readVec2(uvIndex),
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
                    if !chosenHasTexture, materialHasTexture(mi) { chosenMaterial = mi; chosenHasTexture = true }
                }

                let primIndices = prim.indices.flatMap(readIndices) ?? Array(0..<UInt32(localPos.count))
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
                    uvs: allHaveUV ? uvs : [], material: chosenMaterial.flatMap(resolveMaterial))
    }

    /// Fill in smooth, area-weighted normals for the vertices in `vertexRange`, using
    /// the triangles in `indices` that reference them, for a primitive that shipped
    /// no `NORMAL` attribute.
    private static func smoothNormals(into normals: inout [Vector3], positions: [Vector3],
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

private struct GLTF: Decodable {
    struct Scene: Decodable { var nodes: [Int]? }
    struct Node: Decodable {
        var children: [Int]?
        var mesh: Int?
        var matrix: [Double]?
        var translation: [Double]?
        var rotation: [Double]?
        var scale: [Double]?

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
    }
    struct Primitive: Decodable {
        var attributes: [String: Int]
        var indices: Int?
        var mode: Int?
        var material: Int?
    }
    struct MeshDef: Decodable { var primitives: [Primitive] }
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

    var scene: Int?
    var scenes: [Scene]?
    var nodes: [Node]?
    var meshes: [MeshDef]?
    var accessors: [Accessor]?
    var bufferViews: [BufferView]?
    var buffers: [BufferDef]?
    var materials: [Material]?
    var textures: [TextureDef]?
    var images: [ImageDef]?
}
