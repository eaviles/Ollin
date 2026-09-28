// figure: frame=0 themed
//
// Guide diagram (Chapter 20): one poster read through the three filters that
// join the catalog together. A barrel lens distortion bows its straight lines
// and leaves the corners empty, a corner pin lays it onto four points with two
// edges converging, and a channel mixer prints it as the monochrome a red
// filter makes, the red bars light and the blue ones dark.
import Ollin
import OllinDiagram

final class LensPinMixer: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 62, width: 262, height: 262)
        }

        // One poster: bars of color, a grid so a bend shows, and two discs.
        let poster = makeRenderTarget(width: 262, height: 262)
        withTarget(poster) {
            noStroke()
            let bars: [UInt32] = [0xE63946, 0xF1FAEE, 0xA8DADC, 0x457B9D, 0x1D3557, 0xF4A261]
            for (i, hex) in bars.enumerated() {
                fill(Color(hex: hex))
                drawRect(0, Double(i) * 262 / 6, 262, 262 / 6 + 1)
            }
            stroke(Color(white: 0.1, alpha: 0.65)); strokeWeight(3); noFill()
            for i in 1 ..< 5 {
                let g = Double(i) * 262 / 5
                drawLine(g, 0, g, 262); drawLine(0, g, 262, g)
            }
            noStroke()
            fill(Color(red: 1, green: 0.88, blue: 0.2)); drawCircle(84, 92, 36)
            fill(Color(red: 0.2, green: 0.85, blue: 0.5, alpha: 0.6)); drawCircle(178, 172, 44)
        }

        drawImage(poster.filtered(.lensDistortion(amount: 0.3, quartic: 0.1)).image,
                  in: panels[0])
        drawImage(poster.filtered(.cornerPin(topLeft: Vector2(0.12, 0.1),
                                             topRight: Vector2(0.9, 0.2),
                                             bottomRight: Vector2(0.95, 0.9),
                                             bottomLeft: Vector2(0.05, 0.85))).image,
                  in: panels[1])
        drawImage(poster.filtered(.channelMixer(.gray(red: 0.7, green: 0.2, blue: 0.1))).image,
                  in: panels[2])

        let titles = [".lensDistortion(amount: 0.3)",
                      ".cornerPin(topLeft:topRight:...)",
                      ".channelMixer(.gray(red: 0.7, ...))"]
        for (i, panel) in panels.enumerated() { frame(panel, title: titles[i]) }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one poster, bent by a lens, thrown onto a wall, and printed through a red filter",
                 width / 2, 348)
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
