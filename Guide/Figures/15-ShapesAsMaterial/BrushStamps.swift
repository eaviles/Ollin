// figure: frame=0 probe themed
//
// Guide diagram (Chapter 15): the same curve stamped three ways at one
// strokeWeight. Close-packed circles that read as a solid mark, squares that
// turn with the path, and a loose spray thrown either side of it. Only the
// brush changes.
import Ollin

final class BrushStamps: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }

    override func draw() {
        background(paper)
        textSize(17)

        let titles = [".round", ".chisel()", ".spray()"]

        for i in 0 ..< 3 {
            let r = Rectangle(x: 68 + Double(i) * 260, y: 56, width: 230, height: 196)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            withState {
                stroke(ink)
                strokeWeight(17)
                switch i {
                case 0: strokeBrush(.round)
                case 1: strokeBrush(.chisel())
                default: strokeBrush(.spray(seed: 4))
                }
                drawPolyline(curve(in: r))
            }

            noStroke()
            noStrokeBrush()
            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.center.x, r.y + r.height + 14)
        }
    }

    /// One S-curve, placed inside a panel.
    private func curve(in r: Rectangle) -> [Vector2] {
        (0 ... 60).map { k in
            let t = Double(k) / 60
            return Vector2(r.x + 26 + t * (r.width - 52),
                           r.center.y + sin(t * .pi * 2) * (r.height * 0.24))
        }
    }
}
