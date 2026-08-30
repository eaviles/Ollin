import Ollin

/// An Apollonian gasket: three circles kiss inside a rim, and every three-way
/// gap is filled by the one circle that exactly touches all three, forever
/// (here, down to a few pixels). The foam is a closed form with no randomness,
/// so it's built once; what moves is the color, sweeping through the
/// generations so the filling order becomes visible.
@main
final class ApollonianFoam: Sketch {
    override var loopDuration: Double? { 8 }

    private var foam: [Circle] = []

    override func setup() {
        foam = apollonianGasket(in: Circle(center: bounds.center, radius: width * 0.44),
                                minRadius: 2.5 * scale)
    }

    override func draw() {
        background(Color(hex: 0x0E1116))

        noFill()
        stroke(Color(hex: 0x2A3140))
        strokeWeight(2 * scale)
        drawCircle(center: bounds.center, radius: width * 0.44)

        let phase = loopProgress(over: 8)
        noStroke()
        for (i, circle) in foam.enumerated() {
            // Age runs with the generation order; the wave loops through it.
            let age = Double(i) / Double(foam.count)
            let wave = pingPong(over: 1, phase: phase - age)
            fill(Color.mix(Color(hex: 0x1D5C63), Color(hex: 0xF9DC5C), wave * wave * wave)
                .withAlpha(0.92))
            drawCircle(circle)
        }
    }
}
