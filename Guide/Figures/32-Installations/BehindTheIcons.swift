// figure: frame=0 themed
//
// Guide diagram (Chapter 32): a sketch as the desktop. On the left, what the
// screen looks like once it is running: the piece edge to edge, with the icons
// on it and a window over it, and a pointer that reaches both of those and
// never the piece. On the right, the three things worth knowing before leaving
// one up: one copy per display, the sparkle as the way out, and what it costs
// to draw all day. The point of the figure: the desktop stays a desktop.
import Ollin
import OllinDiagram

final class BehindTheIcons: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The piece's own colors stay put in both themes: it is depicted content,
    /// a drawing on a screen rather than part of the page.
    let deepBlue = Color(hex: 0x102840)
    let drift = Color(hex: 0x3E7CA6)
    let ember = Color(hex: 0xE4572E)

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()
        textFont(.system)

        drawText("The desktop becomes the piece, and stays a desktop.",
                 40, 26, size: 17, color: theme.ink, align: .left, .top)
        drawText("ollin new Drift --kind wallpaper", 40, 52,
                 size: 12, color: theme.accent, align: .left, .top)

        desktop()
        notes()
    }

    // MARK: The screen itself

    func desktop() {
        let theme = self.theme
        let screen = Rectangle(x: 40, y: 92, width: 480, height: 300)
        piece(in: screen, phase: 0)

        // The menu bar across the top, with the sparkle at its right end.
        fill(Color.black.withAlpha(0.3))
        drawRect(Rectangle(x: screen.x, y: screen.y, width: screen.width, height: 22))
        fill(Color.white.withAlpha(0.8))
        drawText("Drift", screen.x + 12, screen.y + 11, size: 11, align: .left, .middle)
        let sparkle = Vector2(screen.x + screen.width - 46, screen.y + 11)
        star(at: sparkle, radius: 6, color: .white)
        drawText("9:41", screen.x + screen.width - 12, screen.y + 11,
                 size: 11, color: Color.white.withAlpha(0.8), align: .right, .middle)

        // Icons sit on it, exactly where they sat before.
        for index in 0 ..< 3 {
            let box = Rectangle(x: screen.x + screen.width - 74,
                                y: screen.y + 42 + Double(index) * 62, width: 44, height: 36)
            fill(Color.white.withAlpha(0.85))
            drawRect(box, cornerRadius: 5)
            fill(Color.white.withAlpha(0.75))
            drawText("file \(index + 1)", box.center.x, box.y + box.height + 9,
                     size: 9, align: .center, .top)
        }

        // And a window stacks over it.
        let window = Rectangle(x: screen.x + 54, y: screen.y + 84, width: 250, height: 150)
        fill(Color.black.withAlpha(0.35))
        drawRect(Rectangle(x: window.x + 5, y: window.y + 6, width: window.width, height: window.height),
                 cornerRadius: 9)
        fill(darkTheme ? Color(hex: 0x1E242C) : Color(hex: 0xF4F5F7))
        drawRect(window, cornerRadius: 9)
        fill(darkTheme ? Color.white.withAlpha(0.12) : Color.black.withAlpha(0.07))
        drawRect(Rectangle(x: window.x, y: window.y, width: window.width, height: 24), cornerRadius: 9)
        for dot in 0 ..< 3 {
            fill(Color.black.withAlpha(0.25))
            drawCircle(window.x + 16 + Double(dot) * 14, window.y + 12, 4)
        }
        fill(theme.ink(0.35))
        for line in 0 ..< 4 {
            drawRect(Rectangle(x: window.x + 16, y: window.y + 42 + Double(line) * 18,
                               width: Double(190 - line * 28), height: 7), cornerRadius: 3)
        }

        // The pointer, landing on the window the way it always did.
        pointer(at: Vector2(window.x + 150, window.y + 96))

        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(screen)
        noStroke()

        drawText("a click reaches the window and the icons, never the piece",
                 screen.x, screen.y + screen.height + 14,
                 size: 13, color: theme.ink, align: .left, .top)
        drawText("the sketch takes no input at all: no mouseX, no key",
                 screen.x, screen.y + screen.height + 36,
                 size: 12, color: theme.muted, align: .left, .top)
    }

    /// The piece, as it draws behind everything: quiet, slow, edge to edge.
    func piece(in box: Rectangle, phase: Double) {
        fill(deepBlue)
        drawRect(box)
        for index in 0 ..< 22 {
            let t = Double(index) / 21
            let y = box.y + box.height * (0.18 + 0.7 * t)
            let wobble = sin(t * 5.4 + phase) * box.height * 0.06
            fill(drift.withAlpha(0.14 + 0.5 * t))
            drawRect(Rectangle(x: box.x, y: y + wobble, width: box.width, height: 2.4))
        }
        fill(ember.withAlpha(0.85))
        drawCircle(box.x + box.width * (0.24 + 0.1 * sin(phase)), box.y + box.height * 0.3,
                   box.height * 0.075)
    }

    // MARK: What to know before leaving one up

    func notes() {
        let theme = self.theme
        var y = 92.0

        y = note(at: y, title: "one copy per display, not in step", height: 118) { box in
            for display in 0 ..< 2 {
                let mini = Rectangle(x: box.x + 16 + Double(display) * 130, y: box.y + 34,
                                     width: 118, height: 66)
                piece(in: mini, phase: display == 0 ? 0 : 1.9)
                stroke(theme.border)
                strokeWeight(1)
                noFill()
                drawRect(mini)
                noStroke()
            }
        }

        y = note(at: y, title: "the way out", height: 106) { box in
            star(at: Vector2(box.x + 28, box.y + 44), radius: 8, color: theme.ink)
            let menu = Rectangle(x: box.x + 62, y: box.y + 32, width: 146, height: 56)
            fill(theme.card)
            drawRect(menu, cornerRadius: 7)
            stroke(theme.border)
            strokeWeight(1)
            noFill()
            drawRect(menu, cornerRadius: 7)
            noStroke()
            drawText("About Drift", menu.x + 12, menu.y + 10,
                     size: 12, color: theme.muted, align: .left, .top)
            drawText("Quit", menu.x + 12, menu.y + 32,
                     size: 12, color: theme.ink, align: .left, .top)
            drawText("in the", box.x + 28, box.y + 58, size: 10, color: theme.muted, align: .center, .top)
            drawText("menu bar", box.x + 28, box.y + 71, size: 10, color: theme.muted, align: .center, .top)
        }

        _ = note(at: y, title: "what it costs", height: 96) { box in
            drawText("It draws at the display's rate for as long as", box.x + 16, box.y + 32,
                     size: 12, color: theme.ink, align: .left, .top)
            drawText("the machine is up. A still piece calls", box.x + 16, box.y + 50,
                     size: 12, color: theme.ink, align: .left, .top)
            drawText("noLoop() and costs nothing at all.", box.x + 16, box.y + 68,
                     size: 12, color: theme.ink, align: .left, .top)
        }

        drawText("Add the built app to Login Items and it is the machine's wallpaper for good.",
                 40, 474, size: 12, color: theme.muted, align: .left, .top)
    }

    /// One titled card in the right column; answers the next card's top.
    func note(at y: Double, title: String, height: Double,
              _ body: (Rectangle) -> Void) -> Double {
        let theme = self.theme
        let box = Rectangle(x: 556, y: y, width: 284, height: height)
        fill(theme.card)
        drawRect(box, cornerRadius: 8)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(box, cornerRadius: 8)
        noStroke()
        drawText(title, box.x + 16, box.y + 12, size: 12, color: theme.accent, align: .left, .top)
        body(box)
        return y + height + 14
    }

    // MARK: Small marks

    /// The status item's sparkle, drawn as a four-pointed star.
    func star(at center: Vector2, radius: Double, color: Color) {
        fill(color)
        for turn in 0 ..< 2 {
            withState {
                translate(center)
                rotate(Double(turn) * .pi / 2)
                drawTriangle(Vector2(0, -radius), Vector2(-radius * 0.34, 0), Vector2(radius * 0.34, 0))
                drawTriangle(Vector2(0, radius), Vector2(-radius * 0.34, 0), Vector2(radius * 0.34, 0))
            }
        }
    }

    func pointer(at position: Vector2) {
        withState {
            translate(position)
            fill(.black)
            drawPolygon([Vector2(0, 0), Vector2(0, 19), Vector2(5, 14.5),
                         Vector2(8.5, 22), Vector2(12, 20), Vector2(8.5, 13),
                         Vector2(14, 12.5)])
            fill(.white)
            drawPolygon([Vector2(1.6, 3.4), Vector2(1.6, 15.6), Vector2(5, 12.4),
                         Vector2(8.6, 19.2), Vector2(9.8, 18.6), Vector2(6.2, 11.6),
                         Vector2(10.6, 11.4)])
        }
    }
}
