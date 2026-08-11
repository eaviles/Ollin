import Foundation
import CMikkTSpace

/// A per-vertex tangent: the direction across the surface that the texture's
/// `u` axis runs in, plus the handedness that orients the bitangent. Together
/// with the vertex normal they form the basis a tangent-space normal map is
/// expressed in; the map's red/green/blue channels are a direction in exactly
/// this frame, so the frame has to exist before the map means anything.
///
/// `handedness` is +1 or -1: the bitangent (the `v` axis's direction) is
/// `handedness * (normal × direction)`. A mirrored patch of UVs flips it to -1,
/// which is what keeps a symmetric model's normal map from lighting one side
/// inside-out.
public struct MeshTangent: Equatable, Sendable {
    /// The surface's +u direction, unit length, perpendicular to the vertex normal.
    public var direction: Vector3
    /// +1 or -1: `bitangent = handedness * (normal × direction)`.
    public var handedness: Double

    public init(_ direction: Vector3, handedness: Double = 1) {
        self.direction = direction
        self.handedness = handedness
    }
}

// MARK: - Generation (MikkTSpace)

// The corner-indexed mesh view the MikkTSpace callbacks read, plus the
// per-corner output they write. A class so the C callbacks can reach it through
// the context's user-data pointer without capturing anything.
private final class TangentMeshData {
    let positions: [Vector3]
    let normals: [Vector3]
    let uvs: [Vector2]
    let indices: [UInt32]
    /// Base offset into `indices` of each complete, in-range triangle. The
    /// generator sees only these; a malformed triangle is skipped the same way
    /// `drawMesh` skips it.
    let faceBases: [Int]
    /// Per corner (face * 3 + vert): tangent x, y, z, sign. Written by the
    /// `setTSpaceBasic` callback.
    var output: [Float]

    init(positions: [Vector3], normals: [Vector3], uvs: [Vector2],
         indices: [UInt32], faceBases: [Int]) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
        self.faceBases = faceBases
        self.output = [Float](repeating: 0, count: faceBases.count * 3 * 4)
    }

    func vertexIndex(face: Int32, vert: Int32) -> Int {
        Int(indices[faceBases[Int(face)] + Int(vert)])
    }
}

private func tangentData(_ context: UnsafePointer<SMikkTSpaceContext>?) -> TangentMeshData {
    Unmanaged<TangentMeshData>.fromOpaque(context!.pointee.m_pUserData).takeUnretainedValue()
}

public extension Mesh {

