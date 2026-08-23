import Ollin

/// A knob does not have to hold one number. A point holds two, a color holds
/// four, a pair of ends holds two more. Each part takes its own rule:
/// `drive($eye, x: "…", y: "…")`.
///
/// The frame below breathes because its `width` and `height` are rules, while
/// its `x` and `y` are left alone: a part with no rule stays where the hand put
/// it. The dot reads the frame it sits in, part by part, and the ink is three
/// rules of its own. The listing under the picture prints every rule beside
/// what its part holds this frame.
///
/// See Docs/Helpers/Formula.md.
@main
final class FormulaParts: Sketch {
    @Param(x: 0...1080, y: 0...1080, width: 40...900, height: 40...900)
    var frame = Rectangle(x: 190, y: 120, width: 700, height: 420)
    @Param(x: 0...1080, y: 0...1080) var eye = Vector2(540, 330)
    @Param var ink = Color(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
    @Param(in: 0...1) var band = 0.2...0.8

    /// The parts in the order the listing shows them, knob by knob.
    static let shown = [("frame", ["width", "height"]),
                        ("eye", ["x", "y"]),
                        ("ink", ["red", "green", "blue"]),
                        ("band", ["lower", "upper"])]

    override func setup() {
        drive($frame, width: "620 + sin(time * tau / 7) * 220",
                      height: "360 + cos(time * tau / 5) * 140")
        drive($eye, x: "frame.x + frame.width * (0.5 + sin(time * tau / 4) * 0.42)",
                    y: "frame.y + frame.height * (0.5 + cos(time * tau / 6) * 0.42)")
        drive($ink, red: "0.35 + sin(time * tau / 9) * 0.3",
                    green: "0.28 + sin(time * tau / 11) * 0.22",
                    blue: "0.6 + sin(time * tau / 7) * 0.25")
        drive($band, lower: "0.1 + sin(time * tau / 8) * 0.08",
                     upper: "0.6 + sin(time * tau / 6) * 0.35")
    }

    override func draw() {
        background(.white)
        drawFrame()
        drawEye()
        drawListing()
    }

    // MARK: The picture

    /// The frame, and the part of it the band names, drawn as a filled slab.
    private func drawFrame() {
        let top = frame.y + frame.height * band.lowerBound
        let deep = frame.height * (band.upperBound - band.lowerBound)
        noStroke()
        fill(ink.withAlpha(0.14))
        drawRect(frame.x, top, frame.width, deep)

        noFill()
        stroke(Color(white: 0.75))
        strokeWeight(1.5 * scale)
        drawRect(frame)
    }

    /// The dot, wherever the two rules put it inside the frame.
    private func drawEye() {
        noFill()
        stroke(ink)
        strokeWeight(2 * scale)
        drawLine(frame.x, eye.y, frame.x + frame.width, eye.y)
        drawLine(eye.x, frame.y, eye.x, frame.y + frame.height)

        noStroke()
        fill(ink)
        drawCircle(center: eye, radius: 16 * scale)
    }

    // MARK: The listing

    /// Read the tracks back and print the rule driving each part, so the
    /// picture says what made it.
    private func drawListing() {
        var top = 660.0
        textSize(19 * scale)
        for (name, parts) in Self.shown {
            guard let track = automation?.track(named: name) else { continue }
            for part in parts {
                guard let rule = track.parts[part] else { continue }
                noStroke()
                fill(Color(white: 0.55))
                textAlign(.right, .middle)
                drawText("\(name).\(part)", 250, top)

                fill(Color(white: 0.2))
                textAlign(.left, .middle)
                drawText(rule.source, 274, top)

                fill(Color(white: 0.6))
                textAlign(.right, .middle)
                drawText(reading(of: name, part), width - 90, top)
                top += 33
            }
            top += 8
        }
    }

    /// What one part holds this frame, rounded to something readable.
    private func reading(of name: String, _ part: String) -> String {
        guard let track = automation?.track(named: name),
              track.parts[part] != nil else { return "" }
        let value: Double
        switch (name, part) {
        case ("frame", "width"): value = frame.width
        case ("frame", "height"): value = frame.height
        case ("eye", "x"): value = eye.x
        case ("eye", "y"): value = eye.y
        case ("ink", "red"): value = ink.red
        case ("ink", "green"): value = ink.green
        case ("ink", "blue"): value = ink.blue
        case ("band", "lower"): value = band.lowerBound
        case ("band", "upper"): value = band.upperBound
        default: return ""
        }
        return String(format: value < 10 ? "%.3f" : "%.1f", value)
    }
}
