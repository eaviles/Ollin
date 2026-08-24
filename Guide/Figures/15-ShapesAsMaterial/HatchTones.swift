// figure: frame=0 themed
//
// Guide diagram (Chapter 15): a pen has no gray, only spacing. The same
// blob hatched three ways: wide spacing for a light tone, tight for a dark
// one, crossed for the darkest. The outline stays crisp because it's drawn
// as its own line.
import Ollin

final class HatchTones: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.4) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }

    override func draw() {
        background(paper)
        textSize(17)

        let hatches = [Hatching(spacing: 13, angle: .pi / 4),
                       Hatching(spacing: 6, angle: .pi / 4),
                       Hatching(spacing: 7, angle: .pi / 4, crossHatch: true)]
        let titles = ["spacing 13", "spacing 6", "crosshatch"]

        for i in 0 ..< 3 {
            let r = Rectangle(x: 68 + Double(i) * 260, y: 60, width: 230, height: 190)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            let blob = blobShape(in: r)
            noFill()
            stroke(ink)
            strokeWeight(1.3)
            for line in hatches[i].lines(filling: blob) {
                drawPolyline(line)
            }
            strokeWeight(2.2)
            for contour in blob.contours { drawPolygon(contour.points) }

            noStroke()
            fill(faint)
            textAlign(.center, .top)
            drawText(titles[i], r.x + r.width / 2, r.y + r.height + 14)
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a pen has no gray, only spacing", width / 2, 288)
    }

    /// A soft blob with a hole, so the hatch shows both respected.
    func blobShape(in r: Rectangle) -> Shape {
        let c = Vector2(r.x + r.width / 2, r.y + r.height / 2)
        let outer = (0 ..< 40).map { k -> Vector2 in
            let a = Double(k) / 40 * .tau
            let radius = 74 + sin(a * 3) * 14
            return c + Vector2(angle: a, length: radius)
        }
        let hole = (0 ..< 24).map { k -> Vector2 in
            c + Vector2(-18, 8) + Vector2(angle: Double(k) / 24 * .tau, length: 24)
        }
        return Shape(contours: [Contour(outer, closed: true), Contour(hole, closed: true)],
                     winding: .evenOdd)
    }
}
