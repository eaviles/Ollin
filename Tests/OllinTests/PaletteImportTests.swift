import Foundation
import Ollin
import Testing

/// The palette loader reads five layouts off disk. These pin the parsing
/// decisions that aren't obvious from the call site: what makes a file one
/// palette versus many, which junk a line survives, and that malformed bytes
/// come back empty rather than trapping.
@Suite
struct PaletteImportTests {

    // MARK: - Text

    /// Every line holding exactly one color means the file is one palette,
    /// not a stack of one-color palettes.
    @Test func hexPerLineIsASinglePalette() {
        let text = "#69d2e7\n#a7dbd8\n#e0e4cc\n#f38630\n#fa6900\n"
        let palettes = Palette.palettes(data: Data(text.utf8))
        #expect(palettes.count == 1)
        #expect(palettes[0].count == 5)
        #expect(palettes[0][0] == Color(hex: 0x69D2E7))
        #expect(palettes[0][4] == Color(hex: 0xFA6900))
    }

    /// A line with more than one color flips the file into palette-per-line,
    /// with no format argument needed.
    @Test func commaSeparatedLinesEachBecomeAPalette() {
        let text = "#69d2e7,#a7dbd8,#e0e4cc\n#fe4365,#fc9d9a\n"
        let palettes = Palette.palettes(data: Data(text.utf8))
        #expect(palettes.count == 2)
        #expect(palettes[0].count == 3)
        #expect(palettes[1].count == 2)
        #expect(palettes[1][0] == Color(hex: 0xFE4365))
    }

    @Test func tabSeparatedReadsAsTSV() {
        let text = "#69d2e7\t#a7dbd8\n#fe4365\t#fc9d9a\n"
        let auto = Palette.palettes(data: Data(text.utf8))
        let forced = Palette.palettes(data: Data(text.utf8), format: .tsv)
        #expect(auto.count == 2)
        #expect(forced.count == 2)
        #expect(auto[0].colors == forced[0].colors)
    }

    /// Naming the format overrides the sniff: the same bytes read as one
    /// palette of four rather than two palettes of two.
    @Test func explicitHexLinesOverridesTheSniff() {
        let text = "#69d2e7,#a7dbd8\n#fe4365,#fc9d9a\n"
        let palettes = Palette.palettes(data: Data(text.utf8), format: .hexLines)
        #expect(palettes.count == 1)
        #expect(palettes[0].count == 4)
    }

    /// A line that parses to no colors is dropped, which is what makes CSV
    /// headers and comment lines a non-issue.
    @Test func unparsableLinesAreSkipped() {
        let text = "name,swatches\n// a comment\n\n#ff0000,#00ff00\n"
        let palettes = Palette.palettes(data: Data(text.utf8))
        #expect(palettes.count == 1)
        #expect(palettes[0].colors == [Color(hex: 0xFF0000), Color(hex: 0x00FF00)])
    }

