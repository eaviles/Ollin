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
/// the conventional default; `.top`/`.bottom` align the block's top/bottom edge to the y, and
/// `.middle` centers the whole block on the y.
public enum TextAlignV: Sendable {
    case top
    case middle
    case baseline
    case bottom
}

/// How outline (`.ttf`/`.otf`) text is rendered (see `textMode`). `.outline`
/// (default) fills each glyph as a vector `Shape` — highest quality, takes `fill`
/// *and* `stroke`. `.atlas` draws each glyph as one textured quad sampling a
/// signed-distance-field atlas: far cheaper per glyph (the scale path for
/// paragraphs and large glyph counts), still crisp under magnification, but
/// fill-only. A no-op for bitmap and stroke fonts, which have no atlas.
public enum TextMode: Sendable {
    case outline
    case atlas
}
