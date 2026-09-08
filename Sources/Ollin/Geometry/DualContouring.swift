import Foundation

/// Dual contouring: the isosurface built with one vertex per piece of surface
/// through a cell instead of one per crossed edge, placed where the field's
/// own normals say the surface is. Marching cubes puts every vertex on a grid
/// edge, so a corner of the field that falls inside a cell can only come out
/// as a bevel across it. Dual contouring reads, at each crossing, the point
/// and the field's normal there (Hermite data), and puts the vertex at the
/// point that best agrees with every tangent plane through those crossings.
/// Where the planes all agree the vertex sits on the surface; where they meet
/// at a crease it sits on the crease, and where three meet at a corner it
/// sits on the corner. Then every crossed edge of the lattice becomes one
/// quad joining the four vertices around it, so the mesh is dual to the grid:
/// its faces sit where marching cubes had vertices and its vertices where
/// marching cubes had faces.
///
/// A cell can hold more than one sheet of surface (a thin wedge, the two
/// walls of a slot), and one vertex cannot lie on both, so each sheet gets its
/// own: the cell's six face contours are chained into loops exactly as the
/// march does it, and each loop is one sheet with one vertex. A quad then
/// joins, in each of its four cells, the sheet that its edge crosses.
///
/// The cost over marching cubes is field calls: each crossing is refined by
/// bisection onto the true surface and its normal read by central differences
/// there, a dozen calls per crossing, so a field with a sharp feature comes
/// out sharp rather than rounded to the lattice. The normals are clustered
/// per sheet (a sheet on a crease carries one normal per side, a smooth one
/// one for all), so a block shades flat to its edges and a sphere still
/// shades smooth.
extension IsosurfaceGrid {

