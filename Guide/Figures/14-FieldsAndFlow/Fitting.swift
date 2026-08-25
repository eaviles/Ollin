// figure: frame=0 themed
//
// Guide figure (Chapter 14): a field fitted through a few known values, the warp the same
// fit makes when it carries vectors, and the circle a downhill walk finds in scattered marks.
import Ollin
import OllinDiagram

final class Fitting: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var labelInk: Color { theme.ink(0.62) }

    let anchors = [Vector2(56, 70), Vector2(214, 60), Vector2(140, 148),
                   Vector2(46, 200), Vector2(228, 206), Vector2(120, 246)]
    let inks = [Color(hex: 0xE8734A), Color(hex: 0x49B0A5), Color(hex: 0xE0C25C),
                Color(hex: 0xC85A7C), Color(hex: 0x6E8FD4), Color(hex: 0x8FC46B)]

    override func draw() {
        background(paper)

        let tile = 268.0, gap = 12.0
        let left = (width - tile * 3 - gap * 2) / 2
        let labels = ["six known colors", "the same six, as a pull", "three numbers found"]

        textFont(.system)
        for index in 0 ..< 3 {
            let x = left + Double(index) * (tile + gap)
            withState {
                translate(x, 20)
                withClip(Rectangle(x: 0, y: 0, width: tile, height: tile)) {
                    switch index {
                    case 0: colorField(tile)
                    case 1: warpedGrid(tile)
                    default: recoveredCircle(tile)
                    }
                }
            }
            fill(labelInk)
            textSize(16)
            textAlign(.center, .top)
            drawText(labels[index], x + tile / 2, 20 + tile + 8)
            textAlign(.left, .baseline)
        }
    }

    /// Six colors at six places, read back everywhere between and beyond them.
    private func colorField(_ side: Double) {
        guard let field = RadialBasis(points: anchors, values: inks) else { return }
        noStroke()
        for y in stride(from: 0.0, to: side, by: 4) {
            for x in stride(from: 0.0, to: side, by: 4) {
                fill(field.value(at: Vector2(x + 2, y + 2)))
                drawRect(x, y, 5, 5)
            }
        }
        // Ringed, not filled: what shows inside each ring is the field's own color, and it
        // matches, which is what passing through the data looks like.
        noFill()
        stroke(Color(hex: 0x101820, alpha: 0.8))
        strokeWeight(3)
        for anchor in anchors { drawCircle(center: anchor, radius: 10) }
        noStroke()
    }

    /// The same six places carrying displacements, which bends a straight grid.
    private func warpedGrid(_ side: Double) {
        // A filled rect rather than `background`, which would clear the whole canvas and
        // take the panels already drawn with it.
        noStroke()
        fill(Color(hex: 0x101820))
        drawRect(0, 0, side, side)
        let pulls = anchors.enumerated().map { i, a in
            a + Vector2(cos(Double(i) * 1.7), sin(Double(i) * 2.3)) * 34
        }
        guard let warp = RadialBasis(points: anchors, values: pulls) else { return }
        noFill()
        stroke(Color(hex: 0xAEBAC6))
        strokeWeight(1.2)
        for x in stride(from: -20.0, through: side + 20, by: 22) {
            drawPolyline(stride(from: -20.0, through: side + 20, by: 5).map {
                warp.value(at: Vector2(x, $0))
            })
        }
        for y in stride(from: -20.0, through: side + 20, by: 22) {
            drawPolyline(stride(from: -20.0, through: side + 20, by: 5).map {
                warp.value(at: Vector2($0, y))
            })
        }
        for (anchor, pull) in zip(anchors, pulls) {
            stroke(Color(hex: 0xE8734A))
            strokeWeight(2)
            drawLine(anchor, pull)
            noStroke()
            fill(Color(hex: 0xE8734A))
            drawCircle(center: pull, radius: 5)
        }
        noStroke()
    }

    /// Marks scattered around a circle nobody told the sketch about, and the ring three
    /// numbers walked downhill describe.
    private func recoveredCircle(_ side: Double) {
        noStroke()
        fill(Color(hex: 0x101820))
        drawRect(0, 0, side, side)
        let truth = Vector2(side * 0.5, side * 0.5)
        let marks = (0 ..< 90).map { i -> Vector2 in
            let a = Double(i) / 90 * .tau
            return truth + Vector2(cos(a), sin(a)) * (92 + sin(a * 4.3) * 13)
        }
        noStroke()
        fill(Color(hex: 0x9FB3C8))
        for mark in marks { drawCircle(center: mark, radius: 2.6) }

        let found = Fit.minimize(from: [side * 0.3, side * 0.3, 30], steps: 400, rate: 3) { p in
            let center = Vector2(p[0], p[1])
            return marks.reduce(0.0) { total, mark in
                let off = center.distance(to: mark) - p[2]
                return total + off * off
            }
        }
        noFill()
        stroke(Color(hex: 0xE0C25C))
        strokeWeight(2.5)
        drawCircle(found.values[0], found.values[1], found.values[2])
        noStroke()
        fill(Color(hex: 0xE0C25C))
        drawCircle(found.values[0], found.values[1], 4)
    }
}
