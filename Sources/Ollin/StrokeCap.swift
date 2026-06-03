/// How the open ends of a stroked path are finished. Set it with
/// `strokeCap(_:)`, the way `strokeWeight` sets the width; the choice holds until
/// changed.
///
/// The default, `.butt`, ends the stroke flat at the endpoint — its footprint
/// stops exactly where the path does. `.round` adds a half-disk over each end (a
/// rounded tip), and `.square` adds a flat extension half the stroke weight past
/// the endpoint, so both `.round` and `.square` reach beyond the path's end by
/// half the weight.
///
/// It applies to the open tessellated stroked paths — `drawPolyline` and any
/// open `drawShape` contour. Closed outlines (the `drawPolygon` outline, a
/// closed contour) have no ends to cap. `drawLine` and `drawBezier` are their own
/// round-capped SDF segments and aren't affected.
public enum StrokeCap: Sendable, CaseIterable {
    /// Ends flat at the endpoint, with no extension. The default.
    case butt
    /// A half-disk over the end — a rounded tip.
    case round
    /// A flat extension half the stroke weight past the endpoint.
    case square
}
