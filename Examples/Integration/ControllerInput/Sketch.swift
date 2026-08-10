import Ollin
import OllinController

/// A game controller as a drawing instrument.
///
/// The left stick steers a pen and the pen leaves ink, so the piece is however
/// you moved your thumb. The right trigger sets how heavy the line is, the face
/// buttons change color, the shoulders spin the pen's own heading, and the right
/// stick blows the ink sideways like wind. Pressing the menu button clears the
/// page.
///
/// Two of these only work on some hardware, which is the point of showing them:
/// a PlayStation or Switch controller reports motion, so tilting it tips the
/// whole canvas and the ink runs downhill, and a PlayStation controller has a
/// touchpad, so sliding a finger across it drags the color. An Xbox controller
/// has neither, and the sketch simply does not offer them rather than pretending.
///
/// With nothing plugged in, everything reads centered and nothing happens, so the
/// sketch says as much on the canvas and waits. Turn `map` on to see every stick,
/// trigger and button as it is read, which is the quickest way to tell whether a
/// controller is talking to the machine at all.
@main
final class ControllerInputExample: Sketch {

    @Param(icon: "gamecontroller") var map = false
    @Param(0.5 ... 8, icon: "figure.walk") var speed = 4.0
    @Param(icon: "gyroscope") var useMotion = true

    private var pen = Vector2.zero
    private var heading = 0.0
    private var ink = Color.black
    private var greeting = ""
    private var greetingFrames = 0

    private let palette: [ControllerButton: Color] = [
        .a: Color(hex: 0x1D3557), .b: Color(hex: 0xE63946),
        .x: Color(hex: 0x457B9D), .y: Color(hex: 0xF4A261),
    ]

    override var canvasSize: CanvasSize { .square(1080) }

    override func setup() {
        pen = center
        ink = palette[.a] ?? .black
        // The sensors cost battery, so they stay off until a sketch asks.
        controllerMotion(true)
        // Ink piles up frame after frame instead of being wiped.
        noClear()
        background(Color(white: 0.97))
    }

    override func draw() {
        let pad = controller

        // Arriving and leaving are events, so they are worth catching rather
        // than polling: this fires on exactly one frame.
        if pad.didConnect { greet("\(pad.name ?? "controller") connected") }
        if pad.didDisconnect { greet("controller disconnected") }

        if pad.wasPressed(.menu) { clearPage() }
        for (button, color) in palette where pad.wasPressed(button) { ink = color }

        move(pad)
        drawInk(pad)

        // Everything below is chrome, so it goes on top of a fresh coat rather
        // than into the ink.
        if map { drawMap(pad) }
        if !pad.isConnected { drawWaiting(pad) }
        drawGreeting()
    }

    // MARK: - The pen

    private func move(_ pad: Controller) {
        // The stick reads in canvas terms already: pushing up gives a negative
        // y, which is up the screen, so this needs no sign of its own.
        var step = pad.leftStick * speed

        // Wind, off the other stick.
        step += pad.rightStick * (speed * 0.4)

        // Tilting the controller tips the page, on hardware that reports it.
        if useMotion && pad.hasMotion {
            step += Vector2(pad.gravity.x, -pad.gravity.y) * speed * 0.6
        }

        heading += (pad.isDown(.rightShoulder) ? 0.06 : 0)
            - (pad.isDown(.leftShoulder) ? 0.06 : 0)
        step = step.rotated(by: heading)

        pen += step
        pen = Vector2(pen.x.wrapped(in: 0 ... width), pen.y.wrapped(in: 0 ... height))
    }

