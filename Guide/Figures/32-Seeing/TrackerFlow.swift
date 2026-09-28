// figure: frame=0 themed
//
// Guide diagram (Chapter 32): the tracker pipeline. A camera produces frames;
// a tracker analyzes them on a background thread and publishes typed results;
// the sketch reads those results in draw() and maps them into the rectangle
// the frame was drawn in. The inset shows the mapping: results arrive
// normalized with a lower-left origin, the canvas is pixels from the top left.
import Ollin
import OllinDiagram

final class TrackerFlow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        box(x: 15, y: 74, w: 214, h: 110, title: "Camera()",
            sub: ["or a video,", "or your own feed"])
        box(x: 333, y: 74, w: 214, h: 110, title: "FaceTracker(camera)",
            sub: ["analyzes frames", "in the background"])
        box(x: 651, y: 74, w: 214, h: 110, title: "faces.faces",
            sub: ["typed results,", "read in draw()"])

        arrow(from: Vector2(229, 129), to: Vector2(331, 129))
        arrow(from: Vector2(547, 129), to: Vector2(649, 129))

        noStroke()
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText("frames", 281, 102)
        drawText("Face values", 599, 102)

        // The inset: normalized results land on the drawn frame's rectangle.
        normalizedPanel(x: 90, y: 260)
        canvasPanel(x: 570, y: 260)
        arrow(from: Vector2(335, 350), to: Vector2(545, 350))

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("face.bounds(in: rect)", 440, 316)
        drawText("draw the frame, keep its rectangle, map every result into it",
                 width / 2, 505)
    }

    func normalizedPanel(x: Double, y: Double) {
        let w = 220.0, h = 165.0
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, w, h)
        noStroke()
        fill(accent)
        drawCircle(x + 0.62 * w, y + h - 0.7 * h, 6)          // (0.62, 0.7), y up
        fill(ink)
        textSize(15)
        textAlign(.left, .top)
        drawText("(0, 0)", x + 4, y + h + 6)
        textAlign(.right, .top)
        drawText("(1, 1)", x + w - 2, y - 24)
        fill(soft)
        textAlign(.center, .top)
        drawText("what a tracker reports:", x + w / 2, y + h + 28)
        drawText("0…1, origin bottom left, y up", x + w / 2, y + h + 48)
    }

    func canvasPanel(x: Double, y: Double) {
        let w = 220.0, h = 165.0
        // The canvas, with a letterboxed frame rectangle inside it.
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, w, h)
        let rect = Rectangle(x: x + 24, y: y + 22, width: w - 48, height: h - 44)
        stroke(ink)
        drawRect(rect)
        noStroke()
        fill(accent)
        drawCircle(rect.x + 0.62 * rect.width, rect.y + 0.3 * rect.height, 6)
        fill(ink)
        textSize(15)
        textAlign(.left, .top)
        drawText("(0, 0)", x + 4, y - 24)
        fill(soft)
        textAlign(.center, .top)
        drawText("where you drew the frame:", x + w / 2, y + h + 28)
        drawText("pixels, origin top left, y down", x + w / 2, y + h + 48)
    }

    func box(x: Double, y: Double, w: Double, h: Double, title: String, sub: [String]) {
        fill(darkTheme ? Color(hex: 0x2A2724) : .white)
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, w, h, cornerRadius: 10)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .bottom)
        drawText(title, x + w / 2, y + 48)
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        for (i, line) in sub.enumerated() {
            drawText(line, x + w / 2, y + 56 + Double(i) * 19)
        }
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
