import Foundation

// Per-vertex color transforms: paint an existing mesh procedurally, or hand it
// the colors of the point cloud it came from. The colors multiply the current
// `fill` at draw time (see `Mesh.colors`), so with the default white fill a
// colored mesh shows exactly these colors.

public extension Mesh {

    /// A copy carrying per-vertex colors computed by `body` from each vertex's
    /// position and normal, in that order (the normal is `.zero` when the mesh
    /// has none). Works on any mesh, so a generator can be painted as easily as
    /// a reconstruction:
    ///
    /// ```swift
    /// let globe = Mesh.sphere(radius: 1).colored { p, _ in
    ///     p.y > 0 ? .white : Color(hex: 0x2B6CB0)
    /// }
    /// ```
    func colored(by body: (Vector3, Vector3) -> Color) -> Mesh {
        var copy = self
        let aligned = normals.count == positions.count
        copy.colors = positions.indices.map { i in
            body(positions[i], aligned ? normals[i] : .zero)
        }
        return copy
    }

    /// A copy colored from a point cloud: each vertex takes the color of the
    /// cloud's nearest point. This is how a reconstructed scan keeps the colors
    /// its samples captured; `reconstructSurface(of: PointCloud)` already calls
    /// it for you, so reach for it directly when the mesh and the cloud met some
    /// other way (a `particleSurface` skin, a mesh sculpted after the fact).
    /// An empty cloud returns the mesh unchanged.
    func colored(from cloud: PointCloud) -> Mesh {
        guard !cloud.isEmpty, !positions.isEmpty else { return self }
        let samples = cloud.points.map(\.position)
        var lo = samples[0], hi = samples[0]
        for p in samples {
            lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        let extent = hi - lo
        let longest = Swift.max(extent.x, Swift.max(extent.y, extent.z))
        let grid = PointGrid3(points: samples, cellSize: Swift.max(longest / 64, 1e-9))
        var copy = self
        copy.colors = positions.map { p in
            grid.nearest(to: p).map { cloud.points[$0].color } ?? .white
        }
        return copy
    }
}
