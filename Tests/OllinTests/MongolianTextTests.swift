import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import Ollin

/// A face that ships with the system and has the script. The suite reports itself
/// skipped where it is missing, rather than passing on nothing.
private let mongolianFace = OutlineFont(name: "Noto Sans Mongolian")
private let hasMongolianFace = mongolianFace != nil

/// Text set in columns that fill left to right, the way traditional Mongolian is
/// written.
///
/// The column order is the easy half. The half worth testing is that this writing
/// joins: a word is one connected stroke and every letter takes its own width, so
/// the line is shaped the way a horizontal line is and then turned a quarter turn
/// clockwise. Every check below therefore names what it is compared against, since
/// "it went down the page" is true of the other vertical mode too.
@Suite(.enabled(if: hasMongolianFace)) @MainActor
struct MongolianTextTests {
    private var font: OutlineFont { mongolianFace! }
    private let size = 100.0
    /// The script's own name for itself, "Mongol bichig". Two words, so a check can
    /// see the gap between them as well as the joins inside them.
    private let phrase = "ᠮᠣᠩᠭᠣᠯ ᠪᠢᠴᠢᠭ"
    private let word = "ᠮᠣᠩᠭᠣᠯ"

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

    // MARK: The turn

    /// The whole mechanism in one check: a column is the horizontal line turned a
    /// quarter turn clockwise, glyph for glyph.
    ///
    /// Both are laid out from their own start point, and the two start points are
    /// known: a line starts on its baseline at the anchor, a column starts on its
    /// axis at the top, one descent in from the block's left edge. So each glyph's
    /// box has an exact place to land, and a turn the wrong way, a turn about the
    /// wrong point, or no turn at all each miss it by more than a glyph.
    @Test func aColumnIsTheLineTurnedAQuarterTurnClockwise() {
        let line = placed(phrase, .automatic, alignH: .left, alignV: .baseline).map { bounds(of: [$0]) }
        let column = placed(phrase, .topToBottomLeftToRight, alignH: .left, alignV: .top)
            .map { bounds(of: [$0]) }
        #expect(line.count == column.count)
        #expect(line.count >= 8)

        let descent = font.descent * size
        for (flat, turned) in zip(line, column) {
            // A point (x, y) from the line's start lands at (descent - y, x) from the
            // column's, so the box's two axes swap and the y one runs backwards.
            #expect(abs(turned.x - (descent - (flat.y + flat.height))) < 0.5)
            #expect(abs(turned.y - flat.x) < 0.5)
            #expect(abs(turned.width - flat.height) < 0.5)
            #expect(abs(turned.height - flat.width) < 0.5)
        }
    }

    /// The letters join and keep their own widths, which is what separates this from
    /// the other vertical mode. Set on em squares, every piece would advance by
    /// exactly one em; here the advances differ from each other and the column is
    /// exactly as long as the same text set across a line.
    @Test func theLettersKeepTheirOwnWidthsRatherThanAnEmSquare() {
        let items = font.glyphRun(for: phrase, size: size, direction: .topToBottomLeftToRight)
        #expect(items.count >= 8)
        let advances = items.map(\.advance)
        #expect(advances.contains { abs($0 - size) > 1 })          // not all one em
        #expect(Set(advances.map { ($0 * 10).rounded() }).count > 2) // and not all alike

        // The column is the line, so it is exactly as long as the line is wide.
        let columnLength = font.width(of: phrase, size: size, direction: .topToBottomLeftToRight)
        let lineWidth = font.width(of: phrase, size: size, direction: .automatic)
        #expect(abs(columnLength - lineWidth) < 0.01)
    }

    /// The joins survive the turn. Inside a word the letters touch, so their boxes
    /// overlap or meet down the column; the space between the two words is a real
    /// gap. Shaping each letter on its own, or setting them on squares, would open a
    /// gap everywhere.
    @Test func theLettersTouchInsideAWordAndPartBetweenTwo() {
        let column = placed(phrase, .topToBottomLeftToRight, alignH: .left, alignV: .top)
            .map { bounds(of: [$0]) }
            .sorted { $0.y < $1.y }
        var gaps: [Double] = []
        for (a, b) in zip(column, column.dropFirst()) { gaps.append(b.y - (a.y + a.height)) }
        // One gap stands well clear of the others: the space between the two words.
        let widest = gaps.max()!
        let rest = gaps.filter { $0 < widest }
        #expect(widest > size * 0.15)
        #expect(rest.allSatisfy { $0 < widest / 2 })
    }

