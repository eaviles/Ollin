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
    /// The source characters this piece of the text stands for.
    ///
    /// Usually one character, but not always, and the exceptions are the whole
    /// reason this is a `String`: a Devanagari syllable is one thing on screen made
    /// of several characters, and a ligature is one shape standing for two. What
    /// you get is a piece a reader would point at and call a letter.
    public let text: String
    /// This piece's index in the run (0-based, **left to right on the canvas**).
    /// For a right-to-left script that is the reverse of reading order, which is
    /// what a sweep across the drawing wants.
    public let index: Int
    /// Total glyphs in the run — for normalizing (`t`).
    public let count: Int
    /// The pen origin (left edge, on the baseline) in canvas space.
    public let position: Vector2
    /// The glyph's advance box in canvas space (`position` to `position + advance`
    /// horizontally, ascent above / descent below the baseline). Its `center` is
    /// the handy pivot for a per-glyph rotation.
    public let bounds: Rectangle
    /// The glyph's geometry positioned in canvas space: one or more `Shape`s
    /// (counters kept as holes). Manipulate these for text-as-geometry effects.
    /// **Empty for an emoji**, which the font stores as a picture and not as
    /// contours; `draw()` still stamps it, and `isPicture` says so.
    public let shapes: [Shape]

    /// Whether this piece is a picture rather than an outline (an emoji). Its
    /// `shapes` are empty, so a sketch warping letterforms should either skip it or
    /// call `draw()` for it.
    public let isPicture: Bool

    /// Stamps this glyph (built by the `Drawer`, so it routes to the same render).
    let drawThunk: () -> Void

    /// The first source character, for the common case of a piece that is one
    /// character. Read `text` when a syllable or a ligature would be cut short.
    public var character: Character { text.first ?? " " }

    /// This glyph's normalized position across the run, `0...1` (0 for a lone
    /// glyph), convenient for spreading a gradient or a phase across the word.
    public var t: Double { count <= 1 ? 0 : Double(index) / Double(count - 1) }

    /// The center of the glyph's advance box — the natural pivot for rotating or
    /// scaling the glyph in place.
    public var center: Vector2 { bounds.center }

    /// Draw this glyph with the current `fill` / `stroke`, through the current
    /// transform.
    public func draw() { drawThunk() }
}

/// One cluster in a single-line run: its source characters, pen metrics (canvas
/// units from the run start), and geometry in a *local* frame (pen origin at the
/// origin, baseline at `y = 0`). The font-agnostic unit behind per-glyph drawing
/// and text-on-a-path; all three font kinds produce these.
struct GlyphRunItem {
    /// The source characters this piece stands for.
    let text: String
    /// How far the piece's leading edge sits from the run start, along whichever
    /// axis the run travels: rightward across a line, downward down a column.
    let pen: Double
    /// The piece's pen advance, canvas units.
    let advance: Double
    /// Geometry with the pen origin at the origin and the baseline at `y = 0`, so
    /// a caller can place it anywhere with a translate (and rotate).
    let localShapes: [Shape]
    /// A picture for a glyph the font stores as one (an emoji), with `localShapes`
    /// empty.
    let picture: Image?
    /// Where the picture sits in the same local frame.
    let localPictureRect: Rectangle
}
