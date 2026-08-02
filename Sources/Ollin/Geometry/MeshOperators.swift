import Foundation

/// Discrete differential-geometry operators over a triangle mesh: the 1-ring
/// neighborhood of every vertex, the cotangent weight of every incident edge,
/// and the mixed-area cell each vertex owns.
///
/// This is the substrate under both surface reaction-diffusion and
/// curvature-driven growth. The reason it exists (rather than each of those
/// averaging its neighbors) is that a plain average is only correct on a
/// regular grid: on a triangle mesh two neighbors sit at different distances
/// across differently shaped cells, so they must carry different weights, or a
/// pattern shears wherever the triangles do.
///
/// The weights are the standard cotangent form: the weight of edge *(i, j)* is
/// the sum of the cotangents of the two angles opposite it, and a vertex's cell
/// is the mixed area, meaning the Voronoi region where the triangle allows it
/// and a halved or quartered triangle area where an obtuse angle would push the
/// Voronoi region outside the 1-ring.
struct MeshOperators {

    /// For each vertex, its 1-ring neighbors in ascending index order.
    let neighbors: [[Int]]
    /// For each vertex, the cotangent weight of the edge to each entry of
    /// `neighbors`, in matching order.
    let weights: [[Double]]
    /// For each vertex, the area of the surface cell it owns (the mixed area).
    let areas: [Double]
    /// The mean length over all edges, the natural length unit of the mesh.
    let meanEdgeLength: Double

    /// Build the operators for a triangle mesh given as positions plus triangle
    /// corner triples. Vertices no triangle uses get an empty neighborhood and a
    /// tiny positive area, so dividing by the area is always safe.
    init(positions: [Vector3], triangles: [MeshTriangle]) {
        let count = positions.count
        var neighborLists = [[Int]](repeating: [], count: count)
        var weightMap = [[Int: Double]](repeating: [:], count: count)
        var areaTotals = [Double](repeating: 0, count: count)

        for tri in triangles {
            let (ia, ib, ic) = (tri.a, tri.b, tri.c)
            guard ia < count, ib < count, ic < count else { continue }
            let a = positions[ia], b = positions[ib], c = positions[ic]

            // Cotangent of each corner angle: cot = cos/sin = dot/|cross|. A
            // corner is obtuse exactly when its cotangent is negative, which is
            // also the test the mixed area needs.
            let cotA = MeshOperators.cotangent(at: a, b, c)
            let cotB = MeshOperators.cotangent(at: b, c, a)
            let cotC = MeshOperators.cotangent(at: c, a, b)

            // The weight of an edge is the cotangent of the angle opposite it,
            // summed over the triangles that share the edge.
            MeshOperators.accumulate(&weightMap, ia, ib, cotC)
            MeshOperators.accumulate(&weightMap, ib, ic, cotA)
            MeshOperators.accumulate(&weightMap, ic, ia, cotB)

            let area = (b - a).cross(c - a).length * 0.5
            guard area > 1e-18 else { continue }

            if cotA >= 0, cotB >= 0, cotC >= 0 {
                // Non-obtuse: each corner takes its true Voronoi region,
                // (1/8)(|PR|² cot∠Q + |PQ|² cot∠R).
                areaTotals[ia] += ((a - c).lengthSquared * cotB + (a - b).lengthSquared * cotC) / 8
                areaTotals[ib] += ((b - a).lengthSquared * cotC + (b - c).lengthSquared * cotA) / 8
                areaTotals[ic] += ((c - b).lengthSquared * cotA + (c - a).lengthSquared * cotB) / 8
            } else {
                // Obtuse: the Voronoi region would leave the 1-ring, so the
                // triangle is split half to the obtuse corner, a quarter each to
                // the other two. The cells still tile the surface exactly once.
                areaTotals[ia] += cotA < 0 ? area / 2 : area / 4
                areaTotals[ib] += cotB < 0 ? area / 2 : area / 4
                areaTotals[ic] += cotC < 0 ? area / 2 : area / 4
            }
        }

        var weightLists = [[Double]](repeating: [], count: count)
        var edgeTotal = 0.0
        var edgeCount = 0
        for v in 0 ..< count {
            // Sorted, so every later pass over a neighborhood runs in a fixed
            // order rather than a Dictionary's.
            let sorted = weightMap[v].keys.sorted()
            neighborLists[v] = sorted
            weightLists[v] = sorted.map { weightMap[v][$0] ?? 0 }
            for n in sorted where n > v {
                edgeTotal += positions[v].distance(to: positions[n])
                edgeCount += 1
            }
        }

        self.neighbors = neighborLists
        self.weights = weightLists
        self.areas = areaTotals.map { Swift.max($0, 1e-12) }
        self.meanEdgeLength = edgeCount > 0 ? edgeTotal / Double(edgeCount) : 0
    }

