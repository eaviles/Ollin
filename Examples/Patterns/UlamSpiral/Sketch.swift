import Ollin

/// The primes, written in a square spiral.
///
/// Count outward from the middle in a square spiral, one whole number per cell,
/// and mark the primes. The marks should look like nothing. They do not: they
/// gather along diagonal lines, which is what Stanisław Ulam noticed on a notepad
/// during a dull talk in 1963.
///
/// The lines are not a mystery. A diagonal of the spiral is the run of values of
/// a quadratic, so a crowded diagonal is a quadratic that keeps returning primes.
/// What the picture does is make them visible.
///
/// Counting from somewhere other than 1 moves every number, so the diagonals
/// break up and re-form. Here `start` climbs slowly over the loop, which is a way
/// of watching the same fact from several places. Hold the mouse to draw the walk
/// itself, so the order the numbers were written in stops being a guess.
@main
final class UlamSpiral_Example: Sketch {
    override var loopDuration: Double? { 20 }

    private let size = 101

    override func draw() {
        background(Color(hex: 0x0C0F16))

        // The number in the middle climbs by a whole ring's worth over the loop.
        let start = 1 + Int(loopProgress(over: 20) * 400)
        let spiral = ulamSpiral(in: bounds.inset(by: 70), size: size, start: start)

        if mouseIsPressed {
            noFill()
            stroke(Color(hex: 0x2C3A52))
            strokeWeight(2)
            drawPolyline(spiral.path.points)
        }

        noStroke()
        let radius = spiral.grid.cellWidth * 0.38
        for point in spiral.primePoints {
            // Warmer toward the middle, so the eye finds the center of the count.
            let reach = (point - bounds.center).length / (Double(size) * spiral.grid.cellWidth / 2)
            fill(Color.mix(Color(hex: 0xFFD166), Color(hex: 0x6FB1FF), t: clamp(reach, 0, 1)))
            drawCircle(center: point, radius: radius)
        }

        drawCaption("the primes from \(start) to \(start + size * size - 1), written in a square spiral; hold the mouse for the walk")
    }
}
