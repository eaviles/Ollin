import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import Ollin

/// A face that ships with the system and carries the vertical forms. The test that
/// wants one reports itself skipped where it is missing, rather than passing on
/// nothing.
private func japaneseCTFont() -> CTFont {
    CTFontCreateWithName("HiraginoSans-W3" as CFString, 1.0, nil)
}
private let hasJapaneseFace = (CTFontCopyPostScriptName(japaneseCTFont()) as String).contains("Hiragino")

/// Text set in columns, the way Japanese and Chinese are often written.
///
/// The whole feature is the layout, so every check here measures where a piece
/// landed rather than how it looks. Each one names the horizontal twin it is
/// compared against, because "it moved" is only interesting beside the same text
/// set the ordinary way.
@Suite @MainActor
struct VerticalTextTests {
    private let font = OutlineFont.systemMedium
    private let size = 100.0
    private let japanese = "春はあけぼの"

    private func run(_ string: String, _ direction: TextDirection) -> [GlyphRunItem] {
        font.glyphRun(for: string, size: size, direction: direction)
    }

    private func placed(_ string: String, _ direction: TextDirection,
                        alignH: TextAlignH = .left, alignV: TextAlignV = .baseline,
                        at origin: Vector2 = Vector2(0, 0)) -> [Shape] {
        font.glyphShapes(for: string, size: size, alignH: alignH, alignV: alignV,
                         direction: direction, at: origin)
    }

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

    // MARK: The column

