// The two ways a fill becomes triangles: the fan a convex polygon takes, and
// the tessellator (libtess2) a shape with concavities or holes goes through.
// The renderer and the web page's player part share both, so a fill that
// travels as its contour points is triangulated on the page exactly as the
// Mac triangulated it.

import CLibtess2

package enum FillExpander {
    /// The triangle fan that fills a convex polygon of `n` points: the triangle
    /// `(0, i, i + 1)` for each `i`, as indices into the polygon, in the order
    /// the renderer emits them.
    @inlinable
    package static func fan(count n: Int, emit: (Int, Int, Int) -> Void) {
        guard n >= 3 else { return }
        for i in 1..<(n - 1) { emit(0, i, i + 1) }
    }

    /// The triangles that fill `contours` under the winding rule: a flat list of
    /// triangle vertices (every three is one triangle). The contours are closed
    /// and each holds at least three points; the caller has already dropped the
    /// open ones. They are cleaned first (`cleaned`), so a ring of coincident
    /// points or one lying along a line never reaches the tessellator. Empty when
    /// nothing is left to fill or the tessellator refuses.
    package static func triangulate(_ contours: [[Point2D]], nonZero: Bool) -> [Point2D] {
        guard !contours.isEmpty else { return [] }
        let contours = cleaned(contours, epsilon: cleaningEpsilon(for: contours))
        guard !contours.isEmpty else { return [] }
        guard let tess = tessNewTess(nil) else { return [] }
        defer { tessDeleteTess(tess) }

        // Feed each contour as a flat array of (x, y) floats.
        for contour in contours {
            var coords = [TESSreal]()
            coords.reserveCapacity(contour.count * 2)
            for p in contour {
                coords.append(TESSreal(p.x))
                coords.append(TESSreal(p.y))
            }
            coords.withUnsafeBufferPointer { buffer in
                tessAddContour(tess, 2, buffer.baseAddress,
                               Int32(MemoryLayout<TESSreal>.stride * 2),
                               Int32(contour.count))
            }
        }

        // Tessellate into triangles (polySize 3), 2D, with the fill rule.
        let rule = nonZero ? TESS_WINDING_NONZERO : TESS_WINDING_ODD
        let ok = tessTesselate(tess,
                               Int32(rule.rawValue),
                               Int32(TESS_POLYGONS.rawValue),
                               3, 2, nil)
        guard ok == 1,
              let verts = tessGetVertices(tess),
              let elements = tessGetElements(tess) else { return [] }

        let vertexCount = Int(tessGetVertexCount(tess))
        let elementCount = Int(tessGetElementCount(tess))
        var triangles = [Point2D]()
        triangles.reserveCapacity(elementCount * 3)
        for e in 0..<elementCount {
            for k in 0..<3 {
                let index = Int(elements[e * 3 + k])
                // Skip a degenerate triangle (libtess2 marks a missing vertex
                // with an out-of-range index).
                guard index >= 0, index < vertexCount else { continue }
                triangles.append(Point2D(Double(verts[index * 2]),
                                         Double(verts[index * 2 + 1])))
            }
        }
        return triangles
    }

    /// The distance under which two consecutive points of a contour are one point to
    /// the tessellator: a millionth of the largest coordinate in play, which is below
    /// anything a pixel shows at any scale a sketch draws at, and never less than a
    /// billionth of a point.
    package static func cleaningEpsilon(for contours: [[Point2D]]) -> Double {
        var magnitude = 1.0
        for contour in contours {
            for p in contour {
                let m = max(p.x < 0 ? -p.x : p.x, p.y < 0 ? -p.y : p.y)
                if m > magnitude { magnitude = m }
            }
        }
        return max(magnitude * 1e-6, 1e-9)
    }

    /// The contours as the tessellator should see them. Its sweep keeps its order by
    /// comparing vertices, so a ring of points on top of each other, or one whose
    /// points all lie along a line, gives it nothing to order: consecutive points
    /// within `epsilon` of each other merge into the first, the ring's closing pair
    /// too, and a ring left with fewer than three points, or with every point within
    /// `epsilon` of one line, is dropped, since it encloses nothing. A ring that
    /// crosses itself is kept whole: its signed area says nothing about what it fills
    /// (a figure eight has none and fills two lobes). What the cleaning cannot settle,
    /// a folded ring crossing itself hundreds of times within a few pixels, the
    /// tessellator's double precision does: in single precision its sweep went out of
    /// order on such rings and its asserts ended the process (a live window, 2026-10-26),
    /// and in double a quarter million of them tessellated without one.
    package static func cleaned(_ contours: [[Point2D]], epsilon: Double) -> [[Point2D]] {
        let eps2 = epsilon * epsilon
        func apart(_ a: Point2D, _ b: Point2D) -> Bool {
            let dx = a.x - b.x, dy = a.y - b.y
            return dx * dx + dy * dy > eps2
        }
        var out: [[Point2D]] = []
        out.reserveCapacity(contours.count)
        for contour in contours {
            var ring: [Point2D] = []
            ring.reserveCapacity(contour.count)
            for p in contour where ring.last.map({ apart($0, p) }) ?? true {
                ring.append(p)
            }
            while ring.count > 1, !apart(ring[0], ring[ring.count - 1]) {
                ring.removeLast()
            }
            guard ring.count >= 3 else { continue }
            // The two points farthest apart, found as the glyph simplifier finds them
            // (the farthest from the first, then the farthest from that one), and the
            // widest distance of any point from the line through them: a ring within
            // `epsilon` of that line is a line.
            var a = 0, b = 0, best = -1.0
            for i in ring.indices {
                let dx = ring[i].x - ring[0].x, dy = ring[i].y - ring[0].y
                let d = dx * dx + dy * dy
                if d > best { best = d; b = i }
            }
            best = -1
            for i in ring.indices {
                let dx = ring[i].x - ring[b].x, dy = ring[i].y - ring[b].y
                let d = dx * dx + dy * dy
                if d > best { best = d; a = i }
            }
            let lx = ring[b].x - ring[a].x, ly = ring[b].y - ring[a].y
            let length2 = lx * lx + ly * ly
            guard length2 > eps2 else { continue }
            var widest = 0.0
            for p in ring {
                let cross = lx * (p.y - ring[a].y) - ly * (p.x - ring[a].x)
                let d = cross * cross / length2
                if d > widest { widest = d }
            }
            guard widest > eps2 else { continue }
            out.append(ring)
        }
        return out
    }
}
