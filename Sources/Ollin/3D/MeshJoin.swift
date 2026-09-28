import Foundation
import simd

/// One mesh from several: parts placed by their transforms and joined into a
/// single `Mesh`, with no boolean. The result is one draw call, one shadow
/// caster, and one file for a printer.
///
/// ```swift
/// let body = Mesh.box(width: 1, height: 0.6, depth: 2)
/// let wheel = Mesh.cylinder(radius: 0.25, height: 0.2)
/// let car = Mesh.joined([
///     body,
///     wheel.placed(MeshInstance(position: Vector3(0.5, -0.3, 0.7), rotation: Vector3(0, 0, .pi / 2))),
///     wheel.placed(MeshInstance(position: Vector3(-0.5, -0.3, 0.7), rotation: Vector3(0, 0, .pi / 2))),
/// ])
/// drawMesh(car)
/// ```
///
/// Joining leaves the parts as they are: where two overlap, both surfaces stay
/// inside the result. That is what drawing them apart shows too, so a joined
/// mesh renders as its parts would, and it costs nothing but the copy. A
/// watertight solid for a printer, with the overlap merged, is `union(_:)`.
public extension Mesh {

    /// A copy with `placement` baked into its vertices: positions moved,
    /// turned and scaled by the placement's matrix, normals by its inverse
    /// transpose (so a non-uniform scale keeps them perpendicular), tangents
    /// by its linear part, and the placement's `color`, when it has one,
    /// multiplied into the vertex colors (a mesh with none gets a full set of
    /// that color).
    ///
    /// The arithmetic is the one `drawMesh` runs on a mesh under the
    /// transform stack, so a placed mesh drawn at the origin renders where
    /// the original would under the same `translate`/`rotate`/`scale` calls.
    func placed(_ placement: MeshInstance) -> Mesh {
        let m = placement.matrix
        let nm = m.normalMatrix
        let lin = simd_float3x3(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        var out = self
        out.positions = positions.map { p in
            let w = m * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
            return Vector3(Double(w.x), Double(w.y), Double(w.z))
        }
        out.normals = normals.map { n in
            let w = nm * SIMD3<Float>(Float(n.x), Float(n.y), Float(n.z))
            let len = simd_length(w)
            guard len > 1e-12 else { return .zero }
            let u = w / len
            return Vector3(Double(u.x), Double(u.y), Double(u.z))
        }
        out.tangents = tangents.map { t in
            let d = lin * SIMD3<Float>(Float(t.direction.x), Float(t.direction.y), Float(t.direction.z))
            let len = simd_length(d)
            guard len > 1e-8 else { return t }
            let u = d / len
            return MeshTangent(Vector3(Double(u.x), Double(u.y), Double(u.z)), handedness: t.handedness)
        }
        if let tint = placement.color {
            if colors.count == positions.count {
                out.colors = colors.map { c in
                    Color(red: c.red * tint.red, green: c.green * tint.green,
                          blue: c.blue * tint.blue, alpha: c.alpha * tint.alpha)
                }
            } else {
                out.colors = [Color](repeating: tint, count: positions.count)
            }
        }
        return out
    }

    /// The parts as one mesh: their vertices in order, each part's indices
    /// offset to its own vertices, and nothing merged or cut. Place each part
    /// first with `placed(_:)`; the join itself moves nothing.
    ///
    /// What the result carries: normals wherever any part has them (a vertex
    /// with none faces +z, as it does when drawn alone); texture coordinates
    /// and tangents only when *every* part has a full set, since half a set
    /// cannot map; vertex colors when any part has a full set, a part without
    /// them filled in white so it draws in the fill alone as before; and the
    /// first material among the parts, the rule a model merged by `loadMesh`
    /// follows. A part with no triangles, and a triangle that points past its
    /// part's vertices, are left out. Joining nothing gives an empty mesh.
    static func joined(_ parts: [Mesh]) -> Mesh {
        let live = parts.filter { !$0.isEmpty }
        guard !live.isEmpty else { return Mesh(positions: [], indices: []) }
        let anyNormals = live.contains { !$0.normals.isEmpty }
        let allUVs = live.allSatisfy { $0.uvs.count == $0.positions.count }
        let anyColors = live.contains { $0.colors.count == $0.positions.count }
        let allTangents = live.allSatisfy { $0.tangents.count == $0.positions.count }

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var indices: [UInt32] = []
        var uvs: [Vector2] = []
        var colors: [Color] = []
        var tangents: [MeshTangent] = []
        positions.reserveCapacity(live.reduce(0) { $0 + $1.positions.count })
        indices.reserveCapacity(live.reduce(0) { $0 + $1.indices.count })

        for part in live {
            let base = UInt32(positions.count)
            let count = UInt32(part.positions.count)
            positions.append(contentsOf: part.positions)
            if anyNormals {
                for i in 0 ..< part.positions.count {
                    normals.append(i < part.normals.count ? part.normals[i] : .unitZ)
                }
            }
            if allUVs { uvs.append(contentsOf: part.uvs) }
            if anyColors {
                if part.colors.count == part.positions.count {
                    colors.append(contentsOf: part.colors)
                } else {
                    colors.append(contentsOf: repeatElement(.white, count: part.positions.count))
                }
            }
            if allTangents { tangents.append(contentsOf: part.tangents) }
            var i = 0
            while i + 2 < part.indices.count {
                let a = part.indices[i], b = part.indices[i + 1], c = part.indices[i + 2]
                i += 3
                guard a < count, b < count, c < count else { continue }
                indices.append(base + a); indices.append(base + b); indices.append(base + c)
            }
        }

        return Mesh(positions: positions, normals: normals, indices: indices,
                    uvs: uvs, colors: colors,
                    material: live.first { $0.material != nil }?.material,
                    tangents: tangents)
    }
}
