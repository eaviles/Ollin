import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import Ollin

/// Text in the scripts that are not Latin.
///
/// The one-glyph-per-letter assumption holds for English and almost nowhere else,
/// and every check here is a place it breaks: a syllable drawn out of order, a
/// line that runs right to left, a mark stacked on the letter under it, a
/// character the font draws as a picture, a paragraph with no spaces to break at.
/// The counterfactual for most of them is the arithmetic the old per-glyph path
/// did, which is named in each test.
@Suite @MainActor
struct ComplexTextTests {
    private let font = OutlineFont.systemMedium
    private let size = 100.0

    private func run(_ string: String, _ direction: TextDirection = .automatic) -> [GlyphRunItem] {
        font.glyphRun(for: string, size: size, direction: direction)
    }

    // MARK: Clusters

    /// A Devanagari syllable is one thing a reader points at, written with several
    /// characters and drawn with several glyphs, one of which the shaper moves to
    /// the *left* of the letter it follows. Splitting it by glyph or by character
    /// gives pieces that overlap on the canvas, so it has to come back whole.
    @Test func aSyllableThatReordersItsGlyphsStaysOnePiece() {
        let items = run("क्षि")
        #expect(items.count == 1)
        #expect(items[0].text == "क्षि")
        #expect(items[0].localShapes.count > 1)      // several glyphs, one piece
        #expect(items[0].advance > 0)
    }

