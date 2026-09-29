// figure: frame=0
//
// Guide payoff (Chapter 41): the contour chart, a keeper got ready to leave.
// Rings of single lines around a still center, each pushed in and out by one
// looping noise field, so neighboring rings bend together and the outer ones
// bend most. Everything is stroked and nothing is filled, so the same frame
// leaves as a poster, a loop, and a plot. The seed is fixed in setup(), the
// lap is declared, sizes are fractions of the canvas, and the sketch
// describes itself. Frame 0 is the start of the lap.
import Ollin

final class ContourChart: Sketch {
    @Param(4...40) var rings = 22
    @Param(0...0.2) var swell = 0.06
    @Param var paper = Color(hex: 0xF2EDE3)
    @Param var ink = Color(hex: 0x1D2A44)

    let lapSeconds = 8.0
    override var loopDuration: Double? { lapSeconds }

    override func setup() {
        seed(4821)          // the variation this keeper was found at
    }

    override func draw() {
        background(paper)
        noFill()
        stroke(ink)
        let unit = min(width, height)       // every size is a fraction of the canvas
        strokeWeight(unit * 0.002)

        let lap = loopProgress(over: lapSeconds)
        for k in 0..<rings {
            let depth = Double(k) / Double(rings)
            let base = unit * (0.04 + 0.36 * depth)
            let ring = (0..<240).map { j -> Vector2 in
                let angle = Double(j) / 240 * .tau
                let push = signedNoise(cos(angle) * 0.8 + depth * 1.5,
                                       sin(angle) * 0.8, loop: lap)
                let r = base + push * unit * swell * (0.3 + depth)
                return center + Vector2(cos(angle), sin(angle)) * r
            }
            drawPolyline(ring, closed: true)
        }

        describe("\(rings) contour lines around a still center, the outer ones bending most, drifting in an eight-second loop.")
    }
}
