import Ollin

/// **Pursuit**: put a runner on each corner of a polygon, tell each one to run
/// at the next, and start them together. Nobody travels in a straight line,
/// because every target is moving too, and the paths they leave are
/// logarithmic spirals that meet in the middle.
///
/// The faint web is the chase itself, kept every few steps: each line joins a
/// runner to the one it is running at. The bright lines are the paths.
///
/// The caption is the reason this figure is worth knowing. The distance each
/// runner covers is exactly `radius / sin(chasing * pi / sides)`, worked out
/// centuries before anyone could plot it, and the drawing lands on it. It
/// lands a hair over, and that is honest: a runner covering a fixed distance
/// per step overshoots the turn a little every time. A smaller `stepSize`
/// draws a finer curve and a closer number.
///
/// Try it: `chasing` is how many places around the ring the target sits. At 1
/// it is the classic figure. At half the number of sides everybody runs
/// straight at whoever is opposite, and the spiral disappears.
@main
final class PursuitSketch: Sketch {
    @Param(3 ... 12, icon: "hexagon") var sides = 6.0
    @Param(1 ... 6, icon: "arrow.triangle.turn.up.right.circle") var chasing = 1.0
    @Param(icon: "scribble") var showTheChase = true

    private let paper = Color(hex: 0x11131A)
    private let chalk = Color(hex: 0xF2ECDD)
    private let warm = Color(hex: 0xE0724A)

    private var chase = Pursuit.ring(sides: 3, center: .zero, radius: 1)
    private var asked = (sides: 0, chasing: 0)
    private var ringRadius = 0.0
    private var restingFrames = 0

    override func draw() {
        background(paper)
        if asked != (Int(sides), Int(chasing)) { start() }

        if !chase.isFinished {
            chase.step(20)
        } else if restingFrames > 0 {
            restingFrames -= 1
        } else {
            start()
        }

        if showTheChase {
            stroke(chalk.withAlpha(0.14))
            strokeWeight(1)
            for line in chase.web { drawPolyline(line.points) }
            stroke(warm.withAlpha(0.5))
            for line in chase.links { drawPolyline(line.points) }
        }

        noFill()
        strokeCap(.round)
        strokeWeight(width * 0.004)
        for (index, trail) in chase.trails.enumerated() {
            let along = Double(index) / Double(max(chase.runners.count - 1, 1))
            stroke(Color.mix(chalk, warm, along))
            drawPolyline(trail.points)
        }

        noStroke()
        fill(chalk)
        for runner in chase.runners {
            drawCircle(center: runner.position, radius: width * 0.006)
        }

        caption()
    }

    private func start() {
        let count = Int(sides)
        let ahead = min(Int(chasing), count - 1)
        ringRadius = width * 0.40
        chase = Pursuit.ring(sides: count, center: center, radius: ringRadius,
                             chasing: ahead, turn: -.pi / 2,
                             stepSize: ringRadius / 800)
        chase.recordEvery = 26
        asked = (count, Int(chasing))
        restingFrames = 90
    }

    private func caption() {
        let ahead = chase.runners[0].chases ?? 1
        let law = ringRadius / sin(Double(ahead) * .pi / Double(chase.runners.count))
        let ran = chase.runners[0].distanceTraveled
        fill(chalk.withAlpha(0.75))
        textFont(.system); textSize(width * 0.021); textAlign(.center, .bottom)
        drawText("\(chase.runners.count) runners, each chasing "
                 + (ahead == 1 ? "the next" : "\(ahead) along")
                 + ": ran \(Int(ran.rounded())) of \(Int(law.rounded()))",
                 width / 2, height - width * 0.045)
    }
}