    /// The pieces of a right-to-left line come out left to right on the canvas,
    /// which is the reverse of reading order. A sweep across the drawing wants the
    /// canvas order, and each piece still carries the character it stands for.
    @Test func anArabicLineComesOutLeftToRightCarryingItsOwnLetters() {
        let word = "مرحبا"
        let items = run(word)
        #expect(items.count == word.count)
        #expect(items.map(\.text).joined() == String(word.reversed()))
        for (a, b) in zip(items, items.dropFirst()) { #expect(a.pen < b.pen) }
    }

    /// Every piece's advance is the pen movement the shaper reported, so the
    /// advances sum to the line's own width in any script.
    ///
    /// The counterfactual is the arithmetic this replaced: taking each advance as
    /// the gap to the next glyph in array order. Arabic glyph positions are not
    /// monotonic in that order (a mark is stored after the letter it sits on, at a
    /// larger x), so the difference goes negative, clamps to zero, and the total
    /// comes out wrong.
    @Test func advancesSumToTheLineWidth() {
        for string in ["Ollin", "مرحبا", "क्षि", "ภาษาไทย", "日本語"] {
            let total = run(string).reduce(0) { $0 + $1.advance }
            let width = font.width(of: string, size: size, direction: .automatic)
            #expect(abs(total - width) < 0.01, "\(string): \(total) vs \(width)")
        }
    }

    /// Per-piece drawing and plain drawing have to put the same ink in the same
    /// place. This is what pins the vertical offsets: Thai stacks a vowel and a
    /// tone mark above the letter, and Arabic hangs its harakat above and below, so
    /// a path that only carried the horizontal position would drop every mark onto
    /// the baseline. Both paths are asked for the same frame (left, baseline, at
    /// the origin) and their ink bounds compared.
    @Test func perPieceDrawingPutsInkWherePlainDrawingDoes() {
        // Arabic harakat carry a vertical offset of up to 0.06 em and a combining
        // diaeresis about 0.017, so at this size a dropped mark moves several
        // pixels. Every glyph is compared on its own: a whole-line bounding box
        // cannot see it, because the mark is never the highest or lowest ink.
        for string in ["مَرْحَبًا", "q̈", "ที่นี่", "क्षि", "Ollin"] {
            let plain = font.glyphShapes(for: string, size: size, alignH: .left,
                                         alignV: .baseline, direction: .automatic,
                                         at: Vector2(0, 0))
            var pieces: [Shape] = []
            for item in run(string) {
                pieces.append(contentsOf: item.localShapes.map { $0.mapPoints { p in
                    Vector2(p.x + item.pen, p.y)
                } })
            }
            #expect(pieces.count == plain.count, "\(string) piece count")
            // The two paths flatten curves at different densities (one simplifies a
            // reference-scale outline), so shapes are matched by where they sit.
            let a = plain.map(bounds(of:)).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            let b = pieces.map(bounds(of:)).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
            for (one, other) in zip(a, b) {
                #expect(abs(one.x - other.x) < 0.5, "\(string) x")
                #expect(abs(one.y - other.y) < 0.5, "\(string) y")
                #expect(abs(one.height - other.height) < 0.5, "\(string) height")
            }
        }
    }

    private func bounds(of shape: Shape) -> Rectangle { bounds(of: [shape]) }

    private func bounds(of shapes: [Shape]) -> Rectangle {
        var lo = Vector2(.infinity, .infinity), hi = Vector2(-.infinity, -.infinity)
        for shape in shapes {
            for contour in shape.contours {
                for p in contour.points {
                    lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
                    hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
                }
            }
        }
        return Rectangle(x: lo.x, y: lo.y, width: hi.x - lo.x, height: hi.y - lo.y)
    }

    /// The grouping rule on its own, with glyphs made by hand so the answer does
    /// not depend on which fonts a machine has. A ligature is one glyph standing
    /// for two characters: the shaper reports it at the first of them and says
    /// nothing about the second, so the second has to join the piece before it
    /// rather than becoming an empty piece of its own.
    @Test func aLigatureKeepsBothCharactersInOnePiece() {
        let face = OutlineFont.system.ctFont
        let glyphs = [
            ShapedGlyph(font: face, glyph: 1, x: 0, y: 0, advance: 0.7, stringIndex: 0),
            ShapedGlyph(font: face, glyph: 2, x: 0.7, y: 0, advance: 0.4, stringIndex: 2),
        ]
        let clusters = TextClusters.group(glyphs, in: "fix")
        #expect(clusters.map(\.text) == ["fi", "x"])
        #expect(clusters[0].advance == 0.7)
    }

    /// A character with no glyph at the very start of a line has nothing before it
    /// to join, so it waits for the first piece instead of being dropped.
    @Test func aCharacterWithNoGlyphOfItsOwnIsNeverLost() {
        let face = OutlineFont.system.ctFont
        let glyphs = [ShapedGlyph(font: face, glyph: 1, x: 0, y: 0, advance: 1, stringIndex: 1)]
        let clusters = TextClusters.group(glyphs, in: "ab")
        #expect(clusters.count == 1)
        #expect(clusters[0].text == "ab")
    }

    // MARK: Direction

    /// A line opening with a bracket has no direction of its own to read, so the
    /// base direction decides which end that bracket sits at. Naming the direction
    /// is the only way to say which reading is meant.
    @Test func theBaseDirectionDecidesWhereTheBracketLands() {
        let line = "(1) مرحبا"
        #expect(run(line, .leftToRight).first?.text == "(")
        #expect(run(line, .rightToLeft).first?.text == "ا")
        // Left to right also ends on the Arabic rather than starting with it.
        #expect(run(line, .leftToRight).last?.text == "م")
    }

    /// Direction reorders a line; it never changes how wide it is.
    @Test func directionDoesNotChangeTheWidth() {
        let line = "(1) مرحبا"
        let widths = [TextDirection.automatic, .leftToRight, .rightToLeft].map {
            font.width(of: line, size: size, direction: $0)
        }
        #expect(abs(widths[0] - widths[1]) < 0.01)
        #expect(abs(widths[1] - widths[2]) < 0.01)
    }

    // MARK: Pictures

    /// An emoji is stored as a picture, not as contours. Asking for its outline
    /// gives nothing at all, which is why it used to draw as empty space: the
    /// picture is the only thing there is to draw.
    @Test func anEmojiIsAPictureRatherThanAnOutline() {
        let items = run("👋")
        #expect(items.count == 1)
        #expect(items[0].localShapes.isEmpty)
        let picture = items[0].picture
        #expect(picture != nil)
        #expect((picture?.width ?? 0) > 0)
        #expect(items[0].localPictureRect.width > 0)
        // It sits on the line: above the baseline, and about as wide as it advances.
        #expect(items[0].localPictureRect.y < 0)
        #expect(items[0].localPictureRect.width > items[0].advance * 0.5)
    }

    /// The picture is rasterized at the largest strike the font carries, so asking
    /// for a bigger one only upsamples the same bitmap. The size is fixed rather
    /// than following `textSize`, which is what keeps one raster per glyph.
    @Test func onePictureServesEverySize() {
        let small = run("👋").first?.picture
        let large = font.glyphRun(for: "👋", size: 400, direction: .automatic).first?.picture
        #expect(small?.width == large?.width)
        #expect(small?.height == large?.height)
    }

    /// Geometry is honest about what it cannot hand back: a picture has no
    /// contours, so `textToShapes` leaves it out rather than inventing an outline.
    @Test func geometryLeavesPicturesOut() {
        let drawer = Drawer()
        drawer.textSize(size)
        #expect(drawer.textToShapes("👋", 0, 0).isEmpty)
        #expect(!drawer.textToShapes("hi", 0, 0).isEmpty)
    }

    // MARK: Fallback

    /// Asking a Latin font for Japanese does not fail. The system borrows a face
    /// that has the letters, which is why text in any script draws at all, and this
    /// is how a sketch can see it happening.
    @Test func fallbackNamesEveryFaceTheLineBorrowed() {
        let names = font.fontsUsed(for: "Ollin 日本語 👋")
        #expect(names.count >= 3)
        #expect(names.contains { $0.contains("Emoji") })
        #expect(font.fontsUsed(for: "Ollin").count == 1)
    }

    /// A character no installed face can draw lands on the system's last resort
    /// face, which draws a box. It is visible rather than missing, and asking finds
    /// it before anything is drawn.
    @Test func missingCharactersFindsWhatNothingCanDraw() {
        #expect(font.missingCharacters(in: "Ollin 日本語").isEmpty)
        #expect(font.missingCharacters(in: "a\u{10FFFD}b") == ["\u{10FFFD}"])
    }

    /// A bitmap font has only the glyphs in its own file, so the same question has
    /// a much longer answer there. This is the case a sketch actually needs to ask
    /// about, because those characters draw nothing at all. Which ones are missing
    /// is not guessable either: the bundled face carries the Japanese in this test
    /// and not the Devanagari.
    @Test func aBitmapFontReportsWhatItCannotDraw() {
        let drawer = Drawer()
        drawer.textFont(BitmapFont.builtIn)
        #expect(drawer.textMissingCharacters("Ollin").isEmpty)
        #expect(drawer.textMissingCharacters("日本語").isEmpty)
        #expect(drawer.textMissingCharacters("मनम").count == 3)
        #expect(drawer.textMissingCharacters("a👋b") == ["👋"])
    }

    // MARK: Line breaking

    /// The pieces a line may be built from join back into the string exactly, so
    /// wrapping can never lose or duplicate a character.
    @Test func breakPiecesRebuildTheString() {
        for string in ["hello wide world", "日本語のテキスト", "ภาษาไทยคือภาษาราชการ",
                       "Ollin, a framework.", "", "x"] {
            #expect(LineBreaks.pieces(of: string).joined() == string)
        }
    }

    /// Where a line may break comes from the script, not from the spaces. Japanese
    /// breaks between characters; Thai breaks between words that nothing in the
    /// string separates; English breaks after spaces, which ride with the word
    /// before them.
    @Test func eachScriptBreaksItsOwnWay() {
        #expect(LineBreaks.pieces(of: "日本語") == ["日", "本", "語"])
        #expect(LineBreaks.pieces(of: "ภาษาไทย") == ["ภาษา", "ไทย"])
        #expect(LineBreaks.pieces(of: "hello wide world") == ["hello ", "wide ", "world"])
    }

    /// The point of all that: a paragraph with no spaces in it still fits its box.
    /// Splitting on spaces gives one long line that runs off the edge.
    @Test func aBoxWrapsTextThatHasNoSpacesInIt() {
        let drawer = Drawer()
        drawer.textSize(32)
        let japanese = String(repeating: "日本語のテキストです", count: 3)
        let lines = drawer.wrapToExtent(japanese, 300).split(separator: "\n")
        #expect(lines.count > 1)
        for line in lines { #expect(drawer.textWidth(String(line)) <= 300.5) }
        #expect(lines.joined() == japanese)
    }

    /// Japanese typesetting forbids certain characters at the edge of a line: a
    /// full stop, a comma, a closing bracket or a small kana may not open one, and
    /// an opening bracket may not close one. Those rules come with the system's
    /// break set rather than from a table written here, because the piece a line is
    /// built from is already the unit that may not be split: a comma arrives joined
    /// to the character it follows, an opening bracket to the one it precedes.
    /// Filling greedily by whole pieces therefore carries the forbidden character
    /// onto the next line along with its neighbor, which is what the rules ask for.
    ///
    /// The second half of the test is the counterfactual, and it is why the first
    /// half means anything: the obvious way to wrap a language with no spaces is to
    /// break between characters, and that *does* strand a comma at the start of a
    /// line. Widths are swept because a rule about line edges is only tested where a
    /// line actually ends.
    @Test func japaneseKeepsForbiddenCharactersOffTheEdgesOfALine() {
        let drawer = Drawer()
        drawer.textSize(32)
        let text = "彼は「ちょっと待って（急いで）ね」と言った。それは、きっと100%の力で!!やる。"
        let mayNotOpen = Set("、。」）！!%っゃゅょ")
        let mayNotClose = Set("「（")

        var lineCount = 0
        for width in stride(from: 140.0, through: 620.0, by: 20.0) {
            let lines = drawer.wrapToExtent(text, width).split(separator: "\n")
            #expect(lines.count > 1)
            for line in lines {
                guard let first = line.first, let last = line.last else { continue }
                #expect(!mayNotOpen.contains(first), "\(first) opened a line at width \(width)")
                #expect(!mayNotClose.contains(last), "\(last) closed a line at width \(width)")
                lineCount += 1
            }
        }
        #expect(lineCount > 20)

        // Breaking between characters instead, which is what a language with no
        // spaces invites, strands one of them at least once over the same sweep.
        var stranded = 0
        for width in stride(from: 140.0, through: 620.0, by: 20.0) {
            var line = ""
            for character in text {
                if !line.isEmpty, drawer.textWidth(line + String(character)) > width {
                    if let first = line.first, mayNotOpen.contains(first) { stranded += 1 }
                    line = ""
                }
                line.append(character)
            }
            if let first = line.first, mayNotOpen.contains(first) { stranded += 1 }
        }
        #expect(stranded > 0)
    }

    /// A line broken at a space does not keep that space, so centered text stays
    /// centered on its letters.
    @Test func wrappingLeavesNoTrailingSpace() {
        let drawer = Drawer()
        drawer.textSize(32)
        let wrapped = drawer.wrapToExtent("the quick brown fox jumps over the lazy dog", 300)
        for line in wrapped.split(separator: "\n") {
            #expect(line.last?.isWhitespace != true)
            #expect(drawer.textWidth(String(line)) <= 300.5)
        }
    }

    // MARK: Reproducibility

    /// Laying a line out twice gives the same answer, in every script, so a frame
    /// exports the same way it drew.
    @Test func layoutRepeats() {
        for string in ["Ollin", "مرحبا", "क्षि", "hi 👋"] {
            let first = run(string), second = run(string)
            #expect(first.count == second.count)
            for (a, b) in zip(first, second) {
                #expect(a.text == b.text)
                #expect(a.pen == b.pen)
                #expect(a.advance == b.advance)
            }
        }
    }
}

/// The picture path has to reach the canvas, which only a render can show.
/// Metal-gated.
@Suite @MainActor
struct ComplexTextRenderProbes {

    /// An emoji puts its own colors on the canvas.
    ///
    /// Two things are measured at once, and both are the defect this fixes: the
    /// emoji leaves ink at all (it used to leave none, because it has no outline
    /// to fill), and that ink is not the fill color (it is a picture carrying its
    /// own colors, not a shape taking the current paint).
    @Test(.enabled(if: Snapshot.hasMetal))
    func anEmojiDrawsItsOwnColors() throws {
        let image = try #require(OllinApp.image(of: EmojiProbe.make("👋"), frame: 1))
        let counts = EmojiProbe.tally(image)
        #expect(counts.ink > 500, "the emoji left \(counts.ink) marked pixels")
        #expect(counts.colored > counts.ink / 4,
                "only \(counts.colored) of \(counts.ink) marked pixels carry their own color")
    }

    /// The volume path draws it too. A distance field holds one channel, so a
    /// picture cannot ride the atlas; it goes down the image path beside the atlas
    /// quads instead, and the two modes have to agree.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theAtlasPathDrawsAnEmojiToo() throws {
        let outline = try #require(OllinApp.image(of: EmojiProbe.make("👋"), frame: 1))
        let atlas = try #require(OllinApp.image(of: EmojiProbe.make("👋", mode: .atlas), frame: 1))
        let a = EmojiProbe.tally(outline), b = EmojiProbe.tally(atlas)
        #expect(b.ink > 500)
        #expect(a.ink == b.ink)
        #expect(a.colored == b.colored)
    }

