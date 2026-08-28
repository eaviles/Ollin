//  Recreation after Manfred Mohr - "Cubic Limit" (1973-1975), the work in which
//  he took a cube apart line by line and used the pieces as an alphabet, and
//  the plate P-161 in it, which he described as "the combinatorial
//  possibilities of lines of a cube taken n at a time at a given rotation". A
//  homage, not a reproduction, and not affiliated with or endorsed by the
//  artist.
//  https://www.emohr.com/themes/combinatoric.html
//
//  An original Ollin interpretation, written from the work and from Mohr's own
//  statement of the rule: "the 12 lines of the cube are used as an alphabet. The
//  drawings and films show combinations of n lines at a time (n = 0 to 12)".
//  Nothing was ported. His programs ran on a mainframe, they are not published,
//  and the program here is not one of them.

import Foundation
import Ollin

/// "Cubic Limit" (Manfred Mohr, 1973-1975): a cube taken apart, and the pieces
/// used as letters.
///
/// Mohr had been painting by hand, and he wanted the picture to come from a
/// rule instead of from his taste. In 1973 he settled on a cube as the fixed
/// structure every drawing would start from, for the reason a musician settles
/// on an instrument: the instrument holds still, and what you hear is the
/// playing. A cube in flat projection has twelve lines.
/// Keep some and leave the rest out, and you have a sign. Keep a different set,
/// and you have another one. There is nothing else to decide.
///
/// The sheet is that alphabet, sorted. Every cell holds the same cube at the
/// same rotation, and each row keeps one more line than the row above it: none
/// at the top, all twelve at the bottom. Across a row the signs are the
/// different ways to keep that many, counted off in order rather than picked. So
/// the sheet fills as your eye goes down, and the first row is empty on purpose.
/// A sign with no lines is a letter of this alphabet, and it is the one Mohr
/// counted first.
///
/// The thing to watch for is where the reading changes. Near the top the marks
/// are flat and stay flat, and there is no cube in them at all. Somewhere
/// around six or seven lines they turn into a solid seen from a corner, and
/// once your eye has done that it does not easily go back. Nothing in the rule
/// marks that row. It is the only thing on the sheet you brought yourself.
///
/// Try it: `offset` walks the window along the count, so a row shows you a
/// different set of the same size, and every combination will pass eventually.
/// `signs` is how many of them a row shows at once. `turning` slows the plate to
/// a stop, and stopped is where his own prints live, each one made at a given
/// rotation he had chosen.
@main
final class CubicLimit: Sketch {
    @Param(4 ... 16, icon: "rectangle.grid.2x2") var signs = 13
    @Param(0 ... 1, icon: "slider.horizontal.3") var offset = 0.0
    @Param(0 ... 3, icon: "metronome") var turning = 1.0
    @Param(0.5 ... 5, icon: "pencil.tip") var lineWeight = 2.6

    override var canvasSize: CanvasSize { .square(1080) }

    /// Every way to keep n of the twelve lines, sorted by n. Row n of the sheet
    /// reads from `alphabet[n]`, which holds 1, 12, 66, 220, ... sets in the
    /// order counting them off produces.
    private var alphabet: [[Int]] = []

    /// Both ends of each of the twelve lines, in a fixed order, so line number 7
    /// means the same line in every cell of the sheet.
    private let lines = cubeEdges()

    override func setup() {
        alphabet = Array(repeating: [], count: 13)
        for kept in 0 ..< (1 << 12) {
            alphabet[kept.nonzeroBitCount].append(kept)
        }
    }

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeCap(.butt)

        let columns = signs, rows = alphabet.count
        let cells = plateGrid(columns: columns, rows: rows).cells
        guard let first = cells.first else { return }

        // One rotation and one size for the whole sheet: the sign is the only
        // thing allowed to differ from cell to cell.
        let radius = min(first.frame.width, first.frame.height) * 0.44
        let corners = shadow(radius: radius)
        strokeWeight(max(0.5, lineWeight * radius / 76))

        for cell in cells {
            let held = alphabet[cell.row]
            guard !held.isEmpty else { continue }
            let start = Int(offset * Double(held.count))
            let kept = held[(start + cell.column * held.count / columns) % held.count]

            withState {
                translate(cell.center)
                for (index, line) in lines.enumerated() where kept & (1 << index) != 0 {
                    drawLine(corners[line.0], corners[line.1])
                }
            }
        }
    }

    /// The eight corners of the cube, turned and cast flat.
    ///
    /// The cast is a parallel one, which is what a plotter draws and what makes
    /// the sign independent of where the viewer stands. Two directions are
    /// carried through the turn and every corner is measured against them. They
    /// start at right angles and the turns keep them there, so no corner can
    /// fall further from the middle than `radius`, and a sign can never reach
    /// into the cell beside it.
    private func shadow(radius: Double) -> [Vector2] {
        // The cast starts with the three axes spread evenly over a half turn,
        // the familiar view of a cube standing on its corner, and `given` tips
        // it off that symmetry. The tip is not decoration. Dead on the corner
        // two of the eight corners land on the same point, which leaves seven
        // where there should be eight and turns the solid into a flat star, so
        // the letters of the alphabet lose the thing that makes them a cube.
        let even = (2.0 / 3).squareRoot()
        var across = (0 ..< 3).map { cos(.pi * Double($0) / 3) * even }
        var down = (0 ..< 3).map { sin(.pi * Double($0) / 3) * even }
        let given = [0.34, 0.17, 0.0]

        for k in 0 ..< 3 {
            let angle = given[k] + time * turning * (0.07 + 0.05 * Double(k))
            turn(&across, k, (k + 1) % 3, by: angle)
            turn(&down, k, (k + 1) % 3, by: angle)
        }

        let scale = radius / 3.0.squareRoot()
        return (0 ..< 8).map { corner in
            var x = 0.0, y = 0.0
            for d in 0 ..< 3 {
                let side = corner & (1 << d) == 0 ? -1.0 : 1.0
                x += across[d] * side
                y += down[d] * side
            }
            return Vector2(x, y) * scale
        }
    }

    /// Turns one direction in the plane of two of its axes.
    private func turn(_ direction: inout [Double], _ i: Int, _ j: Int, by angle: Double) {
        let c = cos(angle), s = sin(angle)
        let a = direction[i], b = direction[j]
        direction[i] = a * c - b * s
        direction[j] = a * s + b * c
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

/// The twelve lines of a cube: two corners share one when exactly one axis tells
/// them apart.
private func cubeEdges() -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    for corner in 0 ..< 8 {
        for d in 0 ..< 3 where corner & (1 << d) == 0 {
            out.append((corner, corner | (1 << d)))
        }
    }
    return out
}
