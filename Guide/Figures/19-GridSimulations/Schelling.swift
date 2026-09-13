// figure: frame=400
//
// Guide figure (Chapter 19): Schelling's board at three ages of one run. Left,
// the seeded start, an even random mix with a quarter of the cells empty.
// Middle, fifteen steps in, the two kinds beginning to gather. Right, four
// hundred steps in, settled into patches from a wish for a third. Three fields
// with one seed: the first never moves, the second is only read for the last
// fifteen frames (a field steps only while something reads it), the third runs
// the whole way.
import Ollin

final class SchellingFigure: Sketch {
    override var canvasSize: CanvasSize { .size(940, 330) }

    private var start: SimField!
    private var early: SimField!
    private var settled: SimField!

    private let kinds = Ramp(stops: [(0.0, Color(hex: 0x14161C)),
                                     (0.5, Color(hex: 0xE4572E)),
                                     (1.0, Color(hex: 0x17BEBB))])

    override func setup() {
        // The same board three times: at a mobility of 0 the start holds.
        start = makeSimField(.schelling(preference: 0.3, mobility: 0, seed: 6), scale: 0.12)
        early = makeSimField(.schelling(preference: 0.3, seed: 6), scale: 0.12)
        settled = makeSimField(.schelling(preference: 0.3, seed: 6), scale: 0.12)
    }

    override func draw() {
        background(Color(hex: 0x0A0B0E))
        let side = 290.0, top = 12.0
        let boards: [(SimField, Double, String)] = [
            (start, 12, "the start"),
            (early, 325, "15 steps in"),
            (settled, 638, "400 steps in"),
        ]
        for (board, x, caption) in boards {
            // The middle board is read only for the last fifteen frames, so at
            // frame 400 it is fifteen steps old.
            if board === early && frameCount < 385 { continue }
            // A field is the canvas's own shape; the square panel takes its
            // left part, which is a square of the board.
            let scale = side / height
            withClip(Rectangle(x: x, y: top, width: side, height: side)) {
                drawImage(board.filtered(.gradientMap(kinds)).image, x, top,
                          width * scale, height * scale)
            }
            noStroke()
            fill(Color(white: 0.7))
            textSize(13)
            textAlign(.center)
            drawText(caption, x + side / 2, top + side + 20)
        }
    }
}
