import Foundation

/// One glyph of a `BitmapFont`: a small grid of pixels, each lit or not.
///
/// A glyph is stored as one bitmask per row (`rows`), the leftmost pixel in the
/// most-significant used bit, so a `width`×`height` cell packs into `height`
/// integers. Render it by stamping a square for every lit pixel — which is
/// exactly what `drawText` does, on the instanced-SDF path (one `drawRect` per
/// lit pixel), so no rasterization and no new pipeline.
public struct BitmapGlyph: Equatable, Sendable {
    /// Cell width in font pixels.
    public let width: Int
    /// Cell height in font pixels.
    public let height: Int
    /// One bitmask per row (top to bottom). Pixel `(col, row)` is lit when
    /// `rows[row]` has bit `width - 1 - col` set (leftmost pixel = highest bit).
    public let rows: [UInt32]
    /// How far the pen advances after this glyph, in font pixels (defaults to
    /// `width + 1`, a one-pixel gap to the next glyph).
    public let advance: Int
    /// Horizontal bearing in font pixels — where the cell's left edge sits
    /// relative to the pen. 0 for the built-in monospace font; used by loaders.
    public let xOffset: Int
    /// Vertical bearing in font pixels — where the cell's top sits relative to
    /// the line's top. 0 for the built-in font; used by loaders.
    public let yOffset: Int

    public init(width: Int, height: Int, rows: [UInt32], advance: Int? = nil,
                xOffset: Int = 0, yOffset: Int = 0) {
        self.width = width
        self.height = height
        self.rows = rows
        self.advance = advance ?? (width + 1)
        self.xOffset = xOffset
        self.yOffset = yOffset
    }

    /// Whether the pixel at `(col, row)` is lit.
    public func isSet(_ col: Int, _ row: Int) -> Bool {
        guard row >= 0, row < rows.count, col >= 0, col < width else { return false }
        return rows[row] & (1 << (width - 1 - col)) != 0
    }
}

public extension BitmapGlyph {
    /// Build a glyph from ASCII-art rows — `["#...#", "#...#", "#####", …]` — where
    /// `on` (default `"#"`) marks a lit pixel and any other character is empty. The
    /// width is the longest row; shorter rows pad empty on the right. The natural
    /// way to hand-author a fixed-grid glyph.
    init(_ artRows: [String], on: Character = "#", advance: Int? = nil) {
        let w = artRows.map(\.count).max() ?? 0
        var masks: [UInt32] = []
        masks.reserveCapacity(artRows.count)
        for line in artRows {
            var mask: UInt32 = 0
            for (col, ch) in line.enumerated() where ch == on {
                mask |= 1 << (w - 1 - col)
            }
            masks.append(mask)
        }
        self.init(width: w, height: artRows.count, rows: masks, advance: advance)
    }
}

/// An ordered pair of characters, the key for a font's kerning table — the extra
/// pen offset (usually negative) applied between `left` and `right` when they sit
/// side by side.
public struct GlyphPair: Hashable, Sendable {
    public let left: Character
    public let right: Character
    public init(_ left: Character, _ right: Character) {
        self.left = left
        self.right = right
    }
}

