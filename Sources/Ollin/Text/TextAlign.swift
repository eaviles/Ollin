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
    /// Set the text in columns that run top to bottom, the columns themselves
    /// filling **right to left**: Japanese and Chinese tategaki.
    ///
    /// This is a different axis, not a third direction, so it changes what the
    /// other text settings measure. A "line" is now a column, `\n` starts the
    /// next column to the left, and the two `textAlign` axes swap roles: the
    /// vertical one says where each column starts, the horizontal one places the
    /// block of columns. A column is one em across.
    ///
    /// The font supplies the sideways forms, so brackets, dashes and long vowel
    /// marks turn, and a comma moves to the top right of its square. Nothing here
    /// rotates a glyph: each one is the shape the font itself keeps for vertical
    /// setting, which is also why the face decides what happens to Latin. A
    /// Japanese face turns it, so a word inside a column reads sideways; a Latin
    /// face has no turned form to offer, so its letters stack upright.
    ///
    /// ```swift
    /// textDirection(.topToBottom)
    /// drawText("春はあけぼの。", 900, 100)
    /// ```
    ///
    /// Mongolian is the writing system this does not serve: it is also vertical,
    /// but its columns fill left to right.
    case topToBottom
}

extension TextDirection: CaseIterable, ParamOption {}

extension TextDirection {
    /// Whether the text runs down a column rather than across a line.
    var isVertical: Bool { self == .topToBottom }
}

/// What a justified block of text is stretched to fit (see `textJustify`).
///
/// Only a box says how far a line should run, so this is built by the box form of
/// `drawText` and lives no longer than that call.
struct TextJustification {
    /// How far every stretched line runs along the writing axis, in points.
    let extent: Double
    /// The lines that must be left alone, by index in the block: the last of each
    /// paragraph. Those are short because the writing ended, not because the box ran
    /// out, and stretching one of them across the box is the mistake everybody
    /// recognises even when they cannot name it.
    let naturalLines: Set<Int>
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
