import Foundation

/// One glyph handed to the per-glyph `drawText` closure — its character, where it
/// sits in the string and on the canvas, and a `draw()` that stamps just this
/// glyph. Use it to give each letter its own transform or color: wave, rotate,
/// fade, or recolor per glyph, then call `draw()`.
///
/// ```swift
/// drawText("ollin", at: center) { g in
///     fill(palette.color(at: g.t))
///     withState {
///         translate(0, sin(time * 3 + Double(g.index)) * 40)   // bob each letter
///         g.draw()
///     }
/// }
/// ```
///
/// `draw()` stamps the glyph at its laid-out position using the current `fill` /
/// `stroke`, through whatever transform you've set — so a `translate` offsets it
/// and a rotation about `center` spins it in place. For geometry instead of a
/// draw, read `shapes` (the glyph's contours in canvas space).
public struct TextGlyph {
    /// The source character.
    public let character: Character
    /// This glyph's index in the run (0-based, left to right).
    public let index: Int
    /// Total glyphs in the run — for normalizing (`t`).
    public let count: Int
    /// The pen origin (left edge, on the baseline) in canvas space.
    public let position: Vector2
    /// The glyph's advance box in canvas space (`position` to `position + advance`
    /// horizontally, ascent above / descent below the baseline). Its `center` is
    /// the handy pivot for a per-glyph rotation.
    public let bounds: Rectangle
    /// The glyph's geometry positioned in canvas space — one or more `Shape`s
    /// (counters kept as holes). Manipulate these for text-as-geometry effects.
    public let shapes: [Shape]

    /// Stamps this glyph (built by the `Drawer`, so it routes to the same render).
    let drawThunk: () -> Void

    /// This glyph's normalized position across the run, `0...1` (0 for a lone
    /// glyph) — convenient for spreading a gradient or a phase across the word.
    public var t: Double { count <= 1 ? 0 : Double(index) / Double(count - 1) }

    /// The center of the glyph's advance box — the natural pivot for rotating or
    /// scaling the glyph in place.
    public var center: Vector2 { bounds.center }

    /// Draw this glyph with the current `fill` / `stroke`, through the current
    /// transform.
    public func draw() { drawThunk() }
}

/// One glyph in a single-line run: its character, pen metrics (canvas units from
/// the run start), and geometry in a *local* frame — pen origin at the origin,
/// baseline at `y = 0`. The font-agnostic unit behind per-glyph drawing and
/// text-on-a-path; both `OutlineFont` and the bitmap path produce these.
struct GlyphRunItem {
    let character: Character
    /// Pen x at the glyph's start, canvas units from the run start.
    let penX: Double
    /// The glyph's pen advance, canvas units.
    let advance: Double
    /// Glyph geometry with the pen origin at the origin and the baseline at
    /// `y = 0`, so a caller can place it anywhere with a translate (and rotate).
    let localShapes: [Shape]
}
