// figure: frame=0 themed
//
// Guide diagram (Chapter 32): a sketch in the menu bar. Along the top, where it
// sits: one status item among the others, at the size it really is. Below, the
// same strip enlarged, with the canvas coordinates written on it, because the
// surprise is that nothing changes except how much room there is. On the right,
// the rate it draws at and the click that gets you out.
import Ollin
import OllinDiagram

final class SmallestCanvas: Sketch {
    override var canvasSize: CanvasSize { .size(880, 424) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The strip's own size in points, which is also its canvas.
    let stripWidth = 56.0
    let stripHeight = 22.0

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()
        textFont(.system)

        drawText("The smallest canvas you will ever draw on.",
                 40, 26, size: 17, color: theme.ink, align: .left, .top)
        drawText("ollin new Pulse --kind menu-bar", 40, 52,
                 size: 12, color: theme.accent, align: .left, .top)

        menuBar()
        enlarged()
        notes()
    }

    // MARK: Where it sits

    func menuBar() {
        let theme = self.theme
        let bar = Rectangle(x: 40, y: 96, width: 800, height: 26)
        fill(theme.card)
        drawRect(bar)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(bar)
        noStroke()

        drawText("  Pulse    File    Edit    Window", bar.x + 12, bar.center.y,
                 size: 11, color: theme.ink, align: .left, .middle)

        // The status items, ours among them at the size it really is.
        let strip = Rectangle(x: bar.x + bar.width - 226, y: bar.center.y - stripHeight / 2,
                              width: stripWidth, height: stripHeight)
        pulse(in: strip)
        stroke(theme.accent)
        strokeWeight(1.5)
        noFill()
        drawRect(Rectangle(x: strip.x - 2, y: strip.y - 2,
                           width: strip.width + 4, height: strip.height + 4), cornerRadius: 4)
        noStroke()

        drawText("battery    9:41", bar.x + bar.width - 12, bar.center.y,
                 size: 11, color: theme.ink, align: .right, .middle)
        drawText("wifi", bar.x + bar.width - 120, bar.center.y,
                 size: 11, color: theme.ink, align: .right, .middle)

        // The line down to the enlargement, so the two are one thing.
        stroke(theme.accent)
        strokeWeight(1)
        drawLine(Vector2(strip.center.x, strip.y + strip.height + 6), Vector2(strip.center.x, 150))
        drawLine(Vector2(strip.center.x, 150), Vector2(330, 150))
        drawLine(Vector2(330, 150), Vector2(330, 186))
        noStroke()
        drawText("56 points of menu bar, at the size it really is",
                 bar.x, bar.y + bar.height + 12, size: 12, color: theme.muted, align: .left, .top)
    }

    // MARK: The same strip, enlarged

    func enlarged() {
        let theme = self.theme
        let scale = 5.0
        let box = Rectangle(x: 330 - stripWidth * scale / 2, y: 186,
                            width: stripWidth * scale, height: stripHeight * scale)
        pulse(in: box)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(box)

        // The canvas the sketch draws into is the strip's own points.
        stroke(theme.accent)
        strokeWeight(1.5)
        drawLine(Vector2(box.center.x, box.y), Vector2(box.center.x, box.y + box.height))
        noStroke()
        drawText("width / 2", box.center.x + 8, box.y + 8,
                 size: 12, color: theme.accent, align: .left, .top)

        fill(theme.accent)
        drawCircle(box.x, box.y, 4)
        drawText("0, 0", box.x + 8, box.y - 18, size: 12, color: theme.accent, align: .left, .top)

        drawText("width 56", box.center.x, box.y + box.height + 10,
                 size: 12, color: theme.ink, align: .center, .top)
        withState {
            translate(box.x - 14, box.center.y)
            rotate(-.pi / 2)
            drawText("height 22", 0, 0, size: 12, color: theme.ink, align: .center, .bottom)
        }

        drawText("Everything this guide taught still works. There is simply less room.",
                 40, 350, size: 13, color: theme.ink, align: .left, .top)
        drawText("The sketch sees a canvas of the strip's own points, so width / 2 is still the middle.",
                 40, 374, size: 12, color: theme.muted, align: .left, .top)
    }

    /// The piece itself: a line that moves, which is all a strip has room for.
    func pulse(in box: Rectangle) {
        fill(Color(hex: 0x14161A))
        drawRect(box)
        stroke(Color(hex: 0x5AC8F5))
        strokeWeight(max(1, box.height / 14))
        noFill()
        let points = (0 ... 56).map { step -> Vector2 in
            let t = Double(step) / 56
            let wave = sin(t * .pi * 4) * exp(-pow((t - 0.5) * 3.4, 2))
            return Vector2(box.x + box.width * t, box.center.y - wave * box.height * 0.34)
        }
        drawPolyline(points)
        noStroke()
    }

    // MARK: The two things to know

    func notes() {
        let theme = self.theme
        card(at: Rectangle(x: 556, y: 186, width: 284, height: 88),
             title: "30 frames a second") { box in
            drawText("a rate a surface that never goes", box.x + 16, box.y + 34,
                     size: 12, color: theme.ink, align: .left, .top)
            drawText("away can afford", box.x + 16, box.y + 52,
                     size: 12, color: theme.ink, align: .left, .top)
        }

        card(at: Rectangle(x: 556, y: 290, width: 284, height: 104),
             title: "a click opens the menu") { box in
            let menu = Rectangle(x: box.x + 16, y: box.y + 32, width: 150, height: 56)
            fill(theme.paper)
            drawRect(menu, cornerRadius: 7)
            stroke(theme.border)
            strokeWeight(1)
            noFill()
            drawRect(menu, cornerRadius: 7)
            noStroke()
            drawText("About Pulse", menu.x + 12, menu.y + 10,
                     size: 12, color: theme.muted, align: .left, .top)
            drawText("Quit", menu.x + 12, menu.y + 32,
                     size: 12, color: theme.ink, align: .left, .top)
            drawText("nothing in the", box.x + 180, box.y + 50,
                     size: 12, color: theme.muted, align: .left, .middle)
            drawText("Dock: there is", box.x + 180, box.y + 66,
                     size: 12, color: theme.muted, align: .left, .middle)
            drawText("no window", box.x + 180, box.y + 82,
                     size: 12, color: theme.muted, align: .left, .middle)
        }
    }

    func card(at box: Rectangle, title: String, _ body: (Rectangle) -> Void) {
        let theme = self.theme
        fill(theme.card)
        drawRect(box, cornerRadius: 8)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(box, cornerRadius: 8)
        noStroke()
        drawText(title, box.x + 16, box.y + 12, size: 12, color: theme.accent, align: .left, .top)
        body(box)
    }
}
