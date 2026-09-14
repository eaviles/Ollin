//  Recreation after Vicente Rojo - the "Mexico bajo la lluvia" series
//  (1981-1989), the square paintings of rain falling across a grid. A
//  homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://muac.unam.mx/objeto/mexico-bajo-la-lluvia-106
//
//  An original Ollin interpretation written from the paintings and from what
//  Rojo said about them. Nothing was ported: the series is acrylic and mixed
//  media on canvas.

import Ollin

/// "Mexico bajo la lluvia" (Vicente Rojo, 1981-1989). In 1953 Rojo watched
/// two rains fall at once over the valley of Cholula, from the observatory at
/// Tonantzintla, and then spent thirty years unable to paint it. "It always
/// seemed to me an impossible subject to paint, and that is what drew me to
/// it." He found the way in 1981: a strictly square canvas with a diagonal
/// across it, so the two triangles lean the way the rain had leaned. Over the
/// whole surface, closely spaced diagonal lines, and the lines made of small
/// things: dots, triangles, half-disks, steps, and blotches, in a cool palette
/// of blues, grays, pinks, white, and black, with yellow, ochre, and green as
/// the warm notes. No part of the canvas is left empty. He painted well over
/// a hundred of them.
///
/// This sketch is one of those canvases with the rain still falling. A grid
/// covers the square, every cell is painted and one small mark is set on it,
/// and the diagonal from the top left corner to the bottom right divides the
/// marks. Above it is the rain, half-disks and dots. Below it is the ground,
/// triangles and steps, like the stepped pyramids the series keeps
/// remembering. Blotches land on both. The colors run in streaks along that
/// same diagonal, broken and stepped because a grid cannot draw a smooth
/// line, and the streaks slide down the slope at `drift` cells a second,
/// which is the rain.
///
/// Try it: `cells` is the grid across the square, `wind` how ragged the
/// streaks are, `drift` how fast they fall, and `variation` the whole canvas.
/// Every mark exports as its own polygon, circle, or path over its cell's
/// square, so `--export-svg` gives back one ground square and one mark for
/// every cell.
@main
final class MexicoBajoLaLluvia: Sketch {
    @Param(24 ... 96, icon: "square.grid.3x3") var cells = 54
    @Param(0 ... 30, icon: "cloud.rain") var drift = 6.0
    @Param(0 ... 1, icon: "wind") var wind = 0.5

    /// The five things the lines are made of.
    private enum Mark {
        case halfDisk, dot, blotch, triangle, step
    }

    /// The palette, darkest first, and how much of the canvas each color
    /// gets: the cool darks carry the picture, and white, yellow, and pink
    /// are the flecks.
    private let palette: [Color] = [
        Color(hex: 0x101317),
        Color(hex: 0x1A294D),
        Color(hex: 0x6C2926),
        Color(hex: 0x1F4A36),
        Color(hex: 0x3C5676),
        Color(hex: 0x64632E),
        Color(hex: 0x6C6F78),
        Color(hex: 0xAD7D32),
        Color(hex: 0xB77689),
        Color(hex: 0xD0B85A),
        Color(hex: 0xE1DBCA),
    ]
    private let shares: [Double] = [20, 16, 10, 14, 13, 11, 6, 4, 2.5, 2.5, 1.5]

