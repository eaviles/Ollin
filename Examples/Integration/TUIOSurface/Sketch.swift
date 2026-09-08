import Ollin
import OllinOSC

/// A tangible surface on screen: touches, tagged pieces, and shapes arriving as
/// TUIO, the protocol marker tables and touch walls speak.
///
/// Like the OSC example, it runs both ends so it works on any machine with no
/// hardware: with `simulate` on, a stand-in tracker sends real TUIO frames to
/// `127.0.0.1` and everything drawn here comes back off the wire. Turn
/// `simulate` off and point a real tracker at this Mac on port 3333 to drive it
/// instead. Marker tables, touch walls, and the phone apps that send finger
/// positions all speak this.
@main
final class TUIOSurface: Sketch {

    @Param var simulate = true

    let surface = TUIOReceiver()
    var tracker: OSCSender!
    var frame = 0
    let palette = CosinePalette.neon

    override func setup() {
        try? surface.start()
        tracker = OSCSender(host: "127.0.0.1", port: TUIOReceiver.defaultPort)
    }

    override func draw() {
        if simulate { sendAFrame() }

        background(Color(white: 0.07))
        drawTheSurfaceEdge()

        for touch in surface.cursors { draw(touch) }
        for piece in surface.objects { draw(piece) }
        for shape in surface.blobs { draw(shape) }

        drawTheStatusLine()
    }

    // MARK: What the tracker reports

    private func draw(_ touch: TUIOCursor) {
        let at = touch.position(in: bounds)
        // Ids come in a run, so the color is spread by a stride rather than
        // taken straight from the number, or neighboring touches read alike.
        let tint = palette.color(at: (Double(touch.id) * 0.37).truncatingRemainder(dividingBy: 1))

        // The whisker is the touch's own velocity, a quarter second ahead.
        strokeWeight(3 * scale)
        stroke(tint.withAlpha(0.5))
        let ahead = Vector2(touch.velocity.x * width, touch.velocity.y * height) * 0.25
        drawLine(at, at + ahead)

        noStroke()
        fill(tint.withAlpha(0.18))
        drawCircle(center: at, radius: 46 * scale)
        fill(tint)
        drawCircle(center: at, radius: 14 * scale)

        fill(Color(white: 0.85))
        textSize(18 * scale)
        drawText("\(touch.id)", at: at + Vector2(24, -24) * scale)
    }

    private func draw(_ piece: TUIOObject) {
        withState {
            translate(piece.position(in: bounds))
            rotate(piece.angle)
            noFill()
            stroke(Color(white: 0.95))
            strokeWeight(4 * scale)
            drawRect(center: .zero, width: 130 * scale, height: 130 * scale)
            // One corner marked, so the turn is readable at a glance.
            fill(Color(white: 0.95))
            noStroke()
            drawCircle(center: Vector2(-52, -52) * scale, radius: 9 * scale)
            textSize(34 * scale)
            drawText("\(piece.symbol)", at: Vector2(-14, 12) * scale)
        }
    }

    private func draw(_ shape: TUIOBlob) {
        let box = shape.bounds(in: bounds)
        withState {
            translate(box.center)
            rotate(shape.angle)
            noStroke()
            fill(Color(white: 1, alpha: 0.14))
            drawEllipse(center: .zero, radiusX: box.width / 2, radiusY: box.height / 2)
        }
    }

    // MARK: The stand-in tracker

    /// Sends one surface frame the way a tracker would: a `set` for everything
    /// that moved, the `alive` list, then the frame number that commits them.
    private func sendAFrame() {
        frame += 1
        let touches = (0..<3).map { index -> (id: Int, point: Vector2) in
            let phase = time * 0.6 + Double(index) * 2.1
            return (id: 11 + index,
                    point: Vector2(0.5 + 0.34 * sin(phase), 0.5 + 0.34 * sin(phase * 1.37 + 0.8)))
        }
        var cursorFrame: [OSCMessage] = touches.map { touch in
            // Velocity in surface widths per second, which is what the whisker reads.
            let ahead = Vector2(0.34 * 0.6 * cos(time * 0.6 + Double(touch.id - 11) * 2.1),
                                0.34 * 0.6 * 1.37 * cos((time * 0.6 + Double(touch.id - 11) * 2.1) * 1.37 + 0.8))
            return OSCMessage("/tuio/2Dcur", .string("set"), .int(Int32(touch.id)),
                              .float(Float(touch.point.x)), .float(Float(touch.point.y)),
                              .float(Float(ahead.x)), .float(Float(ahead.y)), .float(0))
        }
        cursorFrame.append(OSCMessage("/tuio/2Dcur",
                                      arguments: [.string("alive")] + touches.map { .int(Int32($0.id)) }))
        cursorFrame.append(OSCMessage("/tuio/2Dcur", .string("fseq"), .int(Int32(frame))))
        tracker.send(OSCBundle(.immediate, messages: cursorFrame))

        let turn = time * 0.5
        tracker.send(OSCBundle(.immediate, messages: [
            OSCMessage("/tuio/2Dobj", .string("set"), .int(41), .int(7),
                       .float(Float(0.5 + 0.18 * cos(time * 0.35))),
                       .float(Float(0.5 + 0.18 * sin(time * 0.35))),
                       .float(Float(turn)), .float(0), .float(0), .float(0.5), .float(0), .float(0)),
            OSCMessage("/tuio/2Dobj", arguments: [.string("alive"), .int(41)]),
            OSCMessage("/tuio/2Dobj", .string("fseq"), .int(Int32(frame))),
        ]))

        let breath = 0.22 + 0.06 * sin(time * 1.1)
        tracker.send(OSCBundle(.immediate, messages: [
            OSCMessage("/tuio/2Dblb", .string("set"), .int(61),
                       .float(0.33), .float(0.4), .float(Float(sin(time * 0.2))),
                       .float(Float(breath)), .float(Float(breath * 0.6)),
                       .float(Float(breath * breath * 0.6)),
                       .float(0), .float(0), .float(0), .float(0), .float(0)),
            OSCMessage("/tuio/2Dblb", arguments: [.string("alive"), .int(61)]),
            OSCMessage("/tuio/2Dblb", .string("fseq"), .int(Int32(frame))),
        ]))
    }

    // MARK: Chrome

    private func drawTheSurfaceEdge() {
        noFill()
        stroke(Color(white: 0.22))
        strokeWeight(2 * scale)
        drawRect(corner: Vector2(1, 1) * scale, width: width - 2 * scale, height: height - 2 * scale)
    }

    private func drawTheStatusLine() {
        noStroke()
        fill(Color(white: 0.55))
        textSize(22 * scale)
        let heard = surface.framesReceived
        let line = heard == 0
            ? "listening for a tracker on port \(TUIOReceiver.defaultPort)"
            : [count(surface.cursors.count, "touch", "touches"),
               count(surface.objects.count, "piece", "pieces"),
               count(surface.blobs.count, "shape", "shapes")].joined(separator: ", ")
        drawText(line, 30 * scale, height - 36 * scale)
        drawText(surface.sourceName ?? "port \(TUIOReceiver.defaultPort)", 30 * scale, 46 * scale)
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) \(n == 1 ? one : many)"
    }
}
