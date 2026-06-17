/// Where a shape's stroke sits relative to its outline. Set it with
/// `strokeAlign(_:)`, the way `strokeWeight` sets the width; the choice holds
/// until changed.
///
/// The default, `.center`, straddles the edge — half the weight inside, half
/// outside — which is what every stroke did before, the conventional default.
/// `.inside` keeps the whole stroke within the shape, so its footprint doesn't
/// grow (handy for tiled grids, where an outward border would overlap
/// neighbors); `.outside` puts the stroke entirely beyond the edge.
///
/// It applies to the analytic (SDF) shapes — circles, ellipses, rectangles, the
/// polygon/star family, and the rest of that catalog — where the inset/outset is
/// a geometrically exact offset of the outline. Shapes with no inside/outside
/// keep the centered stroke: lines, point markers, the open arc, and the
/// tessellated `drawPolyline` / `drawPolygon` / `drawShape` paths.
public enum StrokeAlign: Sendable, CaseIterable {
    /// Centered on the outline — half inside, half outside. The default.
    case center
    /// Entirely inside the outline; the shape's footprint is unchanged.
    case inside
    /// Entirely outside the outline; the footprint grows by the stroke weight.
    case outside

    /// The code the fragment shader reads, packed into the high bits of the SDF
    /// shape tag (so it costs no extra room in `SDFInstance`).
    var shaderCode: UInt32 {
        switch self {
        case .center:  return 0
        case .inside:  return 1
        case .outside: return 2
        }
    }
}
