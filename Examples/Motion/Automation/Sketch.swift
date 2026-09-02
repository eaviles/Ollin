import Ollin

/// An `Automation` writes a sketch's parameters down over time: a value at one
/// moment, another later, and a curve carrying the first into the second.
/// Where `@Param` gives you a parameter to adjust, this moves it for you, so the
/// piece is directed rather than only tuned.
///
/// Four parameters are on tracks here, one per kind of value. The size and the
/// place travel along their curves; the color fades along its own; the fill
/// switch *steps*, because a switch has nothing between off and on. The lanes
/// under the stage are the automation drawing itself: the sketch reads its own
/// tracks back and plots them, with a playhead where the pass stands.
///
/// The clock is the sketch clock, so `--export-video` renders the piece
/// exactly as it plays here. See Docs/Core/Automation.md.
@main
final class Automated: Sketch {
    @Param(20...300) var radius = 40.0
    @Param(x: 0...1080, y: 0...1080) var anchor = Vector2(300, 400)
    @Param var tint = Color.coral
    @Param var filled = true

    /// One pass of the piece, in seconds.
    static let pass = 6.0

    override func setup() {
        automate($radius) { track in
            track.key(at: 0, 40, curve: .easeInOut)
            track.key(at: 2, 260, curve: .easeInOut)
            track.key(at: 4.5, 90, curve: .bezier(x1: 0.85, y1: 0, x2: 0.15, y2: 1))
            track.key(at: Self.pass, 40)
        }
        automate($anchor) { track in
            track.key(at: 0, Vector2(320, 380), curve: .easeOut)
            track.key(at: 2, Vector2(760, 300), curve: .easeInOut)
            track.key(at: 4.5, Vector2(540, 470), curve: .easeIn)
            track.key(at: Self.pass, Vector2(320, 380))
        }
        automate($tint) { track in
            track.key(at: 0, .coral, curve: .linear)
            track.key(at: 2, Color(hex: 0x2E6BE6), curve: .linear)
            track.key(at: 4.5, Color(hex: 0x18A56A), curve: .linear)
            track.key(at: Self.pass, .coral)
        }
        // A switch holds what it was given until the next key takes over.
        automate($filled) { track in
            track.hold(at: 0, true)
            track.hold(at: 2, false)
            track.hold(at: 4.5, true)
        }
        automation?.length = Self.pass
        automation?.loops = true
    }

    override func draw() {
        background(.white)

        if filled {
            noStroke()
            fill(tint)
        } else {
            noFill()
            stroke(tint)
            strokeWeight(7 * scale)
        }
        drawCircle(center: anchor, radius: radius)

        drawLanes(at: automation?.position(at: time) ?? 0)
    }

    // MARK: The lanes

    private static let left = 140.0
    private static let laneHeight = 78.0
    private static let gap = 30.0

    /// Draw each track as the curve it holds, with a playhead at `position`.
    private func drawLanes(at position: Double) {
        let right = width - Self.left
        func x(of moment: Double) -> Double {
            lerp(Self.left, right, moment / Self.pass)
        }

        var top = 660.0
        drawNumberLane("radius", top: top, x: x)
        label("radius", at: top)
        top += Self.laneHeight + Self.gap
        drawPointLane("anchor", top: top, x: x)
        label("anchor", at: top)
        top += Self.laneHeight + Self.gap
        drawColorLane("tint", top: top, x: x)
        label("tint", at: top)
        top += Self.laneHeight + Self.gap
        drawSwitchLane("filled", top: top, x: x)
        label("filled", at: top)

        // The playhead, across every lane.
        stroke(Color(white: 0.2))
        strokeWeight(2 * scale)
        let head = x(of: position)
        drawLine(head, 652, head, top + Self.laneHeight + 8)
    }

    /// A `Double` track: the curve itself, sampled across the lane.
    private func drawNumberLane(_ name: String, top: Double, x: (Double) -> Double) {
        guard let track = automation?.track(named: name) else { return }
        drawCurve(of: track, top: top, x: x, shade: 0.35) { value in
            guard case .number(let v) = value else { return nil }
            return v
        }
        frame(top: top)
        keyTicks(of: track, top: top, x: x)
    }

