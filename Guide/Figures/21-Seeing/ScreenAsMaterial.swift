// figure: frame=0
//
// Guide diagram (Chapter 21): the screen as material. A stand-in desktop is
// drawn into a layer (a real capture would put the machine's own screen there,
// which no committed figure could reproduce), then shown twice: left, the
// capture with the sketch's own window left out, which is the default; right,
// the same capture with the window left in, so the picture recedes into itself.
import Ollin

final class ScreenAsMaterial: Sketch {
    override var canvasSize: CanvasSize { .size(880, 452) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)

    override func draw() {
        seed(7)
        background(paper)

        // The stand-in screen, drawn into a layer: a desktop with a menu bar and
        // a couple of windows on it. What a capture hands over is a picture, and
        // this is a picture, so everything downstream of it is honest. It is
        // built inside `draw()` because a layer is resolved as part of rendering
        // a frame, and `setup()` is not one.
        let screen = renderTarget()
        withTarget(screen) { drawDesktop(in: bounds) }
        let desktop = screen.image

        let left = Rectangle(x: 60, y: 66, width: 350, height: 250)
        let right = Rectangle(x: 470, y: 66, width: 350, height: 250)

        do {
            drawImage(desktop, in: left)

            // The tunnel: the same picture, with a sketch window on it that is
            // showing the picture, four times over. A live capture reaches this
            // by feeding each drawn frame back in; here it is drawn directly, so
            // the figure renders the same way every time.
            drawImage(desktop, in: right)
            var window = Rectangle(x: right.x + right.width * 0.30,
                                   y: right.y + right.height * 0.30,
                                   width: right.width * 0.60,
                                   height: right.height * 0.60)
            for depth in 0 ..< 4 {
                drawSketchWindow(window, showing: desktop, dim: Double(depth) * 0.06)
                let inner = contentArea(of: window)
                window = Rectangle(x: inner.x + inner.width * 0.30,
                                   y: inner.y + inner.height * 0.30,
                                   width: inner.width * 0.60,
                                   height: inner.height * 0.60)
            }
        }

        label(left, "excludesOwnWindows = true", "the screen, this sketch left out")
        label(right, "excludesOwnWindows = false", "the sketch left in, so it eats itself")

        noStroke()
        fill(ink)
        textSize(20)
        textAlign(.center, .top)
        drawText("one boolean is the difference between a mirror and a tunnel",
                 width / 2, 384)
    }

    // MARK: The stand-in screen

    private func drawDesktop(in area: Rectangle) {
        noStroke()
        // A plain gradient stands in for a wallpaper.
        for row in 0 ..< 40 {
            let t = Double(row) / 39
            fill(Color.mix(Color(hex: 0x1B3A5C), Color(hex: 0x6E4B7A), t: t, in: .oklab))
            drawRect(area.x, area.y + t * area.height,
                     area.width, area.height / 39 + 1)
        }
        // The menu bar.
        fill(Color(white: 1, alpha: 0.16))
        drawRect(area.x, area.y, area.width, area.height * 0.055)

        windowShape(Rectangle(x: area.x + area.width * 0.05,
                              y: area.y + area.height * 0.14,
                              width: area.width * 0.44,
                              height: area.height * 0.62),
                    tint: Color(hex: 0xE8E4DD), lines: 9)
        windowShape(Rectangle(x: area.x + area.width * 0.42,
                              y: area.y + area.height * 0.30,
                              width: area.width * 0.50,
                              height: area.height * 0.55),
                    tint: Color(hex: 0x232733), lines: 11)
    }

    /// A window with a title bar and some suggestion of content in it.
    private func windowShape(_ rect: Rectangle, tint: Color, lines: Int) {
        noStroke()
        fill(Color(white: 0, alpha: 0.28))
        drawRect(corner: Vector2(rect.x + 3, rect.y + 4),
                 width: rect.width, height: rect.height, cornerRadius: 7)
        fill(tint)
        drawRect(rect, cornerRadius: 7)
        fill(Color(white: 0, alpha: 0.10))
        drawRect(rect.x, rect.y, rect.width, 13, cornerRadius: 7)

        let dark = tint.luminance < 0.4
        fill(Color(white: dark ? 0.75 : 0.25, alpha: 0.55))
        for index in 0 ..< lines {
            let y = rect.y + 24 + Double(index) * (rect.height - 32) / Double(lines)
            guard y < rect.y + rect.height - 8 else { break }
            drawRect(rect.x + 9, y, (rect.width - 22) * random(0.35, 0.95), 3)
        }
    }

    /// One level of the tunnel: an Ollin window whose canvas holds the picture.
    private func drawSketchWindow(_ rect: Rectangle, showing picture: Image, dim: Double) {
        noStroke()
        fill(Color(white: 0, alpha: 0.35))
        drawRect(corner: Vector2(rect.x + 3, rect.y + 4),
                 width: rect.width, height: rect.height, cornerRadius: 8)
        fill(Color(hex: 0x1C1C1E))
        drawRect(rect, cornerRadius: 8)

        let bar = rect.height * 0.13
        fill(Color(hex: 0x2C2C2E))
        drawRect(rect.x, rect.y, rect.width, bar, cornerRadius: 8)
        for (index, dot) in [Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E),
                             Color(hex: 0x28C840)].enumerated() {
            fill(dot)
            drawCircle(rect.x + 9 + Double(index) * 11, rect.y + bar / 2, 3.4)
        }

        // The canvas, holding the picture the capture handed over. It is
        // letterboxed, which is what `drawFrame` does with a wide screen on a
        // canvas that is not the same shape.
        let canvas = contentArea(of: rect)
        fill(Color(hex: 0x0A0A0B))
        drawRect(canvas)
        tint(Color(white: 1 - dim))
        drawImage(picture, in: Rectangle(fitting: Vector2(Double(picture.width),
                                                          Double(picture.height)),
                                         in: canvas))
        noTint()
    }

    private func contentArea(of window: Rectangle) -> Rectangle {
        let bar = window.height * 0.13
        return Rectangle(x: window.x, y: window.y + bar,
                         width: window.width, height: window.height - bar)
    }

    // MARK: Labels

    private func label(_ rect: Rectangle, _ code: String, _ caption: String) {
        noFill()
        stroke(Color(hex: 0x2B2B2B, alpha: 0.35))
        strokeWeight(1)
        drawRect(rect)

        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.center, .bottom)
        drawText(code, rect.x + rect.width / 2, rect.y - 12)
        fill(Color(hex: 0x2B2B2B, alpha: 0.62))
        textSize(15)
        textAlign(.center, .top)
        drawText(caption, rect.x + rect.width / 2, rect.y + rect.height + 10)
    }
}
