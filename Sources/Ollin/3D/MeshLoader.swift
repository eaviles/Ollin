import Foundation
import simd
#if canImport(ModelIO)
import ModelIO
#endif

// Loading a `Mesh` from a file. Three paths, chosen by extension: Ollin's own
// readers for Wavefront `.obj`, glTF, and the USD family (the same write-our-
// own-parser approach the bitmap/stroke fonts and the wire formats take), and
// Apple's Model I/O for the remaining binary containers (STL, PLY, Alembic).
// A loaded model arrives in its author's own coordinates and scale; `normalized(scale:)`
// (see `Mesh`) fits it for drawing the way the built-in generators already are.

extension Mesh {

    /// Load a 3D model from a file, dispatching on the extension: `.obj`, glTF, and
    /// the USD family (`.usdz`/`.usdc`/`.usda`/`.usd`) are parsed by Ollin's own
    /// readers; `.stl`, `.ply`, and `.abc` go through Apple's Model I/O. Returns
    /// `nil` if the file can't be read or holds no triangles. The model keeps its
    /// own coordinates and scale, call `normalized(scale:)` to fit it. Mirrors
    /// `Image(contentsOf:)`.
    public init?(contentsOf url: URL) {
        switch url.pathExtension.lowercased() {
        case "obj":
            guard let mesh = Mesh.loadOBJ(url) else { return nil }
            self = mesh
        case "gltf", "glb":
            guard let mesh = Mesh.loadGLTF(url) else { return nil }
            self = mesh
        case "usdz", "usdc", "usda", "usd":
            guard let mesh = Mesh.loadUSD(url) else { return nil }
            self = mesh
        #if canImport(ModelIO)
        case "stl", "ply", "abc":
            guard let mesh = Mesh.loadViaModelIO(url) else { return nil }
            self = mesh
        #endif
        default:
            return nil
        }
    }

    /// Load a model from a file `path`. Sugar over `Mesh(contentsOf:)`.
    public init?(path: String) { self.init(contentsOf: URL(fileURLWithPath: path)) }

    /// Load a model bundled as a resource. Mirrors `Image(resource:extension:in:)`
    /// and the font loaders, `in:` has no default, since a default argument would
    /// resolve to *Ollin's* bundle, not the caller's.
    public init?(resource name: String, withExtension ext: String?, in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        self.init(contentsOf: url)
    }
}

// MARK: - Wavefront OBJ

extension Mesh {

    /// Parse Wavefront OBJ source text into a `Mesh`. Reads geometric vertices (`v`),
    /// texture coordinates (`vt`), vertex normals (`vn`), and faces (`f`); skips
    /// grouping/smoothing directives and comments. The material (`mtllib`/`usemtl`)
    /// needs the file's folder to resolve, so a bare string parses geometry + UVs only
    /// — load from a URL (`Mesh(contentsOf:)`) to read the `.mtl` too. Faces may be
    /// polygons (fan-triangulated) and may reference vertices/UVs/normals 1-based or
    /// with negative (relative) indices, in any of OBJ's corner forms (`v`, `v/vt`,
    /// `v//vn`, `v/vt/vn`). When the file carries no normals, smooth, area-weighted
    /// vertex normals are computed. Returns `nil` if no triangles result. Total, a
    /// malformed line is skipped, never trapped (the file is untrusted input, like
    /// every other Ollin parser).
    public init?(objSource source: String) {
        guard let p = Mesh.parseOBJ(source) else { return nil }
        self.init(positions: p.positions, normals: p.normals, indices: p.indices, uvs: p.uvs)
    }