    /// Hex in the wild carries quotes, an `0x` prefix, or three-digit shorthand.
    @Test func tokensSurviveQuotesPrefixesAndShorthand() {
        let text = "\"#ff0000\",0x00ff00,#00f,0000FF\n"
        let palettes = Palette.palettes(data: Data(text.utf8))
        #expect(palettes.count == 1)
        #expect(palettes[0].colors == [Color(hex: 0xFF0000), Color(hex: 0x00FF00),
                                       Color(hex: 0x0000FF), Color(hex: 0x0000FF)])
    }

    // MARK: - JSON

    /// The array-of-arrays shape: many palettes, five colors each.
    @Test func jsonArrayOfArraysReadsAsManyPalettes() {
        let json = """
        [["#69d2e7","#a7dbd8","#e0e4cc","#f38630","#fa6900"],
         ["#fe4365","#fc9d9a","#f9cdad","#c8c8a9","#83af9b"]]
        """
        let palettes = Palette.palettes(data: Data(json.utf8))
        #expect(palettes.count == 2)
        #expect(palettes[0].count == 5)
        #expect(palettes[1][0] == Color(hex: 0xFE4365))
    }

    /// A flat array of hex strings is one palette.
    @Test func jsonArrayOfHexReadsAsOnePalette() {
        let json = ##"["#69d2e7","#a7dbd8","#e0e4cc"]"##
        let palettes = Palette.palettes(data: Data(json.utf8))
        #expect(palettes.count == 1)
        #expect(palettes[0].count == 3)
    }

    @Test func jsonObjectsWithColorsKeyRead() {
        let json = ##"[{"name":"a","colors":["#ff0000","#00ff00"]},{"colors":["#0000ff"]}]"##
        let palettes = Palette.palettes(data: Data(json.utf8))
        #expect(palettes.count == 2)
        #expect(palettes[0].count == 2)
        #expect(palettes[1][0] == Color(hex: 0x0000FF))
    }

    /// Leading whitespace must not hide the opening bracket from the sniffer.
    @Test func jsonIsSniffedThroughLeadingWhitespace() {
        let json = "\n\n   [[\"#ff0000\"]]"
        #expect(Palette.palettes(data: Data(json.utf8)).count == 1)
    }

    // MARK: - Adobe Swatch Exchange

    /// Groups become palettes, in the order the file lists them.
    @Test func aseGroupsBecomePalettes() {
        let data = ASEFixture()
            .group("warm", rgb: [(1, 0, 0), (1, 0.5, 0)])
            .group("cool", rgb: [(0, 0, 1)])
            .data()
        let palettes = Palette.palettes(data: data)
        #expect(palettes.count == 2)
        #expect(palettes[0].count == 2)
        #expect(palettes[1].count == 1)
        #expect(palettes[0][0] == Color(red: 1, green: 0, blue: 0))
        #expect(palettes[1][0] == Color(red: 0, green: 0, blue: 1))
    }

    /// Colors sitting outside any group still make a palette.
    @Test func aseLooseColorsFormOnePalette() {
        let data = ASEFixture().loose(rgb: [(1, 0, 0), (0, 1, 0)]).data()
        let palettes = Palette.palettes(data: data)
        #expect(palettes.count == 1)
        #expect(palettes[0].count == 2)
    }

    /// Loose colors before a group flush in place, so document order holds.
    @Test func aseKeepsDocumentOrder() {
        let data = ASEFixture()
            .loose(rgb: [(1, 0, 0)])
            .group("g", rgb: [(0, 1, 0)])
            .data()
        let palettes = Palette.palettes(data: data)
        #expect(palettes.count == 2)
        #expect(palettes[0][0] == Color(red: 1, green: 0, blue: 0))
        #expect(palettes[1][0] == Color(red: 0, green: 1, blue: 0))
    }

    /// A block type we don't handle must be stepped over by its declared
    /// length, leaving the blocks after it readable.
    @Test func aseSkipsUnknownBlocksByLength() {
        let data = ASEFixture()
            .unknownBlock(payload: [0xDE, 0xAD, 0xBE, 0xEF])
            .loose(rgb: [(0, 0, 1)])
            .data()
        let palettes = Palette.palettes(data: data)
        #expect(palettes.count == 1)
        #expect(palettes[0][0] == Color(red: 0, green: 0, blue: 1))
    }

    /// Gray and CMYK swatches decode to the colors their models imply.
    @Test func aseReadsGrayAndCMYK() {
        let data = ASEFixture().grayLoose(0.5).cmykLoose(0, 1, 1, 0).data()
        let palettes = Palette.palettes(data: data)
        #expect(palettes.count == 1)
        #expect(palettes[0].count == 2)
        #expect(abs(palettes[0][0].red - 0.5) < 0.001)
        #expect(palettes[0][0].red == palettes[0][0].blue)
        // Cyan zero, magenta and yellow full, no black: pure red.
        #expect(palettes[0][1] == Color(red: 1, green: 0, blue: 0))
    }

    /// LAB lightness arrives as 0...1, so a mid-gray must not come back black.
    @Test func aseLabLightnessIsNormalized() {
        let data = ASEFixture().labLoose(l: 0.5, a: 0, b: 0).data()
        let palettes = Palette.palettes(data: data)
        #expect(palettes.count == 1)
        let gray = palettes[0][0]
        #expect(gray.red > 0.4 && gray.red < 0.65)
        #expect(abs(gray.red - gray.green) < 0.01)
        #expect(abs(gray.green - gray.blue) < 0.01)
    }

    // MARK: - Failure

    /// Garbage never traps. A file with no colors has no first palette.
    @Test func malformedInputYieldsNothing() {
        #expect(Palette.palettes(data: Data()).isEmpty)
        #expect(Palette.palettes(data: Data("not a palette".utf8)).isEmpty)
        #expect(Palette.palettes(data: Data("{".utf8)).isEmpty)
        #expect(Palette(data: Data("zzz".utf8)) == nil)
        #expect(Palette(contentsOf: "/nonexistent/path.hex") == nil)
    }

    /// A truncated swatch file stops where the bytes stop.
    @Test func truncatedASEStopsCleanly() {
        let full = ASEFixture().group("g", rgb: [(1, 0, 0), (0, 1, 0)]).data()
        for cut in stride(from: 4, to: full.count, by: 3) {
            _ = Palette.palettes(data: full.prefix(cut))  // must not trap
        }
        #expect(Palette.palettes(data: full.prefix(12)).isEmpty)
    }

    /// The single-palette initializer is the first palette of the file.
    @Test func singleInitTakesTheFirstPalette() {
        let json = ##"[["#ff0000"],["#00ff00"]]"##
        let palette = Palette(data: Data(json.utf8))
        #expect(palette?.colors == [Color(hex: 0xFF0000)])
    }
}

