// figure: frame=0 themed
//
// Guide diagram (Chapter 9): seam carving. The chapter's sunset at its own
// width, squeezed to seven tenths of it, and carved to the same width by
// removing the cheapest paths down. The squeeze narrows everything together;
// the carve takes the empty sky and leaves the sun the shape it was.
import Ollin

final class CarvedNarrower: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var source: Image?
    var carved: Image?

    override func setup() {
        noiseSeed(3)
        let picture = makeSunset(size: 300)
        source = picture
        // Hold the sun still: it is nearly flat inside, and a flat thing is
        // cheap to cross, so without a mask the carve would narrow it too.
        let mask = Image(width: 300, height: 300, color: .black)
        for py in 0..<300 {
            for px in 0..<300 {
                let u = Double(px) / 299, v = Double(py) / 299
                let d = ((u - 0.58) * (u - 0.58) + (v - 0.47) * (v - 0.47)).squareRoot()
                if d < 0.12 { mask[px, py] = .white }
            }
        }
        carved = picture.seamCarved(toWidth: 210, protecting: mask)
    }

    override func draw() {
        background(paper)
        guard let source, let carved else { return }

        let full = Rectangle(x: 92, y: 96, width: 240, height: 240)
        let squeezed = Rectangle(x: 392, y: 96, width: 168, height: 240)
        let narrowed = Rectangle(x: 620, y: 96, width: 168, height: 240)

        drawImage(source, in: full)
        drawImage(source, in: squeezed)
        drawImage(carved, in: narrowed)

        frame(full, title: "the picture")
        frame(squeezed, title: "squeezed to 70%")
        frame(narrowed, title: "carved to 70%, sun held")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the squeeze narrows everything; the carve takes the empty sky",
                 width / 2, 386)
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
                    color = Color.mix(color, Color(hex: 0xFFF3D6), t: min(1, disk + glow))
                } else {
                    let w = (v - horizon) / (1 - horizon)
                    let reflected = sky.color(at: max(0, 0.92 - w * 0.9))
                    let dark = Color.mix(reflected, Color(hex: 0x0B1020), t: 0.45 + w * 0.4)
                    let streak = noise(u * 5, v * 120)
                    let path = 1 - smoothstep(0.02, 0.16 + w * 0.3, abs(u - sunX))
                    color = Color.mix(dark, Color(hex: 0xFFD98A),
                                      t: min(1, path * (0.2 + streak * 0.8)))
                }
                image[px, py] = color
            }
        }
        return image
    }
}
