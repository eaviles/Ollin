import Foundation

/// Horizontal anchoring of text relative to the `drawText` position (see
/// `textAlign`). `.left` (default) starts the text at the x; `.center` centers
/// it on the x; `.right` ends it at the x.
public enum TextAlignH: Sendable {
    case left
    case center
    case right
}

/// Vertical anchoring of text relative to the `drawText` position (see
/// `textAlign`). `.baseline` (default) sits the first line's baseline on the y —
/// p5's default; `.top`/`.bottom` align the block's top/bottom edge to the y, and
/// `.middle` centers the whole block on the y.
public enum TextAlignV: Sendable {
    case top
    case middle
    case baseline
    case bottom
}
