import Foundation
import simd

/// A scene seen from a camera and written down as line work, with everything
/// the surface hides taken out.
///
/// What comes back is ordinary 2D line work in canvas points, so a sketch draws
/// it with `drawPolyline` and everything that follows from that follows for
/// free: a pen plotter reaches it through [SVG](../Output/Export.md) or
/// [G-code](../Output/GCode.md), a laser through [DXF](../Output/DXF.md), and
/// a stroke style, a wobble, or a hand-drawn brush can be put on it the way it
/// can on any other path. That is the whole reason this exists: the lit,
/// shaded, GPU-drawn mesh is a picture, and a picture is not a line to follow.
///
/// ```swift
/// camera(Camera3D(eye: Vector3(3, 2, 4), target: .zero))
/// stroke(.black)
/// for line in lineDrawing(of: [.box(size: 2), .sphere().transformed(by: MeshInstance(position: Vector3(0, 2, 0)))]) {
///     drawPolyline(line.points, closed: line.isClosed)
/// }
/// ```
///
/// Which edges are drawn is the other half of a line drawing. Three kinds are:
/// the **silhouette**, where the surface turns away from the camera; a
/// **crease**, where two faces meet at more than `creaseAngle`; and a
/// **boundary**, where a surface simply ends. Everything else, the tessellation
/// inside a smooth surface, is left out, which is what separates a drawing from
/// a wireframe. A `creaseAngle` of 0 draws every edge, which is the wireframe.
public struct LineDrawing: Sendable {

    /// The visible line work, in canvas points, joined into as few paths as the
    /// edges allow so a pen lifts as rarely as it can.
    public var paths: [Contour]

    /// The rest of the same edges: the stretches something covers. Drawing
    /// these faintly, or as a dashed line, is the draughtsman's way of showing
    /// what is behind, and drawing them at all is the difference between a
    /// drawing and a wireframe.
    public var hidden: [Contour]

    /// The line work of `meshes` as `camera` sees it on a canvas of `size`,
    /// with what the surface hides taken out.
    ///
    /// Every mesh is in world coordinates and every one of them occludes every
    /// other, which is why they are drawn together rather than one call each.
    /// `creaseAngle` is the angle two faces must meet at, in radians, before the
    /// edge between them is drawn; `spacing` is how far apart, in canvas points,
    /// an edge is tested for whether it is hidden, so a smaller spacing catches
    /// a narrower gap and costs more. Whichever spacing is set, the ends of a
    /// visible stretch are found to a fraction of a point.
    ///
    /// Two things it does not do. Geometry crossing the plane the camera stands
    /// on is cut off there rather than drawn, since it has no place on the page.
    /// And a triangle straddling that plane does not occlude, which is a hole in
    /// the drawing only when something is half behind the camera.
    public init(of meshes: [Mesh], camera: Camera3D, size: Vector2,
                creaseAngle: Double = .pi / 6, spacing: Double = 2) {
        let both = LineDrawing.trace(meshes: meshes, camera: camera, size: size,
                                     creaseAngle: creaseAngle, spacing: spacing)
        paths = both.seen
        hidden = both.covered
    }
}

// MARK: - The work
extension LineDrawing {

    /// Where a world point lands on a canvas of `size` through `camera`, or nil
    /// if it is behind it. The same mapping the drawing itself uses.
    static func canvasPoint(of point: Vector3, camera: Camera3D, size: Vector2) -> Vector2? {
        guard size.x > 0, size.y > 0 else { return nil }
        let clip = camera.viewProjectionMatrix(aspect: size.x / size.y) * SIMD4<Float>(point.simd3, 1)
        guard clip.w > 1e-6 else { return nil }
        return Vector2((Double(clip.x / clip.w) + 1) / 2 * size.x,
                       (1 - Double(clip.y / clip.w)) / 2 * size.y)
    }
}

extension LineDrawing {

    /// One triangle after projection: the screen corners, the view depths, and
    /// whether the whole of it is in front of the camera.
    private struct Face {
        var a: Int, b: Int, c: Int
        var normal: Vector3
        /// Twice the signed area on screen: its sign is which way the face is
        /// turned, so two faces of opposite sign share a silhouette edge.
        var turn: Double
        var whole: Bool
        var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0
    }

