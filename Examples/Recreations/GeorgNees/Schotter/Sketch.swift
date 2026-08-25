//  Recreation after Georg Nees - "Schotter" (1968), his plotter drawing of a
//  square grid coming apart as it falls down the page. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  http://www.medienkunstnetz.de/works/schotter/
//
//  An original Ollin interpretation written from the work itself and from
//  published descriptions of how it was made. No source was ported: the piece
//  was drawn on a Zuse Graphomat Z64 from an ALGOL program that is not the
//  program here.

import Ollin

/// "Schotter" (Georg Nees, 1968): a grid of identical squares that starts
/// perfectly ruled at the top of the page and falls apart on the way down.
/// Each square is turned a little and pushed a little off its place, and the
/// amount grows with the row, so the same rule produces order at the top and
/// gravel at the bottom. The title is German for gravel.
///
/// It is usually called the first famous piece of generative art, and the
/// reason it still works is the honesty of it: nothing is composed. One rule
/// runs down the page and the composition is what the rule does.
///
/// Two things are worth noticing in it. The disorder is in *two* things at
/// once, the turn and the place, and they arrive at different rates as you
/// read down. And the bottom rows are still a grid, in the sense that every
/// square is the same square. Nothing is scaled, nothing is deformed, and
/// nothing is thrown away.
///
/// Try it: `steepness` decides how the disorder arrives. At 1 it comes on in a
/// straight line, which spreads the transition over the whole page. Take it up
/// and the top half stays quiet while the bottom half comes apart, which is
/// nearer the original. `seed` is the whole piece: every run of it is a
/// different fall of gravel, and the same seed always draws the same one.
@main
final class Schotter: Sketch {
    @Param(4 ... 20, icon: "square.grid.3x3") var columns = 12.0
    @Param(6 ... 40, icon: "arrow.down") var rows = 22.0
    @Param(0 ... 2.5, icon: "wind") var disorder = 1.0
    @Param(0.5 ... 4, icon: "chart.line.uptrend.xyaxis") var steepness = 2.0
    @Param(1 ... 999, icon: "dice") var gravelSeed = 42.0

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(1.6)
        randomSeed(Int(gravelSeed.rounded()))

        let across = Int(columns.rounded()), down = Int(rows.rounded())
        let cell = min(width * 0.72 / Double(across), height * 0.88 / Double(down))
        let grid = Grid(in: Rectangle(center: center,
                                      width: cell * Double(across), height: cell * Double(down)),
                        columns: across, rows: down)

        for cellRect in grid.cells {
            // How far down the page this row is, and therefore how much of a
            // hand the randomness gets. Nothing else changes: every square is
            // the same square, turned and moved.
            let fall = down > 1 ? Double(cellRect.row) / Double(down - 1) : 0
            let hand = pow(fall, steepness) * disorder

            let turn = random(-1, 1) * hand * 0.8
            let push = Vector2(random(-1, 1), random(-1, 1)) * hand * cell * 0.4

            withState {
                translate(cellRect.center + push)
                rotate(turn)
                drawRect(center: .zero, width: cell * 0.86, height: cell * 0.86)
            }
        }
    }
}
