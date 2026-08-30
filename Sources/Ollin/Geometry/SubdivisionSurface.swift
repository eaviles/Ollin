import Foundation

/// Which refinement rules `Mesh.subdivided(_:levels:)` smooths with.
///
/// Both are subdivision-surface schemes: each level splits every face and
/// nudges every vertex toward a weighted average of its neighborhood, so a
/// coarse cage converges to a smooth limit surface. They differ in the face
/// type they work best on.
public enum SubdivisionScheme: Sendable, Hashable {
    /// The quad-oriented scheme (Catmull-Clark): every face gains a center
    /// point, every edge a midpoint-flavored point, and each level rebuilds
    /// the surface out of quads. The standard "smooth a low-poly cage" look;
    /// a cube becomes the classic rounded blob. Consecutive triangle pairs
    /// that share their first-to-third edge (the pattern Ollin's own
    /// generators emit for grid quads) are treated as the quads they came
    /// from, so a built-in primitive subdivides on its intended topology;
    /// any remaining triangles subdivide as three-sided faces.
    case catmullClark
    /// The triangle scheme (Loop): each triangle splits into four, and both
    /// the split points and the original vertices move by fixed valence-
    /// dependent weights. The right pick for triangle-native geometry: an
    /// icosphere, a marching-cubes surface, a scanned model.
    case loop
}

public extension Mesh {

    /// A smoothed copy of this mesh, refined `levels` times as a subdivision
    /// surface, the standard way to turn a low-poly control cage into a
    /// smooth, organic solid. Coincident vertices are welded first so a
    /// flat-shaded cage (a `box`, a loaded model) rounds as one surface
    /// instead of falling apart into plates.
    ///
    /// ```swift
    /// drawMesh(Mesh.box(size: 1).subdivided(levels: 3))          // the classic rounded cube
    /// drawMesh(Mesh.icosphere().subdivided(.loop, levels: 2))    // smoother still
    /// ```
    ///
    /// Open edges follow the matching B-spline curve rules, so a sheet's rim
    /// smooths along itself instead of shrinking inward, and a corner (a
    /// boundary vertex with a single incident face) holds its position.
    /// Non-manifold edges (used by more than two faces) smooth as if they
    /// were open edges. Each level multiplies the face count by about four;
    /// past two million faces refinement stops early with a note. The result
    /// carries smooth normals and no texture coordinates (a welded, re-knit
    /// surface has no single parameterization to keep), and the base
    /// `material` color carries over. Per-vertex `colors` carry too, refined
    /// by the same masks the positions take, so a painted cage smooths into a
    /// painted surface. Where the input has normals, the
    /// output's orientation follows them, so the smoothed surface lights the
    /// way its cage did regardless of how the source happened to wind.
    ///
    /// - Parameters:
    ///   - scheme: The refinement rules; `.catmullClark` (default) for cage
    ///     smoothing, `.loop` for triangle-native meshes.
    ///   - levels: How many times to refine (0 returns the mesh unchanged).
    func subdivided(_ scheme: SubdivisionScheme = .catmullClark, levels: Int = 1) -> Mesh {
        guard levels > 0, !isEmpty else { return self }
        var control = SubdivisionMesh(self)
        guard !control.faces.isEmpty else { return self }
        if scheme == .catmullClark {
            control.recoverQuads()
            control.mergeCoplanarFaces()
        }
        // The output's normals derive from winding, but a source mesh may wind
        // either way while shading by its own assigned normals (some
        // generators do). Follow the input's normals where it has them, so the
        // smoothed surface lights the way its cage did.
        if SubdivisionMesh.windingDisagreesWithNormals(self) { control.flipFaces() }
        for level in 0..<levels {
            guard control.projectedNextFaceCount <= SubdivisionMesh.maxFaces else {
                print("Ollin: subdivided(\(scheme), levels: \(levels)) stopped after level \(level); the next level would exceed \(SubdivisionMesh.maxFaces) faces.")
                break
            }
            switch scheme {
            case .catmullClark: control.refineCatmullClark()
            case .loop: control.refineLoop()
            }
        }
        if scheme == .loop { control.pushToLoopLimit() }
        return control.mesh(material: material)
    }
}

// MARK: - Internal polygon mesh (welded, face-based)

/// The working form `subdivided` refines: welded shared-vertex positions plus
/// faces as corner-index rings. Everything in here iterates arrays in index
/// order (dictionaries are lookup-only), so a given mesh always refines to
/// byte-identical output.
struct SubdivisionMesh {

