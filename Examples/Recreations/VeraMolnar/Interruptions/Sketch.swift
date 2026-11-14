//  Recreation after Vera Molnár, in the spirit of her "Interruptions" (1968 to
//  1969) and her order-and-disorder line works. A homage, not a reproduction.
//
//  Ported from the p5.js sketch week-1/vera-1 (MIT) in
//  https://github.com/eaviles/rtp-sfpc-f21-p5, itself a p5 port of Zach
//  Lieberman's openFrameworks sample for the RTP class at SFPC, Fall 2021
//  (https://github.com/ofZach/RTP_SFPC_F21). Reworked for Ollin's API.
//
//  Its numbers were then read off one plate of the series, the plotter drawing
//  the Victoria and Albert Museum holds as E.269-2011: 56 lines a side, each
//  1.77 cells long, leaning toward the vertical, with one line in eight left
//  out, half of those in about ten patches a few cells across. How the patches
//  are made here (boxes of cells, some emptied and some thinned, and single
//  lines dropped) is this sketch's reading of that plate, not a procedure
//  Molnár published.

import Foundation
import Ollin

/// A 56 by 56 field of short lines, each turned about its own middle, with
/// patches of them left out: Vera Molnár's play of order (the grid) against
/// disorder (the turns and the gaps). **Click to recreate**: each click rolls
/// a new seed.
///
/// The turns are not even. A line's angle is the sum of two random draws, which
/// lands near the vertical more often than far from it, so the field keeps a
/// grain: runs of nearly upright strokes with the odd one lying flat. The
/// interruptions are boxes of cells. Most are emptied, a few are only thinned,
/// and a line here and there goes missing by itself.
///
/// The original is a still. Here `draw()` applies the seed again every frame,
/// so the picture holds until `mousePressed()` moves the seed on, with no need
/// for `noLoop()`. Demonstrates `withState { }` with `translate`/`rotate`,
/// `drawLine`, and `random`.
@main
final class Interruptions: Sketch {
    var seed = 0

    /// Lines along a side.
    private let side = 56
    /// A line's length in cells: long enough to cross its neighbors.
    private let reach = 1.77

    /// Each click is a fresh roll of the disorder.
    override func mousePressed() {
        seed += 1
    }

    override func draw() {
        background(.white)
        randomSeed(seed)   // the same seed every frame holds the picture still

        // Which lines are left out. Eleven boxes are emptied, four larger ones
        // keep about half their lines, thirty small gaps are a cell or two
        // across, and one line in forty is dropped wherever it stands.
        var kept = [Bool](repeating: true, count: side * side)
        func interrupt(_ count: Int, width: ClosedRange<Int>, height: ClosedRange<Int>,
                       keeping share: Double) {
            for _ in 0 ..< count {
                let w = whole(in: width), h = whole(in: height)
                let column = whole(in: 0 ... side - w), row = whole(in: 0 ... side - h)
                for r in row ..< row + h {
                    for c in column ..< column + w where random() >= share {
                        kept[r * side + c] = false
                    }
                }
            }
        }
        interrupt(11, width: 3 ... 7, height: 2 ... 5, keeping: 0)
        interrupt(4, width: 5 ... 9, height: 3 ... 6, keeping: 0.5)
        interrupt(30, width: 1 ... 2, height: 1 ... 3, keeping: 0)

        // The field spans a 1/16 inset edge to edge. The pen is a fourteenth
        // of a cell wide, which is the weight the plate's ink comes to.
        let margin = shortSide * 0.0625
        let field = grid(columns: side, rows: side, padding: .all(margin), distribution: .spanning)
        let cell = (shortSide - margin * 2) / Double(side - 1)
        let half = cell * reach / 2
        stroke(.black)
        strokeWeight(cell * 0.07)
        for dot in field.points {
            // Two draws added: a turn from the vertical of up to a quarter
            // turn either way, small more often than large.
            let turn = (random() + random() - 1) * .pi / 2
            let dropped = random() < 0.025
            guard kept[dot.row * side + dot.column], !dropped else { continue }
            withState {
                translate(dot.position)
                rotate(.pi / 2 + turn)
                drawLine(-half, 0, half, 0)
            }
        }
    }

    /// A whole number drawn evenly from a range, both ends included.
    private func whole(in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, Int(random(Double(range.lowerBound), Double(range.upperBound) + 1)))
    }
}