    // MARK: The columns

    /// A new line starts the next column to the *right*, which is the direction this
    /// writing fills in, and the opposite of the other vertical mode. Both are
    /// checked here, because one filling the wrong way is only visible beside the
    /// other.
    @Test func columnsFillLeftToRight() {
        // One letter in each column, so the second glyph really is the second
        // column's start rather than somewhere down its length.
        let pair = "ᠠ\nᠠ"
        let rightward = font.placedGlyphs(for: pair, size: size, alignH: .left,
                                          alignV: .top, direction: .topToBottomLeftToRight,
                                          at: Vector2(200, 100))
        #expect(rightward.count == 2)
        let first = rightward.first!.origin, last = rightward.last!.origin
        #expect(last.x > first.x + size / 2)      // a whole column to the right
        #expect(abs(last.y - first.y) < 0.5)      // both columns start at the top

        // The same two columns the other way about.
        let leftward = font.placedGlyphs(for: pair, size: size, alignH: .left,
                                         alignV: .top, direction: .topToBottom,
                                         at: Vector2(200, 100))
        #expect(leftward.last!.origin.x < leftward.first!.origin.x)
    }

    /// A column is read from the top, so its pieces come out in that order and each
    /// one keeps its own distance down the run.
    @Test func aColumnsPiecesComeOutInReadingOrder() {
        let items = font.glyphRun(for: phrase, size: size, direction: .topToBottomLeftToRight)
        #expect(items.map(\.text).joined() == phrase)
        for (a, b) in zip(items, items.dropFirst()) { #expect(a.pen < b.pen) }
    }

    /// The two alignment axes swap roles here as they do for the other vertical
    /// mode: the vertical one says where a column starts, the horizontal one places
    /// the block. Measured off the ink rather than the reported box.
    @Test func alignmentSwapsAxes() {
        let anchor = Vector2(500, 400)
        let length = font.width(of: phrase, size: size, direction: .topToBottomLeftToRight)

        let top = bounds(of: placed(phrase, .topToBottomLeftToRight, alignH: .left,
                                    alignV: .top, at: anchor))
        let middle = bounds(of: placed(phrase, .topToBottomLeftToRight, alignH: .left,
                                       alignV: .middle, at: anchor))
        let bottom = bounds(of: placed(phrase, .topToBottomLeftToRight, alignH: .left,
                                       alignV: .bottom, at: anchor))
        #expect(abs(middle.center.y - anchor.y) < size * 0.25)
        #expect(top.y > middle.y)
        #expect(bottom.y < middle.y)
        #expect(abs((top.y - bottom.y) - length) < size * 0.3)

        // Across the columns: `.left` puts the block's left edge on the anchor and
        // `.right` its right edge.
        let right = bounds(of: placed(phrase, .topToBottomLeftToRight, alignH: .right,
                                      alignV: .top, at: anchor))
        #expect(top.x > anchor.x - 1)
        #expect(right.x + right.width < anchor.x + 1)
    }

    /// The bounds a sketch can ask for have to hold the ink, or laying anything out
    /// beside the text is guesswork. A column here is as wide as the face's ascent
    /// and descent rather than one em, so this is the check that would catch the
    /// block being measured on the wrong width.
    @Test func theReportedBoundsHoldTheInk() {
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(size)
        drawer.textDirection(.topToBottomLeftToRight)
        let text = "\(word)\n\(word)"
        for alignment in [(TextAlignH.left, TextAlignV.top), (.center, .middle), (.right, .bottom)] {
            drawer.textAlign(alignment.0, alignment.1)
            let reported = drawer.textBounds(text, 400, 300)
            let ink = bounds(of: font.glyphShapes(for: text, size: size,
                                                  alignH: alignment.0, alignV: alignment.1,
                                                  direction: .topToBottomLeftToRight,
                                                  at: Vector2(400, 300)))
            let slack = size * 0.05
            #expect(ink.x >= reported.x - slack)
            #expect(ink.y >= reported.y - slack)
            #expect(ink.x + ink.width <= reported.x + reported.width + slack)
            #expect(ink.y + ink.height <= reported.y + reported.height + slack)
        }
    }

    /// Two columns do not sit on top of each other. A column set on em squares is one
    /// em across, and this writing needs more than that, so measuring it the other
    /// way would overlap the ink.
    @Test func twoColumnsDoNotOverlap() {
        let shapes = font.glyphShapes(for: "\(word)\n\(word)", size: size, alignH: .left,
                                      alignV: .top, direction: .topToBottomLeftToRight,
                                      at: Vector2(0, 0))
        let boxes = shapes.map { bounds(of: [$0]) }
        let split = boxes.map(\.center.x).max()! / 2
        let left = boxes.filter { $0.center.x < split }
        let right = boxes.filter { $0.center.x >= split }
        #expect(!left.isEmpty && !right.isEmpty)
        #expect(left.map { $0.x + $0.width }.max()! < right.map(\.x).min()!)
    }

    // MARK: The other paths

    /// The atlas path places its quads where the outline path places its ink, so
    /// `textMode(.atlas)` draws the same column rather than a second layout.
    @Test func theAtlasPathPlacesGlyphsWhereTheOutlinePathDoes() {
        let outline = font.placedGlyphs(for: phrase, size: size, alignH: .left, alignV: .top,
                                        direction: .topToBottomLeftToRight, at: Vector2(300, 200))
        let atlas = font.placedAtlasGlyphs(for: phrase, size: size, alignH: .left, alignV: .top,
                                           direction: .topToBottomLeftToRight, at: Vector2(300, 200))
        // The atlas keeps the spaces the outline path drops, so it is the longer list.
        #expect(atlas.count >= outline.count)
        #expect(atlas.allSatisfy { $0.turned })
        for glyph in outline {
            #expect(atlas.contains { abs($0.origin.x - glyph.origin.x) < 0.01
                                  && abs($0.origin.y - glyph.origin.y) < 0.01 })
        }
    }

    /// Per-piece drawing and plain drawing put the same ink in the same place, the
    /// turned twin of the checks the other two writing axes already carry. A piece's
    /// own frame here starts at its pen on the column axis, not at the top edge of a
    /// square, which is the arithmetic easiest to get wrong.
    @Test func perPieceDrawingPutsInkWherePlainDrawingDoes() {
        let plain = font.glyphShapes(for: phrase, size: size, alignH: .left, alignV: .top,
                                     direction: .topToBottomLeftToRight, at: Vector2(0, 0))
        // The same frame the drawer builds: the axis one descent in from the left
        // edge, the run starting at the anchor.
        var pieces: [Shape] = []
        for item in font.glyphRun(for: phrase, size: size, direction: .topToBottomLeftToRight) {
            pieces.append(contentsOf: item.localShapes.map { $0.mapPoints { p in
                Vector2(p.x + font.descent * size, p.y + item.pen)
            } })
        }
        #expect(pieces.count == plain.count)
        let a = plain.map { bounds(of: [$0]) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let b = pieces.map { bounds(of: [$0]) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        for (one, other) in zip(a, b) {
            #expect(abs(one.x - other.x) < 0.5)
            #expect(abs(one.y - other.y) < 0.5)
        }
    }

    /// A box wraps against the room the text has down the column, and the pieces it
    /// breaks between join back into the text it was given.
    @Test func aBoxWrapsDownTheColumn() {
        let drawer = Drawer()
        drawer.textFont(font)
        drawer.textSize(36)
        drawer.textDirection(.topToBottomLeftToRight)
        let text = Array(repeating: phrase, count: 6).joined(separator: " ")
        let columns = drawer.wrapToExtent(text, 300).split(separator: "\n")
        #expect(columns.count > 1)
        for column in columns {
            #expect(drawer.textWidth(String(column)) <= 300.5)
        }
        #expect(columns.joined(separator: " ") == text)
    }

    /// Laying a column out twice gives the same answer, so an export repeats.
    @Test func layoutRepeats() {
        let first = font.glyphRun(for: phrase, size: size, direction: .topToBottomLeftToRight)
        let second = font.glyphRun(for: phrase, size: size, direction: .topToBottomLeftToRight)
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.text == b.text)
            #expect(a.pen == b.pen)
            #expect(a.advance == b.advance)
        }
    }
}
