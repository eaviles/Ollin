import Testing
import Foundation
@testable import Ollin

/// A stop or comma at the end of a line, allowed to sit past that end.
///
/// The text below is full-width Japanese, where every character advances exactly
/// one em. That makes the box width an exact number of characters, so each check
/// is about the rule rather than about a font's measurements.
@Suite @MainActor
struct HangingPunctuationTests {
    private let font = OutlineFont.systemMedium
    private let size = 20.0
    /// Ten characters, a full stop, then five more. At ten ems the stop is the one
    /// character that will not fit.
    private let passage = "あいうえおかきくけこ。さしすせそ"
    private let boxExtent = 200.0

    private func drawer(hanging: Bool, direction: TextDirection = .automatic) -> Drawer {
        let d = Drawer()
        d.textFont(font)
        d.textSize(size)
        d.textDirection(direction)
        d.textHangingPunctuation(hanging)
        return d
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

    // MARK: The wrap

    /// The rule itself. A stop that will not fit normally takes the character it
    /// follows to the next line. Hanging leaves both where they are, and the stop
    /// keeps the line it was already on.
    @Test func aStopThatWillNotFitStaysOnItsLine() {
        let plain = drawer(hanging: false).wrappedLines(passage, boxExtent).lines
        let hung = drawer(hanging: true).wrappedLines(passage, boxExtent).lines
        // A stop may not open a line, so without hanging it goes to the next line
        // and takes the character it follows with it. That pair is what stays.
        #expect(plain[1].hasPrefix("こ。"))
        #expect(hung[0].hasSuffix("こ。"))
        #expect(hung[0].count == plain[0].count + 2)
        // And nothing was thrown away either way.
        #expect(plain.joined() == passage)
        #expect(hung.joined() == passage)
    }

    /// Only the stops and the commas hang. A closing bracket may not open a line
    /// either, and it stays inside the box, because hanging one would leave a hole
    /// where the bracket should have closed.
    @Test func onlyStopsAndCommasHang() {
        let text = "あいうえおかきくけこ）さしすせそ"
        let plain = drawer(hanging: false).wrappedLines(text, boxExtent).lines
        let hung = drawer(hanging: true).wrappedLines(text, boxExtent).lines
        #expect(plain == hung)
        #expect(hung.first?.hasSuffix("）") == false)
    }

    /// A comma hangs on the same terms as a stop.
    @Test func aCommaHangsToo() {
        let text = "あいうえおかきくけこ、さしすせそ"
        let hung = drawer(hanging: true).wrappedLines(text, boxExtent).lines
        #expect(hung.first?.hasSuffix("、") == true)
    }

    /// Off by default, and off means the wrap is exactly what it was.
    @Test func nothingChangesUntilItIsAskedFor() {
        let plain = Drawer()
        plain.textFont(font)
        plain.textSize(size)
        #expect(plain.textHangsPunctuation == false)
        #expect(plain.wrappedLines(passage, boxExtent).lines
                == drawer(hanging: false).wrappedLines(passage, boxExtent).lines)
    }

    /// It works down a column as readily as across a line, since a column wraps
    /// against the box the same way.
    @Test func itWorksDownAColumnToo() {
        let plain = drawer(hanging: false, direction: .topToBottom)
            .wrappedLines(passage, boxExtent).lines
        let hung = drawer(hanging: true, direction: .topToBottom)
            .wrappedLines(passage, boxExtent).lines
        #expect(plain.first?.hasSuffix("。") == false)
        #expect(hung.first?.hasSuffix("。") == true)
    }

    // MARK: Where the ink lands

    /// A hung stop is left out of how far the line counts as running, so the rest of
    /// the line lands where a line of that length would land and the stop sits past
    /// the end. Checked against the same text measured the ordinary way.
    @Test func theHungStopSitsPastTheEndOfTheLine() {
        let anchor = Vector2(500, 300)
        let line = "あい。"
        let held = font.glyphShapes(for: line, size: 100, alignH: .right, alignV: .baseline,
                                    direction: .automatic, at: anchor)
        let hung = font.glyphShapes(for: line, size: 100, alignH: .right, alignV: .baseline,
                                    direction: .automatic, hangs: true, at: anchor)
        // Held inside, the whole line ends at the anchor. Hanging, the stop is past
        // it, so the ink runs on.
        #expect(bounds(of: held).x + bounds(of: held).width <= anchor.x + 1)
        #expect(bounds(of: hung).x + bounds(of: hung).width > anchor.x)

        // The exact claim: a hanging line lands where the same line without its stop
        // would land, which is one whole advance to the right of holding it inside.
        let rest = font.glyphShapes(for: "あい", size: 100, alignH: .right, alignV: .baseline,
                                    direction: .automatic, at: anchor)
        #expect(abs(bounds(of: hung).x - bounds(of: rest).x) < 1)
        #expect(abs(bounds(of: hung).x - (bounds(of: held).x + 100)) < 1)
    }

    /// The stop is still drawn. Leaving it out of the measurement must not leave it
    /// out of the ink.
    @Test func theHungStopIsStillDrawn() {
        let held = font.glyphShapes(for: "あい。", size: 100, alignH: .left, alignV: .baseline,
                                    direction: .automatic, at: Vector2(0, 0))
        let hung = font.glyphShapes(for: "あい。", size: 100, alignH: .left, alignV: .baseline,
                                    direction: .automatic, hangs: true, at: Vector2(0, 0))
        #expect(hung.count == held.count)
        #expect(!hung.isEmpty)
    }

    /// A justified line reaches the box on the part that counts, which means the
    /// hung stop is carried past the edge rather than squeezed inside it.
    @Test func aJustifiedLineReachesTheBoxWithoutCountingTheStop() {
        let box = 400.0
        let line = "あいうえお。"
        let justify = TextJustification(extent: box, naturalLines: [])
        let held = font.glyphShapes(for: line, size: 50, alignH: .left, alignV: .baseline,
                                    direction: .automatic, justify: justify, at: Vector2(0, 0))
        let hung = font.glyphShapes(for: line, size: 50, alignH: .left, alignV: .baseline,
                                    direction: .automatic, justify: justify, hangs: true,
                                    at: Vector2(0, 0))
        // Held inside, the whole line ends on the box edge. Hanging, the stop is
        // outside it, so the ink runs further than the box does.
        #expect(bounds(of: held).width <= box + 1)
        #expect(bounds(of: hung).width > box)
    }

    // MARK: The setting itself

    /// It is drawing state, so a scope restores it like any other.
    @Test func withStateRestoresIt() {
        let d = Drawer()
        d.textHangingPunctuation()
        d.pushState()
        d.noTextHangingPunctuation()
        #expect(d.textHangsPunctuation == false)
        d.popState()
        #expect(d.textHangsPunctuation == true)
    }

    /// Only a box has an edge to hang past, so nothing leaks out of that one call.
    /// The same rule justification already follows.
    @Test func itLivesOnlyForTheBoxCall() {
        let d = drawer(hanging: true)
        #expect(d.textHangsInBox == false)
        d.fill(.black)
        d.drawText(passage, in: Rectangle(x: 0, y: 0, width: boxExtent, height: 400))
        #expect(d.textHangsInBox == false)
    }
}