    /// The dual-contoured surface of `field` at `level`, given the lattice
    /// samples already taken (shifted so the surface sits at zero).
    func dualContour(values: [Double], field: (Vector3) -> Double, level: Double) -> Mesh {
        // One slot per lattice edge, as the march keeps: the index of the
        // crossing on that edge, or -1. Fixed visiting order makes the output
        // reproducible.
        var crossingAt = [Int32](repeating: -1, count: sx * sy * sz * 3)
        var points: [Vector3] = []
        var normals: [Vector3] = []

        // MARK: Pass one, the Hermite data on every crossed edge

        for k in 0 ..< sz {
            for j in 0 ..< sy {
                for i in 0 ..< sx {
                    let here = latticeIndex(i, j, k)
                    let a = values[here]
                    for axis in 0 ..< 3 {
                        let (ni, nj, nk) = (i + (axis == 0 ? 1 : 0), j + (axis == 1 ? 1 : 0), k + (axis == 2 ? 1 : 0))
                        guard ni < sx, nj < sy, nk < sz else { continue }
                        let b = values[latticeIndex(ni, nj, nk)]
                        guard (a > 0) != (b > 0) else { continue }
                        let low = point(i, j, k), high = point(ni, nj, nk)
                        let p = refineCrossing(from: low, to: high, a: a, b: b, field: field, level: level)
                        crossingAt[here * 3 + axis] = Int32(points.count)
                        points.append(p)
                        normals.append(surfaceNormal(at: p, field: field, fallback: high - low, sign: a > 0))
                    }
                }
            }
        }

        // MARK: Pass two, one vertex per sheet of surface through a cell

        let cellCount = nx * ny * nz
        // A cell's sheets are stored together: where they start and how many.
        var cellFirstSheet = [Int32](repeating: 0, count: cellCount)
        var cellSheetCount = [UInt8](repeating: 0, count: cellCount)
        var sheetPosition: [Vector3] = []
        var sheetRank: [UInt8] = []
        var sheetEdges: [UInt16] = []          // which of the cell's twelve edges the sheet crosses
        var sheetFirstCrossing: [Int32] = []   // into sheetCrossings
        var sheetCrossingCount: [UInt8] = []
        var sheetCrossings: [Int32] = []
        var solver = QuadricSolver()

        var corner = [Double](repeating: 0, count: 8)
        var next = [Int](repeating: -1, count: 12)
        var order = [Int](repeating: 0, count: 4)
        var loop: [Int] = []
        loop.reserveCapacity(12)

        for k in 0 ..< nz {
            for j in 0 ..< ny {
                for i in 0 ..< nx {
                    let cell = cellIndex(i, j, k)
                    var mask = 0
                    for c in 0 ..< 8 {
                        let v = values[latticeIndex(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))]
                        corner[c] = v
                        if v > 0 { mask |= 1 << c }
                    }
                    if mask == 0 || mask == 255 { continue }

                    let lowCorner = point(i, j, k)
                    let highCorner = lowCorner + Vector3(spacing, spacing, spacing)
                    // An ambiguous face (two inside corners across a diagonal)
                    // is settled by the field at the face's saddle, the one
                    // spot the bilinear guess can be wrong about: a thin wedge
                    // of material reads as a channel there, and its two sheets
                    // would be chained into one and given one vertex between
                    // them. Both cells on the face ask the same point, so they
                    // still agree.
                    let cornerValues = corner
                    func decide(_ face: Int) -> Bool? {
                        guard let (s, t) = saddle(face: face, corner: cornerValues) else { return nil }
                        let base = face * 4
                        func at(_ step: Int) -> Vector3 {
                            let c = IsosurfaceCube.faceCorners[base + step]
                            return point(i + (c & 1), j + ((c >> 1) & 1), k + ((c >> 2) & 1))
                        }
                        let a = at(0), b = at(1), d = at(3)
                        return field(a + (b - a) * s + (d - a) * t) - level > 0
                    }
                    for e in 0 ..< 12 { next[e] = -1 }
                    for face in 0 ..< 6 {
                        link(face: face, corner: corner, order: &order, into: &next, decide: decide)
                    }
                    cellFirstSheet[cell] = Int32(sheetPosition.count)

                    for start in 0 ..< 12 where next[start] >= 0 {
                        loop.removeAll(keepingCapacity: true)
                        var e = start
                        while next[e] >= 0 {
                            loop.append(e)
                            let step = next[e]
                            next[e] = -1
                            e = step
                        }
                        guard loop.count >= 3 else { continue }

                        solver.reset()
                        var edges: UInt16 = 0
                        let firstCrossing = sheetCrossings.count
                        for e in loop {
                            let low = IsosurfaceCube.edges[e].low
                            let slot = latticeIndex(i + (low & 1), j + ((low >> 1) & 1), k + ((low >> 2) & 1)) * 3
                                + IsosurfaceCube.axis(of: e)
                            let crossing = crossingAt[slot]
                            guard crossing >= 0 else { continue }
                            edges |= 1 << UInt16(e)
                            sheetCrossings.append(crossing)
                            solver.add(point: points[Int(crossing)], normal: normals[Int(crossing)])
                        }
                        let solved = solver.solve(within: lowCorner, highCorner)
                        sheetPosition.append(solved.point)
                        sheetRank.append(UInt8(solved.rank))
                        sheetEdges.append(edges)
                        sheetFirstCrossing.append(Int32(firstCrossing))
                        sheetCrossingCount.append(UInt8(sheetCrossings.count - firstCrossing))
                        cellSheetCount[cell] += 1
                    }
                }
            }
        }

        // MARK: Pass two, again: a crease that cut a cell too briefly