// MARK: - Fixture

/// Builds Adobe Swatch Exchange bytes so the parser is tested against the
/// format rather than against a checked-in binary nobody can read in a diff.
private struct ASEFixture {
    private var blocks: [Data] = []

    func group(_ name: String, rgb: [(Float, Float, Float)]) -> ASEFixture {
        var copy = self
        copy.blocks.append(ASEFixture.block(type: 0xC001, body: ASEFixture.name(name)))
        for (r, g, b) in rgb { copy.blocks.append(ASEFixture.rgbBlock(r, g, b)) }
        copy.blocks.append(ASEFixture.block(type: 0xC002, body: Data()))
        return copy
    }

    func loose(rgb: [(Float, Float, Float)]) -> ASEFixture {
        var copy = self
        for (r, g, b) in rgb { copy.blocks.append(ASEFixture.rgbBlock(r, g, b)) }
        return copy
    }

    func grayLoose(_ v: Float) -> ASEFixture {
        var copy = self
        var body = ASEFixture.name("gray") + Data("Gray".utf8) + ASEFixture.f32(v)
        body += ASEFixture.u16(2)
        copy.blocks.append(ASEFixture.block(type: 0x0001, body: body))
        return copy
    }

    func cmykLoose(_ c: Float, _ m: Float, _ y: Float, _ k: Float) -> ASEFixture {
        var copy = self
        var body = ASEFixture.name("ink") + Data("CMYK".utf8)
        body += ASEFixture.f32(c) + ASEFixture.f32(m) + ASEFixture.f32(y) + ASEFixture.f32(k)
        body += ASEFixture.u16(1)
        copy.blocks.append(ASEFixture.block(type: 0x0001, body: body))
        return copy
    }

    func labLoose(l: Float, a: Float, b: Float) -> ASEFixture {
        var copy = self
        var body = ASEFixture.name("lab") + Data("LAB ".utf8)
        body += ASEFixture.f32(l) + ASEFixture.f32(a) + ASEFixture.f32(b)
        body += ASEFixture.u16(0)
        copy.blocks.append(ASEFixture.block(type: 0x0001, body: body))
        return copy
    }

    func unknownBlock(payload: [UInt8]) -> ASEFixture {
        var copy = self
        copy.blocks.append(ASEFixture.block(type: 0x9999, body: Data(payload)))
        return copy
    }

    func data() -> Data {
        var out = Data("ASEF".utf8)
        out += ASEFixture.u16(1) + ASEFixture.u16(0)
        out += ASEFixture.u32(UInt32(blocks.count))
        for block in blocks { out += block }
        return out
    }

    // Big-endian primitives, matching the format.
    private static func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    private static func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    private static func f32(_ v: Float) -> Data { u32(v.bitPattern) }

    /// Length in UTF-16 code units, including the terminating null the count covers.
    private static func name(_ s: String) -> Data {
        let units = Array(s.utf16) + [0]
        var out = u16(UInt16(units.count))
        for unit in units { out += u16(unit) }
        return out
    }

    private static func block(type: UInt16, body: Data) -> Data {
        u16(type) + u32(UInt32(body.count)) + body
    }

    private static func rgbBlock(_ r: Float, _ g: Float, _ b: Float) -> Data {
        var body = name("c") + Data("RGB ".utf8)
        body += f32(r) + f32(g) + f32(b)
        body += u16(2)
        return block(type: 0x0001, body: body)
    }
}
