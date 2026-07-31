// figure: frame=0
//
// Guide diagram (Chapter 2): what dithering is for. One smooth color field
// reduced to the same five colors three ways. Snapping each pixel to its
// nearest color bands; a threshold map and error diffusion both trade those
// bands for texture the eye reads back as the original tone.
import Ollin

final class Dithering: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    var panelsOut: [Image] = []

    override func setup() {
        let source = field(size: 262)
        let five = Palette([Color(hex: 0x14213D), Color(hex: 0x5E60CE),
                            Color(hex: 0xE56B6F), Color(hex: 0xFFB703),
                            Color(hex: 0xF7F5F1)])
        panelsOut = [source.dithered(.none, to: five),
                     source.dithered(.ordered(size: 8), to: five),
                     source.dithered(.floydSteinberg, to: five)]
    }

    override func draw() {
        background(paper)

        let titles = [".none (just snap)", ".ordered(size: 8)", ".floydSteinberg"]
        for (i, picture) in panelsOut.enumerated() {
            let panel = Rectangle(x: 25 + Double(i) * 284, y: 62,
                                  width: 262, height: 262)
            drawImage(picture, in: panel)
            frame(panel, title: titles[i])
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("same five colors; only the arrangement changes",
                 width / 2, 348)
    }

    /// A smooth two-way gradient, the hardest thing to quantize cleanly.
    func field(size: Int) -> Image {
        let image = Image(width: size, height: size)
        let ramp = Ramp([Color(hex: 0x14213D), Color(hex: 0x5E60CE),
                         Color(hex: 0xE56B6F), Color(hex: 0xFFB703)])
        for y in 0 ..< size {
            for x in 0 ..< size {
                let u = Double(x) / Double(size - 1)
                let v = Double(y) / Double(size - 1)
                let t = min(1, max(0, v * 0.75 + u * 0.25))
                image[x, y] = Color.mix(ramp.color(at: t), paper,
                                        t: smoothstep(0.35, 1, u) * 0.55)
            }
        }
        return image
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
        drawText(title, r.x, r.y - 18)
    }
}