        // A crease between two curved surfaces can pass through a cell without
        // one of the surfaces crossing any of its twelve edges, so the sheet's
        // data reads as one patch and its vertex lands off the crease, and the
        // crease comes out as a stair. Such a sheet sits between two sheets on
        // the cell's faces that did read the crease: its vertex moves to the
        // chord between theirs, where that chord passes through the cell.
        let faceSteps = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
        var bridged = sheetPosition
        var creased: [Vector3] = []
        for k in 0 ..< nz {
            for j in 0 ..< ny {
                for i in 0 ..< nx {
                    let cell = cellIndex(i, j, k)
                    guard cellSheetCount[cell] > 0 else { continue }
                    creased.removeAll(keepingCapacity: true)
                    for (di, dj, dk) in faceSteps {
                        let (ni, nj, nk) = (i + di, j + dj, k + dk)
                        guard ni >= 0, ni < nx, nj >= 0, nj < ny, nk >= 0, nk < nz else { continue }
                        let neighbor = cellIndex(ni, nj, nk)
                        let first = Int(cellFirstSheet[neighbor])
                        for sheet in first ..< first + Int(cellSheetCount[neighbor]) where sheetRank[sheet] >= 2 {
                            creased.append(sheetPosition[sheet])
                        }
                    }
                    guard creased.count >= 2 else { continue }
                    let lowCorner = point(i, j, k)
                    let highCorner = lowCorner + Vector3(spacing, spacing, spacing)
                    let slack = spacing * 0.05
                    let first = Int(cellFirstSheet[cell])
                    for sheet in first ..< first + Int(cellSheetCount[cell]) where sheetRank[sheet] < 2 {
                        let v = sheetPosition[sheet]
                        var best: (point: Vector3, distance: Double)?
                        for a in 0 ..< creased.count {
                            for b in a + 1 ..< creased.count {
                                let p = creased[a], chord = creased[b] - creased[a]
                                guard chord.lengthSquared > 0 else { continue }
                                let t = min(max((v - p).dot(chord) / chord.lengthSquared, 0), 1)
                                let foot = p + chord * t
                                guard foot.x >= lowCorner.x - slack, foot.x <= highCorner.x + slack,
                                      foot.y >= lowCorner.y - slack, foot.y <= highCorner.y + slack,
                                      foot.z >= lowCorner.z - slack, foot.z <= highCorner.z + slack
                                else { continue }
                                let distance = (foot - v).length
                                if best == nil || distance < best!.distance { best = (foot, distance) }
                            }
                        }
                        if let best {
                            bridged[sheet] = Vector3(min(max(best.point.x, lowCorner.x), highCorner.x),
                                                     min(max(best.point.y, lowCorner.y), highCorner.y),
                                                     min(max(best.point.z, lowCorner.z), highCorner.z))
                        }
                    }
                }
            }
        }
        sheetPosition = bridged

        // MARK: Pass three, one quad per crossed edge with four cells around it

        var outPositions: [Vector3] = []
        var outNormals: [Vector3] = []
        var indices: [UInt32] = []
        // The output vertices of each sheet, threaded as a list, so a corner
        // asking for a normal the sheet already emitted gets the same vertex.
        var sheetHead = [Int32](repeating: -1, count: sheetPosition.count)
        var nextInSheet: [Int32] = []
        var corners = [Int](repeating: 0, count: 4)
        let creaseCosine = cos(35 * Double.pi / 180)

        /// The vertex of `sheet` shaded with the normals of its crossings that
        /// agree with `guide`, welded to an earlier one if the sheet has it. A
        /// guide that agrees with none (a crossing that landed on the crease
        /// itself reads a blend of both sides) takes the side nearest it.
        func vertex(of sheet: Int, toward guide: Vector3) -> Int {
            let first = Int(sheetFirstCrossing[sheet]), count = Int(sheetCrossingCount[sheet])
            var seed = guide
            var nearest = -2.0
            for c in first ..< first + count {
                let n = normals[Int(sheetCrossings[c])]
                let agreement = n.dot(guide)
                if agreement > nearest { nearest = agreement; seed = n }
            }
            var sum = Vector3.zero
            for c in first ..< first + count {
                let n = normals[Int(sheetCrossings[c])]
                if n.dot(seed) >= creaseCosine { sum += n }
            }
            let normal = sum.lengthSquared > 0 ? sum.normalized : guide

            var existing = sheetHead[sheet]
            while existing >= 0 {
                if outNormals[Int(existing)].dot(normal) > 0.9999 { return Int(existing) }
                existing = nextInSheet[Int(existing)]
            }
            let index = outPositions.count
            outPositions.append(sheetPosition[sheet])
            outNormals.append(normal)
            nextInSheet.append(sheetHead[sheet])
            sheetHead[sheet] = Int32(index)
            return index
        }

        /// The sheet of `cell` that crosses its local edge `edge`, or -1.
        func sheet(of cell: Int, crossing edge: Int) -> Int {
            let first = Int(cellFirstSheet[cell])
            let bit = UInt16(1) << UInt16(edge)
            for sheet in first ..< first + Int(cellSheetCount[cell]) where sheetEdges[sheet] & bit != 0 {
                return sheet
            }
            return -1
        }

