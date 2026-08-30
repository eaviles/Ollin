import Foundation

/// One glyph of a `StrokeFont`: a set of **open pen polylines** plus the pen
/// advance. There's no fill — a stroke glyph is drawn the way a plotter draws it,
/// by tracing lines with a pen.
///
/// The polylines are in font units, positioned so the glyph's pen origin sits at
/// `x = 0` and the baseline at `y = 0` (y increasing downward, like the rest of
/// Ollin). A caller scales by `size / unitsPerEm` and places the glyph with a
/// translate. Each polyline is one continuous pen-down stroke; a glyph with
/// disjoint strokes (the dot of an `i`, the bar of an `A`) has several.
public struct StrokeGlyph: Equatable, Sendable {
    /// How far the pen advances after this glyph, in font units.
    public let advance: Double
    /// The pen-down strokes — each an open polyline in font units (pen origin at
    /// `x = 0`, baseline at `y = 0`).
    public let polylines: [[Vector2]]

    public init(advance: Double, polylines: [[Vector2]]) {
        self.advance = advance
        self.polylines = polylines
    }
}

/// A single-line (stroke) font: glyphs drawn as **pen polylines with no fill**,
/// the kind of letterform a pen plotter wants. Where a `BitmapFont` stamps pixels
/// and an `OutlineFont` fills vector contours, a `StrokeFont` strokes open paths —
/// so `drawText` draws it with the current `stroke` (weight, join, cap) and the
/// `fill` is ignored.
///
/// The built-in ``builtIn`` font is **Hershey Sans** (`futural`), so stroke text
/// works with no setup once you switch to it:
///
/// ```swift
/// textFont(StrokeFont.builtIn)   // Hershey Sans
/// textSize(140)
/// stroke(.white); strokeWeight(2); noFill()
/// drawText("ollin", width / 2, height / 2)
/// ```
///
/// Load your own from a Hershey `.jhf` file with `StrokeFont(jhfContentsOf:)` or
/// `StrokeFont(resource:in:)`.
public struct StrokeFont: Equatable, Sendable {
    /// The glyph for each character. Characters with no entry advance the pen by
    /// the space width (for `" "`) or not at all, and draw nothing.
    public let glyphs: [Character: StrokeGlyph]
    /// The font's design size in font units — the divisor that turns `textSize`
    /// into a scale (`scale = textSize / unitsPerEm`), so `textSize` reads as the
    /// rendered em height.
    public let unitsPerEm: Double
    /// Distance from the baseline up to the top of the tallest glyphs, in font
    /// units.
    public let ascentUnits: Double
    /// Distance from the baseline down to the bottom of the lowest descenders, in
    /// font units.
    public let descentUnits: Double
    /// Extra space between lines beyond ascent + descent, in font units.
    public let lineGapUnits: Double
    /// Pen advance for a space, in font units (used when `" "` has no glyph).
    public let spaceAdvanceUnits: Double

    public init(glyphs: [Character: StrokeGlyph], unitsPerEm: Double,
                ascentUnits: Double, descentUnits: Double, lineGapUnits: Double = 0,
                spaceAdvanceUnits: Double? = nil) {
        self.glyphs = glyphs
        self.unitsPerEm = unitsPerEm
        self.ascentUnits = ascentUnits
        self.descentUnits = descentUnits
        self.lineGapUnits = lineGapUnits
        self.spaceAdvanceUnits = spaceAdvanceUnits ?? (unitsPerEm / 2)
    }

    /// The glyph for `character`, if the font has one.
    public func glyph(for character: Character) -> StrokeGlyph? { glyphs[character] }

    /// The pen advance for `character`, in font units — the glyph's own advance, a
    /// space's `spaceAdvanceUnits`, or 0 for an unknown non-space character.
    public func advanceUnits(for character: Character) -> Double {
        if let g = glyphs[character] { return g.advance }
        if character == " " { return spaceAdvanceUnits }
        return 0
    }

    // Em-fraction metrics, so a caller scales them by the rendered size exactly
    // like an outline font's (`font.ascent * textSize`).

    /// Ascent as a fraction of the em (multiply by the rendered size for points).
    public var ascent: Double { unitsPerEm > 0 ? ascentUnits / unitsPerEm : 0 }
    /// Descent as a fraction of the em.
    public var descent: Double { unitsPerEm > 0 ? descentUnits / unitsPerEm : 0 }
    /// Line gap as a fraction of the em (the extra beyond ascent + descent).
    public var leading: Double { unitsPerEm > 0 ? lineGapUnits / unitsPerEm : 0 }

    /// The advance width of one `line`, in font units (no `\n` handling).
    public func lineAdvanceUnits<S: StringProtocol>(of line: S) -> Double {
        var width = 0.0
        for ch in line { width += advanceUnits(for: ch) }
        return width
    }

    /// The on-screen width of `string`'s widest line, in points, at `size`.
    public func width(of string: String, size: Double) -> Double {
        guard unitsPerEm > 0 else { return 0 }
        let scale = size / unitsPerEm
        var maxWidth = 0.0
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            maxWidth = Swift.max(maxWidth, lineAdvanceUnits(of: line))
        }
        return maxWidth * scale
    }
}
