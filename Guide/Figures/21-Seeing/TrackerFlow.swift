// figure: frame=0
//
// Guide diagram (Chapter 21): the tracker pipeline. A camera produces frames;
// a tracker analyzes them on a background thread and publishes typed results;
// the sketch reads those results in draw() and maps them into the rectangle
// the frame was drawn in. The inset shows the mapping: results arrive
// normalized with a lower-left origin, the canvas is pixels from the top left.
import Ollin

final class TrackerFlow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        box(x: 45, y: 80, w: 200, h: 96, title: "Camera()",
            sub: "or a video, or your own feed")
        box(x: 340, y: 80, w: 200, h: 96, title: "FaceTracker(camera)",
            sub: "analyzes frames in the background")
        box(x: 635, y: 80, w: 200, h: 96, title: "faces.faces",
            sub: "typed results, read in draw()")

        arrow(from: Vector2(245, 128), to: Vector2(338, 128))
        arrow(from: Vector2(540, 128), to: Vector2(633, 128))

        noStroke()
        fill(soft)
        textSize(15)
        textAlign(.center, .top)
        drawText("frames", 292, 100)
        drawText("Face values", 587, 100)

        // The inset: normalized results land on the drawn frame's rectangle.
        normalizedPanel(x: 130, y: 260)
        canvasPanel(x: 500, y: 260)
        arrow(from: Vector2(390, 350), to: Vector2(488, 350))

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

    func box(x: Double, y: Double, w: Double, h: Double, title: String, sub: String) {
        fill(.white)
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, w, h, cornerRadius: 10)
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.center, .bottom)
        drawText(title, x + w / 2, y + h / 2 + 2)
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText(sub, x + w / 2, y + h / 2 + 8)
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
