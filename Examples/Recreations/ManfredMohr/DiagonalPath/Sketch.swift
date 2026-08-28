//  Recreation after Manfred Mohr - "Dimensions I" (1978), the work in which he
//  drew the diagonal paths of a four-dimensional cube, and the plate P-228 in
//  it, which shows all of them between one pair of opposite corners. A homage,
//  not a reproduction, and not affiliated with or endorsed by the artist.
//  https://www.emohr.com/themes/combinatoric.html
//
//  An original Ollin interpretation, written from the work and from Mohr's own
//  statement of the rule: "a diagonal path is a set of edges along the structure
//  of the hypercube, changing one dimension at a time and visiting each
//  dimension once". Nothing was ported. His programs ran on a mainframe, they
//  are not published, and the program here is not one of them.

import Foundation
import Ollin

/// "Dimensions I" (Manfred Mohr, 1978): every way to walk from one corner of a
/// cube to the corner farthest from it.
///
/// Mohr took up the cube in 1973 and has worked from it ever since. He did not
/// use it to draw a cube. He used it as an instrument, the way a musician uses
/// one: a fixed structure that a rule can play, so that what you see is the
/// rule and not his taste. First the cube, then the cube in four dimensions,
/// later in six.
///
/// This is one of those rules, and it is small enough to say in a line. Start at
/// a corner. Cross one dimension. Cross another. Keep going until you have
/// crossed every dimension exactly once, and you arrive at the corner opposite
/// the one you left. In four dimensions there are four crossings to order, so
/// there are twenty four such walks, and each cell here is one of them: the
/// whole cube in thin line, the walk in heavy line.
///
/// Three things are worth noticing. Every sign is the same object, turned the
/// same way, so nothing at all was composed; the enumeration is the
/// composition. Every walk is the same length and ends in the same place, so
/// what separates the twenty four signs is order alone. And a shadow of four
/// dimensions is flat, so lines cross that do not touch, which is why the heavy
/// line is there. It is how you keep your place in a solid you cannot see.
///
/// Try it: `dimensions` is the whole instrument. Take it to 3 and the six walks
/// of an ordinary cube are easy to follow; take it to 5 and a hundred and
/// twenty signs arrive at once, past the point where you could keep the count
/// yourself. At 5 turn `showCube` off as well: eighty thin edges in a small
/// cell close up into gray, and the walks alone read as an alphabet. `turning`
/// slows the whole plate to a stop, and stopped is where his own prints live.
@main
final class DiagonalPath: Sketch {
    @Param(3 ... 5, icon: "cube") var dimensions = 4
    @Param(0 ... 3, icon: "metronome") var turning = 1.0
    @Param(1 ... 8, icon: "pencil.tip") var pathWeight = 3.5
    @Param(icon: "square.grid.3x3") var showCube = true