    static let maxFaces = 2_000_000

    var points: [Vector3]
    /// Faces as counter-clockwise corner rings (3+ corners each).
    var faces: [[Int]]
    /// Per-point vertex colors as straight RGBA, parallel to `points`, or nil
    /// when the source mesh carried none. Refinement is a linear operator on a
    /// vertex attribute and the masks depend only on `faces`, so a color takes
    /// exactly the weights its position does and arrives smoothed the same way.
    /// A mirror of the position math rather than a fold into it: the position
    /// path is byte-pinned by the snapshot and the five-fold-symmetry test, so
    /// the color pass sits beside it rather than rewriting around it.
    var colors: [SIMD4<Double>]?

    /// Weld the mesh's (often deliberately duplicated, flat-shaded) vertices
    /// into shared topology and keep its triangles as three-corner faces.
    /// Degenerate triangles, the ones the weld collapses (like the seam-cap
    /// slivers at a UV sphere's poles), are dropped here for the pure-triangle
    /// path; `recoverQuads` re-derives faces from the raw pairs instead, so
    /// it can still see a collapsed quad and keep its surviving triangle.
    init(_ mesh: Mesh) {
        let weld = SubdivisionMesh.weld(mesh.positions)
        points = weld.points
        rawTriangles = []
        rawTriangles.reserveCapacity(mesh.indices.count / 3)
        var i = 0
        while i + 2 < mesh.indices.count {
            rawTriangles.append((weld.map[Int(mesh.indices[i])],
                                 weld.map[Int(mesh.indices[i + 1])],
                                 weld.map[Int(mesh.indices[i + 2])]))
            i += 3
        }
        faces = rawTriangles.compactMap { SubdivisionMesh.canonicalFace([$0.0, $0.1, $0.2]) }
        // A welded point takes the color of the first source vertex that claimed
        // it, matching the weld's own first-come identity. Duplicated flat-shaded
        // corners of one seam agree anyway; where they genuinely differ the mesh
        // was painting a hard edge that a smoothed surface cannot keep.
        if mesh.colors.count == mesh.positions.count, !mesh.colors.isEmpty {
            var welded = [SIMD4<Double>](repeating: SIMD4(1, 1, 1, 1), count: points.count)
            var claimed = [Bool](repeating: false, count: points.count)
            for (source, target) in weld.map.enumerated() where !claimed[target] {
                let c = mesh.colors[source]
                welded[target] = SIMD4(c.red, c.green, c.blue, c.alpha)
                claimed[target] = true
            }
            colors = welded
        }
    }

    /// The welded triangles in emission order, kept so `recoverQuads` can see
    /// the original pairing even where the weld degenerated a triangle.
    private var rawTriangles: [(Int, Int, Int)]

    /// Re-derive `faces` by pairing consecutive triangles that share their
    /// first-to-third edge, `(a, b, c), (a, c, d)`, back into the quad
    /// `(a, b, c, d)`. That is exactly the split every Ollin generator emits
    /// for a grid cell, so built-in primitives recover their quad topology;
    /// triangles that don't pair stay triangles. Greedy and sequential, so
    /// the result is deterministic.
    mutating func recoverQuads() {
        var recovered: [[Int]] = []
        recovered.reserveCapacity(rawTriangles.count / 2)
        var i = 0
        while i < rawTriangles.count {
            let t = rawTriangles[i]
            if i + 1 < rawTriangles.count {
                let u = rawTriangles[i + 1]
                if u.0 == t.0 && u.1 == t.2 {
                    if let quad = SubdivisionMesh.canonicalFace([t.0, t.1, t.2, u.2]) {
                        recovered.append(quad)
                    }
                    i += 2
                    continue
                }
            }
            if let tri = SubdivisionMesh.canonicalFace([t.0, t.1, t.2]) {
                recovered.append(tri)
            }
            i += 1
        }
        faces = recovered
    }

