import Testing
import CoreGraphics
@testable import Ollin

/// Text placed glyph by glyph: along a path, and through a per-glyph
/// closure. Both are held to plain
/// `drawText` where they should agree with it, a straight path at the text's
/// own baseline and a closure that only stamps each glyph, and to their own
/// rules where they differ.
@Suite
@MainActor
struct TextPlacementTests {

    private func render(_ paint: @escaping (Sketch) -> Void) throws -> [UInt8] {
        pixels(of: try OllinApp.image(of: TextProbe(paint), frame: 1))
    }

    /// Where a picture's ink sits, glyph by glyph: the column spans the ink
    /// covers (one per glyph in a run of separate letters), the rows it
    /// covers, and how much of it there is. Spans rather than a weighted
    /// center, since two routes that place a glyph alike can still differ in
    /// how much ink its curves carry, and a center would move with that.
    private struct Ink: Equatable {
        var spans: [ClosedRange<Int>] = []
        var rows: ClosedRange<Int>? = nil
        var total = 0.0
        static func == (a: Ink, b: Ink) -> Bool { a.spans == b.spans && a.rows == b.rows }
    }

    private func ink(_ bytes: [UInt8], width: Int = 256) -> Ink {
        let height = bytes.count / 4 / width
        var result = Ink()
        var columns = [Double](repeating: 0, count: width)
        var top = Int.max, bottom = Int.min
        for y in 0 ..< height {
            for x in 0 ..< width {
                let g = Double(bytes[(y * width + x) * 4]) / 255
                guard g > 0.08 else { continue }
                columns[x] += g
                result.total += g
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        var start: Int?
        for (x, sum) in columns.enumerated() {
            if sum > 0.05 { start = start ?? x } else if let s = start { result.spans.append(s ... x - 1); start = nil }
        }
        if let s = start { result.spans.append(s ... width - 1) }
        if top <= bottom { result.rows = top ... bottom }
        return result
    }

    private func expectSamePlace(_ a: [UInt8], _ b: [UInt8], _ what: String) {
        let p = ink(a), q = ink(b)
        #expect(p == q, "\(what): the glyphs cover \(p.spans) and rows \(String(describing: p.rows)), against \(q.spans) and \(String(describing: q.rows))")
    }

    /// On a straight path every glyph sits where the plain run puts it: the
    /// glyph's center at its distance along the run, its baseline on the line.
    @Test func alongAStraightPathIsThePlainRun() throws {
        let line = Path { $0.move(to: Vector2(12, 60)); $0.line(to: Vector2(240, 60)) }
        let along = try render { $0.drawText("Ollin wave", along: line) }
        let plain = try render { $0.drawText("Ollin wave", 12, 60) }
        #expect(along != (try render { _ in }))
        expectSamePlace(along, plain, "along the path against the plain run")
        withKnownIssue("""
            the plain run fills each glyph from its outline simplified to 0.3 px, the \
            per-glyph route (a path, perGlyph) from the outline flattened at render size \
            with every point kept, so the same glyph differs at its curves: a 20 px O \
            carries 4.5% more ink along a path (filed under Rendering and color frontier in DESIGN-NOTES)
            """) {
            #expect(zip(along, plain).map { abs(Int($0) - Int($1)) }.max() ?? 0 <= 1)
        }
    }

    /// The offset slides the run along the path, and a glyph that falls off
    /// either end is skipped rather than drawn past it.
    @Test func anOffsetSlidesTheRunAndTheEndsDropGlyphs() throws {
        let line = Path { $0.move(to: Vector2(12, 60)); $0.line(to: Vector2(240, 60)) }
        let slid = try render { $0.drawText("Ollin", along: line, offset: 40) }
        let moved = try render { sketch in
            sketch.drawText("Ollin", along: Path { $0.move(to: Vector2(52, 60)); $0.line(to: Vector2(240, 60)) })
        }
        #expect(slid == moved)
        expectSamePlace(slid, try render { $0.drawText("Ollin", 52, 60) }, "the slid run against the plain run")
        let blank = try render { _ in }
        #expect(try render { $0.drawText("Ollin", along: line, offset: -1000) } == blank)
        #expect(try render { $0.drawText("Ollin", along: line, offset: 1000) } == blank)
        // Half on: the run starts before the path, so its first glyphs go.
        let half = ink(try render { $0.drawText("Ollin wave", along: line, offset: -30) })
        let full = ink(try render { $0.drawText("Ollin wave", along: line, offset: 0) })
        #expect(half.total < full.total && half.total > 0)
    }

    /// Around a circle each glyph stands on the curve: all the ink lies in the
    /// band between the circle and the circle grown by the type's size.
    @Test func aroundACircleTheGlyphsStandOnIt() throws {
        let center = Vector2(128, 72), radius = 50.0
        var circle = Path()
        circle.move(to: center + Vector2(-radius, 0))
        for k in 1 ... 180 {
            let a = Double.pi + Double.pi * Double(k) / 180
            circle.line(to: center + Vector2(cos(a), sin(a)) * radius)
        }
        let image = Pixels(try OllinApp.image(of: TextProbe { $0.drawText("over the top", along: circle) }, frame: 1))
        var inked = 0, astray = 0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width where image.gray(x, y) > 128 {
                inked += 1
                let r = (Vector2(Double(x) + 0.5, Double(y) + 0.5) - center).length
                if r < radius - 4 || r > radius + 24 { astray += 1 }
            }
        }
        #expect(inked > 100)
        #expect(astray == 0, "\(astray) of \(inked) inked pixels lie off the band the glyphs stand in")
    }

    /// The closure sees every glyph once, in order, numbered, with its share
    /// of the run; stamping each unchanged is the plain run, and stamping none
    /// draws nothing.
    @Test func perGlyphSeesEveryGlyphInOrder() throws {
        var seen: [(index: Int, count: Int, character: Character, progress: Double, x: Double)] = []
        let stamped = try render { sketch in
            sketch.drawText("Ollin", 12, 60) { glyph in
                // A headless frame draws twice (frame 0, then frame 1); keep the last.
                if glyph.index == 0 { seen.removeAll() }
                seen.append((glyph.index, glyph.count, glyph.character, glyph.progress, glyph.position.x))
                glyph.draw()
            }
        }
        #expect(seen.map(\.character) == Array("Ollin"))
        #expect(seen.map(\.index) == Array(0 ..< 5))
        #expect(seen.allSatisfy { $0.count == 5 })
        #expect(zip(seen, seen.dropFirst()).allSatisfy { $0.progress < $1.progress && $0.x < $1.x })
        // Stamped unchanged, the glyphs are the per-glyph route's run: the same
        // pixels as the run along a straight path, in the plain run's place.
        let line = Path { $0.move(to: Vector2(12, 60)); $0.line(to: Vector2(240, 60)) }
        #expect(stamped == (try render { $0.drawText("Ollin", along: line) }))
        expectSamePlace(stamped, try render { $0.drawText("Ollin", 12, 60) }, "the stamped run against the plain run")
        let unstamped = try render { $0.drawText("Ollin", 12, 60) { _ in } }
        #expect(unstamped == (try render { _ in }))
        // The anchored form is the same call.
        #expect(try render { $0.drawText("Ollin", at: Vector2(12, 60)) { $0.draw() } } == stamped)
    }
}

@MainActor
private final class TextProbe: Sketch {
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .size(256, 96) }

    override func draw() {
        background(.black)
        noStroke()
        fill(.white)
        textSize(20)
        paint(self)
    }
}
