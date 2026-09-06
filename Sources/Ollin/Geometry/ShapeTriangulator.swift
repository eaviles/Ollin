import OllinExpander

extension Shape {
    /// The closed contours with at least three points: what the fill is made of.
    var fillableContours: [Contour] {
        contours.filter { $0.isClosed && $0.points.count >= 3 }
    }

    /// Triangulated fill geometry: a flat array of triangle vertices (every three
    /// is one triangle), ready for the renderer's triangle path. Closed contours
    /// are tessellated together with the shape's `winding` rule, so nested
    /// contours become holes. Open contours don't contribute to the fill. Returns
    /// empty when there's nothing fillable.
    ///
    /// Re-evaluated per call, matching the immediate-mode model (like the convex
    /// `drawPolygon` fan). The heavy lifting is libtess2's, reached through the
    /// `OllinExpander` module the web page's player part shares, so a fill a
    /// page carries as its contours triangulates there as it does here.
    func triangulatedFill() -> [Vector2] {
        let fillable = fillableContours
        guard !fillable.isEmpty else { return [] }
        let contours = fillable.map { $0.points.map { Point2D($0.x, $0.y) } }
        return FillExpander.triangulate(contours, nonZero: winding == .nonZero).map { Vector2($0.x, $0.y) }
    }
}