    /// The control: the same call with a letter in place of the emoji marks the
    /// canvas in the fill color alone, so the check above is measuring the picture
    /// path rather than anything the text path does in general.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLetterDrawsInTheFillColor() throws {
        let image = try #require(OllinApp.image(of: EmojiProbe.make("O"), frame: 1))
        let counts = EmojiProbe.tally(image)
        #expect(counts.ink > 500)
        #expect(counts.colored < counts.ink / 20)
    }
}

/// One character on a white canvas, filled black, so a colored pixel can only have
/// come from a picture the font carried.
final class EmojiProbe: Sketch {
    var text = "O"
    var mode: TextMode = .outline

    static func make(_ text: String, mode: TextMode = .outline) -> EmojiProbe {
        let probe = EmojiProbe()
        probe.text = text
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(200) }
    override func setup() { noLoop() }
    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        textMode(mode)
        textSize(140)
        textAlign(.center, .middle)
        drawText(text, at: Vector2(100, 100))
    }

    /// Marked pixels, and how many of those carry a color rather than a gray.
    static func tally(_ image: CGImage) -> (ink: Int, colored: Int) {
        let w = image.width, h = image.height
        var raw = [UInt8](repeating: 0, count: w * h * 4)
        raw.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var ink = 0, colored = 0
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Int(raw[i]), g = Int(raw[i + 1]), b = Int(raw[i + 2])
            guard min(r, min(g, b)) < 230 else { continue }   // not paper
            ink += 1
            if max(r, max(g, b)) - min(r, min(g, b)) > 40 { colored += 1 }
        }
        return (ink, colored)
    }
}
