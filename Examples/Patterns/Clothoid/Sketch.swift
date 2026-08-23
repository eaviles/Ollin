import Ollin

/// **Clothoid**: the curve whose bend grows at a steady rate along its own
/// length. It is the piece that joins a straight run to a turn with no kink in
/// the bend, which is why roads, railways, and roller coasters are laid out
/// with it.
///
/// The route here is a plain polyline with every corner replaced by an
/// easement in, an arc, and an easement back out. The comb along the outside
/// is the bend itself, drawn as a distance off the route, so a still picture
/// shows the thing the eye cannot otherwise check: on a clothoid corner the
/// comb ramps up and back down, and on a plain arc it steps.
///
/// Try it: pull `easement` down to zero. The corners become plain arcs, the
/// comb turns into a square step, and the caption jumps from a bend that never
/// moves much to one that changes by a whole turn's worth in one step. That is
/// the wheel being yanked, and it is what the curve exists to avoid.
@main
final class ClothoidSketch: Sketch {
    @Param(20 ... 220, icon: "circle.dashed") var radius = 120.0
    @Param(0 ... 220, icon: "point.topleft.down.to.point.bottomright.curvepath") var easement = 90.0
    @Param(icon: "waveform.path") var showTheBend = true
    @Param(icon: "scribble") var showThePlan = true

    private let paper = Color(hex: 0x11131A)
    private let chalk = Color(hex: 0xF2ECDD)
    private let warm = Color(hex: 0xE0724A)

    private let plan = [
        Vector2(230, 300), Vector2(560, 190), Vector2(870, 320),
        Vector2(830, 700), Vector2(560, 620), Vector2(250, 800),
    ]

    override func draw() {
        background(paper)

        let route = clothoidCorners(plan, radius: radius, easement: max(easement, 0.01),
                                    closed: true)
        let total = route.length

        if showThePlan {
            stroke(chalk.withAlpha(0.16))
            strokeWeight(1)
            drawPolyline(plan, closed: true)
            noStroke()
            fill(chalk.withAlpha(0.25))
            for corner in plan { drawCircle(center: corner, radius: 4) }
        }

        if showTheBend { drawTheBend(route, total: total) }

        noFill()
        stroke(chalk)
        strokeWeight(width * 0.006)
        strokeCap(.round)
        drawPolyline(route.contour(spacing: 1.5, closed: true).points, closed: true)

        drive(route, total: total)
        caption(route, total: total)
    }

    /// The bend, drawn as a distance off the route. A comb reads better than a
    /// second line, because it shows where each reading was taken.
    private func drawTheBend(_ route: [Clothoid], total: Double) {
        let scale = radius * 26
        let steps = 520
        var ribbon = [Vector2]()
        for i in 0...steps {
            let s = total * Double(i) / Double(steps)
            guard let here = route.point(at: s),
                  let heading = route.heading(at: s),
                  let bend = route.curvature(at: s) else { continue }
            let out = Vector2(angle: heading).perpendicular * (bend * scale)
            ribbon.append(here + out)
            if i % 6 == 0 {
                stroke(warm.withAlpha(0.30))
                strokeWeight(1)
                drawLine(here, here + out)
            }
        }
        stroke(warm.withAlpha(0.85))
        strokeWeight(1.6)
        drawPolyline(ribbon, closed: true)
    }

    /// Something driving the route at a steady speed, turned the way the route
    /// turns, with a wheel that reads the bend under it.
    private func drive(_ route: [Clothoid], total: Double) {
        let along = (time * 260).truncatingRemainder(dividingBy: total)
        guard let here = route.point(at: along),
              let heading = route.heading(at: along),
              let bend = route.curvature(at: along) else { return }

        withState {
            translate(here)
            rotate(heading)
            noStroke()
            fill(warm)
            drawTriangle(Vector2(16, 0), Vector2(-10, 9), Vector2(-10, -9))
        }

        // The wheel, off in the corner: how far it is turned is the bend under
        // the driver, and full lock is the tightest the route ever gets.
        let wheel = Vector2(width - 120, height - 120)
        noFill()
        stroke(chalk.withAlpha(0.30))
        strokeWeight(2)
        drawCircle(center: wheel, radius: 46)
        stroke(warm)
        strokeWeight(5)
        strokeCap(.round)
        let lock = bend * radius * 2.2
        drawLine(wheel - Vector2(angle: lock, length: 40), wheel + Vector2(angle: lock, length: 40))
    }

    private func caption(_ route: [Clothoid], total: Double) {
        var worst = 0.0
        let steps = 2000
        for i in 1...steps {
            let a = route.curvature(at: total * Double(i - 1) / Double(steps)) ?? 0
            let b = route.curvature(at: total * Double(i) / Double(steps)) ?? 0
            worst = max(worst, abs(b - a))
        }
        let tightest = 1 / radius
        let share = worst / tightest
        noStroke()
        fill(chalk.withAlpha(0.75))
        textFont(.system)
        textSize(width * 0.021)
        textAlign(.center, .bottom)
        drawText("easement \(Int(easement.rounded())): the bend moves at most "
                 + "\(Int((share * 100).rounded()))% of full lock in a step",
                 width / 2, height - width * 0.045)
    }
}
