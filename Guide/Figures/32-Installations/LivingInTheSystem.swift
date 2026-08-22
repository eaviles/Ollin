// figure: frame=1
//
// Guide diagram (Chapter 32): the shape of a screen saver. On the left the
// folder the script builds, with the one link that has to hold drawn across it:
// the name in the property list is the name in the code. On the right, what the
// sketch's own window mode decides once it is on a display that is not the shape
// of its canvas.
import Ollin

final class LivingInTheSystem: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let accent = Color(hex: 0xE4572E)
    let good = Color(hex: 0x2E7D5B)
    let rule = Color(hex: 0x2B2B2B, alpha: 0.18)
    let shade = Color(hex: 0x2B2B2B, alpha: 0.06)

    override func draw() {
        background(paper)
        bundle()
        display()
    }

    // MARK: The folder the script builds

    func bundle() {
        heading("Ripple.saver", at: Vector2(48, 40))

        // The three files that matter, as stacked cards.
        let plist = card(y: 76, title: "Contents/Info.plist",
                         lines: ["CFBundlePackageType   BNDL",
                                 "CFBundleExecutable    Ripple",
                                 "NSPrincipalClass      RippleSaverView"],
                         mark: 2)
        let binary = card(y: 200, title: "Contents/MacOS/Ripple",
                          lines: ["@objc(RippleSaverView)",
                                  "final class RippleSaverView: SketchSaverView",
                                  "    override func makeSketch() -> Sketch"],
                          mark: 0)
        _ = card(y: 324, title: "Contents/Resources/",
                 lines: ["Ollin_Ollin.bundle",
                         "the shaders and fonts the framework loads",
                         "beside the running program, which is not yours"],
                 mark: -1)

        // The link. It is the only thing joining the two files, and getting it
        // wrong is the failure that looks like nothing at all.
        let from = Vector2(plist.x + plist.width - 22, plist.y + plist.height - 16)
        let to = Vector2(binary.x + binary.width - 22, binary.y + 22)
        stroke(accent)
        strokeWeight(2)
        drawLine(Vector2(from.x, from.y), Vector2(from.x + 38, from.y))
        drawLine(Vector2(from.x + 38, from.y), Vector2(from.x + 38, to.y))
        drawLine(Vector2(from.x + 38, to.y), Vector2(to.x, to.y))
        arrowHead(at: to, pointingLeft: true)

        noStroke()
        fill(accent)
        textSize(12)
        textAlign(.left, .center)
        drawText("the same name,", from.x + 46, (from.y + to.y) / 2 - 9)
        drawText("or nothing shows", from.x + 46, (from.y + to.y) / 2 + 8)
    }

    /// One file, as a titled card with its lines under it. `mark` picks the line
    /// the link touches, or -1 for none.
    @discardableResult
    func card(y: Double, title: String, lines: [String], mark: Int) -> Rectangle {
        let box = Rectangle(x: 48, y: y, width: 356, height: 104)

        noStroke()
        fill(shade)
        drawRect(corner: box.corner, width: box.width, height: box.height)
        noFill()
        stroke(rule)
        strokeWeight(1)
        drawRect(corner: box.corner, width: box.width, height: box.height)

        noStroke()
        fill(ink)
        textSize(14)
        textAlign(.left, .top)
        drawText(title, box.x + 14, box.y + 12)

        textSize(12)
        for (index, line) in lines.enumerated() {
            fill(index == mark ? accent : soft)
            drawText(line, box.x + 14, box.y + 38 + Double(index) * 19)
        }
        return box
    }

    // MARK: What the sketch's window mode decides

    func display() {
        heading("on a display that is not its shape", at: Vector2(560, 40))

        screen(y: 88, title: ".resizable",
               note: "the canvas is the display",
               fills: true)
        screen(y: 250, title: "anything else",
               note: "its own proportions, centered",
               fills: false)

        fill(soft)
        textSize(12)
        textAlign(.left, .top)
        drawText("Neither one stretches the drawing.", 560, 412)
        drawText("A circle stays a circle either way.", 560, 431)
    }

    /// A wide screen with the drawing in it, either edge to edge or fitted.
    func screen(y: Double, title: String, note: String, fills: Bool) {
        let box = Rectangle(x: 560, y: y + 26, width: 280, height: 96)

        noStroke()
        fill(ink)
        textSize(14)
        textAlign(.left, .top)
        drawText(title, box.x, y)

        // The display itself is black, the way a screen saver leaves it.
        fill(Color(hex: 0x1B1B1B))
        drawRect(corner: box.corner, width: box.width, height: box.height)

        let drawn = fills
            ? box
            : Rectangle(x: box.x + (box.width - box.height) / 2, y: box.y,
                        width: box.height, height: box.height)
        fill(Color(hex: 0x25404F))
        drawRect(corner: drawn.corner, width: drawn.width, height: drawn.height)

        // One mark, so the shape of the drawing is readable rather than stated.
        fill(good)
        let radius = min(drawn.width, drawn.height) * 0.26
        drawCircle(drawn.x + drawn.width / 2, drawn.y + drawn.height / 2, radius)

        noStroke()
        fill(soft)
        textSize(12)
        textAlign(.left, .top)
        drawText(note, box.x, box.y + box.height + 8)
    }

    // MARK: Shared furniture

    func heading(_ text: String, at position: Vector2) {
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .top)
        drawText(text, position.x, position.y)
    }

    func arrowHead(at point: Vector2, pointingLeft: Bool) {
        let direction = pointingLeft ? -1.0 : 1.0
        noStroke()
        fill(accent)
        drawTriangle(point,
                     Vector2(point.x - direction * 9, point.y - 5),
                     Vector2(point.x - direction * 9, point.y + 5))
    }
}