    /// The text runs down rather than across: each piece sits below the one before
    /// it and they share a column, where the same string set the ordinary way
    /// spreads sideways along one height.
    @Test func aColumnRunsDownAndALineRunsAcross() {
        let column = placed(japanese, .topToBottom).map { bounds(of: [$0]) }
        let line = placed(japanese, .automatic).map { bounds(of: [$0]) }
        #expect(column.count == japanese.count)
        #expect(line.count == japanese.count)

        for (a, b) in zip(column, column.dropFirst()) { #expect(a.y < b.y) }
        for (a, b) in zip(line, line.dropFirst()) { #expect(a.x < b.x) }

        // A column is one em across and as long as its glyphs; a line is the other
        // way about.
        let columnBox = bounds(of: placed(japanese, .topToBottom))
        let lineBox = bounds(of: placed(japanese, .automatic))
        #expect(columnBox.height > columnBox.width * 3)
        #expect(lineBox.width > lineBox.height * 3)
    }

    /// A column is read from the top, so its pieces come out in that order: the
    /// first piece a per-glyph effect is handed is the first character of the text,
    /// and a sweep runs down the column rather than up it.
    ///
    /// Ordering is easy to lose and hard to see. Every piece keeps its own distance
    /// down the run whichever way the list is sorted, so a reversed column still
    /// measures perfectly and still lands its ink in the right places: only the
    /// character each piece stands for gives it away.
    @Test func aColumnsPiecesComeOutInReadingOrder() {
        let items = run(japanese, .topToBottom)
        #expect(items.map(\.text).joined() == japanese)
        for (a, b) in zip(items, items.dropFirst()) { #expect(a.pen < b.pen) }
    }

    /// The distance down the column is the advances added up, so a column is
    /// exactly as long as the text says it is.
    @Test func piecesAdvanceByTheirOwnSize() {
        let items = run(japanese, .topToBottom)
        var reached = 0.0
        for item in items {
            #expect(abs(item.pen - reached) < 0.01)
            reached += item.advance
        }
        let length = font.width(of: japanese, size: size, direction: .topToBottom)
        #expect(abs(reached - length) < 0.01)
    }

    /// A new line starts the next column to the *left*, which is the direction this
    /// writing fills in. The horizontal twin puts its second line below the first
    /// and leaves the x alone.
    @Test func columnsFillRightToLeft() {
        let vertical = font.placedGlyphs(for: "あ\nい", size: size, alignH: .left,
                                         alignV: .baseline, direction: .topToBottom,
                                         at: Vector2(500, 100))
        let first = vertical.first!.origin, last = vertical.last!.origin
        #expect(last.x < first.x - size / 2)      // a whole column to the left
        // Both columns start at the top. The two glyphs are allowed to differ by a
        // hair, because each carries its own vertical origin from the font.
        #expect(abs(last.y - first.y) < 0.5)

        let horizontal = font.placedGlyphs(for: "あ\nい", size: size, alignH: .left,
                                           alignV: .baseline, direction: .automatic,
                                           at: Vector2(500, 100))
        #expect(horizontal.last!.origin.y > horizontal.first!.origin.y)
        #expect(abs(horizontal.last!.origin.x - horizontal.first!.origin.x) < 0.01)
    }

    // MARK: The glyphs themselves

    /// The font keeps a second shape for the characters that must turn, and asking
    /// for vertical setting is what picks them. A bracket is the clearest case: it
    /// is taller than it is wide along a line, and wider than it is tall down a
    /// column. Nothing here rotates anything, so if the wrong glyph came back the
    /// bracket would stay upright.
    @Test func theSidewaysFormsAreTheOnesTheFontKeeps() {
        let across = bounds(of: placed("（", .automatic))
        let down = bounds(of: placed("（", .topToBottom))
        #expect(across.height > across.width * 2)
        #expect(down.width > down.height * 2)
    }

    /// A comma belongs at the bottom left of its square along a line and at the top
    /// right of it down a column, which is a move the reader would notice at once.
    /// Measured against the square the piece occupies, not against the canvas.
    @Test func aCommaMovesToTheOppositeCornerOfItsSquare() {
        let across = bounds(of: placed("、", .automatic, at: Vector2(0, 0)))
        // Along a line the pen sits on the baseline at the origin, so ink above the
        // baseline is negative y and the comma hangs at the bottom: near y = 0.
        #expect(across.y > -size * 0.35)

        // Down a column the square starts at the origin and the comma sits in its
        // top half.
        let down = bounds(of: placed("、", .topToBottom, at: Vector2(0, 0),
                                     alignHV: (.left, .top)))
        #expect(down.y < size * 0.5)
    }

    /// Whether Latin turns is the *face's* decision, not Ollin's, and both answers
    /// are correct. A Japanese face keeps a turned A for vertical setting, so a word
    /// in the middle of a column reads sideways as a reader expects. A Latin face
    /// keeps no such form, so its A stays upright and the column is a stack of
    /// letters. Since nothing here rotates a glyph, what the sketch gets is whatever
    /// the font it chose has.
    @Test(.enabled(if: hasJapaneseFace))
    func whetherLatinTurnsIsTheFacesDecision() throws {
        let jp = OutlineFont(ctFont: japaneseCTFont())
        let turned = bounds(of: jp.glyphShapes(for: "A", size: size, alignH: .left,
                                               alignV: .top, direction: .topToBottom,
                                               at: Vector2(0, 0)))
        #expect(turned.width > turned.height)

        // The Latin face, same request, keeps its letter upright.
        let upright = bounds(of: placed("A", .topToBottom))
        #expect(upright.height > upright.width)
    }

    // MARK: Where the block lands

    /// The two alignment axes swap roles, so the vertical one now says where a
    /// column starts and the horizontal one places the block of columns. Each is
    /// checked against the ink itself rather than against the reported bounds.
    @Test func alignmentSwapsAxes() {
        let anchor = Vector2(500, 400)
        let length = font.width(of: japanese, size: size, direction: .topToBottom)

        let top = bounds(of: placed(japanese, .topToBottom, at: anchor, alignHV: (.left, .top)))
        let middle = bounds(of: placed(japanese, .topToBottom, at: anchor, alignHV: (.left, .middle)))
        let bottom = bounds(of: placed(japanese, .topToBottom, at: anchor, alignHV: (.left, .bottom)))
        #expect(abs(middle.center.y - anchor.y) < size * 0.2)
        #expect(top.y > middle.y)
        #expect(bottom.y < middle.y)
        #expect(abs((top.y - bottom.y) - length) < size * 0.3)

        // Across the columns: one column is one em wide, so `.left` puts its left
        // edge on the anchor and `.right` its right edge.
        let left = bounds(of: placed(japanese, .topToBottom, at: anchor, alignHV: (.left, .top)))
        let right = bounds(of: placed(japanese, .topToBottom, at: anchor, alignHV: (.right, .top)))
        #expect(left.x > anchor.x - 1)
        #expect(right.x + right.width < anchor.x + 1)
    }

    /// The bounds a sketch can ask for have to hold the ink that gets drawn, or
    /// laying anything out beside the text is guesswork.
    ///
    /// The tolerance is there because these are advance boxes, in either direction:
    /// a glyph is drawn a little outside the square it advances by, so the ink can
    /// sit a couple of points proud of the box at this size. It is nowhere near a
    /// column width, which is what a misplaced block would cost.
    @Test func theReportedBoundsHoldTheInk() {
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(size)
        drawer.textDirection(.topToBottom)
        for alignment in [(TextAlignH.left, TextAlignV.top), (.center, .middle), (.right, .bottom)] {
            drawer.textAlign(alignment.0, alignment.1)
            let reported = drawer.textBounds("あいう\nえお", 400, 300)
            let ink = bounds(of: font.glyphShapes(for: "あいう\nえお", size: size,
                                                  alignH: alignment.0, alignV: alignment.1,
                                                  direction: .topToBottom, at: Vector2(400, 300)))
            let slack = size * 0.05
            #expect(ink.x >= reported.x - slack)
            #expect(ink.y >= reported.y - slack)
            #expect(ink.x + ink.width <= reported.x + reported.width + slack)
            #expect(ink.y + ink.height <= reported.y + reported.height + slack)
        }
    }

    /// Per-piece drawing and plain drawing put the same ink in the same place, the
    /// vertical twin of the horizontal check.
    ///
    /// This is what pins the arithmetic that was easiest to get wrong. A piece's own
    /// frame starts at the top edge of its square, while the layout engine reports
    /// each glyph at its baseline, one ascent further down. Measuring the piece from
    /// the glyph instead of from the square would slide every column by that ascent.
    @Test func perPieceDrawingPutsInkWherePlainDrawingDoes() {
        for string in [japanese, "AとB", "（あ）"] {
            let plain = font.glyphShapes(for: string, size: size, alignH: .left,
                                         alignV: .top, direction: .topToBottom,
                                         at: Vector2(0, 0))
            // The same frame the drawer builds: the column axis half an em in from
            // the left edge, the run starting at the anchor.
            var pieces: [Shape] = []
            for item in run(string, .topToBottom) {
                pieces.append(contentsOf: item.localShapes.map { $0.mapPoints { p in
                    Vector2(p.x + size / 2, p.y + item.pen)
                } })
            }
            #expect(pieces.count == plain.count, "\(string) piece count")
            let a = plain.map { bounds(of: [$0]) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            let b = pieces.map { bounds(of: [$0]) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            for (one, other) in zip(a, b) {
                #expect(abs(one.x - other.x) < 0.5, "\(string) x")
                #expect(abs(one.y - other.y) < 0.5, "\(string) y")
            }
        }
    }

    // MARK: What it does not do

    /// A bitmap font has no sideways forms and no engine to place a column with, so
    /// it says so and stays horizontal rather than drawing something wrong.
    @Test func aBitmapFontStaysHorizontal() {
        let drawer = Drawer()
        drawer.textFont(BitmapFont.builtin)
        drawer.textSize(size)
        drawer.textDirection(.topToBottom)
        #expect(drawer.runsVertically == false)

        drawer.textFont(font)
        #expect(drawer.runsVertically == true)
    }

    /// A box wraps against the room the text actually has: its height down a
    /// column, where a line wraps against the width. Set the same box and the same
    /// text both ways and the two disagree, which is the point.
    @Test func aBoxWrapsAgainstTheAxisTheTextTravels() {
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(32)
        let text = String(repeating: "日本語のテキストです", count: 3)

        drawer.textDirection(.topToBottom)
        let columns = drawer.wrapToExtent(text, 300).split(separator: "\n")
        #expect(columns.count > 1)
        for column in columns {
            #expect(drawer.textWidth(String(column)) <= 300.5)
        }
        #expect(columns.joined() == text)
    }

    // MARK: Justification

    /// A justified block runs the full width of its box on every line but the last
    /// of a paragraph, where the plain block is ragged. Both are measured off the
    /// ink, which is what a reader sees.
    @Test func justifiedLinesReachBothEdgesOfTheBox() {
        let box = Rectangle(x: 0, y: 0, width: 520, height: 400)
        let text = "the quick brown fox jumps over the lazy dog and keeps running well past the edge of the box"
        let ragged = lineWidths(of: text, in: box, justified: false)
        let flush = lineWidths(of: text, in: box, justified: true)
        #expect(ragged.count == flush.count)
        #expect(ragged.count > 2)

        // Every line but the last is stretched to the box, and every one of them was
        // short of it before.
        for index in 0..<(flush.count - 1) {
            #expect(flush[index] > box.width * 0.94, "line \(index) at \(flush[index])")
            #expect(ragged[index] < flush[index] - 1, "line \(index) did not move")
        }
    }

    /// The last line of a paragraph keeps its natural width. Stretching a line that
    /// is short because the writing ended is the mistake everybody recognizes, so it
    /// is checked on its own, against the same line unjustified.
    @Test func theLastLineOfAParagraphIsLeftAlone() {
        let box = Rectangle(x: 0, y: 0, width: 520, height: 400)
        let text = "the quick brown fox jumps over the lazy dog and keeps running well past the edge of the box"
        let ragged = lineWidths(of: text, in: box, justified: false)
        let flush = lineWidths(of: text, in: box, justified: true)
        #expect(abs(ragged.last! - flush.last!) < 0.5)
        #expect(flush.last! < box.width * 0.9)
    }

    /// Two paragraphs, so the rule is about paragraphs and not about the block: the
    /// first paragraph's own last line is left alone too, in the middle of the text.
    @Test func everyParagraphKeepsItsOwnLastLine() {
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(28)
        let (lines, ends) = drawer.wrappedLines("the quick brown fox jumps over it\nand a second paragraph here", 300)
        #expect(lines.count > 2)
        #expect(ends.count == 2)
        #expect(ends.contains(lines.count - 1))
        // The end of the first paragraph is somewhere in the middle of the block.
        #expect(ends.contains { $0 < lines.count - 1 })
    }

    /// Justification stretches whichever way the text travels, so a column reaches
    /// the bottom of its box the way a line reaches its right edge. The system's
    /// layout engine puts the extra room between the characters here, since Japanese
    /// has no spaces to open up.
    @Test func aColumnJustifiesDownTheBoxToo() {
        let box = Rectangle(x: 0, y: 0, width: 400, height: 520)
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(40)
        drawer.textDirection(.topToBottom)
        drawer.textAlign(.right, .top)

        let text = String(repeating: "日本語のテキストです", count: 3)
        let (lines, ends) = drawer.wrappedLines(text, box.height)
        #expect(lines.count > 1)

        let natural = font.width(of: lines[0], size: 40, direction: .topToBottom)
        #expect(natural < box.height)
        let stretched = bounds(of: font.glyphShapes(
            for: lines[0], size: 40, alignH: .right, alignV: .top,
            direction: .topToBottom,
            justify: TextJustification(extent: box.height, naturalLines: ends),
            at: Vector2(box.x + box.width, box.y)))
        #expect(stretched.height > box.height * 0.9)
        #expect(stretched.height > natural + 1)
    }

    /// Justification is the box's business, so text drawn at a plain position is
    /// untouched by it: there is nothing there that says how far a line should run.
    @Test func textAtAPlainPositionIsNeverStretched() {
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(28)
        drawer.textJustify()
        #expect(drawer.textJustification == nil)
        let before = drawer.textWidth("a short line")
        drawer.textJustify(false)
        #expect(drawer.textWidth("a short line") == before)
    }

    /// Every line's ink, in the order the box laid them out.
    private func lineWidths(of text: String, in box: Rectangle, justified: Bool) -> [Double] {
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(28)
        let (lines, ends) = drawer.wrappedLines(text, box.width)
        let justify = justified ? TextJustification(extent: box.width, naturalLines: ends) : nil
        return lines.indices.map { index in
            let shapes = font.glyphShapes(for: lines[index], size: 28, alignH: .left,
                                          alignV: .top, direction: .automatic,
                                          justify: justify.map {
                                              // One line at a time, so it has to be
                                              // told whether this one is a paragraph's
                                              // last rather than being line 0 always.
                                              TextJustification(extent: $0.extent,
                                                                naturalLines: ends.contains(index) ? [0] : [])
                                          },
                                          at: Vector2(box.x, box.y))
            return bounds(of: shapes).width
        }
    }

    /// Laying a column out twice gives the same answer, so an export repeats.
    @Test func layoutRepeats() {
        let first = run(japanese, .topToBottom), second = run(japanese, .topToBottom)
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.text == b.text)
            #expect(a.pen == b.pen)
            #expect(a.advance == b.advance)
        }
    }
}

private extension VerticalTextTests {
    func placed(_ string: String, _ direction: TextDirection, at origin: Vector2,
                alignHV: (TextAlignH, TextAlignV)) -> [Shape] {
        font.glyphShapes(for: string, size: size, alignH: alignHV.0, alignV: alignHV.1,
                         direction: direction, at: origin)
    }
}
