// The record a stroke or a fill travels in on the web page: the points and
// the style the sketch gave, back to back as floats, and the walk that turns
// a run of them into the vertices the renderer would have drawn. The Mac
// writes the records (`WebGraphRecorder`) and the page's player part, this
// file compiled to WebAssembly, reads them; the Mac also reads them in its
// tests, against its own vertices, so the two sides cannot drift.
//
// A record is a header of `WebSourceLayout.headerFloats`, then its body:
//
//     kind, flags, count, fringe, ctmScale, t0, t1, t2, t3, t4, t5, 0
//
// `kind` is a stroke (0), a convex fan (1), a tessellated fill (2), or one run
// of a stroke under a medium (3), a ribbon;
// `count` the points of a stroke or a fan, or the contours of a tessellated
// fill; `fringe` and `ctmScale` the stroke's anti-aliasing band in its own
// units and the transform's scale (0 for a fill); `t0...t5` the transform's
// two axis columns and its translation, as a shape record carries them. A
// stroke's body is its points (x, y each), then one half-width or one per
// point, then one color (r, g, b, a) or one per point, as the flags say. A
// fan's body is its points then its color. A tessellated fill's body is its
// contour lengths, then every contour's points in order, then its color. A
// ribbon's body is a stroke's, then a fraction along the whole path per point
// when the run is a dash, then under ink the pen's pace (one, or one per
// point, as the flags say), then the whole path's length (-1 when the run is
// the whole path) and the stroke's seed.

package enum WebSourceLayout {
    package static let headerFloats = 12

    /// The header's columns.
    package static let kindColumn = 0
    package static let flagsColumn = 1
    package static let countColumn = 2
    package static let fringeColumn = 3
    package static let ctmScaleColumn = 4
    package static let transformColumn = 5

    package static let strokeKind: Float = 0
    package static let fanKind: Float = 1
    package static let tessellatedKind: Float = 2
    package static let ribbonKind: Float = 3

    /// The flag bits. A join and a cap are `StrokeExpanderJoin` and
    /// `StrokeExpanderCap` raw values in their two-bit fields.
    package static let closedFlag = 1
    package static let joinShift = 1
    package static let capShift = 3
    package static let widthsPerPointFlag = 32
    package static let colorsPerPointFlag = 64
    package static let nonZeroFlag = 128
    package static let fractionsFlag = 256
    /// A ribbon under ink carries the pen's pace: one value for the run, or one
    /// per point.
    package static let paceFlag = 512
    package static let pacesPerPointFlag = 1024

    /// The floats a stroke of `n` points takes.
    package static func strokeFloats(points n: Int, widthsPerPoint: Bool, colorsPerPoint: Bool) -> Int {
        headerFloats + 2 * n + (widthsPerPoint ? n : 1) + (colorsPerPoint ? 4 * n : 4)
    }

    /// The floats a ribbon run of `n` points takes.
    package static func ribbonFloats(points n: Int, widthsPerPoint: Bool, colorsPerPoint: Bool,
                                     fractions: Bool, paces: Int = 0) -> Int {
        strokeFloats(points: n, widthsPerPoint: widthsPerPoint, colorsPerPoint: colorsPerPoint)
            + (fractions ? n : 0) + paces + 2
    }

    /// How many pace values a ribbon record with `flags` carries for `n`
    /// points: none, one, or one per point.
    package static func paceCount(flags: Int, points n: Int) -> Int {
        flags & pacesPerPointFlag != 0 ? n : (flags & paceFlag != 0 ? 1 : 0)
    }

    /// The floats a fan of `n` points takes.
    package static func fanFloats(points n: Int) -> Int {
        headerFloats + 2 * n + 4
    }

    /// The floats a tessellated fill of the given contour lengths takes.
    package static func tessellatedFloats(contours lengths: [Int]) -> Int {
        var points = 0
        for length in lengths { points += length }
        return headerFloats + lengths.count + 2 * points + 4
    }

    /// The columns of the records in `floats` whose value is part of the cast
    /// rather than its motion (the kind, the flags, the count, and a
    /// tessellated fill's contour lengths), relative to the run's start, and
    /// the number of records, or `nil` where a record is malformed.
    package static func structure(of floats: UnsafeBufferPointer<Float>) -> (columns: [Int], records: Int)? {
        var columns: [Int] = []
        var at = 0
        var records = 0
        while at < floats.count {
            guard let length = recordFloats(floats, at: at) else { return nil }
            columns.append(at + kindColumn)
            columns.append(at + flagsColumn)
            columns.append(at + countColumn)
            if floats[at + kindColumn] == tessellatedKind {
                let contours = Int(floats[at + countColumn])
                for c in 0..<contours { columns.append(at + headerFloats + c) }
            }
            at += length
            records += 1
        }
        return (columns, records)
    }

    /// The length of the record at `at`, or `nil` when it does not fit.
    package static func recordFloats(_ floats: UnsafeBufferPointer<Float>, at: Int) -> Int? {
        guard at + headerFloats <= floats.count else { return nil }
        let kind = floats[at + kindColumn]
        let flags = Int(floats[at + flagsColumn])
        let count = Int(floats[at + countColumn])
        guard count >= 0 else { return nil }
        var length: Int
        if kind == strokeKind {
            length = strokeFloats(points: count, widthsPerPoint: flags & widthsPerPointFlag != 0,
                                  colorsPerPoint: flags & colorsPerPointFlag != 0)
        } else if kind == ribbonKind {
            length = ribbonFloats(points: count, widthsPerPoint: flags & widthsPerPointFlag != 0,
                                  colorsPerPoint: flags & colorsPerPointFlag != 0,
                                  fractions: flags & fractionsFlag != 0,
                                  paces: paceCount(flags: flags, points: count))
        } else if kind == fanKind {
            length = fanFloats(points: count)
        } else if kind == tessellatedKind {
            guard at + headerFloats + count <= floats.count else { return nil }
            var lengths: [Int] = []
            lengths.reserveCapacity(count)
            for c in 0..<count {
                let n = Int(floats[at + headerFloats + c])
                guard n >= 0 else { return nil }
                lengths.append(n)
            }
            length = tessellatedFloats(contours: lengths)
        } else {
            return nil
        }
        guard at + length <= floats.count else { return nil }
        return length
    }
}

