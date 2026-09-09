import Ollin

/// **Drawing with a pen.**
///
/// A tablet says more about a stylus than where it is. How hard it is pressed
/// arrives as `pressure`, which a Force Touch trackpad sends too; the rest is
/// `pen`: how far it leans, how far its barrel is turned, whether the end on
/// the tablet is the eraser, and whether it is over the tablet at all.
///
/// This is a nib that reads all of it. The mark is a chisel, laid across the
/// direction the pen leans, so turning your hand turns the stroke from thick to
/// thin the way a broad-edged pen does. `pressure` sets how wide, and the
/// eraser end takes ink away. With no tablet, the nib holds a fixed angle and
/// the width follows how fast you draw, so the sketch still works under a
/// mouse; the panel says which of the two you are getting. Space clears the
/// page.
@main
final class Pen: Sketch {

    @Param("Nib", 6 ... 60, icon: "pencil.tip", group: "Pen") var nib = 26.0
    @Param("Angle", 0 ... 3.14, icon: "angle", group: "Pen") var fixedAngle = 0.8
    @Param("Ink", icon: "drop.fill", group: "Pen") var ink = Color(hex: 0x171A22)
    @Param("Paper", icon: "doc.plaintext", group: "Pen") var paper = Color(hex: 0xF3EEE3)
    @Param(icon: "eye", group: "View") var readout = true

    override var canvasSize: CanvasSize { .square(900) }
    private var previous: Vector2? = nil

    override func setup() {
        noClear()          // the page keeps what is drawn on it, the way paper does
        background(paper)
    }

    override func draw() {
        if frameCount <= 1 { background(paper) }
        drawStroke()
        if readout { drawPanel() }
    }

    override func mousePressed() { previous = nil }
    override func mouseReleased() { previous = nil }

    override func keyPressed() {
        // A clean sheet, since a page that only fills up is no use.
        if key == " " { background(paper) }
    }

    /// One step of the nib: a chisel laid across the lean, from the last point
    /// to this one, as a quad so a broad edge stays broad however it turns.
    private func drawStroke() {
        guard mouseIsPressed else { previous = mouse; return }
        let here = mouse
        defer { previous = here }
        guard let from = previous else { return }

        // The nib's angle: across the lean when a pen is on the tablet, and the
        // fixed angle of an italic nib otherwise.
        let leaning = pen.tiltIsAvailable && pen.tilt.length > 0.02
        let angle = leaning ? atan2(pen.tilt.y, pen.tilt.x) + .pi / 2 : fixedAngle
        // How wide: the press when the device measures one, and how slowly the
        // hand moved when it does not. A pen laid flat draws wider, the way a
        // brush pressed onto its side does.
        let speed = min((here - from).length / 40, 1)
        let force = pressureIsAvailable ? pressure : 1 - speed * 0.7
        let width = nib * (0.18 + 0.82 * force) * (leaning ? 0.6 + 0.6 * pen.tilt.length : 1)
        let across = Vector2(cos(angle), sin(angle)) * (width / 2)

        noStroke()
        fill(pen.isEraser ? paper : ink)
        drawShape { path in
            path.move(to: from + across)
            path.line(to: here + across)
            path.line(to: here - across)
            path.line(to: from - across)
            path.close()
        }
    }

    /// What the tablet is saying, so a hand at the desk can see it move.
    private func drawPanel() {
        let panel = Rectangle(x: 24, y: 24, width: 330, height: 132)
        noStroke()
        fill(paper)
        drawRect(panel)
        fill(ink.withAlpha(0.5))
        textSize(15)
        textAlign(.left, .top)
        let lean = pen.tiltIsAvailable
            ? String(format: "lean %.2f, %.2f   turn %.0f°",
                     pen.tilt.x, pen.tilt.y, pen.twist * 180 / .pi)
            : "lean: no tablet has spoken"
        let press = pressureIsAvailable
            ? String(format: "press %.2f (measured)", pressure)
            : String(format: "press %.2f (a button, not a force)", pressure)
        let lines = [lean, press,
                     pen.isNearby ? "the pen is over the tablet" : "no pen in range",
                     pen.isEraser ? "the eraser end is down" : "the tip end is down"]
        for (index, line) in lines.enumerated() {
            drawText(line, panel.x + 16, panel.y + 16 + Double(index) * 26)
        }
    }
}