    /// A `Vector2` track: both components, the y one paler. Each rides its own
    /// span, so a component that barely moves still reads.
    private func drawPointLane(_ name: String, top: Double, x: (Double) -> Double) {
        guard let track = automation?.track(named: name) else { return }
        drawCurve(of: track, top: top, x: x, shade: 0.35) { value in
            guard case .vector(let vx, _) = value else { return nil }
            return vx
        }
        drawCurve(of: track, top: top, x: x, shade: 0.7) { value in
            guard case .vector(_, let vy) = value else { return nil }
            return vy
        }
        frame(top: top)
        keyTicks(of: track, top: top, x: x)
    }

    /// Plot one number read out of a track, over the span that number covers,
    /// so every lane fills whatever the values happen to be.
    private func drawCurve(of track: Automation.Track, top: Double,
                           x: (Double) -> Double, shade: Double,
                           number: (ParamStored) -> Double?) {
        var samples: [(moment: Double, value: Double)] = []
        for step in 0...180 {
            let moment = Self.pass * Double(step) / 180
            guard let value = track.value(at: moment), let number = number(value) else { continue }
            samples.append((moment, number))
        }
        guard let low = samples.map(\.value).min(), let high = samples.map(\.value).max() else { return }
        let span = max(high - low, 1e-6)
        let inset = Self.laneHeight * 0.12
        let points = samples.map { sample in
            Vector2(x(sample.moment),
                    top + inset + (Self.laneHeight - 2 * inset) * (1 - (sample.value - low) / span))
        }
        noFill()
        stroke(Color(white: shade))
        strokeWeight(2.5 * scale)
        drawPolyline(points)
    }

    /// A `Color` track: the fade itself, a bar at a time.
    private func drawColorLane(_ name: String, top: Double, x: (Double) -> Double) {
        guard let track = automation?.track(named: name) else { return }
        noStroke()
        for step in 0..<180 {
            let moment = Self.pass * Double(step) / 180
            guard case .color(let r, let g, let b, let a)? = track.value(at: moment) else { continue }
            fill(Color(red: r, green: g, blue: b, alpha: a))
            drawRect(corner: Vector2(x(moment), top),
                     width: x(Self.pass / 180) - Self.left + 1, height: Self.laneHeight)
        }
        frame(top: top)
        keyTicks(of: track, top: top, x: x)
    }

    /// A `Bool` track: on where it is on, and nothing in between.
    private func drawSwitchLane(_ name: String, top: Double, x: (Double) -> Double) {
        guard let track = automation?.track(named: name) else { return }
        noStroke()
        fill(Color(white: 0.78))
        for step in 0..<180 {
            let moment = Self.pass * Double(step) / 180
            guard case .boolean(true)? = track.value(at: moment) else { continue }
            drawRect(corner: Vector2(x(moment), top),
                     width: x(Self.pass / 180) - Self.left + 1, height: Self.laneHeight)
        }
        frame(top: top)
        keyTicks(of: track, top: top, x: x)
    }

    /// The lane's outline.
    private func frame(top: Double) {
        noFill()
        stroke(Color(white: 0.86))
        strokeWeight(1.5 * scale)
        drawRect(corner: Vector2(Self.left, top), width: width - 2 * Self.left, height: Self.laneHeight)
    }

    /// A mark under every key, so the shape of the curve reads against the
    /// moments it was given.
    private func keyTicks(of track: Automation.Track, top: Double, x: (Double) -> Double) {
        noStroke()
        fill(Color(white: 0.55))
        for key in track.keys {
            drawCircle(x(key.time), top + Self.laneHeight + 9, 3.5 * scale)
        }
    }

    private func label(_ name: String, at top: Double) {
        noStroke()
        fill(Color(white: 0.5))
        textSize(20 * scale)
        textAlign(.right, .middle)
        drawText(name, Self.left - 14, top + Self.laneHeight / 2)
    }
}
