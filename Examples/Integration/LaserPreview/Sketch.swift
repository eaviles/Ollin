import Ollin
import OllinLaser

/// The laser's own view of a drawing: not the picture, but the path the beam
/// takes to make it.
///
/// The sketch builds a `LaserFrame` from a few shapes, optimizes it, and draws
/// the resulting point stream: lit runs in their colors, the dark travel
/// between shapes as faint lines, and, when you ask for them, the beam's own
/// footsteps as dots. Turn the knobs and watch the cost of a picture: finer
/// spacing crowds the dots and drops the refresh rate, sharper corners cost
/// points to hold, and reordering the shapes cuts the travel that buys nothing.
///
/// It runs with no hardware. To send the same frame to a real projector, add a
/// DAC and arm it:
///
/// ```swift
/// let laser = LaserProjector(etherDream: "192.168.1.50")
/// // in setup(): laser.connect()
/// // when you mean it: laser.arm()
/// ```
@main
final class LaserPreview: Sketch {

    let laser = LaserProjector()

    @Param(0.005 ... 0.08, icon: "ruler") var spacing = 0.025
    @Param(0 ... 12, icon: "arrow.turn.up.right") var cornerDwell = 3
    @Param(0 ... 12, icon: "moon") var blankingDwell = 4
    @Param(5_000 ... 40_000, icon: "metronome") var pointRate = 20_000
    @Param(icon: "arrow.triangle.swap") var shortestRoute = true
    @Param(icon: "circle.dotted") var showPoints = true
    @Param(icon: "line.diagonal") var showTravel = true

    override func draw() {
        background(Color(white: 0.04))

        laser.optimizer.spacing = spacing
        laser.optimizer.cornerDwell = cornerDwell
        laser.optimizer.blankingDwell = blankingDwell
        laser.optimizer.pointsPerSecond = pointRate
        laser.optimizer.reordersPaths = shortestRoute

        laser.send(artwork())
        drawLaserPreview(laser.stream, showsTravel: showTravel, showsPoints: showPoints,
                         pointRadius: 2.5 * scale)
        drawReadout()
    }

    /// A few shapes with something to teach the optimizer: a turning star (six
    /// sharp corners), a ring (a curve, so a steady arc of points), and two
    /// short strokes far apart (the dark travel between shapes).
    func artwork() -> LaserFrame {
        var frame = LaserFrame(canvas: bounds)
        let middle = Vector2(width / 2, height / 2)

        var star: [Vector2] = []
        for i in 0..<12 {
            let angle = Double(i) / 12 * 2 * .pi + time * 0.3
            let radius = (i % 2 == 0 ? 0.26 : 0.11) * width
            star.append(middle + Vector2(cos(angle), sin(angle)) * radius)
        }
        frame.add(star, color: .cyan, closed: true)

        let ring = (0..<64).map { i -> Vector2 in
            let angle = Double(i) / 64 * 2 * .pi
            return middle + Vector2(cos(angle), sin(angle)) * (0.38 * width)
        }
        frame.add(ring, colors: ring.indices.map {
            Color(hue: Double($0) / Double(ring.count), saturation: 0.9, brightness: 1)
        }, closed: true)

        let swing = sin(time * 0.7) * 0.06 * width
        frame.addLine(from: Vector2(width * 0.12, height * 0.12 + swing),
                      to: Vector2(width * 0.26, height * 0.12 - swing),
                      color: Color(red: 1, green: 0.62, blue: 0.15))
        frame.addLine(from: Vector2(width * 0.74, height * 0.88 - swing),
                      to: Vector2(width * 0.88, height * 0.88 + swing),
                      color: Color(red: 1, green: 0.62, blue: 0.15))
        return frame
    }

    /// What the frame costs, in the projector's own terms.
    func drawReadout() {
        guard let stream = laser.stream else { return }
        withState {
            noStroke()
            textSize(20 * scale)
            fill(Color(white: 0.75))
            let lines = [
                "\(stream.points.count) points a frame, \(stream.pointBudget) in the budget",
                String(format: "%.0f frames a second at %d points a second",
                       stream.refreshRate, stream.pointsPerSecond),
                String(format: "drawn %.2f, travelled dark %.2f",
                       stream.drawnLength, stream.travelLength)
            ]
            for (i, line) in lines.enumerated() {
                drawText(line, 30 * scale, (60 + Double(i) * 30) * scale)
            }
            // Over budget is not an error and nothing is dropped: the frame
            // plays whole and repeats more slowly, which the eye reads as
            // flicker. Say so rather than hiding it.
            if stream.isOverBudget {
                fill(Color(red: 1, green: 0.55, blue: 0.2))
                drawText("over budget: this frame will flicker", 30 * scale, 150 * scale)
            }
            fill(laser.isArmed ? Color(red: 1, green: 0.3, blue: 0.25) : Color(white: 0.45))
            drawText(laser.isArmed ? "armed" : "not armed: nothing is going out",
                     30 * scale, height - 40 * scale)
        }
    }
}
