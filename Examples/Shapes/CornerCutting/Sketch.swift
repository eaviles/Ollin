import Ollin

/// Chaikin's corner cutting live: every pass replaces each corner with two
/// points a quarter of the way along its segments, so jagged geometry relaxes
/// into a flowing curve. Top: a spiky closed burst (its raw outline ghosted
/// behind the smoothed fill). Bottom: an open zigzag ribbon, showing that
/// smoothing preserves the exact endpoints. The spikes wobble on looping
/// noise while the smoothing re-runs every frame, and the iterations parameter
/// walks from raw polygon to soft blob one halving at a time.
@main
final class CornerCutting: Sketch {
    @Param(0 ... 6, icon: "scissors") var iterations = 3.0

    let period = 9.0
    override var loopDuration: Double? { period }

    override func draw() {
        background(Color(hex: 0x12151C))
        let passes = Int(iterations)
        let phase = loopProgress(over: period)

        // A spiky burst: spokes alternating between two radii, each wobbling
        // on its own slice of looping noise.
        let spikes = 22
        let center = Vector2(width / 2, height * 0.40)
        var burst: [Vector2] = []
        for i in 0..<spikes {
            let angle = Double(i) / Double(spikes) * .tau
            let base = i % 2 == 0 ? 0.34 : 0.16
            let wobble = signedNoise(Double(i) * 0.7, loop: phase, radius: 0.6) * 0.06
            burst.append(center + Vector2(angle: angle,
                                          length: (base + wobble) * Double(shortSide)))
        }
        let raw = Contour(burst, closed: true)
        let smooth = raw.smoothed(iterations: passes)

        noFill()
        stroke(Color(white: 0.32))
        strokeWeight(1 * scale)
        drawPolyline(raw.points, closed: true)

        fill(Color(hex: 0x2EC4B6).withAlpha(0.85))
        stroke(.white)
        strokeWeight(2 * scale)
        drawShape(Shape(contours: [smooth]))

        // An open zigzag: the endpoints never move, however many passes run.
        var zigzag: [Vector2] = []
        let steps = 13
        for i in 0...steps {
            let x = map(Double(i), 0, Double(steps), width * 0.08, width * 0.92)
            let lift = i % 2 == 0 ? -0.06 : 0.06
            let wobble = signedNoise(Double(i) * 1.3 + 40, loop: phase, radius: 0.6) * 0.03
            zigzag.append(Vector2(x, height * (0.82 + lift + wobble)))
        }
        let ribbon = Contour(zigzag, closed: false)

        noFill()
        stroke(Color(white: 0.32))
        strokeWeight(1 * scale)
        drawPolyline(ribbon.points, closed: false)
        stroke(Color(hex: 0xF6511D))
        strokeWeight(3 * scale)
        drawPolyline(ribbon.smoothed(iterations: passes).points, closed: false)

        // Mark the preserved endpoints.
        noStroke()
        fill(.white)
        drawCircle(zigzag[0].x, zigzag[0].y, 5 * scale)
        drawCircle(zigzag[steps].x, zigzag[steps].y, 5 * scale)
    }
}
