import Testing
@testable import Ollin

/// Pure-CPU checks on the glyph mosaic: measured ramps order by real ink,
/// unknown characters drop out, cells map brightness to density, the empty
/// floor really is empty, and the whole pass is deterministic. No GPU.
@Suite @MainActor
struct GlyphMosaicTests {
    private let font = ActiveFont.bitmap(.builtin)

    /// In the bundled bitmap font, a dot inks less than a cross, which inks
    /// less than a full block; the measured ramp orders them so.
    @Test func rampOrdersByMeasuredInk() {
        let ramp = glyphRamp(for: "█·✚", font: font)
        #expect(ramp.map(\.character) == ["·", "✚", "█"])
        #expect(ramp[0].coverage < ramp[1].coverage)
        #expect(ramp[1].coverage < ramp[2].coverage)
    }

    /// The ramp normalizes to its densest member.
    @Test func rampNormalizesToItsDensest() {
        let ramp = glyphRamp(for: GlyphSet.technical, font: font)
        #expect(!ramp.isEmpty)
        #expect(abs((ramp.last?.coverage ?? 0) - 1) < 1e-12)
        for entry in ramp { #expect(entry.coverage > 0 && entry.coverage <= 1) }
    }

    /// Characters the font has no glyph for drop out; duplicates collapse.
    @Test func unknownAndDuplicateCharactersDropOut() {
        let ramp = glyphRamp(for: "\u{0378}····", font: font)
        #expect(ramp.count == 1)
        #expect(ramp[0].character == "·")
    }

    /// A half-black half-white image: the white half earns dense glyphs, the
    /// black half stays empty, and cell centers land inside the bounds.
    @Test func brightCellsEarnGlyphsDarkCellsStayEmpty() {
        let image = Image(width: 40, height: 20, color: .black)
        for y in 0 ..< 20 {
            for x in 20 ..< 40 { image[x, y] = .white }
        }
        let bounds = Rectangle(x: 0, y: 0, width: 400, height: 200)
        let cells = mosaicCells(of: image, columns: 8, characters: GlyphSet.technical,
                                bounds: bounds, inverted: false, font: font)
        #expect(!cells.isEmpty)
        // Only the right half (columns 4...7) carries glyphs.
        for cell in cells {
            #expect(cell.column >= 4)
            #expect(cell.brightness > 0.9)
            #expect(cell.center.x > 200)
            #expect(cell.center.x < 400)
            #expect(cell.character == "█")   // the densest mark in the set
        }
        #expect(cells.count == 4 * (cells.map(\.row).max()! + 1))
    }

    /// `inverted` flips the mapping: the black half carries the ink instead.
    @Test func invertedFlipsTheMapping() {
        let image = Image(width: 40, height: 20, color: .black)
        for y in 0 ..< 20 {
            for x in 20 ..< 40 { image[x, y] = .white }
        }
        let bounds = Rectangle(x: 0, y: 0, width: 400, height: 200)
        let cells = mosaicCells(of: image, columns: 8, characters: GlyphSet.technical,
                                bounds: bounds, inverted: true, font: font)
        #expect(!cells.isEmpty)
        for cell in cells { #expect(cell.column < 4) }
    }

    /// A transparent image maps to no glyphs in either mode: transparency
    /// carries no ink.
    @Test func transparencyCarriesNoInk() {
        let image = Image(width: 8, height: 8, color: .clear)
        let bounds = Rectangle(x: 0, y: 0, width: 80, height: 80)
        let plain = mosaicCells(of: image, columns: 4, characters: GlyphSet.technical,
                                bounds: bounds, inverted: false, font: font)
        let inverted = mosaicCells(of: image, columns: 4, characters: GlyphSet.technical,
                                   bounds: bounds, inverted: true, font: font)
        #expect(plain.isEmpty)
        #expect(inverted.isEmpty)
    }

    /// The same input maps to the same mosaic, cell for cell.
    @Test func mosaicIsDeterministic() {
        let image = Image(width: 32, height: 32, color: .black)
        for y in 0 ..< 32 {
            for x in 0 ..< 32 {
                image[x, y] = Color(white: Double((x + y) % 32) / 31)
            }
        }
        let bounds = Rectangle(x: 0, y: 0, width: 320, height: 320)
        let a = mosaicCells(of: image, columns: 8, characters: GlyphSet.technical,
                            bounds: bounds, inverted: false, font: font)
        let b = mosaicCells(of: image, columns: 8, characters: GlyphSet.technical,
                            bounds: bounds, inverted: false, font: font)
        #expect(a.count == b.count)
        for (x, y) in zip(a, b) {
            #expect(x.character == y.character)
            #expect(x.center == y.center)
        }
    }

    /// An outline font measures by glyph area: a period inks less than an
    /// at-sign there too, so the classic letter ramp orders itself.
    @Test func outlineFontMeasuresByArea() {
        let ramp = glyphRamp(for: ".@", font: .outline(.systemMedium))
        #expect(ramp.map(\.character) == [".", "@"])
    }
}