    /// Load an OBJ from a URL, also reading its `.mtl` material (diffuse color +
    /// texture) when the file references one (`mtllib` + the first `usemtl`), relative
    /// to the OBJ's folder.
    static func loadOBJ(_ url: URL) -> Mesh? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let p = parseOBJ(text) else { return nil }
        let material = p.mtllib.flatMap { lib -> MeshMaterial? in
            loadMTL(url.deletingLastPathComponent().appendingPathComponent(lib), use: p.material)
        }
        return Mesh(positions: p.positions, normals: p.normals, indices: p.indices,
                    uvs: p.uvs, material: material)
    }

    private struct ParsedOBJ {
        var positions: [Vector3]; var normals: [Vector3]; var uvs: [Vector2]
        var indices: [UInt32]; var mtllib: String?; var material: String?
    }

    /// The geometry-and-references half of OBJ parsing (no file I/O), shared by the
    /// bare-string init and the URL loader.
    private static func parseOBJ(_ source: String) -> ParsedOBJ? {
        var verts: [Vector3] = []
        var fileNormals: [Vector3] = []
        var fileUVs: [Vector2] = []

        var positions: [Vector3] = []
        var outNormals: [Vector3] = []
        var outUVs: [Vector2] = []
        var provided: [Bool] = []        // did this output vertex get a normal from the file?
        var providedUV: [Bool] = []      // and a texture coordinate?
        var indices: [UInt32] = []
        var cache: [Int64: UInt32] = [:] // (vertex, uv, normal) corner -> output index
        var mtllib: String?
        var material: String?

        // An OBJ index is 1-based, or negative meaning "relative to the count so far".
        // Resolve to a 0-based offset, or nil if out of range / the invalid 0.
        func resolve(_ idx: Int, count: Int) -> Int? {
            if idx > 0 { return idx <= count ? idx - 1 : nil }
            if idx < 0 { let i = count + idx; return i >= 0 ? i : nil }
            return nil
        }

        // A face corner, "v", "v/vt", "v//vn", or "v/vt/vn", to (vertex, uv?, normal?).
        func corner(_ token: Substring) -> (v: Int, vt: Int?, vn: Int?)? {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let first = parts.first, let v = Int(first) else { return nil }
            let vt = parts.count >= 2 ? Int(parts[1]) : nil   // empty in "v//vn"
            let vn = parts.count >= 3 ? Int(parts[2]) : nil
            return (v, vt, vn)
        }

        // The output index for a unique (vertex, uv, normal) corner, appending on first
        // use so faces that share a corner share a vertex (and its normal/UV).
        func emit(_ c: (v: Int, vt: Int?, vn: Int?)) -> UInt32? {
            guard let vi = resolve(c.v, count: verts.count) else { return nil }
            let ni = c.vn.flatMap { resolve($0, count: fileNormals.count) }
            let ti = c.vt.flatMap { resolve($0, count: fileUVs.count) }
            let key = (Int64(vi) &* 1_000_003 &+ Int64((ni ?? -1) + 1)) &* 1_000_003 &+ Int64((ti ?? -1) + 1)
            if let existing = cache[key] { return existing }
            let out = UInt32(positions.count)
            positions.append(verts[vi])
            if let ni { outNormals.append(fileNormals[ni]); provided.append(true) }
            else { outNormals.append(.zero); provided.append(false) }
            if let ti, ti < fileUVs.count { outUVs.append(fileUVs[ti]); providedUV.append(true) }
            else { outUVs.append(.zero); providedUV.append(false) }
            cache[key] = out
            return out
        }

        for line in source.split(whereSeparator: \.isNewline) {
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let first = tokens.first else { continue }
            let values = tokens.dropFirst()
            switch String(first) {
            case "v":
                let f = values.compactMap { Double($0) }
                if f.count >= 3 { verts.append(Vector3(f[0], f[1], f[2])) }
            case "vn":
                let f = values.compactMap { Double($0) }
                if f.count >= 3 { fileNormals.append(Vector3(f[0], f[1], f[2])) }
            case "vt":
                let f = values.compactMap { Double($0) }
                if f.count >= 2 { fileUVs.append(Vector2(f[0], f[1])) }
            case "f":
                let outs = values.compactMap(corner).compactMap(emit)
                guard outs.count >= 3 else { continue }
                for k in 1..<(outs.count - 1) {        // fan-triangulate the polygon
                    indices.append(outs[0]); indices.append(outs[k]); indices.append(outs[k + 1])
                }
            case "mtllib":
                if mtllib == nil, let name = values.first { mtllib = String(name) }
            case "usemtl":
                if material == nil, let name = values.first { material = String(name) }
            default:
                continue   // o, g, s, comments, anything else
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else { return nil }

        // Smooth (area-weighted) normals for any vertex the file gave none.
        if provided.contains(false) {
            var accum = [Vector3](repeating: .zero, count: positions.count)
            var i = 0
            while i + 2 < indices.count {
                let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
                let faceNormal = (positions[b] - positions[a]).cross(positions[c] - positions[a])
                accum[a] = accum[a] + faceNormal
                accum[b] = accum[b] + faceNormal
                accum[c] = accum[c] + faceNormal
                i += 3
            }
            for k in positions.indices where !provided[k] {
                outNormals[k] = accum[k].lengthSquared > 1e-12 ? accum[k].normalized : .unitY
            }
        }
        // Re-unitize file-provided normals (some exporters write non-unit vectors).
        for k in positions.indices where provided[k] {
            outNormals[k] = outNormals[k].lengthSquared > 1e-12 ? outNormals[k].normalized : .unitY
        }

        // Keep UVs only if every output vertex carried one (a partial set can't map).
        let uvs = providedUV.allSatisfy { $0 } ? outUVs : []
        return ParsedOBJ(positions: positions, normals: outNormals, uvs: uvs, indices: indices,
                         mtllib: mtllib, material: material)
    }

    /// Read a `.mtl` for the named material (or the first one): diffuse `Kd` → base
    /// color, `map_Kd` → texture image (relative to the `.mtl`'s folder). OBJ has no
    /// color-space tag, so `Kd` is taken as the display (sRGB) color directly.
    private static func loadMTL(_ url: URL, use name: String?) -> MeshMaterial? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let dir = url.deletingLastPathComponent()
        struct M { var kd: Color?; var mapKd: String?; var clamped = false }
        var mats: [String: M] = [:]
        var order: [String] = []
        var cur: String?
        for line in text.split(whereSeparator: \.isNewline) {
            let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard let key = t.first else { continue }
            let vals = Array(t.dropFirst())
            switch String(key) {
            case "newmtl":
                let n = vals.first.map(String.init)
                cur = n
                if let n, mats[n] == nil { mats[n] = M(); order.append(n) }
            case "Kd":
                let f = vals.compactMap { Double($0) }
                if f.count >= 3, let c = cur { mats[c]?.kd = Color(red: f[0], green: f[1], blue: f[2]) }
            case "map_Kd":
                // The map path is the last token (earlier tokens are options like -s).
                if let file = vals.last, let c = cur { mats[c]?.mapKd = String(file) }
                // The format has one word about wrapping, and it turns tiling
                // *off*: `-clamp on`. So an unmarked map tiles, which is what
                // every renderer of this format does with it.
                if let c = cur, let i = vals.firstIndex(of: "-clamp") {
                    mats[c]?.clamped = vals.count > i + 1 && vals[i + 1] == "on"
                }
            default:
                continue
            }
        }
        let chosen = name.flatMap { mats[$0] != nil ? $0 : nil } ?? order.first
        guard let key = chosen, let m = mats[key] else { return nil }
        var texture: Image?
        if let file = m.mapKd {
            let path = file.removingPercentEncoding ?? file
            if let data = try? Data(contentsOf: dir.appendingPathComponent(path)) { texture = Image(data: data) }
        }
        if m.kd == nil, texture == nil { return nil }
        return MeshMaterial(baseColor: m.kd ?? .white, texture: texture,
                            wrap: texture == nil ? .clamp : (m.clamped ? .clamp : .tile))
    }
}

