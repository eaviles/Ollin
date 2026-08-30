// figure: frame=0 themed
//
// Guide diagram (Chapter 9): a picture turned into line work. The same
// stipple of the chapter's sunset joined two ways: one closed tour that
// never lifts the pen, and the minimum spanning tree, which branches.
import Ollin
import OllinDiagram

final class PictureAsLines: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var dots: [Vector2] = []
    var tour: Contour?
    var tree: [Contour] = []

    override func setup() {
        noiseSeed(3)
        seed(5)
        let source = makeSunset(size: 160)
        let first = Rectangle(x: 25, y: 66, width: 262, height: 262)
        dots = stipple(of: source, count: 1500, in: first, iterations: 24)
        tour = singleLine(through: dots)
        tree = spanningTree(through: dots)
    }

    override func draw() {
        background(paper)

        let panels = [Rectangle(x: 25, y: 66, width: 262, height: 262),
                      Rectangle(x: 309, y: 66, width: 262, height: 262),
                      Rectangle(x: 593, y: 66, width: 262, height: 262)]

        noStroke()
        fill(ink)
        drawCircles(dots, radius: 1.5)

        withState {
            translate(284, 0)
            noFill()
            stroke(ink)
            strokeWeight(0.8)
            if let tour { drawPolyline(tour.points, closed: tour.isClosed) }
        }

        withState {
            translate(568, 0)
            noFill()
            stroke(ink)
            strokeWeight(0.8)
            for chain in tree { drawPolyline(chain.points) }
        }

        frame(panels[0], title: "the stipple")
        frame(panels[1], title: "one unbroken tour")
        frame(panels[2], title: "the spanning tree")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the same 1,500 dots, joined into a loop and into branches",
                 width / 2, 364)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }

    /// The chapter's authored sunset, so every treatment reads the same image.
    func makeSunset(size: Int) -> Image {
        let image = Image(width: size, height: size)
        let sky = Ramp([Color(hex: 0x14213D), Color(hex: 0x5E60CE),
                        Color(hex: 0xE56B6F), Color(hex: 0xFFB703)])
        let horizon = 0.62
        let sunX = 0.58, sunY = 0.47
        for py in 0..<size {
            for px in 0..<size {
                let u = Double(px) / Double(size - 1)
                let v = Double(py) / Double(size - 1)
                var color: Color
                if v < horizon {
                    color = sky.color(at: v / horizon)
                    let d = ((u - sunX) * (u - sunX) + (v - sunY) * (v - sunY)).squareRoot()
                    let disk = 1 - smoothstep(0.075, 0.095, d)
                    let glow = (1 - smoothstep(0.04, 0.4, d)) * 0.5
                    color = Color.mix(color, Color(hex: 0xFFF3D6), min(1, disk + glow))
                } else {
                    let w = (v - horizon) / (1 - horizon)
                    let reflected = sky.color(at: max(0, 0.92 - w * 0.9))
                    let dark = Color.mix(reflected, Color(hex: 0x0B1020), 0.45 + w * 0.4)
                    let streak = noise(u * 5, v * 120)
                    let path = 1 - smoothstep(0.02, 0.16 + w * 0.3, abs(u - sunX))
                    color = Color.mix(dark, Color(hex: 0xFFD98A),
                                      min(1, path * (0.2 + streak * 0.8)))
                }
                image[px, py] = color
            }
        }
        return image
    }
}
