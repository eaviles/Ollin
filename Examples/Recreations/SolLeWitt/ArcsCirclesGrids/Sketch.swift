//  Recreation after Sol LeWitt - the compass alphabet of his 1972 book "Arcs,
//  from Corners & Sides, Circles, & Grids and All Their Combinations"
//  (Kunsthalle Bern) and the wall drawings made from it. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  https://www.stedelijk.nl/en/collection/9579-sol-lewitt-arcs-circles-and-grids
//
//  An original Ollin interpretation written from the vocabulary the book's
//  title states. Nothing was ported: the book is ink drawings, and the wall
//  drawings made from it were drawn by hand with a compass.

import Ollin

/// LeWitt's compass alphabet: arcs from the four corners of a square, arcs
/// from the midpoints of its four sides, circles from its center, and a grid.
/// Ten elements. In 1972 he drew their combinations for a book, 195 drawings
/// in all, and many became wall drawings. This sheet draws the forty-five
/// two-part combinations: every way to lay one element over another, one
/// square each, nine across and five down, in the order counting them off
/// produces.
///
/// Every element is the same gesture repeated: a compass opened one notch
/// wider each time, from one fixed point, until the arc leaves the square. So
/// a square holds nothing but evenly spaced lines, and what you see, the moire
/// where two families cross, is not drawn at all. It is what two rules do to
/// each other.
///
/// The instruction fixes the elements and leaves the spacing to whoever draws
/// it. That latitude is what moves here. `lines` is how many lines cross a
/// square, and `breath` lets it drift up and down over `period` seconds, so
/// the moire shifts while every square keeps its two elements. `lineWeight`
/// is the pen. The arcs export as strokes cut at their squares, so
/// `--export-svg` gives the compass drawing back.
@main
final class ArcsCirclesGrids: Sketch {
    @Param(4 ... 24, icon: "circle.dotted") var lines = 10.0
    @Param(0 ... 6, icon: "wind") var breath = 3.0
    @Param(4 ... 120, icon: "metronome") var period = 24.0
    @Param(0.5 ... 4, icon: "pencil.tip") var lineWeight = 1.6

    override var canvasSize: CanvasSize { .size(1800, 1000) }
    override var loopDuration: Double? { period }

    /// The ten elements, in the order the book's title names them.
    private enum Element: Int, CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft
        case top, right, bottom, left
        case circles, grid
    }

    /// Every pair of distinct elements, the first with each of the nine after
    /// it, then the second with the eight after it, and so on: forty-five.
    private let pairs: [(Element, Element)] = {
        let all = Element.allCases
        var out: [(Element, Element)] = []
        for i in all.indices {
            for j in all.indices where j > i {
                out.append((all[i], all[j]))
            }
        }
        return out
    }()

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeCap(.butt)
        strokeWeight(lineWeight)

        let columns = 9, rows = 5
        let cells = plateGrid(columns: columns, rows: rows).cells
        guard let first = cells.first else { return }
        let across = lines + breath * sin(.tau * time / period)
        let spacing = first.frame.width / across

        for (index, cell) in cells.enumerated() where index < pairs.count {
            let (a, b) = pairs[index]
            draw(a, in: cell.frame, spacing: spacing)
            draw(b, in: cell.frame, spacing: spacing)
        }
    }

    /// One element in one square: a family of evenly spaced lines from its
    /// fixed point, each cut where it leaves the square.
    private func draw(_ element: Element, in square: Rectangle, spacing: Double) {
        let x0 = square.x, y0 = square.y
        let x1 = x0 + square.width, y1 = y0 + square.height
        let side = square.width

        if element == .grid {
            var offset = spacing
            while offset < side - 0.5 {
                drawLine(x0 + offset, y0, x0 + offset, y1)
                drawLine(x0, y0 + offset, x1, y0 + offset)
                offset += spacing
            }
            return
        }

        // Where the compass stands, the angles that face into the square, and
        // how far the farthest corner is, which is where the arcs stop.
        let quarter = Double.pi / 2
        let (pivot, from, to): (Vector2, Double, Double) = switch element {
        case .topLeft: (Vector2(x0, y0), 0, quarter)
        case .topRight: (Vector2(x1, y0), quarter, 2 * quarter)
        case .bottomRight: (Vector2(x1, y1), 2 * quarter, 3 * quarter)
        case .bottomLeft: (Vector2(x0, y1), 3 * quarter, 4 * quarter)
        case .top: (Vector2(square.center.x, y0), 0, 2 * quarter)
        case .right: (Vector2(x1, square.center.y), quarter, 3 * quarter)
        case .bottom: (Vector2(square.center.x, y1), 2 * quarter, 4 * quarter)
        case .left: (Vector2(x0, square.center.y), -quarter, quarter)
        case .circles, .grid: (square.center, 0, 4 * quarter)
        }
        let reach = [square.topLeft, square.topRight, square.bottomLeft, square.bottomRight]
            .map { pivot.distance(to: $0) }.max() ?? 0

        var radius = spacing
        while radius < reach {
            arc(around: pivot, radius: radius, from: from, to: to, in: square)
            radius += spacing
        }
    }

    /// One arc, flattened to chords no more than a fifth of a pixel off the
    /// circle, and cut against the square so only the part inside is drawn.
    private func arc(around pivot: Vector2, radius: Double, from: Double, to: Double,
                     in square: Rectangle) {
        let flatness = 0.2
        let step = radius > flatness ? 2 * acos(1 - flatness / radius) : Double.pi / 8
        let count = max(8, Int(((to - from) / step).rounded(.up)))
        var run: [Vector2] = []
        var previous = pivot + Vector2(cos(from), sin(from)) * radius
        for k in 1 ... count {
            let angle = from + (to - from) * Double(k) / Double(count)
            let point = pivot + Vector2(cos(angle), sin(angle)) * radius
            if let (start, end) = clip(previous, point, to: square) {
                if let last = run.last, last.distance(to: start) < 1e-6 {
                    run.append(end)
                } else {
                    flush(&run)
                    run = [start, end]
                }
            }
            previous = point
        }
        flush(&run)
    }

    private func flush(_ run: inout [Vector2]) {
        if run.count >= 2 { drawPolyline(run) }
        run.removeAll(keepingCapacity: true)
    }

    /// The part of the segment from `a` to `b` that lies inside `rect`, or
    /// nothing when it misses.
    private func clip(_ a: Vector2, _ b: Vector2, to rect: Rectangle) -> (Vector2, Vector2)? {
        let d = b - a
        var enter = 0.0, leave = 1.0
        let edges: [(Double, Double)] = [
            (-d.x, a.x - rect.x), (d.x, rect.x + rect.width - a.x),
            (-d.y, a.y - rect.y), (d.y, rect.y + rect.height - a.y),
        ]
        for (p, q) in edges {
            if p == 0 {
                if q < 0 { return nil }
            } else {
                let t = q / p
                if p < 0 { enter = max(enter, t) } else { leave = min(leave, t) }
            }
        }
        guard enter <= leave else { return nil }
        return (a + d * enter, a + d * leave)
    }

    /// Square cells with a gutter between them, the block centered on the
    /// wall with a margin around it.
    private func plateGrid(columns: Int, rows: Int) -> Grid {
        let room = Rectangle(center: center, width: width * 0.94, height: height * 0.9)
        let cell = min(room.width / Double(columns), room.height / Double(rows))
        let block = Rectangle(center: center,
                              width: cell * Double(columns), height: cell * Double(rows))
        return Grid(in: block, columns: columns, rows: rows, gutter: cell * 0.09)
    }
}