// MARK: - USD (merged)

extension Mesh {

    /// A USD file merged to one `Mesh`: the native scene read
    /// (`Scene.loadUSDScene`) walked with node transforms *baked into* the
    /// vertices, so a multi-part file's placement survives the merge, exactly
    /// the glTF merged-loader treatment. The merged mesh wears the first
    /// authored material (in traversal order) carrying a color or texture;
    /// UVs are kept only when every part has them (a partial set can't map).
    static func loadUSD(_ url: URL) -> Mesh? {
        guard let scene = Scene.loadUSDScene(url) else { return nil }

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2] = []
        var indices: [UInt32] = []
        var allHaveUV = true
        var material: MeshMaterial?

        func visit(_ node: SceneNode, parent: simd_float4x4) {
            let world = parent * node.localTransform
            if let mesh = node.mesh, !mesh.positions.isEmpty, !mesh.indices.isEmpty {
                let normalMatrix = world.normalMatrix
                let base = UInt32(positions.count)
                for p in mesh.positions {
                    let w = world * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
                    positions.append(Vector3(Double(w.x), Double(w.y), Double(w.z)))
                }
                for n in mesh.normals {
                    let w = normalMatrix * SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z))
                    let v = Vector3(Double(w.x), Double(w.y), Double(w.z))
                    normals.append(v.lengthSquared > 1e-12 ? v.normalized : .unitY)
                }
                if mesh.uvs.count == mesh.positions.count {
                    uvs.append(contentsOf: mesh.uvs)
                } else {
                    allHaveUV = false
                    uvs.append(contentsOf: repeatElement(.zero, count: mesh.positions.count))
                }
                indices.append(contentsOf: mesh.indices.map { base + $0 })
                if material == nil { material = mesh.material }
            }
            for child in node.children { visit(child, parent: world) }
        }
        for node in scene.nodes { visit(node, parent: matrix_identity_float4x4) }

        guard !positions.isEmpty, !indices.isEmpty else { return nil }
        var mesh = Mesh(positions: positions, normals: normals, indices: indices,
                        uvs: allHaveUV ? uvs : [], material: material)
        // A normal-mapped material generates the standard basis over the
        // merged uvs (the loadGLTF rule); the merged mesh carries nothing
        // aligned to its vertex order, so a seam split is always safe here.
        if mesh.material?.normalTexture != nil, mesh.tangents.count != mesh.positions.count,
           !mesh.uvs.isEmpty {
            mesh = mesh.generatingTangents()
        }
        return mesh
    }
}