        /// Two triangles. The diagonal is the one whose two triangles both
        /// face the way the crossing's normal does, since a quad across a
        /// crease can fold along the other one (two of its corners landing
        /// almost together on the crease line, the fourth off it); when both
        /// splits agree the shorter diagonal wins. A corner that fell on
        /// another skips its triangle.
        func emitQuad(_ a: Int, _ b: Int, _ c: Int, _ d: Int, facing guide: Vector3) {
            let pa = outPositions[a], pb = outPositions[b], pc = outPositions[c], pd = outPositions[d]
            func folds(_ p: Vector3, _ q: Vector3, _ r: Vector3) -> Int {
                (q - p).cross(r - p).dot(guide) < 0 ? 1 : 0
            }
            let alongAC = folds(pa, pb, pc) + folds(pa, pc, pd)
            let alongBD = folds(pb, pc, pd) + folds(pb, pd, pa)
            let splitAC = alongAC != alongBD
                ? alongAC < alongBD
                : (pa - pc).lengthSquared <= (pb - pd).lengthSquared
            if splitAC {
                appendTriangle(a, b, c); appendTriangle(a, c, d)
            } else {
                appendTriangle(b, c, d); appendTriangle(b, d, a)
            }
        }

        func appendTriangle(_ a: Int, _ b: Int, _ c: Int) {
            let pa = outPositions[a], pb = outPositions[b], pc = outPositions[c]
            guard (pb - pa).cross(pc - pa).lengthSquared > 0 else { return }
            indices.append(UInt32(a)); indices.append(UInt32(b)); indices.append(UInt32(c))
        }

        let cells = [nx, ny, nz]
        let ring = [(1, 1), (0, 1), (0, 0), (1, 0)]

        for k in 0 ..< sz {
            for j in 0 ..< sy {
                for i in 0 ..< sx {
                    let here = latticeIndex(i, j, k)
                    for axis in 0 ..< 3 {
                        let crossing = crossingAt[here * 3 + axis]
                        guard crossing >= 0 else { continue }
                        // The four cells around the edge, walked counter-clockwise
                        // as seen from the edge's positive end. The edge runs
                        // along `axis`; the cells step back along the other two.
                        let u = (axis + 1) % 3, w = (axis + 2) % 3
                        var steps = [i, j, k]
                        guard steps[u] >= 1, steps[u] <= cells[u] - 1,
                              steps[w] >= 1, steps[w] <= cells[w] - 1
                        else { continue }   // the surface leaves the box here: left open
                        let guide = normals[Int(crossing)]
                        var complete = true
                        for (corner, offset) in ring.enumerated() {
                            steps = [i, j, k]
                            steps[u] -= offset.0
                            steps[w] -= offset.1
                            let cell = cellIndex(steps[0], steps[1], steps[2])
                            // The edge's low corner within this cell names its
                            // local edge, and with it the sheet that crosses it.
                            let low = (i - steps[0]) | ((j - steps[1]) << 1) | ((k - steps[2]) << 2)
                            let high = low | (1 << axis)
                            let local = IsosurfaceCube.edgeBetween[low * 8 + high]
                            let owner = sheet(of: cell, crossing: local)
                            guard owner >= 0 else { complete = false; break }
                            corners[corner] = vertex(of: owner, toward: guide)
                        }
                        guard complete else { continue }
                        // With the low end inside, the outward side is the
                        // positive end and the walk already faces it; otherwise
                        // the quad turns over.
                        if values[here] > 0 {
                            emitQuad(corners[0], corners[1], corners[2], corners[3], facing: guide)
                        } else {
                            emitQuad(corners[3], corners[2], corners[1], corners[0], facing: guide)
                        }
                    }
                }
            }
        }

