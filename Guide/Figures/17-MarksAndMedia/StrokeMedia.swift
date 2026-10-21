// figure: frame=0 probe themed
//
// Guide diagram (Chapter 17): one curve in eight stroke media at one
// strokeWeight. The four dry panels draw a mark whose density falls along its
// length, so the paper's tooth shows a light line breaking into speckles rather
// than fading. The brush panels streak two pigments and run dry; the wet and oil
// panels cross a ground in two colors, which the wet paint drags along with it.
import Ollin
import OllinDiagram

final class StrokeMedia: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    let red = Color(red: 0.75, green: 0.22, blue: 0.17)
    let gold = Color(red: 0.95, green: 0.65, blue: 0.07)
    let navy = Color(red: 0.16, green: 0.2, blue: 0.36)
    let sky = Color(red: 0.23, green: 0.43, blue: 0.65)
    let straw = Color(red: 0.96, green: 0.83, blue: 0.37)

    override func draw() {
        background(paper)
        textSize(16)

        let titles = [".pencil", ".charcoal", ".pastel", ".pastel(palette:)",
                      ".bristles", ".dryBrush", ".wet", ".oil"]
        let media: [StrokeMedium] = [
            .pencil, .charcoal, .pastel, .pastel(palette: [red, gold, navy], seed: 3),
            .bristles(gold, seed: 2), .dryBrush(seed: 4), .wet, .oil(seed: 6),
        ]

        for i in 0 ..< 8 {
            let r = Rectangle(x: 36 + Double(i % 4) * 206, y: 34 + Double(i / 4) * 262,
                              width: 188, height: 196)
            if i >= 6 {
                // The ground the wet paint drags: two colors split down the middle.
                noStroke()
                fill(sky)
                drawRect(r.x, r.y, r.width / 2, r.height)
                fill(straw)
                drawRect(r.x + r.width / 2, r.y, r.width / 2, r.height)
            }
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(r)

            withState {
                strokeCap(.round)
                strokeWeight(i < 4 ? 22 : 28)
                strokeMedium(media[i])
                switch i {
                case 0, 1, 5: stroke(ink)
                case 3: stroke(.white)
                default: stroke(red)
                }
                if i < 4 {
                    // A mark whose density falls from full to a seventh along it.
                    let points = curve(in: r)
                    drawMark(StrokeMark(samples: points.indices.map { k in
                        StrokeMark.Sample(position: points[k],
                                          opacity: 1 - 0.86 * Double(k) / Double(points.count - 1))
                    }))
                } else {
                    drawPolyline(curve(in: r))
                }
            }

            noStroke()
            fill(ink)
            textAlign(.center, .top)
            drawText(titles[i], r.center.x, r.y + r.height + 12)
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
