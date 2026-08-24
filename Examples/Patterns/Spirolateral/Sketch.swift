import Ollin

/// A walk of growing steps, repeated until it comes home.
///
/// Step one length, turn a quarter turn, step two lengths, turn again, and keep
/// going to the order of the figure. Then start the run over. The walk either
/// arrives back where it began, or it walks off forever, and the numbers alone
/// decide which.
///
/// A run turns the walker through the same angle every time, so the whole figure
/// is one run turned about a point, once per repeat. It closes as soon as a whole
/// number of runs makes a whole number of turns. At the quarter turn, that leaves
/// out exactly the orders that are multiples of four: their runs come back facing
/// the way they set off, so every repeat lands further away in the same
/// direction. Those are drawn pale here, and given three runs, because a walk
/// that leaves is worth seeing leave.
///
/// The pen draws over the loop, so the order of the walk is never a guess. Hold
/// the mouse for a fifth of a turn instead of a quarter, where the same rule
/// picks out the multiples of five.
@main
final class Spirolateral_Example: Sketch {
    override var loopDuration: Double? { 12 }

    private let orders = Array(3 ... 14)

    override func draw() {
        background(Color(hex: 0x0B0E14))

        // An exact fraction of a turn, never a swept angle: a walk closes on the
        // arithmetic of the turn, so anything in between simply never closes.
        let parts = mouseIsPressed ? 5 : 4
        let turn = Double.tau / Double(parts)
        let drawn = min(1, loopProgress(over: 12) * 1.25)

        let grid = Grid(in: bounds.inset(by: 54), columns: 4, rows: 3, gutter: 20)
        noFill()
        strokeWeight(2.5)
        strokeJoin(.round)

        for (index, order) in orders.enumerated() {
            let cell = grid.cells[index]
            let drifts = order % parts == 0
            let figure = spirolateral(order: order, turn: turn, step: 10,
                                      repeats: drifts ? 3 : nil)

            // Fit the points, never the transform: scaling the canvas scales the
            // stroke with it, and these lines have to stay one weight.
            let placed = fitted(figure.points, in: cell.frame.inset(by: 18))
            // The pen travels the corners in order, so the walk draws itself.
            let reached = Swift.max(2, Int((Double(placed.count) * drawn).rounded()))
            let sofar = Array(placed.prefix(reached))
            let whole = reached == placed.count

            if drifts {
                stroke(Color(hex: 0x3C4763))
            } else {
                stroke(CosinePalette.rainbow.color(at: Double(index) / 12 * 0.8))
            }
            drawPolyline(sofar, closed: whole && figure.closes)

            fill(Color(hex: 0x8D9AB4))
            noStroke()
            textSize(14)
            drawText("\(order)", cell.frame.x + 6, cell.frame.y + 20)
            noFill()
        }

        let drifting = orders.filter { $0 % parts == 0 }
        drawCaption("a \(parts == 4 ? "quarter" : "fifth") of a turn: every order closes but the multiples of "
            + "\(parts) (\(drifting.map(String.init).joined(separator: ", "))), which walk away instead")
    }
}
