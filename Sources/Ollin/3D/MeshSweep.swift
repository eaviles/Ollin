import Foundation

// MARK: - Sweeping a profile along a path

public extension Mesh {

    /// A 2D `shape` carried along a 3D `path`: the shape is laid across the
    /// path at every point and the copies are joined into a surface, a
    /// picture frame's molding run round a corner, a rope of any section, a
    /// horn that tapers and turns. The shape's origin rides on the path, its
    /// x along each frame's `normal` and its y along the `binormal`, so a
    /// path running straight along `+z` gives what `extrude(_:depth:)` gives.
    ///
    /// `scale` and `twist` are read at each point with the fraction of the way
    /// along the path by walked length (`0...1`): `scale` multiplies the
    /// shape's size there, and `twist` turns it by that many radians about the
    /// path, counterclockwise as the path comes toward you. Left out, the
    /// shape keeps its size and does not turn, because the path's frames never
    /// twist on their own (see `Curve3D`).
    ///
    /// ```swift
    /// let rail = Curve3D(curveThrough: anchors)
    /// drawMesh(.sweep(Profile.star(points: 4, outerRadius: 0.3, innerRadius: 0.12), along: rail,
    ///                 scale: { 1 - 0.8 * $0 }, twist: { $0 * .pi }))
    /// ```
    ///
    /// Every closed contour of the shape becomes a wall, holes included, and
    /// its walls face out of the solid whichever way the contour was drawn;
    /// an open contour becomes a sheet. A corner of the shape sharper than
    /// 30° keeps a hard edge down the whole sweep, and a gentler one is
    /// smoothed, so a square stays square and a circle reads round.
    /// `capped` closes the two ends of an open path with the shape's fill.
    /// The mesh carries uvs: `u` runs round each contour by walked length and
    /// `v` along the path, and a cap maps the shape's bounds.
    ///
    /// On a closed path the last copy joins the first, so `scale` should come
    /// back to its starting value and `twist` to its start plus a whole number
    /// of turns, or the join shows.
    static func sweep(_ shape: Shape, along path: Curve3D,
                      scale: (Double) -> Double = { _ in 1 },
                      twist: (Double) -> Double = { _ in 0 },
                      capped: Bool = true) -> Mesh {
        let stations = path.points.count
        guard stations >= 2 else { return Mesh(positions: [], indices: []) }
        let contours = SweepProfile.contours(of: shape)
        guard !contours.isEmpty else { return Mesh(positions: [], indices: []) }

        // Each station's frame, fraction, size, and turn; a closed path repeats
        // its first station at the end (fraction 1) so `v` can reach 1.
        let rows = path.isClosed ? stations + 1 : stations
        var placements: [SweepPlacement] = []
        placements.reserveCapacity(rows)
        for row in 0..<rows {
            let i = row % stations
            let fraction: Double
            if row == stations {
                fraction = 1
            } else if path.length > 0 {
                fraction = path.walked[i] / path.length
            } else {
                fraction = Double(i) / Double(stations - 1)
            }
            placements.append(SweepPlacement(frame: path.frames[i], fraction: fraction,
                                             scale: scale(fraction), twist: twist(fraction)))
        }

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2] = []
        var indices: [UInt32] = []

        for contour in contours {
            let columns = contour.columns
            let width = columns.count
            let base = positions.count
            var grid = [Vector3](repeating: .zero, count: rows * width)
            for row in 0..<rows {
                for c in 0..<width {
                    grid[row * width + c] = placements[row].place(columns[c].point)
                }
            }
            for row in 0..<rows {
                let place = placements[row]
                // Neighboring stations for the direction along the path: a
                // closed path wraps over its real stations (the repeated one
                // copies the first), an open one is one-sided at its ends.
                let i = row % stations
                let before: Int, after: Int
                if path.isClosed {
                    before = (i - 1 + stations) % stations
                    after = (i + 1) % stations
                } else {
                    before = max(i - 1, 0)
                    after = min(i + 1, stations - 1)
                }
                for c in 0..<width {
                    let column = columns[c]
                    let along = grid[after * width + c] - grid[before * width + c]
                    let across = place.direction(column.direction)
                    var normal = across.cross(along)
                    if !(normal.lengthSquared > 1e-24) || !normal.lengthSquared.isFinite {
                        // A shape shrunk to nothing at this station: fall back
                        // to the outline's own outward direction there.
                        normal = place.direction(Vector2(column.direction.y, -column.direction.x))
                    }
                    positions.append(grid[row * width + c])
                    normals.append(normal.lengthSquared > 0 ? normal.normalized : place.frame.normal)
                    uvs.append(Vector2(column.u, place.fraction))
                }
            }
            for row in 0..<(rows - 1) {
                for edge in contour.edges {
                    let a = UInt32(base + row * width + edge.from)
                    let b = UInt32(base + row * width + edge.to)
                    let c = UInt32(base + (row + 1) * width + edge.to)
                    let d = UInt32(base + (row + 1) * width + edge.from)
                    indices += [a, b, c, a, c, d]
                }
            }
        }

