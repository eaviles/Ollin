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

    /// `.middle`, under the name the horizontal axis uses, so
    /// `textAlign(.center, .center)` also compiles. Vertical centering is
    /// typographically "middle"; the canonical case stays `.middle`.
    public static var center: TextAlignV { .middle }
}

/// The base direction a line of text is laid out in (see `textDirection`).
///
/// A line can hold both directions at once: an Arabic sentence quoting a Latin
/// product name, a Hebrew caption with a number in it. The *base* direction is
/// the one the line as a whole runs in. It decides where the neutral characters
/// (spaces, brackets, punctuation) land, and which end the line starts at.
///
/// `.automatic` (the default) takes the direction from the text itself: the first
/// letter with a direction of its own wins, which is what a paragraph of one
/// language wants. Name a direction when that answer is wrong. A line opening
/// with a bracket or a digit has no direction of its own to read.
///
/// ```swift
/// textDirection(.rightToLeft)
/// drawText("(١) مرحبا", 40, 100)     // the bracket goes on the right
/// ```
///
/// Shaping and reordering come from the system's own layout engine, so this
/// applies to an `OutlineFont`. A bitmap or stroke font has no shaping engine and
/// always runs left to right.
public enum TextDirection: Sendable {
    /// Read the direction from the text: the first directional letter decides.
    case automatic
    /// Lay the line out left to right whatever it holds.
    case leftToRight
    /// Lay the line out right to left whatever it holds.
    case rightToLeft
}

extension TextDirection: CaseIterable, ParamOption {}

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
