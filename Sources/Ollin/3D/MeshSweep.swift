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
    ///
    /// A sweep is a loft of one section: to change the shape on the way, see
    /// `loft(_:along:at:smoothed:scale:twist:capped:)`.
    static func sweep(_ shape: Shape, along path: Curve3D,
                      scale: (Double) -> Double = { _ in 1 },
                      twist: (Double) -> Double = { _ in 0 },
                      capped: Bool = true) -> Mesh {
        SweepBuilder.loft([shape], along: path, stations: [0], smoothed: false,
                          scale: scale, twist: twist, capped: capped)
    }

    /// A closed outline carried along a 3D `path` (the `Shape` form, for the
    /// `Profile` helpers' point lists).
    static func sweep(_ outline: [Vector2], along path: Curve3D,
                      scale: (Double) -> Double = { _ in 1 },
                      twist: (Double) -> Double = { _ in 0 },
                      capped: Bool = true) -> Mesh {
        sweep(Shape(outline, closed: true), along: path, scale: scale, twist: twist, capped: capped)
    }

    /// A surface through several 2D `sections` laid across a 3D `path`, one
    /// after another: a bottle that runs from a square foot to a round neck,
    /// a hull from its ribs, a horn whose section changes on the way. Each
    /// section sits at its fraction of the path's walked length in `at`
    /// (`0...1`; left out, the sections are spaced evenly from the start to
    /// the end, or round a closed path), placed in the path's frame the way
    /// `sweep(_:along:scale:twist:capped:)` places one shape, and the surface
    /// between two sections blends one into the next.
    ///
    /// ```swift
    /// let spine = Curve3D([Vector3(0, -1, 0), Vector3(0, 1, 0)])
    /// drawMesh(.loft([Shape(Profile.rectangle(width: 0.8, height: 0.8)),
    ///                 Shape(Profile.ellipse(radiusX: 0.5, radiusY: 0.5)),
    ///                 Shape(Profile.ellipse(radiusX: 0.15, radiusY: 0.15))],
    ///                along: spine, at: [0, 0.5, 1]))
    /// ```
    ///
    /// Every section is laid exactly where it was asked for, its own corners
    /// and all, and the outlines between are blends of their neighbors. The
    /// sections' outlines are matched point for point by the fraction of
    /// their length, every corner of every section kept as a point on all of
    /// them, and each closed outline's seam is turned to where it sits
    /// nearest the section before it, so the surface does not twist on its
    /// own. `smoothed` (the default) runs the surface as a smooth curve
    /// through three or more sections; off, it runs straight from each
    /// section to the next, like planks over ribs. Between two sections the
    /// blend is straight either way, and a section that is the halfway blend
    /// of its neighbors changes nothing.
    ///
    /// The walls follow the sweep's rules: a closed contour becomes a wall
    /// facing out and an open one a sheet; a corner sharper than 30° on any
    /// section keeps a hard edge down the whole loft, which softens where the
    /// other sections round it off; `u` runs round each outline by walked
    /// length and `v` along the path; `scale` and `twist` are read at the
    /// fraction along the path; and `capped` closes an open path with the
    /// first and last section's fill. Sections are matched contour by
    /// contour in order, closed with closed and open with open, and a contour
    /// some section lacks is left out of the loft. On a closed path the last
    /// section blends back into the first, which keeps its seam where it was
    /// drawn.
    ///
    /// `at` must hold one fraction per section, in ascending order, within
    /// `0...1` on an open path and `0..<1` on a closed one.
    static func loft(_ sections: [Shape], along path: Curve3D, at stations: [Double]? = nil,
                     smoothed: Bool = true,
                     scale: (Double) -> Double = { _ in 1 },
                     twist: (Double) -> Double = { _ in 0 },
                     capped: Bool = true) -> Mesh {
        let count = sections.count
        let placed: [Double]
        if let stations {
            precondition(stations.count == count, "Mesh.loft: \(count) sections but \(stations.count) stations in `at`")
            for (k, s) in stations.enumerated() {
                precondition(s.isFinite && s >= 0 && (path.isClosed ? s < 1 : s <= 1),
                             "Mesh.loft: station \(k) at \(s) is outside the path (0...1, below 1 on a closed path)")
                precondition(k == 0 || s > stations[k - 1],
                             "Mesh.loft: stations in `at` must ascend (station \(k) at \(s) follows \(stations[k - 1]))")
            }
            placed = stations
        } else if path.isClosed {
            placed = (0..<count).map { Double($0) / Double(count) }
        } else {
            placed = count > 1 ? (0..<count).map { Double($0) / Double(count - 1) } : [0]
        }
        return SweepBuilder.loft(sections, along: path, stations: placed, smoothed: smoothed,
                                 scale: scale, twist: twist, capped: capped)
    }

    /// A surface through several closed outlines laid along a 3D `path` (the
    /// `Shape` form, for the `Profile` helpers' point lists). See
    /// `loft(_:along:at:smoothed:scale:twist:capped:)`.
    static func loft(_ outlines: [[Vector2]], along path: Curve3D, at stations: [Double]? = nil,
                     smoothed: Bool = true,
                     scale: (Double) -> Double = { _ in 1 },
                     twist: (Double) -> Double = { _ in 0 },
                     capped: Bool = true) -> Mesh {
        loft(outlines.map { Shape($0, closed: true) }, along: path, at: stations, smoothed: smoothed,
             scale: scale, twist: twist, capped: capped)
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

/// The grid a sweep or a loft is built on: one row per point of the path
/// (plus one per section that sits between points), and per contour the same
/// columns on every row, each row's outline the blend of the sections there.
private enum SweepBuilder {

    /// One row: how far along the path it sits, and the frame there.
    struct Row {
        let fraction: Double
        let frame: Curve3D.Frame
    }

    /// Two fractions along a path this close are one place.
    static let sameFraction = 1e-9

    /// Every point of the path, in order, with a row inserted at each station
    /// that is not a point's own place (so a section lands exactly where it
    /// was asked for), and a closed path's first row repeated at fraction 1
    /// so `v` can reach it.
    static func rows(of path: Curve3D, stations: [Double]) -> [Row] {
        let n = path.points.count
        var rows: [Row] = []
        rows.reserveCapacity(n + stations.count + 1)
        for i in 0..<n {
            let fraction = path.length > 0 ? path.walked[i] / path.length : Double(i) / Double(n - 1)
            rows.append(Row(fraction: fraction, frame: path.frames[i]))
        }
        if path.length > 0 {
            for s in stations where s > 0 && s < 1 {
                if rows.contains(where: { abs($0.fraction - s) < sameFraction }) { continue }
                let at = rows.firstIndex(where: { $0.fraction > s }) ?? rows.count
                rows.insert(Row(fraction: s, frame: path.frame(at: s)), at: at)
            }
        }
        if path.isClosed { rows.append(Row(fraction: 1, frame: path.frames[0])) }
        return rows
    }

    static func loft(_ sections: [Shape], along path: Curve3D, stations: [Double], smoothed: Bool,
                     scale: (Double) -> Double, twist: (Double) -> Double, capped: Bool) -> Mesh {
        guard path.points.count >= 2, !sections.isEmpty, sections.count == stations.count else {
            return Mesh(positions: [], indices: [])
        }
        // Every section's outlines, cleaned the way a sweep lays them, matched
        // in order: as many closed and as many open as every section has.
        let outlines = sections.map { SweepProfile.outlines(of: $0) }
        let closedRings = outlines.map { $0.filter { $0.isClosed }.map { LoftRing(points: $0.points, isClosed: true) } }
        let openRings = outlines.map { $0.filter { !$0.isClosed }.map { LoftRing(points: $0.points, isClosed: false) } }
        let closedCount = closedRings.map(\.count).min() ?? 0
        let openCount = openRings.map(\.count).min() ?? 0
        guard closedCount + openCount > 0 else { return Mesh(positions: [], indices: []) }

        let rows = rows(of: path, stations: stations)
        let placements = rows.map {
            SweepPlacement(frame: $0.frame, fraction: $0.fraction, scale: scale($0.fraction), twist: twist($0.fraction))
        }
        let blend = LoftBlend(stations: stations, closedPath: path.isClosed, smoothed: smoothed)

        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var uvs: [Vector2] = []
        var indices: [UInt32] = []
        // The closed outlines at the first and the last row, for the caps.
        var endRings: [[[Vector2]]] = [[], []]

        for (closed, count) in [(true, closedCount), (false, openCount)] {
            for c in 0..<count {
                let rings = closed ? closedRings.map { $0[c] } : openRings.map { $0[c] }
                let columns = LoftColumns(rings)
                var prepared: [SweepProfile.Prepared] = []
                prepared.reserveCapacity(rows.count)
                for (r, row) in rows.enumerated() {
                    let points = blend.points(columns.points, at: row.fraction)
                    if closed && (r == 0 || r == rows.count - 1) {
                        endRings[r == 0 ? 0 : 1].append(points)
                    }
                    prepared.append(closed ? SweepProfile.closedColumns(points, sharp: columns.sharp)
                                           : SweepProfile.openColumns(points, sharp: columns.sharp))
                }
                appendWalls(prepared, placements: placements, closedPath: path.isClosed,
                            positions: &positions, normals: &normals, uvs: &uvs, indices: &indices)
            }
        }

        var sealed = openCount == 0 && closedCount > 0
        if capped && !path.isClosed && closedCount > 0 {
            for (end, outward) in [(0, -1.0), (1, 1.0)] {
                let place = placements[end == 0 ? 0 : rows.count - 1]
                let winding = sections[end == 0 ? 0 : sections.count - 1].winding
                let fill = SweepProfile.capTriangles(of: endRings[end], winding: winding)
                guard fill.count >= 3 else { sealed = false; continue }
                let box = SweepProfile.CapMap(fill)
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
        } else if !path.isClosed {
            sealed = false
        }
        var mesh = Mesh(positions: positions, normals: normals, indices: indices, uvs: uvs)
        mesh.isClosed = sealed
        return mesh
    }

    /// One contour's walls: `prepared[row]` is its outline at that row, every
    /// row with the same columns and edges.
    static func appendWalls(_ prepared: [SweepProfile.Prepared], placements: [SweepPlacement], closedPath: Bool,
                            positions: inout [Vector3], normals: inout [Vector3],
                            uvs: inout [Vector2], indices: inout [UInt32]) {
        let rows = placements.count
        let width = prepared[0].columns.count
        let base = positions.count
        var grid = [Vector3](repeating: .zero, count: rows * width)
        for row in 0..<rows {
            for c in 0..<width {
                grid[row * width + c] = placements[row].place(prepared[row].columns[c].point)
            }
        }
        // Neighboring rows for the direction along the path: a closed path
        // wraps over its real rows (the repeated one copies the first), an
        // open one is one-sided at its ends.
        let real = closedPath ? rows - 1 : rows
        for row in 0..<rows {
            let place = placements[row]
            let i = row % real
            let before = closedPath ? (i - 1 + real) % real : max(i - 1, 0)
            let after = closedPath ? (i + 1) % real : min(i + 1, real - 1)
            for c in 0..<width {
                let column = prepared[row].columns[c]
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
            for edge in prepared[0].edges {
                let a = UInt32(base + row * width + edge.from)
                let b = UInt32(base + row * width + edge.to)
                let c = UInt32(base + (row + 1) * width + edge.to)
                let d = UInt32(base + (row + 1) * width + edge.from)
                indices += [a, b, c, a, c, d]
            }
        }
    }
}

/// One outline of one section, read by the fraction of its walked length.
private struct LoftRing {
    let points: [Vector2]
    let isClosed: Bool
    /// The length walked to each point, and for a closed ring one more entry,
    /// the walk back to the start.
    let walked: [Double]
    let total: Double

    init(points: [Vector2], isClosed: Bool) {
        self.points = points
        self.isClosed = isClosed
        let m = points.count
        var walked = [0.0]
        let steps = isClosed ? m : m - 1
        if steps > 0 {
            for i in 1...steps { walked.append(walked[i - 1] + (points[i % m] - points[i - 1]).length) }
        }
        self.walked = walked
        self.total = walked[walked.count - 1]
    }

    /// Each point's fraction of the walk, in order; a closed ring's first
    /// point is 0 and no point reaches 1.
    var fractions: [Double] {
        let m = points.count
        return (0..<m).map { i in
            total > 0 ? walked[i] / total : Double(i) / Double(max(isClosed ? m : m - 1, 1))
        }
    }

    /// The point a fraction `f` of the way round (wrapped on a closed ring,
    /// clamped on an open one).
    func point(at f: Double) -> Vector2 {
        let m = points.count
        guard m >= 2, total > 0, f.isFinite else { return points[0] }
        let t = isClosed ? f - f.rounded(.down) : min(max(f, 0), 1)
        let target = t * total
        let segments = isClosed ? m : m - 1
        var lo = 0, hi = segments - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if walked[mid] <= target { lo = mid } else { hi = mid - 1 }
        }
        let a = points[lo], b = points[(lo + 1) % m]
        let span = walked[lo + 1] - walked[lo]
        let w = span > 0 ? min(max((target - walked[lo]) / span, 0), 1) : 0
        return a + (b - a) * w
    }
}

/// The columns a set of matched rings share: the union of every ring's
/// points by their fraction of its length (each closed ring read from the
/// seam that keeps it nearest the ring before), every ring read at every
/// column, and which columns turn sharply on some ring.
private struct LoftColumns {
    /// `points[ring][column]`.
    let points: [[Vector2]]
    /// Whether the outline turns more than 30° at that column on any ring.
    let sharp: [Bool]

    /// The seam of each closed ring in turn is tried at this many even steps
    /// round it, against the ring before read from its own seam.
    static let seamSteps = 256

    init(_ rings: [LoftRing]) {
        let closed = rings[0].isClosed
        var seams = [Double](repeating: 0, count: rings.count)
        if closed {
            for k in 1..<rings.count {
                seams[k] = LoftColumns.seam(of: rings[k], nearest: rings[k - 1], from: seams[k - 1])
            }
        }
        // Every ring's points as fractions past its seam, merged into
        // columns: a point joins a column within the tolerance that no point
        // of its own ring already holds, and otherwise opens a new one.
        struct Entry { let fraction: Double; let ring: Int; let point: Int }
        var entries: [Entry] = []
        for (k, ring) in rings.enumerated() {
            for (i, f) in ring.fractions.enumerated() {
                var a = f - seams[k]
                if closed {
                    a -= a.rounded(.down)
                    if a > 1 - SweepBuilder.sameFraction { a = 0 }
                }
                entries.append(Entry(fraction: a, ring: k, point: i))
            }
        }
        entries.sort { $0.fraction != $1.fraction ? $0.fraction < $1.fraction : ($0.ring != $1.ring ? $0.ring < $1.ring : $0.point < $1.point) }
        var fractions: [Double] = []
        var holders: [[Int?]] = []          // holders[column][ring] = the ring's point there, if its own
        for e in entries {
            if let last = fractions.last, abs(e.fraction - last) < SweepBuilder.sameFraction,
               holders[holders.count - 1][e.ring] == nil {
                holders[holders.count - 1][e.ring] = e.point
            } else {
                fractions.append(e.fraction)
                var row = [Int?](repeating: nil, count: rings.count)
                row[e.ring] = e.point
                holders.append(row)
            }
        }
        var points: [[Vector2]] = []
        for (k, ring) in rings.enumerated() {
            points.append(fractions.indices.map { c in
                if let own = holders[c][k] { return ring.points[own] }
                return ring.point(at: fractions[c] + seams[k])
            })
        }
        self.points = points
        var sharp = [Bool](repeating: false, count: fractions.count)
        for ring in points {
            for c in SweepProfile.sharpCorners(of: ring, closed: closed) { sharp[c] = true }
        }
        self.sharp = sharp
    }

    /// The fraction of `ring`'s walk at which to start it so that, read from
    /// there, it sits nearest `previous` read from `previousSeam`: the one of
    /// `seamSteps` even starts round the ring with the least summed squared
    /// distance (ties keep the earliest).
    static func seam(of ring: LoftRing, nearest previous: LoftRing, from previousSeam: Double) -> Double {
        let n = seamSteps
        let a = (0..<n).map { previous.point(at: previousSeam + Double($0) / Double(n)) }
        let b = (0..<n).map { ring.point(at: Double($0) / Double(n)) }
        var best = 0
        var bestSum = Double.infinity
        for offset in 0..<n {
            var sum = 0.0
            for j in 0..<n {
                sum += (a[j] - b[(j + offset) % n]).lengthSquared
                if sum >= bestSum { break }
            }
            if sum < bestSum { bestSum = sum; best = offset }
        }
        return Double(best) / Double(n)
    }
}

/// How a fraction along the path blends the sections: straight from one to
/// the next, or as a smooth curve through them.
private struct LoftBlend {
    let stations: [Double]
    let closedPath: Bool
    let smoothed: Bool

    /// The outline at `fraction`, blended column by column from
    /// `sections[section][column]`. A fraction at a station (within
    /// `sameFraction`) is that section exactly; before the first or past the
    /// last on an open path, the end section holds.
    func points(_ sections: [[Vector2]], at fraction: Double) -> [Vector2] {
        let n = sections.count
        guard n >= 2 else { return sections[0] }
        let near = SweepBuilder.sameFraction
        for (k, s) in stations.enumerated() where abs(fraction - s) < near { return sections[k] }
        if closedPath && abs(fraction - 1 - stations[0]) < near { return sections[0] }

        // The interval the fraction falls in, and how far through it.
        let k: Int, next: Int, t: Double
        if fraction < stations[0] || fraction >= stations[n - 1] {
            guard closedPath else { return sections[fraction < stations[0] ? 0 : n - 1] }
            k = n - 1
            next = 0
            let width = 1 - stations[n - 1] + stations[0]
            let walked = fraction >= stations[n - 1] ? fraction - stations[n - 1] : fraction + 1 - stations[n - 1]
            t = width > 0 ? walked / width : 0
        } else {
            var last = 0
            while last + 1 < n && stations[last + 1] <= fraction { last += 1 }
            k = last
            next = last + 1
            let width = stations[next] - stations[k]
            t = width > 0 ? (fraction - stations[k]) / width : 0
        }
        if t <= 0 { return sections[k] }
        if t >= 1 { return sections[next] }
        let from = sections[k], to = sections[next]
        if !smoothed || (n == 2 && !closedPath) {
            return from.indices.map { from[$0] + (to[$0] - from[$0]) * t }
        }
        // A cubic through the sections, written from the start section and
        // differences so equal sections blend to themselves exactly: the
        // tangent at a section is half the chord across its neighbors, or
        // the whole chord to its one neighbor at an open end.
        func tangent(_ j: Int, _ c: Int) -> Vector2 {
            if closedPath {
                return (sections[(j + 1) % n][c] - sections[(j - 1 + n) % n][c]) * 0.5
            }
            if j == 0 { return sections[1][c] - sections[0][c] }
            if j == n - 1 { return sections[n - 1][c] - sections[n - 2][c] }
            return (sections[j + 1][c] - sections[j - 1][c]) * 0.5
        }
        let t2 = t * t, t3 = t2 * t
        let h01 = -2 * t3 + 3 * t2
        let h10 = t3 - 2 * t2 + t
        let h11 = t3 - t2
        return from.indices.map { c in
            from[c] + (to[c] - from[c]) * h01 + tangent(k, c) * h10 + tangent(next, c) * h11
        }
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

    /// A shape's contours as plain point runs, cleaned for sweeping: repeated
    /// points and a closed contour's duplicated closing point dropped, a
    /// closed contour reversed where its wall would face in, and a contour
    /// too short to sweep left out.
    static func outlines(of shape: Shape) -> [(points: [Vector2], isClosed: Bool)] {
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
                return (points, true)
            }
            guard points.count >= 2 else { return nil }
            return (points, false)
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

    /// The indices where `points` turns more than 30°: round a closed
    /// outline, or inside an open one (its ends never split).
    static func sharpCorners(of points: [Vector2], closed: Bool) -> [Int] {
        let m = points.count
        func edge(_ i: Int) -> Vector2 { (points[(i + 1) % m] - points[i]).normalized }
        var sharp: [Int] = []
        let range = closed ? 0..<m : (m > 2 ? 1..<(m - 1) : 0..<0)
        for i in range where edge((i - 1 + m) % m).dot(edge(i)) < creaseCosine - 1e-9 {
            sharp.append(i)
        }
        return sharp
    }

    /// A closed outline's columns, `sharp[i]` saying which points keep a hard
    /// edge (two columns, one for each side).
    static func closedColumns(_ points: [Vector2], sharp: [Bool]) -> Prepared {
        let m = points.count
        var walked = [0.0]
        for i in 1...m { walked.append(walked[i - 1] + (points[i % m] - points[i - 1]).length) }
        let total = walked[m]
        func u(_ i: Int) -> Double { total > 0 ? walked[i] / total : Double(i) / Double(m) }
        func edge(_ i: Int) -> Vector2 { (points[(i + 1) % m] - points[i]).normalized }
        func smooth(_ i: Int) -> Vector2 {
            let d = points[(i + 1) % m] - points[(i - 1 + m) % m]
            return d.lengthSquared > 0 ? d.normalized : edge(i)
        }
        var columns: [Column] = []
        var edges: [(from: Int, to: Int)] = []
        // The seam at point 0 opens the walk (its outgoing side) and closes it
        // again at u = 1 (its incoming side), one column each.
        columns.append(Column(point: points[0], direction: sharp[0] ? edge(0) : smooth(0), u: 0))
        for i in 1..<m {
            let incoming = columns.count - 1
            if sharp[i] {
                columns.append(Column(point: points[i], direction: edge(i - 1), u: u(i)))
                edges.append((incoming, columns.count - 1))
                columns.append(Column(point: points[i], direction: edge(i), u: u(i)))
            } else {
                columns.append(Column(point: points[i], direction: smooth(i), u: u(i)))
                edges.append((incoming, columns.count - 1))
            }
        }
        let last = columns.count - 1
        columns.append(Column(point: points[0], direction: sharp[0] ? edge(m - 1) : smooth(0), u: 1))
        edges.append((last, columns.count - 1))
        return Prepared(columns: columns, edges: edges)
    }

    /// An open outline's columns, `sharp[i]` as for a closed one (the two
    /// ends are never sharp).
    static func openColumns(_ points: [Vector2], sharp: [Bool]) -> Prepared {
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
            } else if sharp[i] {
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

    /// The triangles that fill the closed outlines `rings` (one cap), every
    /// corner one of the rings' own points. The outlines are triangulated
    /// with each straight run of points reduced to its two ends, since the
    /// triangulator fills a run of points on one line with slivers of no
    /// area; a triangle's edge along such a run is then split back at the
    /// run's points and fanned from the corner opposite (or, when more than
    /// one edge is split, from the triangle's center), so the cap meets the
    /// walls point for point.
    static func capTriangles(of rings: [[Vector2]], winding: FillWinding) -> [Vector2] {
        struct Key: Hashable { let x: Float; let y: Float }
        var corners: [[Int]] = []
        var lookup: [Key: (ring: Int, slot: Int)] = [:]
        var contours: [Contour] = []
        for (r, ring) in rings.enumerated() {
            let m = ring.count
            var kept: [Int] = []
            for i in 0..<m where !onSegment(ring[i], from: ring[(i - 1 + m) % m], to: ring[(i + 1) % m]) {
                kept.append(i)
            }
            corners.append(kept)
            guard kept.count >= 3 else { continue }
            for (slot, i) in kept.enumerated() {
                lookup[Key(x: Float(ring[i].x), y: Float(ring[i].y))] = (r, slot)
            }
            contours.append(Contour(kept.map { ring[$0] }, closed: true))
        }
        guard !contours.isEmpty else { return [] }
        let fill = Shape(contours: contours, winding: winding).triangulatedFill()

        /// The ring's points strictly between two of its indices, forward.
        func dropped(_ ring: [Vector2], from i: Int, to j: Int) -> [Vector2] {
            var out: [Vector2] = []
            var k = (i + 1) % ring.count
            while k != j { out.append(ring[k]); k = (k + 1) % ring.count }
            return out
        }

        var out: [Vector2] = []
        var k = 0
        while k + 2 < fill.count {
            let ids = (0..<3).map { lookup[Key(x: Float(fill[k + $0].x), y: Float(fill[k + $0].y))] }
            let exact = (0..<3).map { e in ids[e].map { rings[$0.ring][corners[$0.ring][$0.slot]] } ?? fill[k + e] }
            k += 3
            var polygon: [Vector2] = []
            var split: [Int] = []
            for e in 0..<3 {
                polygon.append(exact[e])
                guard let u = ids[e], let v = ids[(e + 1) % 3], u.ring == v.ring else { continue }
                let kept = corners[u.ring], ring = rings[u.ring], n = kept.count
                var between: [Vector2] = []
                if v.slot == (u.slot + 1) % n {
                    between = dropped(ring, from: kept[u.slot], to: kept[v.slot])
                } else if u.slot == (v.slot + 1) % n {
                    between = dropped(ring, from: kept[v.slot], to: kept[u.slot]).reversed()
                }
                if !between.isEmpty { split.append(e); polygon += between }
            }
            if split.isEmpty {
                out += exact
            } else if split.count == 1 {
                // Fan from the corner opposite the split edge: the polygon
                // turned to start there, its two edges at that corner skipped.
                let apex = (split[0] + 2) % 3
                let start = polygon.firstIndex { $0 == exact[apex] } ?? 0
                let turned = Array(polygon[start...]) + Array(polygon[..<start])
                for i in 1..<(turned.count - 1) { out += [turned[0], turned[i], turned[i + 1]] }
            } else {
                let center = (exact[0] + exact[1] + exact[2]) * (1.0 / 3)
                for i in polygon.indices { out += [center, polygon[i], polygon[(i + 1) % polygon.count]] }
            }
        }
        return out
    }

    /// Whether `p` lies on the segment from `a` to `b` (within a trillionth
    /// of its length).
    static func onSegment(_ p: Vector2, from a: Vector2, to b: Vector2) -> Bool {
        let ab = b - a, ap = p - a
        let len2 = ab.lengthSquared
        guard len2 > 0 else { return ap.lengthSquared == 0 }
        let t = ap.dot(ab) / len2
        guard t >= 0 && t <= 1 else { return false }
        return (ap - ab * t).lengthSquared <= 1e-24 * len2
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
        var mesh = Mesh(positions: positions, normals: normals, indices: indices, uvs: uvs, colors: vertexColors)
        mesh.isClosed = false
        return mesh
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