    /// The discrete Laplace-Beltrami operator applied to a scalar field, one
    /// value per vertex: how much the field at each vertex differs from the
    /// area-weighted average around it.
    ///
    /// Scaled by the square of the mean edge length, which makes it
    /// dimensionless, so a field on a coarse mesh and the same field on a fine
    /// one diffuse at the same rate per step and diffusion constants tuned on a
    /// grid carry over unchanged.
    func laplacian(of field: [Double]) -> [Double] {
        let h2 = meanEdgeLength * meanEdgeLength
        guard h2 > 0 else { return [Double](repeating: 0, count: field.count) }
        var out = [Double](repeating: 0, count: field.count)
        for v in 0 ..< Swift.min(field.count, neighbors.count) {
            var sum = 0.0
            let ns = neighbors[v], ws = weights[v]
            for k in ns.indices where ns[k] < field.count {
                sum += ws[k] * (field[ns[k]] - field[v])
            }
            out[v] = sum * h2 / (2 * areas[v])
        }
        return out
    }

    /// The largest diagonal magnitude of the scaled Laplacian, which is what
    /// bounds an explicit diffusion step: a step is stable while
    /// `rate * dt * spectralBound <= 2`. On a well-shaped mesh this sits near 4
    /// (the value a square grid gives); a sliver triangle drives it up, and the
    /// caller answers by taking more, smaller sub-steps.
    var spectralBound: Double {
        let h2 = meanEdgeLength * meanEdgeLength
        guard h2 > 0 else { return 0 }
        var bound = 0.0
        for v in neighbors.indices {
            var sum = 0.0
            for w in weights[v] { sum += Swift.abs(w) }
            bound = Swift.max(bound, sum * h2 / (2 * areas[v]))
        }
        return bound
    }

    /// The mean-curvature normal at each vertex: direction along the surface
    /// normal, magnitude twice the mean curvature. Points outward where the
    /// surface bulges and inward where it dishes, so its dot product with the
    /// vertex normal is a signed measure of how convex the surface is there.
    func meanCurvatureNormals(of positions: [Vector3]) -> [Vector3] {
        var out = [Vector3](repeating: .zero, count: positions.count)
        for v in 0 ..< Swift.min(positions.count, neighbors.count) {
            var sum = Vector3.zero
            let ns = neighbors[v], ws = weights[v]
            for k in ns.indices where ns[k] < positions.count {
                sum += (positions[v] - positions[ns[k]]) * ws[k]
            }
            out[v] = sum * (1 / (2 * areas[v]))
        }
        return out
    }

    private static func cotangent(at apex: Vector3, _ p: Vector3, _ q: Vector3) -> Double {
        let u = p - apex, v = q - apex
        let sine = u.cross(v).length
        guard sine > 1e-18 else { return 0 }
        // Clamped: a needle triangle otherwise contributes a weight so large it
        // swamps every other term in the row.
        return Swift.min(Swift.max(u.dot(v) / sine, -1e4), 1e4)
    }

    private static func accumulate(_ map: inout [[Int: Double]], _ i: Int, _ j: Int, _ w: Double) {
        map[i][j, default: 0] += w
        map[j][i, default: 0] += w
    }
}

/// A triangle as three vertex indices, wound counter-clockwise seen from the
/// outside. The growth surface and the mesh operators both work in these rather
/// than a flat index array, so a corner is named rather than counted.
struct MeshTriangle: Equatable {
    var a: Int
    var b: Int
    var c: Int

