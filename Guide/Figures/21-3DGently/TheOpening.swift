// figure: frame=0 themed
//
// Guide diagram (Chapter 21): a highlight is a picture of the opening.
// The same handful of lights thrown out of focus three times: through a round
// opening, through a five-bladed iris, and through the same iris with the
// barrel clipping it toward the corners.
import Ollin

final class TheOpening: Sketch {
    override var canvasSize: CanvasSize { .size(880, 380) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x232020) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }

    override func draw() {
        background(paper)

        // Square layers, because the panels are square: a layer drawn into a panel of
        // another shape would squash every highlight into an ellipse and say the
        // opposite of what this figure is for.
        let side = 262
        let lights = renderTarget(width: side, height: side)
        withTarget(lights) { lamps(Double(side)) }
        let far = renderTarget(width: side, height: side)
        withTarget(far) { background(.white) }          // every light sits far away

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 58, width: 262, height: 262)
        }
        let settings: [(blades: Int, catsEye: Double)] = [(0, 0), (5, 0), (5, 1)]
        let titles = ["round opening", "5 blades", "+ the barrel"]

        for (i, panel) in panels.enumerated() {
            let blurred = lights.combined(with: far,
                                          .defocus(focus: 0, range: 0.05, maxBlur: 34,
                                                   quality: .detail,
                                                   blades: settings[i].blades,
                                                   catsEye: settings[i].catsEye))
            drawImage(blurred.image, in: panel)
            frame(panel, title: titles[i])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("out of focus, a point of light draws the iris it came through",
                 width / 2, 336)
    }

    /// A few small lamps, far brighter than the picture can show. Spreading one over
    /// the whole opening is what divides it back into range.
    func lamps(_ side: Double) {
        background(Color(hex: 0x07080D))
        noStroke()
        seed(3)
        for _ in 0 ..< 11 {
            let hue = random(1)
            let color = Color(hue: hue, saturation: 0.3, brightness: 1)
            fill(Color(red: color.red * 5, green: color.green * 5, blue: color.blue * 5))
            drawCircle(random(0.1, 0.9) * side, random(0.1, 0.9) * side, random(4, 6))
        }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