    /// Merge each exactly-flat patch of adjacent faces back into the single
    /// polygon it triangulated from, so a tessellated cap (an extruded star's
    /// libtess2 fill, a pentagon fan) subdivides as the n-gon it is. This is
    /// load-bearing for symmetry: a triangulator's arbitrary diagonals give
    /// otherwise-identical corners different valences, and the smoothed arms
    /// of an extruded star come out visibly uneven (the five-fold-symmetry
    /// test pins this). Deliberately conservative: faces join only
    /// when their normals match to ~1e-6 (a curved grid never merges), the
    /// merged boundary must be one simple loop, and a region with interior
    /// vertices (a flat grid someone tessellated on purpose) is left alone.
    mutating func mergeCoplanarFaces() {
        guard faces.count > 1 else { return }
        // Exact-enough face normals; a face the weld degenerated keeps .zero
        // and never merges.
        let normals: [Vector3] = faces.map { face in
            var n = Vector3.zero
            for c in 0..<face.count {
                let p = points[face[c]], q = points[face[(c + 1) % face.count]]
                n = n + Vector3((p.y - q.y) * (p.z + q.z),
                                (p.z - q.z) * (p.x + q.x),
                                (p.x - q.x) * (p.y + q.y))
            }
            return n.lengthSquared > 1e-24 ? n.normalized : .zero
        }
        // Edge -> first two adjacent faces (a third makes the edge unusable).
        var edgeFaces: [EdgeKey: (Int, Int, Int)] = [:]   // (faceA, faceB, count)
        for (f, face) in faces.enumerated() {
            for c in 0..<face.count {
                let key = EdgeKey(face[c], face[(c + 1) % face.count])
                if var entry = edgeFaces[key] {
                    if entry.2 == 1 { entry.1 = f }
                    entry.2 += 1
                    edgeFaces[key] = entry
                } else {
                    edgeFaces[key] = (f, -1, 1)
                }
            }
        }
        func neighbor(_ f: Int, across key: EdgeKey) -> Int? {
            guard let entry = edgeFaces[key], entry.2 == 2 else { return nil }
            let other = entry.0 == f ? entry.1 : entry.0
            return other >= 0 ? other : nil
        }

        var regionOf = [Int](repeating: -1, count: faces.count)
        var merged: [Int: [Int]] = [:]      // representative face -> polygon
        var dropped = [Bool](repeating: false, count: faces.count)
        for seed in 0..<faces.count where regionOf[seed] == -1 {
            let n0 = normals[seed]
            guard n0.lengthSquared > 0.5 else { regionOf[seed] = seed; continue }
            // Grow the exactly-coplanar region from the seed, in face order.
            var region: [Int] = [seed]
            regionOf[seed] = seed
            var cursor = 0
            while cursor < region.count {
                let f = region[cursor]
                cursor += 1
                let face = faces[f]
                for c in 0..<face.count {
                    let key = EdgeKey(face[c], face[(c + 1) % face.count])
                    guard let g = neighbor(f, across: key), regionOf[g] == -1,
                          normals[g].dot(n0) > 1 - 1e-6 else { continue }
                    regionOf[g] = seed
                    region.append(g)
                }
            }
            guard region.count >= 2, let polygon = Self.regionBoundaryPolygon(
                region: region, regionOf: regionOf, seed: seed,
                faces: faces, edgeFaces: edgeFaces) else { continue }
            merged[seed] = polygon
            for f in region where f != seed { dropped[f] = true }
        }
        guard !merged.isEmpty else { return }
        var out: [[Int]] = []
        out.reserveCapacity(faces.count)
        for f in 0..<faces.count {
            if dropped[f] { continue }
            out.append(merged[f] ?? faces[f])
        }
        faces = out
    }

    /// The single simple boundary loop of a merged region, wound the way its
    /// faces are, or `nil` when the region isn't a clean polygon: a vertex
    /// used twice on the rim, more than one loop (a hole), or any region
    /// vertex not on the rim (an interior vertex someone meant to keep).
    private static func regionBoundaryPolygon(
        region: [Int], regionOf: [Int], seed: Int,
        faces: [[Int]], edgeFaces: [EdgeKey: (Int, Int, Int)]
    ) -> [Int]? {
        var successor: [Int: Int] = [:]
        var regionVertices = Set<Int>()
        var boundaryCount = 0
        for f in region {
            let face = faces[f]
            for c in 0..<face.count {
                let u = face[c], v = face[(c + 1) % face.count]
                regionVertices.insert(u)
                guard let entry = edgeFaces[EdgeKey(u, v)] else { continue }
                let interior = entry.2 == 2
                    && entry.1 >= 0
                    && regionOf[entry.0] == seed && regionOf[entry.1] == seed
                if !interior {
                    // A directed rim edge; two outgoing edges from one vertex
                    // means the rim pinches, so give up.
                    guard successor[u] == nil else { return nil }
                    successor[u] = v
                    boundaryCount += 1
                }
            }
        }
        guard boundaryCount >= 3, let start = successor.keys.min() else { return nil }
        var polygon: [Int] = [start]
        var walk = successor[start]
        while let v = walk, v != start, polygon.count <= boundaryCount {
            polygon.append(v)
            walk = successor[v]
        }
        guard walk == start, polygon.count == boundaryCount else { return nil }
        // Every region vertex must sit on the rim, or merging would delete it.
        guard regionVertices.count == polygon.count else { return nil }
        return polygon
    }

