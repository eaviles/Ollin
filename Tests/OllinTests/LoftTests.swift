import Foundation
import Testing
@testable import Ollin

/// A surface through several flat shapes laid along a 3D path (`Mesh.loft`):
/// every section exact at its station, sections of one shape the sweep byte
/// for byte, straight and smooth blends against their arithmetic, the seam
/// turned to the nearest start, caps that seal the solid, and the uvs.
/// GPU-free.
struct LoftTests {

    // MARK: - Helpers

    /// A path that bends, rises, and turns.
    private var bending: Curve3D {
        Curve3D(curveThrough: [Vector3(0, 0, 0), Vector3(2, 1, 0), Vector3(3, 3, 2),
                               Vector3(1, 4, 3), Vector3(-1, 3, 1)], segments: 10)
    }

    /// A straight path along +z from z = 0 to z = 1 in ten steps, so a
    /// section's own x and y are the mesh's.
    private var straight: Curve3D {
        Curve3D((0...10).map { Vector3(0, 0, Double($0) / 10) })
    }

    /// The wall vertices grouped by row (consecutive vertices sharing a `v`),
    /// in order, caps left out.
    private func rows(of mesh: Mesh) -> [(v: Double, points: [Vector3])] {
        var rows: [(v: Double, points: [Vector3])] = []
        for (p, uv) in zip(mesh.positions, mesh.uvs) {
            if let last = rows.last, last.v == uv.y {
                rows[rows.count - 1].points.append(p)
            } else {
                rows.append((uv.y, [p]))
            }
        }
        return rows
    }

    /// A point in a frame's plane: its offsets along the normal and binormal.
    private func local(_ p: Vector3, in frame: Curve3D.Frame) -> Vector2 {
        let d = p - frame.position
        return Vector2(d.dot(frame.normal), d.dot(frame.binormal))
    }

