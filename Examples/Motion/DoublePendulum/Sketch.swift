import Ollin

/// The butterfly effect, drawn: twenty-four double pendulums released from
/// starts a ten-thousandth of a radian apart. For the first seconds they
/// swing as one line; then the differences compound and the fan tears open
/// into twenty-four unrelated dances. Nothing here is random. Each pendulum
/// is exact physics from a fixed start, and restarting replays the same
/// divergence every time; chaos is not noise, it is sensitivity.
///
/// Each second bob leaves a fading trail (the first bob's motion stays tame;
/// all the drama lives at the end of the second arm). Hue runs across the
/// fan, so once the spread begins you can watch neighbors peel away from
/// each other.
@main
final class DoublePendulumFan: Sketch {
    private var pendulums: [DoublePendulum] = []
    private var trails: [[Vector2]] = []
    private let trailLength = 110

    override func setup() {
        pendulums = (0 ..< 24).map { i in
            DoublePendulum(length1: 230, length2: 185,
                           angle1: 2.05 + Double(i) * 1e-4, angle2: 2.6)
        }
        trails = pendulums.map { _ in [] }
    }

    override func draw() {
        background(Color(hex: 0x0F1117))
        let pivot = Vector2(width / 2, height * 0.38)

        for (i, pendulum) in pendulums.enumerated() {
            pendulum.advance()
            trails[i].append(pivot + pendulum.bob2)
            if trails[i].count > trailLength { trails[i].removeFirst() }
        }

        strokeCap(.round)
        for (i, pendulum) in pendulums.enumerated() {
            let hue = Double(i) / Double(pendulums.count - 1)
            let color = Color(hue: 0.52 + hue * 0.42, saturation: 0.72, brightness: 0.95)

            // The fading trail of the second bob.
            let trail = trails[i]
            for k in 1 ..< max(trail.count, 1) {
                let age = Double(k) / Double(trail.count)
                stroke(color.withAlpha(age * age * 0.5))
                strokeWeight(1.5 + age * 1.5)
                drawLine(trail[k - 1], trail[k])
            }

            // The arms, whisper-faint so the trails carry the image.
            stroke(color.withAlpha(0.16))
            strokeWeight(1.5)
            drawLine(pivot, pivot + pendulum.bob1)
            drawLine(pivot + pendulum.bob1, pivot + pendulum.bob2)
            noStroke()
            fill(color.withAlpha(0.9))
            drawCircle(center: pivot + pendulum.bob2, radius: 4)
        }

        noStroke()
        fill(Color(hex: 0x8A93A6))
        drawCircle(center: pivot, radius: 5)

        let seconds = Int(Double(frameCount) / 60)
        drawCaption("24 starts, 0.0001 radians apart. \(seconds)s in")
    }
}