    private static func trace(meshes: [Mesh], camera: Camera3D, size: Vector2,
                              creaseAngle: Double, spacing: Double)
        -> (seen: [Contour], covered: [Contour]) {
        guard size.x > 1, size.y > 1 else { return ([], []) }
        var positions: [Vector3] = []
        var faces: [Face] = []
        for mesh in meshes {
            let base = positions.count
            positions.append(contentsOf: mesh.positions)
            var index = 0
            while index + 2 < mesh.indices.count {
                let a = base + Int(mesh.indices[index])
                let b = base + Int(mesh.indices[index + 1])
                let c = base + Int(mesh.indices[index + 2])
                index += 3
                guard a < positions.count, b < positions.count, c < positions.count else { continue }
                faces.append(Face(a: a, b: b, c: c, normal: .zero, turn: 0, whole: false))
            }
        }
        guard !faces.isEmpty else { return ([], []) }

        // Every vertex through the camera: where it lands on the canvas, and how
        // far down the camera's axis it sits, which is the depth things are
        // sorted by (and the one a perspective divide is taken against).
        let aspect = size.x / size.y
        let view = camera.viewMatrix
        let clipMatrix = camera.projectionMatrix(aspect: aspect) * view
        let perspective: Bool
        if case .orthographic = camera.projection { perspective = false } else { perspective = true }
        var screen = [Vector2](repeating: .zero, count: positions.count)
        var depth = [Double](repeating: 0, count: positions.count)
        var ahead = [Bool](repeating: false, count: positions.count)
        for (index, point) in positions.enumerated() {
            let p = SIMD4<Float>(point.simd3, 1)
            let camera = view * p
            depth[index] = Double(-camera.z)
            let clip = clipMatrix * p
            let w = perspective ? Double(clip.w) : 1
            guard w > 1e-6 else { continue }
            ahead[index] = true
            screen[index] = Vector2((Double(clip.x) / w + 1) / 2 * size.x,
                                    (1 - Double(clip.y) / w) / 2 * size.y)
        }

        // Each face's geometric normal, its turn on screen, and its own box, so
        // the occlusion test can skip most of them.
        // A lat-long sphere's poles are rows of triangles with no area at all,
        // and the direction of one of those is whatever the arithmetic makes of
        // a cross product of nothing: left in, they scribble over the pole.
        var solid = [Bool](repeating: true, count: faces.count)
        for i in faces.indices {
            let face = faces[i]
            let pa = positions[face.a], pb = positions[face.b], pc = positions[face.c]
            let cross = (pb - pa).cross(pc - pa)
            let scale = max((pb - pa).length * (pc - pa).length, 1e-30)
            solid[i] = cross.length > scale * 1e-6
            faces[i].normal = solid[i] ? cross.normalized : .zero
            faces[i].whole = solid[i] && ahead[face.a] && ahead[face.b] && ahead[face.c]
            guard faces[i].whole else { continue }
            let sa = screen[face.a], sb = screen[face.b], sc = screen[face.c]
            faces[i].turn = (sb.x - sa.x) * (sc.y - sa.y) - (sc.x - sa.x) * (sb.y - sa.y)
            faces[i].minX = min(sa.x, sb.x, sc.x)
            faces[i].maxX = max(sa.x, sb.x, sc.x)
            faces[i].minY = min(sa.y, sb.y, sc.y)
            faces[i].maxY = max(sa.y, sb.y, sc.y)
        }

        let welded = weld(positions)
        let candidates = edges(faces: faces, solid: solid, welded: welded, creaseAngle: creaseAngle)
        guard !candidates.isEmpty else { return ([], []) }
        let grid = Grid(faces: faces, screen: screen)

        // Every candidate edge, cut into the stretches that can be seen and the
        // stretches something covers.
        var segments: [(Vector2, Vector2)] = []
        var covered: [(Vector2, Vector2)] = []
        for edge in candidates {
            let a = positions[edge.0], b = positions[edge.1]
            guard let piece = clipToCamera(a: a, b: b, depthA: depth[edge.0], depthB: depth[edge.1],
                                           perspective: perspective, near: camera.near) else { continue }
            visible(from: piece.0, to: piece.1, spacing: spacing,
                    faces: faces, positions: positions, screen: screen, depth: depth,
                    grid: grid, view: view, clip: clipMatrix, size: size,
                    perspective: perspective, into: &segments, covered: &covered)
        }
        return (chain(segments), chain(covered))
    }

