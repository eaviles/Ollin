import Foundation

// Displacement mapping: the height map read as real geometry. The shading
// counterpart is `parallaxMapped(_:scale:)`, which carves the same relief
// per pixel without moving a vertex; this one moves the vertices, so the
// silhouette, the cast shadow, and a reflection all change with it.

public extension Mesh {

    /// A copy with `height` read as real geometry: every vertex moves along
    /// its surface normal by the height sampled at its uv, and the mesh's
    /// normals are recomputed for the new shape.
    ///
    /// The map's convention is the parallax one, so the two read one image
    /// the same way: the red channel is height, white *is* the authored
    /// surface, and darker carves in below it, `scale` (in the mesh's own
    /// units) being the depth of the deepest point. `parallaxMapped(_:scale:)`
    /// fakes this relief in shading alone; `displaced(by:scale:)` makes it
    /// true of the geometry, which is what changes the outline.
    ///
    /// The generators emit flat-shaded surfaces (each triangle its own three
    /// vertices), so displacement works on the position-welded surface:
    /// coincident vertices move together, along one averaged normal, by one
    /// averaged height, and a uv seam cannot tear the mesh open. Normals come
    /// back smooth (area-weighted over the welded surface); tangents, if the
    /// mesh carried them, are regenerated for the new shape. Needs per-vertex
    /// `uvs` and an image with CPU pixels; without either the mesh comes back
    /// unchanged with a printed note.
    ///
    /// ```swift
    /// let carved = Mesh.plane(width: 400, depth: 400, segments: 128)
    ///     .displaced(by: reliefImage, scale: 40)
    /// ```
    func displaced(by height: Image, scale: Double) -> Mesh {
        guard uvs.count == positions.count, !positions.isEmpty else {
            print("Ollin: displaced(by:) needs per-vertex uvs; returning the mesh unchanged.")
            return self
        }
        guard let pixels = height.premultipliedPixels(),
              height.width > 0, height.height > 0 else {
            print("Ollin: displaced(by:) needs an image with CPU pixels; returning the mesh unchanged.")
            return self
        }
        let field = HeightSampler(width: height.width, height: height.height, pixels: pixels)
        let welding = welded()

        // Per welded position: the averaged surface normal to move along
        // (the authored normals when they align, else the welded surface's own
        // face-normal sum) and the averaged sampled height, so every vertex a
        // seam split moves as one and the surface cannot tear.
        var groupNormal = [Vector3](repeating: .zero, count: welding.count)
        if normals.count == positions.count {
            for v in positions.indices {
                groupNormal[welding.remap[v]] = groupNormal[welding.remap[v]] + normals[v]
            }
        } else {
            var i = 0
            while i + 2 < welding.indices.count {
                let a = Int(welding.indices[i]), b = Int(welding.indices[i + 1])
                let c = Int(welding.indices[i + 2])
                i += 3
                let fn = (welding.positions[b] - welding.positions[a])
                    .cross(welding.positions[c] - welding.positions[a])
                groupNormal[a] = groupNormal[a] + fn
                groupNormal[b] = groupNormal[b] + fn
                groupNormal[c] = groupNormal[c] + fn
            }
        }
        var groupHeight = [Double](repeating: 0, count: welding.count)
        var groupCount = [Int](repeating: 0, count: welding.count)
        for v in positions.indices {
            let g = welding.remap[v]
            groupHeight[g] += field.sample(uvs[v].x, uvs[v].y)
            groupCount[g] += 1
        }

        // One offset per welded position. White (h 1) is the authored surface;
        // darker carves in below it, the parallax datum, so the two views of
        // one map agree.
        var offset = [Vector3](repeating: .zero, count: welding.count)
        for g in 0..<welding.count {
            let n = groupNormal[g]
            guard n.lengthSquared > 1e-12, groupCount[g] > 0 else { continue }
            let h = groupHeight[g] / Double(groupCount[g])
            offset[g] = n.normalized * ((h - 1) * scale)
        }

        var copy = self
        for v in positions.indices {
            copy.positions[v] = positions[v] + offset[welding.remap[v]]
        }

        // Smooth normals over the welded (connected) displaced surface,
        // republished per original vertex, so the relief lights as the
        // continuous surface it now is.
        if copy.normals.count == positions.count {
            var moved = welding.positions
            for g in 0..<welding.count { moved[g] = moved[g] + offset[g] }
            var accum = [Vector3](repeating: .zero, count: welding.count)
            var i = 0
            while i + 2 < welding.indices.count {
                let a = Int(welding.indices[i]), b = Int(welding.indices[i + 1])
                let c = Int(welding.indices[i + 2])
                i += 3
                let fn = (moved[b] - moved[a]).cross(moved[c] - moved[a])
                accum[a] = accum[a] + fn
                accum[b] = accum[b] + fn
                accum[c] = accum[c] + fn
            }
            for v in positions.indices {
                let n = accum[welding.remap[v]]
                if n.lengthSquared > 1e-12 { copy.normals[v] = n.normalized }
            }
        }

        // A carried tangent basis describes the old surface; regenerate it for
        // the new one (a normal or height map keeps working on the relief).
        if copy.tangents.count == copy.positions.count {
            copy.tangents = []
            copy = copy.generatingTangents()
        }
        return copy
    }
}

/// Clamp-to-edge bilinear sampling of a premultiplied RGBA8 buffer's red
/// channel, mirroring the GPU sampler the parallax march reads the same map
/// through (linear filter, clamp to edge, texel centers at half steps).
private struct HeightSampler {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func sample(_ u: Double, _ v: Double) -> Double {
        let x = u * Double(width) - 0.5
        let y = v * Double(height) - 0.5
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        func texel(_ tx: Int, _ ty: Int) -> Double {
            let cx = min(max(tx, 0), width - 1)
            let cy = min(max(ty, 0), height - 1)
            return Double(pixels[(cy * width + cx) * 4]) / 255
        }
        let top = texel(x0, y0) * (1 - fx) + texel(x0 + 1, y0) * fx
        let bottom = texel(x0, y0 + 1) * (1 - fx) + texel(x0 + 1, y0 + 1) * fx
        return top * (1 - fy) + bottom * fy
    }
}