        if capped && !path.isClosed {
            let closedContours = shape.contours.filter { $0.isClosed && $0.points.count >= 3 }
            let fill = Shape(contours: closedContours, winding: shape.winding).triangulatedFill()
            if fill.count >= 3 {
                let box = SweepProfile.CapMap(fill)
                for (place, outward) in [(placements[0], -1.0), (placements[rows - 1], 1.0)] {
                    let normal = place.frame.tangent * outward
                    var k = 0
                    while k + 2 < fill.count {
                        var tri = [fill[k], fill[k + 1], fill[k + 2]]
                        k += 3
                        // Counterclockwise in the shape's plane faces along the
                        // path, so the far cap wants it and the near one not.
                        let area = (tri[1] - tri[0]).cross(tri[2] - tri[0])
                        if (area > 0) != (outward > 0) { tri.swapAt(1, 2) }
                        let first = UInt32(positions.count)
                        for p in tri {
                            positions.append(place.place(p))
                            normals.append(normal)
                            uvs.append(box.map(p))
                        }
                        indices += [first, first + 1, first + 2]
                    }
                }
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices, uvs: uvs)
    }

    /// A closed outline carried along a 3D `path` (the `Shape` form, for the
    /// `Profile` helpers' point lists).
    static func sweep(_ outline: [Vector2], along path: Curve3D,
                      scale: (Double) -> Double = { _ in 1 },
                      twist: (Double) -> Double = { _ in 0 },
                      capped: Bool = true) -> Mesh {
        sweep(Shape(outline, closed: true), along: path, scale: scale, twist: twist, capped: capped)
    }
}

/// One station of a sweep: where the shape is laid, how big, how turned.
private struct SweepPlacement {
    let frame: Curve3D.Frame
    let fraction: Double
    let cosine: Double
    let sine: Double
    let size: Double

    init(frame: Curve3D.Frame, fraction: Double, scale: Double, twist: Double) {
        self.frame = frame
        self.fraction = fraction
        self.size = scale
        self.cosine = cos(twist)
        self.sine = sin(twist)
    }

    /// The shape's point `p` placed at this station.
    func place(_ p: Vector2) -> Vector3 {
        frame.position + direction(p)
    }

    /// A shape-plane vector `d` sized, turned, and laid across the path here.
    func direction(_ d: Vector2) -> Vector3 {
        let x = (d.x * cosine - d.y * sine) * size
        let y = (d.x * sine + d.y * cosine) * size
        return frame.normal * x + frame.binormal * y
    }
}

/// A shape's contours prepared for sweeping: walls facing out of the solid,
/// corners split where they are sharp, and a `u` for every column.
private enum SweepProfile {

    /// One column of the sweep's grid: a point of the outline, the direction
    /// the outline runs there (for the surface normal), and its `u`.
    struct Column {
        let point: Vector2
        let direction: Vector2
        let u: Double
    }

    struct Prepared {
        var columns: [Column]
        /// Each segment of the outline as the two columns it joins.
        var edges: [(from: Int, to: Int)]
    }

    /// Corners turning more than this (30°) keep a hard edge.
    static let creaseCosine = cos(Double.pi / 6)

    static func contours(of shape: Shape) -> [Prepared] {
        shape.contours.compactMap { contour in
            var points: [Vector2] = []
            for p in contour.points where p.x.isFinite && p.y.isFinite {
                if let last = points.last, last == p { continue }
                points.append(p)
            }
            if contour.isClosed, points.count > 1, points[0] == points[points.count - 1] {
                points.removeLast()
            }
            if contour.isClosed {
                guard points.count >= 3 else { return nil }
                if facesInward(points, in: shape) { points.reverse() }
                return closedColumns(points)
            }
            guard points.count >= 2 else { return nil }
            return openColumns(points)
        }
    }

    /// Whether the right-hand side of the outline's travel is inside the
    /// shape's fill, read across its longest edge; the walls face right, so
    /// such an outline is reversed first.
    static func facesInward(_ points: [Vector2], in shape: Shape) -> Bool {
        var longest = 0, best = -1.0
        for i in points.indices {
            let length = (points[(i + 1) % points.count] - points[i]).lengthSquared
            if length > best { best = length; longest = i }
        }
        let a = points[longest], b = points[(longest + 1) % points.count]
        let d = (b - a).normalized
        let probe = (a + b) * 0.5 + Vector2(d.y, -d.x) * (best.squareRoot() * 1e-4)
        return shape.contains(probe)
    }

