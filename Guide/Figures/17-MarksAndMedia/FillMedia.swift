// figure: frame=0 probe themed
//
// Guide diagram (Chapter 17): one blob in ten fill media at one size. Every
// panel stands on the same striped ground, which the wash glazes, the gouache
// covers, the chrome reflects at its rim, and the two glasses bend; the paint,
// the knife, rock, marble, and sand are lit from the upper left.
import Ollin
import OllinDiagram

final class FillMedia: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    let sky = Color(red: 0.23, green: 0.43, blue: 0.65)
    let straw = Color(red: 0.96, green: 0.83, blue: 0.37)

    override func draw() {
        background(paper)
        textSize(16)

        let titles = [".impasto", ".knife", ".wash", ".gouache", ".chrome",
                      ".glass", ".facetedGlass", ".rock", ".marble", ".sand"]
        let media: [FillMedium] = [.impasto(seed: 2), .knife(seed: 1), .wash, .gouache, .chrome,
                                   .glass, .facetedGlass(seed: 3), .rock(seed: 1), .marble(seed: 2), .sand]
        let colors = [Color(red: 0.78, green: 0.33, blue: 0.24), Color(red: 0.18, green: 0.53, blue: 0.67),
                      Color(red: 0.62, green: 0.25, blue: 0.45), Color(red: 0.93, green: 0.42, blue: 0.27),
                      .white, Color(red: 0.8, green: 0.92, blue: 0.95), .white,
                      Color(red: 0.54, green: 0.5, blue: 0.45), Color(red: 0.93, green: 0.91, blue: 0.88),
                      Color(red: 0.85, green: 0.72, blue: 0.5)]

        for i in 0 ..< 10 {
            let r = Rectangle(x: 28 + Double(i % 5) * 168, y: 26 + Double(i / 5) * 236,
                              width: 152, height: 172)
            // The ground: stripes of two colors.
            noFillMedium()
            noStroke()
            var x = r.x
            var k = 0
            while x < r.x + r.width {
                let w = min(12, r.x + r.width - x)
                fill(k % 2 == 0 ? sky : straw)
                drawRect(x, r.y, w, r.height)
                x += 12
                k += 1
            }
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            noStroke()
            fill(colors[i])
            fillMedium(media[i])
            drawShape(blob(around: r.center, radius: 60, phase: Double(i) * 0.9))
            noFillMedium()

            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.center.x, r.y + r.height + 12)
        }
    }

    /// A rounded blob around `center`, its radius wandering by a few sines.
    private func blob(around center: Vector2, radius: Double, phase: Double) -> Shape {
        let points = (0 ..< 160).map { k -> Vector2 in
            let a = Double(k) / 160 * .tau
            let rr = radius * (1 + 0.12 * sin(3 * a + phase) + 0.06 * sin(5 * a + 2 * phase))
            return center + Vector2(cos(a), sin(a)) * rr
        }
        return Shape(contours: [Contour(points, closed: true)])
    }
}
