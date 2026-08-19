import Testing
@testable import Ollin

/// Rendered checks on the tessellated stroke path, which outline-font glyphs
/// are the only remaining customer of (every other stroke goes through the
/// fringe expander, covered by `FringeStrokeTests`).
///
/// Both paths expand a path segment by segment, so both have to end consecutive
/// segments on the point where their inner edges cross, and both are read the
/// same way here (see `InkProbe`). A glyph's curves are finely flattened, so a
/// per-join defect repeats every few pixels along every stroke.
@Suite
@MainActor
struct GlyphStrokeTests {

    /// One letter with no self-overlapping contours, stroked in translucent ink
    /// thick enough that a second coat would be obvious.
    private final class Letter: Sketch {
        var join: StrokeJoin = .round
        override var canvasSize: CanvasSize { .square(512) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            noFill()
            stroke(Color.black.withAlpha(0.25))
            strokeWeight(16)
            strokeJoin(join)
            textFont(OutlineFont.systemBold)
            textSize(340)
            textAlign(.center, .middle)
            drawText("o", 256, 256)
        }
    }

    /// A segment that ends on its own perpendicular overshoots into its
    /// neighbor and paints the inside of every turn twice: a comb of dark ticks
    /// along each curve. Fanning the join filler from the path vertex once the
    /// ends bend to the shared crossing leaves a T-junction instead, whose
    /// hairline shows as the same comb in pale. Both have to stay away.
    ///
    /// The join style is in the loop because it must stay irrelevant: the filler
    /// only ever covers the outside of a turn, so every style darkened alike
    /// before the segments were made to share the crossing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTranslucentGlyphOutlineIsAnEvenCoat() throws {
        for join in [StrokeJoin.round, .miter, .bevel] {
            let letter = Letter()
            letter.join = join
            let ink = InkProbe(try #require(OllinApp.image(of: letter)), inkDarkerThan: 250)
            #expect(ink.coatArea > 5_000, "\(join): probe missed the glyph")
            #expect(ink.paintedTwice == 0,
                    "\(join): \(ink.paintedTwice) pixels painted twice (coat \(ink.coat))")
            #expect(ink.hairlines == 0,
                    "\(join): \(ink.hairlines) pixels of hairline inside the ink")
        }
    }
}