/// One vertex as the renderer's triangle path holds it: the position in
/// canvas space, the anti-aliasing coverage (0 on a fill), and the straight
/// color with its alpha.
package typealias WebSourceVertex = (x: Float, y: Float, coverage: Float, color: SIMD4<Float>)

package enum WebSourceExpander {
    /// Expand every record in `floats` into the vertices the renderer would
    /// have drawn, in order, each record's points placed by its transform.
    /// Returns the number of records expanded, or `nil` when a record is
    /// malformed (nothing after it is emitted).
    package static func expand(_ floats: UnsafeBufferPointer<Float>,
                               emit: (WebSourceVertex) -> Void) -> Int? {
        var at = 0
        var records = 0
        while at < floats.count {
            guard let length = WebSourceLayout.recordFloats(floats, at: at) else { return nil }
            expandRecord(floats, at: at, emit: emit)
            at += length
            records += 1
        }
        return records
    }

    /// The vertices of the one record at `at`, which `recordFloats` has
    /// already found well formed.
    static func expandRecord(_ floats: UnsafeBufferPointer<Float>, at: Int,
                             emit: (WebSourceVertex) -> Void) {
        let h = WebSourceLayout.headerFloats
        let kind = floats[at + WebSourceLayout.kindColumn]
        let flags = Int(floats[at + WebSourceLayout.flagsColumn])
        let count = Int(floats[at + WebSourceLayout.countColumn])
        let tc = at + WebSourceLayout.transformColumn
        let t0 = floats[tc], t1 = floats[tc + 1], t2 = floats[tc + 2]
        let t3 = floats[tc + 3], t4 = floats[tc + 4], t5 = floats[tc + 5]
        // The identity is applied as no transform at all, as the renderer
        // applies it, so a point under it keeps its bits.
        let identity = t0 == 1 && t1 == 0 && t2 == 0 && t3 == 1 && t4 == 0 && t5 == 0
        func place(_ p: SIMD2<Float>) -> SIMD2<Float> {
            identity ? p : SIMD2<Float>(t0 * p.x + t2 * p.y + t4, t1 * p.x + t3 * p.y + t5)
        }
        func point(_ i: Int) -> Point2D {
            Point2D(Double(floats[i]), Double(floats[i + 1]))
        }
        func color(_ i: Int) -> SIMD4<Float> {
            SIMD4<Float>(floats[i], floats[i + 1], floats[i + 2], floats[i + 3])
        }

        if kind == WebSourceLayout.strokeKind {
            var pts: [Point2D] = []
            pts.reserveCapacity(count)
            for i in 0..<count { pts.append(point(at + h + 2 * i)) }
            var cursor = at + h + 2 * count
            var hws: [Double] = []
            hws.reserveCapacity(count)
            if flags & WebSourceLayout.widthsPerPointFlag != 0 {
                for i in 0..<count { hws.append(Double(floats[cursor + i])) }
                cursor += count
            } else {
                let w = Double(floats[cursor])
                for _ in 0..<count { hws.append(w) }
                cursor += 1
            }
            var cols: [SIMD4<Float>] = []
            cols.reserveCapacity(count)
            if flags & WebSourceLayout.colorsPerPointFlag != 0 {
                for i in 0..<count { cols.append(color(cursor + 4 * i)) }
            } else {
                let c = color(cursor)
                for _ in 0..<count { cols.append(c) }
            }
            let join = StrokeExpanderJoin(rawValue: UInt8((flags >> WebSourceLayout.joinShift) & 3)) ?? .miter
            let cap = StrokeExpanderCap(rawValue: UInt8((flags >> WebSourceLayout.capShift) & 3)) ?? .butt
            strokeVertices(pts, closed: flags & WebSourceLayout.closedFlag != 0,
                           halfWidths: hws, colors: cols,
                           fringe: Double(floats[at + WebSourceLayout.fringeColumn]),
                           ctmScale: Double(floats[at + WebSourceLayout.ctmScaleColumn]),
                           join: join, cap: cap) { v, _ in
                let p = place(v.position)
                emit((p.x, p.y, v.coverage, v.color))
            }
        } else if kind == WebSourceLayout.fanKind {
            let c = color(at + h + 2 * count)
            func vertex(_ i: Int) {
                let p = place(point(at + h + 2 * i).simd2)
                emit((p.x, p.y, 0, c))
            }
            FillExpander.fan(count: count) { a, b, d in
                vertex(a); vertex(b); vertex(d)
            }
        } else if kind == WebSourceLayout.tessellatedKind {
            var contours: [[Point2D]] = []
            contours.reserveCapacity(count)
            var cursor = at + h + count
            for c in 0..<count {
                let n = Int(floats[at + h + c])
                var contour: [Point2D] = []
                contour.reserveCapacity(n)
                for i in 0..<n { contour.append(point(cursor + 2 * i)) }
                cursor += 2 * n
                contours.append(contour)
            }
            let c = color(cursor)
            let triangles = FillExpander.triangulate(contours, nonZero: flags & WebSourceLayout.nonZeroFlag != 0)
            for t in triangles {
                let p = place(t.simd2)
                emit((p.x, p.y, 0, c))
            }
        }
    }

    /// The stroke expander behind one call that is never inlined, which both
    /// the stroke records and the ribbons go through, so the page's module
    /// holds one copy of the expander's body rather than one per caller.
    @inline(never)
    static func strokeVertices(_ pts: [Point2D], closed: Bool, halfWidths hws: [Double],
                               colors cols: [SIMD4<Float>], fringe fw: Double, ctmScale: Double,
                               join: StrokeExpanderJoin, cap: StrokeExpanderCap,
                               emit: (StrokeVertex, Int) -> Void) {
        StrokeExpander.expand(pts, closed: closed, halfWidths: hws, colors: cols, fringe: fw,
                              ctmScale: ctmScale, join: join, cap: cap, emit: emit)
    }

    /// The floats a ribbon vertex takes in `expandRibbons`' output: the
    /// position, the coverage, the color, then the ribbon's own coordinates
    /// (`RibbonFrame`: the distance along and the place across), the
    /// half-width of its path vertex, the fraction along, the stroke's seed,
    /// the length the fraction divides by, and the pen's pace (0 under any
    /// medium but ink). It is the pair a medium stroke's vertex is on the
    /// renderer, laid end to end.
    package static let ribbonVertexFloats = 14

    /// Expand the ribbon runs of one stroke under a medium into the vertices
    /// the renderer draws for it, `ribbonVertexFloats` each into `out`: every
    /// run's core triangles, then every run's fringe triangles (a corner at no
    /// coverage), as the coat draw wants them, each vertex placed by its
    /// record's transform and measured in the record's own space. Returns the
    /// runs expanded, or `nil` when a record is malformed or not a ribbon
    /// (nothing is written then).
    package static func expandRibbons(_ floats: UnsafeBufferPointer<Float>, into out: inout [Float]) -> Int? {
        var cores: [Float] = []
        var fringes: [Float] = []
        var at = 0
        var runs = 0
        while at < floats.count {
            guard at + WebSourceLayout.headerFloats <= floats.count,
                  floats[at + WebSourceLayout.kindColumn] == WebSourceLayout.ribbonKind,
                  let length = WebSourceLayout.recordFloats(floats, at: at) else { return nil }
            expandRibbon(floats, at: at, cores: &cores, fringes: &fringes)
            at += length
            runs += 1
        }
        out.append(contentsOf: cores)
        out.append(contentsOf: fringes)
        return runs
    }

    /// The triangles of the one ribbon record at `at`, into `cores` and
    /// `fringes`.
    static func expandRibbon(_ floats: UnsafeBufferPointer<Float>, at: Int,
                             cores: inout [Float], fringes: inout [Float]) {
        let h = WebSourceLayout.headerFloats
        let flags = Int(floats[at + WebSourceLayout.flagsColumn])
        let count = Int(floats[at + WebSourceLayout.countColumn])
        let tc = at + WebSourceLayout.transformColumn
        let t0 = floats[tc], t1 = floats[tc + 1], t2 = floats[tc + 2]
        let t3 = floats[tc + 3], t4 = floats[tc + 4], t5 = floats[tc + 5]
        let identity = t0 == 1 && t1 == 0 && t2 == 0 && t3 == 1 && t4 == 0 && t5 == 0
        var pts: [Point2D] = []
        pts.reserveCapacity(count)
        for i in 0..<count { pts.append(Point2D(Double(floats[at + h + 2 * i]), Double(floats[at + h + 2 * i + 1]))) }
        var cursor = at + h + 2 * count
        var hws: [Double] = []
        hws.reserveCapacity(count)
        let widths = flags & WebSourceLayout.widthsPerPointFlag != 0
        for i in 0..<count { hws.append(Double(floats[cursor + (widths ? i : 0)])) }
        cursor += widths ? count : 1
        var cols: [SIMD4<Float>] = []
        cols.reserveCapacity(count)
        let colors = flags & WebSourceLayout.colorsPerPointFlag != 0
        for i in 0..<count {
            let c = cursor + (colors ? 4 * i : 0)
            cols.append(SIMD4<Float>(floats[c], floats[c + 1], floats[c + 2], floats[c + 3]))
        }
        cursor += colors ? 4 * count : 4
        var fractions: [Double]? = nil
        if flags & WebSourceLayout.fractionsFlag != 0 {
            var ts: [Double] = []
            ts.reserveCapacity(count)
            for i in 0..<count { ts.append(Double(floats[cursor + i])) }
            fractions = ts
            cursor += count
        }
        // The pen's pace: none under the other media (0 on every vertex), one
        // value for the run, or one per point.
        let paceCount = WebSourceLayout.paceCount(flags: flags, points: count)
        var paces: [Float] = []
        paces.reserveCapacity(count)
        for i in 0..<count { paces.append(paceCount == 0 ? 0 : floats[cursor + (paceCount == 1 ? 0 : i)]) }
        cursor += paceCount
        let whole: Double? = floats[cursor] >= 0 ? Double(floats[cursor]) : nil
        let seed = floats[cursor + 1]
        let closed = flags & WebSourceLayout.closedFlag != 0
        let fw = Double(floats[at + WebSourceLayout.fringeColumn])
        let frame = RibbonFrame(pts, closed: closed, halfWidths: hws, fringe: fw,
                                fractions: fractions, wholeLength: whole)
        let lengthF = Float(frame.length)
        let join = StrokeExpanderJoin(rawValue: UInt8((flags >> WebSourceLayout.joinShift) & 3)) ?? .miter
        let cap = StrokeExpanderCap(rawValue: UInt8((flags >> WebSourceLayout.capShift) & 3)) ?? .butt
        // The expander hands each triangle's three corners in order; they are
        // held here until the third, which decides the triangle's list.
        let none: StrokeVertex = (SIMD2<Float>(0, 0), 0, SIMD4<Float>(0, 0, 0, 0), 0)
        var c0 = none, c1 = none
        var s0 = 0, s1 = 0
        var held = 0
        func put(_ u: StrokeVertex, _ src: Int, wraps: Bool, into list: inout [Float]) {
            let c = frame.coordinates(Point2D(Double(u.position.x), Double(u.position.y)),
                                      offset: u.offset, source: src, wraps: wraps)
            if identity {
                list.append(u.position.x)
                list.append(u.position.y)
            } else {
                list.append(t0 * u.position.x + t2 * u.position.y + t4)
                list.append(t1 * u.position.x + t3 * u.position.y + t5)
            }
            list.append(u.coverage)
            list.append(u.color.x); list.append(u.color.y); list.append(u.color.z); list.append(u.color.w)
            list.append(Float(c.arc)); list.append(c.across); list.append(Float(hws[src]))
            list.append(c.along); list.append(seed); list.append(lengthF); list.append(paces[src])
        }
        strokeVertices(pts, closed: closed, halfWidths: hws, colors: cols, fringe: fw,
                       ctmScale: Double(floats[at + WebSourceLayout.ctmScaleColumn]),
                       join: join, cap: cap) { v, source in
            if held == 0 { c0 = v; s0 = source; held = 1; return }
            if held == 1 { c1 = v; s1 = source; held = 2; return }
            held = 0
            let wraps = frame.wraps(s0, s1, source)
            if c0.coverage <= 0 || c1.coverage <= 0 || v.coverage <= 0 {
                put(c0, s0, wraps: wraps, into: &fringes)
                put(c1, s1, wraps: wraps, into: &fringes)
                put(v, source, wraps: wraps, into: &fringes)
            } else {
                put(c0, s0, wraps: wraps, into: &cores)
                put(c1, s1, wraps: wraps, into: &cores)
                put(v, source, wraps: wraps, into: &cores)
            }
        }
    }
}
