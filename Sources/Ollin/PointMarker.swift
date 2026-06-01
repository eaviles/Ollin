/// The glyph `drawPoint` stamps at each position. Set it with `pointMarker(_:)`,
/// the way `pointSize` sets the diameter; the chosen marker holds until changed,
/// so a scatter is `pointMarker(.cross)` once and then a run of `drawPoint`s.
///
/// Every marker is sized by its on-screen *diameter* (the `pointSize` / per-call
/// `size`), so swapping the marker keeps the same footprint. Like `drawPoint`
/// itself, markers take the current `fill` color and ignore stroke.
public enum PointMarker: Sendable, CaseIterable {
    /// A round dot — the default, and the only one with sub-pixel area-conserving
    /// coverage (a shrinking dot fades smoothly rather than snapping to ~1px).
    case circle
    /// An axis-aligned square whose side is the diameter.
    case square
    /// A square turned 45°, whose diagonal is the diameter.
    case diamond
    /// A plus sign (+): two bars meeting at the center, spanning the diameter.
    case cross
    /// A diagonal cross (✕): the `cross` turned 45°.
    case x
}