    /// Reverse every face's corner order (after any quad recovery, which
    /// reads the original triangle pattern), so winding-derived normals come
    /// out on the side the source mesh shaded.
    mutating func flipFaces() {
        for i in 0..<faces.count { faces[i].reverse() }
    }

    /// Whether the mesh's triangle winding points its geometric normals
    /// against its own assigned normals, summed over every triangle (area-
    /// weighted, so slivers don't decide). A mesh with no normals reports
    /// `false`: nothing to disagree with, its winding is taken as authored.
    static func windingDisagreesWithNormals(_ mesh: Mesh) -> Bool {
        guard mesh.normals.count == mesh.positions.count else { return false }
        var agreement = 0.0
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            i += 3
            let g = (mesh.positions[b] - mesh.positions[a]).cross(mesh.positions[c] - mesh.positions[a])
            agreement += g.dot(mesh.normals[a] + mesh.normals[b] + mesh.normals[c])
        }
        return agreement < 0
    }

    // MARK: Topology shared by both schemes

    private struct EdgeKey: Hashable {
        let a: Int, b: Int
        init(_ u: Int, _ v: Int) { a = Swift.min(u, v); b = Swift.max(u, v) }
    }

    /// Undirected edges in first-encounter order, with the per-face corner to
    /// edge mapping and everything the refinement masks need. Built fresh per
    /// level by iterating faces in index order.
    private struct Topology {
        var edgeEnds: [(Int, Int)] = []
        /// Lookup only, never iterated.
        var edgeIndex: [EdgeKey: Int] = [:]
        var edgeFaceCount: [Int] = []
        /// Up to two adjacent face ids per edge, in encounter order.
        var edgeFaces: [(Int, Int)] = []
        /// Per face, the edge id for each corner's outgoing edge (corner i to
        /// corner i+1).
        var faceEdges: [[Int]] = []
        /// Per vertex: incident-edge count, incident-face count, and how many
        /// of its edges are open (boundary), plus the first two boundary
        /// neighbors, for the crease rule.
        var valence: [Int]
        var faceCount: [Int]
        var boundaryEdgeCount: [Int]
        var boundaryNeighbors: [(Int, Int)]

        init(points: Int, faces: [[Int]]) {
            valence = [Int](repeating: 0, count: points)
            faceCount = [Int](repeating: 0, count: points)
            boundaryEdgeCount = [Int](repeating: 0, count: points)
            boundaryNeighbors = [(Int, Int)](repeating: (-1, -1), count: points)
            faceEdges.reserveCapacity(faces.count)
            for (f, face) in faces.enumerated() {
                var ids: [Int] = []
                ids.reserveCapacity(face.count)
                for c in 0..<face.count {
                    let u = face[c], v = face[(c + 1) % face.count]
                    faceCount[u] += 1
                    let key = EdgeKey(u, v)
                    let id: Int
                    if let existing = edgeIndex[key] {
                        id = existing
                        edgeFaceCount[id] += 1
                        if edgeFaceCount[id] == 2 { edgeFaces[id].1 = f }
                    } else {
                        id = edgeEnds.count
                        edgeIndex[key] = id
                        edgeEnds.append((key.a, key.b))
                        edgeFaceCount.append(1)
                        edgeFaces.append((f, -1))
                        valence[key.a] += 1
                        valence[key.b] += 1
                    }
                    ids.append(id)
                }
                faceEdges.append(ids)
            }
            // An edge not shared by exactly two faces is open (or non-manifold,
            // treated the same). Recorded per endpoint for the crease rule.
            for (id, ends) in edgeEnds.enumerated() where edgeFaceCount[id] != 2 {
                noteBoundary(at: ends.0, neighbor: ends.1)
                noteBoundary(at: ends.1, neighbor: ends.0)
            }
        }

        private mutating func noteBoundary(at v: Int, neighbor: Int) {
            boundaryEdgeCount[v] += 1
            if boundaryNeighbors[v].0 == -1 { boundaryNeighbors[v].0 = neighbor }
            else if boundaryNeighbors[v].1 == -1 { boundaryNeighbors[v].1 = neighbor }
        }

        func isBoundaryEdge(_ id: Int) -> Bool { edgeFaceCount[id] != 2 }

        /// A vertex the refinement holds in place: a corner (one incident
        /// face), a non-manifold pinch (more than two open edges), or a
        /// stray with a single open edge.
        func isPinned(_ v: Int) -> Bool {
            faceCount[v] == 1 || boundaryEdgeCount[v] > 2 || boundaryEdgeCount[v] == 1
        }

        /// A vertex on an open rim with exactly two open edges; the crease
        /// (B-spline curve) rule applies.
        func isCrease(_ v: Int) -> Bool { boundaryEdgeCount[v] == 2 && faceCount[v] > 1 }
    }

    var projectedNextFaceCount: Int {
        faces.reduce(0) { $0 + $1.count }
    }

    // MARK: Catmull-Clark

    /// One Catmull-Clark level over the general polygon mesh: a face point
    /// per face (the corner average), an edge point per edge (endpoint +
    /// adjacent-face-point average, or the midpoint on an open edge), and
    /// every original vertex moved by the valence-weighted vertex rule
    /// `(Q + 2R + (n-3)S) / n`, with `Q` the average of the adjacent face
    /// points and `R` of the incident edge midpoints. Open rims use the
    /// B-spline crease rule `(6v + b1 + b2) / 8`; pinned vertices hold.
    /// Every face with k corners becomes k quads.
    mutating func refineCatmullClark() {
        let topo = Topology(points: points.count, faces: faces)
        let vCount = points.count, fCount = faces.count

        var facePoints = [Vector3](repeating: .zero, count: fCount)
        for (f, face) in faces.enumerated() {
            var sum = Vector3.zero
            for v in face { sum = sum + points[v] }
            facePoints[f] = sum / Double(face.count)
        }

        var edgePoints = [Vector3](repeating: .zero, count: topo.edgeEnds.count)
        for (id, ends) in topo.edgeEnds.enumerated() {
            let mid = (points[ends.0] + points[ends.1]) * 0.5
            if topo.isBoundaryEdge(id) {
                edgePoints[id] = mid
            } else {
                let f = topo.edgeFaces[id]
                edgePoints[id] = (points[ends.0] + points[ends.1] + facePoints[f.0] + facePoints[f.1]) * 0.25
            }
        }

        // Per-vertex sums for Q and R, accumulated in face/edge index order.
        var faceSum = [Vector3](repeating: .zero, count: vCount)
        for (f, face) in faces.enumerated() {
            for v in face { faceSum[v] = faceSum[v] + facePoints[f] }
        }
        var midSum = [Vector3](repeating: .zero, count: vCount)
        for ends in topo.edgeEnds {
            let mid = (points[ends.0] + points[ends.1]) * 0.5
            midSum[ends.0] = midSum[ends.0] + mid
            midSum[ends.1] = midSum[ends.1] + mid
        }

        var vertexPoints = [Vector3](repeating: .zero, count: vCount)
        for v in 0..<vCount {
            if topo.isPinned(v) || topo.valence[v] == 0 {
                vertexPoints[v] = points[v]
            } else if topo.isCrease(v) {
                let b = topo.boundaryNeighbors[v]
                vertexPoints[v] = (points[v] * 6 + points[b.0] + points[b.1]) / 8
            } else {
                let n = Double(topo.valence[v])
                let q = faceSum[v] / Double(topo.faceCount[v])
                let r = midSum[v] / Double(topo.valence[v])
                vertexPoints[v] = (q + r * 2 + points[v] * (n - 3)) / n
            }
        }

        var newPoints = vertexPoints
        newPoints.append(contentsOf: facePoints)     // offset vCount
        newPoints.append(contentsOf: edgePoints)     // offset vCount + fCount
        var newFaces: [[Int]] = []
        newFaces.reserveCapacity(topo.faceEdges.reduce(0) { $0 + $1.count })
        for (f, face) in faces.enumerated() {
            let k = face.count
            let center = vCount + f
            for c in 0..<k {
                let ahead = vCount + fCount + topo.faceEdges[f][c]
                let behind = vCount + fCount + topo.faceEdges[f][(c + k - 1) % k]
                newFaces.append([face[c], ahead, center, behind])
            }
        }
        // Colors take the same three masks, in the same order, so a refined color
        // lands on the vertex its position did.
        if let old = colors {
            var faceColors = [SIMD4<Double>](repeating: .zero, count: fCount)
            for (f, face) in faces.enumerated() {
                var sum = SIMD4<Double>.zero
                for v in face { sum += old[v] }
                faceColors[f] = sum / Double(face.count)
            }
            var edgeColors = [SIMD4<Double>](repeating: .zero, count: topo.edgeEnds.count)
            for (id, ends) in topo.edgeEnds.enumerated() {
                if topo.isBoundaryEdge(id) {
                    edgeColors[id] = (old[ends.0] + old[ends.1]) * 0.5
                } else {
                    let f = topo.edgeFaces[id]
                    edgeColors[id] = (old[ends.0] + old[ends.1] + faceColors[f.0] + faceColors[f.1]) * 0.25
                }
            }
            var faceColorSum = [SIMD4<Double>](repeating: .zero, count: vCount)
            for (f, face) in faces.enumerated() {
                for v in face { faceColorSum[v] += faceColors[f] }
            }
            var midColorSum = [SIMD4<Double>](repeating: .zero, count: vCount)
            for ends in topo.edgeEnds {
                let mid = (old[ends.0] + old[ends.1]) * 0.5
                midColorSum[ends.0] += mid
                midColorSum[ends.1] += mid
            }
            var vertexColors = [SIMD4<Double>](repeating: .zero, count: vCount)
            for v in 0..<vCount {
                if topo.isPinned(v) || topo.valence[v] == 0 {
                    vertexColors[v] = old[v]
                } else if topo.isCrease(v) {
                    let b = topo.boundaryNeighbors[v]
                    vertexColors[v] = (old[v] * 6 + old[b.0] + old[b.1]) / 8
                } else {
                    let n = Double(topo.valence[v])
                    let q = faceColorSum[v] / Double(topo.faceCount[v])
                    let r = midColorSum[v] / Double(topo.valence[v])
                    vertexColors[v] = (q + r * 2 + old[v] * (n - 3)) / n
                }
            }
            var newColors = vertexColors
            newColors.append(contentsOf: faceColors)
            newColors.append(contentsOf: edgeColors)
            colors = newColors
        }
        points = newPoints
        faces = newFaces
    }

    // MARK: Loop

    /// One Loop level over the triangle mesh. Edge (odd) points: interior
    /// edges take `3/8` of each endpoint plus `1/8` of the two opposite
    /// corners; open edges take the midpoint. Original (even) vertices:
    /// interior ones move to `(1 - nβ)v + β Σ neighbors` with Warren's
    /// `β = 3/16` at valence 3 and `3/(8n)` above; open rims use the crease
    /// rule `(6v + b1 + b2) / 8`; pinned vertices hold. Each triangle
    /// splits into four.
    mutating func refineLoop() {
        let topo = Topology(points: points.count, faces: faces)
        let vCount = points.count

        // The two corners opposite each edge, in face-encounter order.
        var opposite = [(Int, Int)](repeating: (-1, -1), count: topo.edgeEnds.count)
        for (f, face) in faces.enumerated() {
            guard face.count == 3 else { continue }
            for c in 0..<3 {
                let id = topo.faceEdges[f][c]
                let far = face[(c + 2) % 3]
                if opposite[id].0 == -1 { opposite[id].0 = far }
                else if opposite[id].1 == -1 { opposite[id].1 = far }
            }
        }

        var edgePoints = [Vector3](repeating: .zero, count: topo.edgeEnds.count)
        for (id, ends) in topo.edgeEnds.enumerated() {
            let a = points[ends.0], b = points[ends.1]
            let far = opposite[id]
            if topo.isBoundaryEdge(id) || far.0 == -1 || far.1 == -1 {
                edgePoints[id] = (a + b) * 0.5
            } else {
                edgePoints[id] = (a + b) * (3.0 / 8.0) + (points[far.0] + points[far.1]) * (1.0 / 8.0)
            }
        }

        var neighborSum = [Vector3](repeating: .zero, count: vCount)
        for ends in topo.edgeEnds {
            neighborSum[ends.0] = neighborSum[ends.0] + points[ends.1]
            neighborSum[ends.1] = neighborSum[ends.1] + points[ends.0]
        }

        var vertexPoints = [Vector3](repeating: .zero, count: vCount)
        for v in 0..<vCount {
            if topo.isPinned(v) || topo.valence[v] == 0 {
                vertexPoints[v] = points[v]
            } else if topo.isCrease(v) {
                let b = topo.boundaryNeighbors[v]
                vertexPoints[v] = (points[v] * 6 + points[b.0] + points[b.1]) / 8
            } else {
                let n = topo.valence[v]
                let beta = SubdivisionMesh.loopBeta(n)
                vertexPoints[v] = points[v] * (1 - Double(n) * beta) + neighborSum[v] * beta
            }
        }

        var newPoints = vertexPoints
        newPoints.append(contentsOf: edgePoints)     // offset vCount
        var newFaces: [[Int]] = []
        newFaces.reserveCapacity(faces.count * 4)
        for (f, face) in faces.enumerated() where face.count == 3 {
            let e01 = vCount + topo.faceEdges[f][0]
            let e12 = vCount + topo.faceEdges[f][1]
            let e20 = vCount + topo.faceEdges[f][2]
            newFaces.append([face[0], e01, e20])
            newFaces.append([face[1], e12, e01])
            newFaces.append([face[2], e20, e12])
            newFaces.append([e01, e12, e20])
        }
        // Colors under the same odd/even masks.
        if let old = colors {
            var edgeColors = [SIMD4<Double>](repeating: .zero, count: topo.edgeEnds.count)
            for (id, ends) in topo.edgeEnds.enumerated() {
                let a = old[ends.0], b = old[ends.1]
                let far = opposite[id]
                if topo.isBoundaryEdge(id) || far.0 == -1 || far.1 == -1 {
                    edgeColors[id] = (a + b) * 0.5
                } else {
                    edgeColors[id] = (a + b) * (3.0 / 8.0) + (old[far.0] + old[far.1]) * (1.0 / 8.0)
                }
            }
            var neighborColorSum = [SIMD4<Double>](repeating: .zero, count: vCount)
            for ends in topo.edgeEnds {
                neighborColorSum[ends.0] += old[ends.1]
                neighborColorSum[ends.1] += old[ends.0]
            }
            var vertexColors = [SIMD4<Double>](repeating: .zero, count: vCount)
            for v in 0..<vCount {
                if topo.isPinned(v) || topo.valence[v] == 0 {
                    vertexColors[v] = old[v]
                } else if topo.isCrease(v) {
                    let b = topo.boundaryNeighbors[v]
                    vertexColors[v] = (old[v] * 6 + old[b.0] + old[b.1]) / 8
                } else {
                    let n = topo.valence[v]
                    let beta = SubdivisionMesh.loopBeta(n)
                    vertexColors[v] = old[v] * (1 - Double(n) * beta) + neighborColorSum[v] * beta
                }
            }
            var newColors = vertexColors
            newColors.append(contentsOf: edgeColors)
            colors = newColors
        }
        points = newPoints
        faces = newFaces
    }

    /// Warren's Loop weight: `3/16` at valence 3, `3/(8n)` otherwise
    /// (equal to the classic `1/16` at the regular valence 6).
    static func loopBeta(_ valence: Int) -> Double {
        valence == 3 ? 3.0 / 16.0 : 3.0 / (8.0 * Double(valence))
    }

    /// Move every vertex of the refined triangle mesh to its position on the
    /// Loop *limit* surface (the surface infinite refinement would reach)
    /// using the limit masks: interior vertices re-weight their one-ring with
    /// `γ = 1 / (n + 3/(8β))`, open-rim vertices take `(3v + b1 + b2) / 5`,
    /// pinned vertices hold. The weights are symmetric over the ring, so no
    /// ring ordering is needed.
    mutating func pushToLoopLimit() {
        let topo = Topology(points: points.count, faces: faces)
        var neighborSum = [Vector3](repeating: .zero, count: points.count)
        for ends in topo.edgeEnds {
            neighborSum[ends.0] = neighborSum[ends.0] + points[ends.1]
            neighborSum[ends.1] = neighborSum[ends.1] + points[ends.0]
        }
        var limit = points
        for v in 0..<points.count {
            if topo.isPinned(v) || topo.valence[v] == 0 { continue }
            if topo.isCrease(v) {
                let b = topo.boundaryNeighbors[v]
                limit[v] = (points[v] * 3 + points[b.0] + points[b.1]) / 5
            } else {
                let n = topo.valence[v]
                let gamma = 1.0 / (Double(n) + 3.0 / (8.0 * SubdivisionMesh.loopBeta(n)))
                limit[v] = points[v] * (1 - Double(n) * gamma) + neighborSum[v] * gamma
            }
        }
        // The limit masks read a value on the limit surface, not a position in
        // particular, so a color takes the same push and stays the color of the
        // point it is attached to.
        if let old = colors {
            var neighborColorSum = [SIMD4<Double>](repeating: .zero, count: old.count)
            for ends in topo.edgeEnds {
                neighborColorSum[ends.0] += old[ends.1]
                neighborColorSum[ends.1] += old[ends.0]
            }
            var limitColors = old
            for v in 0..<old.count {
                if topo.isPinned(v) || topo.valence[v] == 0 { continue }
                if topo.isCrease(v) {
                    let b = topo.boundaryNeighbors[v]
                    limitColors[v] = (old[v] * 3 + old[b.0] + old[b.1]) / 5
                } else {
                    let n = topo.valence[v]
                    let gamma = 1.0 / (Double(n) + 3.0 / (8.0 * SubdivisionMesh.loopBeta(n)))
                    limitColors[v] = old[v] * (1 - Double(n) * gamma) + neighborColorSum[v] * gamma
                }
            }
            colors = limitColors
        }
        points = limit
    }

    // MARK: Output

    /// The refined control mesh as a drawable `Mesh`: quads split along their
    /// first-to-third diagonal (larger faces fan), smooth area-weighted
    /// normals, no texture coordinates.
    func mesh(material: MeshMaterial?) -> Mesh {
        var indices: [UInt32] = []
        indices.reserveCapacity(faces.count * 6)
        for face in faces {
            for c in 1..<(face.count - 1) {
                indices.append(UInt32(face[0]))
                indices.append(UInt32(face[c]))
                indices.append(UInt32(face[c + 1]))
            }
        }
        var out = Mesh(positions: points, indices: indices, material: material)
        if let colors {
            out.colors = colors.map {
                Color(red: min(max($0.x, 0), 1), green: min(max($0.y, 0), 1),
                      blue: min(max($0.z, 0), 1), alpha: min(max($0.w, 0), 1))
            }
        }
        return out.generatingSmoothNormals()
    }

    // MARK: Support

    /// Drop consecutive duplicate corners (wrapping), and reject faces left
    /// with fewer than three corners or with any repeated corner; the weld
    /// can collapse a sliver either way.
    static func canonicalFace(_ corners: [Int]) -> [Int]? {
        var cleaned: [Int] = []
        cleaned.reserveCapacity(corners.count)
        for c in corners where c != cleaned.last {
            cleaned.append(c)
        }
        if cleaned.count > 1 && cleaned.first == cleaned.last { cleaned.removeLast() }
        guard cleaned.count >= 3, Set(cleaned).count == cleaned.count else { return nil }
        return cleaned
    }

    private struct CellKey: Hashable { let x: Int64, y: Int64, z: Int64 }

    /// Weld coincident positions into shared vertices: first-come index
    /// assignment over a hash grid (lookup only, never iterated), matching
    /// within about a millionth of the mesh's extent. That tolerance is
    /// load-bearing: a triangulated cap comes back from the tessellator
    /// Float-quantized (~1e-8 relative) while the walls it must join carry
    /// exact doubles, so a tighter weld leaves every rim edge open and the
    /// caps float free (the extruded-star test pins this).
    static func weld(_ positions: [Vector3]) -> (points: [Vector3], map: [Int]) {
        guard !positions.isEmpty else { return ([], []) }
        var lo = positions[0], hi = positions[0]
        for p in positions {
            lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
            hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
        }
        let eps = Swift.max((hi - lo).length * 1e-6, 1e-12)
        let epsSq = eps * eps
        var cells: [CellKey: [Int]] = [:]
        var points: [Vector3] = []
        var map = [Int](repeating: 0, count: positions.count)
        for (i, p) in positions.enumerated() {
            let cx = Int64((p.x / eps).rounded(.down))
            let cy = Int64((p.y / eps).rounded(.down))
            let cz = Int64((p.z / eps).rounded(.down))
            var found = -1
            search: for dx in Int64(-1)...1 {
                for dy in Int64(-1)...1 {
                    for dz in Int64(-1)...1 {
                        guard let bucket = cells[CellKey(x: cx + dx, y: cy + dy, z: cz + dz)] else { continue }
                        for id in bucket where (points[id] - p).lengthSquared <= epsSq {
                            found = id
                            break search
                        }
                    }
                }
            }
            if found == -1 {
                found = points.count
                points.append(p)
                cells[CellKey(x: cx, y: cy, z: cz), default: []].append(found)
            }
            map[i] = found
        }
        return (points, map)
    }
}