/// A bitmap (pixel-grid) font: a table of `BitmapGlyph`s plus the metrics needed
/// to lay them out. Drawn by `drawText`, which stamps one square per lit pixel on
/// the instanced-SDF path — no rasterization, no new pipeline.
///
/// The built-in ``builtin`` font is ready to use, so `drawText("hi", x, y)` works
/// with no setup. Hand-author your own with the grid initializer
/// (`BitmapFont(grid:…)`), which takes the same ASCII-art form as `BitmapGlyph`.
///
/// ```swift
/// textFont(.builtin)        // the default; shown here for clarity
/// textSize(120)             // rendered glyph height, in points
/// fill(.black)
/// drawText("ollin", width / 2, height / 2)
/// ```
public struct BitmapFont: Equatable, Sendable {
    /// The glyph for each character. Characters with no entry are skipped — they
    /// advance the pen (a space's `spaceAdvance`, others nothing) but draw nothing.
    public let glyphs: [Character: BitmapGlyph]
    /// The native cell height in font pixels — the divisor that turns `textSize`
    /// into an on-screen module size (`module = textSize / pixelHeight`), so
    /// `textSize` reads as the rendered glyph height.
    public let pixelHeight: Int
    /// Distance from a line's top to its baseline, in font pixels.
    public let baseline: Int
    /// Distance from one line's top to the next, in font pixels — the vertical
    /// advance for `\n`.
    public let lineHeight: Int
    /// Pen advance for a space, in font pixels (used when `" "` has no glyph).
    public let spaceAdvance: Int
    /// Per-pair pen adjustments, in font pixels — the extra offset applied between
    /// two adjacent glyphs (usually negative, tucking them closer). Empty for fonts
    /// without kerning; loaders that carry it (the Playdate `.fnt` loader) fill it.
    public let kerning: [GlyphPair: Int]

    public init(glyphs: [Character: BitmapGlyph], pixelHeight: Int,
                baseline: Int? = nil, lineHeight: Int? = nil, spaceAdvance: Int? = nil,
                kerning: [GlyphPair: Int] = [:]) {
        self.glyphs = glyphs
        self.pixelHeight = pixelHeight
        self.baseline = baseline ?? pixelHeight
        self.lineHeight = lineHeight ?? (pixelHeight + 1)
        self.spaceAdvance = spaceAdvance ?? ((glyphs.values.first?.width ?? pixelHeight) + 1)
        self.kerning = kerning
    }

    /// The glyph for `character`, if the font has one.
    public func glyph(for character: Character) -> BitmapGlyph? { glyphs[character] }

    /// The pen advance for `character`, in font pixels — the glyph's own advance,
    /// a space's `spaceAdvance`, or 0 for an unknown non-space character.
    public func advance(for character: Character) -> Int {
        if let g = glyphs[character] { return g.advance }
        if character == " " { return spaceAdvance }
        return 0
    }

    /// The kerning adjustment between `left` and `right`, in font pixels — 0 unless
    /// the font has a pair for them.
    public func kerning(between left: Character, _ right: Character) -> Int {
        kerning[GlyphPair(left, right)] ?? 0
    }

    /// The width of `string`'s widest line, in font pixels — the inked extent (the
    /// rightmost lit column across the line). Backs alignment and `textWidth`.
    public func inkWidth(of string: String) -> Int {
        var maxWidth = 0
        for line in string.split(separator: "\n", omittingEmptySubsequences: false) {
            var penX = 0
            var right = 0
            var previous: Character? = nil
            for ch in line {
                if let prev = previous { penX += kerning(between: prev, ch) }
                if let g = glyphs[ch] { right = Swift.max(right, penX + g.xOffset + g.width) }
                penX += advance(for: ch)
                previous = ch
            }
            maxWidth = Swift.max(maxWidth, right)
        }
        return maxWidth
    }
}

public extension BitmapFont {
    /// Build a fixed-cell font from a dictionary of ASCII-art glyphs — the form a
    /// hand-authored pixel font takes, each value the glyph's rows (`["#...#", …]`,
    /// `on` marking a lit pixel). `pixelHeight` defaults to the tallest glyph; every
    /// glyph gets a monospace `advance` (`width + 1`).
    init(grid: [Character: [String]], on: Character = "#",
         pixelHeight: Int? = nil, baseline: Int? = nil, lineHeight: Int? = nil) {
        var built: [Character: BitmapGlyph] = [:]
        built.reserveCapacity(grid.count)
        for (ch, rows) in grid { built[ch] = BitmapGlyph(rows, on: on) }
        let h = pixelHeight ?? (grid.values.map(\.count).max() ?? 0)
        self.init(glyphs: built, pixelHeight: h, baseline: baseline, lineHeight: lineHeight)
    }
}
