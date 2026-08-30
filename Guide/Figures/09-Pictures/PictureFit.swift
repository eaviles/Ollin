// figure: frame=0 themed
//
// Guide diagram: one 3:2 landscape into three 2:3 boxes, one per ImageFit.
// Stretched, the round sun goes oval. Contained, the whole picture is there and
// the box shows above and below it. Covered, the box is full and the tree on the
// right has gone over the edge.
import Ollin
import OllinDiagram

final class PictureFit: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var box: Color { theme.card }

    private var picture = Image(width: 300, height: 200, color: .white)

    static let modes: [(ImageFit, String)] = [(.stretch, ".stretch"),
                                              (.contain, ".contain"),
                                              (.cover, ".cover")]

    override func setup() {
        textFont(OutlineFont.system)
        paint()
    }

    override func draw() {
        background(paper)
        for (i, mode) in PictureFit.modes.enumerated() {
            let frame = Rectangle(x: 104 + Double(i) * 236, y: 70, width: 200, height: 300)
            noStroke()
            fill(box)
            drawRect(corner: frame.corner, width: frame.width, height: frame.height)
            drawImage(picture, in: frame, fit: mode.0)
            noFill()
            stroke(ink.withAlpha(0.3))
            strokeWeight(1.5)
            drawRect(corner: frame.corner, width: frame.width, height: frame.height)
            noStroke()
            fill(ink)
            textSize(22)
            textAlign(.center, .top)
            drawText(mode.1, frame.center.x, 388)
        }
        fill(faint)
        textSize(18)
        textAlign(.center, .top)
        drawText("the picture is 3:2, every box is 2:3", 440, 432)
        drawText("the sun is round; the tree is on the right", 440, 462)
    }

    /// A low sun over two ridges, one tree well off to the right.
    func paint() {
        let w = picture.width, h = picture.height
        let sun = Vector2(Double(w) * 0.30, Double(h) * 0.33), radius = 29.0
        for y in 0..<h {
            let v = Double(y) / Double(h - 1)
            let sky = Color.mix(Color(hex: 0x3E5C7E), Color(hex: 0xE8B478), pow(v, 0.7))
            for x in 0..<w {
                let d = Vector2(Double(x), Double(y)).distance(to: sun)
                var c = sky
                if d < radius {
                    c = Color(hex: 0xFFF0C2)
                } else if d < radius * 2.4 {
                    c = Color.mix(c, Color(hex: 0xFFD98F), (1 - (d - radius) / (radius * 1.4)) * 0.5)
                }
                picture[x, y] = c
            }
        }
        ridge(base: 0.62, amplitude: 16, frequency: 2.1, phase: 0.4, color: Color(hex: 0x5D6B77))
        ridge(base: 0.78, amplitude: 11, frequency: 1.3, phase: 2.2, color: Color(hex: 0x2E3A43))
        tree(at: 0.85, ground: 0.78)
    }

    func ridge(base: Double, amplitude: Double, frequency: Double, phase: Double, color: Color) {
        let w = picture.width, h = picture.height
        for x in 0..<w {
            let u = Double(x) / Double(w - 1)
            let top = Double(h) * base + sin(u * .tau * frequency + phase) * amplitude
            for y in Int(top)..<h where y >= 0 { picture[x, y] = color }
        }
    }

    func tree(at u: Double, ground: Double) {
        let w = picture.width, h = picture.height
        let x0 = Double(w) * u, base = Double(h) * ground
        let crown = Vector2(x0, base - 39), bark = Color(hex: 0x22282C)
        for y in 0..<h {
            for x in 0..<w {
                let p = Vector2(Double(x), Double(y))
                if (abs(p.x - x0) < 3 && p.y > crown.y && p.y < base) || p.distance(to: crown) < 19 {
                    picture[x, y] = bark
                }
            }
        }
    }
}
