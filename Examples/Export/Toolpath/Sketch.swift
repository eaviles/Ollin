import Ollin

/// Toolpath: watch the machine's route before anything moves. The sketch
/// composes its line work as plain contours, plans them with
/// `GCode.toolpath(_:in:)`, and draws the plan itself: every path in plot
/// order, the pen-up travels between them, and a pen that walks the route at
/// machine speed. The planner clips to the canvas, merges touching ends, and
/// orders the paths so the travel (the thin straight hops) stays short.
///
/// The same plan writes a program a machine runs directly:
///
/// ```sh
/// swift run Example-Export-Toolpath --export-gcode /tmp/plot.gcode
/// swift run Example-Export-Toolpath --export-gcode /tmp/cut.gcode --gcode-machine laser
/// ```
@main
final class Toolpath_Example: Sketch {
    private let ink = Color(red: 0.1, green: 0.12, blue: 0.42)
    private let settings = GCode(.plotter(), width: 150)

    /// One leg of the route: a straight hop (pen up) or one path (pen down).
    private enum Leg {
        case travel(from: Vector2, to: Vector2)
        case draw([Vector2])
    }
    private var legs: [Leg] = []
    private var legLengths: [Double] = []      // canvas units
    private var totalLength = 0.0
    private var plan: Toolpath?

    override func setup() {
        let canvas = Rectangle(x: 0, y: 0, width: width, height: height)
        let toolpath = settings.toolpath(lineWork(), in: canvas)
        plan = toolpath
        for (i, path) in toolpath.paths.enumerated() {
            let hop = toolpath.travels[i]
            legs.append(.travel(from: hop.from, to: hop.to))
            var points = path.points
            if path.isClosed { points.append(points[0]) }
            legs.append(.draw(points))
        }
        if let home = toolpath.travels.last {
            legs.append(.travel(from: home.from, to: home.to))
        }
        legLengths = legs.map { leg in
            switch leg {
            case let .travel(from, to): return from.distance(to: to) * 0.4
            case let .draw(points):     // the pen draws slower than it travels
                var length = 0.0
                for i in 0..<(points.count - 1) { length += points[i].distance(to: points[i + 1]) }
                return length
            }
        }
        totalLength = legLengths.reduce(0, +)
    }

    override func draw() {
        background(Color(white: 0.97))
        guard let plan else { return }

        // A vector export gets the bare line work: the machine plots the
        // composition, never the preview chrome around it.
        if isVectorExporting {
            noFill()
            stroke(ink)
            strokeWeight(2)
            for path in plan.paths { drawShape(Shape(contours: [path], winding: .evenOdd)) }
            return
        }

        // Everything still to come, faint; the route already run, in ink.
        noFill()
        stroke(Color(white: 0.8))
        strokeWeight(1.5)
        for path in plan.paths { drawShape(Shape(contours: [path], winding: .evenOdd)) }

        var remaining = (time * 220).truncatingRemainder(dividingBy: totalLength + 200)
        var pen: Vector2?
        stroke(ink)
        for (i, leg) in legs.enumerated() {
            let length = legLengths[i]
            let fraction = min(max(remaining / max(length, 1e-9), 0), 1)
            switch leg {
            case let .travel(from, to):
                stroke(Color(red: 0.8, green: 0.45, blue: 0.2, alpha: 0.5))
                strokeWeight(1)
                if fraction > 0 { drawLine(from, from + (to - from) * fraction) }
                if fraction < 1 { pen = pen ?? from + (to - from) * fraction }
            case let .draw(points):
                stroke(ink)
                strokeWeight(2.5)
                var walked = 0.0
                for j in 0..<(points.count - 1) {
                    let a = points[j], b = points[j + 1]
                    let segment = a.distance(to: b)
                    let left = fraction * length - walked
                    if left <= 0 { break }
                    if left >= segment {
                        drawLine(a, b)
                    } else {
                        drawLine(a, a + (b - a) * (left / segment))
                    }
                    walked += segment
                }
                if fraction < 1, let last = partialPoint(points, at: fraction * length) {
                    pen = pen ?? last
                }
            }
            remaining -= length
            if remaining <= 0 { break }
        }

        if let pen {
            noStroke()
            fill(Color(red: 0.8, green: 0.45, blue: 0.2))
            drawCircle(center: pen, radius: 7)
        }

        caption(String(format: "draw %.0f mm   travel %.0f mm   %d paths",
                       plan.drawnLength, plan.travelLength, plan.paths.count),
                at: Vector2(width / 2, height - 36))
    }

    /// The point `distance` along a polyline, for placing the pen mid-stroke.
    private func partialPoint(_ points: [Vector2], at distance: Double) -> Vector2? {
        var walked = 0.0
        for j in 0..<(points.count - 1) {
            let segment = points[j].distance(to: points[j + 1])
            if walked + segment >= distance, segment > 0 {
                return points[j] + (points[j + 1] - points[j]) * ((distance - walked) / segment)
            }
            walked += segment
        }
        return points.last
    }

    private func caption(_ text: String, at p: Vector2) {
        noStroke(); fill(Color(white: 0.45))
        textFont(.system); textSize(22); textAlign(.center, .middle)
        drawText(text, at: p)
    }

    // MARK: - The composition, as bare line work

    /// Rings, rays, a wave, and a hatched star, deliberately emitted in a
    /// scrambled order so the planner has travel to save.
    private func lineWork() -> [Contour] {
        let center = Vector2(width / 2, height * 0.42)
        var work: [Contour] = []

        // Rays, alternating sides so the drawn order ping-pongs.
        for i in 0..<24 {
            let slot = i % 2 == 0 ? i / 2 : 23 - i / 2
            let a = Double(slot) / 24 * 2 * .pi
            let direction = Vector2(angle: a)
            work.append(Contour([center + direction * (shortSide * 0.17),
                                 center + direction * (shortSide * 0.26)], closed: false))
        }

        // Rings around them.
        for radius in [0.12, 0.145, 0.28] {
            let n = 96
            work.append(Contour((0..<n).map { k in
                center + Vector2(angle: 2 * .pi * Double(k) / Double(n)) * (shortSide * radius)
            }, closed: true))
        }

        // A wave across the lower third, drawn as many short pieces whose ends
        // touch: the planner's merge welds them back into one stroke.
        let waveY = height * 0.8
        for i in 0..<40 {
            let x0 = width * Double(i) / 40, x1 = width * Double(i + 1) / 40
            func wave(_ x: Double) -> Vector2 {
                Vector2(x, waveY + sin(x / width * 6 * .pi) * shortSide * 0.04)
            }
            work.append(Contour([wave(x0), wave(x1)], closed: false))
        }

        // A hatched star: solid tone a pen can only shade with lines.
        let starCenter = Vector2(width * 0.82, height * 0.72)
        let star = Shape((0..<10).map { k -> Vector2 in
            let radius = k % 2 == 0 ? shortSide * 0.1 : shortSide * 0.045
            return starCenter + Vector2(angle: Double(k) / 10 * 2 * .pi - .pi / 2) * radius
        })
        work.append(contentsOf: star.contours)
        for line in Hatching(spacing: 6).lines(filling: star) {
            work.append(Contour(line, closed: false))
        }
        return work
    }
}
