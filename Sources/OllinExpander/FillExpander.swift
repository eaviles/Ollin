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
    /// open ones and the degenerate ones. Empty when the tessellator refuses.
    package static func triangulate(_ contours: [[Point2D]], nonZero: Bool) -> [Point2D] {
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
}