    private func drawInk(_ pad: Controller) {
        // The trigger is a level, not a switch, so a light pull is a fine line.
        let weight = 1 + pad.rightTrigger * 28
        guard pad.leftStick.length > 0 || pad.rightStick.length > 0 || pad.hasMotion else { return }

        // A finger on the touchpad shifts the hue, on a controller that has one.
        var color = ink
        if pad.hasTouchpad && pad.isTouching {
            color = Color.mix(ink, Color(hex: 0x2A9D8F), t: (pad.touch.x + 1) / 2, in: .oklab)
        }

        // The left trigger lifts ink back off the page instead of laying it on.
        if pad.leftTrigger > 0 {
            fill(Color(white: 0.97).withAlpha(pad.leftTrigger * 0.25))
            noStroke()
            drawCircle(center: pen, radius: weight * 2)
            return
        }

        stroke(color.withAlpha(0.85))
        strokeWeight(weight)
        strokeCap(.round)
        drawPoint(pen)
    }

    private func clearPage() {
        noStroke()
        fill(Color(white: 0.97))
        drawRect(corner: .zero, width: width, height: height)
        greet("cleared")
    }

    // MARK: - Saying what is happening

    private func greet(_ message: String) {
        greeting = message
        greetingFrames = 90
    }

    private func drawGreeting() {
        guard greetingFrames > 0 else { return }
        greetingFrames -= 1
        let fade = min(Double(greetingFrames) / 30, 1)
        fill(Color(white: 0.1).withAlpha(fade))
        textSize(22)
        textAlign(.center)
        drawText(greeting, center.x, height - 60)
    }

    private func drawWaiting(_ pad: Controller) {
        // An export has no live input, and says so; an empty slot is not a
        // fault and says nothing, so there is a reason to show only sometimes.
        let message = pad.unavailableReason
            ?? "plug in a game controller, or pair one in System Settings"
        drawStatus(message, style: .info)
    }

    // MARK: - The map

    private func drawMap(_ pad: Controller) {
        withState {
            translate(40, 40)
            noStroke()
            fill(Color(white: 1, alpha: 0.88))
            drawRect(corner: .zero, width: 320, height: 250, cornerRadius: 14)

            fill(Color(white: 0.1))
            textSize(15)
            textAlign(.left)
            drawText(pad.name ?? "nothing attached", 18, 32)

            stick(pad.leftStick, at: Vector2(70, 110), label: "left")
            stick(pad.rightStick, at: Vector2(180, 110), label: "right")
            bar(pad.leftTrigger, at: Vector2(250, 70), label: "LT")
            bar(pad.rightTrigger, at: Vector2(285, 70), label: "RT")

            var x = 18.0
            for button in ControllerButton.allCases {
                fill(pad.isDown(button) ? Color(hex: 0xE63946) : Color(white: 0.85))
                drawCircle(center: Vector2(x, 200), radius: 6)
                x += 16
                if x > 300 { x = 18 }
            }

            fill(Color(white: 0.35))
            textSize(12)
            let motion = pad.hasMotion
                ? "tilt \(String(format: "%.2f, %.2f", pad.gravity.x, pad.gravity.y))"
                : "no motion on this controller"
            drawText(motion, 18, 228)
        }
    }

    private func stick(_ value: Vector2, at origin: Vector2, label: String) {
        noFill()
        stroke(Color(white: 0.8))
        strokeWeight(2)
        drawCircle(center: origin, radius: 34)
        noStroke()
        fill(Color(hex: 0x1D3557))
        drawCircle(center: origin + value * 30, radius: 7)
        fill(Color(white: 0.45))
        textSize(11)
        textAlign(.center)
        drawText(label, origin.x, origin.y + 52)
        textAlign(.left)
    }

    private func bar(_ value: Double, at origin: Vector2, label: String) {
        noStroke()
        fill(Color(white: 0.85))
        drawRect(corner: origin, width: 20, height: 80)
        fill(Color(hex: 0x457B9D))
        drawRect(corner: origin + Vector2(0, 80 * (1 - value)), width: 20, height: 80 * value)
        fill(Color(white: 0.45))
        textSize(11)
        drawText(label, origin.x, origin.y + 96)
    }
}

private extension Double {
    /// Keep the pen on the page by bringing it round the other side.
    func wrapped(in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return range.lowerBound }
        var value = self
        while value < range.lowerBound { value += span }
        while value > range.upperBound { value -= span }
        return value
    }
}
