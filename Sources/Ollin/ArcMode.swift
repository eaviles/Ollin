/// How `drawArc` closes its endpoints — which decides both the filled region and
/// what the stroke traces.
///
/// Angles are in radians, measured from the positive x-axis and increasing
/// clockwise (Ollin's y-down space, the same sense as `rotate`).
public enum ArcMode {
    /// Stroke only the open curve. The fill (if any) is the segment cut off by a
    /// straight chord between the endpoints, but that chord is not stroked.
    case open
    /// Close the arc with a straight chord between its endpoints; the stroke
    /// traces the chord as well as the curve, and the fill is that segment.
    case chord
    /// Close the arc through the center, like a pie slice; the stroke traces both
    /// radii, and the fill is the wedge.
    case pie
}
