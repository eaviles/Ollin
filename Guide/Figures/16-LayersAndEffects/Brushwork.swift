// figure: frame=0 themed
//
// Guide diagram (Chapter 16): the anisotropic Kuwahara filter. A small hillside
// drawn into a layer, then the same layer through `.brushwork()`: each blade of
// grass widened into a stroke that follows its bend, the sky flattened into
// soft patches, and every edge kept.
import Ollin
import OllinDiagram

final class Brushwork: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 90, y: 92, width: 330, height: 180)
        let right = Rectangle(x: 460, y: 92, width: 330, height: 180)

        // The layer is the panel's own size, so a blade keeps the width the filter
        // painted it at.
        let scene = makeRenderTarget(width: Int(left.width), height: Int(left.height))
        withTarget(scene) { paint(width: left.width, height: left.height) }

        drawImage(scene.image, in: left)
        drawImage(scene.filtered(.brushwork()).image, in: right)

        frame(left, title: "the layer")
        frame(right, title: "filtered(.brushwork())")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("patches that run along the picture's own contours", width / 2, 312)
    }

    /// A hillside: sky, one cloud, a ridge, and grass in a breeze, from one seed.
    func paint(width: Double, height: Double) {
        seed(3)
        noStroke()

        // The sky runs to the bottom, so the ridge's dips never open onto the paper.
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, height * 0.55),
                     Ramp([Color(hex: 0x2F63AE), Color(hex: 0xBFD9F2)])))
        drawRect(0, 0, width, height)

        for lobe in 0 ..< 3 {
            let at = Vector2(width * 0.62 + Double(lobe - 1) * 26, height * 0.2 + (lobe == 1 ? -10 : 0))
            fill(.radial(center: at, radius: 34,
                         Ramp([Color(white: 1, alpha: 0.95), Color(white: 1, alpha: 0)])))
            drawEllipse(center: at, radiusX: 34, radiusY: 24)
        }

        var crest: [Vector2] = []
        for x in stride(from: -10.0, through: width + 10, by: 8) {
            crest.append(Vector2(x, height * 0.6 - noise(x * 0.006, 0.5) * height * 0.14))
        }
        crest.append(Vector2(width + 10, height + 10))
        crest.append(Vector2(-10, height + 10))
        fill(.linear(from: Vector2(0, height * 0.46), to: Vector2(0, height),
                     Ramp([Color(hex: 0x8FBF7A), Color(hex: 0x2A4F26)])))
        drawPolygon(crest)

        let greens = Ramp([Color(hex: 0x3C7A2E), Color(hex: 0x7DBE4A), Color(hex: 0xC8D65A)])
        strokeCap(.round)
        for _ in 0 ..< 260 {
            let root = Vector2(random(-4, width + 4), random(height * 0.68, height + 2))
            let depth = (root.y - height * 0.68) / (height * 0.34)
            let tall = height * (0.08 + 0.16 * depth) * random(0.7, 1.3)
            let lean = 0.35 + random(-0.2, 0.2)
            var blade: [Vector2] = []
            for step in 0 ... 5 {
                let t = Double(step) / 5
                blade.append(Vector2(root.x + lean * tall * t * t, root.y - tall * t))
            }
            stroke(greens.color(at: random(0, 1)).darker(by: 0.18 * (1 - depth)))
            strokeWeight(1.2 + 1.6 * depth)
            drawPolyline(blade)
        }
        noStroke()
        for _ in 0 ..< 12 {
            fill([Color(hex: 0xE04E4E), Color(hex: 0xFFD447), Color(hex: 0xF3F0FF)][Int(random(0, 3)) % 3])
            drawCircle(random(0, width), random(height * 0.78, height), random(2, 3.5))
        }
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
}