// MARK: - Model I/O (STL, PLY, Alembic)

#if canImport(ModelIO)
extension Mesh {

    /// One `MDLMesh`'s payload, read in the mesh's own local space: the unit of
    /// work `loadViaModelIO` merges and the structure-preserving scene reader
    /// keeps per node. `uvs` is `nil` when the mesh carries no texture
    /// coordinates (the merged loader needs the distinction to drop UVs unless
    /// every mesh has them).
    struct MDLMeshData {
        var positions: [Vector3]
        var normals: [Vector3]
        var uvs: [Vector2]?
        var indices: [UInt32]
        var colors: [Color]?
        var material: MeshMaterial?
    }

    /// Read positions, normals, triangle indices, texture coordinates, and the
    /// base-color material out of any container Model I/O can open. Every `MDLMesh` in
    /// the asset is merged into one `Mesh`; a mesh with no normals has them generated.
    /// Reads attribute data by its own stride/offset (so interleaved buffers are
    /// handled) and submesh index buffers at their own bit depth. The merged mesh wears
    /// the first submesh material that carries a base color or texture.
    static func loadViaModelIO(_ url: URL) -> Mesh? {
        let asset = MDLAsset(url: url)
        guard let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh],
              !mdlMeshes.isEmpty else { return nil }

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2] = []
        var indices: [UInt32] = []
        var allHaveUV = true
        // Vertex colors fill with white where a mesh has none, since white is the
        // multiply identity: a partial set costs nothing, so they survive as soon as
        // any merged mesh carried them (unlike UVs, where a partial set would mismap).
        var colors: [Color] = []
        var anyHaveColor = false
        var material: MeshMaterial?

        for mdl in mdlMeshes {
            guard let data = readMDLMesh(mdl) else { continue }
            let base = UInt32(positions.count)
            positions.append(contentsOf: data.positions)
            normals.append(contentsOf: data.normals)
            if let meshUVs = data.uvs {
                uvs.append(contentsOf: meshUVs)
            } else {
                allHaveUV = false
                uvs.append(contentsOf: repeatElement(.zero, count: data.positions.count))
            }
            if let meshColors = data.colors, meshColors.count == data.positions.count {
                colors.append(contentsOf: meshColors)
                anyHaveColor = true
            } else {
                colors.append(contentsOf: repeatElement(.white, count: data.positions.count))
            }
            indices.append(contentsOf: data.indices.map { base + $0 })
            if material == nil { material = data.material }
        }

        guard !positions.isEmpty, !indices.isEmpty else { return nil }
        return Mesh(positions: positions, normals: normals, indices: indices,
                    uvs: allHaveUV ? uvs : [], colors: anyHaveColor ? colors : [],
                    material: material)
    }

    /// Read one `MDLMesh`'s vertices, triangle indices, and first readable
    /// material, generating normals when the file has none and re-unitizing the
    /// ones it does have (some exporters write non-unit vectors). Returns `nil`
    /// for a mesh with no position data.
    static func readMDLMesh(_ mdl: MDLMesh) -> MDLMeshData? {
        let normalAttr = mdl.vertexDescriptor.attributeNamed(MDLVertexAttributeNormal)
        if normalAttr == nil || normalAttr?.format == MDLVertexFormat.invalid {
            mdl.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.2)
        }
        guard let posAttr = mdl.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition,
                                                    as: .float3) else { return nil }
        let nrmAttr = mdl.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3)
        let uvAttr = mdl.vertexAttributeData(forAttributeNamed: MDLVertexAttributeTextureCoordinate, as: .float2)
        let count = mdl.vertexCount

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2]?
        var indices: [UInt32] = []
        var colors: [Color]?
        var material: MeshMaterial?

        // Positions and normals are read three floats at a time from each vertex's
        // stride, `SIMD3<Float>` is 16-byte-padded, so a packed float3 buffer must
        // be read float-by-float, not as a SIMD3.
        for i in 0..<count {
            let p = posAttr.dataStart.advanced(by: i * posAttr.stride).assumingMemoryBound(to: Float.self)
            positions.append(Vector3(Double(p[0]), Double(p[1]), Double(p[2])))
        }
        if let nrmAttr {
            for i in 0..<count {
                let n = nrmAttr.dataStart.advanced(by: i * nrmAttr.stride).assumingMemoryBound(to: Float.self)
                normals.append(Vector3(Double(n[0]), Double(n[1]), Double(n[2])))
            }
        } else {
            normals.append(contentsOf: repeatElement(.unitY, count: count))
        }
        if let uvAttr {
            var read: [Vector2] = []
            for i in 0..<count {
                let t = uvAttr.dataStart.advanced(by: i * uvAttr.stride).assumingMemoryBound(to: Float.self)
                read.append(Vector2(Double(t[0]), Double(t[1])))
            }
            uvs = read
        }
        // Per-vertex color, the payload a scanned or vertex-painted mesh carries (a
        // point-cloud PLY's `red`/`green`/`blue`). These arrive as *display* values
        // (the format stores what a viewer should show, and nothing color-manages
        // them on the way in), so they become a `Color` directly rather than being
        // re-encoded the way a linear glTF factor is.
        //
        // The requested format must keep the attribute's own component count. Asking
        // a three-component color for four hands back a buffer that reads as the
        // first vertex's value repeated for every vertex, silently: it does not
        // return nil, so there is nothing to fall back from. The count is the low
        // byte of the format, so read that and ask for the matching width.
        func clamped01(_ v: Float) -> Double { Double(min(max(v, 0), 1)) }
        let colorFormat = mdl.vertexDescriptor.attributeNamed(MDLVertexAttributeColor)?.format
        if let colorFormat, colorFormat != .invalid {
            let wide = Int(colorFormat.rawValue & 0xFF) >= 4
            if let colorAttr = mdl.vertexAttributeData(forAttributeNamed: MDLVertexAttributeColor,
                                                       as: wide ? .float4 : .float3) {
                var read: [Color] = []
                read.reserveCapacity(count)
                for i in 0..<count {
                    let c = colorAttr.dataStart.advanced(by: i * colorAttr.stride)
                        .assumingMemoryBound(to: Float.self)
                    read.append(Color(red: clamped01(c[0]), green: clamped01(c[1]),
                                      blue: clamped01(c[2]),
                                      alpha: wide ? clamped01(c[3]) : 1))
                }
                colors = read
            }
        }

        for case let submesh as MDLSubmesh in mdl.submeshes ?? [] {
            if material == nil, let m = submesh.material { material = readMaterial(m) }
            guard submesh.geometryType == .triangles else { continue }
            let map = submesh.indexBuffer.map()
            let raw = map.bytes
            switch submesh.indexType {
            case .uInt32:
                let p = raw.assumingMemoryBound(to: UInt32.self)
                for i in 0..<submesh.indexCount { indices.append(p[i]) }
            case .uInt16:
                let p = raw.assumingMemoryBound(to: UInt16.self)
                for i in 0..<submesh.indexCount { indices.append(UInt32(p[i])) }
            case .uInt8:
                let p = raw.assumingMemoryBound(to: UInt8.self)
                for i in 0..<submesh.indexCount { indices.append(UInt32(p[i])) }
            default:
                continue
            }
        }

        let unit = normals.map { $0.lengthSquared > 1e-12 ? $0.normalized : .unitY }
        return MDLMeshData(positions: positions, normals: unit, uvs: uvs,
                           indices: indices, colors: colors, material: material)
    }

    /// Read an `MDLMaterial`'s base color: a texture (decoded to an `Image`) or a solid
    /// color/float3, whichever the `.baseColor` property carries. Other channels
    /// (metallic/roughness, normal) are the later PBR tier. Returns nil if neither is
    /// present. (A texture comes back at Model I/O's image origin; a vertically
    /// flipped result is a known limitation until UV-origin handling lands.)
    private static func readMaterial(_ mdlMaterial: MDLMaterial) -> MeshMaterial? {
        guard let prop = mdlMaterial.property(with: .baseColor) else { return nil }
        var baseColor: Color?
        var texture: Image?
        var wrap = TextureWrap.clamp
        switch prop.type {
        case .texture:
            if let cg = prop.textureSamplerValue?.texture?.imageFromTexture()?.takeRetainedValue() {
                texture = Image(cgImage: cg)
            }
            // The file's own answer for uvs outside the square, as Model I/O read
            // it. It reports clamp when the format said nothing, which is the
            // conservative reading and the one Ollin defaults to anyway.
            switch prop.textureSamplerValue?.hardwareFilter?.sWrapMode {
            case .some(.repeat): wrap = .tile
            case .some(.mirror): wrap = .mirror
            default: break
            }
        case .color:
            if let comps = prop.color?.components, comps.count >= 3 {
                baseColor = Color(red: Double(comps[0]), green: Double(comps[1]), blue: Double(comps[2]))
            }
        case .float3:
            let f = prop.float3Value
            baseColor = Color(red: Double(f.x), green: Double(f.y), blue: Double(f.z))
        default:
            break
        }
        if baseColor == nil, texture == nil { return nil }
        return MeshMaterial(baseColor: baseColor ?? .white, texture: texture, wrap: wrap)
    }
}
#endif

// MARK: - Sketch sugar

extension Sketch {

    /// Load a 3D model from a file `path` (`.obj`, `.usdz`, `.stl`, …) for `drawMesh`.
    /// Returns `nil` if it can't be read. Call it in `setup()` and keep the result in
    /// a property, parsing every frame is wasteful. Sugar over `Mesh(contentsOf:)`.
    public func loadMesh(_ path: String) -> Mesh? { Mesh(path: path) }

    /// Load a model from a file `url`. Sugar over `Mesh(contentsOf:)`.
    public func loadMesh(_ url: URL) -> Mesh? { Mesh(contentsOf: url) }
}
