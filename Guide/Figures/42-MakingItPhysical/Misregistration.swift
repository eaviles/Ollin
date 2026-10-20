// figure: frame=0
//
// Guide figure (Chapter 42): a three-ink poster as the press would print it
// in register, with its plates slipped out of register, and slipped and then
// screened, so each plate's dots keep their own angle.
import Ollin

final class Misregistration: Sketch {
    override var canvasSize: CanvasSize { .size(880, 340) }

    private var inRegister = Image(width: 1, height: 1)
    private var slipped = Image(width: 1, height: 1)
    private var screened = Image(width: 1, height: 1)

    override func setup() {
        let separation = paint().separated(into: [.black, .blue, .fluorescentPink])
        inRegister = separation.preview()
        let off = separation.misregistered(offsets: [.zero, Vector2(7, 4), Vector2(-6, 3)],
                                           rotations: [0, 0.02, 0])
        slipped = off.preview()
        screened = off.halftoned(pitch: 6).preview()
    }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        let tile = 276.0, gap = 16.0, top = 14.0
        let left = (width - tile * 3 - gap * 2) / 2
        for (i, image) in [inRegister, slipped, screened].enumerated() {
            drawImage(image, in: Rectangle(x: left + Double(i) * (tile + gap), y: top, width: tile, height: tile))
        }
        textFont(.system)
        noStroke()
        fill(Color(white: 0.5))
        textSize(17)
        textAlign(.center, .top)
        drawText("in register", left + tile / 2, top + tile + 10)
        drawText("the plates slipped", left + tile * 1.5 + gap, top + tile + 10)
        drawText("slipped, then screened", left + tile * 2.5 + gap * 2, top + tile + 10)
    }

    /// A poster of flat shapes in the inks' colors: a sun ringed in black, a
    /// blue ridge, a navy ground the blue and the black plates both print,
    /// and stripes, so the separation is exact and a slip shows as ink.
    private func paint() -> Image {
        let side = 276
        let image = Image(width: side, height: side)
        let black = Ink.black.color, blue = Ink.blue.color, pink = Ink.fluorescentPink.color
        let navy = Color(red: blue.red * black.red, green: blue.green * black.green, blue: blue.blue * black.blue)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                var c = Color.white
                let sun = (p - Vector2(150, 92)).length
                if sun < 58 { c = pink }
                if sun > 58 && sun < 64 { c = black }
                if p.y > 168 + 20 * sin(p.x * 0.026 + 1.1) + 9 * sin(p.x * 0.061) { c = blue }
                if p.y > 206 + 14 * sin(p.x * 0.04 + 3) { c = navy }
                if p.y > 236 && Int(p.x / 18) % 2 == 0 { c = .white }
                image[x, y] = c
            }
        }
        return image
    }
}
