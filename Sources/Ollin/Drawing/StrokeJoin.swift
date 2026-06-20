/// How a stroked path turns its corners. Set it with `strokeJoin(_:)`, the way
/// `strokeWeight` sets the width; the choice holds until changed.
///
/// The default, `.miter`, extends the two outer edges until they meet at a sharp
/// point — what keeps a star's tips crisp — and falls back to a flat `.bevel`
/// when a corner is acute enough that the point would shoot out into a long
/// spike. `.bevel` always cuts the corner off with a straight edge; `.round`
/// fills it with an arc, so the turn reads as a smooth bend.
///
/// It applies to the stroked paths with interior corners — `drawPolyline`, the
/// `drawPolygon` outline, `drawShape` contours, and the flattened `drawBezier`.
/// The analytic SDF shapes draw their own outlines, and `drawLine` is a single
/// segment, so those have no joins to style.
public enum StrokeJoin: Sendable, CaseIterable {
    /// A sharp point where the outer edges meet, beveled off past the miter
    /// limit so an acute corner doesn't spike. The default.
    case miter
    /// A flat edge across the corner.
    case bevel
    /// An arc that rounds the corner off.
    case round
}
