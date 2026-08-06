import Foundation

/// A mesh's vertices merged by position, plus the map back to the original
/// vertex order.
///
/// Ollin's mesh generators emit flat-shaded surfaces: every triangle carries
/// its own three vertices so each face can hold its own normal, which means
/// neighbouring triangles share no vertex index at all. Anything that treats a
/// mesh as a *connected surface* rather than a bag of triangles has to merge
/// those duplicates first, or it sees a pile of loose triangles.
///
/// The `remap` is what lets the caller keep speaking in the original mesh's
/// terms: it simulates or solves over `positions`, then republishes through
/// `remap` so results still line up with `Mesh.positions` index for index, and
/// the source mesh's uvs, colors, and material survive untouched.
package struct MeshWelding: Sendable {

    /// One position per distinct location, in first-seen order.
    package var positions: [Vector3]

    /// The triangles as flat corner indices into `positions`, degenerates
    /// dropped.
    package var indices: [UInt32]

    /// For each vertex of the original mesh, its index in `positions`.
    package var remap: [Int]

    /// How many original vertices merged onto each welded position.
    package var count: Int { positions.count }

    package init(positions: [Vector3], indices: [UInt32], remap: [Int]) {
        self.positions = positions
        self.indices = indices
        self.remap = remap
    }
}

extension Mesh {

    /// Merge this mesh's coincident vertices into one connected surface.
    ///
    /// Positions merge when they land in the same bucket at roughly one part in
    /// a million of the mesh's own extent, which is loose enough to catch the
    /// float-quantized duplicates a generator or a triangulator emits and tight
    /// enough to keep genuinely distinct vertices apart.
    package func welded() -> MeshWelding {
        let welded = WeldedMesh(self)
        var flat: [UInt32] = []
        flat.reserveCapacity(welded.triangles.count * 3)
        for tri in welded.triangles {
            flat.append(UInt32(tri.a))
            flat.append(UInt32(tri.b))
            flat.append(UInt32(tri.c))
        }
        return MeshWelding(positions: welded.positions, indices: flat, remap: welded.remap)
    }
}