    init(_ a: Int, _ b: Int, _ c: Int) {
        self.a = a
        self.b = b
        self.c = c
    }

    /// Whether the triangle uses `vertex` at any corner.
    func contains(_ vertex: Int) -> Bool { a == vertex || b == vertex || c == vertex }

    /// The corner that is neither `i` nor `j`, or `nil` when the triangle does
    /// not use both.
    func opposite(_ i: Int, _ j: Int) -> Int? {
        if (a == i && b == j) || (a == j && b == i) { return c }
        if (b == i && c == j) || (b == j && c == i) { return a }
        if (c == i && a == j) || (c == j && a == i) { return b }
        return nil
    }

    /// The corner indices as an array, in winding order.
    var corners: [Int] { [a, b, c] }

    /// A copy with every mention of `old` replaced by `new`.
    func replacing(_ old: Int, with new: Int) -> MeshTriangle {
        MeshTriangle(a == old ? new : a, b == old ? new : b, c == old ? new : c)
    }

    /// Whether two corners have collapsed onto the same vertex, leaving no area.
    var isDegenerate: Bool { a == b || b == c || c == a }
}

/// A mesh's triangles rewritten against shared vertices.
///
/// Ollin's mesh generators emit flat-shaded geometry: a sphere's triangles each
/// carry their own three corners, so an icosphere that looks like one closed
/// surface is, by index, a few thousand loose triangles. Anything that spreads a
/// value across a surface has to join those corners first or it is working on
/// confetti.
///
/// The tolerance is relative to the mesh's own size rather than absolute,
/// because a generated cap arrives quantized to float precision and an exact
/// comparison leaves its rim unjoined.
struct WeldedMesh {

    /// One position per distinct location, in first-seen order.
    let positions: [Vector3]
    /// The triangles, indexing `positions`, with degenerates dropped.
    let triangles: [MeshTriangle]
    /// For each vertex of the original mesh, its index in `positions`.
    let remap: [Int]

    init(_ mesh: Mesh) {
        var lo = Vector3.zero, hi = Vector3.zero
        if let first = mesh.positions.first {
            lo = first; hi = first
            for p in mesh.positions {
                lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
            }
        }
        let span = hi - lo
        let extent = Swift.max(span.x, Swift.max(span.y, span.z))
        let inverse = 1 / Swift.max(extent * 1e-6, 1e-12)

        var lookup: [Bucket: Int] = [:]
        var mapping = [Int](repeating: 0, count: mesh.positions.count)
        var merged: [Vector3] = []
        for (index, p) in mesh.positions.enumerated() {
            let key = Bucket(x: Int((p.x * inverse).rounded()),
                             y: Int((p.y * inverse).rounded()),
                             z: Int((p.z * inverse).rounded()))
            if let existing = lookup[key] {
                mapping[index] = existing
            } else {
                lookup[key] = merged.count
                mapping[index] = merged.count
                merged.append(p)
            }
        }

        var tris: [MeshTriangle] = []
        tris.reserveCapacity(mesh.indices.count / 3)
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            guard a < mapping.count, b < mapping.count, c < mapping.count else { i += 3; continue }
            let t = MeshTriangle(mapping[a], mapping[b], mapping[c])
            if !t.isDegenerate { tris.append(t) }
            i += 3
        }

        self.positions = merged
        self.triangles = tris
        self.remap = mapping
    }

    private struct Bucket: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }
}

/// An undirected edge, keyed so the same pair always compares and hashes the
/// same way whichever direction it was walked.
struct MeshEdge: Hashable, Comparable {
    let low: Int
    let high: Int

    init(_ i: Int, _ j: Int) {
        low = Swift.min(i, j)
        high = Swift.max(i, j)
    }

    /// The end that is not `vertex` (or `nil` when the edge does not touch it).
    func other(than vertex: Int) -> Int? {
        if vertex == low { return high }
        if vertex == high { return low }
        return nil
    }

    static func < (a: MeshEdge, b: MeshEdge) -> Bool {
        a.low == b.low ? a.high < b.high : a.low < b.low
    }
}
