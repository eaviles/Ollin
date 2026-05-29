import CLibtess2

extension Shape {
    /// Triangulated fill geometry: a flat array of triangle vertices (every three
    /// is one triangle), ready for the renderer's triangle path. Closed contours
    /// are tessellated together with even-odd winding, so nested contours become
    /// holes. Open contours don't contribute to the fill. Returns empty when
    /// there's nothing fillable.
    ///
    /// Re-evaluated per call, matching the immediate-mode model (like the convex
    /// `drawPolygon` fan). The heavy lifting is libtess2's; see CLibtess2.
    func triangulatedFill() -> [Vector2] {
        let fillable = contours.filter { $0.isClosed && $0.points.count >= 3 }
        guard !fillable.isEmpty else { return [] }
        guard let tess = tessNewTess(nil) else { return [] }
        defer { tessDeleteTess(tess) }

        // Feed each contour as a flat array of (x, y) floats.
        for contour in fillable {
            var coords = [TESSreal]()
            coords.reserveCapacity(contour.points.count * 2)
            for p in contour.points {
                coords.append(TESSreal(p.x))
                coords.append(TESSreal(p.y))
            }
            coords.withUnsafeBufferPointer { buffer in
                tessAddContour(tess, 2, buffer.baseAddress,
                               Int32(MemoryLayout<TESSreal>.stride * 2),
                               Int32(contour.points.count))
            }
        }

        // Tessellate into triangles (polySize 3), 2D, even-odd winding.
        let ok = tessTesselate(tess,
                               Int32(TESS_WINDING_ODD.rawValue),
                               Int32(TESS_POLYGONS.rawValue),
                               3, 2, nil)
        guard ok == 1,
              let verts = tessGetVertices(tess),
              let elements = tessGetElements(tess) else { return [] }

        let vertexCount = Int(tessGetVertexCount(tess))
        let elementCount = Int(tessGetElementCount(tess))
        var triangles = [Vector2]()
        triangles.reserveCapacity(elementCount * 3)
        for e in 0..<elementCount {
            for k in 0..<3 {
                let index = Int(elements[e * 3 + k])
                // Skip a degenerate triangle (libtess2 marks a missing vertex
                // with an out-of-range index).
                guard index >= 0, index < vertexCount else { continue }
                triangles.append(Vector2(Double(verts[index * 2]),
                                         Double(verts[index * 2 + 1])))
            }
        }
        return triangles
    }
}