    /// The distance from `p` to the closed polygon `ring`.
    private func distance(_ p: Vector2, toRing ring: [Vector2]) -> Double {
        var best = Double.infinity
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            let ab = b - a
            let t = ab.lengthSquared > 0 ? min(max((p - a).dot(ab) / ab.lengthSquared, 0), 1) : 0
            best = min(best, (p - (a + ab * t)).length)
        }
        return best
    }

    private func square(_ side: Double) -> Shape {
        Shape(Profile.rectangle(width: side, height: side))
    }

    private func circle(_ radius: Double, segments: Int = 32) -> Shape {
        Shape(Profile.ellipse(radiusX: radius, radiusY: radius, segments: segments))
    }

    /// Every edge of every triangle keyed by its two ends' positions
    /// (quantized), counted with its direction: a closed, consistently
    /// oriented surface has every edge once each way.
    private func boundaryEdges(of mesh: Mesh) -> Int {
        func key(_ p: Vector3) -> String {
            "\(Int((p.x * 1e8).rounded())),\(Int((p.y * 1e8).rounded())),\(Int((p.z * 1e8).rounded()))"
        }
        var count: [String: Int] = [:]
        var k = 0
        while k + 2 < mesh.indices.count {
            let a = key(mesh.positions[Int(mesh.indices[k])])
            let b = key(mesh.positions[Int(mesh.indices[k + 1])])
            let c = key(mesh.positions[Int(mesh.indices[k + 2])])
            for (from, to) in [(a, b), (b, c), (c, a)] where from != to {
                count[from + ">" + to, default: 0] += 1
            }
            k += 3
        }
        var open = 0
        for (edge, n) in count {
            let parts = edge.split(separator: ">")
            let back = String(parts[1]) + ">" + String(parts[0])
            if count[back] != n { open += 1 }
        }
        return open
    }

    // MARK: - Sections at their stations

    /// Every section is laid exactly at its station, corners and all, sized
    /// and turned by what `scale` and `twist` say there: a square, a star,
    /// and a circle at 0, 0.37, and 1 along a bending path, the middle one
    /// between two of the path's own points.
    @Test func everySectionIsLaidExactlyAtItsStation() {
        let path = bending
        let sections = [square(0.6), Shape(Profile.star(points: 5, outerRadius: 0.4, innerRadius: 0.2)),
                        circle(0.3, segments: 24)]
        let stations = [0.0, 0.37, 1.0]
        #expect(!path.walked.contains { abs($0 / path.length - 0.37) < 1e-6 }, "0.37 is between two points")
        let scale: (Double) -> Double = { 1 - 0.3 * $0 }
        let twist: (Double) -> Double = { 0.7 * $0 }
        let mesh = Mesh.loft(sections, along: path, at: stations, scale: scale, twist: twist, capped: false)
        let rows = rows(of: mesh)
        for (section, s) in zip(sections, stations) {
            let frame = path.frame(at: s)
            let size = scale(s), c = cos(twist(s)), sn = sin(twist(s))
            let placed = section.contours[0].points.map { p in
                Vector2((p.x * c - p.y * sn) * size, (p.x * sn + p.y * c) * size)
            }
            guard let row = rows.first(where: { abs($0.v - s) < 1e-12 }) else {
                Issue.record("no row at station \(s)")
                continue
            }
            // Every corner of the section is a vertex of the row, and every
            // vertex of the row lies on the section's outline, in its plane.
            for corner in placed {
                let hit = row.points.contains { ($0 - frame.point(corner)).length < 1e-12 }
                #expect(hit, "station \(s): corner \(corner) missing")
            }
            for p in row.points {
                #expect(abs((p - frame.position).dot(frame.tangent)) < 1e-12)
                #expect(distance(local(p, in: frame), toRing: placed) < 1e-12)
            }
        }
    }

    /// Sections of one shape are that shape's sweep, byte for byte: an open
    /// path with the stations on three of its points, and a closed path with
    /// the default stations landing on its points, with `scale` and `twist`,
    /// smoothed or not.
    @Test func sectionsOfOneShapeAreThatShapesSweep() {
        let outer = Profile.star(points: 5, outerRadius: 1, innerRadius: 0.5)
        let hole = Array(Profile.rectangle(width: 0.3, height: 0.3).reversed())
        let shape = Shape(outer: outer, holes: [hole])
        let scale: (Double) -> Double = { 1 - 0.4 * $0 }
        let twist: (Double) -> Double = { 0.9 * $0 }
        func same(_ a: Mesh, _ b: Mesh) -> Bool {
            a.positions == b.positions && a.normals == b.normals && a.uvs == b.uvs && a.indices == b.indices
        }
        let open = bending
        let at = [0, 7, open.points.count - 1].map { open.walked[$0] / open.length }
        let swept = Mesh.sweep(shape, along: open, scale: scale, twist: twist)
        for smoothed in [false, true] {
            let lofted = Mesh.loft([shape, shape, shape], along: open, at: at, smoothed: smoothed,
                                   scale: scale, twist: twist)
            #expect(same(lofted, swept), "open path, smoothed \(smoothed)")
        }
        let loop = Curve3D((0..<300).map { k -> Vector3 in
            let t = Double(k) / 300 * .tau
            return Vector3(2 * cos(t), 0.5 * sin(2 * t), 2 * sin(t))
        }, closed: true)
        let round = Mesh.sweep(shape, along: loop, scale: { 1 + 0.2 * sin($0 * .tau) }, twist: { $0 * .tau })
        let thirds = [0, 100, 200].map { loop.walked[$0] / loop.length }
        for smoothed in [false, true] {
            let lofted = Mesh.loft([shape, shape, shape], along: loop, at: thirds, smoothed: smoothed,
                                   scale: { 1 + 0.2 * sin($0 * .tau) }, twist: { $0 * .tau })
            #expect(same(lofted, round), "closed path, smoothed \(smoothed)")
        }
        #expect(round.isClosed == true && swept.isClosed == true)
    }

    // MARK: - The blend

    /// Two sections blend straight: between a square of side 1 and one of
    /// side 2, the ring a fraction `f` along is the square of side `1 + f`.
    /// A third section that is the halfway blend of the two changes
    /// nothing, smoothed or not.
    @Test func twoSectionsBlendStraightAndAMidwaySectionChangesNothing() {
        let two = Mesh.loft([square(1), square(2)], along: straight, capped: false)
        let rows = rows(of: two)
        #expect(rows.count == 11)
        for row in rows {
            let side = 1 + row.v
            for p in row.points {
                #expect(abs(max(abs(p.x), abs(p.y)) - side / 2) < 1e-12, "v \(row.v): \(p)")
                #expect(abs(p.z - row.v) < 1e-12)
            }
        }
        for smoothed in [false, true] {
            let three = Mesh.loft([square(1), square(1.5), square(2)], along: straight,
                                  at: [0, 0.5, 1], smoothed: smoothed, capped: false)
            #expect(three.positions.count == two.positions.count)
            for (a, b) in zip(three.positions, two.positions) {
                #expect((a - b).length < 1e-12, "smoothed \(smoothed): \(a) against \(b)")
            }
        }
    }

    /// Three unevenly spaced sections: straight, the ring a fifth of the way
    /// is the two-fifths blend of the first two; smoothed, it is the cubic
    /// through all three (the tangent at an end is the chord to its
    /// neighbor, inside it is half the chord across both), and both are
    /// exact at the stations.
    @Test func aSmoothLoftCurvesThroughThreeSectionsAndAStraightOneDoesNot() {
        let sides = [1.0, 1.2, 2.0]
        for smoothed in [false, true] {
            let mesh = Mesh.loft(sides.map(square), along: straight, at: [0, 0.5, 1],
                                 smoothed: smoothed, capped: false)
            let rows = rows(of: mesh)
            func side(at v: Double) -> Double {
                let row = rows.first { abs($0.v - v) < 1e-12 }!
                return row.points.map { max(abs($0.x), abs($0.y)) }.max()! * 2
            }
            #expect(abs(side(at: 0) - 1) < 1e-12 && abs(side(at: 0.5) - 1.2) < 1e-12 && abs(side(at: 1) - 2) < 1e-12)
            if smoothed {
                let t = 0.4
                let h01 = -2 * t * t * t + 3 * t * t, h10 = t * t * t - 2 * t * t + t, h11 = t * t * t - t * t
                let want = 1 + 0.2 * h01 + 0.2 * h10 + 0.5 * h11
                #expect(abs(side(at: 0.2) - want) < 1e-12, "smoothed: \(side(at: 0.2)) against \(want)")
                #expect(abs(side(at: 0.2) - 1.08) > 0.01)
            } else {
                #expect(abs(side(at: 0.2) - 1.08) < 1e-12, "straight: \(side(at: 0.2))")
            }
        }
    }

    /// On a closed path the last section blends back into the first: three
    /// squares at 0, 1/3, and 2/3 of a loop, read at 5/6, are halfway from
    /// the third back to the first, and the loop's closing row is the first
    /// section exactly.
    @Test func aClosedPathBlendsTheLastSectionBackIntoTheFirst() {
        let loop = Curve3D((0..<300).map { k -> Vector3 in
            let t = Double(k) / 300 * .tau
            return Vector3(3 * cos(t), 0, 3 * sin(t))
        }, closed: true)
        let mesh = Mesh.loft([square(1), square(2), square(1.5)], along: loop, smoothed: false)
        let rows = rows(of: mesh)
        func side(at v: Double) -> Double {
            let row = rows.first { abs($0.v - v) < 1e-9 }!
            let frame = loop.frame(at: v)
            return row.points.map { let l = local($0, in: frame); return max(abs(l.x), abs(l.y)) }.max()! * 2
        }
        #expect(abs(side(at: 5.0 / 6) - 1.25) < 1e-9)
        #expect(abs(side(at: 1.0 / 6) - 1.5) < 1e-9)
        #expect(abs(side(at: 1) - 1) < 1e-12)
        #expect(mesh.isClosed == true)
    }

    // MARK: - The seam

    /// A section's seam turns to where it sits nearest the one before: a
    /// square and the same square a quarter turn round, its point list
    /// started one corner on, make a straight prism; turned 20° instead,
    /// every column travels about 20° and none winds the other way round.
    @Test func theSeamTurnsToTheNearestStart() {
        let a = Profile.rectangle(width: 1, height: 1)
        func turned(_ angle: Double) -> [Vector2] {
            let c = cos(angle), s = sin(angle)
            let r = a.map { Vector2($0.x * c - $0.y * s, $0.x * s + $0.y * c) }
            return Array(r[1...]) + [r[0]]
        }
        let prism = Mesh.loft([a, turned(.pi / 2)], along: straight, capped: false)
        let prismRows = rows(of: prism)
        for row in prismRows {
            for (p, q) in zip(row.points, prismRows[0].points) {
                #expect(abs(p.x - q.x) < 1e-12 && abs(p.y - q.y) < 1e-12, "v \(row.v): \(p) against \(q)")
            }
        }
        let skewed = Mesh.loft([a, turned(0.35)], along: straight, capped: false)
        let skewRows = rows(of: skewed)
        for (p, q) in zip(skewRows[skewRows.count - 1].points, skewRows[0].points) {
            let travel = abs(atan2(p.x * q.y - p.y * q.x, p.x * q.x + p.y * q.y))
            #expect(travel < 0.45, "a column traveled \(travel) rad")
        }
    }

    // MARK: - Caps and closure

    /// Capped, a loft is a sealed solid: every edge is shared by two
    /// triangles facing the same way, the caps meeting the walls vertex for
    /// vertex, and the mesh says it is closed. Uncapped it is open and says
    /// so, as does a sweep now, and a loft of open outlines is a sheet.
    @Test func aCappedLoftIsSealedAndSaysSo() {
        let sections = [square(0.8), Shape(Profile.star(points: 6, outerRadius: 0.5, innerRadius: 0.3)),
                        circle(0.3)]
        let sealed = Mesh.loft(sections, along: bending, at: [0, 0.4, 1])
        #expect(boundaryEdges(of: sealed) == 0)
        #expect(sealed.isClosed == true)
        let open = Mesh.loft(sections, along: bending, at: [0, 0.4, 1], capped: false)
        #expect(boundaryEdges(of: open) > 0)
        #expect(open.isClosed == false)
        let sheet = Mesh.loft([Shape(contours: [Contour([Vector2(-1, 0), Vector2(0, -0.5), Vector2(1, 0)], closed: false)]),
                               Shape(contours: [Contour([Vector2(-2, 0), Vector2(0, -1), Vector2(2, 0)], closed: false)])],
                              along: bending)
        #expect(sheet.isClosed == false)
        // Three points, the middle one a sharp corner split in two: four columns a row.
        #expect(sheet.positions.count == 4 * bending.points.count)
        #expect(Mesh.sweep(sections[0], along: bending).isClosed == true)
        #expect(Mesh.sweep(sections[0], along: bending, capped: false).isClosed == false)
    }

    /// A contour some section lacks is left out: a section with a hole lofted
    /// to one without makes the outer wall alone.
    @Test func aContourSomeSectionLacksIsLeftOut() {
        let holed = Shape(outer: Profile.rectangle(width: 1, height: 1),
                          holes: [Array(Profile.rectangle(width: 0.3, height: 0.3).reversed())])
        let mesh = Mesh.loft([holed, square(1)], along: straight, capped: false)
        // Four sharp corners, two columns each: eight columns a row, eleven rows.
        #expect(mesh.positions.count == 8 * 11)
    }

    // MARK: - Edges and uvs

    /// A corner sharp on one section keeps its edge down the loft, hard where
    /// the section is a square (its two columns' normals a right angle
    /// apart) and all but gone where the other section is a circle.
    @Test func aCornerKeepsItsEdgeWhereItIsSharpAndFadesWhereItIsNot() {
        let mesh = Mesh.loft([square(1), circle(0.5, segments: 32)], along: straight, capped: false)
        let rows = rows(of: mesh)
        let first = rows[0], last = rows[rows.count - 1]
        var splits = 0
        for c in 0..<(first.points.count - 1) where (first.points[c] - first.points[c + 1]).length < 1e-12 {
            splits += 1
            let n0 = mesh.normals[c], n1 = mesh.normals[c + 1]
            // Not a right angle: the wall tapers toward the circle, so both
            // normals lean along the path by the same amount.
            #expect(n0.dot(n1) < 0.5, "a square's corner: \(n0) and \(n1)")
            let start = (rows.count - 1) * first.points.count
            let m0 = mesh.normals[start + c], m1 = mesh.normals[start + c + 1]
            #expect(m0.dot(m1) > cos(0.25), "at the circle: \(m0) and \(m1)")
            #expect((last.points[c] - last.points[c + 1]).length < 1e-12)
        }
        #expect(splits == 3, "three corners split inside the row (the fourth is the seam)")
    }

    /// `u` runs round each ring by that ring's own walked length, 0 and 1 at
    /// the seam, and `v` is the fraction along the path, the inserted
    /// station's row included.
    @Test func uvsRunByLengthRoundEachRingAndAlongThePath() {
        let path = bending
        let mesh = Mesh.loft([square(1), circle(0.5)], along: path, at: [0, 0.37], capped: false)
        let rows = rows(of: mesh)
        #expect(rows.count == path.points.count + 1)
        #expect(rows.contains { $0.v == 0.37 })
        var k = 0
        for row in rows {
            let width = row.points.count
            let us = (0..<width).map { mesh.uvs[k + $0].x }
            #expect(us[0] == 0 && us[width - 1] == 1)
            // Walked length round the row against its `u`.
            var walked = [0.0]
            for c in 1..<width { walked.append(walked[c - 1] + (row.points[c] - row.points[c - 1]).length) }
            for c in 0..<width {
                #expect(abs(us[c] - walked[c] / walked[width - 1]) < 1e-9, "v \(row.v), column \(c)")
            }
            k += width
        }
    }
}