        return Mesh(positions: outPositions, normals: outNormals, indices: indices)
    }

    private func cellIndex(_ i: Int, _ j: Int, _ k: Int) -> Int { (k * ny + j) * nx + i }

    /// Where the field crosses zero between `low` and `high`, whose shifted
    /// values `a` and `b` straddle it: six halvings of the bracket, then one
    /// linear step inside what is left, so a plane lands exactly and a curve
    /// lands within a sixty-fourth of the edge before the last step tightens it.
    private func refineCrossing(from low: Vector3, to high: Vector3, a: Double, b: Double,
                                field: (Vector3) -> Double, level: Double) -> Vector3 {
        var t0 = 0.0, t1 = 1.0
        var fa = a, fb = b
        for _ in 0 ..< 6 {
            let tm = 0.5 * (t0 + t1)
            let fm = field(low + (high - low) * tm) - level
            if (fm > 0) == (fa > 0) { t0 = tm; fa = fm } else { t1 = tm; fb = fm }
        }
        let t = fa == fb ? 0.5 * (t0 + t1) : clamp(t0 + (t1 - t0) * (fa / (fa - fb)), t0, t1)
        return low + (high - low) * t
    }

    /// The surface's outward normal at `p`: the field's gradient there by
    /// central differences over a hundredth of a cell, pointing down the
    /// field, out of the region it encloses. A flat spot falls back to the
    /// crossed edge's own direction, turned to point outward.
    private func surfaceNormal(at p: Vector3, field: (Vector3) -> Double,
                               fallback: Vector3, sign lowIsInside: Bool) -> Vector3 {
        let e = spacing * 0.01
        let g = Vector3(field(p + Vector3(e, 0, 0)) - field(p - Vector3(e, 0, 0)),
                        field(p + Vector3(0, e, 0)) - field(p - Vector3(0, e, 0)),
                        field(p + Vector3(0, 0, e)) - field(p - Vector3(0, 0, e)))
        if g.lengthSquared > 0 { return (g * -1).normalized }
        return lowIsInside ? fallback.normalized : fallback.normalized * -1
    }
}

// MARK: - The quadric

/// The least-squares point for a sheet's Hermite data: the `x` minimizing the
/// summed squared distance to every tangent plane `n · (x - p) = 0`. Solved
/// through the normal equations about the crossings' mass point, with the
/// matrix's small eigenvalues dropped so a flat patch (one direction) or a
/// crease (two) does not send the answer off along the direction the data
/// never constrained. The rank comes back with the point: how many directions
/// the data pinned, so a crease (two) and a corner (three) can be told from a
/// patch (one).
struct QuadricSolver {
    private var xx = 0.0, xy = 0.0, xz = 0.0, yy = 0.0, yz = 0.0, zz = 0.0
    private var rhs = Vector3.zero
    private var mass = Vector3.zero
    private var count = 0

    mutating func reset() {
        xx = 0; xy = 0; xz = 0; yy = 0; yz = 0; zz = 0
        rhs = .zero; mass = .zero; count = 0
    }

    mutating func add(point p: Vector3, normal n: Vector3) {
        xx += n.x * n.x; xy += n.x * n.y; xz += n.x * n.z
        yy += n.y * n.y; yz += n.y * n.z; zz += n.z * n.z
        rhs += n * n.dot(p)
        mass += p
        count += 1
    }

