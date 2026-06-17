import Foundation
import simd
#if canImport(ModelIO)
import ModelIO
#endif

// Loading a `Mesh` from a file. Two paths, chosen by extension: Ollin's own reader
// for Wavefront `.obj` (a small, well-understood text format, the same write-our-
// own-parser approach the bitmap/stroke fonts and the wire formats take), and
// Apple's Model I/O for the binary container formats (the USD family, STL, PLY).
// A loaded model arrives in its author's own coordinates and scale; `normalized(scale:)`
// (see `Mesh`) fits it for drawing the way the built-in generators already are.

extension Mesh {

    /// Load a 3D model from a file, dispatching on the extension: `.obj` is parsed by
    /// Ollin's own reader; `.usdz`/`.usdc`/`.usda`/`.usd`, `.stl`, `.ply`, and `.abc`
    /// go through Apple's Model I/O. Returns `nil` if the file can't be read or holds
    /// no triangles. The model keeps its own coordinates and scale, call
    /// `normalized(scale:)` to fit it. Mirrors `Image(contentsOf:)`.
    public init?(contentsOf url: URL) {
        switch url.pathExtension.lowercased() {
        case "obj":
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let mesh = Mesh(objSource: text) else { return nil }
            self = mesh
        case "gltf", "glb":
            guard let mesh = Mesh.loadGLTF(url) else { return nil }
            self = mesh
        #if canImport(ModelIO)
        case "usdz", "usdc", "usda", "usd", "stl", "ply", "abc":
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
    public init?(resource name: String, extension ext: String?, in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext) else { return nil }
        self.init(contentsOf: url)
    }
}

// MARK: - Wavefront OBJ

extension Mesh {

    /// Parse Wavefront OBJ source text into a `Mesh`. Reads geometric vertices (`v`),
    /// vertex normals (`vn`), and faces (`f`); skips texture coords (`vt`, no UVs on
    /// `Mesh` yet), grouping/smoothing/material directives, and comments. Faces may be
    /// polygons (triangulated as a fan) and may reference vertices and normals either
    /// 1-based or with negative (relative) indices, in any of OBJ's corner forms (`v`,
    /// `v/vt`, `v//vn`, `v/vt/vn`). When the file carries no normals, smooth,
    /// area-weighted vertex normals are computed. Returns `nil` if no triangles
    /// result. Total, a malformed line is skipped, never trapped (the file is
    /// untrusted input, like every other Ollin parser).
    public init?(objSource source: String) {
        var verts: [Vector3] = []
        var fileNormals: [Vector3] = []

        var positions: [Vector3] = []
        var outNormals: [Vector3] = []
        var provided: [Bool] = []        // did this output vertex get a normal from the file?
        var indices: [UInt32] = []
        var cache: [Int64: UInt32] = [:] // (vertex, normal) corner -> output index

        // An OBJ index is 1-based, or negative meaning "relative to the count so far".
        // Resolve to a 0-based offset, or nil if out of range / the invalid 0.
        func resolve(_ idx: Int, count: Int) -> Int? {
            if idx > 0 { return idx <= count ? idx - 1 : nil }
            if idx < 0 { let i = count + idx; return i >= 0 ? i : nil }
            return nil
        }

        // A face corner, "v", "v/vt", "v//vn", or "v/vt/vn", to (vertex, normal?).
        func corner(_ token: Substring) -> (v: Int, vn: Int?)? {
            let parts = token.split(separator: "/", omittingEmptySubsequences: false)
            guard let first = parts.first, let v = Int(first) else { return nil }
            let vn = parts.count >= 3 ? Int(parts[2]) : nil
            return (v, vn)
        }

        // The output index for a unique (vertex, normal) corner, appending on first use
        // so faces that share a corner share a vertex (and a smooth normal).
        func emit(_ c: (v: Int, vn: Int?)) -> UInt32? {
            guard let vi = resolve(c.v, count: verts.count) else { return nil }
            let ni = c.vn.flatMap { resolve($0, count: fileNormals.count) }
            let key = Int64(vi) &* 1_000_000 &+ Int64((ni ?? -1) + 1)
            if let existing = cache[key] { return existing }
            let out = UInt32(positions.count)
            positions.append(verts[vi])
            if let ni { outNormals.append(fileNormals[ni]); provided.append(true) }
            else { outNormals.append(.zero); provided.append(false) }
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
            case "f":
                let outs = values.compactMap(corner).compactMap(emit)
                guard outs.count >= 3 else { continue }
                for k in 1..<(outs.count - 1) {        // fan-triangulate the polygon
                    indices.append(outs[0]); indices.append(outs[k]); indices.append(outs[k + 1])
                }
            default:
                continue   // vt, o, g, s, mtllib, usemtl, comments, anything else
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

        self.init(positions: positions, normals: outNormals, indices: indices)
    }
}

// MARK: - Model I/O (USD family, STL, PLY, Alembic)

#if canImport(ModelIO)
extension Mesh {

    /// Read positions, normals, and triangle indices out of any container Model I/O
    /// can open. Every `MDLMesh` in the asset is merged into one `Mesh`; a mesh with
    /// no normals has them generated. Reads attribute data by its own stride/offset
    /// (so interleaved buffers are handled) and submesh index buffers at their own
    /// bit depth.
    static func loadViaModelIO(_ url: URL) -> Mesh? {
        let asset = MDLAsset(url: url)
        guard let mdlMeshes = asset.childObjects(of: MDLMesh.self) as? [MDLMesh],
              !mdlMeshes.isEmpty else { return nil }

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []

        for mdl in mdlMeshes {
            let normalAttr = mdl.vertexDescriptor.attributeNamed(MDLVertexAttributeNormal)
            if normalAttr == nil || normalAttr?.format == MDLVertexFormat.invalid {
                mdl.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.2)
            }
            guard let posAttr = mdl.vertexAttributeData(forAttributeNamed: MDLVertexAttributePosition,
                                                        as: .float3) else { continue }
            let nrmAttr = mdl.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal, as: .float3)
            let base = UInt32(positions.count)
            let count = mdl.vertexCount

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

            for case let submesh as MDLSubmesh in mdl.submeshes ?? [] {
                guard submesh.geometryType == .triangles else { continue }
                let map = submesh.indexBuffer.map()
                let raw = map.bytes
                switch submesh.indexType {
                case .uInt32:
                    let p = raw.assumingMemoryBound(to: UInt32.self)
                    for i in 0..<submesh.indexCount { indices.append(base + p[i]) }
                case .uInt16:
                    let p = raw.assumingMemoryBound(to: UInt16.self)
                    for i in 0..<submesh.indexCount { indices.append(base + UInt32(p[i])) }
                case .uInt8:
                    let p = raw.assumingMemoryBound(to: UInt8.self)
                    for i in 0..<submesh.indexCount { indices.append(base + UInt32(p[i])) }
                default:
                    continue
                }
            }
        }

        guard !positions.isEmpty, !indices.isEmpty else { return nil }
        let unit = normals.map { $0.lengthSquared > 1e-12 ? $0.normalized : .unitY }
        return Mesh(positions: positions, normals: unit, indices: indices)
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
