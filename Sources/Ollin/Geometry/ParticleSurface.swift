import Foundation

/// A skin over a set of points: every point becomes a ball of `radius`, and
/// nearby balls blend into one smooth surface instead of intersecting as
/// separate spheres. This is the surfacing used for particle fluids, and it is
/// the right tool whenever the points are *material* (a splash, a clay-like
/// blob, a swarm dense enough to read as a body) rather than samples of some
/// original surface to be recovered; recovering is `reconstructSurface`.
///
/// ```swift
/// let skin = particleSurface(of: positions, radius: 0.1)
/// drawMesh(skin)
/// ```
///
/// It needs no normals and no structure: any bag of points works, including a
/// single one (which comes back as an exact ball). Blending is local, each
/// field sample looking only `blend * radius` around itself, so the cost
/// scales with the grid rather than with the point count squared.
///
/// The field is the classic blended distance: at a sample position, the
/// nearby points are averaged with a smooth falloff weight, and the surface
/// sits `radius` from that local average. Averaging is what removes the
/// bumpy union-of-spheres look; its known cost is that a strongly concave
/// neighborhood can bulge slightly inward or outward, which reads as
/// liquid surface tension and is usually the point.
///
/// - Parameters:
///   - points: The points to skin.
///   - radius: The ball each point contributes; the surface sits about this
///     far outside the points.
///   - blend: How far a sample looks for points to average, as a multiple of
///     `radius` (clamped to at least 1). Higher melts neighbors together from
///     farther apart; 1 approaches separate spheres.
///   - resolution: Grid cells across the longest side of the points' bounds,
///     as in `isosurface`. Raise it for finer detail at cubically more cost.
public func particleSurface(of points: [Vector3],
                            radius: Double,
                            blend: Double = 2,
                            resolution: Int = 64) -> Mesh {
    guard !points.isEmpty, radius > 0, radius.isFinite else {
        return Mesh(positions: [], indices: [])
    }
    let support = radius * max(blend, 1)
    let grid = PointGrid3(points: points, cellSize: support)

    var lo = points[0], hi = points[0]
    for p in points {
        lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
        hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
    }
    // The surface can reach at most `radius` past a point; pad a little more
    // so marching cubes closes the skin instead of clipping it at the wall.
    let size = hi - lo
    let longest = max(size.x, max(size.y, size.z), radius)
    let pad = radius + 1.5 * longest / Double(max(resolution, 1))
    let bounds = (min: lo - Vector3(pad, pad, pad), max: hi + Vector3(pad, pad, pad))

    let s2 = support * support
    return isosurface(at: 0, in: bounds, resolution: resolution) { p in
        // Kernel-weighted average of the nearby points; the surface sits
        // `radius` from it. The kernel is the smooth compact bump (1 - s²)³.
        var weightSum = 0.0
        var average = Vector3.zero
        grid.forEachNeighbor(of: p, within: support) { i, d2 in
            let s = 1 - d2 / s2
            let w = s * s * s
            weightSum += w
            average += grid.points[i] * w
        }
        guard weightSum > 0 else { return -radius }
        return radius - (p - average * (1 / weightSum)).length
    }
}

/// `particleSurface` over a point cloud's positions: skin a captured or
/// generated cloud with one call.
public func particleSurface(of cloud: PointCloud,
                            radius: Double,
                            blend: Double = 2,
                            resolution: Int = 64) -> Mesh {
    particleSurface(of: cloud.points.map(\.position),
                    radius: radius, blend: blend, resolution: resolution)
}