    override var canvasSize: CanvasSize { .square(1080) }

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)

        let n = dimensions
        let orders = walks(through: n)
        let (columns, rows) = plate(holding: orders.count)
        let cells = plateGrid(columns: columns, rows: rows).cells
        guard let first = cells.first else { return }

        // One radius for the whole plate, and one shadow, because every cell
        // shows the same solid turned the same way.
        let radius = min(first.frame.width, first.frame.height) * 0.47
        let unit = radius / 76
        let corners = shadow(of: n, radius: radius)
        let lines = edges(of: n)

        for (index, order) in orders.enumerated() where index < cells.count {
            withState {
                translate(cells[index].center)
                if showCube {
                    strokeWeight(max(0.4, 0.9 * unit))
                    strokeCap(.butt)
                    for line in lines { drawLine(corners[line.0], corners[line.1]) }
                }
                strokeWeight(max(0.8, pathWeight * unit))
                strokeCap(.round)
                strokeJoin(.round)
                drawPolyline(walk(order, over: corners))
            }
        }
    }

    /// The corners of the n-dimensional cube, turned in n dimensions and cast
    /// flat.
    ///
    /// The cast is a parallel one, the kind a plotter can draw and the kind that
    /// does not depend on where you stand. Two directions are carried through
    /// the turn and every corner is measured against them. They start at right
    /// angles and every turn keeps them there, so nothing in the shadow is
    /// stretched, and no corner can fall further from the middle than `radius`.
    /// That last part is why a sign can never reach into the cell beside it.
    private func shadow(of n: Int, radius: Double) -> [Vector2] {
        // The cast starts with the n dimensions spread evenly over a half turn,
        // which gives each of them its own direction on the paper and puts no
        // two of them on one line. In three dimensions that is the familiar
        // view of a cube standing on its corner; in four it opens into a
        // rosette of eight sides. `opening` tips it slightly off that symmetry.
        // Dead on the corner two of the eight corners of a cube land on the
        // same point, which leaves seven where there should be eight, and the
        // solid reads as a flat star.
        let even = (2 / Double(n)).squareRoot()
        var across = (0 ..< n).map { cos(.pi * Double($0) / Double(n)) * even }
        var down = (0 ..< n).map { sin(.pi * Double($0) / Double(n)) * even }
        let opening = 0.22

        // One turn per pair of neighboring dimensions, each at its own rate, so
        // every dimension is in motion and the plate never repeats itself soon.
        for k in 0 ..< n {
            let angle = (k == 0 ? opening : 0)
                + time * turning * (0.08 + 0.05 * Double(k))
            turn(&across, k, (k + 1) % n, by: angle)
            turn(&down, k, (k + 1) % n, by: angle)
        }

        let scale = radius / Double(n).squareRoot()
        return (0 ..< (1 << n)).map { corner in
            var x = 0.0, y = 0.0
            for d in 0 ..< n {
                let side = corner & (1 << d) == 0 ? -1.0 : 1.0
                x += across[d] * side
                y += down[d] * side
            }
            return Vector2(x, y) * scale
        }
    }

    /// Turns one direction in the plane of two of its dimensions.
    private func turn(_ direction: inout [Double], _ i: Int, _ j: Int, by angle: Double) {
        let c = cos(angle), s = sin(angle)
        let a = direction[i], b = direction[j]
        direction[i] = a * c - b * s
        direction[j] = a * s + b * c
    }

    /// Every order in which the n dimensions can be crossed, listed the way you
    /// would count them off. One order is one diagonal path, so there are n! of
    /// them: 6, then 24, then 120.
    private func walks(through n: Int) -> [[Int]] {
        var out: [[Int]] = []
        func step(_ crossed: [Int], _ left: [Int]) {
            if left.isEmpty { out.append(crossed); return }
            for (index, d) in left.enumerated() {
                var rest = left
                rest.remove(at: index)
                step(crossed + [d], rest)
            }
        }
        step([], Array(0 ..< n))
        return out
    }

    /// The walk itself: start at the corner where every dimension reads low,
    /// cross them in the given order, and arrive at the corner where they all
    /// read high.
    private func walk(_ order: [Int], over corners: [Vector2]) -> [Vector2] {
        var corner = 0
        var points = [corners[0]]
        for d in order {
            corner |= 1 << d
            points.append(corners[corner])
        }
        return points
    }

    /// Both ends of every edge of the n-dimensional cube. Two corners share an
    /// edge when exactly one dimension tells them apart.
    private func edges(of n: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for corner in 0 ..< (1 << n) {
            for d in 0 ..< n where corner & (1 << d) == 0 {
                out.append((corner, corner | (1 << d)))
            }
        }
        return out
    }

    /// The block of cells the signs are laid out in: as near square as the count
    /// allows, lying down.
    private func plate(holding count: Int) -> (Int, Int) {
        var side = Int(Double(count).squareRoot().rounded())
        while side > 1 && count % side != 0 { side -= 1 }
        let other = count / max(1, side)
        return (max(side, other), min(side, other))
    }

    /// Square cells, centered, with a margin the sheet can be held by.
    private func plateGrid(columns: Int, rows: Int) -> Grid {
        let room = Rectangle(center: center, width: width * 0.92, height: height * 0.92)
        let cell = min(room.width / Double(columns), room.height / Double(rows))
        let block = Rectangle(center: center,
                              width: cell * Double(columns), height: cell * Double(rows))
        return Grid(in: block, columns: columns, rows: rows)
    }
}
