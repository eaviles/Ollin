import Ollin

/// `strokeProfile` shapes a mark by *where you are* along the path. Stroke
/// dynamics shapes it by *how you got there*: a `StrokeMark` measures how fast
/// the pointer is moving and how hard it is pressed, and hands both to a
/// `StrokeDynamics` that answers with a width and an opacity for that point.
///
/// Drag to paint. Fast strokes come out thin and faint, slow ones full and dark,
/// and on a Force Touch trackpad a heavier press swells the mark under your
/// finger. The three marks along the top are recorded the same way, from a
/// synthetic hand that speeds up through the middle of each curve, so they show
/// the mapping without anyone touching the mouse.
///
/// `1` drives from speed, `2` from pressure, `3` from both. `c` clears.
@main
final class Brushwork: Sketch {
    enum Driver: String { case speed, pressure, both }

    /// The mark in progress. Live-recorded and redrawn every frame, so it grows
    /// under the pointer instead of appearing when the drag ends.
    var mark = StrokeMark()
    /// Everything already finished. A mark is a value, so keeping one is a copy.
    var strokes: [StrokeMark] = []
    var driver: Driver = .speed

    override func setup() {
        strokes = demonstrations()
    }

    override func draw() {
        background(Color(white: 0.07))
        strokeCap(.round)
        strokeJoin(.round)

        for (i, stroke) in strokes.enumerated() {
            withState {
                self.stroke(ink(i))
                strokeWeight(30 * scale)
                drawMark(stroke)
            }
            if i < demoLabels.count, let box = stroke.bounds {
                label(demoLabels[i], at: Vector2(box.x, box.y - 34 * scale))
            }
        }

        if mouseIsPressed { record(into: &mark) }
        withState {
            stroke(ink(strokes.count))
            strokeWeight(30 * scale)
            drawMark(mark)
        }

        legend()
    }

    override func mousePressed() {
        // The driver is chosen per stroke, because whether the device can measure
        // pressure is only known once it has sent some. A plain mouse reports full
        // force throughout, so a pressure-driven mark on one is a flat mark.
        mark = StrokeMark(dynamics(for: driver), smoothing: 0.55)
    }

    override func mouseReleased() {
        if !mark.isEmpty { strokes.append(mark) }
        mark.clear()
    }

    override func keyPressed() {
        switch key {
        case "1": driver = .speed
        case "2": driver = .pressure
        case "3": driver = .both
        case "c": strokes = []; mark.clear()
        default: break
        }
    }

    /// The three named drivers. `.speed` works on any device; `.pressure` needs a
    /// trackpad or tablet that measures it; `.both` reads width from the press and
    /// opacity from the pace, which is the pair a real brush gives you at once.
    func dynamics(for driver: Driver) -> StrokeDynamics {
        let reference = 1200 * scale
        switch driver {
        case .speed:
            return StrokeDynamics(width: .speed(reference: reference, fast: 0.12),
                                  opacity: .speed(reference: reference, fast: 0.35))
        case .pressure:
            return StrokeDynamics(width: .pressure(light: 0.1),
                                  opacity: .pressure(light: 0.3))
        case .both:
            // The pair a real brush gives you at once: the press decides how much
            // of the tip is down, the pace decides how much ink it leaves.
            return StrokeDynamics(width: .pressure(light: 0.1),
                                  opacity: .speed(reference: reference, fast: 0.35))
        }
    }

    /// Three marks recorded from a hand that is not there: one curve walked at a
    /// fixed frame rate but a changing pace, nearly still at the ends and flicking
    /// through the middle. Each row shows one axis of the same measurement.
    func demonstrations() -> [StrokeMark] {
        let reference = 1200 * scale
        let recipes = [
            StrokeDynamics(width: .speed(reference: reference, fast: 0.08)),
            StrokeDynamics(opacity: .speed(reference: reference, fast: 0.12)),
            StrokeDynamics(width: .speed(reference: reference, fast: 0.08),
                           opacity: .speed(reference: reference, fast: 0.12)),
        ]
        return recipes.enumerated().map { i, dynamics in
            var mark = StrokeMark(dynamics, smoothing: 0.4)
            let y = height * (0.17 + 0.15 * Double(i))
            let steps = 300
            for step in 0...steps {
                // Easing the parameter, not the position, is what varies the pace:
                // the curve is the same either way, but the hand covers its middle
                // far faster than its ends. The step is timed so the quickest part
                // reaches `reference`, where the dynamics bottom out.
                let u = smootherstep(Double(step) / Double(steps))
                let x = lerp(width * 0.1, width * 0.9, u)
                let wobble = sin(u * .tau * 1.5) * height * 0.035
                mark.record(Vector2(x, y + wobble), deltaTime: 1.0 / 240)
            }
            return mark
        }
    }

    /// The smoothstep one degree smoother: flat enough at both ends that the
    /// synthetic hand really does start and finish at a standstill.
    func smootherstep(_ t: Double) -> Double {
        t * t * t * (t * (t * 6 - 15) + 10)
    }

    let demoLabels = ["speed drives width", "speed drives opacity", "speed drives both"]

    func ink(_ i: Int) -> Color {
        Colormap.turbo.color(at: 0.16 + 0.13 * Double(i % 6))
    }

    func label(_ text: String, at p: Vector2) {
        withState {
            noStroke(); fill(Color(white: 0.55)); textAlign(.left, .baseline)
            textSize(20 * scale)
            drawText(text, p.x, p.y)
        }
    }

    func legend() {
        let felt = pressureIsAvailable ? "pressure available" : "no pressure on this device"
        drawCaption("drag to paint  ·  \(driver.rawValue)  ·  \(felt)  ·  1 2 3 to switch, c to clear")
    }
}
