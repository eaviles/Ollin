// figure: frame=0 themed
//
// Guide diagram (Chapter 15): the same curve dashed three ways at one
// strokeWeight. An even dash, dots made of zero-length dashes under round caps,
// and a taper that keeps reading the whole path across the gaps. Only the
// pattern and the cap change.
import Ollin
import OllinDiagram

final class DashPatterns: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)
        textSize(17)

        let titles = ["[18, 10]", ".dots(spacing: 16)", "[18, 10] with .taper()"]

        for i in 0 ..< 3 {
            let r = Rectangle(x: 68 + Double(i) * 260, y: 56, width: 230, height: 196)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            withState {
                stroke(ink)
                strokeWeight(11)
                switch i {
                case 0:
                    strokeDash([18, 10])
                case 1:
                    strokeCap(.round)
                    strokeDash(.dots(spacing: 16))
                default:
                    strokeProfile(.taper())
                    strokeDash([18, 10])
                }
                drawPolyline(curve(in: r))
            }

            noStroke()
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