    /// A copy with per-vertex `tangents` generated from the positions, normals,
    /// and `uvs`: the basis a normal map needs. Uses the vendored MikkTSpace
    /// generator, the tangent-space standard the glTF spec names and the one
    /// normal-map bakers target, so a generated basis matches a baked texture.
    ///
    /// `normalMapped(_:scale:)` and the model loaders call this for you; reach
    /// for it directly after a rebuild that dropped the tangents (`subdivided`,
    /// a hand-edit of the arrays). Needs `normals` and `uvs` aligned with
    /// `positions`; without them the mesh comes back unchanged.
    ///
    /// Where the standard basis genuinely differs between two triangles sharing
    /// a vertex (a mirrored-UV seam), the vertex is split so each side keeps its
    /// own frame: positions/normals/uvs/colors gain the duplicate and the
    /// triangle indices retarget, exactly what every tool doing this does.
    func generatingTangents() -> Mesh {
        guard normals.count == positions.count, uvs.count == positions.count,
              indices.count >= 3, !positions.isEmpty else { return self }
        var faceBases: [Int] = []
        faceBases.reserveCapacity(indices.count / 3)
        var i = 0
        while i + 2 < indices.count {
            if indices[i] < positions.count, indices[i + 1] < positions.count,
               indices[i + 2] < positions.count {
                faceBases.append(i)
            }
            i += 3
        }
        guard !faceBases.isEmpty else { return self }

        let data = TangentMeshData(positions: positions, normals: normals, uvs: uvs,
                                   indices: indices, faceBases: faceBases)

        var interface = SMikkTSpaceInterface()
        interface.m_getNumFaces = { context in
            Int32(tangentData(context).faceBases.count)
        }
        interface.m_getNumVerticesOfFace = { _, _ in 3 }
        interface.m_getPosition = { context, out, face, vert in
            let d = tangentData(context)
            let p = d.positions[d.vertexIndex(face: face, vert: vert)]
            out![0] = Float(p.x); out![1] = Float(p.y); out![2] = Float(p.z)
        }
        interface.m_getNormal = { context, out, face, vert in
            let d = tangentData(context)
            let n = d.normals[d.vertexIndex(face: face, vert: vert)]
            out![0] = Float(n.x); out![1] = Float(n.y); out![2] = Float(n.z)
        }
        interface.m_getTexCoord = { context, out, face, vert in
            let d = tangentData(context)
            let t = d.uvs[d.vertexIndex(face: face, vert: vert)]
            out![0] = Float(t.x); out![1] = Float(t.y)
        }
        interface.m_setTSpaceBasic = { context, tangent, sign, face, vert in
            let d = tangentData(context)
            let base = (Int(face) * 3 + Int(vert)) * 4
            d.output[base]     = tangent![0]
            d.output[base + 1] = tangent![1]
            d.output[base + 2] = tangent![2]
            d.output[base + 3] = sign
        }

        var ok: Int32 = 0
        withUnsafeMutablePointer(to: &interface) { interfacePtr in
            var context = SMikkTSpaceContext()
            context.m_pInterface = interfacePtr
            context.m_pUserData = Unmanaged.passUnretained(data).toOpaque()
            ok = genTangSpaceDefault(&context)
        }
        guard ok != 0 else { return self }

        // Fold the per-corner results back onto the vertices. MikkTSpace welds
        // internally, so every corner it grouped comes back with bit-identical
        // values; corners of a shared vertex normally agree exactly and the
        // index list survives untouched. Where they genuinely differ (a
        // mirrored-UV seam), the vertex splits: the corner retargets to a
        // duplicate carrying its own frame. Exact bit keys, face-order
        // processing, appends in encounter order, so the result is
        // deterministic throughout.
        struct CornerKey: Hashable {
            let vertex: Int
            let x: UInt32, y: UInt32, z: UInt32, s: UInt32
        }
        var result = self
        result.tangents = [MeshTangent](repeating: MeshTangent(Vector3(1, 0, 0)),
                                        count: positions.count)
        var claimed = [Bool](repeating: false, count: positions.count)
        var assigned: [CornerKey: UInt32] = [:]
        let carryColors = colors.count == positions.count
        for (face, base) in faceBases.enumerated() {
            for corner in 0..<3 {
                let o = (face * 3 + corner) * 4
                let tx = data.output[o], ty = data.output[o + 1]
                let tz = data.output[o + 2], sign = data.output[o + 3]
                let orig = Int(indices[base + corner])
                let key = CornerKey(vertex: orig, x: tx.bitPattern, y: ty.bitPattern,
                                    z: tz.bitPattern, s: sign.bitPattern)
                // The stored handedness is glTF's sign, which is MikkTSpace's
                // fSign *negated*. Measured, not assumed: the raw fSign makes
                // `fSign * cross(n, t)` point along +v (down the map image) on
                // every surface, while the spec's green-up maps need the
                // bitangent pointing image-up, so files in the wild (and the
                // Khronos test assets) store the negation. One convention
                // everywhere: authored glTF tangents pass through unchanged and
                // generated ones land in the same sign.
                let tangent = MeshTangent(Vector3(Double(tx), Double(ty), Double(tz)),
                                          handedness: -Double(sign))
                if let target = assigned[key] {
                    result.indices[base + corner] = target
                } else if !claimed[orig] {
                    claimed[orig] = true
                    result.tangents[orig] = tangent
                    assigned[key] = UInt32(orig)
                } else {
                    let newIndex = UInt32(result.positions.count)
                    result.positions.append(positions[orig])
                    result.normals.append(normals[orig])
                    result.uvs.append(uvs[orig])
                    if carryColors { result.colors.append(colors[orig]) }
                    result.tangents.append(tangent)
                    assigned[key] = newIndex
                    result.indices[base + corner] = newIndex
                }
            }
        }
        return result
    }