    func solve(within low: Vector3, _ high: Vector3) -> (point: Vector3, rank: Int) {
        guard count > 0 else { return ((low + high) * 0.5, 0) }
        let c = mass * (1 / Double(count))
        // The residual about the mass point: what the planes ask for beyond it.
        let r = rhs - Vector3(xx * c.x + xy * c.y + xz * c.z,
                              xy * c.x + yy * c.y + yz * c.z,
                              xz * c.x + yz * c.y + zz * c.z)
        let (values, vectors) = symmetricEigen(xx, xy, xz, yy, yz, zz)
        var pairs = [(values.0, vectors.0), (values.1, vectors.1), (values.2, vectors.2)]
        pairs.sort { $0.0 > $1.0 }
        let largest = pairs[0].0
        guard largest > 0 else { return (clamp(c, low, high), 0) }
        // Directions whose singular value falls under a tenth of the largest
        // are unconstrained: kept, they would carry the answer far away.
        let kept = pairs.filter { $0.0 > largest * 0.01 }.count

        func inside(_ x: Vector3, by slack: Double) -> Bool {
            x.x >= low.x - slack && x.x <= high.x + slack
                && x.y >= low.y - slack && x.y <= high.y + slack
                && x.z >= low.z - slack && x.z <= high.z + slack
        }
        let slack = (high.x - low.x) * 1e-6

        // The data may pin the answer to a point (three directions), a line
        // (two: a crease) or a plane (one: a patch). When the pinned point
        // falls outside the cell, the crease or the patch that runs through
        // the cell is still the answer: slide along what the data left free
        // to where it enters the cell, nearest the pinned point. Only when
        // that misses the cell too has a curved patch been read as a corner,
        // and the rank drops.
        var rank = kept
        while rank >= 1 {
            var x = c
            for (value, axis) in pairs.prefix(rank) {
                x += axis * (axis.dot(r) / value)
            }
            if inside(x, by: slack) { return (clamp(x, low, high), rank) }
            switch rank {
            case 2:
                // The crease line through the pinned point: the stretch of it
                // inside the cell, and the point of that stretch nearest the foot.
                let d = pairs[2].1
                var tMin = -Double.infinity, tMax = Double.infinity
                for (position, step, lower, upper) in [(x.x, d.x, low.x, high.x), (x.y, d.y, low.y, high.y), (x.z, d.z, low.z, high.z)] {
                    if abs(step) > 1e-12 {
                        let t1 = (lower - position) / step, t2 = (upper - position) / step
                        tMin = max(tMin, min(t1, t2))
                        tMax = min(tMax, max(t1, t2))
                    } else if position < lower - slack || position > upper + slack {
                        tMin = .infinity
                    }
                }
                if tMin <= tMax {
                    let t = min(max(0, tMin), tMax)
                    return (clamp(x + d * t, low, high), 2)
                }
            case 1:
                // The patch's plane: the point of it inside the cell nearest
                // the foot, by alternating the clamp and the plane.
                let n = pairs[0].1
                var y = x
                for _ in 0 ..< 12 {
                    y = clamp(y, low, high)
                    y -= n * n.dot(y - x)
                }
                if inside(y, by: slack * 1e3) { return (clamp(y, low, high), 1) }
            default:
                break
            }
            rank -= 1
        }
        return (clamp(c, low, high), 0)
    }

    private func clamp(_ p: Vector3, _ low: Vector3, _ high: Vector3) -> Vector3 {
        Vector3(min(max(p.x, low.x), high.x), min(max(p.y, low.y), high.y), min(max(p.z, low.z), high.z))
    }
}

/// The eigenvalues and unit eigenvectors of a symmetric 3x3 matrix, by
/// cyclic Jacobi rotations: a handful of sweeps takes the off-diagonal part
/// to nothing for a matrix this small.
private func symmetricEigen(_ xx: Double, _ xy: Double, _ xz: Double,
                            _ yy: Double, _ yz: Double, _ zz: Double)
    -> (values: (Double, Double, Double), vectors: (Vector3, Vector3, Vector3)) {
    var a = [[xx, xy, xz], [xy, yy, yz], [xz, yz, zz]]
    var v = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
    for _ in 0 ..< 12 {
        let off = a[0][1] * a[0][1] + a[0][2] * a[0][2] + a[1][2] * a[1][2]
        if off < 1e-24 * max(1, xx * xx + yy * yy + zz * zz) { break }
        for (p, q) in [(0, 1), (0, 2), (1, 2)] where a[p][q] != 0 {
            let theta = (a[q][q] - a[p][p]) / (2 * a[p][q])
            let t = (theta >= 0 ? 1.0 : -1.0) / (abs(theta) + (theta * theta + 1).squareRoot())
            let cs = 1 / (t * t + 1).squareRoot(), sn = t * cs
            for k in 0 ..< 3 {
                let akp = a[k][p], akq = a[k][q]
                a[k][p] = cs * akp - sn * akq
                a[k][q] = sn * akp + cs * akq
            }
            for k in 0 ..< 3 {
                let apk = a[p][k], aqk = a[q][k]
                a[p][k] = cs * apk - sn * aqk
                a[q][k] = sn * apk + cs * aqk
            }
            for k in 0 ..< 3 {
                let vkp = v[k][p], vkq = v[k][q]
                v[k][p] = cs * vkp - sn * vkq
                v[k][q] = sn * vkp + cs * vkq
            }
        }
    }
    return ((a[0][0], a[1][1], a[2][2]),
            (Vector3(v[0][0], v[1][0], v[2][0]),
             Vector3(v[0][1], v[1][1], v[2][1]),
             Vector3(v[0][2], v[1][2], v[2][2])))
}
