import Ollin

/// **Fitting**: two ways of getting from a handful of numbers to a whole picture.
///
/// `RadialBasis` goes outward. You know a value at a few scattered places and want one
/// everywhere, so every known point contributes a bump and the bumps are weighted to pass
/// exactly through the values you gave. `Fit.minimize` goes inward: you have a few knobs
/// and a way of saying how wrong a setting is, and it walks them downhill.
///
/// - **field**: a color at six drifting points, read back over the whole canvas. Nothing
///   here is a gradient. Every pixel is a weighted sum of the six, and the six are the only
///   thing that moves.
/// - **warp**: the same fit carrying `Vector2`s instead of colors. Six places are pinned to
///   where they should move to, and the grid between them follows.
/// - **fit**: marks scattered around a circle that is never told to the sketch. Three
///   numbers get walked downhill every frame until they describe the circle the marks came
///   from, and the ring is drawn from those three.
///
/// Try it: pull `smoothing` up in the `field` reading and watch the field stop passing
/// through its own points, or pull `wobble` up in `fit` until the marks stop being a circle
/// at all and watch the answer get less sure of itself.
@main
final class Scattered_Example: Sketch {

    enum Reading: String, CaseIterable, ParamOption { case field, warp, fit }

    @Param(style: .segmented, icon: "circle.grid.cross") var reading: Reading = .field
    @Param(0 ... 0.6, icon: "wind") var smoothing = 0.0
    @Param(6 ... 40, icon: "square.grid.3x3") var step = 12.0
    @Param(0 ... 90, icon: "waveform") var wobble = 26.0

    let ground = Color(hex: 0x0E1216)
    let inks = [Color(hex: 0xE8734A), Color(hex: 0x49B0A5), Color(hex: 0xE0C25C),
                Color(hex: 0xC85A7C), Color(hex: 0x6E8FD4), Color(hex: 0x8FC46B)]

    override func draw() {
        background(ground)
        switch reading {
        case .field: drawColorField()
        case .warp: drawWarpedGrid()
        case .fit: drawRecoveredCircle()
        }
    }

    /// Six drifting points, each holding a color, read back over the whole canvas.
    private func drawColorField() {
        let anchors = drifting()
        guard let field = RadialBasis(points: anchors, values: inks, smoothing: smoothing) else {
            return
        }
        noStroke()
        let side = step
        for y in stride(from: 0.0, to: height, by: side) {
            for x in stride(from: 0.0, to: width, by: side) {
                fill(field.value(at: Vector2(x + side / 2, y + side / 2)))
                drawRect(x, y, side + 1, side + 1)
            }
        }
        // The points themselves, ringed rather than filled, so it is clear how few of them
        // there are. What shows inside each ring is the field's own color, and it matches
        // the point's exactly, because passing through the values it was given is what
        // makes this an interpolation rather than a blur of them.
        noFill()
        stroke(Color(hex: 0x101820, alpha: 0.85))
        strokeWeight(4)
        for anchor in anchors { drawCircle(center: anchor, radius: 12) }
        noStroke()
    }

    /// The same six points carrying displacements instead of colors, which makes the fit a
    /// warp: pin a few places to where they should go, and everything between them follows.
    private func drawWarpedGrid() {
        let anchors = drifting()
        let pulls = anchors.enumerated().map { i, a -> Vector2 in
            let phase = time * 0.5 + Double(i) * 1.9
            return a + Vector2(cos(phase), sin(phase * 1.3)) * 130
        }
        guard let warp = RadialBasis(points: anchors, values: pulls, smoothing: smoothing) else {
            return
        }
        noFill()
        stroke(Color(hex: 0x9FB3C8, alpha: 0.75))
        strokeWeight(1.5)
        let side = max(step * 2.5, 24)
        // Each grid line is drawn through the warp point by point, so a straight line comes
        // out bent by however the six pins are pulling where it passes.
        for x in stride(from: 0.0, through: width, by: side) {
            drawPolyline(stride(from: 0.0, through: height, by: 10).map {
                warp.value(at: Vector2(x, $0))
            })
        }
        for y in stride(from: 0.0, through: height, by: side) {
            drawPolyline(stride(from: 0.0, through: width, by: 10).map {
                warp.value(at: Vector2($0, y))
            })
        }
        noStroke()
        for (anchor, pull) in zip(anchors, pulls) {
            stroke(Color(hex: 0xE8734A, alpha: 0.6))
            strokeWeight(2)
            drawLine(anchor, pull)
            noStroke()
            fill(Color(hex: 0xE8734A))
            drawCircle(center: pull, radius: 7)
        }
    }

    /// Marks scattered around a circle the sketch is never told, and the three numbers a
    /// downhill walk recovers from them.
    private func drawRecoveredCircle() {
        let truth = Vector2(width * 0.5 + cos(time * 0.4) * 120,
                            height * 0.5 + sin(time * 0.31) * 90)
        let radius = 250 + sin(time * 0.6) * 60
        let marks = (0 ..< 120).map { i -> Vector2 in
            let a = Double(i) / 120 * .tau
            // A fixed pattern of noise rather than a random one, so the marks wander with
            // the shape instead of flickering.
            let off = noise(cos(a) * 2 + 11, sin(a) * 2 + 7, time * 0.2) - 0.5
            return truth + Vector2(angle: a) * (radius + off * 2 * wobble)
        }

        noStroke()
        fill(Color(hex: 0x9FB3C8, alpha: 0.8))
        for mark in marks { drawCircle(center: mark, radius: 3.5) }

        // Three knobs: where the middle is, and how far out the ring sits. The cost is how
        // badly the marks miss a ring with those three numbers.
        let found = Fit.minimize(from: [width / 2, height / 2, 200], steps: 260, rate: 6) { p in
            let center = Vector2(p[0], p[1])
            return marks.reduce(0.0) { total, mark in
                let off = center.distance(to: mark) - p[2]
                return total + off * off
            }
        }
        noFill()
        stroke(Color(hex: 0xE0C25C))
        strokeWeight(3)
        drawCircle(found.values[0], found.values[1], found.values[2])
        noStroke()
        fill(Color(hex: 0xE0C25C))
        drawCircle(found.values[0], found.values[1], 6)
    }

    /// Six points wandering slowly, well inside the canvas.
    private func drifting() -> [Vector2] {
        (0 ..< 6).map { i in
            let phase = Double(i) * 2.4
            return Vector2(width * (0.5 + cos(time * 0.17 + phase) * 0.34),
                           height * (0.5 + sin(time * 0.23 + phase * 1.4) * 0.34))
        }
    }
}