    /// A copy wearing `image` as its tangent-space normal map: per-pixel surface
    /// relief that bends the lighting normal, so a flat triangle shades like a
    /// detailed surface. `scale` is the relief strength (1 as authored, smaller
    /// flattens, larger exaggerates). The map rides the mesh's `uvs`, and the
    /// tangent basis it needs is generated here (MikkTSpace) if the mesh doesn't
    /// already carry one. Composes with `textured(_:)`; either order works.
    ///
    /// ```swift
    /// drawMesh(.sphere(radius: 200).textured(rock).normalMapped(rockBumps))
    /// ```
    func normalMapped(_ image: Image, scale: Double = 1) -> Mesh {
        var copy = self
        var m = copy.material ?? MeshMaterial()
        m.normalTexture = image
        m.normalScale = scale
        copy.material = m
        if copy.tangents.count != copy.positions.count,
           copy.uvs.count == copy.positions.count {
            copy = copy.generatingTangents()
        }
        return copy
    }

    /// A copy wearing `image` as its height map, read as parallax occlusion:
    /// the map's red channel is per-pixel depth (white the surface itself,
    /// darker carved in), and the fragment marches the eye ray through that
    /// relief so every other map, the base texture included, shifts the way a
    /// really carved surface would. `scale` is how deep the relief runs, as a
    /// fraction of the texture tile (the default recesses the darkest point 5%
    /// of the tile below the surface).
    ///
    /// Parallax shifts *shading only*: the silhouette, the cast shadow, and a
    /// reflection all keep the flat geometry. When the outline itself should
    /// change, read the same image as real geometry with
    /// `displaced(by:scale:)`.
    ///
    /// Like a normal map, the effect rides the mesh's `uvs` plus a tangent
    /// basis, generated here (MikkTSpace) if the mesh doesn't already carry
    /// one. Composes with `textured(_:)` / `normalMapped(_:scale:)` in any
    /// order.
    ///
    /// ```swift
    /// drawMesh(.sphere(radius: 200).textured(brick).parallaxMapped(brickHeight))
    /// ```
    func parallaxMapped(_ image: Image, scale: Double = 0.05) -> Mesh {
        var copy = self
        var m = copy.material ?? MeshMaterial()
        m.heightTexture = image
        m.heightScale = scale
        copy.material = m
        if copy.tangents.count != copy.positions.count,
           copy.uvs.count == copy.positions.count {
            copy = copy.generatingTangents()
        }
        return copy
    }

    /// A copy wearing detail maps: a second, much finer texture pair tiled
    /// `scale` times across each base uv tile, so the surface keeps texture
    /// when the camera gets close instead of dissolving into blur. `color`
    /// multiplies the base color (sampled as raw data with 128 gray the
    /// neutral: darker values darken, lighter ones lighten), and `normal` adds
    /// fine grain to the lighting, reoriented onto whatever the base normal
    /// map already shapes so the two reliefs compose rather than fight.
    /// `strength` fades the pair (1 as authored, 0 off). Either map may be
    /// `nil`; a normal detail needs the tangent basis, generated here
    /// (MikkTSpace) if the mesh doesn't already carry one. Composes with
    /// `textured(_:)` / `normalMapped(_:scale:)` / the rest of the map set in
    /// any order.
    ///
    /// ```swift
    /// drawMesh(.sphere(radius: 200).textured(rock)
    ///     .detailMapped(grain, normal: grainBumps, scale: 12))
    /// ```
    func detailMapped(_ color: Image? = nil, normal: Image? = nil,
                      scale: Double = 8, strength: Double = 1) -> Mesh {
        var copy = self
        var m = copy.material ?? MeshMaterial()
        m.detailTexture = color
        m.detailNormalTexture = normal
        m.detailScale = scale
        m.detailStrength = strength
        copy.material = m
        if normal != nil, copy.tangents.count != copy.positions.count,
           copy.uvs.count == copy.positions.count {
            copy = copy.generatingTangents()
        }
        return copy
    }
}
