// figure: frame=0 themed
//
// Guide diagram (Appendix B): how the pairs grow. Three rings of 5, 10, and
// 20 dots with a line between every pair of them. The count under each is
// n times (n - 1) over 2: 10, 45, and 190 pairs. Doubling the dots about
// quadruples the pairs, which is why asking every creature about every
// other creature gets slow.
import Ollin
import OllinDiagram

final class EveryPair: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    override func draw() {
        background(theme.paper)
        ring(count: 5, center: Vector2(150, 240))
        ring(count: 10, center: Vector2(440, 240))
        ring(count: 20, center: Vector2(730, 240))
        diagramCaption("twice the dots, about four times the pairs", at: 488, theme: theme)
    }

    func ring(count n: Int, center: Vector2) {
        let radius = 120.0
        let dots = (0..<n).map { k in
            center + Vector2(angle: Double(k) / Double(n) * .tau - .pi / 2, length: radius)
        }

        stroke(theme.ink(0.3))
        strokeWeight(1.2)
        for i in 0..<n {
            for j in (i + 1)..<n {
                drawLine(dots[i], dots[j])
            }
        }

        noStroke()
        fill(theme.accent)
        for dot in dots {
            drawCircle(center: dot, radius: 6)
        }

        fill(theme.ink)
        textSize(17)
        textAlign(.center, .top)
        drawText("\(n) dots", center.x, center.y + radius + 22)
        fill(theme.muted)
        textSize(15)
        drawText("\(n * (n - 1) / 2) pairs", center.x, center.y + radius + 46)
    }
}
