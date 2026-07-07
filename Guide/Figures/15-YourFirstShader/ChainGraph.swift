// figure: frame=0
//
// Guide diagram (Chapter 15): a Visual chain as a graph. Each thumbnail is
// the real chain up to that step: the oscillator source, folded by the
// kaleidoscope, then displaced by a noise driver patched in from the side.
import Ollin

final class ChainGraph: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let source: Visual = .oscillator(frequency: 24, colorShift: 0.12)
        let folded = source.kaleidoscope(6)
        let driver: Visual = .noise(scale: 3)
        let final = folded.displaced(by: driver, amount: 0.12)

        let w = 210.0, h = 210.0
        let y = 100.0
        thumb(source, 40, y, w, h, ".oscillator(frequency: 24)")
        thumb(folded, 335, y, w, h, ".kaleidoscope(6)")
        thumb(final, 630, y, w, h, ".displaced(by: noise)")
        thumb(driver.brightness(0.5), 483, 370, w * 0.55, h * 0.55, "the noise driver")

        arrow(from: Vector2(40 + w + 10, y + h / 2), to: Vector2(335 - 10, y + h / 2))
        arrow(from: Vector2(335 + w + 10, y + h / 2), to: Vector2(630 - 10, y + h / 2))
        arrow(from: Vector2(483 + w * 0.55 + 10, 370 + h * 0.27),
              to: Vector2(630 + w * 0.32, y + h + 12))

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a chain reads left to right; a driver patches into any step", width / 2, 505)
    }

    func thumb(_ chain: Visual, _ x: Double, _ y: Double,
               _ w: Double, _ h: Double, _ caption: String) {
        let panel = Rectangle(x: x, y: y, width: w, height: h)
        drawImage(generate(chain, width: Int(w), height: Int(h)).image, in: panel)
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(panel)
        noStroke()
        fill(faint)
        textSize(15)
        textAlign(.center, .top)
        drawText(caption, panel.center.x, y + h + 8)
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