    static func closedColumns(_ points: [Vector2]) -> Prepared {
        let m = points.count
        var walked = [0.0]
        for i in 1...m { walked.append(walked[i - 1] + (points[i % m] - points[i - 1]).length) }
        let total = walked[m]
        func u(_ i: Int) -> Double { total > 0 ? walked[i] / total : Double(i) / Double(m) }
        func edge(_ i: Int) -> Vector2 { (points[(i + 1) % m] - points[i]).normalized }
        func sharp(_ i: Int) -> Bool {
            edge((i - 1 + m) % m).dot(edge(i)) < creaseCosine - 1e-9
        }
        func smooth(_ i: Int) -> Vector2 {
            let d = points[(i + 1) % m] - points[(i - 1 + m) % m]
            return d.lengthSquared > 0 ? d.normalized : edge(i)
        }
        var columns: [Column] = []
        var edges: [(from: Int, to: Int)] = []
        // The seam at point 0 opens the walk (its outgoing side) and closes it
        // again at u = 1 (its incoming side), one column each.
        columns.append(Column(point: points[0], direction: sharp(0) ? edge(0) : smooth(0), u: 0))
        for i in 1..<m {
            let incoming = columns.count - 1
            if sharp(i) {
                columns.append(Column(point: points[i], direction: edge(i - 1), u: u(i)))
                edges.append((incoming, columns.count - 1))
                columns.append(Column(point: points[i], direction: edge(i), u: u(i)))
            } else {
                columns.append(Column(point: points[i], direction: smooth(i), u: u(i)))
                edges.append((incoming, columns.count - 1))
            }
        }
        let last = columns.count - 1
        columns.append(Column(point: points[0], direction: sharp(0) ? edge(m - 1) : smooth(0), u: 1))
        edges.append((last, columns.count - 1))
        return Prepared(columns: columns, edges: edges)
    }

    static func openColumns(_ points: [Vector2]) -> Prepared {
        let m = points.count
        var walked = [0.0]
        for i in 1..<m { walked.append(walked[i - 1] + (points[i] - points[i - 1]).length) }
        let total = walked[m - 1]
        func u(_ i: Int) -> Double { total > 0 ? walked[i] / total : Double(i) / Double(m - 1) }
        func edge(_ i: Int) -> Vector2 { (points[i + 1] - points[i]).normalized }
        var columns: [Column] = []
        var edges: [(from: Int, to: Int)] = []
        for i in 0..<m {
            if i == 0 {
                columns.append(Column(point: points[0], direction: edge(0), u: 0))
                continue
            }
            let incoming = columns.count - 1
            if i == m - 1 {
                columns.append(Column(point: points[i], direction: edge(i - 1), u: 1))
                edges.append((incoming, columns.count - 1))
            } else if edge(i - 1).dot(edge(i)) < creaseCosine - 1e-9 {
                columns.append(Column(point: points[i], direction: edge(i - 1), u: u(i)))
                edges.append((incoming, columns.count - 1))
                columns.append(Column(point: points[i], direction: edge(i), u: u(i)))
            } else {
                let d = points[i + 1] - points[i - 1]
                columns.append(Column(point: points[i], direction: d.normalized, u: u(i)))
                edges.append((incoming, columns.count - 1))
            }
        }
        return Prepared(columns: columns, edges: edges)
    }

    /// The box a cap's uvs map: the bounds of `points`, read as `0...1`.
    struct CapMap {
        let low: Vector2
        let size: Vector2

        init(_ points: [Vector2]) {
            var lo = points[0], hi = points[0]
            for p in points {
                lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
                hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
            }
            low = lo
            size = hi - lo
        }

        func map(_ p: Vector2) -> Vector2 {
            Vector2(size.x > 0 ? (p.x - low.x) / size.x : 0, size.y > 0 ? (p.y - low.y) / size.y : 0)
        }
    }
}

// MARK: - A strip between two lines

public extension Mesh {

