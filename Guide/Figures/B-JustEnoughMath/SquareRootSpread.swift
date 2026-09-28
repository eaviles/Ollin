// figure: frame=0 themed
//
// Guide diagram (Appendix B): spreading darts over a disk. Both panels throw
// the same 900 angles and the same 900 draws of random(1). The left uses the
// draw as the distance from the center; the right uses its square root. The
// accent ring is half the radius, which holds a quarter of the disk's area,
// and each panel counts the darts that landed inside it.
import Ollin
import OllinDiagram

final class SquareRootSpread: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let count = 900
    let radius = 160.0
    var angles: [Double] = []
    var draws: [Double] = []

    override func setup() {
        seed(12)
        angles = (0..<count).map { _ in random(.tau) }
        draws = (0..<count).map { _ in random(1) }
    }

    override func draw() {
        background(theme.paper)
        panel(center: Vector2(225, 250), title: "distance = random(1) × R") { $0 }
        panel(center: Vector2(655, 250), title: "distance = sqrt(random(1)) × R") { $0.squareRoot() }
        diagramCaption("the square root spreads the same darts evenly", at: 488, theme: theme)
    }

    func panel(center: Vector2, title: String, spread: (Double) -> Double) {
        noFill()
        stroke(theme.ink(0.5))
        strokeWeight(2)
        drawCircle(center: center, radius: radius)
        stroke(theme.accent)
        strokeWeight(1.5)
        drawCircle(center: center, radius: radius / 2)

        var inside = 0
        noStroke()
        fill(theme.ink(0.8))
        for i in 0..<count {
            let distance = spread(draws[i]) * radius
            if distance < radius / 2 { inside += 1 }
            drawCircle(center: center + Vector2(angle: angles[i], length: distance), radius: 2)
        }

        fill(theme.ink)
        textSize(17)
        textAlign(.center, .bottom)
        drawText(title, center.x, center.y - radius - 14)
        fill(theme.accent)
        textSize(15)
        textAlign(.center, .top)
        drawText("\(inside) of \(count) inside half the radius", center.x, center.y + radius + 12)
    }
}
