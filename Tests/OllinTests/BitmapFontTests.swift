import Ollin
import Testing

/// Parse + decode checks on the Playdate `.fnt` loader. These run on the CPU
/// (ImageIO decode, no Metal), so they run everywhere including CI. The fixture
/// is a tiny self-contained embedded-strike font with two deliberately
/// asymmetric glyphs — `F` and `L` — so any flip or mirror in the strike decode
/// is caught (a vertical flip would swap `F`'s full top row for its sparse
/// bottom; a horizontal flip would move the stems to the right).
@Suite
struct BitmapFontTests {

    /// A 10×7 RGBA strike (two 5×7 cells: `F`, then `L`) embedded as base64, plus
    /// the metrics index and one kerning pair.
    ///
    /// ```
    /// F: #####   L: #....
    ///    #....      #....
    ///    #....      #....
    ///    ####.      #....
    ///    #....      #....
    ///    #....      #....
    ///    #....      #####
    /// ```
    static let fnt = """
    width=5
    height=7
    datalen=116
    data=iVBORw0KGgoAAAANSUhEUgAAAAoAAAAHCAYAAAAxrNxjAAAAHklEQVR42mNgYGD4jwNjgP9EipGmEN1KOlpNyDn/AU+VGOi8VGLjAAAAAElFTkSuQmCC
    tracking=1
    F\t5
    L\t5
    FL\t-1
    """

    @Test func parsesMetricsAndKerning() throws {
        let font = try #require(BitmapFont(fnt: Self.fnt))
        #expect(font.pixelHeight == 7)
        // Advance is the glyph width plus tracking.
        #expect(font.advance(for: "F") == 6)
        #expect(font.advance(for: "L") == 6)
        // The kerning pair carried through.
        #expect(font.kerning(between: "F", "L") == -1)
        #expect(font.kerning(between: "L", "F") == 0)
    }

    @Test func decodesGlyphsRightSideUp() throws {
        let font = try #require(BitmapFont(fnt: Self.fnt))

        let f = try #require(font.glyph(for: "F"))
        #expect(f.width == 5 && f.height == 7)
        // Full top row, sparse bottom row — pins vertical orientation.
        #expect((0..<5).allSatisfy { f.isSet($0, 0) })
        #expect(f.isSet(0, 6) && !f.isSet(4, 6))
        // The mid bar sits on row 3 as `####.`, and the stem is on the left —
        // pins the horizontal orientation.
        #expect(f.isSet(0, 3) && f.isSet(3, 3) && !f.isSet(4, 3))

        let l = try #require(font.glyph(for: "L"))
        // Sparse top, full bottom — the inverse of `F`, so a vertical flip can't
        // pass both.
        #expect(l.isSet(0, 0) && !l.isSet(4, 0))
        #expect((0..<5).allSatisfy { l.isSet($0, 6) })
    }
}