    /// Which vertices are the same point: a mesh drawn with hard edges holds a
    /// copy of a corner per face, and without this every edge would look like a
    /// boundary and be drawn.
    private static func weld(_ positions: [Vector3]) -> [Int] {
        var low = Vector3(.infinity, .infinity, .infinity)
        var high = Vector3(-.infinity, -.infinity, -.infinity)
        for p in positions {
            low = Vector3(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
            high = Vector3(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
        }
        let span = max((high - low).length, 1e-9)
        let grain = span * 1e-6
        var seen: [SIMD3<Int64>: Int] = [:]
        seen.reserveCapacity(positions.count)
        var welded = [Int](repeating: 0, count: positions.count)
        for (index, p) in positions.enumerated() {
            let key = SIMD3<Int64>(Int64((p.x / grain).rounded()),
                                   Int64((p.y / grain).rounded()),
                                   Int64((p.z / grain).rounded()))
            if let first = seen[key] {
                welded[index] = first
            } else {
                seen[key] = index
                welded[index] = index
            }
        }
        return welded
    }

    /// The edges worth drawing: a boundary, a silhouette, or a crease.
    private static func edges(faces: [Face], solid: [Bool], welded: [Int],
                              creaseAngle: Double) -> [(Int, Int)] {
        struct Neighbors { var first: Int; var second: Int? }
        var shared: [SIMD2<Int32>: Neighbors] = [:]
        shared.reserveCapacity(faces.count * 3)
        var order: [(SIMD2<Int32>, Int, Int)] = []
        order.reserveCapacity(faces.count * 3)
        for (index, face) in faces.enumerated() where solid[index] {
            for (u, v) in [(face.a, face.b), (face.b, face.c), (face.c, face.a)] {
                let wu = welded[u], wv = welded[v]
                guard wu != wv else { continue }
                let key = SIMD2<Int32>(Int32(min(wu, wv)), Int32(max(wu, wv)))
                if var already = shared[key] {
                    if already.second == nil { already.second = index }
                    shared[key] = already
                } else {
                    shared[key] = Neighbors(first: index, second: nil)
                    order.append((key, u, v))
                }
            }
        }

        var drawn: [(Int, Int)] = []
        let creaseLimit = cos(min(max(creaseAngle, 0), .pi))
        for (key, u, v) in order {
            guard let neighbors = shared[key] else { continue }
            let first = faces[neighbors.first]
            guard let secondIndex = neighbors.second else {
                drawn.append((u, v))                       // a boundary: the surface ends
                continue
            }
            let second = faces[secondIndex]
            if !first.whole || !second.whole {
                drawn.append((u, v))                       // nothing to compare: keep it
                continue
            }
            if (first.turn >= 0) != (second.turn >= 0) {
                drawn.append((u, v))                       // a silhouette: the surface turns away
                continue
            }
            if creaseAngle <= 0 || first.normal.dot(second.normal) < creaseLimit {
                drawn.append((u, v))                       // a crease: the faces meet at an angle
            }
        }
        return drawn
    }

    /// The part of an edge that is in front of the camera, cut at the plane the
    /// camera stands on rather than dragged around behind it.
    private static func clipToCamera(a: Vector3, b: Vector3, depthA: Double, depthB: Double,
                                     perspective: Bool, near: Double) -> (Vector3, Vector3)? {
        guard perspective else { return (a, b) }
        // Cut at the camera's own near plane rather than at its eye: a point at
        // the eye projects nowhere at all, while one on the near plane lands on
        // the page where the frustum says it should.
        let front = max(near, 1e-4)
        let aheadA = depthA > front, aheadB = depthB > front
        if aheadA && aheadB { return (a, b) }
        if !aheadA && !aheadB { return nil }
        let t = (front - depthA) / (depthB - depthA)
        let cut = a + (b - a) * t
        return aheadA ? (a, cut) : (cut, b)
    }

    /// A face's own screen box, bucketed, so a point is tested against the few
    /// faces that could cover it rather than all of them.
    private struct Grid {
        var origin = Vector2.zero
        var cell = 48.0
        var columns = 1, rows = 1
        var buckets: [[Int]] = []

        init(faces: [Face], screen: [Vector2]) {
            var low = Vector2(.infinity, .infinity), high = Vector2(-.infinity, -.infinity)
            for face in faces where face.whole {
                low = Vector2(min(low.x, face.minX), min(low.y, face.minY))
                high = Vector2(max(high.x, face.maxX), max(high.y, face.maxY))
            }
            guard low.x.isFinite, high.x > low.x, high.y > low.y else { buckets = [[]]; return }
            origin = low
            // A cell an inch or so across, and never so many that the grid
            // itself costs more than the tests it saves.
            let across = max(high.x - low.x, high.y - low.y)
            cell = max(48, across / 256)
            columns = max(1, Int((high.x - low.x) / cell) + 1)
            rows = max(1, Int((high.y - low.y) / cell) + 1)
            buckets = [[Int]](repeating: [], count: columns * rows)
            for (index, face) in faces.enumerated() where face.whole {
                let x0 = column(face.minX), x1 = column(face.maxX)
                let y0 = row(face.minY), y1 = row(face.maxY)
                for y in y0...y1 {
                    for x in x0...x1 { buckets[y * columns + x].append(index) }
                }
            }
        }

        func column(_ x: Double) -> Int { min(max(Int((x - origin.x) / cell), 0), columns - 1) }
        func row(_ y: Double) -> Int { min(max(Int((y - origin.y) / cell), 0), rows - 1) }

        func faces(at point: Vector2) -> [Int] {
            guard !buckets.isEmpty else { return [] }
            return buckets[row(point.y) * columns + column(point.x)]
        }
    }

    /// Whether anything covers this point nearer than `distance`.
    private static func hidden(at point: Vector2, distance: Double, faces: [Face],
                              screen: [Vector2], depth: [Double], grid: Grid,
                              perspective: Bool) -> Bool {
        // A point on an edge sits on its own faces, so a face has to be nearer
        // by a share of the distance before it counts as covering it.
        let bias = max(distance * 1e-3, 1e-6)
        for index in grid.faces(at: point) {
            let face = faces[index]
            guard point.x >= face.minX, point.x <= face.maxX,
                  point.y >= face.minY, point.y <= face.maxY else { continue }
            let a = screen[face.a], b = screen[face.b], c = screen[face.c]
            let area = (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
            guard abs(area) > 1e-12 else { continue }
            let u = ((b.x - point.x) * (c.y - point.y) - (c.x - point.x) * (b.y - point.y)) / area
            let v = ((c.x - point.x) * (a.y - point.y) - (a.x - point.x) * (c.y - point.y)) / area
            let w = 1 - u - v
            guard u >= 0, v >= 0, w >= 0 else { continue }
            let da = depth[face.a], db = depth[face.b], dc = depth[face.c]
            // Under perspective what interpolates evenly across the screen is
            // one over the depth, not the depth.
            var covering: Double
            if perspective {
                let reciprocal = u / max(da, 1e-9) + v / max(db, 1e-9) + w / max(dc, 1e-9)
                guard reciprocal > 1e-12 else { continue }
                covering = 1 / reciprocal
            } else {
                covering = u * da + v * db + w * dc
            }
            if covering < distance - bias { return true }
        }
        return false
    }

    /// One edge, cut into the stretches of it that can be seen. The edge is
    /// walked at `spacing` and each change from seen to hidden is then pinned
    /// down by halving, so the end of a stretch lands where it belongs however
    /// coarse the walk was.
    private static func visible(from a: Vector3, to b: Vector3, spacing: Double,
                                faces: [Face], positions: [Vector3], screen: [Vector2],
                                depth: [Double], grid: Grid, view: simd_float4x4,
                                clip: simd_float4x4, size: Vector2, perspective: Bool,
                                into segments: inout [(Vector2, Vector2)],
                                covered: inout [(Vector2, Vector2)]) {
        /// Where a point along the edge lands, and how far away it is.
        func place(_ t: Double) -> (Vector2, Double)? {
            let p = a + (b - a) * t
            let point = SIMD4<Float>(p.simd3, 1)
            let distance = Double(-(view * point).z)
            let projected = clip * point
            let w = perspective ? Double(projected.w) : 1
            guard w > 1e-6 else { return nil }
            return (Vector2((Double(projected.x) / w + 1) / 2 * size.x,
                            (1 - Double(projected.y) / w) / 2 * size.y), distance)
        }
        func seen(_ t: Double) -> Bool {
            guard let (point, distance) = place(t) else { return false }
            return !hidden(at: point, distance: distance, faces: faces,
                           screen: screen, depth: depth, grid: grid, perspective: perspective)
        }
        guard let start = place(0), let end = place(1) else { return }
        // A stretch shorter than a point is not line work. It is the width of
        // the tolerance the depth test needs, which is what a hidden edge shows
        // of itself where it runs into the silhouette it ends on.
        let shortest = 1.0
        let length = (end.0 - start.0).length
        let steps = max(1, min(Int((length / max(spacing, 0.25)).rounded(.up)), 4096))

        /// The t between a seen sample and a hidden one, to a fraction of a point.
        func between(_ lit: Double, _ dark: Double) -> Double {
            var lit = lit, dark = dark
            for _ in 0..<8 {
                let middle = (lit + dark) / 2
                if seen(middle) { lit = middle } else { dark = middle }
            }
            return lit
        }

        /// One stretch of the edge, onto whichever side it belongs to.
        func keep(from: Double, to: Double, lit: Bool) {
            guard let p = place(from), let q = place(to),
                  (q.0 - p.0).length > shortest else { return }
            if lit { segments.append((p.0, q.0)) } else { covered.append((p.0, q.0)) }
        }
        let litAtStart = seen(0)
        var runStart = 0.0
        var running = litAtStart
        var previous = 0.0
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let lit = seen(t)
            if lit != running {
                let turn = lit ? between(t, previous) : between(previous, t)
                keep(from: runStart, to: turn, lit: running)
                runStart = turn
                running = lit
            }
            previous = t
        }
        keep(from: runStart, to: 1, lit: running)
    }

    /// The segments joined end to end into as few paths as they allow, so a pen
    /// draws a whole silhouette in one go rather than edge by edge.
    private static func chain(_ segments: [(Vector2, Vector2)]) -> [Contour] {
        guard !segments.isEmpty else { return [] }
        let grain = 0.05
        func key(_ p: Vector2) -> SIMD2<Int64> {
            SIMD2<Int64>(Int64((p.x / grain).rounded()), Int64((p.y / grain).rounded()))
        }
        var ends: [SIMD2<Int64>: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            ends[key(segment.0), default: []].append(index)
            ends[key(segment.1), default: []].append(index)
        }
        var used = [Bool](repeating: false, count: segments.count)

        /// The unused segment that carries on from here, taking the straightest
        /// one where several meet, so a pen goes round an outline rather than
        /// turning up whatever spoke it finds first.
        func next(from point: Vector2, heading: Vector2, without index: Int) -> Int? {
            let waiting = (ends[key(point)] ?? []).filter { $0 != index && !used[$0] }
            guard !waiting.isEmpty else { return nil }
            var best = waiting[0], straightest = -Double.infinity
            for candidate in waiting {
                let segment = segments[candidate]
                let far = (segment.0 - point).length < grain ? segment.1 : segment.0
                let step = far - point
                guard step.length > 1e-9 else { continue }
                let along = step.normalized.dot(heading)
                if along > straightest { straightest = along; best = candidate }
            }
            return best
        }

        var paths: [Contour] = []
        for start in segments.indices where !used[start] {
            used[start] = true
            var points = [segments[start].0, segments[start].1]
            var index = start
            while true {
                let end = points[points.count - 1]
                let heading = (end - points[points.count - 2]).normalized
                guard let step = next(from: end, heading: heading, without: index) else { break }
                used[step] = true
                let segment = segments[step]
                points.append((segment.0 - end).length < grain ? segment.1 : segment.0)
                index = step
            }
            index = start
            while true {
                let end = points[0]
                let heading = (end - points[1]).normalized
                guard let step = next(from: end, heading: heading, without: index) else { break }
                used[step] = true
                let segment = segments[step]
                points.insert((segment.1 - end).length < grain ? segment.0 : segment.1, at: 0)
                index = step
            }
            let closed = points.count > 2 && (points[0] - points[points.count - 1]).length < grain
            paths.append(Contour(closed ? Array(points.dropLast()) : points, closed: closed))
        }
        return paths
    }
}

public extension Mesh {

    /// This mesh with a placement applied to every point of it, so several
    /// meshes can be put where they belong and handed to something that takes
    /// them all at once, [`LineDrawing`](../3D/LineDrawing.md) among them.
    func transformed(by placement: MeshInstance) -> Mesh {
        transformed(by: placement.matrix)
    }

    /// This mesh with a matrix applied to every point of it. Normals go through
    /// the inverse transpose, so a squashed mesh still lights correctly.
    func transformed(by matrix: simd_float4x4) -> Mesh {
        var moved = self
        moved.positions = positions.map { matrix.transforming($0) }
        if !normals.isEmpty {
            let direction = matrix.inverse.transpose
            moved.normals = normals.map { normal in
                let n = direction * SIMD4<Float>(normal.simd3, 0)
                return Vector3(Double(n.x), Double(n.y), Double(n.z)).normalized
            }
        }
        return moved
    }
}