    override func draw() {
        let count = max(2, cells)
        let cell = width / Double(count)
        background(palette[0])
        noStroke()

        // The colors first, a ground and a mark for every cell, read off a
        // field of noise. One coordinate is constant along a diagonal and the
        // other runs down it, so the noise makes streaks that lean the way
        // the rain does, and the drift slides them down the slope. The mark
        // reads the same streak a little further along, so it takes the
        // color the ground will have a few cells down, which is what makes a
        // streak read as one beaded line rather than as two fields laid over
        // each other.
        let fall = drift * time
        let ragged = 0.3 + 0.6 * wind
        let offset = Double(variation) * 37.1
        var grounds: [Int] = []
        var marks: [Int] = []
        grounds.reserveCapacity(count * count)
        marks.reserveCapacity(count * count)
        for row in 0 ..< count {
            for column in 0 ..< count {
                let along = Double(column - row) * ragged + offset
                let down = (Double(column + row) - fall) * 0.022
                let ground = tone(noise(along, down))
                var mark = tone(noise(along, down + 0.3))
                if mark == ground { mark = (ground + 3) % 8 }
                grounds.append(ground)
                marks.append(mark)
            }
        }

        for row in 0 ..< count {
            for column in 0 ..< count {
                fill(palette[grounds[row * count + column]])
                drawRect(Double(column) * cell, Double(row) * cell, cell, cell)
            }
        }

        for row in 0 ..< count {
            for column in 0 ..< count {
                fill(palette[marks[row * count + column]])
                draw(kind(column: column, row: row), column: column, row: row, cell: cell)
            }
        }
    }

    /// A palette index from a noise value: the value is handed to the colors
    /// by their shares, so a color's share of the canvas is near what the
    /// list says.
    private func tone(_ value: Double) -> Int {
        let spread = min(1, max(0, (value - 0.05) / 0.9))
        var remaining = spread * shares.reduce(0, +)
        for (index, share) in shares.enumerated() {
            remaining -= share
            if remaining < 0 { return index }
        }
        return palette.count - 1
    }

    /// Which mark a cell carries. The diagonal from the top left corner
    /// decides the family, and a coin fixed to the cell decides which one.
    private func kind(column: Int, row: Int) -> Mark {
        var rng = SplitMix64(seed: seed(column: column, row: row))
        let coin = Double.random(in: 0 ..< 1, using: &rng)
        if column >= row {
            return coin < 0.78 ? .halfDisk : coin < 0.9 ? .dot : .blotch
        }
        return coin < 0.7 ? .triangle : coin < 0.9 ? .step : .blotch
    }

    private func seed(column: Int, row: Int) -> UInt64 {
        let mixed = (column &+ 1) &* 73_856_093 ^ (row &+ 1) &* 19_349_663 ^ variation &* 83_492_791
        return UInt64(bitPattern: Int64(mixed))
    }

    /// One mark, inside its cell. A half-disk bulges the way the rain falls,
    /// a triangle and a step stand on the cell's floor like a pyramid, and a
    /// blotch is a ring of points thrown around the middle.
    private func draw(_ mark: Mark, column: Int, row: Int, cell: Double) {
        let x0 = Double(column) * cell, y0 = Double(row) * cell
        let cx = x0 + cell / 2, cy = y0 + cell / 2
        switch mark {
        case .halfDisk:
            drawArc(cx, cy, cell / 2, cell / 2, start: -.pi / 4, stop: .pi * 0.75, mode: .chord)
        case .dot:
            drawCircle(cx, cy, cell * 0.3)
        case .triangle:
            drawTriangle(Vector2(x0, y0 + cell), Vector2(x0 + cell, y0 + cell), Vector2(cx, y0))
        case .step:
            // A stair is concave, so it goes through the shape path, which
            // triangulates it, rather than the polygon fan.
            drawShape(Shape([Vector2(x0, y0 + cell), Vector2(x0, cy), Vector2(cx, cy),
                             Vector2(cx, y0), Vector2(x0 + cell, y0), Vector2(x0 + cell, y0 + cell)]))
        case .blotch:
            var rng = SplitMix64(seed: seed(column: column, row: row) &+ 977)
            let points = 9
            drawShape { path in
                for i in 0 ..< points {
                    let angle = (Double(i) + Double.random(in: -0.3 ... 0.3, using: &rng)) * .tau / Double(points)
                    let radius = cell * Double.random(in: 0.24 ... 0.48, using: &rng)
                    let point = Vector2(cx + cos(angle) * radius, cy + sin(angle) * radius)
                    if i == 0 { path.move(to: point) } else { path.line(to: point) }
                }
                path.close()
            }
        }
    }
}