    /// A ribbon between two lines in space: rung `i` joins `first[i]` to
    /// `second[i]`, and each rung is joined to the next with two triangles.
    /// It is a loft between two rails, the surface a moving segment sweeps,
    /// the band a pair of hands traces through the air.
    ///
    /// `colors`, one per rung, paints both ends of each rung (the mesh's
    /// vertex colors, which multiply the `fill`); any other count is ignored.
    /// The uvs run `u` from 0 at the first rung to 1 at the last, by rung
    /// rather than by distance, so rungs spaced evenly (a `Pace` hands out
    /// even spacing) lay a texture evenly, and `v` from 0 on `first` to 1 on
    /// `second`. The normals come from the strip itself: at each end of a
    /// rung, the direction its line runs crossed with the rung, so a ribbon
    /// that twists shades with its twist. The front is the side from which
    /// `first` runs left to right beneath `second`.
    ///
    /// `closed` joins the last rung back to the first (the closing rung is
    /// the first one again, so `u` can reach 1). When the two lines have
    /// different counts, the one with more points sets the rungs, and each
    /// rung meets the other line at the same fraction of its walked length;
    /// a line of one point makes a fan.
    ///
    /// ```swift
    /// let pace = Pace(byAreaBetween: lower, and: upper, period: .tau)
    /// let ts = (0..<240).map { pace.parameter(at: Double($0) / 240) }
    /// drawMesh(.strip(between: ts.map(lower), and: ts.map(upper),
    ///                 colors: ts.map { Color(hue: $0 / .tau, saturation: 0.7, brightness: 1) },
    ///                 closed: true))
    /// ```
    static func strip(between first: [Vector3], and second: [Vector3],
                      colors: [Color] = [], closed: Bool = false) -> Mesh {
        guard !first.isEmpty, !second.isEmpty else { return Mesh(positions: [], indices: []) }
        var a = first, b = second
        if a.count < b.count {
            a = StripRails.resampled(a, atFractionsOf: b, closed: closed)
        } else if b.count < a.count {
            b = StripRails.resampled(b, atFractionsOf: a, closed: closed)
        }
        let n = a.count
        guard n >= 2 else { return Mesh(positions: [], indices: []) }
        let rows = closed ? n + 1 : n
        let rungColors = colors.count == n

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2] = []
        var vertexColors: [Color] = []
        positions.reserveCapacity(rows * 2)
        normals.reserveCapacity(rows * 2)
        uvs.reserveCapacity(rows * 2)
        func along(_ line: [Vector3], _ i: Int) -> Vector3 {
            if closed { return line[(i + 1) % n] - line[(i - 1 + n) % n] }
            return line[min(i + 1, n - 1)] - line[max(i - 1, 0)]
        }
        for row in 0..<rows {
            let i = row % n
            let rung = b[i] - a[i]
            let u = Double(row) / Double(rows - 1)
            positions.append(a[i]); positions.append(b[i])
            normals.append(along(a, i).cross(rung)); normals.append(along(b, i).cross(rung))
            uvs.append(Vector2(u, 0)); uvs.append(Vector2(u, 1))
            if rungColors { vertexColors.append(colors[i]); vertexColors.append(colors[i]) }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((rows - 1) * 6)
        for row in 0..<(rows - 1) {
            let a0 = UInt32(row * 2), b0 = a0 + 1, a1 = a0 + 2, b1 = a0 + 3
            indices += [a0, a1, b1, a0, b1, b0]
        }
        // A rung of no width, or a line standing still, has no direction to
        // cross: take the triangles' own facing there instead.
        if normals.contains(where: { !($0.lengthSquared > 1e-24) || !$0.lengthSquared.isFinite }) {
            var faces = [Vector3](repeating: .zero, count: positions.count)
            var k = 0
            while k + 2 < indices.count {
                let i0 = Int(indices[k]), i1 = Int(indices[k + 1]), i2 = Int(indices[k + 2])
                let f = (positions[i1] - positions[i0]).cross(positions[i2] - positions[i0])
                faces[i0] += f; faces[i1] += f; faces[i2] += f
                k += 3
            }
            for v in normals.indices where !(normals[v].lengthSquared > 1e-24) || !normals[v].lengthSquared.isFinite {
                normals[v] = faces[v]
            }
        }
        normals = normals.map { $0.lengthSquared > 0 && $0.lengthSquared.isFinite ? $0.normalized : .unitZ }
        return Mesh(positions: positions, normals: normals, indices: indices, uvs: uvs, colors: vertexColors)
    }
}

private enum StripRails {
    /// `line` read at the walked-length fractions of `guide`'s points.
    static func resampled(_ line: [Vector3], atFractionsOf guide: [Vector3], closed: Bool) -> [Vector3] {
        guard line.count >= 2 else { return [Vector3](repeating: line[0], count: guide.count) }
        let rail = Curve3D(line, closed: closed)
        var walked = [0.0]
        for i in 1..<guide.count { walked.append(walked[i - 1] + (guide[i] - guide[i - 1]).length) }
        var total = walked[guide.count - 1]
        if closed { total += (guide[0] - guide[guide.count - 1]).length }
        return walked.enumerated().map { i, w in
            rail.point(at: total > 0 ? w / total : Double(i) / Double(guide.count - 1))
        }
    }
}
